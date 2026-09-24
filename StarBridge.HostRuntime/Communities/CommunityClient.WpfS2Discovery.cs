using System.Collections.Concurrent;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.PartyRooms;

namespace StarBridge.HostRuntime.Communities;

// Narrow input for the linked, existing WPF-semantics directory filter.
internal sealed record WpfS2DirectoryActivityWindow(string[] Days, string StartTime, string EndTime, bool EndsNextDay);
internal sealed record WpfS2DirectoryFilterSnapshot(bool PublicShowActivityTime, string ActivityCadence,
    string PublicShipScaleMode, int PublicShipCount, string PublicShipTypeSummary,
    string TimeZoneId, WpfS2DirectoryActivityWindow[] ActivityWindows)
{
    internal static string NormalizeFleetPublicShipScaleMode(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        "totalonly" => "TotalOnly", "hidden" => "Hidden", _ => "TypeSummary"
    };
}

internal sealed partial class CommunityClient
{
    private sealed record WpfS2DirectoryCursor(string Scope, string ViewerId, string Query, string Filters, string Code, DateTimeOffset Expires);
    private readonly ConcurrentDictionary<string, WpfS2DirectoryCursor> _wpfS2DirectoryCursors = new();
    private readonly Dictionary<string, (string Data, DateTimeOffset Expires)> _directoryLogos = new();
    private readonly object _directoryLogoGate = new();

    private void ClearDirectoryLogos() { lock (_directoryLogoGate) _directoryLogos.Clear(); }

    private string? CacheSharingLogo(string scope, string code, string? data)
    {
        var key = "sharing\0" + scope + "\0" + code.ToUpperInvariant();
        if (data is null) { lock (_directoryLogoGate) _directoryLogos.Remove(key); }
        else StoreDirectoryLogo(key, data, DateTimeOffset.MaxValue);
        return data;
    }

    internal string? CachedSharingLogo(string scope, string code)
    {
        lock (_directoryLogoGate)
            return _directoryLogos.TryGetValue("sharing\0" + scope + "\0" + code.ToUpperInvariant(), out var image)
                ? image.Data : null;
    }

    private void StoreDirectoryLogo(string reference, string data, DateTimeOffset expires)
    {
        lock (_directoryLogoGate)
        {
            foreach (var old in _directoryLogos.Where(x => x.Value.Expires <= _targetClock.GetUtcNow()).ToArray())
                _directoryLogos.Remove(old.Key);
            // At most 64 original images, each bounded to 512 KiB decoded.
            while (_directoryLogos.Count >= 64)
                _directoryLogos.Remove(_directoryLogos.MinBy(x => x.Value.Expires).Key);
            _directoryLogos[reference] = (data, expires);
        }
    }

    private JsonElement ReadDirectoryLogo(string reference, int offset, string? version, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        string data;
        lock (_directoryLogoGate)
        {
            if (!_directoryLogos.TryGetValue(reference, out var image) || image.Expires <= _targetClock.GetUtcNow())
                throw new AccountBridgeHostException("communities.refreshRequired");
            data = image.Data;
        }
        return WpfS2MediaChunk(data, "logo", null, offset, version);
    }

