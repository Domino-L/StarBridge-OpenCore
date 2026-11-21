using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.Core.Achievements;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Achievements;

// Separate from the v1 observation journal, so older clients neither read nor rewrite records.
internal sealed class ContractRecordStore(string root)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "achievements-contract-records-v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) {
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, PropertyNameCaseInsensitive = false, MaxDepth = 16 };
    internal sealed record Award(DateTimeOffset EarnedAt, ContractAchievementRecord Run);
    internal sealed record State(Dictionary<string, string> Names, Dictionary<string, ContractAchievementRecord> Runs,
        Dictionary<string, Award> Awards)
    {
        internal static State Empty => new([], [], []);
        internal void Validate()
        {
            if (Names is null || Runs is null || Awards is null || Names.Count > 8192 || Runs.Count > 8192 || Awards.Count > 5 ||
                Names.Any(p => !Mission(p.Key) || p.Value is null || ContractAchievementRecord.CleanName(p.Value) != p.Value) ||
                Runs.Any(p => !Mission(p.Key) || p.Value is null) || Awards.Any(p =>
                    !ContractAchievementPolicy.IsAward(p.Key) || p.Value is null || p.Value.Run is null ||
                    p.Value.EarnedAt <= DateTimeOffset.UnixEpoch || p.Value.EarnedAt.Offset != TimeSpan.Zero))
                throw new InvalidDataException("Invalid contract records.");
            foreach (var run in Runs.Values.Concat(Awards.Values.Select(a => a.Run))) run.Validate();
        }
        private static bool Mission(string id) => Guid.TryParseExact(id, "D", out var value) && value != Guid.Empty;
    }
    private sealed record Saved(int SchemaVersion, string Owner, State State, string Integrity);
    internal Lease Open(BridgeAccountContext owner)
    {
        if (!owner.IsComplete || new[] { owner.Environment, owner.Authority, owner.Subject }.Any(s => s.Length > 2048 || s.Any(char.IsControl)))
            throw new InvalidDataException();
        CheckTree(_directory); Directory.CreateDirectory(_directory);
        var hash = Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { owner.Environment, owner.Authority, owner.Subject }));
        var path = Path.Combine(_directory, hash + ".json"); CheckTree(path + ".lock");
        return new(path, hash, new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None));
    }
    internal sealed class Lease(string path, string owner, FileStream gate) : IDisposable
    {
        internal State Read()
        {
            CheckTree(path); if (!File.Exists(path)) return State.Empty;
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            if (stream.Length is <= 0 or > 8388608) throw new InvalidDataException();
            var bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes);
            using var doc = JsonDocument.Parse(bytes); Profiles.LocalPersonalProfileStore.RejectDuplicates(doc.RootElement);
            var saved = JsonSerializer.Deserialize<Saved>(bytes, Json);
            if (saved is null || saved.SchemaVersion != 1 || saved.Owner != owner || saved.State is null ||
                saved.Integrity != Integrity(owner, saved.State)) throw new InvalidDataException("Invalid contract record integrity.");
            saved.State.Validate(); return saved.State;
        }
        internal void Save(State state, Func<bool> current)
        {
            state.Validate(); _ = Read(); if (!current()) throw new OperationCanceledException();
            var temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                var bytes = JsonSerializer.SerializeToUtf8Bytes(new Saved(1, owner, state, Integrity(owner, state)), Json);
                if (bytes.Length > 8388608) throw new InvalidDataException("Contract record limit.");
                using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
                { stream.Write(bytes); stream.Flush(true); }
                CheckTree(path);
                if (!current() || !StoreFileCommit.Replace(temp, path, current, "Contract record commit timed out.")) throw new OperationCanceledException();
            }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
        public void Dispose() => gate.Dispose();
    }
    internal void Capture(BridgeAccountContext owner, string mission, string? name, ContractAchievementRecord? run, Func<bool> current)
    {
        using var lease = Open(owner); var state = lease.Read();
        if (ContractAchievementRecord.CleanName(name) is { } clean) state.Names.TryAdd(mission, clean);
        if (run is not null) state.Runs.TryAdd(mission, run with { DisplayName = state.Names.GetValueOrDefault(mission) });
        // The optional presentation history is bounded independently of the authoritative outbox.
        while (state.Names.Count > 8192) state.Names.Remove(state.Names.Keys.First());
        while (state.Runs.Count > 8192) state.Runs.Remove(state.Runs.Keys.First());
        lease.Save(state, current);
    }
    internal void Confirm(BridgeAccountContext owner, ContractObservation observation, ContractAchievementReceipt receipt, Func<bool> current)
    {
        using var lease = Open(owner); var state = lease.Read();
        if (!state.Runs.TryGetValue(observation.MissionId, out var run) || run.AcceptedAt != observation.AcceptedAt ||
            run.CompletedAt != observation.CompletedAt || run.ArrivedAt != observation.ArrivedAt ||
            run.Owner != observation.Owner || run.Deaths != observation.Deaths) return;
        foreach (var id in receipt.NewlyEarned)
            if (run.Lines(id) is not null) state.Awards.TryAdd(id, new(receipt.EarnedAt[id], run));
        // Only the local best run changes; the original award date and grant remain intact.
        const string swift = "contract-tsg-swift";
        if (observation.Outcome == "completed" && observation.Contract == ContractAchievementPolicy.Tsg &&
            observation.CompleteRun && run.ArrivedAt is { } arrived &&
            run.CompletedAt - arrived <= TimeSpan.FromMinutes(90) &&
            receipt.EarnedAt.TryGetValue(swift, out var earnedAt) &&
            (!state.Awards.TryGetValue(swift, out var best) ||
                best.EarnedAt == earnedAt && (best.Run.ArrivedAt is not { } previous ||
                    run.CompletedAt - arrived < best.Run.CompletedAt - previous)))
            state.Awards[swift] = new(earnedAt, run);
        lease.Save(state, current);
    }
    internal Dictionary<string, ContractRecordLines> ReadLines(BridgeAccountContext owner, AchievementSnapshot snapshot)
    {
        using var lease = Open(owner);
        return lease.Read().Awards.Where(p => snapshot.EarnedAt.GetValueOrDefault(p.Key) == p.Value.EarnedAt)
            .Select(p => (p.Key, Lines: p.Value.Run.Lines(p.Key))).Where(p => p.Lines is not null)
            .ToDictionary(p => p.Key, p => p.Lines!);
    }
    internal static bool IsStorageError(Exception error) => error is IOException or InvalidDataException or UnauthorizedAccessException or JsonException;
    private static string Hash(byte[] value) => Convert.ToHexString(SHA256.HashData(value));
    private static string Integrity(string owner, State state) => Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, state }, Json));
    private static void CheckTree(string path)
    {
        for (var part = path; part is not null; part = Path.GetDirectoryName(part))
        {
            try { if (File.GetAttributes(part).HasFlag(FileAttributes.ReparsePoint)) throw new IOException("Linked contract record path."); }
            catch (FileNotFoundException) { } catch (DirectoryNotFoundException) { }
        }
    }
}
