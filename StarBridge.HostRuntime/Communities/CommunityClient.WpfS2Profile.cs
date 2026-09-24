using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private sealed record WpfS2ProfileEdit(string Code, string Scope, string TargetRef, string ViewerId,
        long Revision, DateTimeOffset Expires);
    private readonly ConcurrentDictionary<string, WpfS2ProfileEdit> _wpfS2ProfileEdits = new();

    internal Task<object> ReadWpfS2ProfileAsync(string bearer, JsonElement body, string scope, string viewerId,
        CancellationToken token) => GuardWorkspace(async () =>
    {
        var epoch = Interlocked.Read(ref _profileEpoch);
        Validate(body, "targetRef", "editRef");
        var reference = Optional(body, "targetRef", 32);
        var editReference = Optional(body, "editRef", 32);
        if ((reference is null) == (editReference is null)) throw Invalid();
        WpfS2ProfileEdit? prior = null;
        Target target;
        if (editReference is null)
        {
            target = ResolveForRead(reference!, scope, allowWpfS2: true);
            if (target.WpfS2ViewerId != viewerId) throw Invalid();
        }
        else
        {
            prior = ResolveWpfS2ProfileEdit(editReference, scope, viewerId);
            reference = prior.TargetRef;
            target = ResolveForRead(reference, scope, allowWpfS2: true);
        }
        var fleet = (await WpfS2Membership(bearer, token)).SingleOrDefault(row =>
            Text(row, "code", 256).Equals(target.Code, StringComparison.OrdinalIgnoreCase));
        if (fleet.ValueKind == JsonValueKind.Undefined) throw new AccountBridgeHostException("communities.notAllowed");
        var ownership = await ReadWpfS2Ownership(bearer, fleet, viewerId, token);
        var canEdit = ownership == WpfS2Ownership.Self || WpfS2HasPermission(fleet, viewerId, "canManageFleetInfo");
        if (!canEdit) throw new AccountBridgeHostException("communities.notAllowed");
        return CaptureWpfS2Profile(fleet, target.Code, scope, reference!, viewerId, epoch);
    });

    private object CaptureWpfS2Profile(JsonElement fleet, string code, string scope, string targetRef,
        string viewerId, long epoch)
    {
        var revision = WpfS2ProfileRevision(fleet);
        var fields = new Dictionary<string, object?>();
        foreach (var (key, max) in ProfileTexts)
            fields[key] = WpfS2ProfileText(fleet, key, max, key == "description");
        foreach (var key in ProfileFlags)
            fields[key] = WpfS2ProfileFlag(fleet, key);
        fields["activityWindows"] = WpfS2ProfileArray(fleet, "activityWindows");
        fields["activeSystemIds"] = WpfS2ProfileArray(fleet, "activeSystemIds");
        fields["externalContacts"] = WpfS2ProfileArray(fleet, "externalContacts");
        var profile = JsonSerializer.SerializeToElement(fields);
        lock (_profileCacheGate)
        {
            if (epoch != _profileEpoch) throw new AccountBridgeHostException("communities.identityUnavailable");
            foreach (var old in _wpfS2ProfileEdits.Where(row => row.Value.Expires <= _targetClock.GetUtcNow()).ToArray())
                _wpfS2ProfileEdits.TryRemove(old.Key, out _);
            if (_wpfS2ProfileEdits.Count >= 128) throw new AccountBridgeHostException("communities.refreshRequired");
            _targets[targetRef] = new(code, scope, _targetClock.GetUtcNow().AddMinutes(5),
                Text(fleet, "name", 512), viewerId);
            var editRef = Guid.NewGuid().ToString("N");
            _wpfS2ProfileEdits[editRef] = new(code, scope, targetRef, viewerId, revision,
                _targetClock.GetUtcNow().AddMinutes(30));
            return new
            {
                schemaVersion = 1,
                targetRef,
                editRef,
                code,
                name = Text(fleet, "name", 512),
                profileRevision = revision,
                hasLogo = !string.IsNullOrEmpty(Optional(fleet, "logoImageData", 1024 * 1024)),
                hasBanner = !string.IsNullOrEmpty(Optional(fleet, "bannerImageData", 3 * 1024 * 1024)),
                access = new { canEditProfile = true, canEditLogo = true, canEditBanner = true },
                profile
            };
        }
    }

    internal async Task<CommunityProfileSaveResult> SaveWpfS2ProfileAsync(string bearer, JsonElement body,
        string scope, string viewerId, Action current, CancellationToken token)
    {
        ValidateProfileSave(body);
        var editRef = Text(body, "editRef", 32);
        var key = scope + "\0wpf\0" + Text(body, "requestId", 32);
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(body.GetRawText())));
        var epoch = Interlocked.Read(ref _profileEpoch);
        if (!await _write.WaitAsync(0, token)) return new("rejected", "busy");
        var sent = false;
        try
        {
            current();
            if (_profileAttempts.TryGetValue(key, out var previous))
                return previous.Hash == hash ? previous.Result : new("rejected", "requestChanged");
            if (_profileAttempts.Count >= 256) return new("rejected", "refreshRequired");
            var edit = ResolveWpfS2ProfileEdit(editRef, scope, viewerId);
            var fleet = (await WpfS2Membership(bearer, token)).SingleOrDefault(row =>
                Text(row, "code", 256).Equals(edit.Code, StringComparison.OrdinalIgnoreCase));
            current();
            if (fleet.ValueKind == JsonValueKind.Undefined) return new("rejected", "notAllowed");
            var ownership = await ReadWpfS2Ownership(bearer, fleet, viewerId, token);
            current();
            if (ownership != WpfS2Ownership.Self && !WpfS2HasPermission(fleet, viewerId, "canManageFleetInfo"))
                return new("rejected", "notAllowed");
            if (WpfS2ProfileRevision(fleet) != edit.Revision) return new("rejected", "conflict");
            var changes = body.GetProperty("changes");
            var outgoing = BuildWpfS2ProfileUpdate(fleet, edit.Code, edit.Revision, changes);
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/fleets/info"))
                { Content = JsonContent.Create(outgoing) };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            current();
            deadline.Token.ThrowIfCancellationRequested();
            lock (_profileCacheGate)
            {
                if (epoch != _profileEpoch || !_wpfS2ProfileEdits.ContainsKey(editRef))
                    return new("rejected", "refreshRequired");
                _profileAttempts[key] = new(hash, new("unknown", "outcomeUnknown"));
            }
            sent = true;
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            current();
            CommunityProfileSaveResult result;
            if (!response.IsSuccessStatusCode)
                result = response.StatusCode switch
                {
                    HttpStatusCode.Conflict => new("rejected", "conflict"),
                    HttpStatusCode.BadRequest or HttpStatusCode.RequestEntityTooLarge => new("rejected", "invalidDraft"),
                    HttpStatusCode.Forbidden => new("rejected", "notAllowed"),
                    HttpStatusCode.NotFound => new("rejected", "refreshRequired"),
                    HttpStatusCode.Unauthorized => new("rejected", "identityUnavailable"),
                    _ => new("unknown", "outcomeUnknown")
                };
            else
            {
                using var document = await ReadBoundedJsonAsync(response, 8 * 1024 * 1024, deadline.Token);
                var root = document.RootElement;
                if (!Text(root, "code", 256).Equals(edit.Code, StringComparison.OrdinalIgnoreCase)) throw Invalid();
                if (changes.TryGetProperty("name", out var renamed) && Text(root, "name", 512) != renamed.GetString()!.Trim()) throw Invalid();
                var revision = WpfS2ProfileRevision(root);
                if (revision <= edit.Revision) throw Invalid();
                deadline.Token.ThrowIfCancellationRequested();
                current();
                result = new("accepted", ProfileRevision: revision) {
                    OrganizationCode = changes.TryGetProperty("name", out _) ? edit.Code : null,
                    OrganizationName = changes.TryGetProperty("name", out _) ? Text(root, "name", 512) : null
                };
            }
            _profileAttempts[key] = new(hash, result);
            return result;
        }
        catch (Exception error) when (error is HttpRequestException or IOException or OperationCanceledException or
            AccountBridgeHostException or BridgeStaleGenerationException or JsonException or InvalidOperationException or
            KeyNotFoundException or FormatException or OverflowException)
        {
            var result = new CommunityProfileSaveResult(sent ? "unknown" : "rejected",
                sent ? "outcomeUnknown" : "refreshRequired");
            if (sent) _profileAttempts[key] = new(hash, result);
            return result;
        }
        finally { _write.Release(); }
    }

    private WpfS2ProfileEdit ResolveWpfS2ProfileEdit(string reference, string scope, string viewerId) =>
        _wpfS2ProfileEdits.TryGetValue(reference, out var edit) && edit.Scope == scope && edit.ViewerId == viewerId &&
        edit.Expires > _targetClock.GetUtcNow()
            ? edit
            : throw new AccountBridgeHostException("communities.refreshRequired");

    private static long WpfS2ProfileRevision(JsonElement fleet)
    {
        if (!fleet.TryGetProperty("profileRevision", out var value)) return 0;
        var revision = value.GetInt64();
        return revision is >= 0 and <= 9007199254740991 ? revision : throw Invalid();
    }

    private static object? WpfS2ProfileText(JsonElement fleet, string key, int max, bool multiline = false)
    {
        if (!fleet.TryGetProperty(key, out var value) || value.ValueKind == JsonValueKind.Null)
            return key switch
            {
                "joinPolicy" => "Open",
                "inviteCodeCreationPolicy" or "fleetInvitationCardPolicy" => "commander",
                "language" => "zh-CN",
                "timeZoneId" => "UTC",
                _ => ""
            };
        return Text(fleet, key, max, multiline);
    }

    private static bool WpfS2ProfileFlag(JsonElement fleet, string key)
    {
        if (fleet.TryGetProperty(key, out var value)) return value.GetBoolean();
        return key is "emailNotificationsEnabled" or "publicListingEnabled" or "publicShowDescription" or
            "publicShowTags" or "publicShowActiveSystems" or "publicShowActivityTime";
    }

    private static JsonElement WpfS2ProfileArray(JsonElement fleet, string key) =>
        fleet.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.Array
            ? value.Clone()
            : JsonSerializer.SerializeToElement(Array.Empty<object>());

    private static Dictionary<string, object?> BuildWpfS2ProfileUpdate(JsonElement fleet, string code,
        long revision, JsonElement changes)
    {
        object? Value(string key, object? fallback = null) =>
            fleet.TryGetProperty(key, out var value) && value.ValueKind != JsonValueKind.Null ? value.Clone() : fallback;
        var outgoing = new Dictionary<string, object?>
        {
            ["fleetCode"] = code,
            ["description"] = Value("description", ""),
            ["type"] = Value("type", ""),
            ["activeTime"] = Value("activeTime", ""),
            ["joinPolicy"] = Value("joinPolicy", "Open"),
            ["logoText"] = Value("logoText", code),
            ["logoImageData"] = Value("logoImageData"),
            ["bannerImageData"] = Value("bannerImageData"),
            ["eventLog"] = null,
            ["emailNotificationsEnabled"] = Value("emailNotificationsEnabled", true),
            ["activityWindows"] = Value("activityWindows", Array.Empty<object>()),
            ["activeDaysDescription"] = Value("activeDaysDescription", ""),
            ["activityCadence"] = Value("activityCadence", ""),
            ["timeZoneId"] = Value("timeZoneId", "UTC"),
            ["recruitingEnabled"] = Value("recruitingEnabled", false),
            ["recruitingTarget"] = Value("recruitingTarget", ""),
            ["recruitingNote"] = Value("recruitingNote", ""),
            ["roleGroups"] = Value("roleGroups", Array.Empty<object>()),
            ["publicListingEnabled"] = Value("publicListingEnabled", true),
            ["publicMemberScaleMode"] = Value("publicMemberScaleMode", "Exact"),
            ["publicShipScaleMode"] = Value("publicShipScaleMode", "TypeSummary"),
            ["publicProfileEnabled"] = Value("publicProfileEnabled", true),
            ["publicShowDescription"] = Value("publicShowDescription", true),
            ["publicShowTags"] = Value("publicShowTags", true),
            ["publicShowActiveSystems"] = Value("publicShowActiveSystems", true),
            ["publicShowActivityTime"] = Value("publicShowActivityTime", true),
            ["publicShowExternalContacts"] = Value("publicShowExternalContacts", false),
            ["clearLogoImage"] = false,
            ["clearBannerImage"] = false,
            ["activeSystemIds"] = Value("activeSystemIds", Array.Empty<string>()),
            ["language"] = Value("language", "zh-CN"),
            ["websiteUrl"] = Value("websiteUrl", ""),
            ["externalContacts"] = Value("externalContacts", Array.Empty<object>()),
            ["expectedProfileRevision"] = revision,
            ["inviteCodeCreationPolicy"] = Value("inviteCodeCreationPolicy", "commander"),
            ["fleetInvitationCardPolicy"] = Value("fleetInvitationCardPolicy", "commander")
        };
        var sections = new HashSet<string>();
        foreach (var change in changes.EnumerateObject())
        {
            outgoing[change.Name] = change.Value.Clone();
            sections.Add(change.Name switch
            {
                "name" => "name",
                "logoText" or "logoImageData" or "clearLogoImage" => "logo",
                "clearBannerImage" => "banner",
                "description" => "description",
                "emailNotificationsEnabled" => "email-notifications",
                _ => "profile"
            });
        }
        outgoing["updatedSections"] = sections.Order().ToArray();
        ValidateRecruitmentChange(changes, outgoing);
        return outgoing;
    }
}
