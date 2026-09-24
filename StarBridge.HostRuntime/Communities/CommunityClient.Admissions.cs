using System.Collections.Concurrent;
using System.Text.Json;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private sealed record AdmissionTarget(string Id, string Kind, string Code, string Scope, DateTimeOffset Expires, int Offset);
    private readonly ConcurrentDictionary<string, AdmissionTarget> _admissionTargets = new();

    internal Task<object> ReadAdmissionsAsync(string bearer, JsonElement body, string scope,
        Action current, CancellationToken token, bool wpfS2 = false) => GuardWorkspace(async () =>
    {
        if (wpfS2) return await ReadWpfS2AdmissionsAsync(bearer, body, scope, current, token);
        Validate(body, "targetRef", "section", "offset");
        var reference = Text(body, "targetRef", 32);
        var target = ResolveForRead(reference, scope);
        var section = Text(body, "section", 16);
        var offset = Number(body, "offset", 0, 1000000);
        if (section is not ("applications" or "invites")) throw Invalid();
        current();
        var root = await WorkspaceJson(bearer,
            $"/api/fleets/admissions?code={Uri.EscapeDataString(target.Code)}&section={section}&offset={offset}", token);
        current();
        if (Number(root, "schemaVersion", 1, 1) != 1 || Number(root, "membershipModelVersion", 2, 2) != 2 ||
            Text(root, "code", 256) != target.Code || Text(root, "section", 16) != section ||
            Number(root, "offset", 0, 1000000) != offset) throw Invalid();
        var total = Number(root, "totalCount", 0, 1000000);
        int? next = root.GetProperty("next").ValueKind == JsonValueKind.Null ? null : Number(root, "next", 0, 1000000);
        var source = Rows(root, section, 20).ToArray();
        if (offset > total || source.Length != Math.Min(20, total - offset) ||
            next != (offset + source.Length < total ? offset + source.Length : null) ||
            Rows(root, section == "applications" ? "invites" : "applications", 0).Any()) throw Invalid();
        var access = root.GetProperty("access");
        var flags = new[] { "canReadApplications", "canDecideApplications", "canReadInvites", "canCreateInvite", "canSendInvitationCard" }
            .ToDictionary(key => key, key => access.GetProperty(key).GetBoolean());
        if (!flags[section == "applications" ? "canReadApplications" : "canReadInvites"]) throw Invalid();
        var rows = new List<Dictionary<string, object?>>();
        Dictionary<string, object?>? currentInvite = null;
        var currentInviteAvailable = root.TryGetProperty("currentInvite", out var own);
        var hasCurrent = currentInviteAvailable && own.ValueKind != JsonValueKind.Null;
        int? ownOffset = null;
        string? ownId = null;
        if (hasCurrent)
        {
            if (section != "invites" || !own.GetProperty("isOwn").GetBoolean() || Text(own, "status", 16) != "Active") throw Invalid();
            ownOffset = Number(root, "currentInviteOffset", 0, 1000000);
            if (ownOffset % 20 != 0 || ownOffset >= total) throw Invalid();
            ownId = Text(own, "inviteId", 128);
            var duplicate = source.FirstOrDefault(row => Text(row, "inviteId", 128) == ownId);
            if (duplicate.ValueKind != JsonValueKind.Undefined && (ownOffset != offset || duplicate.GetRawText() != own.GetRawText())) throw Invalid();
            if (duplicate.ValueKind == JsonValueKind.Undefined && ownOffset == offset) throw Invalid();
        }
        else if (root.TryGetProperty("currentInviteOffset", out var unexpectedOffset) && unexpectedOffset.ValueKind != JsonValueKind.Null) throw Invalid();
        var pending = new List<(string Reference, AdmissionTarget Target)>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var extra = hasCurrent && !source.Any(row => Text(row, "inviteId", 128) == ownId);
        foreach (var row in extra ? source.Append(own) : source)
        {
            var id = Text(row, section == "applications" ? "applicationId" : "inviteId", 128);
            if (id.Length == 0 || !seen.Add(id)) throw Invalid();
            var entryRef = Guid.NewGuid().ToString("N");
            var fields = section == "applications"
                ? Strings(row, ("gameName", 512), ("callsign", 512), ("status", 16))
                : Strings(row, ("code", 128), ("createdBy", 512), ("status", 16));
            fields["entryRef"] = entryRef;
            fields["createdAt"] = Timestamp(row, "createdAt");
            if (section == "applications")
            {
                if ((string)fields["status"]! != "Pending") throw Invalid();
                fields["message"] = Text(row, "message", 8192, true);
                fields["hasAvatar"] = row.GetProperty("hasAvatar").GetBoolean();
            }
            else
            {
                if ((string)fields["status"]! is not ("Active" or "Revoked" or "Expired" or "Exhausted" or "Unavailable")) throw Invalid();
                fields["expiresAt"] = Timestamp(row, "expiresAt");
                fields["maxUses"] = Number(row, "maxUses", 0, int.MaxValue);
                fields["usedCount"] = Number(row, "usedCount", 0, int.MaxValue);
                fields["isOwn"] = row.GetProperty("isOwn").GetBoolean();
                fields["canRevoke"] = row.GetProperty("canRevoke").GetBoolean();
            }
            if (hasCurrent && id == ownId) currentInvite = fields;
            if (!extra || id != ownId) rows.Add(fields);
            pending.Add((entryRef, new(id, section, target.Code, scope, DateTimeOffset.UtcNow.AddMinutes(5), id == ownId ? ownOffset!.Value : offset)));
        }
        var fetchedAt = Timestamp(root, "fetchedAt") ?? throw Invalid();
        token.ThrowIfCancellationRequested();
        lock (_inviteGate)
        {
            current();
            foreach (var old in _admissionTargets.Where(row => row.Value.Expires <= DateTimeOffset.UtcNow).ToArray())
                _admissionTargets.TryRemove(old.Key, out _);
            if (_admissionTargets.Count + pending.Count > 2048) throw Invalid();
            foreach (var entry in pending) _admissionTargets[entry.Reference] = entry.Target;
        }
        RenewTarget(reference, target, token);
        return new { schemaVersion = 1, targetRef = reference, section, offset, next, totalCount = total,
            access = flags, items = rows, currentInviteAvailable, currentInvite, fetchedAt };
    });
}
