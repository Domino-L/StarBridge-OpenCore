using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Achievements;

/// <summary>Private pending evidence only. Cloud acknowledgement owns the earned collection.</summary>
internal sealed class HangarAchievementOutbox(string root)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "achievements-hangar-pending-v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    { PropertyNameCaseInsensitive = false, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, MaxDepth = 8 };
    private sealed record Saved(int SchemaVersion, string OwnerHash, HangarAchievementObservation? Pending, string Integrity);
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
        internal HangarAchievementObservation? Read()
        {
            Check(Path.GetDirectoryName(path)!, true);
            if (!Check(path, false)) return null;
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            if (stream.Length is <= 0 or > 4096) throw new InvalidDataException();
            var bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes);
            using var document = JsonDocument.Parse(bytes);
            Profiles.LocalPersonalProfileStore.RejectDuplicates(document.RootElement);
            var data = JsonSerializer.Deserialize<Saved>(bytes, Json);
            if (data is null || data.SchemaVersion != 1 || data.OwnerHash != hash ||
                data.Integrity != Integrity(hash, data.Pending) || data.Pending is { IsValid: false }) throw new InvalidDataException();
            return data.Pending;
        }
        internal void Save(HangarAchievementObservation? pending, Func<bool> current)
        {
            if (pending is { IsValid: false }) throw new InvalidDataException();
            _ = Read(); // A damaged record is unavailable; never overwrite it as empty.
            if (!current()) throw new OperationCanceledException();
            var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                var bytes = JsonSerializer.SerializeToUtf8Bytes(new Saved(1, hash, pending, Integrity(hash, pending)), Json);
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
    private static string Integrity(string owner, HangarAchievementObservation? pending) => Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, pending }, Json));
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
