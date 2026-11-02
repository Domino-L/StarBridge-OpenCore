using StarBridge.Core.Organizations;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace StarBridge.HostRuntime.Communities;

// Closed role recovery facts. They never masquerade as announcement timeline facts.
internal sealed record OfficialRoleMetadataValue(string DisplayName, string Description, string Color, int SortOrder);
internal sealed record OfficialRoleJournalIntent(string SourceRef, string ScopeKey, string AuthorityBinding, string Action,
    long PolicyRevision, string RoleKey, int? ExpectedPermissionVersion, long? ExpectedMetadataRevision,
    OfficialRoleMetadataValue Metadata, IReadOnlyList<OrganizationCapabilityPermission>? Permissions);
internal sealed record OfficialRoleJournalReceipt(long PolicyRevision, long AuditSequence);
internal sealed record OfficialRoleJournalRecord(string RequestId, string OperationId, OfficialRoleJournalIntent Intent,
    string Fingerprint, string BridgeFingerprint, DateTimeOffset RequestedAt, string Phase,
    string? Error = null, OfficialRoleJournalReceipt? Receipt = null);

internal sealed partial class AnnouncementAttemptJournal
{
    private sealed record RoleEnvelope(int SchemaVersion, string Partition, string Origin,
        AnnouncementJournalRecord[] Items, OfficialRoleJournalRecord[] RoleItems);
    internal static string RoleOperationId(string account, Uri origin, string requestId) => Hash(new
    { Domain = "StarBridge.OfficialRole.Operation.v1", Partition = Partition(account, origin), RequestId = requestId });
    internal static string RoleFingerprint(OfficialRoleJournalIntent intent) => Hash(new
    { Domain = "StarBridge.OfficialRole.Intent.v1", Intent = intent });
    internal static string RoleKind(string action) => action switch
    {
        "create" => "roles.permissions",
        "metadata" => "roles.metadata",
        _ => throw new InvalidDataException("Unknown role operation.")
    };

    private static void StrictRoleEnvelope(JsonElement root)
    {
        Keys(root, "schemaVersion", "partition", "origin", "items", "roleItems");
        var roles = root.GetProperty("roleItems"); var announcements = root.GetProperty("items");
        StrictAnnouncementItems(announcements);
        if (roles.ValueKind != JsonValueKind.Array || roles.GetArrayLength() > MaximumEntries ||
            roles.GetArrayLength() + announcements.GetArrayLength() > MaximumEntries) throw new InvalidDataException("Recovery capacity.");
        foreach (var row in roles.EnumerateArray())
        {
            Keys(row, "requestId", "operationId", "intent", "fingerprint", "bridgeFingerprint", "requestedAt", "phase", "error", "receipt");
            var intent = row.GetProperty("intent");
            Keys(intent, "sourceRef", "scopeKey", "authorityBinding", "action", "policyRevision", "roleKey",
                "expectedPermissionVersion", "expectedMetadataRevision", "metadata", "permissions");
            Keys(intent.GetProperty("metadata"), "displayName", "description", "color", "sortOrder");
            var permissions = intent.GetProperty("permissions");
            if (permissions.ValueKind != JsonValueKind.Null)
            {
                if (permissions.ValueKind != JsonValueKind.Array || permissions.GetArrayLength() > OrganizationCapabilityCatalog.Implemented.Count)
                    throw new InvalidDataException("Invalid role rights.");
                foreach (var permission in permissions.EnumerateArray()) Keys(permission, "capability", "canUse", "canDelegate");
            }
            if (row.GetProperty("receipt").ValueKind != JsonValueKind.Null)
                Keys(row.GetProperty("receipt"), "policyRevision", "auditSequence");
        }
    }

