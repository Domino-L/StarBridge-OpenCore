using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using StarBridge.Core.FleetAnnouncements;

namespace StarBridge.HostRuntime.Communities;

internal sealed record AnnouncementJournalIntent(string SourceRef, string ScopeKey, string AuthorityBinding, string Action,
    long PolicyRevision, long TimelineRevision, string? AnnouncementId, int? ItemRevision, string? Title, string? Content);
internal sealed record AnnouncementJournalReceipt(long PolicyRevision, long TimelineRevision, long AuditSequence);
internal sealed record AnnouncementJournalRecord(string RequestId, string OperationId, AnnouncementJournalIntent Intent,
    string Fingerprint, string BridgeFingerprint, DateTimeOffset RequestedAt, string Phase,
    string? Error = null, AnnouncementJournalReceipt? Receipt = null);

// A local recovery record, not membership, management permission or Server audit authority.
internal sealed partial class AnnouncementAttemptJournal
{
    internal const int MaximumEntries = 128, MaximumPlainBytes = 1024 * 1024, MaximumCipherBytes = 2 * 1024 * 1024;
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private readonly string _root;
    private readonly TimeProvider _clock;
    private readonly Action<string>? _beforeReplace;
    internal AnnouncementAttemptJournal(string? root = null, TimeProvider? clock = null, Action<string>? beforeReplace = null)
    {
        _root = Path.GetFullPath(root ?? Path.Combine(HostDataRoot.CurrentRoot, "official-fleet-announcement-operations"));
        _clock = clock ?? TimeProvider.System;
        _beforeReplace = beforeReplace; // Internal deterministic IO seam; no runtime setting/HTTP selector.
    }
    private sealed record Envelope(int SchemaVersion, string Partition, string Origin, AnnouncementJournalRecord[] Items);
    internal static string Partition(string account, Uri origin) => Hash(new
    { Domain = "StarBridge.OfficialAnnouncement.JournalPartition.v1", Account = account, Origin = origin.GetLeftPart(UriPartial.Authority) });
    internal static string OperationId(string account, Uri origin, string requestId) => Hash(new
    { Domain = "StarBridge.OfficialAnnouncement.Operation.v1", Partition = Partition(account, origin), RequestId = requestId });
    internal static string Fingerprint(AnnouncementJournalIntent intent) => Hash(new
    { Domain = "StarBridge.OfficialAnnouncement.Intent.v1", Intent = intent });
    private static string Hash(object value) => Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(value, Json))).ToLowerInvariant();
    internal static bool Hex(string? value, int length) => value is not null && value.Length == length &&
        value.All(c => c is >= 'a' and <= 'f' or >= '0' and <= '9');

    internal async Task<T> RunAsync<T>(string account, Uri origin, Func<Session, Task<T>> action, Action current, CancellationToken token)
    {
        if (string.IsNullOrWhiteSpace(account) || account.Length > 8192 || !origin.IsAbsoluteUri ||
            origin.UserInfo.Length != 0 || origin.Query.Length != 0 || origin.Fragment.Length != 0 ||
            origin.Scheme != "https" && !(origin.Scheme == "http" && origin.IsLoopback)) throw new InvalidDataException("Invalid recovery partition.");
        current(); token.ThrowIfCancellationRequested();
        var partition = Partition(account, origin); var originText = origin.GetLeftPart(UriPartial.Authority);
        Directory.CreateDirectory(_root);
        var path = Path.Combine(_root, partition + ".dat");
        using var lease = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        var entropy = Encoding.UTF8.GetBytes("StarBridge.OfficialAnnouncement.Journal.v1:" + partition);
        var rows = new Dictionary<string, AnnouncementJournalRecord>(StringComparer.Ordinal);
        var roleRows = new Dictionary<string, OfficialRoleJournalRecord>(StringComparer.Ordinal);
        var schemaVersion = 1;
        if (File.Exists(path))
        {
            using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            if (file.Length is <= 0 or > MaximumCipherBytes) throw new InvalidDataException("Recovery size limit.");
            var encrypted = new byte[(int)file.Length];
            await file.ReadExactlyAsync(encrypted, token);
            var clear = ProtectedData.Unprotect(encrypted, entropy, DataProtectionScope.CurrentUser);
            try
            {
                if (clear.Length > MaximumPlainBytes) throw new InvalidDataException("Recovery size limit.");
                using var document = JsonDocument.Parse(clear);
                var root = document.RootElement;
                if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("schemaVersion", out var version) ||
                    version.ValueKind != JsonValueKind.Number || !version.TryGetInt32(out schemaVersion))
                    throw new InvalidDataException("Invalid recovery document.");
                AnnouncementJournalRecord[] items;
                if (schemaVersion == 1)
                {
                    StrictEnvelope(root);
                    var stored = JsonSerializer.Deserialize<Envelope>(clear, Json) ?? throw new InvalidDataException("Invalid recovery document.");
                    if (stored.Partition != partition || stored.Origin != originText || stored.Items is null)
                        throw new InvalidDataException("Invalid recovery document.");
                    items = stored.Items;
                }
                else if (schemaVersion == 2)
                {
                    StrictRoleEnvelope(root);
                    var stored = JsonSerializer.Deserialize<RoleEnvelope>(clear, Json) ?? throw new InvalidDataException("Invalid recovery document.");
                    if (stored.Partition != partition || stored.Origin != originText || stored.Items is null || stored.RoleItems is null ||
                        stored.Items.Length + stored.RoleItems.Length > MaximumEntries) throw new InvalidDataException("Invalid recovery document.");
                    items = stored.Items;
                    foreach (var item in stored.RoleItems)
                    {
                        ValidateRole(item, account, origin, _clock.GetUtcNow());
                        if (!roleRows.TryAdd(item.RequestId, item)) throw new InvalidDataException("Duplicate role recovery request.");
                    }
                }
                else throw new InvalidDataException("Invalid recovery document.");
                foreach (var item in items)
                {
                    Validate(item, account, origin, _clock.GetUtcNow());
                    if (!rows.TryAdd(item.RequestId, item)) throw new InvalidDataException("Duplicate recovery request.");
                }
            }
            finally { CryptographicOperations.ZeroMemory(clear); }
        }
        current(); token.ThrowIfCancellationRequested();
        return await action(new Session(rows, roleRows, schemaVersion, async (candidate, candidateRoles, nextVersion, phase) =>
        {
            if (candidate.Count + candidateRoles.Count > MaximumEntries || nextVersion is not (1 or 2) ||
                nextVersion == 1 && candidateRoles.Count != 0) throw new InvalidDataException("Invalid recovery document.");
            foreach (var item in candidate.Values) Validate(item, account, origin, _clock.GetUtcNow());
            foreach (var item in candidateRoles.Values) ValidateRole(item, account, origin, _clock.GetUtcNow());
            var clear = nextVersion == 1
                ? JsonSerializer.SerializeToUtf8Bytes(new Envelope(1, partition, originText, candidate.Values.ToArray()), Json)
                : JsonSerializer.SerializeToUtf8Bytes(new RoleEnvelope(2, partition, originText, candidate.Values.ToArray(), candidateRoles.Values.ToArray()), Json);
            byte[] encrypted;
            try
            {
                if (clear.Length > MaximumPlainBytes) throw new InvalidDataException("Recovery size limit.");
                encrypted = ProtectedData.Protect(clear, entropy, DataProtectionScope.CurrentUser);
            }
            finally { CryptographicOperations.ZeroMemory(clear); }
            if (encrypted.Length > MaximumCipherBytes) throw new InvalidDataException("Recovery size limit.");
            var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            var created = false;
            try
            {
                using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                    4096, FileOptions.Asynchronous | FileOptions.WriteThrough))
                {
                    created = true;
                    await file.WriteAsync(encrypted, token);
                    file.Flush(true);
                }
                current(); token.ThrowIfCancellationRequested();
                _beforeReplace?.Invoke(phase);
                File.Move(temporary, path, true);
            }
            finally { if (created && File.Exists(temporary)) File.Delete(temporary); }
        }));
    }

    internal sealed partial class Session
    {
        private Dictionary<string, AnnouncementJournalRecord> _rows;
        private Dictionary<string, OfficialRoleJournalRecord> _roleRows;
        private int _schemaVersion;
        private readonly Func<Dictionary<string, AnnouncementJournalRecord>, Dictionary<string, OfficialRoleJournalRecord>, int, string, Task> _persist;
        internal Session(Dictionary<string, AnnouncementJournalRecord> rows, Dictionary<string, OfficialRoleJournalRecord> roleRows,
            int schemaVersion, Func<Dictionary<string, AnnouncementJournalRecord>, Dictionary<string, OfficialRoleJournalRecord>, int, string, Task> persist)
        { _rows = rows; _roleRows = roleRows; _schemaVersion = schemaVersion; _persist = persist; }
        internal AnnouncementJournalRecord? Find(string id) => _rows.GetValueOrDefault(id);
        internal AnnouncementJournalRecord[] Items => _rows.Values.ToArray();
        internal async Task SaveAsync(AnnouncementJournalRecord item)
        {
            if (_rows.TryGetValue(item.RequestId, out var old))
            {
                if ((old with { Phase = item.Phase, Error = item.Error, Receipt = item.Receipt }) != item)
                    throw new InvalidDataException("Recovery intent is immutable.");
                if (old.Phase != item.Phase && (old.Phase, item.Phase) is not
                    (("prepared", "sendStarted") or ("prepared", "unknown") or ("prepared", "rejected") or
                     ("sendStarted", "unknown") or ("sendStarted", "accepted") or ("sendStarted", "rejected") or
                     ("unknown", "accepted")))
                    throw new InvalidDataException("Invalid recovery phase transition.");
                if (old.Phase is "accepted" or "rejected" && old != item)
                    throw new InvalidDataException("Confirmed recovery result is immutable.");
            }
            else if (item.Phase != "prepared") throw new InvalidDataException("New recovery request must be prepared.");
            var candidate = new Dictionary<string, AnnouncementJournalRecord>(_rows, StringComparer.Ordinal);
            var candidateRoles = new Dictionary<string, OfficialRoleJournalRecord>(_roleRows, StringComparer.Ordinal);
            if (!candidate.ContainsKey(item.RequestId)) MakeRoom(candidate, candidateRoles);
            candidate[item.RequestId] = item;
            await _persist(candidate, candidateRoles, _schemaVersion, item.Phase);
            _rows = candidate; _roleRows = candidateRoles; // Never expose a phase before durable replacement.
        }
    }

    private static void Validate(AnnouncementJournalRecord? row, string account, Uri origin, DateTimeOffset now)
    {
        if (row is null || !Hex(row.RequestId, 32) || row.OperationId != OperationId(account, origin, row.RequestId) ||
            !Hex(row.BridgeFingerprint, 64) || row.Intent is not { } intent || row.Fingerprint != Fingerprint(intent) ||
            row.RequestedAt.Offset != TimeSpan.Zero || row.RequestedAt > now.AddMinutes(5) ||
            row.Phase is not ("prepared" or "sendStarted" or "unknown" or "accepted" or "rejected"))
            throw new InvalidDataException("Invalid recovery record.");
        if (intent.SourceRef is not { } sourceRef || !Regex.IsMatch(sourceRef, "^officialFleet:[1-9][0-9]{0,18}$") ||
            !long.TryParse(sourceRef[14..], System.Globalization.NumberStyles.None,
                System.Globalization.CultureInfo.InvariantCulture, out var id) || id <= 0 ||
            !Hex(intent.ScopeKey, 64) || !Hex(intent.AuthorityBinding, 64) || intent.PolicyRevision < 0 || intent.TimelineRevision < 0 ||
            intent.Action is not ("publish" or "edit" or "withdraw")) throw new InvalidDataException("Invalid recovery intent.");
        if (intent.Action == "publish" ? intent.AnnouncementId is not null || intent.ItemRevision is not null :
            string.IsNullOrWhiteSpace(intent.AnnouncementId) || intent.AnnouncementId.Length > 128 ||
            intent.AnnouncementId.Any(char.IsControl) || intent.ItemRevision is not > 0)
            throw new InvalidDataException("Invalid recovery item.");
        if (intent.Action == "withdraw")
        {
            if (intent.Title is not null || intent.Content is not null) throw new InvalidDataException("Invalid recovery content.");
        }
        else
        {
            if (intent.Title is null || intent.Content is null) throw new InvalidDataException("Invalid recovery content.");
            var normalized = FleetAnnouncementPolicy.Normalize(intent.Title, intent.Content);
            if (normalized.Error is not null || normalized.Title != intent.Title || normalized.Content != intent.Content)
                throw new InvalidDataException("Invalid recovery content.");
        }
        if (row.Phase == "accepted")
        {
            if (row.Error is not null || row.Receipt is not { } receipt || intent.PolicyRevision == long.MaxValue ||
                intent.TimelineRevision == long.MaxValue || receipt.PolicyRevision != intent.PolicyRevision + 1 ||
                receipt.TimelineRevision != intent.TimelineRevision + 1 || receipt.AuditSequence != receipt.PolicyRevision)
                throw new InvalidDataException("Invalid recovery receipt.");
        }
        else if (row.Receipt is not null || row.Phase is "prepared" or "sendStarted" && row.Error is not null ||
            row.Phase == "unknown" && row.Error != "outcomeUnknown" ||
            row.Phase == "rejected" && row.Error is not ("dataInvalid" or "notAllowed" or "announcementsChanged" or "refreshRequired" or "unavailable" or "localRecoveryUnavailable"))
            throw new InvalidDataException("Invalid recovery phase outcome.");
    }

    private static void Keys(JsonElement value, params string[] keys)
    {
        if (value.ValueKind != JsonValueKind.Object ||
            !value.EnumerateObject().Select(p => p.Name).Order(StringComparer.Ordinal).SequenceEqual(keys.Order(StringComparer.Ordinal)))
            throw new InvalidDataException("Invalid recovery fields.");
    }
    private static void StrictEnvelope(JsonElement root)
    {
        Keys(root, "schemaVersion", "partition", "origin", "items");
        StrictAnnouncementItems(root.GetProperty("items"));
    }
    private static void StrictAnnouncementItems(JsonElement items)
    {
        if (items.ValueKind != JsonValueKind.Array || items.GetArrayLength() > MaximumEntries)
            throw new InvalidDataException("Invalid recovery items.");
        foreach (var row in items.EnumerateArray())
        {
            Keys(row, "requestId", "operationId", "intent", "fingerprint", "bridgeFingerprint", "requestedAt", "phase", "error", "receipt");
            Keys(row.GetProperty("intent"), "sourceRef", "scopeKey", "authorityBinding", "action", "policyRevision",
                "timelineRevision", "announcementId", "itemRevision", "title", "content");
            if (row.GetProperty("receipt").ValueKind != JsonValueKind.Null)
                Keys(row.GetProperty("receipt"), "policyRevision", "timelineRevision", "auditSequence");
        }
    }
}
