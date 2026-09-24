using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
namespace StarBridge.HostRuntime.Notifications;

// WPF scope bit 2 means community members, not RSI official-fleet membership.
internal sealed record PlayerActivityPreferences(bool Enabled = false, int Scope = 2, int Position = 3,
    bool Online = true, bool Offline = false, bool StartedGame = true, bool StoppedGame = false,
    bool BackgroundOnly = true, bool ReduceInGame = true);
internal sealed record PlayerActivityPreferencesSnapshot(string Revision, PlayerActivityPreferences Value,
    bool DoNotDisturb = false, int CooldownSeconds = 60);
internal sealed class PlayerActivityPreferencesConflictException : IOException;

// Caller supplies the verified WPF settings root and enforces single-writer ownership.
// No legacy-directory search or automatic migration. Unknown fields survive updates.
internal sealed class PlayerActivityPreferencesStore
{
    private readonly string _root, _path;
    private readonly object _gate = new();
    public PlayerActivityPreferencesStore(string settingsRoot)
    {
        if (!Path.IsPathFullyQualified(settingsRoot)) throw new ArgumentException(nameof(settingsRoot));
        _root = Path.GetFullPath(settingsRoot);
        _path = Path.Combine(_root, "notification.settings.json");
    }
    public PlayerActivityPreferencesSnapshot Read()
    {
        lock (_gate) { var (revision, doc) = ReadDocument(); return Snapshot(revision, doc, Parse(doc)); }
    }
    public PlayerActivityPreferencesSnapshot Save(PlayerActivityPreferences value, string expectedRevision, Action? ensureCurrent = null)
    {
        Validate(value);
        lock (_gate)
        {
            ensureCurrent?.Invoke();
            var (revision, doc) = ReadDocument();
            _ = Parse(doc);
            if (revision != expectedRevision) throw new PlayerActivityPreferencesConflictException();
            doc["EnablePlayerActivityNotifications"] = value.Enabled;
            doc["PlayerActivityScope"] = value.Scope;
            doc["PlayerActivityPosition"] = value.Position;
            doc["NotifyPlayerOnline"] = value.Online;
            doc["NotifyPlayerOffline"] = value.Offline;
            doc["NotifyPlayerStartedGame"] = value.StartedGame;
            doc["NotifyPlayerStoppedGame"] = value.StoppedGame;
            doc["PlayerActivityBackgroundOnly"] = value.BackgroundOnly;
            doc["ReducePlayerActivityNotificationsInGame"] = value.ReduceInGame;
            var bytes = JsonSerializer.SerializeToUtf8Bytes(doc, new JsonSerializerOptions { WriteIndented = true });
            if (bytes.Length > 65536) throw new InvalidDataException();
            ensureCurrent?.Invoke();
            CheckPaths(); Directory.CreateDirectory(_root);
            var temp = Path.Combine(_root, ".player-activity-" + Guid.NewGuid().ToString("N") + ".tmp");
            try
            {
                using (var file = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
                { file.Write(bytes); file.Flush(true); }
                CheckPaths();
                if (ReadDocument().Revision != expectedRevision) throw new PlayerActivityPreferencesConflictException();
                ensureCurrent?.Invoke();
                File.Move(temp, _path, overwrite: true);
            }
            finally { if (File.Exists(temp)) File.Delete(temp); }
            return Snapshot(Hash(bytes), doc, value);
        }
    }
    private static PlayerActivityPreferencesSnapshot Snapshot(string revision, JsonObject doc, PlayerActivityPreferences value) =>
        new(revision, value, Bool(doc,"DoNotDisturb",false), Math.Clamp(Int(doc,"NotificationCooldownSeconds",60),0,3600));
    private (string Revision, JsonObject Document) ReadDocument()
    {
        CheckPaths(); byte[] bytes;
        try
        {
            using var file = new FileStream(_path, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (file.Length is <= 0 or > 65536) throw new InvalidDataException();
            bytes = new byte[checked((int)file.Length)]; file.ReadExactly(bytes);
        }
        catch (FileNotFoundException) { return ("missing", new()); }
        catch (DirectoryNotFoundException) { return ("missing", new()); }
        try
        {
            using var parsed = JsonDocument.Parse(bytes);
            if (parsed.RootElement.ValueKind != JsonValueKind.Object) throw new InvalidDataException();
            var keys = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in parsed.RootElement.EnumerateObject())
                if (!keys.Add(property.Name)) throw new InvalidDataException();
            return (Hash(bytes), JsonNode.Parse(bytes) as JsonObject ?? throw new InvalidDataException());
        }
        catch (JsonException e) { throw new InvalidDataException("Invalid preferences document.", e); }
    }
    private static PlayerActivityPreferences Parse(JsonObject d)
    {
        var v = new PlayerActivityPreferences(Bool(d,"EnablePlayerActivityNotifications",false),
            Int(d,"PlayerActivityScope",2),Int(d,"PlayerActivityPosition",3),
            Bool(d,"NotifyPlayerOnline",true),Bool(d,"NotifyPlayerOffline",false),
            Bool(d,"NotifyPlayerStartedGame",true),Bool(d,"NotifyPlayerStoppedGame",false),
            Bool(d,"PlayerActivityBackgroundOnly",true),Bool(d,"ReducePlayerActivityNotificationsInGame",true));
        Validate(v); return v;
    }
    private static bool Bool(JsonObject d,string key,bool fallback) => !d.ContainsKey(key) ? fallback :
        d[key] is JsonValue n && n.TryGetValue<bool>(out var v) ? v : throw new InvalidDataException();
    private static int Int(JsonObject d,string key,int fallback) => !d.ContainsKey(key) ? fallback :
        d[key] is JsonValue n && n.TryGetValue<int>(out var v) ? v : throw new InvalidDataException();
    private static void Validate(PlayerActivityPreferences v)
    { if (v.Scope is < 0 or > 7 || v.Position is < 0 or > 3) throw new InvalidDataException(); }
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    private void CheckPaths()
    {
        for (var d = new DirectoryInfo(_root); d is not null; d = d.Parent) Check(d.FullName, true);
        Check(_path, false);
    }
    private static void Check(string path, bool directory)
    {
        try
        {
            var a = File.GetAttributes(path);
            if ((a & FileAttributes.ReparsePoint) != 0 || ((a & FileAttributes.Directory) != 0) != directory)
                throw new IOException("Unsupported settings path.");
        }
        catch (FileNotFoundException) { }
        catch (DirectoryNotFoundException) { }
    }
}
