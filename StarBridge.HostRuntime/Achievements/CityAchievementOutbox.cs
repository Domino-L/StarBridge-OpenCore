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
            if (Pending is null || Confirmed is null || Pending.Length > 4 || Confirmed.Length > 4 ||
                Pending.Any(p => p is null || !p.IsValid || Confirmed.Contains(p.City)) ||
                Pending.Select(p => p.City).Distinct().Count() != Pending.Length ||
                Confirmed.Any(c => !JourneyAchievementPolicy.IsCity(c)) || Confirmed.Distinct().Count() != Confirmed.Length)
                throw new InvalidDataException("Invalid city outbox.");
        }
    }
    private sealed record Saved(int SchemaVersion, string OwnerHash, State Cities, string Integrity);
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
        internal State Read()
        {
            Check(Path.GetDirectoryName(path)!, true);
            if (!Check(path, false)) return State.Empty;
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            if (stream.Length is <= 0 or > 8192) throw new InvalidDataException();
            var bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes);
            using var document = JsonDocument.Parse(bytes);
            Profiles.LocalPersonalProfileStore.RejectDuplicates(document.RootElement);
            var data = JsonSerializer.Deserialize<Saved>(bytes, Json);
            if (data is null || data.SchemaVersion != 1 || data.OwnerHash != hash || data.Cities is null ||
                data.Integrity != Integrity(hash, data.Cities)) throw new InvalidDataException();
            data.Cities.Validate();
            return data.Cities;
        }
        internal void Save(State cities, Func<bool> current)
        {
            cities.Validate();
            _ = Read(); // Never overwrite a corrupt record with an empty one.
            if (!current()) throw new OperationCanceledException();
            var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                var bytes = JsonSerializer.SerializeToUtf8Bytes(new Saved(1, hash, cities, Integrity(hash, cities)), Json);
                using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
                { stream.Write(bytes); stream.Flush(true); }
                Check(Path.GetDirectoryName(path)!, true); var exists = Check(path, false);
                if (!current()) throw new OperationCanceledException();
                if (exists) File.Replace(temporary, path, null); else File.Move(temporary, path);
            }
            finally { try { File.Delete(temporary); } catch (IOException) { } }
        }
        public void Dispose() => fileLock.Dispose();
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
