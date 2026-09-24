using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.Core.Fleets;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed record CommunityCreationResult(string Status, string? Error = null, CommunityView? Organization = null)
{
    public int SchemaVersion => 1;
}

internal sealed partial class CommunityClient
{
    private sealed record CreationAttempt(string Hash, CommunityCreationResult Result);
    private readonly ConcurrentDictionary<string, CreationAttempt> _creationAttempts = new();

    internal static object CreationOptions(JsonElement body)
    {
        Validate(body);
        return new
        {
            schemaVersion = 1,
            categories = LegacyFleetTagCatalog.Categories,
            tags = LegacyFleetTagCatalog.Tags,
            maxTags = LegacyFleetTagCatalog.MaxSelection,
            timeZones = TimeZoneInfo.GetSystemTimeZones().Append(TimeZoneInfo.Local).DistinctBy(zone => zone.Id)
                .Select(zone => new { id = zone.Id, name = zone.DisplayName }).ToArray(),
            defaultTimeZoneId = TimeZoneInfo.Local.Id,
            defaultActiveFrom = "19:00", defaultActiveTo = "22:00", defaultSystem = "stanton"
        };
    }

    internal static (string RequestId, JsonElement Draft) ParseCreation(JsonElement body)
    {
        try
        {
            Validate(body, "requestId", "draft");
            var id = Text(body, "requestId", 32);
            if (id.Length != 32 || !id.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f')) throw Invalid();
            var draft = body.GetProperty("draft");
            Validate(draft, "name", "code", "description", "joinPolicy", "tagIds", "activeSystemIds",
                "activeFrom", "activeTo", "timeZoneId", "logoImageData");
            var name = Text(draft, "name", 32);
            var code = Text(draft, "code", 10);
            var from = Text(draft, "activeFrom", 5);
            var to = Text(draft, "activeTo", 5);
            var tags = CreationArray(draft, "tagIds", 5);
            var systems = CreationArray(draft, "activeSystemIds", 3);
            if (!LegacyFleetCreationRules.ValidateForm(name, code, from, to, tags.Length, systems.Length).IsValid ||
                Text(draft, "joinPolicy", 10) is not ("Open" or "Approval" or "Invite") ||
                tags.Any(id => !LegacyFleetTagCatalog.Tags.Any(tag => tag.Id == id)) ||
                systems.Any(id => id is not ("stanton" or "pyro" or "nyx"))) throw Invalid();
            Text(draft, "description", 500, multiline: true);
            var zone = Text(draft, "timeZoneId", 128);
            if (!TimeZoneInfo.GetSystemTimeZones().Any(z => z.Id == zone) && zone != TimeZoneInfo.Local.Id && zone != "UTC") throw Invalid();
            Optional(draft, "logoImageData", 700000);
            return (id, draft.Clone());
        }
        catch (Exception e) when (e is InvalidOperationException or KeyNotFoundException or FormatException or JsonException)
        { throw Invalid(); }
    }

    private static string[] CreationArray(JsonElement body, string name, int max)
    {
        var array = body.GetProperty(name);
        if (array.GetArrayLength() > max) throw Invalid();
        var result = array.EnumerateArray().Select(value => value.GetString() ?? "").ToArray();
        if (result.Any(value => value.Length > 64 || value.Any(char.IsControl)) || result.Distinct().Count() != result.Length) throw Invalid();
        return result;
    }

    internal async Task<CommunityCreationResult> CreateAsync(string bearer, JsonElement body, string scope,
        Action current, CancellationToken token)
    {
        var (id, draft) = ParseCreation(body);
        var key = scope + "\0" + id;
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(draft.GetRawText())));
        if (!await _write.WaitAsync(0, token)) return new("rejected", "busy");
        var sent = false;
        try
        {
            current();
            if (_creationAttempts.TryGetValue(key, out var prior))
                return prior.Hash == hash ? prior.Result : new("rejected", "requestChanged");
            // Never evict an uncertain request merely to make a retry possible.
            if (_creationAttempts.Count >= 256) return new("rejected", "refreshRequired");
            _creationAttempts[key] = new(hash, new("unknown", "outcomeUnknown"));
            token.ThrowIfCancellationRequested();
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/fleets/create"))
                { Content = JsonContent.Create(draft) };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            current();
            sent = true;
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            current();
            if (!response.IsSuccessStatusCode)
            {
                var result = response.StatusCode switch
                {
                    HttpStatusCode.Conflict => new CommunityCreationResult("rejected", "codeUnavailable"),
                    HttpStatusCode.NotFound or HttpStatusCode.MethodNotAllowed => new("rejected", "upgradeRequired"),
                    HttpStatusCode.Unauthorized => new("rejected", "identityUnavailable"),
                    HttpStatusCode.Forbidden => new("rejected", "notAllowed"),
                    HttpStatusCode.BadRequest => new("rejected", "invalidDraft"),
                    _ => new("unknown", "outcomeUnknown")
                };
                _creationAttempts[key] = new(hash, result);
                return result;
            }
            using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            using var buffer = new MemoryStream();
            var chunk = new byte[1024];
            int count;
            while ((count = await stream.ReadAsync(chunk, deadline.Token)) > 0)
            {
                if (buffer.Length + count > 8192) throw Invalid();
                buffer.Write(chunk, 0, count);
            }
            using var confirmation = JsonDocument.Parse(buffer.ToArray());
            var payload = confirmation.RootElement;
            var code = LegacyFleetCreationRules.NormalizeCode(Text(draft, "code", 10));
            if (payload.GetProperty("schemaVersion").GetInt32() != 1 ||
                Text(payload, "status", 16) != "created" || Text(payload, "code", 10) != code) throw Invalid();
            var reference = Guid.NewGuid().ToString("N");
            _targets[reference] = new(code, scope, DateTimeOffset.UtcNow.AddMinutes(5));
            var page = await ReadAsync(bearer, new("mine", "", null, reference), scope, deadline.Token);
            current();
            var organization = page.Items.SingleOrDefault();
            var confirmed = organization?.Relationship == "owner"
                ? new CommunityCreationResult("accepted", Organization: organization)
                : new CommunityCreationResult("unknown", "outcomeUnknown");
            _creationAttempts[key] = new(hash, confirmed);
            return confirmed;
        }
        catch (Exception e) when (e is HttpRequestException or IOException or OperationCanceledException or
            AccountBridgeHostException or StarBridge.NativeBridge.BridgeStaleGenerationException or JsonException or
            InvalidOperationException or KeyNotFoundException or FormatException)
        {
            var result = new CommunityCreationResult(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired");
            if (sent) _creationAttempts[key] = new(hash, result);
            else _creationAttempts.TryRemove(key, out _);
            return result;
        }
        finally { _write.Release(); }
    }

