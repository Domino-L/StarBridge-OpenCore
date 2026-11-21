using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Achievements;

// One atomic account record owns active runs, terminal deduplication and the outbox.
// Completion and enqueue cannot be separated by a Host crash. No raw lines or names are saved.
internal sealed class ContractAchievementStore(string root)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "achievements-contract-v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) {
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, PropertyNameCaseInsensitive = false, MaxDepth = 16 };
    internal sealed record Objective(string Id, DateTimeOffset At, bool Created, bool Travel, DateTimeOffset? CompletedAt, string? Text = null);
    internal sealed record Run(string MissionId, string HandleHash, Guid ReadingPeriod, bool Shared = false,
        bool Historical = false, DateTimeOffset? AcceptedAt = null, bool Owner = false, bool Gap = false,
        string? Contract = null, string? DefinitionId = null, int Deaths = 0, DateTimeOffset? LastDeathAt = null,
        bool Dead = false, Objective[]? Objectives = null, DateTimeOffset? ArrivedAt = null, bool TravelClosed = false,
        string? Outcome = null, DateTimeOffset? EndedAt = null, ContractObservation? Pending = null, bool Confirmed = false);
    internal sealed record State(Run[] Runs)
    {
        internal static State Empty => new([]);
        internal void Validate()
        {
            if (Runs is null || Runs.Length > 8192 || Runs.Any(r => r is null) || Runs.Select(r => r.MissionId).Distinct().Count() != Runs.Length ||
                Runs.Any(r => !Guid.TryParseExact(r.MissionId, "D", out var id) || id == Guid.Empty ||
                    r.HandleHash is not { Length: 64 } || r.Deaths is < 0 or > 10000 || r.Objectives?.Length > 256 ||
                    r.Objectives is { } goals && (goals.Any(o => o is null || o.Id is null || o.Id.Length > 64 || o.Text?.Length > 160) ||
                        goals.Select(o => o.Id).Distinct().Count() != goals.Length) ||
                    r.Pending is { } p && (!p.IsValid || p.MissionId != r.MissionId || p.HandleHash != r.HandleHash || r.Confirmed)))
                throw new InvalidDataException("Invalid contract journal.");
        }
    }
    private sealed record Saved(int SchemaVersion, string Owner, State State, string Integrity);
    internal Lease Open(BridgeAccountContext owner)
    {
        if (!owner.IsComplete || new[] { owner.Environment, owner.Authority, owner.Subject }.Any(s => s.Length > 2048 || s.Any(char.IsControl)))
            throw new InvalidDataException();
        CheckTree(_directory); Directory.CreateDirectory(_directory);
        var hash = Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { owner.Environment, owner.Authority, owner.Subject }));
        var path = Path.Combine(_directory, hash + ".json");
        CheckTree(path + ".lock");
        return new(path, hash, new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None));
    }
    internal sealed class Lease(string path, string owner, FileStream gate) : IDisposable
    {
        internal State Read()
        {
            CheckTree(path);
            if (!File.Exists(path)) return State.Empty;
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            if (stream.Length is <= 0 or > 16777216) throw new InvalidDataException();
            var bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes);
            using var doc = JsonDocument.Parse(bytes); Profiles.LocalPersonalProfileStore.RejectDuplicates(doc.RootElement);
            var saved = JsonSerializer.Deserialize<Saved>(bytes, Json);
            if (saved is null || saved.SchemaVersion != 1 || saved.Owner != owner || saved.State is null ||
                saved.Integrity != Integrity(owner, saved.State)) throw new InvalidDataException("Invalid contract journal integrity.");
            saved.State.Validate(); return saved.State;
        }
        internal void Save(State state, Func<bool> current)
        {
            state.Validate(); _ = Read();
            if (!current()) throw new OperationCanceledException();
            var temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                var bytes = JsonSerializer.SerializeToUtf8Bytes(new Saved(1, owner, state, Integrity(owner, state)), Json);
                if (bytes.Length > 16777216) throw new InvalidDataException("Contract journal limit.");
                using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
                { stream.Write(bytes); stream.Flush(true); }
                CheckTree(path);
                if (!current() || !StoreFileCommit.Replace(temp, path, current, "Contract commit timed out.")) throw new OperationCanceledException();
            }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
        public void Dispose() => gate.Dispose();
    }
    private static string Hash(byte[] value) => Convert.ToHexString(SHA256.HashData(value));
    private static string Integrity(string owner, State state) => Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, state }, Json));
    private static void CheckTree(string path)
    {
        for (var part = path; part is not null; part = Path.GetDirectoryName(part))
        {
            try { if (File.GetAttributes(part).HasFlag(FileAttributes.ReparsePoint)) throw new IOException("Linked contract journal path."); }
            catch (FileNotFoundException) { } catch (DirectoryNotFoundException) { }
        }
    }
}
