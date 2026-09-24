using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.PartyRooms;

namespace StarBridge.HostRuntime.Communities;

internal sealed record CommunityView(string Name, string Description, string Language, string ActiveTime,
    int? MemberCount, string Relationship, string JoinMode, string[] Actions, string? LogoImageData, string TargetRef)
{
    public string OrganizationRef { get; init; } = "";
    public bool LogoDeferred { get; init; }
    public string Tags { get; init; } = "";
    public string MemberScale { get; init; } = "";
    public bool Recruiting { get; init; }
    public string RecruitingTarget { get; init; } = "";
    public string RecruitingNote { get; init; } = "";
    public string[] Systems { get; init; } = [];
}
internal sealed record CommunityPage(string View, string Query, string? Next, CommunityView[] Items)
{
    public int SchemaVersion => 1;
    public int? TotalCount { get; init; }
}
internal sealed record CommunityQuery(string View, string Query, string? After, string? TargetRef, string? Filters = null);
internal sealed record CommunityCommand(string Status, string? Error = null)
{
    public int SchemaVersion => 1;
}

internal sealed partial class CommunityClient : IDisposable
{
    private sealed record Target(string Code, string Scope, DateTimeOffset Expires, string Name = "", string? WpfS2ViewerId = null, bool WpfS2Directory = false);
    private readonly ConcurrentDictionary<string, Target> _targets = new();
    private readonly ConcurrentDictionary<string, string> _organizationRefs = new();
    private readonly SemaphoreSlim _write = new(1);
    private readonly Uri _origin;
    private readonly HttpClient _http;
    private readonly TimeProvider _targetClock;
    private readonly Lazy<InvitationSendWorkflow> _invitationWorkflow;
    private readonly Func<string, string?, string, object[]?> _shipLoaners;
    private readonly bool _loanerSearchAvailable;
    internal CommunityClient(Uri origin, HttpMessageHandler? handler = null, TimeProvider? targetClock = null,
        InvitationOutboxJournal? invitationJournal = null,
        Func<string, string?, string, object[]?>? shipLoaners = null, bool? loanerSearchAvailable = null)
    {
        if (!origin.IsAbsoluteUri || origin.UserInfo.Length != 0 || origin.Query.Length != 0 || origin.Fragment.Length != 0 ||
            origin.Scheme != "https" && !(origin.Scheme == "http" && origin.IsLoopback)) throw new ArgumentException("Trusted origin required");
        _origin = origin;
        _targetClock = targetClock ?? TimeProvider.System;
        _invitationWorkflow = new(() => new(invitationJournal ?? new InvitationOutboxJournal()));
        _shipLoaners = shipLoaners ?? CommunityShipCatalog.Loaners;
        _loanerSearchAvailable = loanerSearchAvailable ?? CommunityShipCatalog.Available;
        _http = new(handler ?? new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(12) };
    }
    internal static CommunityQuery ParseQuery(JsonElement body)
    {
        Validate(body, "view", "query", "after", "targetRef", "filters");
        var view = Text(body, "view", 16);
        if (view is not ("mine" or "discover")) throw Invalid();
        return new(view, Text(body, "query", 128), Optional(body, "after", 256), Optional(body, "targetRef", 32), Optional(body, "filters", 4096));
    }
    internal static (string Action, string Reference) ParseCommand(JsonElement body)
    {
        Validate(body, "action", "targetRef");
        var action = Text(body, "action", 16);
        if (action is not ("join" or "apply" or "withdraw" or "leave")) throw Invalid();
        return (action, Text(body, "targetRef", 32));
    }
    private static void Validate(JsonElement body, params string[] allowed)
    {
        try
        {
            if (body.GetProperty("schemaVersion").GetInt32() != 1 ||
                body.EnumerateObject().Select(p => p.Name).Distinct().Count() != body.EnumerateObject().Count() ||
                body.EnumerateObject().Any(p => p.Name != "schemaVersion" && !allowed.Contains(p.Name))) throw Invalid();
        }
        catch (Exception e) when (e is InvalidOperationException or KeyNotFoundException or FormatException) { throw Invalid(); }
    }
    private Target Resolve(string reference, string scope, bool allowWpfS2 = false)
    {
        if (!_targets.TryGetValue(reference, out var target) || target.Scope != scope || target.Expires <= _targetClock.GetUtcNow())
            throw new AccountBridgeHostException("communities.refreshRequired");
        if (!allowWpfS2 && target.WpfS2ViewerId is not null)
            throw new AccountBridgeHostException("communities.upgradeRequired");
        return target;
    }
    // A retained address is not a permission or a write lease. Root page reads
    // always fetch and validate current server membership/visibility before
    // returning data. Action/detail references still use strict Resolve above.
    private Target ResolveForRead(string reference, string scope, bool allowWpfS2 = false)
    {
        if (!_targets.TryGetValue(reference, out var target) || target.Scope != scope)
            throw new AccountBridgeHostException("communities.refreshRequired");
        if (!allowWpfS2 && target.WpfS2ViewerId is not null)
            throw new AccountBridgeHostException("communities.upgradeRequired");
        return target;
    }
    private void TrimTargets()
    {
        var now = _targetClock.GetUtcNow();
        // Account-scoped addresses survive sleep; they confer no authorization.
        // Bound memory by count rather than making an idle page expire by time.
        foreach (var old in _targets.Where(p => p.Value.Expires <= now).OrderBy(p => p.Value.Expires)
                     .Take(Math.Max(0, _targets.Count - 3980)).ToArray())
            _targets.TryRemove(old.Key, out _);
    }
    // Only a fully validated authorized read may keep an active page's lease
    // alive. Compare/update cannot recreate a disposed or replaced scope.
    private void RenewTarget(string reference, Target target, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        _targets.TryUpdate(reference, target with { Expires = _targetClock.GetUtcNow().AddMinutes(5) }, target);
    }
    internal async Task<CommunityPage> ReadAsync(string bearer, CommunityQuery query, string scope, CancellationToken token)
    {
        if (query.TargetRef is not null && ResolveForRead(query.TargetRef, scope, allowWpfS2: true) is { WpfS2ViewerId: not null } legacy)
            return await ReadWpfS2Discovery(bearer, query, scope, legacy.WpfS2ViewerId, token);
        var code = query.TargetRef is null ? null : ResolveForRead(query.TargetRef, scope).Code;
        var path = "/api/fleets/directory?view=" + Uri.EscapeDataString(query.View) + "&q=" + Uri.EscapeDataString(query.Query);
        if (query.After is not null) path += "&after=" + Uri.EscapeDataString(query.After);
        if (query.Filters is not null) path += "&filters=" + Uri.EscapeDataString(query.Filters);
        if (code is not null) path += "&code=" + Uri.EscapeDataString(code);
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_origin, path));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        try
        {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (response.StatusCode == HttpStatusCode.Unauthorized) throw new AccountBridgeHostException("communities.identityUnavailable");
            if (response.StatusCode == HttpStatusCode.NotFound) throw new AccountBridgeHostException("communities.upgradeRequired");
            if (!response.IsSuccessStatusCode) throw new AccountBridgeHostException("communities.unavailable", true);
            using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            using var buffer = new MemoryStream();
            var chunk = new byte[8192];
            int count;
            while ((count = await stream.ReadAsync(chunk, deadline.Token)) > 0)
            {
                if (buffer.Length + count > 3 * 1024 * 1024) throw Invalid();
                buffer.Write(chunk, 0, count);
            }
            using var document = JsonDocument.Parse(buffer.ToArray());
            return Project(document.RootElement, query, scope, code);
        }
        catch (OperationCanceledException) when (!token.IsCancellationRequested) { throw new AccountBridgeHostException("communities.unavailable", true); }
        catch (Exception e) when (e is HttpRequestException or IOException) { throw new AccountBridgeHostException("communities.unavailable", true); }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException) { throw Invalid(); }
    }
    private CommunityPage Project(JsonElement root, CommunityQuery query, string scope, string? targetCode)
    {
        if (root.GetProperty("schemaVersion").GetInt32() != 1 || root.GetProperty("membershipModelVersion").GetInt32() != 2 ||
            Text(root, "view", 16) != query.View || Text(root, "query", 128) != query.Query.Trim()) throw Invalid();
        var items = root.GetProperty("items");
        if (query.Filters is not null && (!root.TryGetProperty("directoryVersion", out var version) || version.GetInt32() != 2))
            throw new AccountBridgeHostException("communities.upgradeRequired");
        if (items.GetArrayLength() > 20) throw Invalid();
        TrimTargets();
        if (_targets.Count + items.GetArrayLength() > 4000) throw Invalid();
        var codes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var rows = items.EnumerateArray().Select(item =>
        {
            var code = Text(item, "code", 256);
            if (code.Length == 0 || !codes.Add(code) || targetCode is not null && code != targetCode) throw Invalid();
            var relationship = Text(item, "relationship", 16);
            var mode = Text(item, "joinMode", 16);
            if (relationship is not ("owner" or "member" or "pending" or "none") || mode is not ("direct" or "application" or "inviteOnly" or "unavailable")) throw Invalid();
            var actions = item.GetProperty("actions").EnumerateArray().Select(a => a.GetString() ?? "").ToArray();
            if (actions.Length > 1 || actions.Any(a => a is not ("join" or "apply" or "withdraw" or "leave"))) throw Invalid();
            int? memberCount = item.GetProperty("memberCount").ValueKind == JsonValueKind.Null ? null : item.GetProperty("memberCount").GetInt32();
            if (memberCount < 0) throw Invalid();
            var reference = Guid.NewGuid().ToString("N");
            _targets[reference] = new(code, scope, _targetClock.GetUtcNow().AddMinutes(5), Text(item, "name", 512));
            return new CommunityView(Text(item, "name", 512), Text(item, "description", 8192, true),
                Text(item, "language", 512), Text(item, "activeTime", 1024), memberCount, relationship, mode, actions,
                CacheSharingLogo(scope, code, RoomAvatarProjection.Normalize(Optional(item, "logoImageData", 128 * 1024))), reference)
            {
                OrganizationRef = _organizationRefs.GetOrAdd(scope + "\0" + code, _ => Guid.NewGuid().ToString("N")),
                Tags = Optional(item, "tags", 2048) ?? "",
                MemberScale = Optional(item, "memberScale", 16) ?? "",
                Recruiting = item.TryGetProperty("recruiting", out var recruiting) && recruiting.GetBoolean(),
                RecruitingTarget = Optional(item, "recruitingTarget", 512) ?? "",
                RecruitingNote = item.TryGetProperty("recruiting", out var isRecruiting) && isRecruiting.GetBoolean()
                    ? Optional(item, "recruitingNote", 2048, multiline: true) ?? "" : "",
                Systems = item.TryGetProperty("systems", out var systems) ? ParseSystems(systems) : [],
            };
        }).ToArray();
        if (_organizationRefs.Count > 10000) _organizationRefs.Clear();
        int? total = root.TryGetProperty("totalCount", out var totalValue) ? totalValue.GetInt32() : null;
        if (total < 0) throw Invalid();
        return new(query.View, query.Query.Trim(), Optional(root, "next", 256), rows) { TotalCount = total };
    }
    private static string[] ParseSystems(JsonElement value)
    {
        if (value.GetArrayLength() > 20) throw Invalid();
        var values = value.EnumerateArray().Select(x => x.GetString() ?? "").ToArray();
        if (values.Any(x => x.Length > 128 || x.Any(char.IsControl))) throw Invalid();
        return values;
    }
    internal async Task<CommunityCommand> ExecuteAsync(string bearer, JsonElement body, string scope,
        Action current, CancellationToken token)
    {
        var (action, reference) = ParseCommand(body);
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(40));
        token = deadline.Token;
        if (!await _write.WaitAsync(0, token)) return new("rejected", "busy");
        var sent = false;
        try
        {
            current();
            var target = Resolve(reference, scope, allowWpfS2: true);
            if (target.WpfS2ViewerId is not null && action == "leave")
                return await LeaveWpfS2Async(bearer, target, current, token);
            var latest = await ReadAsync(bearer, new("discover", "", null, reference), scope, token);
            if (latest.Items.Length != 1 || !latest.Items[0].Actions.Contains(action)) return new("rejected", "refreshRequired");
            current();
            token.ThrowIfCancellationRequested();
            var path = action switch { "join" or "apply" => "/api/fleets/apply", "withdraw" => "/api/fleets/applications/withdraw", _ => "/api/fleets/leave" };
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, path))
                { Content = target.WpfS2ViewerId is not null && action is "join" or "apply"
                    ? JsonContent.Create(new { FleetCode = target.Code, Message = "" })
                    : JsonContent.Create(new { FleetCode = target.Code }) };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            sent = true;
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            if (!response.IsSuccessStatusCode) return new(response.StatusCode is HttpStatusCode.BadRequest or HttpStatusCode.Forbidden or HttpStatusCode.NotFound ? "rejected" : "unknown", "refreshRequired");
            current();
            if (target.WpfS2ViewerId is not null)
            {
                var outcome = await ReadWpfS2AdmissionOutcome(bearer, target.Code, action, token);
                current();
                return new(outcome ? "accepted" : "unknown", outcome ? null : "outcomeUnknown");
            }
            var confirmed = await ReadAsync(bearer, new("discover", "", null, reference), scope, token);
            current();
            if (target.WpfS2ViewerId is not null && confirmed.Items.Length != 1)
                return new("unknown", "outcomeUnknown");
            var relationship = confirmed.Items.SingleOrDefault()?.Relationship;
            var expected = action switch
            {
                "join" => relationship is "member" or "owner",
                "apply" => relationship == "pending",
                _ => relationship is null or "none"
            };
            return new(expected ? "accepted" : "unknown", expected ? null : "refreshRequired");
        }
        catch (Exception e) when (e is HttpRequestException or IOException or OperationCanceledException or AccountBridgeHostException or StarBridge.NativeBridge.BridgeStaleGenerationException)
        { return new(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired"); }
        finally { if (sent) _targets.TryRemove(reference, out _); _write.Release(); }
    }
    private static string? Optional(JsonElement body, string name, int max, bool multiline = false) =>
        !body.TryGetProperty(name, out var value) || value.ValueKind == JsonValueKind.Null ? null : Text(body, name, max, multiline);
    private static string Text(JsonElement body, string name, int max, bool multiline = false)
    {
        var text = body.GetProperty(name).GetString() ?? "";
        if (text.Length > max || text.Any(c => char.IsControl(c) && !(multiline && c is '\n' or '\r' or '\t'))) throw Invalid();
        return text;
    }
    private static AccountBridgeHostException Invalid() => new("communities.dataInvalid");
    public void Dispose() { DisposeMembershipReads(); InvalidateInvitePreviews(); InvalidateProfileEdits(); InvalidateRolesEdits(); InvalidateHangarEdits(); ClearDirectoryLogos(); _http.Dispose(); _targets.Clear(); _organizationRefs.Clear(); _wpfS2DirectoryCursors.Clear(); _creationAttempts.Clear(); _memberTargets.Clear(); _profileAttempts.Clear(); _logTargets.Clear(); _disbandConfirmations.Clear(); _chatTargets.Clear(); _chatAttempts.Clear(); _announcementTargets.Clear(); _announcementAttempts.Clear(); _shipTargets.Clear(); _shipReportAttempts.Clear(); }
}
