using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Notifications;

internal sealed record NotificationTypeRule(string Type, string Mode)
{
    [JsonExtensionData] public Dictionary<string, JsonElement>? Extra { get; init; }
}
internal sealed record NotificationQuietHours(bool Enabled = false, int StartMinute = 1320, int EndMinute = 480, string Clock = "local")
{
    [JsonExtensionData] public Dictionary<string, JsonElement>? Extra { get; init; }
}
internal sealed record NotificationPolicyRule(string Source, NotificationSourceMode Mode)
{
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] public NotificationTypeRule[]? TypeRules { get; init; }
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] public NotificationQuietHours? QuietHours { get; init; }
    [JsonExtensionData] public Dictionary<string, JsonElement>? Extra { get; init; }
}
internal sealed record NotificationPolicySnapshot(long Revision, string? OperationId, NotificationPolicyRule[] Rules)
{
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public Dictionary<string, long>? SuppressionRevisions { get; init; }
    [JsonExtensionData] public Dictionary<string, JsonElement>? Extra { get; init; }
    internal NotificationSourceMode For(string source) => Rules.FirstOrDefault(rule => rule.Source == source)?.Mode ?? NotificationSourceMode.Normal;
    internal NotificationPolicyRule Rule(string source) => Rules.FirstOrDefault(rule => rule.Source == source) ?? new(source, NotificationSourceMode.Normal);
    internal long SuppressionRevision(string source) => SuppressionRevisions?.GetValueOrDefault(source) ?? 0;
}

