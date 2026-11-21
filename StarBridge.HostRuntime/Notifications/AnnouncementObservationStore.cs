using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Notifications;

// Independent of policy v1/v2. Only derived keys are persisted. Saturation
// fails closed rather than evicting tombstones and replaying old publications.
internal sealed class AnnouncementObservationStore(string root)
{
    internal const int MaximumKeys = 20000;
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "notification-observations-v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) {
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, MaxDepth = 6
    };
    private sealed record Data(int SchemaVersion, string[] Keys, string Integrity);
    private sealed record DataV2(int SchemaVersion, string[] Keys, Membership[] Slots, string Integrity);
    internal sealed record Membership(string Slot, string? Binding, long Epoch, bool Official, bool Active);
    internal sealed class Snapshot {
        internal HashSet<string> Keys = new(StringComparer.Ordinal);
        internal Dictionary<string, Membership> Slots = new(StringComparer.Ordinal);
        internal bool Changed;
        internal long Observe(string slot, string? binding, bool official) {
            if (!Slots.TryGetValue(slot, out var prior)) {
                Slots.Add(slot, new(slot, binding, 0, official, binding != null)); Changed = true;
            } else if (binding == null ? prior.Active : !prior.Active || prior.Binding != binding) {
                // Departure/account retirement advances once. Reappearance only
                // activates that retired generation; it is not another departure.
                var epoch = prior.Active ? checked(prior.Epoch + 1) : prior.Epoch;
                Slots[slot] = prior with { Binding = binding ?? prior.Binding, Epoch = epoch, Active = binding != null }; Changed = true;
            }
            return Slots[slot].Epoch;
        }
    }
    internal static string Slot(string identity, bool official) => Hash(JsonSerializer.SerializeToUtf8Bytes(
        new[] { "membership-slot-v1", official ? "official" : identity }));
    internal static string Binding(string identity, string policy) => Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { identity, policy }));
    internal static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    internal static string Owner(BridgeAccountContext owner) {
        if (!owner.IsComplete) throw new InvalidDataException();
        return Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { owner.Environment, owner.Authority, owner.Subject }));
    }
    internal static string Key(string owner, string source, string id) =>
        Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { owner, source, id.ToUpperInvariant() }));
    // Separate hash domain: cannot collide with a three-part publication key.
    // v1 markers used relay session generations and cannot prove membership.
    // v2 binds a baseline to the durable locally observed membership generation.
    internal static string Baseline(string owner, string source, string policy, long membershipEpoch) =>
        Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { "announcement-baseline-v2", owner, source, policy, membershipEpoch.ToString(System.Globalization.CultureInfo.InvariantCulture) }));
    internal string PathFor(string owner) => Path.Combine(_directory, owner + ".json");
    private static void CheckPath(string path) {
        // Reject redirects at every existing ancestor, including the data root.
        for (var entry = new DirectoryInfo(Path.GetFullPath(path)); entry != null; entry = entry.Parent)
            if ((Directory.Exists(entry.FullName) || File.Exists(entry.FullName)) &&
                File.GetAttributes(entry.FullName).HasFlag(FileAttributes.ReparsePoint)) throw new InvalidDataException();
    }
    private static bool ValidKey(string key) => key.Length == 64 && key.All(c => c is >= 'a' and <= 'f' or >= '0' and <= '9');
    private static string Integrity(string owner, string[] keys) => Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, keys }, Json));
    internal HashSet<string> Read(string owner) => ReadSnapshot(owner).Keys;
    internal Snapshot ReadSnapshot(string owner) {
        var path = PathFor(owner); CheckPath(path);
        if (Directory.Exists(path)) throw new InvalidDataException();
        if (!File.Exists(path)) return new();
        using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
        if (file.Length is <= 0 or > 1500000) throw new InvalidDataException();
        using var doc = JsonDocument.Parse(file, new JsonDocumentOptions { MaxDepth = 6 });
        var names = doc.RootElement.EnumerateObject().Select(p => p.Name).ToArray();
        if (doc.RootElement.GetProperty("schemaVersion").GetInt32() == 2) {
            if (names.Length != 4 || names.Distinct().Count() != 4) throw new InvalidDataException();
            var modern = doc.RootElement.Deserialize<DataV2>(Json) ?? throw new InvalidDataException();
            if (modern.Keys is null || modern.Keys.Length > MaximumKeys || modern.Keys.Any(k => k is null || !ValidKey(k)) ||
                modern.Keys.Distinct().Count() != modern.Keys.Length || modern.Slots is null || modern.Slots.Length > 130 ||
                modern.Slots.Any(s => s is null || s.Slot is null || !ValidKey(s.Slot) || s.Binding != null && !ValidKey(s.Binding) ||
                    s.Active && s.Binding == null || s.Epoch < 0) ||
                modern.Slots.Select(s => s.Slot).Distinct().Count() != modern.Slots.Length ||
                modern.Integrity != IntegrityV2(owner, modern.Keys, modern.Slots)) throw new InvalidDataException();
            return new() { Keys = modern.Keys.ToHashSet(StringComparer.Ordinal), Slots = modern.Slots.ToDictionary(s => s.Slot, StringComparer.Ordinal) };
        }
        if (names.Length != 3 || names.Distinct().Count() != 3) throw new InvalidDataException();
        var data = doc.RootElement.Deserialize<Data>(Json);
        if (data is null || data.SchemaVersion != 1 || data.Keys is null || data.Keys.Length > MaximumKeys ||
            data.Keys.Any(k => k is null || !ValidKey(k)) || data.Keys.Distinct().Count() != data.Keys.Length ||
            data.Integrity != Integrity(owner, data.Keys)) throw new InvalidDataException();
        return new() { Keys = data.Keys.ToHashSet(StringComparer.Ordinal) };
    }
    private static string IntegrityV2(string owner, string[] keys, Membership[] slots) =>
        Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 2, owner, keys, slots }, Json));
    internal void Write(string owner, HashSet<string> keys, Func<bool> current) => WriteSnapshot(owner, new() { Keys = keys }, current);
    internal void WriteSnapshot(string owner, Snapshot snapshot, Func<bool> current) {
        var keys = snapshot.Keys;
        if (keys.Count > MaximumKeys || keys.Any(k => !ValidKey(k))) throw new InvalidDataException();
        if (snapshot.Slots.Count > 130) throw new InvalidDataException();
        var path = PathFor(owner); CheckPath(path);
        Directory.CreateDirectory(_directory);
        var temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try {
            var ordered = keys.Order(StringComparer.Ordinal).ToArray();
            var slots = snapshot.Slots.Values.OrderBy(s => s.Slot, StringComparer.Ordinal).ToArray();
            using (var file = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough)) {
                JsonSerializer.Serialize(file, new DataV2(2, ordered, slots, IntegrityV2(owner, ordered, slots)), Json); file.Flush(true);
            }
            if (!current()) throw new OperationCanceledException();
            CheckPath(path);
            File.Move(temp, path, true);
        } finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}
