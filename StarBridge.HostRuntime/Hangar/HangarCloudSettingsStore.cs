using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Hangar;

/// <summary>
/// Per-account state of the account hangar copy, beside (not inside) hangar-local-v1 so the local hangar
/// format stays exactly what older clients read. Since 11-05 the copy is always on: only NoticeShown is used;
/// Enabled is still written for files from earlier 0.7.3 test builds but never read. Missing file = notice
/// not yet shown.
/// </summary>
public sealed class HangarCloudSettingsStore(string root)
{
    public sealed record Settings(bool Enabled, bool NoticeShown);

    private sealed record FileData([property: JsonRequired] int SchemaVersion, [property: JsonRequired] string OwnerHash,
        [property: JsonRequired] bool Enabled, [property: JsonRequired] bool NoticeShown, [property: JsonRequired] string Integrity);

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        MaxDepth = 4
    };
    private const int MaximumBytes = 4096;
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "hangar-cloud-v1");
    private readonly object _gate = new();

    public static Settings Default { get; } = new(true, false);
    /// <summary>A file that cannot be read safely: the one-time notice is not shown again (no more prompts).</summary>
    public static Settings Unreadable { get; } = new(false, true);

    public Settings Read(BridgeAccountContext owner)
    {
        var hash = OwnerHash(owner);
        lock (_gate)
        {
            try
            {
                var path = PathFor(hash);
                if (!Exists(_directory, true) || !Exists(path, false)) return Default;
                var bytes = File.ReadAllBytes(path);
                if (bytes.Length is <= 0 or > MaximumBytes) return Unreadable;
                var data = JsonSerializer.Deserialize<FileData>(bytes, Json);
                if (data is null || data.SchemaVersion != 1 || data.OwnerHash != hash ||
                    data.Integrity != Integrity(hash, data.Enabled, data.NoticeShown)) return Unreadable;
                return new(data.Enabled, data.NoticeShown);
            }
            // Only a missing file means "never written". A file that cannot be read or verified is treated as
            // "notice already shown"; the copy itself no longer depends on this file.
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException)
            { return Unreadable; }
        }
    }

    /// <summary>Read-modify-write under one lock, so concurrent changes never undo each other.</summary>
    public void Update(BridgeAccountContext owner, Func<Settings, Settings> change)
    {
        lock (_gate)
        {
            var current = Read(owner);
            var next = change(current);
            if (next != current) Save(owner, next);
        }
    }

    public void Save(BridgeAccountContext owner, Settings settings)
    {
        var hash = OwnerHash(owner);
        lock (_gate)
        {
            try
            {
                Exists(_directory, true);
                Directory.CreateDirectory(_directory);
                var path = PathFor(hash);
                Exists(path, false);
                var bytes = JsonSerializer.SerializeToUtf8Bytes(new FileData(1, hash, settings.Enabled, settings.NoticeShown,
                    Integrity(hash, settings.Enabled, settings.NoticeShown)), Json);
                var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
                try
                {
                    using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096,
                               FileOptions.WriteThrough))
                    { stream.Write(bytes); stream.Flush(true); }
                    if (File.Exists(path)) File.Replace(temporary, path, null);
                    else File.Move(temporary, path);
                }
                finally { try { File.Delete(temporary); } catch (IOException) { } }
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            { throw new LocalHangarStoreException("hangar.cloud_settings_write_failed", "The hangar account setting could not be saved.", error); }
        }
    }

    private string PathFor(string hash) => Path.Combine(_directory, hash + ".json");

    private static bool Exists(string path, bool directory)
    {
        FileAttributes attributes;
        try { attributes = File.GetAttributes(path); }
        catch (FileNotFoundException) { return false; }
        catch (DirectoryNotFoundException) { return false; }
        if ((attributes & FileAttributes.ReparsePoint) != 0 || attributes.HasFlag(FileAttributes.Directory) != directory)
            throw new IOException("Unexpected path type.");
        return true;
    }

    private static string OwnerHash(BridgeAccountContext owner)
    {
        if (owner is null || !owner.IsComplete || new[] { owner.Environment, owner.Authority, owner.Subject }
                .Any(v => v.Length > 2048 || v.Any(char.IsControl)))
            throw new LocalHangarStoreException("hangar.account_changed", "Invalid account.");
        return Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(
            new[] { "hangar-cloud-v1", owner.Environment, owner.Authority, owner.Subject })));
    }

    private static string Integrity(string hash, bool enabled, bool noticeShown) =>
        Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, hash, enabled, noticeShown })));
}
