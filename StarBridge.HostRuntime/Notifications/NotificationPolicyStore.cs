using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Notifications;

internal sealed record NotificationPolicyRule(string Source, NotificationSourceMode Mode);
internal sealed record NotificationPolicySnapshot(long Revision, string? OperationId, NotificationPolicyRule[] Rules)
{
    internal NotificationSourceMode For(string source) => Rules.FirstOrDefault(rule => rule.Source == source)?.Mode ?? NotificationSourceMode.Normal;
}

// Separate account-scoped delivery preferences, never a privacy grant. The
// owner and source identities are stable across launches, unlike live UI refs.
internal sealed class NotificationPolicyStore(string root)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "notification-policies-v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) {
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, MaxDepth = 6
    };
    private sealed record FileValue(int SchemaVersion, string Owner, NotificationPolicySnapshot Snapshot, string Integrity);
    internal static string Organization(string code, DateTimeOffset joined) => "organization:" + Hash(
        JsonSerializer.SerializeToUtf8Bytes(new[] { code.ToUpperInvariant(), joined.ToUniversalTime().ToString("O") }));
    private static string Hash(byte[] value) => Convert.ToHexString(SHA256.HashData(value)).ToLowerInvariant();
    private static string Owner(BridgeAccountContext owner)
    {
        if (!owner.IsComplete || new[] { owner.Environment, owner.Authority, owner.Subject }
            .Any(value => value.Length > 2048 || value.Any(char.IsControl))) throw new InvalidDataException("Invalid policy owner.");
        return Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { owner.Environment, owner.Authority, owner.Subject }));
    }
    private static string Integrity(string owner, NotificationPolicySnapshot snapshot) =>
        Hash(JsonSerializer.SerializeToUtf8Bytes(new { owner, snapshot }, Json));
    private static NotificationPolicyRule[] Validate(NotificationPolicyRule[] rules)
    {
        if (rules is null || rules.Length > 128 || rules.Any(rule => rule is null || !Enum.IsDefined(rule.Mode) ||
            !(rule.Source is "room" or "friends" or "directMessages" || rule.Source is { Length: 77 } source &&
                source.StartsWith("organization:", StringComparison.Ordinal) && source[13..].All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f'))) ||
            rules.Select(rule => rule.Source).Distinct(StringComparer.Ordinal).Count() != rules.Length) throw new InvalidDataException("Invalid source rules.");
        return rules.OrderBy(rule => rule.Source, StringComparer.Ordinal).ToArray();
    }
    internal NotificationPolicySnapshot Read(BridgeAccountContext owner)
    {
        var hash = Owner(owner); var path = Path.Combine(_directory, hash + ".json");
        CheckPath(_directory, true); CheckPath(path);
        if (!File.Exists(path)) return new(0, null, []);
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
        if (stream.Length is <= 0 or > 32768) throw new InvalidDataException("Invalid policy file.");
        using var doc = JsonDocument.Parse(stream, new JsonDocumentOptions { MaxDepth = 6 });
        Unique(doc.RootElement);
        var file = doc.RootElement.Deserialize<FileValue>(Json);
        if (file is null || file.SchemaVersion != 1 || file.Owner != hash || file.Snapshot is null ||
            file.Snapshot.Revision < 1 || !Guid.TryParseExact(file.Snapshot.OperationId, "N", out _) ||
            file.Integrity != Integrity(hash, file.Snapshot)) throw new InvalidDataException("Invalid policy file.");
        return file.Snapshot with { Rules = Validate(file.Snapshot.Rules) };
    }
    internal NotificationPolicySnapshot Save(BridgeAccountContext owner, long expected, string operationId,
        NotificationPolicyRule[] rules, Func<bool> current)
    {
        rules = Validate(rules);
        if (expected < 0 || expected == long.MaxValue || !Guid.TryParseExact(operationId, "N", out _)) throw new InvalidDataException();
        var hash = Owner(owner); var path = Path.Combine(_directory, hash + ".json");
        if (!current()) throw new OperationCanceledException();
        CheckPath(_directory, true); Directory.CreateDirectory(_directory); CheckPath(path + ".lock");
        using var writeLock = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        var previous = Read(owner);
        if (!current()) throw new OperationCanceledException();
        if (previous.OperationId == operationId && previous.Revision == expected + 1 && previous.Rules.SequenceEqual(rules)) return previous;
        if (previous.Revision != expected || previous.OperationId == operationId) throw new NotificationSettingsConflictException();
        var snapshot = new NotificationPolicySnapshot(expected + 1, operationId, rules);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(new FileValue(1, hash, snapshot, Integrity(hash, snapshot)), Json);
        if (bytes.Length > 32768) throw new InvalidDataException();
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try {
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough)) {
                file.Write(bytes); file.Flush(true);
            }
            CheckPath(_directory, true); CheckPath(path);
            if (!current()) throw new OperationCanceledException();
            if (previous.Revision == 0) File.Move(temporary, path); else File.Replace(temporary, path, null);
            return snapshot;
        } finally { if (File.Exists(temporary)) File.Delete(temporary); }
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
