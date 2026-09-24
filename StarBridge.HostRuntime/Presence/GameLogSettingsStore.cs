using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Presence;

public sealed record GameLogSettings(long Revision = 0, string? Path = null, bool Enabled = true,
    string Channel = "LIVE", string Selection = "automatic", string Channels = "LIVE|PTU",
    string VerifiedChannels = "", string IdentityCheck = "none", string? IdentityHandleHash = null);

/// <summary>
/// Stores the listening choice and the last comparison result. Log contents and detected Handles are never stored.
/// </summary>
public sealed class GameLogSettingsStore(string root)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "game-log-local-v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, PropertyNameCaseInsensitive = false, MaxDepth = 8 };
    private sealed record Data(int SchemaVersion, string Owner, GameLogSettings Settings, string Integrity);
    private sealed record Version3Settings(long Revision, string? Path, bool Enabled, string Channel,
        string Selection, string Channels);
    private sealed record Version3Data(int SchemaVersion, string Owner, Version3Settings Settings, string Integrity);
    private sealed record Version4Settings(long Revision, string? Path, bool Enabled, string Channel,
        string Selection, string Channels, string VerifiedChannels);
    private sealed record Version4Data(int SchemaVersion, string Owner, Version4Settings Settings, string Integrity);
    private sealed record Version2Settings(long Revision, string? Path, bool Enabled, string Channel, string Selection);
    private sealed record Version2Data(int SchemaVersion, string Owner, Version2Settings Settings, string Integrity);
    private sealed record LegacySettings(long Revision, string? Path, bool Enabled);
    private sealed record LegacyData(int SchemaVersion, string Owner, LegacySettings Settings, string Integrity);
    public Lease Open(BridgeAccountContext owner)
    {
        if (!owner.IsComplete) throw new IOException();
        var hash = Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { owner.Environment, owner.Authority, owner.Subject }));
        CheckTree(_directory);
        Directory.CreateDirectory(_directory);
        var path = Path.Combine(_directory, hash + ".json");
        CheckTree(path + ".lock");
        return new(path, hash, new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None));
    }
    public sealed class Lease(string path, string owner, FileStream writeLock) : IDisposable
    {
        public GameLogSettings Read()
        {
            CheckTree(path);
            if (!File.Exists(path)) return new();
            using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (file.Length is <= 0 or > 16384) throw new IOException();
            var bytes = new byte[(int)file.Length]; file.ReadExactly(bytes);
            using var doc = JsonDocument.Parse(bytes);
            Profiles.LocalPersonalProfileStore.RejectDuplicates(doc.RootElement);
            if (doc.RootElement.GetProperty("schemaVersion").GetInt32() == 1)
            {
                var legacy = JsonSerializer.Deserialize<LegacyData>(bytes, Json);
                if (legacy is null || legacy.Owner != owner || legacy.Settings is null ||
                    legacy.Settings.Revision <= 0 || legacy.Settings.Path?.Length > 1024 ||
                    legacy.Settings.Enabled && legacy.Settings.Path is null ||
                    legacy.Integrity != Hash(JsonSerializer.SerializeToUtf8Bytes(new { owner, settings = legacy.Settings }, Json)))
                    throw new IOException();
                // Keep explicit manual paths and stopped choices from the previous client.
                return new(legacy.Settings.Revision, legacy.Settings.Path, legacy.Settings.Enabled,
                    GameLogLocator.ChannelOf(legacy.Settings.Path) ?? "LIVE",
                    legacy.Settings.Path is null ? "automatic" : "manual");
            }
            if (doc.RootElement.GetProperty("schemaVersion").GetInt32() == 2)
            {
                var version2 = JsonSerializer.Deserialize<Version2Data>(bytes, Json);
                if (version2 is null || version2.Owner != owner || version2.Settings is null ||
                    version2.Settings.Revision <= 0 || version2.Settings.Path?.Length > 1024 ||
                    !GameLogLocator.ValidChannel(version2.Settings.Channel) ||
                    version2.Settings.Selection is not ("automatic" or "manual") ||
                    version2.Settings.Enabled && version2.Settings.Selection == "manual" && version2.Settings.Path is null ||
                    version2.Integrity != Hash(JsonSerializer.SerializeToUtf8Bytes(new { owner, settings = version2.Settings }, Json)))
                    throw new IOException();
                return new(version2.Settings.Revision, version2.Settings.Path, version2.Settings.Enabled,
                    version2.Settings.Channel, version2.Settings.Selection,
                    GameLogLocator.AddChannel("LIVE|PTU", version2.Settings.Channel));
            }
            if (doc.RootElement.GetProperty("schemaVersion").GetInt32() == 3)
            {
                var version3 = JsonSerializer.Deserialize<Version3Data>(bytes, Json);
                if (version3 is null || version3.Owner != owner || version3.Settings is null ||
                    version3.Settings.Revision <= 0 ||
                    version3.Integrity != Hash(JsonSerializer.SerializeToUtf8Bytes(
                        new { owner, settings = version3.Settings }, Json)) ||
                    version3.Settings.Path?.Length > 1024 ||
                    !GameLogLocator.ValidChannel(version3.Settings.Channel) ||
                    GameLogLocator.Channels(version3.Settings.Channels) is not { Count: >= 1 and <= 16 } version3Channels ||
                    !version3Channels.Contains("LIVE") || !version3Channels.Contains(version3.Settings.Channel) ||
                    version3.Settings.Selection is not ("automatic" or "manual") ||
                    version3.Settings.Enabled && version3.Settings.Selection == "manual" &&
                    version3.Settings.Path is null)
                    throw new IOException();
                return new(version3.Settings.Revision, version3.Settings.Path, version3.Settings.Enabled,
                    version3.Settings.Channel, version3.Settings.Selection, version3.Settings.Channels);
            }
            if (doc.RootElement.GetProperty("schemaVersion").GetInt32() == 4)
            {
                var version4 = JsonSerializer.Deserialize<Version4Data>(bytes, Json);
                if (version4 is null || version4.Owner != owner || version4.Settings is null ||
                    version4.Settings.Revision <= 0 ||
                    version4.Integrity != Hash(JsonSerializer.SerializeToUtf8Bytes(
                        new { owner, settings = version4.Settings }, Json)) ||
                    !ValidCommon(version4.Settings.Path, version4.Settings.Enabled, version4.Settings.Channel,
                        version4.Settings.Selection, version4.Settings.Channels, version4.Settings.VerifiedChannels))
                    throw new IOException();
                return new(version4.Settings.Revision, version4.Settings.Path, version4.Settings.Enabled,
                    version4.Settings.Channel, version4.Settings.Selection, version4.Settings.Channels,
                    version4.Settings.VerifiedChannels);
            }
            var data = JsonSerializer.Deserialize<Data>(bytes, Json);
            if (data is null || data.Owner != owner || data.SchemaVersion != 5 || data.Settings is null ||
                data.Settings.Revision <= 0 || data.Integrity != Integrity(owner, data.Settings) ||
                !ValidCommon(data.Settings.Path, data.Settings.Enabled, data.Settings.Channel,
                    data.Settings.Selection, data.Settings.Channels, data.Settings.VerifiedChannels) ||
                data.Settings.IdentityCheck is not ("none" or "match" or "mismatch") ||
                data.Settings.IdentityCheck == "none" && data.Settings.IdentityHandleHash is not null ||
                data.Settings.IdentityCheck != "none" && !ValidHash(data.Settings.IdentityHandleHash))
                throw new IOException();
            return data.Settings;
        }
        public GameLogSettings Save(GameLogSettings before, GameLogSettings desired, Func<bool> current)
        {
            if (Read() != before || before.Revision == long.MaxValue) throw new IOException();
            var next = desired with { Revision = before.Revision + 1 };
            var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write,
                    FileShare.None, 4096, FileOptions.WriteThrough))
                {
                    file.Write(JsonSerializer.SerializeToUtf8Bytes(new Data(5, owner, next, Integrity(owner, next)), Json));
                    file.Flush(true);
                }
                CheckTree(path);
                if (!current()) throw new OperationCanceledException();
                if (before.Revision == 0) File.Move(temporary, path);
                else File.Replace(temporary, path, null);
                return next;
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }
        public void Dispose() => writeLock.Dispose();
    }
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    private static string Integrity(string owner, GameLogSettings settings) =>
        Hash(JsonSerializer.SerializeToUtf8Bytes(new { owner, settings }, Json));
    private static bool ValidCommon(string? path, bool enabled, string channel, string selection,
        string channelsValue, string verifiedChannelsValue)
    {
        if (path?.Length > 1024 || !GameLogLocator.ValidChannel(channel) ||
            GameLogLocator.Channels(channelsValue) is not { Count: >= 1 and <= 16 } channels ||
            !channels.Contains("LIVE") || !channels.Contains(channel) ||
            GameLogLocator.Channels(verifiedChannelsValue) is not { Count: <= 16 } verified ||
            verified.Any(item => !channels.Contains(item)) ||
            selection is not ("automatic" or "manual") ||
            enabled && selection == "manual" && path is null)
            return false;
        return true;
    }
    private static bool ValidHash(string? value) =>
        value is { Length: 64 } && value.All(character =>
            character is >= '0' and <= '9' or >= 'A' and <= 'F');
    private static void CheckTree(string path)
    {
        for (var part = Path.GetFullPath(path); !string.IsNullOrEmpty(part); part = Path.GetDirectoryName(part))
        {
            try { if ((File.GetAttributes(part) & FileAttributes.ReparsePoint) != 0) throw new IOException(); }
            catch (FileNotFoundException) { }
            catch (DirectoryNotFoundException) { }
        }
    }
}