// Separate account-scoped delivery preferences, never a privacy grant. The
// owner and source identities are stable across launches, unlike live UI refs.
internal sealed class NotificationPolicyStore(string root)
{
    private const int SaveByteLimit = 131072;
    private const int ReconciledByteLimit = SaveByteLimit * 2;
    private readonly string _legacyDirectory = Path.Combine(Path.GetFullPath(root), "notification-policies-v1");
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "notification-policies-v2");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) {
        MaxDepth = 12, PropertyNameCaseInsensitive = false
    };
    private sealed record FileValue(int SchemaVersion, string Owner, NotificationPolicySnapshot Snapshot, string Integrity)
    {
        public string? LegacyFingerprint { get; init; }
        [JsonExtensionData] public Dictionary<string, JsonElement>? Extra { get; init; }
    }
    internal static string Organization(string code, DateTimeOffset joined) => "organization:" + Hash(
        JsonSerializer.SerializeToUtf8Bytes(new[] { code.ToUpperInvariant(), joined.ToUniversalTime().ToString("O") }));
    internal static string OfficialFleet(string sourceRef)
    {
        if (!System.Text.RegularExpressions.Regex.IsMatch(sourceRef, "^officialFleet:[1-9][0-9]{0,18}$") ||
            !long.TryParse(sourceRef[14..], out var id) || id <= 0) throw new InvalidDataException("Invalid official source.");
        return "officialFleet:" + Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { sourceRef }));
    }
    internal static bool IsOfficialFleetKey(string source) => source is { Length: 78 } &&
        source.StartsWith("officialFleet:", StringComparison.Ordinal) && source[14..].All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f');
    private static string Hash(byte[] value) => Convert.ToHexString(SHA256.HashData(value)).ToLowerInvariant();
    private static string Owner(BridgeAccountContext owner)
    {
        if (!owner.IsComplete || new[] { owner.Environment, owner.Authority, owner.Subject }
            .Any(value => value.Length > 2048 || value.Any(char.IsControl))) throw new InvalidDataException("Invalid policy owner.");
        return Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { owner.Environment, owner.Authority, owner.Subject }));
    }
    private static string Integrity(string owner, NotificationPolicySnapshot snapshot) =>
        Hash(JsonSerializer.SerializeToUtf8Bytes(new { owner, snapshot }, Json));
    private static string Integrity(string owner, JsonElement snapshot) =>
        Hash(JsonSerializer.SerializeToUtf8Bytes(new { owner, snapshot }, Json));
    private static string IntegrityV2(string owner, JsonElement snapshot, string? legacyFingerprint) =>
        Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 2, owner, snapshot, legacyFingerprint }, Json));
    private static NotificationPolicyRule[] Validate(NotificationPolicyRule[] rules, int maximum = 256)
    {
        if (rules is null || rules.Length > maximum || rules.Any(rule => rule is null || !Enum.IsDefined(rule.Mode) ||
            !(rule.Source is "room" or "friends" or "directMessages" || IsOfficialFleetKey(rule.Source) || rule.Source is { Length: 77 } source &&
                source.StartsWith("organization:", StringComparison.Ordinal) && source[13..].All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f'))) ||
            rules.Select(rule => rule.Source).Distinct(StringComparer.Ordinal).Count() != rules.Length) throw new InvalidDataException("Invalid source rules.");
        foreach (var rule in rules) {
            if (rule.TypeRules is { } types && (types.Length > 3 || types.Any(t => t is null ||
                t.Type is not ("chat" or "announcement" or "activity") || t.Mode is not ("inherit" or "enabled" or "disabled")) ||
                types.Select(t => t.Type).Distinct().Count() != types.Length)) throw new InvalidDataException("Invalid notification types.");
            if (rule.QuietHours is { } q && (q.Clock != "local" || q.StartMinute is < 0 or > 1439 ||
                q.EndMinute is < 0 or > 1439 || q.StartMinute == q.EndMinute)) throw new InvalidDataException("Invalid quiet hours.");
        }
        return rules.OrderBy(rule => rule.Source, StringComparer.Ordinal).ToArray();
    }
    private string LegacyFingerprint(string hash)
    {
        CheckPath(_legacyDirectory, true);
        var path = Path.Combine(_legacyDirectory, hash + ".json"); CheckPath(path);
        if (!File.Exists(path)) return "missing";
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
        // Fingerprint the actual bytes even when the legacy document is invalid
        // (including empty/oversize). Parsing limits belong to ReadFile.
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }
    private FileValue? ReadFile(string hash, bool v2)
    {
        CheckPath(_directory, true);
        var modern = Path.Combine(_directory, hash + ".json"); CheckPath(modern);
        var directory = v2 ? _directory : _legacyDirectory;
        var path = v2 ? modern : Path.Combine(directory, hash + ".json");
        CheckPath(directory, true); CheckPath(path);
        if (!File.Exists(path)) return null;
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
        if (stream.Length is <= 0 || stream.Length > (v2 ? ReconciledByteLimit : 32768)) throw new InvalidDataException("Invalid policy file.");
        try {
            using var doc = JsonDocument.Parse(stream, new JsonDocumentOptions { MaxDepth = v2 ? 12 : 6 });
            Unique(doc.RootElement);
            var file = doc.RootElement.Deserialize<FileValue>(Json);
            if (file is null || file.SchemaVersion != (v2 ? 2 : 1) || file.Owner != hash || file.Snapshot is null ||
                file.Snapshot.Revision < 1 || !Guid.TryParseExact(file.Snapshot.OperationId, "N", out _) ||
                file.Snapshot.SuppressionRevisions?.Any(p => p.Value < 1 || p.Value > file.Snapshot.Revision) == true ||
                file.Integrity != (v2 ? IntegrityV2(hash, doc.RootElement.GetProperty("snapshot"), file.LegacyFingerprint) :
                    Integrity(hash, doc.RootElement.GetProperty("snapshot")))) throw new InvalidDataException("Invalid policy file.");
            return file with { Snapshot = file.Snapshot with { Rules = Validate(file.Snapshot.Rules, v2 ? 256 : 128) } };
        } catch (Exception error) {
            // Every decoding/validation failure means this generation is corrupt.
            // Keep path, open and writer-lock failures outside this boundary.
            throw new InvalidDataException("Invalid policy file.", error);
        }
    }
    private FileStream Lock(string directory, string hash)
    {
        CheckPath(directory, true); Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, hash + ".json.lock"); CheckPath(path);
        return new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
    }
    // Caller holds both generations' writer locks, always v2 before v1.
    private FileValue? ReadCurrent(string hash, Func<bool> current, bool saving = false)
    {
        FileValue? modern;
        try { modern = ReadFile(hash, true); }
        catch (InvalidDataException) {
            // Bad v2 must not hide a usable v1. Preserve the damaged file until
            // the next explicit save; no extended settings can be trusted here.
            return ReadLegacy(hash);
        }
        if (modern is null) return ReadLegacy(hash);
        var fingerprint = LegacyFingerprint(hash);
        if (modern.LegacyFingerprint == fingerprint) return modern;
        NotificationPolicySnapshot legacy;
        try { legacy = ReadLegacy(hash)?.Snapshot ?? new(0, null, []); }
        catch (InvalidDataException) {
            // Damaged v1 means unknown old-version state, not default modes.
            // Keep all valid v2 values; an explicit save records the damaged
            // bytes' fingerprint without ever replacing v1.
            return modern;
        }
        var previous = modern.Snapshot;
        if (previous.Revision == long.MaxValue) throw new InvalidDataException("Policy revision exhausted.");
        var revision = previous.Revision + 1;
        var rules = Merge(previous.Rules, legacy.Rules, false);
        // A manually expanded file can make the union exceed both generations'
        // combined capacity. Use the readable v2 without rewriting either file.
        if (rules.Length > 256) return modern;
        rules = Validate(rules);
        var suppressions = previous.SuppressionRevisions is { } saved ? new Dictionary<string, long>(saved) : new();
        foreach (var rule in rules.Where(r => r.Mode != NotificationSourceMode.Normal && r.Mode != previous.For(r.Source)))
            suppressions[rule.Source] = revision;
        var snapshot = previous with { Revision = revision, OperationId = Guid.NewGuid().ToString("N"), Rules = rules,
            SuppressionRevisions = suppressions.Count == 0 ? null : suppressions };
        // Only v2 is replaced atomically. A crash leaves either the old v2
        // (reconciliation retries) or the complete new v2, with v1 untouched.
        try { Write(hash, snapshot, fingerprint, modern.Extra, current, ReconciledByteLimit); }
        catch (Exception error) {
            // A best-effort repair must never hide the complete in-memory union.
            // Leave the on-disk fingerprint untouched so a later save retries.
            if (saving) {
                if (error is OperationCanceledException or NotificationSettingsConflictException) throw;
                throw new NotificationPolicySaveException(error);
            }
            return modern with { Snapshot = snapshot };
        }
        return modern with { Snapshot = snapshot, LegacyFingerprint = fingerprint };
    }
    private FileValue? ReadLegacy(string hash)
    {
        var file = ReadFile(hash, false);
        return file is null ? null : file with { Snapshot = file.Snapshot with {
            Rules = file.Snapshot.Rules.Select(r => new NotificationPolicyRule(r.Source, r.Mode)).ToArray() } };
    }
    internal NotificationPolicySnapshot Read(BridgeAccountContext owner)
    {
        var hash = Owner(owner);
        CheckPath(_directory, true);
        var path = Path.Combine(_directory, hash + ".json"); CheckPath(path);
        if (!File.Exists(path)) return ReadLegacy(hash)?.Snapshot ?? new(0, null, []);
        using var writeLock = Lock(_directory, hash);
        using var legacyLock = Lock(_legacyDirectory, hash);
        return ReadCurrent(hash, () => true)?.Snapshot ?? new(0, null, []);
    }
    internal NotificationPolicySnapshot Save(BridgeAccountContext owner, long expected, string operationId,
        NotificationPolicyRule[] rules, Func<bool> current, bool extended = false)
    {
        rules = Validate(rules);
        if (expected < 0 || expected == long.MaxValue || !Guid.TryParseExact(operationId, "N", out _)) throw new InvalidDataException();
        var hash = Owner(owner);
        if (!current()) throw new OperationCanceledException();
        using var writeLock = Lock(_directory, hash);
        using var legacyLock = Lock(_legacyDirectory, hash);
        var previousFile = ReadCurrent(hash, current, saving: true);
        var previous = previousFile?.Snapshot ?? new(0, null, []);
        var legacyFingerprint = LegacyFingerprint(hash);
        var addsSource = rules.Any(rule => !previous.Rules.Any(old => old.Source == rule.Source));
        rules = Validate(Merge(previous.Rules, rules, extended));
        // Reconciled sources remain editable, even above the new-source limit.
        // Never make room for a new source by discarding an existing extension.
        if (addsSource && rules.Length > 128) throw new InvalidDataException("Source limit reached.");
        if (!current()) throw new OperationCanceledException();
        if (previous.OperationId == operationId && previous.Revision == expected + 1 &&
            JsonSerializer.Serialize(previous.Rules, Json) == JsonSerializer.Serialize(rules, Json)) return previous;
        if (previous.Revision != expected || previous.OperationId == operationId) throw new NotificationSettingsConflictException();
        var suppressions = previous.SuppressionRevisions is { } saved ? new Dictionary<string, long>(saved) : new();
        foreach (var rule in rules.Where(rule => rule.Mode != NotificationSourceMode.Normal && rule.Mode != previous.For(rule.Source)))
            suppressions[rule.Source] = expected + 1;
        foreach (var rule in rules) {
            var old = previous.Rule(rule.Source);
            foreach (var type in (rule.TypeRules ?? []).Where(t => t.Mode == "disabled" &&
                old.TypeRules?.FirstOrDefault(o => o.Type == t.Type)?.Mode != "disabled"))
                suppressions[rule.Source + "#" + type.Type] = suppressions[rule.Source] = expected + 1;
            if (rule.QuietHours is { Enabled: true } && JsonSerializer.Serialize(rule.QuietHours, Json) != JsonSerializer.Serialize(old.QuietHours, Json))
                suppressions[rule.Source + "#quiet"] = suppressions[rule.Source] = expected + 1;
        }
        var snapshot = new NotificationPolicySnapshot(expected + 1, operationId, rules) {
            SuppressionRevisions = suppressions.Count == 0 ? null : suppressions, Extra = previous.Extra };
        // Reconciled documents above 128 KiB remain editable without growth.
        // The normal budget only prevents a user save from making them larger.
        var maximum = Math.Min(ReconciledByteLimit, Math.Max(SaveByteLimit, previousFile is { SchemaVersion: 2 }
            ? Serialize(hash, previous, previousFile.LegacyFingerprint, previousFile.Extra).Length : 0));
        try { Write(hash, snapshot, legacyFingerprint, previousFile?.Extra, current, maximum); }
        catch (Exception error) when (error is IOException or InvalidDataException or UnauthorizedAccessException) {
            throw new NotificationPolicySaveException(error);
        }
        return snapshot;
    }
    private static byte[] Serialize(string hash, NotificationPolicySnapshot snapshot, string? legacyFingerprint,
        Dictionary<string, JsonElement>? extra) => JsonSerializer.SerializeToUtf8Bytes(new FileValue(2, hash, snapshot,
            IntegrityV2(hash, JsonSerializer.SerializeToElement(snapshot, Json), legacyFingerprint)) {
            LegacyFingerprint = legacyFingerprint, Extra = extra }, Json);
    private void Write(string hash, NotificationPolicySnapshot snapshot, string legacyFingerprint,
        Dictionary<string, JsonElement>? extra, Func<bool> current, int maximum)
    {
        var path = Path.Combine(_directory, hash + ".json");
        var bytes = Serialize(hash, snapshot, legacyFingerprint, extra);
        if (bytes.Length > maximum) throw new InvalidDataException("Policy byte limit reached.");
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try {
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough)) {
                file.Write(bytes); file.Flush(true);
            }
            CheckPath(_directory, true); CheckPath(path);
            if (!current()) throw new OperationCanceledException();
            if (LegacyFingerprint(hash) != legacyFingerprint) throw new NotificationSettingsConflictException();
            if (!File.Exists(path)) File.Move(temporary, path); else File.Replace(temporary, path, null);
        } finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    private static NotificationPolicyRule[] Merge(NotificationPolicyRule[] previous, NotificationPolicyRule[] incoming, bool extended)
    {
        var result = incoming.Select(rule => {
            var old = previous.FirstOrDefault(p => p.Source == rule.Source);
            if (old is null) return rule;
            var types = old.TypeRules;
            if (extended && rule.TypeRules is { } edits) types = edits.Select(t => t with {
                Extra = old.TypeRules?.FirstOrDefault(o => o.Type == t.Type)?.Extra
            }).Concat((old.TypeRules ?? []).Where(t => !edits.Any(e => e.Type == t.Type))).OrderBy(t => t.Type).ToArray();
            return rule with { Extra = old.Extra, TypeRules = types,
                QuietHours = extended && rule.QuietHours is { } q ? q with { Extra = old.QuietHours?.Extra } : old.QuietHours };
        }).ToList();
        // Older editors replace their complete list. Omission may reset a base
        // mode, but can never erase fields that editor cannot represent.
        // Incoming rows (current v1 on reconciliation) always take priority.
        // Preserve every extension-only row; capacity is checked by the caller.
        foreach (var old in previous.Where(p => !incoming.Any(r => r.Source == p.Source) &&
            (p.TypeRules != null || p.QuietHours != null || p.Extra != null))
            .OrderBy(p => p.Source, StringComparer.Ordinal))
            result.Add(old with { Mode = NotificationSourceMode.Normal });
        return result.OrderBy(rule => rule.Source, StringComparer.Ordinal).ToArray();
    }
    private static void CheckPath(string path, bool directory = false)
    {
        try {
            var attributes = File.GetAttributes(path);
            if (attributes.HasFlag(FileAttributes.ReparsePoint) || attributes.HasFlag(FileAttributes.Directory) != directory)
                throw new IOException("Invalid policy path.");
        }
        catch (FileNotFoundException) { } catch (DirectoryNotFoundException) { }
    }
    private static void Unique(JsonElement element)
    {
        if (element.ValueKind == JsonValueKind.Object) {
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var item in element.EnumerateObject()) { if (!names.Add(item.Name)) throw new JsonException(); Unique(item.Value); }
        } else if (element.ValueKind == JsonValueKind.Array) foreach (var item in element.EnumerateArray()) Unique(item);
    }
}

internal sealed class NotificationPolicySaveException(Exception inner)
    : Exception("Notification policy save failed.", inner);
