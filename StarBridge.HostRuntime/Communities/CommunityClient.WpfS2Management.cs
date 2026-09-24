using System.Text.Json;
using StarBridge.Core.Fleets;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    // The WPF/S2 service stores admissions inside its authoritative fleet
    // snapshot. This adapter keeps that bulk contract behind Host and emits the
    // same narrow projection consumed by the Flutter management surface.
    private async Task<object> ReadWpfS2AdmissionsAsync(string bearer, JsonElement body, string scope,
        Action current, CancellationToken token)
    {
        var epoch = Interlocked.Read(ref _inviteEpoch);
        Validate(body, "targetRef", "section", "offset");
        var reference = Text(body, "targetRef", 32);
        var target = ResolveForRead(reference, scope, allowWpfS2: true);
        if (target.WpfS2ViewerId is not { Length: > 0 } viewerId) throw Invalid();
        var section = Text(body, "section", 16);
        var offset = Number(body, "offset", 0, 1000000);
        if (section is not ("applications" or "invites")) throw Invalid();

        current();
        var fleet = (await WpfS2Membership(bearer, token)).SingleOrDefault(row =>
            string.Equals(Text(row, "code", 256), target.Code, StringComparison.OrdinalIgnoreCase));
        if (fleet.ValueKind == JsonValueKind.Undefined)
            throw new AccountBridgeHostException("communities.notAllowed");
        var ownership = await ReadWpfS2Ownership(bearer, fleet, viewerId, token);
        var canReview = WpfS2HasPermissionId(fleet, viewerId, "members.review", ownership);
        var canCreateInvite = WpfS2CanCreateInvite(fleet, viewerId, ownership);
        var canSendInvitationCard = WpfS2CanSendInvitationCard(fleet, viewerId, ownership);
        var canReadInvites = canCreateInvite;
        if (section == "applications" ? !canReview : !canReadInvites)
            throw new AccountBridgeHostException("communities.notAllowed");

        var pending = new List<(string Reference, AdmissionTarget Target)>();
        var rows = new List<Dictionary<string, object?>>();
        Dictionary<string, object?>? currentInvite = null;
        var now = _targetClock.GetUtcNow();
        string? viewerName = null;
        if (section == "applications")
        {
            var allApplications = WpfS2OptionalRows(fleet, "applications", 10000);
            if (allApplications.Select(row => Text(row, "id", 128)).Distinct(StringComparer.OrdinalIgnoreCase).Count() != allApplications.Length) throw Invalid();
            var source = allApplications
                .Where(row => string.IsNullOrWhiteSpace(WpfText(row, "status", 16)) || WpfText(row, "status", 16).Equals("Pending", StringComparison.OrdinalIgnoreCase))
                .OrderByDescending(row => WpfTimestamp(row, "createdAt"))
                .ToArray();
            if (offset > source.Length) throw Invalid();
            foreach (var row in source.Skip(offset).Take(20))
            {
                var id = Text(row, "id", 128);
                if (id.Length == 0) throw Invalid();
                var entryRef = Guid.NewGuid().ToString("N");
                rows.Add(new()
                {
                    ["entryRef"] = entryRef,
                    ["gameName"] = WpfText(row, "applicantGameName", 512),
                    ["callsign"] = WpfText(row, "applicantCallsign", 512),
                    ["message"] = WpfText(row, "message", 8192, multiline: true),
                    ["status"] = "Pending",
                    ["createdAt"] = WpfTimestamp(row, "createdAt")?.ToString("O"),
                    ["hasAvatar"] = !string.IsNullOrEmpty(Optional(row, "avatarImageData", 1024 * 1024))
                });
                pending.Add((entryRef, new(id, section, target.Code, scope, now.AddMinutes(5), offset)));
            }
            return Finish(source.Length, currentInviteAvailable: false);
        }

        var session = await WorkspaceJson(bearer, "/api/auth/session", token, 2 * 1024 * 1024);
        if (!Text(session, "accountId", 512).Equals(viewerId, StringComparison.OrdinalIgnoreCase)) throw Invalid();
        viewerName = Optional(session, "userName", 512);
        var invites = WpfS2InvitationRows(fleet)
            .OrderByDescending(row => WpfS2InviteStatus(row, now) == "Active")
            .ThenByDescending(row => WpfTimestamp(row, "createdAt"))
            .ToArray();
        if (offset > invites.Length) throw Invalid();
        var projectedInvites = new Dictionary<int, Dictionary<string, object?>>();
        for (var index = offset; index < Math.Min(offset + 20, invites.Length); index++)
        {
            var fields = ProjectInvite(invites[index], offset);
            projectedInvites[index] = fields;
            rows.Add(fields);
        }
        var ownIndex = Array.FindIndex(invites, row =>
            IsOwn(row) &&
            WpfS2InviteStatus(row, now) == "Active");
        if (ownIndex >= 0)
        {
            currentInvite = projectedInvites.TryGetValue(ownIndex, out var projected)
                ? projected
                : ProjectInvite(invites[ownIndex], ownIndex / 20 * 20);
        }
        return Finish(invites.Length, currentInviteAvailable: true);

        Dictionary<string, object?> ProjectInvite(JsonElement row, int pageOffset)
        {
            var id = Text(row, "id", 128);
            if (id.Length == 0) throw Invalid();
            var entryRef = Guid.NewGuid().ToString("N");
            var expires = WpfTimestamp(row, "expiresAt") ?? throw Invalid();
            var maxUses = Number(row, "maxUses", 0, int.MaxValue);
            var usedCount = Number(row, "usedCount", 0, int.MaxValue);
            var status = WpfS2InviteStatus(row, now);
            var isOwn = IsOwn(row);
            var fields = new Dictionary<string, object?>
            {
                ["entryRef"] = entryRef, ["code"] = Text(row, "code", 128),
                ["createdBy"] = WpfText(row, "createdBy", 512), ["status"] = status,
                ["createdAt"] = WpfTimestamp(row, "createdAt")?.ToString("O"), ["expiresAt"] = expires.ToString("O"),
                ["maxUses"] = maxUses, ["usedCount"] = usedCount, ["isOwn"] = isOwn,
                ["canRevoke"] = status == "Active" && (WpfS2HasManagementAccess(fleet, viewerId, ownership) || isOwn)
            };
            pending.Add((entryRef, new(id, section, target.Code, scope, now.AddMinutes(5), pageOffset)));
            return fields;
        }

        object Finish(int total, bool currentInviteAvailable)
        {
            current();
            token.ThrowIfCancellationRequested();
            lock (_inviteGate)
            {
                if (epoch != _inviteEpoch) throw new AccountBridgeHostException("communities.identityUnavailable");
                foreach (var old in _admissionTargets.Where(row => row.Value.Expires <= now).ToArray())
                    _admissionTargets.TryRemove(old.Key, out _);
                if (_admissionTargets.Count + pending.Count > 2048) throw Invalid();
                foreach (var entry in pending) _admissionTargets[entry.Reference] = entry.Target;
            }
            RenewTarget(reference, target, token);
            return new
            {
                schemaVersion = 1, targetRef = reference, section, offset,
                next = offset + rows.Count < total ? (int?)(offset + rows.Count) : null,
                totalCount = total,
                access = new { canReadApplications = canReview, canDecideApplications = canReview,
                    canReadInvites, canCreateInvite, canSendInvitationCard },
                items = rows, currentInviteAvailable, currentInvite,
                fetchedAt = now
            };
        }

        bool IsOwn(JsonElement row)
        {
            var creator = Optional(row, "createdByAccount", 512);
            return !string.IsNullOrWhiteSpace(creator) && (creator.Equals(viewerId, StringComparison.OrdinalIgnoreCase) ||
                !string.IsNullOrWhiteSpace(viewerName) && creator.Equals(viewerName, StringComparison.OrdinalIgnoreCase));
        }
    }

    private static JsonElement[] WpfS2OptionalRows(JsonElement source, string key, int max)
    {
        if (!source.TryGetProperty(key, out var rows) || rows.ValueKind == JsonValueKind.Null) return [];
        if (rows.ValueKind != JsonValueKind.Array || rows.GetArrayLength() > max) throw Invalid();
        return rows.EnumerateArray().ToArray();
    }

    private static DateTimeOffset? WpfTimestamp(JsonElement row, string key)
    {
        var value = Optional(row, key, 64);
        return value is null ? null : DateTimeOffset.TryParse(value, out var parsed) ? parsed : throw Invalid();
    }

    private static string WpfS2InviteStatus(JsonElement row, DateTimeOffset now)
    {
        var stored = WpfText(row, "status", 16, fallback: "Unavailable");
        if (!stored.Equals("Active", StringComparison.OrdinalIgnoreCase))
            return new[] { "Revoked", "Expired", "Exhausted" }.FirstOrDefault(value => value.Equals(stored, StringComparison.OrdinalIgnoreCase)) ?? "Unavailable";
        var expires = WpfTimestamp(row, "expiresAt") ?? throw Invalid();
        if (expires <= now) return "Expired";
        var maxUses = Number(row, "maxUses", 0, int.MaxValue);
        return maxUses > 0 && Number(row, "usedCount", 0, int.MaxValue) >= maxUses ? "Exhausted" : "Active";
    }

    private static bool WpfS2HasPermissionId(JsonElement fleet, string viewerId, string permission,
        WpfS2Ownership ownership)
    {
        if (ownership == WpfS2Ownership.Self) return true;
        if (!fleet.TryGetProperty("memberPermissions", out var source) || source.ValueKind != JsonValueKind.Array ||
            source.GetArrayLength() > 10000) return false;
        var matches = source.EnumerateArray().Where(row =>
            string.Equals(Optional(row, "accountId", 512), viewerId, StringComparison.OrdinalIgnoreCase)).ToArray();
        if (matches.Length != 1 || !matches[0].TryGetProperty("permissionEnabled", out var enabled) || !enabled.GetBoolean()) return false;
        var row = matches[0];
        if (row.TryGetProperty("extraDeniedPermissions", out var denied) && denied.ValueKind == JsonValueKind.Array &&
            denied.EnumerateArray().Any(value => string.Equals(value.GetString(), permission, StringComparison.OrdinalIgnoreCase))) return false;
        var hasRole = false;
        if (row.TryGetProperty("roleGroupKey", out var roleKey) && roleKey.ValueKind == JsonValueKind.String &&
            fleet.TryGetProperty("roleGroups", out var groups) && groups.ValueKind == JsonValueKind.Array)
        {
            var group = groups.EnumerateArray().SingleOrDefault(value =>
                string.Equals(Optional(value, "key", 128), roleKey.GetString(), StringComparison.OrdinalIgnoreCase));
            hasRole = group.ValueKind != JsonValueKind.Undefined;
            if (hasRole && group.TryGetProperty("permissions", out var permissions) && permissions.ValueKind == JsonValueKind.Array &&
                permissions.EnumerateArray().Any(value => string.Equals(value.GetString(), permission, StringComparison.OrdinalIgnoreCase))) return true;
        }
        if (!hasRole && row.TryGetProperty("extraAllowedPermissions", out var allowed) && allowed.ValueKind == JsonValueKind.Array &&
            allowed.EnumerateArray().Any(value => string.Equals(value.GetString(), permission, StringComparison.OrdinalIgnoreCase))) return true;
        return permission switch
        {
            "fleet.profile.edit" or "fleet.avatar.edit" or "members.review" or "audit.view" =>
                row.TryGetProperty("canManageFleetInfo", out var value) && value.GetBoolean(),
            "members.remove" => row.TryGetProperty("canRemoveMembers", out var value) && value.GetBoolean(),
            _ => false
        };
    }

    private static bool WpfS2HasManagementAccess(JsonElement fleet, string viewerId, WpfS2Ownership ownership) =>
        ownership == WpfS2Ownership.Self || WpfS2HasPermissionId(fleet, viewerId, "fleet.profile.edit", ownership) ||
        WpfS2HasPermissionId(fleet, viewerId, "members.remove", ownership) ||
        WpfS2HasPermission(fleet, viewerId, "canPublishTasks") || WpfS2HasPermission(fleet, viewerId, "canPublishPlans");

    private static bool WpfS2CanCreateInvite(JsonElement fleet, string viewerId, WpfS2Ownership ownership) =>
        FleetInvitationAccessPolicy.Allows(Optional(fleet, "inviteCodeCreationPolicy", 64), true,
            ownership == WpfS2Ownership.Self, WpfS2HasManagementAccess(fleet, viewerId, ownership));

    private static bool WpfS2CanSendInvitationCard(JsonElement fleet, string viewerId, WpfS2Ownership ownership) =>
        FleetInvitationAccessPolicy.Allows(Optional(fleet, "fleetInvitationCardPolicy", 64), true,
            ownership == WpfS2Ownership.Self, WpfS2HasManagementAccess(fleet, viewerId, ownership));
}
