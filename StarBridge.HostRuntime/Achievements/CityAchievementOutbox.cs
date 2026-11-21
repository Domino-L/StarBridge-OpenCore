using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.Core.Achievements;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Achievements;

/// <summary>Account-isolated durable observations. Confirmed cities remain as deduplication markers, never local grants.</summary>
internal sealed class CityAchievementOutbox(string root)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "achievements-city-pending-v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    { PropertyNameCaseInsensitive = false, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, MaxDepth = 8 };
    internal sealed record State(CityObservation[] Pending, string[] Confirmed)
    {
        internal static State Empty => new([], []);
        internal bool Contains(string city) => Confirmed.Contains(city) || Pending.Any(p => p.City == city);
        internal void Validate()
        {
            if (Pending is null || Confirmed is null || Pending.Length > JourneyAchievementPolicy.Tokens.Count || Confirmed.Length > JourneyAchievementPolicy.Tokens.Count ||
                Pending.Any(p => p is null || !p.IsValid || Confirmed.Contains(p.City)) ||
                Pending.Select(p => p.City).Distinct().Count() != Pending.Length ||
                Confirmed.Any(c => !JourneyAchievementPolicy.IsToken(c)) || Confirmed.Distinct().Count() != Confirmed.Length)
                throw new InvalidDataException("Invalid city outbox.");
        }
    }
    private sealed record Saved(int SchemaVersion, string OwnerHash, State Cities, string Integrity);
    // Keep the original owner.json wire format restricted to the four released cities.
    // Both files share the original lease lock, including while recovering a mixed 0.7.3 file.
    private static State Partition(State state, bool extra) => new(
        state.Pending.Where(p => JourneyAchievementPolicy.IsCity(p.City) != extra).ToArray(),
        state.Confirmed.Where(c => JourneyAchievementPolicy.IsCity(c) != extra).ToArray());
    private static void ValidatePartition(State state, bool extra)
    {
        state.Validate();
        var limit = extra ? JourneyAchievementPolicy.Tokens.Count - JourneyAchievementPolicy.Cities.Count : JourneyAchievementPolicy.Cities.Count;
        if (state.Pending.Length > limit || state.Confirmed.Length > limit ||
            state.Pending.Any(p => JourneyAchievementPolicy.IsCity(p.City) == extra) ||
            state.Confirmed.Any(c => JourneyAchievementPolicy.IsCity(c) == extra))
            throw new InvalidDataException("Invalid city outbox partition.");
    }
    private static State Merge(State first, State second)
    {
        // A confirmed marker wins over a pending duplicate after an interrupted migration.
        var confirmed = first.Confirmed.Concat(second.Confirmed).Distinct().ToArray();
        var merged = new State(first.Pending.Concat(second.Pending).Where(p => !confirmed.Contains(p.City))
            .DistinctBy(p => p.City).ToArray(), confirmed);
        merged.Validate();
        return merged;
    }
    internal Lease Open(BridgeAccountContext owner)
    {
        if (!owner.IsComplete || new[] { owner.Environment, owner.Authority, owner.Subject }
            .Any(s => s.Length > 2048 || s.Any(char.IsControl))) throw new InvalidDataException();
        var hash = Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { owner.Environment, owner.Authority, owner.Subject }));
        Check(_directory, true); Directory.CreateDirectory(_directory);
        var path = Path.Combine(_directory, hash + ".json");
        Check(path + ".lock", false);
        return new(path, hash, new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None));
    }
    internal sealed class Lease(string path, string hash, FileStream fileLock) : IDisposable
    {
        private readonly string _extraPath = Path.ChangeExtension(path, ".journey-extra-v1.json");
        // Entries a newer build wrote (e.g. a 0.7.4 token after rolling back) are skipped here,
        // never uploaded or celebrated, and written back unchanged into the file they came from.
        private State _unknownOriginal = State.Empty, _unknownExtra = State.Empty;
        internal State Read()
            => Read(() => true);
        private State Read(Func<bool> current)
        {
            // Verify both records before attempting any repair. Invalid integrity is never repaired.
            var (original, unknownOriginal) = ReadFile(path);
            var (extra, unknownExtra) = ReadFile(_extraPath);
            _unknownOriginal = unknownOriginal; _unknownExtra = unknownExtra;
            ValidatePartition(extra, true);
            var cities = Partition(original, false);
            ValidatePartition(cities, false);
            var misplaced = Partition(original, true);
            if (misplaced.Pending.Length != 0 || misplaced.Confirmed.Length != 0)
            {
                extra = Merge(extra, misplaced);
                ValidatePartition(extra, true);
                // Crash recovery is idempotent: until the second replace succeeds the original
                // still contains every migrated observation; re-opening merges without duplicates.
                WriteFile(_extraPath, Keep(extra, _unknownExtra), current);
                WriteFile(path, Keep(cities, _unknownOriginal), current);
            }
            return Merge(cities, extra);
        }
        private (State Known, State Unknown) ReadFile(string recordPath)
        {
            Check(Path.GetDirectoryName(recordPath)!, true);
            if (!Check(recordPath, false)) return (State.Empty, State.Empty);
            using var stream = new FileStream(recordPath, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            if (stream.Length is <= 0 or > 8192) throw new InvalidDataException();
            var bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes);
            using var document = JsonDocument.Parse(bytes);
            Profiles.LocalPersonalProfileStore.RejectDuplicates(document.RootElement);
            var data = JsonSerializer.Deserialize<Saved>(bytes, Json);
            if (data is null || data.SchemaVersion != 1 || data.OwnerHash != hash || data.Cities is null ||
                data.Integrity != Integrity(hash, data.Cities)) throw new InvalidDataException();
            var (known, unknown) = SplitUnknown(data.Cities);
            known.Validate();
            return (known, unknown);
        }
        internal void Save(State cities, Func<bool> current)
        {
            cities.Validate();
            _ = Read(current); // Never overwrite a corrupt record with an empty one.
            var legacy = Partition(cities, false);
            var extra = Partition(cities, true);
            ValidatePartition(legacy, false);
            ValidatePartition(extra, true);
            if (extra.Pending.Length != 0 || extra.Confirmed.Length != 0 || Check(_extraPath, false))
                WriteFile(_extraPath, Keep(extra, _unknownExtra), current);
            WriteFile(path, Keep(legacy, _unknownOriginal), current);
        }
        // Known entries first, then the untouched entries of a newer build.
        private static State Keep(State known, State unknown) =>
            unknown.Pending.Length == 0 && unknown.Confirmed.Length == 0 ? known
                : new([.. known.Pending, .. unknown.Pending], [.. known.Confirmed, .. unknown.Confirmed]);
        private void WriteFile(string recordPath, State cities, Func<bool> current)
        {
            if (!current()) throw new OperationCanceledException();
            var temporary = recordPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                var bytes = JsonSerializer.SerializeToUtf8Bytes(new Saved(1, hash, cities, Integrity(hash, cities)), Json);
                if (bytes.Length > 8192) throw new InvalidDataException("City outbox limit.");
                using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
                { stream.Write(bytes); stream.Flush(true); }
                Check(Path.GetDirectoryName(recordPath)!, true); var exists = Check(recordPath, false);
                if (!current()) throw new OperationCanceledException();
                if (exists) File.Replace(temporary, recordPath, null); else File.Move(temporary, recordPath);
            }
            finally { try { File.Delete(temporary); } catch (IOException) { } }
        }
        public void Dispose() => fileLock.Dispose();
    }
    // A token this build does not know is still a bounded, well-formed entry; anything else is corruption.
    private const int MaxUnknown = 64;
    private static bool UnknownToken(string? token) =>
        token is { Length: > 0 and <= 64 } && token.All(c => c is >= 'a' and <= 'z' or >= '0' and <= '9' or '-') &&
        !JourneyAchievementPolicy.IsToken(token);
    private static (State Known, State Unknown) SplitUnknown(State cities)
    {
        if (cities.Pending is null || cities.Confirmed is null || cities.Pending.Any(p => p is null) ||
            cities.Confirmed.Any(c => c is null)) throw new InvalidDataException("Invalid city outbox.");
        var unknown = new State(cities.Pending.Where(p => UnknownToken(p.City)).ToArray(),
            cities.Confirmed.Where(UnknownToken).ToArray());
        if (unknown.Pending.Length + unknown.Confirmed.Length > MaxUnknown ||
            unknown.Pending.Any(p => p.SchemaVersion != 1 || p.HandleHash is not { Length: 64 } ||
                !p.HandleHash.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f') || p.Evidence is not { Length: > 0 and <= 64 }) ||
            unknown.Pending.Select(p => p.City).Concat(unknown.Confirmed).Distinct().Count() !=
                unknown.Pending.Length + unknown.Confirmed.Length)
            throw new InvalidDataException("Invalid city outbox.");
        var known = new State(cities.Pending.Where(p => !UnknownToken(p.City)).ToArray(),
            cities.Confirmed.Where(c => !UnknownToken(c)).ToArray());
        return (known, unknown);
    }
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    private static string Integrity(string owner, State cities) =>
        Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, cities }, Json));
    private static bool Check(string path, bool directory)
    {
        FileAttributes value;
        try { value = File.GetAttributes(path); }
        catch (FileNotFoundException) { return false; }
        catch (DirectoryNotFoundException) { return false; }
        if (value.HasFlag(FileAttributes.ReparsePoint) || value.HasFlag(FileAttributes.Directory) != directory) throw new IOException();
        return true;
    }
}