    private async Task<CommunityPage> ReadWpfS2Discovery(string bearer, CommunityQuery query, string scope, string viewerId, CancellationToken token)
    {
        if (string.IsNullOrWhiteSpace(viewerId) || query.View != "discover") throw Invalid();
        var requested = query.TargetRef is null ? null : ResolveForRead(query.TargetRef, scope, allowWpfS2: true);
        if (requested is not null && (requested.WpfS2ViewerId != viewerId || query.After is not null ||
            query.Filters is not null || query.Query.Length != 0)) throw Invalid();
        try
        {
            var search = query.Query.Trim();
            var filter = CommunityDirectoryFilters.Parse(query.Filters);
            var filterKey = query.Filters ?? "";
            WpfS2DirectoryCursor? cursor = null;
            if (query.After is not null && (!_wpfS2DirectoryCursors.TryGetValue(query.After, out cursor) ||
                cursor.Scope != scope || cursor.ViewerId != viewerId || cursor.Query != search || cursor.Filters != filterKey ||
                cursor.Expires <= _targetClock.GetUtcNow())) throw new AccountBridgeHostException("communities.refreshRequired");

            // WPF PullFleetsAsync sources, selected explicitly for an authenticated
            // legacy session. Never fall back from a failed modern/SCM request.
            var membership = await WorkspaceJson(bearer, "/api/fleets/membership", token);
            var ownCodes = WpfS2MembershipCodes(membership);
            // The additive list advertises multi-membership; older servers keep the guard.
            var multiple = membership.TryGetProperty("fleetCodes", out var membershipRows) &&
                membershipRows.ValueKind == JsonValueKind.Array;
            var admissionBlocked = ownCodes.Count > 0 && !multiple;
            var applications = await WorkspaceJson(bearer, "/api/fleets/applications/mine", token);
            if (applications.ValueKind != JsonValueKind.Array || applications.GetArrayLength() > 10000) throw Invalid();
            var pending = applications.EnumerateArray().Select(row => Text(row, "fleetCode", 256).Trim()).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var root = await WorkspaceJson(bearer, "/api/fleets", token, 8 * 1024 * 1024);
            if (root.ValueKind != JsonValueKind.Array || root.GetArrayLength() > 10000) throw Invalid();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var candidates = new List<(string Code, CommunityView Row, int Score, int Online, DateTimeOffset Updated)>();
            foreach (var fleet in root.EnumerateArray())
            {
                var code = Text(fleet, "code", 256);
                if (string.IsNullOrWhiteSpace(code) || !seen.Add(code)) throw Invalid();
                if (requested is not null && !code.Equals(requested.Code, StringComparison.OrdinalIgnoreCase)) continue;
                var member = ownCodes.Contains(code);
                if (!member && (!WpfFlag(fleet, "publicListingEnabled", true) || !WpfFlag(fleet, "publicProfileEnabled", true))) continue;
                var count = Number(fleet, "totalMembers", 0, 1000000);
                var scaleMode = WpfText(fleet, "publicMemberScaleMode", 32).Trim().ToLowerInvariant();
                var showActivity = WpfFlag(fleet, "publicShowActivityTime", true);
                var recruiting = WpfFlag(fleet, "recruitingEnabled", false);
                var row = new CommunityView(Text(fleet, "name", 512),
                    WpfFlag(fleet, "publicShowDescription", true) ? WpfText(fleet, "description", 8192, true) : "",
                    WpfText(fleet, "language", 512), showActivity ? WpfText(fleet, "activeTime", 1024) : "",
                    scaleMode is not ("approx" or "hidden") ? count : null,
                    member ? "member" : pending.Contains(code) ? "pending" : "none",
                    WpfS2JoinMode(WpfText(fleet, "joinPolicy", 32)),
                    WpfS2AdmissionActions(member, pending.Contains(code), admissionBlocked, WpfS2JoinMode(WpfText(fleet, "joinPolicy", 32))),
                    RoomAvatarProjection.Normalize(Optional(fleet, "logoImageData", 1024 * 1024), 512 * 1024), "")
                {
                    Tags = WpfFlag(fleet, "publicShowTags", true) ? WpfText(fleet, "type", 2048) : "",
                    MemberScale = scaleMode != "hidden" ? CommunityDirectoryFilters.Scale(count) : "",
                    Recruiting = recruiting, RecruitingTarget = recruiting ? WpfText(fleet, "recruitingTarget", 512, fallback: "所有玩家") : "",
                    RecruitingNote = recruiting ? WpfText(fleet, "recruitingNote", 2048, true) : "",
                    Systems = WpfFlag(fleet, "publicShowActiveSystems", true) && fleet.TryGetProperty("activeSystemIds", out var systems) && systems.ValueKind != JsonValueKind.Null ? ParseSystems(systems) : []
                };
                var windows = showActivity && fleet.TryGetProperty("activityWindows", out var windowRows) && windowRows.ValueKind == JsonValueKind.Array
                    ? Rows(fleet, "activityWindows", 3).Select(window => new WpfS2DirectoryActivityWindow(ParseSystems(window.GetProperty("days")),
                        Text(window, "startTime", 5), Text(window, "endTime", 5), WpfFlag(window, "endsNextDay", false))).ToArray() : [];
                var filterInput = new WpfS2DirectoryFilterSnapshot(showActivity, showActivity ? WpfText(fleet, "activityCadence", 128, fallback: "休闲") : "",
                    WpfText(fleet, "publicShipScaleMode", 32), fleet.TryGetProperty("publicShipCount", out _) ? Number(fleet, "publicShipCount", 0, 1000000) : 0,
                    WpfText(fleet, "publicShipTypeSummary", 4096), showActivity ? WpfText(fleet, "timeZoneId", 128) : "", windows);
                if (!filter.Matches(filterInput, row)) continue;
                var score = CommunityDirectoryFilters.SearchScore(row, search);
                // WPF also accepts its public organization identification code.
                if (search.Length > 0 && code.Contains(search, StringComparison.OrdinalIgnoreCase)) score = Math.Max(score,
                    code.Equals(search, StringComparison.OrdinalIgnoreCase) ? 100 : code.StartsWith(search, StringComparison.OrdinalIgnoreCase) ? 80 : 50);
                if (score == 0) continue;
                var updated = Timestamp(fleet, "lastUpdated");
                candidates.Add((code, row, score, fleet.TryGetProperty("onlineMembers", out _) ? Number(fleet, "onlineMembers", 0, 1000000) : 0,
                    updated is null ? DateTimeOffset.MinValue : DateTimeOffset.Parse(updated)));
            }
            var sorted = filter.Sort switch
            {
                "name" => candidates.OrderBy(x => x.Row.Name, StringComparer.OrdinalIgnoreCase),
                "members" => candidates.OrderByDescending(x => x.Row.MemberCount ?? -1).ThenByDescending(x => x.Row.Recruiting).ThenBy(x => x.Row.Name, StringComparer.OrdinalIgnoreCase),
                "recent" => candidates.OrderByDescending(x => x.Updated).ThenBy(x => x.Row.Name, StringComparer.OrdinalIgnoreCase),
                _ => candidates.OrderByDescending(x => x.Score).ThenByDescending(x => x.Row.Recruiting).ThenByDescending(x => x.Online).ThenByDescending(x => x.Updated).ThenBy(x => x.Row.Name, StringComparer.OrdinalIgnoreCase)
            };
            var all = sorted.ThenBy(x => x.Code, StringComparer.OrdinalIgnoreCase).ToArray();
            var start = cursor is null ? 0 : Array.FindIndex(all, x => string.Equals(x.Code, cursor.Code, StringComparison.OrdinalIgnoreCase)) + 1;
            if (cursor is not null && start == 0) throw new AccountBridgeHostException("communities.refreshRequired");
            var rows = all.Skip(start).Take(20).ToArray();
            // Pagination counts organizations, not image bytes. Media travels separately.
            var now = _targetClock.GetUtcNow();
            foreach (var old in _wpfS2DirectoryCursors.Where(x => x.Value.Expires <= now).ToArray()) _wpfS2DirectoryCursors.TryRemove(old.Key, out _);
            TrimTargets();
            if (_wpfS2DirectoryCursors.Count >= 512 || _targets.Count + rows.Length > 4000 || _organizationRefs.Count + rows.Length > 10000) throw Invalid();
            token.ThrowIfCancellationRequested();
            var result = rows.Select(x =>
            {
                var reference = Guid.NewGuid().ToString("N");
                _targets[reference] = new(x.Code, scope, now.AddMinutes(5), x.Row.Name, viewerId, true);
                if (x.Row.LogoImageData is { } logo) StoreDirectoryLogo(reference, logo, now.AddMinutes(5));
                return x.Row with { LogoImageData = null, LogoDeferred = x.Row.LogoImageData is not null,
                    TargetRef = reference, OrganizationRef = _organizationRefs.GetOrAdd(scope + "\0" + x.Code, _ => Guid.NewGuid().ToString("N")) };
            }).ToArray();
            string? next = null;
            if (start + rows.Length < all.Length)
            {
                next = Guid.NewGuid().ToString("N");
                _wpfS2DirectoryCursors[next] = new(scope, viewerId, search, filterKey, rows[^1].Code, now.AddMinutes(5));
            }
            return new("discover", search, next, result) { TotalCount = all.Length };
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { throw Invalid(); }
    }

    private static bool WpfFlag(JsonElement row, string key, bool fallback) =>
        !row.TryGetProperty(key, out var value) || value.ValueKind == JsonValueKind.Null ? fallback : value.GetBoolean();

    private static string[] WpfS2AdmissionActions(bool member, bool pending, bool admissionBlocked, string mode)
    {
        if (member) return [];
        if (pending) return ["withdraw"];
        if (admissionBlocked) return [];
        return mode switch { "direct" => ["join"], "application" => ["apply"], _ => [] };
    }

    private static string WpfS2JoinMode(string policy)
    {
        // Same legacy labels accepted by NetworkFleetCard.FromSnapshot.
        if (new[] { "申请", "审核", "Application", "Apply", "Request" }.Any(x => policy.Contains(x, StringComparison.OrdinalIgnoreCase))) return "application";
        if (new[] { "邀请", "Invite", "Code" }.Any(x => policy.Contains(x, StringComparison.OrdinalIgnoreCase))) return "inviteOnly";
        return "direct";
    }
}