    private static void ValidateRole(OfficialRoleJournalRecord? row, string account, Uri origin, DateTimeOffset now)
    {
        if (row is null || !Hex(row.RequestId, 32) || row.OperationId != RoleOperationId(account, origin, row.RequestId) ||
            !Hex(row.BridgeFingerprint, 64) || row.Intent is not { } intent || row.Fingerprint != RoleFingerprint(intent) ||
            row.RequestedAt.Offset != TimeSpan.Zero || row.RequestedAt > now.AddMinutes(5) ||
            row.Phase is not ("prepared" or "sendStarted" or "unknown" or "accepted" or "rejected")) throw new InvalidDataException("Invalid role recovery record.");
        if (intent.SourceRef is not { } source || !Regex.IsMatch(source, "^officialFleet:[1-9][0-9]{0,18}$") ||
            !long.TryParse(source[14..], System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var id) || id <= 0 ||
            !Hex(intent.ScopeKey, 64) || !Hex(intent.AuthorityBinding, 64) || intent.PolicyRevision < 0 ||
            intent.Action is not ("create" or "metadata") || !RoleText(intent.RoleKey, 256) || intent.Metadata is not { } metadata ||
            !RoleText(metadata.DisplayName, 64) || !RoleText(metadata.Color, 32) || metadata.Description is null || metadata.Description.Length > 1024 ||
            metadata.Description.Any(c => char.IsControl(c) && c is not ('\r' or '\n' or '\t'))) throw new InvalidDataException("Invalid role recovery intent.");
        if (intent.Action == "create")
        {
            if (intent.ExpectedMetadataRevision is not null || intent.ExpectedPermissionVersion is not null || intent.Permissions is null ||
                intent.Permissions.Count > OrganizationCapabilityCatalog.Implemented.Count ||
                intent.Permissions.Any(p => p is null || !OrganizationCapabilityCatalog.IsSupported(p.Capability) || p.CanDelegate && !p.CanUse) ||
                !intent.Permissions.Select(p => p.Capability).SequenceEqual(intent.Permissions.Select(p => p.Capability).Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal)))
                throw new InvalidDataException("Invalid role creation.");
        }
        else if (intent.Permissions is not null || intent.ExpectedPermissionVersion is not > 0 || intent.ExpectedMetadataRevision is not >= 0)
            throw new InvalidDataException("Invalid role metadata change.");
        if (row.Phase == "accepted")
        {
            if (row.Error is not null || row.Receipt is not { } receipt || intent.PolicyRevision == long.MaxValue ||
                receipt.PolicyRevision != intent.PolicyRevision + 1 || receipt.AuditSequence != receipt.PolicyRevision)
                throw new InvalidDataException("Invalid role receipt.");
        }
        else if (row.Receipt is not null || row.Phase is "prepared" or "sendStarted" && row.Error is not null ||
            row.Phase == "unknown" && row.Error != "outcomeUnknown" ||
            row.Phase == "rejected" && row.Error is not ("dataInvalid" or "notAllowed" or "rolesChanged" or "refreshRequired" or "unavailable" or "localRecoveryUnavailable"))
            throw new InvalidDataException("Invalid role outcome.");
    }
    private static bool RoleText(string? value, int limit) => !string.IsNullOrWhiteSpace(value) && value.Length <= limit &&
        value == value.Trim() && !value.Any(char.IsControl);

    internal sealed partial class Session
    {
        internal OfficialRoleJournalRecord? FindRole(string id) => _roleRows.GetValueOrDefault(id);
        internal OfficialRoleJournalRecord[] RoleItems => _roleRows.Values.ToArray();
        internal async Task SaveRoleAsync(OfficialRoleJournalRecord item)
        {
            if (_roleRows.TryGetValue(item.RequestId, out var old))
            {
                if (old.OperationId != item.OperationId || old.Fingerprint != item.Fingerprint ||
                    old.BridgeFingerprint != item.BridgeFingerprint || old.RequestedAt != item.RequestedAt ||
                    RoleFingerprint(old.Intent) != RoleFingerprint(item.Intent)) throw new InvalidDataException("Role intent is immutable.");
                if (old.Phase != item.Phase && (old.Phase, item.Phase) is not
                    (("prepared", "sendStarted") or ("prepared", "unknown") or ("prepared", "rejected") or
                     ("sendStarted", "unknown") or ("sendStarted", "accepted") or ("sendStarted", "rejected") or ("unknown", "accepted")))
                    throw new InvalidDataException("Invalid role recovery transition.");
                if (old.Phase is "accepted" or "rejected" && (old.Phase != item.Phase || old.Error != item.Error || old.Receipt != item.Receipt))
                    throw new InvalidDataException("Confirmed role result is immutable.");
            }
            else if (item.Phase != "prepared") throw new InvalidDataException("New role operation must be prepared.");
            var announcements = new Dictionary<string, AnnouncementJournalRecord>(_rows, StringComparer.Ordinal);
            var roles = new Dictionary<string, OfficialRoleJournalRecord>(_roleRows, StringComparer.Ordinal);
            if (!roles.ContainsKey(item.RequestId)) MakeRoom(announcements, roles);
            roles[item.RequestId] = item;
            await _persist(announcements, roles, 2, item.Phase);
            _rows = announcements; _roleRows = roles; _schemaVersion = 2;
        }
        private static void MakeRoom(Dictionary<string, AnnouncementJournalRecord> announcements, Dictionary<string, OfficialRoleJournalRecord> roles)
        {
            if (announcements.Count + roles.Count < MaximumEntries) return;
            var terminal = announcements.Values.Where(r => r.Phase is "accepted" or "rejected").Select(r => (r.RequestId, r.RequestedAt, Role: false))
                .Concat(roles.Values.Where(r => r.Phase is "accepted" or "rejected").Select(r => (r.RequestId, r.RequestedAt, Role: true)))
                .OrderBy(r => r.RequestedAt).ThenBy(r => r.RequestId, StringComparer.Ordinal).ThenBy(r => r.Role).ToArray();
            if (terminal.Length == 0) throw new InvalidDataException("Recovery capacity exhausted by unresolved operations.");
            var oldest = terminal[0];
            if (oldest.Role) roles.Remove(oldest.RequestId); else announcements.Remove(oldest.RequestId);
        }
    }
}
