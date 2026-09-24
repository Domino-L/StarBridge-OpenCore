namespace StarBridge.HostRuntime.Notifications;

using System.Text.Json;
using StarBridge.NativeBridge;

internal sealed record AudioSettings(int SchemaVersion = 1, int Revision = 0, bool Enabled = false, double Volume = 0.65, bool DoNotDisturb = false);

// Device-only preference. Never imports or writes WPF account files.
internal sealed class NotificationAudioSettingsStore(string root)
{
    private readonly string _path = Path.Combine(Path.GetFullPath(root), "notification-audio.v1.json");
    internal AudioSettings Read()
    {
        if (!File.Exists(_path)) return new();
        var info = new FileInfo(_path);
        if (info.Length > 4096 || info.Attributes.HasFlag(FileAttributes.ReparsePoint)) throw new IOException("Invalid audio settings");
        var bytes = File.ReadAllBytes(_path);
        using var document = JsonDocument.Parse(bytes);
        var expected = new HashSet<string>(["schemaVersion", "revision", "enabled", "volume"]);
        if (document.RootElement.TryGetProperty("doNotDisturb", out _)) expected.Add("doNotDisturb");
        foreach (var property in document.RootElement.EnumerateObject())
            if (!expected.Remove(property.Name)) throw new IOException("Invalid audio settings");
        if (expected.Count != 0) throw new IOException("Invalid audio settings");
        var value = JsonSerializer.Deserialize<AudioSettings>(bytes, BridgeProtocol.JsonOptions);
        if (value is null || value.SchemaVersion != 1 || value.Revision < 0 || !double.IsFinite(value.Volume) || value.Volume is < 0 or > 1)
            throw new IOException("Invalid audio settings");
        return value;
    }
    internal AudioSettings Save(int revision, bool enabled, double volume, bool? doNotDisturb = null)
    {
        if (!double.IsFinite(volume) || volume is < 0 or > 1) throw new ArgumentException("Invalid volume");
        var current = Read(); // A damaged file is not permission to overwrite it.
        if (current.Revision != revision) throw new AudioConflictException();
        var next = new AudioSettings(Revision: checked(revision + 1), Enabled: enabled, Volume: volume, DoNotDisturb: doNotDisturb ?? current.DoNotDisturb);
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        var temporary = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None)) {
                JsonSerializer.Serialize(stream, next, BridgeProtocol.JsonOptions);
                stream.Flush(true);
            }
            File.Move(temporary, _path, true);
        } finally { if (File.Exists(temporary)) File.Delete(temporary); }
        return next;
    }
}
internal sealed class AudioConflictException : Exception;