    // Explicit WPF S2 adapter. The production legacy contract creates through
    // the original full snapshot write; it must never be selected as an HTTP
    // failure fallback for the modern create-only endpoint.
    internal async Task<CommunityCreationResult> CreateWpfS2Async(
        string bearer,
        JsonElement body,
        string scope,
        string viewerId,
        string commander,
        Action current,
        CancellationToken token)
    {
        var (id, draft) = ParseCreation(body);
        var key = scope + "\0wpf-s2\0" + id;
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(draft.GetRawText())));
        if (!await _write.WaitAsync(0, token)) return new("rejected", "busy");
        var sent = false;
        try
        {
            current();
            if (_creationAttempts.TryGetValue(key, out var prior))
                return prior.Hash == hash ? prior.Result : new("rejected", "requestChanged");
            if (_creationAttempts.Count >= 256) return new("rejected", "refreshRequired");

            // WPF S2 owns one membership relation. Failure to prove the empty
            // state closes the write; a modern multi-membership session never
            // reaches this adapter.
            if ((await WpfS2Membership(bearer, token)).Length != 0)
            {
                var blocked = new CommunityCreationResult("rejected", "notAllowed");
                _creationAttempts[key] = new(hash, blocked);
                return blocked;
            }
            current();

            _creationAttempts[key] = new(hash, new("unknown", "outcomeUnknown"));
            token.ThrowIfCancellationRequested();
            var snapshot = BuildWpfS2CreationSnapshot(draft, commander, includeLogo: true);
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            sent = true;
            using var response = await SendWpfS2CreationAsync(bearer, snapshot, deadline.Token);
            HttpResponseMessage finalResponse = response;
            HttpResponseMessage? retryResponse = null;
            try
            {
                if (response.StatusCode == HttpStatusCode.RequestEntityTooLarge &&
                    Optional(draft, "logoImageData", 700000) is not null)
                {
                    current();
                    retryResponse = await SendWpfS2CreationAsync(
                        bearer,
                        BuildWpfS2CreationSnapshot(draft, commander, includeLogo: false),
                        deadline.Token);
                    finalResponse = retryResponse;
                }
                current();
                if (!finalResponse.IsSuccessStatusCode)
                {
                    var rejected = finalResponse.StatusCode switch
                    {
                        HttpStatusCode.Conflict => new CommunityCreationResult("rejected", "codeUnavailable"),
                        HttpStatusCode.Unauthorized => new("rejected", "identityUnavailable"),
                        HttpStatusCode.Forbidden => new("rejected", "notAllowed"),
                        HttpStatusCode.BadRequest => new("rejected", "invalidDraft"),
                        HttpStatusCode.NotFound or HttpStatusCode.MethodNotAllowed => new("rejected", "upgradeRequired"),
                        _ => new("unknown", "outcomeUnknown")
                    };
                    _creationAttempts[key] = new(hash, rejected);
                    return rejected;
                }

                using var payload = await ReadBoundedJsonAsync(finalResponse, 8 * 1024 * 1024, deadline.Token);
                if (payload.RootElement.ValueKind != JsonValueKind.Object ||
                    !Text(payload.RootElement, "code", 256).Equals(
                        LegacyFleetCreationRules.NormalizeCode(Text(draft, "code", 10)),
                        StringComparison.OrdinalIgnoreCase))
                    throw Invalid();

                var confirmed = await ReadWpfS2Async(
                    bearer,
                    new("mine", "", null, null),
                    scope,
                    viewerId,
                    deadline.Token);
                current();
                var organization = confirmed.Items.SingleOrDefault();
                var result = organization?.Relationship == "owner"
                    ? new CommunityCreationResult("accepted", Organization: organization)
                    : new CommunityCreationResult("unknown", "outcomeUnknown");
                _creationAttempts[key] = new(hash, result);
                return result;
            }
            finally
            {
                retryResponse?.Dispose();
            }
        }
        catch (Exception e) when (e is HttpRequestException or IOException or OperationCanceledException or
            AccountBridgeHostException or StarBridge.NativeBridge.BridgeStaleGenerationException or JsonException or
            InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        {
            var result = new CommunityCreationResult(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired");
            if (sent) _creationAttempts[key] = new(hash, result);
            else _creationAttempts.TryRemove(key, out _);
            return result;
        }
        finally
        {
            _write.Release();
        }
    }

    private async Task<HttpResponseMessage> SendWpfS2CreationAsync(
        string bearer,
        object snapshot,
        CancellationToken token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/fleets"))
        {
            Content = JsonContent.Create(snapshot)
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        return await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
    }

    private object BuildWpfS2CreationSnapshot(JsonElement draft, string commander, bool includeLogo)
    {
        var tagIds = CreationArray(draft, "tagIds", LegacyFleetTagCatalog.MaxSelection);
        var tagNames = tagIds.Select(id => LegacyFleetTagCatalog.Tags.Single(tag => tag.Id == id).Name).ToArray();
        var code = LegacyFleetCreationRules.NormalizeCode(Text(draft, "code", 10));
        var from = Text(draft, "activeFrom", 5);
        var to = Text(draft, "activeTo", 5);
        return new
        {
            name = Text(draft, "name", 32).Trim(),
            code,
            commander,
            description = Text(draft, "description", 500, multiline: true),
            type = tagNames.Length == 0 ? "未指定" : string.Join(" / ", tagNames),
            activeTime = $"{from} - {to}",
            joinPolicy = Text(draft, "joinPolicy", 10),
            logoText = code,
            logoImageData = includeLogo ? Optional(draft, "logoImageData", 700000) : null,
            onlineMembers = 0,
            totalMembers = 1,
            noticeTitle = "",
            noticeContent = "",
            currentTaskTitle = "",
            currentTaskBrief = "",
            currentTaskParticipants = "",
            currentTaskRally = "",
            currentTaskShip = "",
            currentTaskTime = (DateTime?)null,
            actionPlans = Array.Empty<object>(),
            lastUpdated = _targetClock.GetUtcNow(),
            ownerAccount = (string?)null,
            memberPermissions = Array.Empty<object>(),
            members = Array.Empty<object>(),
            eventLog = Array.Empty<object>(),
            currentTaskNoticeRevision = 0,
            ships = Array.Empty<object>(),
            taskHistory = Array.Empty<object>(),
            applications = Array.Empty<object>(),
            emailNotificationsEnabled = false,
            bannerImageData = (string?)null,
            activityWindows = new[]
            {
                new
                {
                    days = new[] { "mon", "tue", "wed", "thu", "fri", "sat", "sun" },
                    startTime = from,
                    endTime = to,
                    endsNextDay = string.CompareOrdinal(to, from) <= 0
                }
            },
            activeDaysDescription = "全周",
            activityCadence = "休闲",
            timeZoneId = Text(draft, "timeZoneId", 128),
            recruitingEnabled = Text(draft, "joinPolicy", 10) != "Invite",
            recruitingTarget = "所有玩家",
            recruitingNote = "",
            invites = Array.Empty<object>(),
            roleGroups = Array.Empty<object>(),
            publicListingEnabled = true,
            publicMemberScaleMode = "Exact",
            publicShipScaleMode = "TypeSummary",
            publicProfileEnabled = true,
            publicShowDescription = true,
            publicShowTags = true,
            publicShowActiveSystems = true,
            publicShowActivityTime = true,
            publicShowExternalContacts = false,
            activeSystemIds = CreationArray(draft, "activeSystemIds", 3),
            language = "zh-CN",
            websiteUrl = "",
            externalContacts = Array.Empty<object>(),
            publicShipCount = 0,
            publicShipTypeSummary = "",
            profileRevision = 0,
            noticePublishedAt = (DateTimeOffset?)null,
            inviteCodeCreationPolicy = FleetInvitationAccessPolicy.AllMembers,
            fleetInvitationCardPolicy = FleetInvitationAccessPolicy.AllMembers
        };
    }

    private static async Task<JsonDocument> ReadBoundedJsonAsync(
        HttpResponseMessage response,
        int maximumBytes,
        CancellationToken token)
    {
        using var stream = await response.Content.ReadAsStreamAsync(token);
        using var buffer = new MemoryStream();
        var chunk = new byte[8192];
        int count;
        while ((count = await stream.ReadAsync(chunk, token)) > 0)
        {
            if (buffer.Length + count > maximumBytes) throw Invalid();
            buffer.Write(chunk, 0, count);
        }
        return JsonDocument.Parse(buffer.ToArray());
    }
}
