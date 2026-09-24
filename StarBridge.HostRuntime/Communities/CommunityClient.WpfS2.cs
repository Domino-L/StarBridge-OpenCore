using System.Text.Json;
using System.Security.Cryptography;
using System.Text;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.PartyRooms;
using StarBridge.Core.Presence;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private enum WpfS2Ownership
    {
        Unknown,
        Self,
        Other
    }

    // Explicit legacy-session read adapter, not an HTTP failure fallback. The S2
    // server remains responsible for membership and field-level visibility.
    // Only ordinary-member exit is exposed here; management remains separate.
    internal async Task<CommunityPage> ReadWpfS2Async(string bearer, CommunityQuery query,
        string scope, string viewerId, CancellationToken token, Action<Notifications.PlayerActivitySourceSnapshot>? observed = null)
    {
        if (query.View == "discover") return await ReadWpfS2Discovery(bearer, query, scope, viewerId, token);
        if (query.View != "mine") throw Invalid();
        if (string.IsNullOrWhiteSpace(viewerId) || query.After is not null || query.Filters is not null || query.TargetRef is not null)
            throw Invalid();
        try
        {
            var fleets = await ReadWpfS2MembershipShared(bearer, scope, token);
            var q = query.Query.Trim();
            var items = new List<CommunityView>();
            Task<JsonElement>? ownershipSession = null;
            foreach (var fleet in fleets)
            {
                var code = Text(fleet, "code", 256);
                var name = Text(fleet, "name", 512);
                if (q.Length > 0 && !name.Contains(q, StringComparison.OrdinalIgnoreCase)) continue;
                var ownership = await ReadWpfS2Ownership(bearer, fleet, viewerId, token,
                    () => ownershipSession ??= WorkspaceJson(bearer, "/api/auth/session", token, 2 * 1024 * 1024));
                var canLeave = WpfS2CanLeave(fleet, viewerId, ownership);
                var reference = Guid.NewGuid().ToString("N");
                var count = Number(fleet, "totalMembers", 0, 1000000);
                _targets[reference] = new(code, scope, _targetClock.GetUtcNow().AddMinutes(5), name, viewerId);
                items.Add(new(name, WpfText(fleet, "description", 8192, true), WpfText(fleet, "language", 512),
                    WpfText(fleet, "activeTime", 1024), count,
                    ownership == WpfS2Ownership.Self ? "owner" : "member", "unavailable", canLeave ? ["leave"] : [],
                    CacheSharingLogo(scope, code, RoomAvatarProjection.Normalize(Optional(fleet, "logoImageData", 1024 * 1024), 512 * 1024)), reference)
                {
                    OrganizationRef = _organizationRefs.GetOrAdd(scope + "\0" + code, _ => Guid.NewGuid().ToString("N")),
                    Tags = WpfText(fleet, "type", 2048),
                    Systems = fleet.TryGetProperty("activeSystemIds", out var systems) && systems.ValueKind != JsonValueKind.Null ? ParseSystems(systems) : []
                });
            }
            TrimTargets();
            if (_targets.Count > 4000 || _organizationRefs.Count > 10000) throw Invalid();
            token.ThrowIfCancellationRequested();
            await ObserveWpfS2Players(bearer, fleets, observed, token, viewerId);
            return new(query.View, q, null, items.ToArray()) { TotalCount = items.Count };
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { throw Invalid(); }
    }

    private async Task<JsonElement[]> WpfS2Membership(string bearer, CancellationToken token)
    {
        // Same authenticated sources as MainWindow.RelaySync.PullFleetsAsync.
        var membership = await WorkspaceJson(bearer, "/api/fleets/membership", token);
        var codes = WpfS2MembershipCodes(membership);
        if (codes.Count == 0) return [];
        var root = await WorkspaceJson(bearer, "/api/fleets", token, 8 * 1024 * 1024);
        if (root.ValueKind != JsonValueKind.Array || root.GetArrayLength() > 10000) throw Invalid();
        var matches = root.EnumerateArray().Where(row => codes.Contains(Text(row, "code", 256))).ToArray();
        // Missing membership snapshot is an incomplete read, never an empty roster.
        if (matches.Length != codes.Count || matches.Select(row => Text(row, "code", 256))
            .Distinct(StringComparer.OrdinalIgnoreCase).Count() != codes.Count) throw Invalid();
        return matches;
    }

    private static HashSet<string> WpfS2MembershipCodes(JsonElement membership)
    {
        if (!membership.TryGetProperty("fleetCode", out _)) throw Invalid();
        var codes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        // The additive S2 response separates all memberships from the selected
        // sharing context (fleetCode). Never turn that context into membership.
        if (membership.TryGetProperty("fleetCodes", out var rows) && rows.ValueKind != JsonValueKind.Null)
        {
            if (rows.ValueKind != JsonValueKind.Array || rows.GetArrayLength() > 10000) throw Invalid();
            foreach (var row in rows.EnumerateArray())
            {
                if (row.ValueKind != JsonValueKind.String) throw Invalid();
                var code = row.GetString()!.Trim();
                if (code.Length is 0 or > 256 || !codes.Add(code)) throw Invalid();
            }
            return codes;
        }
        var single = Optional(membership, "fleetCode", 256)?.Trim();
        if (!string.IsNullOrEmpty(single)) codes.Add(single);
        return codes;
    }

    private async Task<WpfS2Ownership> ReadWpfS2Ownership(
        string bearer,
        JsonElement fleet,
        string viewerId,
        CancellationToken token,
        Func<Task<JsonElement>>? readSession = null)
    {
        var owner = Optional(fleet, "ownerAccount", 512)?.Trim();
        if (string.IsNullOrEmpty(owner)) return WpfS2Ownership.Unknown;
        if (owner.Equals(viewerId, StringComparison.OrdinalIgnoreCase)) return WpfS2Ownership.Self;
        try
        {
            // OwnerAccount in S2 may be the login name rather than the stable
            // account id. Resolve it only through the authenticated session.
            var session = await (readSession?.Invoke() ?? WorkspaceJson(bearer, "/api/auth/session", token, 2 * 1024 * 1024));
            if (!Text(session, "accountId", 512).Equals(viewerId, StringComparison.OrdinalIgnoreCase))
                return WpfS2Ownership.Unknown;
            var userName = Optional(session, "userName", 512)?.Trim();
            return string.IsNullOrEmpty(userName)
                ? WpfS2Ownership.Unknown
                : owner.Equals(userName, StringComparison.OrdinalIgnoreCase)
                    ? WpfS2Ownership.Self
                    : WpfS2Ownership.Other;
        }
        catch (AccountBridgeHostException)
        {
            return WpfS2Ownership.Unknown;
        }
    }

    private static bool WpfS2CanLeave(JsonElement fleet, string viewerId, WpfS2Ownership ownership)
    {
        if (ownership != WpfS2Ownership.Other ||
            !fleet.TryGetProperty("members", out var members) ||
            members.ValueKind != JsonValueKind.Array ||
            members.GetArrayLength() > 10000)
            return false;
        return members.EnumerateArray().Count(row =>
            string.Equals(Optional(row, "accountId", 512), viewerId, StringComparison.OrdinalIgnoreCase)) == 1;
    }

    private static bool WpfS2HasPermission(JsonElement fleet, string viewerId, string permission)
    {
        if (!fleet.TryGetProperty("memberPermissions", out var permissions) || permissions.ValueKind != JsonValueKind.Array ||
            permissions.GetArrayLength() > 10000) return false;
        var matches = permissions.EnumerateArray().Where(row =>
            string.Equals(Optional(row, "accountId", 512), viewerId, StringComparison.OrdinalIgnoreCase)).ToArray();
        if (matches.Length != 1 || !matches[0].TryGetProperty("permissionEnabled", out var enabled) || !enabled.GetBoolean())
            return false;
        return matches[0].TryGetProperty(permission, out var value) && value.ValueKind is JsonValueKind.True or JsonValueKind.False &&
               value.GetBoolean();
    }

    private async Task<JsonElement> WpfS2Workspace(string bearer, Target target, string query, int offset, CancellationToken token,
        Action<Notifications.PlayerActivitySourceSnapshot>? observed = null)
    {
        var membership = await ReadWpfS2MembershipShared(bearer, target.Scope, token);
        var fleet = membership.SingleOrDefault(row =>
            string.Equals(Text(row, "code", 256), target.Code, StringComparison.OrdinalIgnoreCase));
        if (fleet.ValueKind == JsonValueKind.Undefined) throw new AccountBridgeHostException("communities.notAllowed");
        var ownership = await ReadWpfS2Ownership(bearer, fleet, target.WpfS2ViewerId!, token);
        var canEditProfile = ownership == WpfS2Ownership.Self ||
                             WpfS2HasPermission(fleet, target.WpfS2ViewerId!, "canManageFleetInfo");
        // Preserve only the roster returned by Relay. No reconstruction from local
        // game handles, profile affiliation, public counts, or unrelated players.
        // Match WPF FleetMemberRosterOrderPolicy before filtering/paging. Use
        // only Relay's privacy-projected presence, never the raw player feed.
        // LINQ's stable ordering keeps equal-ranked members in source order.
        var roster = Rows(fleet, "members", 10000)
            .OrderBy(row => PlayerPresence.Normalize(WpfText(row, "liveStatus", 64, fallback: "Offline"),
                row.GetProperty("online").GetBoolean()) switch
            {
                PlayerPresenceKind.InGame => 0,
                PlayerPresenceKind.AppOnline or PlayerPresenceKind.Away => 1,
                _ => 2,
            })
            .ThenByDescending(row => WpfMemberIsOwner(fleet, row))
            .ThenByDescending(row => WpfFlag(WpfMemberPermission(fleet, row), "permissionEnabled"))
            .ToArray();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var members = roster.Select((row, index) =>
        {
            var accountId = Optional(row, "accountId", 512);
            // Only an ephemeral reference is emitted, including for hidden game IDs.
            var mediaId = WpfS2MemberId(row);
            var memberId = mediaId ?? "s2-row:" + index;
            if (!seen.Add(memberId)) throw Invalid();
            var role = WpfText(row, "roleTitle", 128);
            var color = "#9DAAB3";
            if (fleet.TryGetProperty("roleGroups", out var groups) && groups.ValueKind == JsonValueKind.Array)
            {
                var matching = groups.EnumerateArray().Where(g => WpfText(g, "displayName", 128) == role).ToArray();
                if (matching.Length == 1)
                {
                    var candidate = WpfText(matching[0], "color", 7);
                    if (candidate.Length == 7 && candidate[0] == '#' && candidate.Skip(1).All(Uri.IsHexDigit)) color = candidate;
                }
            }
            return new
            {
                memberId, gameName = WpfText(row, "gameName", 512), callsign = WpfText(row, "callsign", 512),
                roleTitle = role, roleColor = color,
                isSelf = string.Equals(accountId, target.WpfS2ViewerId, StringComparison.OrdinalIgnoreCase),
                isOwner = WpfMemberIsOwner(fleet, row),
                online = row.GetProperty("online").GetBoolean(), liveStatus = WpfText(row, "liveStatus", 64, fallback: "Offline"),
                hasAvatar = mediaId is not null && !string.IsNullOrEmpty(Optional(row, "avatarImageData", 1024 * 1024)),
                avatarVersion = mediaId is null ? null : AvatarContentVersion(Optional(row, "avatarImageData", 1024 * 1024)),
                ship = Optional(row, "ship", 512), location = Optional(row, "location", 512),
                hasServerSession = OptionalServerSession(row),
                locationConfidence = Optional(row, "locationConfidence", 512), serverRegion = Optional(row, "serverRegion", 512),
                serverShard = Optional(row, "serverShard", 512), lastUpdated = Timestamp(row, "lastUpdated"), joinedAt = Timestamp(row, "joinedAt"),
                arrivalPendingConfirmation = row.TryGetProperty("arrivalPendingConfirmation", out var pending) && pending.GetBoolean(),
                arrivalTargetCode = Optional(row, "arrivalTargetCode", 512)
            };
        }).ToArray();
        var matched = members.Where(row => query.Length == 0 || row.callsign.Contains(query, StringComparison.OrdinalIgnoreCase) ||
            row.gameName.Contains(query, StringComparison.OrdinalIgnoreCase) || row.roleTitle.Contains(query, StringComparison.OrdinalIgnoreCase)).ToArray();
        if (offset > matched.Length) throw Invalid();
        var page = matched.Skip(offset).Take(20).ToArray();
        object[] contacts = fleet.TryGetProperty("externalContacts", out var contactRows) && contactRows.ValueKind == JsonValueKind.Array
            ? Rows(fleet, "externalContacts", 100).Select(row => (object)new { platform = Text(row, "platform", 128), value = Text(row, "value", 2048) }).ToArray() : [];
        object[] windows = fleet.TryGetProperty("activityWindows", out var windowRows) && windowRows.ValueKind == JsonValueKind.Array
            ? Rows(fleet, "activityWindows", 3).Select(row => (object)new { days = ParseSystems(row.GetProperty("days")),
                startTime = Text(row, "startTime", 5), endTime = Text(row, "endTime", 5),
                endsNextDay = row.TryGetProperty("endsNextDay", out var ends) && ends.GetBoolean() }).ToArray() : [];
        await ObserveWpfS2Players(bearer, membership, observed, token, target.WpfS2ViewerId!);
        return JsonSerializer.SerializeToElement(new
        {
            schemaVersion = 1, membershipModelVersion = 1,
            code = target.Code, name = Text(fleet, "name", 512), description = WpfText(fleet, "description", 8192, true),
            tags = WpfText(fleet, "type", 2048), language = WpfText(fleet, "language", 512), activeTime = WpfText(fleet, "activeTime", 1024),
            timeZoneId = Optional(fleet, "timeZoneId", 128), websiteUrl = Optional(fleet, "websiteUrl", 2048),
            activeSystemIds = fleet.TryGetProperty("activeSystemIds", out var systems) && systems.ValueKind != JsonValueKind.Null ? ParseSystems(systems) : [],
            externalContacts = contacts, activityWindows = windows,
            hasLogo = !string.IsNullOrEmpty(Optional(fleet, "logoImageData", 1024 * 1024)),
            hasBanner = !string.IsNullOrEmpty(Optional(fleet, "bannerImageData", 3 * 1024 * 1024)),
            query, offset, next = offset + page.Length < matched.Length ? (int?)(offset + page.Length) : null,
            totalCount = members.Length, matchedCount = matched.Length, members = page, fetchedAt = DateTimeOffset.UtcNow,
            // Expose only the management slice with a completed WPF adapter.
            // Never infer an action grant from a display role.
            access = new { isOwner = ownership == WpfS2Ownership.Self, canEditProfile,
                canReviewApplications = WpfS2HasPermissionId(fleet, target.WpfS2ViewerId!, "members.review", ownership),
                canRemoveMembers = WpfS2HasPermissionId(fleet, target.WpfS2ViewerId!, "members.remove", ownership),
                canCreateInvite = WpfS2CanCreateInvite(fleet, target.WpfS2ViewerId!, ownership),
                canManageAnnouncements = WpfS2HasPermissionId(fleet, target.WpfS2ViewerId!, "announcements.manage", ownership),
                canEditLogo = canEditProfile, canEditBanner = canEditProfile,
                canViewLogs = WpfS2HasPermissionId(fleet, target.WpfS2ViewerId!, "audit.view", ownership) }
        });
    }

    private static string WpfText(JsonElement row, string key, int max, bool multiline = false, string fallback = "") =>
        !row.TryGetProperty(key, out var value) || value.ValueKind == JsonValueKind.Null ? fallback : Text(row, key, max, multiline);

    private async Task<JsonElement> WpfS2Media(string bearer, Target target, string kind, string? memberId,
        int offset, string? version, CancellationToken token)
    {
        var fleet = (await ReadWpfS2MembershipShared(bearer, target.Scope, token)).SingleOrDefault(row =>
            string.Equals(Text(row, "code", 256), target.Code, StringComparison.OrdinalIgnoreCase));
        if (fleet.ValueKind == JsonValueKind.Undefined) throw new AccountBridgeHostException("communities.notAllowed");
        var source = fleet;
        var key = kind == "logo" ? "logoImageData" : "bannerImageData";
        if (kind == "applicant")
        {
            var ownership = await ReadWpfS2Ownership(bearer, fleet, target.WpfS2ViewerId!, token);
            if (!WpfS2HasPermissionId(fleet, target.WpfS2ViewerId!, "members.review", ownership))
                throw new AccountBridgeHostException("communities.notAllowed");
            var candidates = WpfS2OptionalRows(fleet, "applications", 10000)
                .Where(row => WpfText(row, "id", 128) == memberId).ToArray();
            if (candidates.Length != 1) throw new AccountBridgeHostException("communities.refreshRequired");
            source = candidates[0];
            key = "avatarImageData";
        }
        if (kind == "avatar")
        {
            var candidates = Rows(fleet, "members", 10000).Select((row, index) => new
            {
                row, id = WpfS2MemberId(row)
            }).Where(candidate => candidate.id == memberId).ToArray();
            if (candidates.Length != 1) throw new AccountBridgeHostException("communities.refreshRequired");
            source = candidates[0].row;
            key = "avatarImageData";
        }
        // Same byte budgets and file signatures as the existing CommunityMediaEndpoint.
        var raw = Optional(source, key, 3 * 1024 * 1024)?.Trim();
        return WpfS2MediaChunk(raw, kind, memberId, offset, version);
    }

    private static JsonElement WpfS2MediaChunk(string? raw, string kind, string? memberId, int offset, string? version)
    {
        if (string.IsNullOrEmpty(raw)) throw new AccountBridgeHostException("communities.notFound");
        var comma = raw.IndexOf(',');
        if (comma >= 0 && !raw.StartsWith("data:image/", StringComparison.Ordinal)) throw Invalid();
        var bytes = Convert.FromBase64String(comma >= 0 ? raw[(comma + 1)..] : raw);
        if (bytes.Length == 0 || bytes.Length > (kind == "banner" ? 2 * 1024 * 1024 : 512 * 1024)) throw Invalid();
        var mimeType = WpfS2Mime(bytes) ?? throw Invalid();
        var hash = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        if (version is not null && version != hash) throw new AccountBridgeHostException("communities.mediaChanged");
        if (offset >= bytes.Length) throw Invalid();
        var count = Math.Min(192 * 1024, bytes.Length - offset);
        return JsonSerializer.SerializeToElement(new
        {
            schemaVersion = 1, kind, memberId, version = hash, mimeType, totalBytes = bytes.Length, offset,
            next = offset + count < bytes.Length ? (int?)(offset + count) : null,
            data = Convert.ToBase64String(bytes, offset, count)
        });
    }

    private static string? WpfS2MemberId(JsonElement row)
    {
        if (Optional(row, "accountId", 512) is { Length: > 0 } account) return "account:" + account;
        var name = WpfText(row, "gameName", 512);
        // A fully anonymous row cannot safely retain media identity across refresh/reorder.
        return name.Length == 0 ? null : "legacy:" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(name.ToUpperInvariant()))).ToLowerInvariant();
    }

    private static string? WpfS2Mime(byte[] bytes) => bytes.AsSpan() switch
    {
        [137, 80, 78, 71, 13, 10, 26, 10, ..] => "image/png",
        [255, 216, 255, ..] => "image/jpeg",
        [66, 77, ..] => "image/bmp",
        [71, 73, 70, 56, 55 or 57, 97, ..] => "image/gif",
        [82, 73, 70, 70, _, _, _, _, 87, 69, 66, 80, ..] => "image/webp",
        _ => null,
    };
}
