namespace StarBridge.HostRuntime.Overlay;

using System.Text;
using System.Text.Json;
using StarBridge.NativeBridge;

internal sealed class OverlaySettingsStore : IOverlaySettingsStore
{
    private readonly string _path;

    internal OverlaySettingsStore(string dataRoot)
    {
        if (string.IsNullOrWhiteSpace(dataRoot))
            throw new ArgumentException("Overlay settings data root is required.", nameof(dataRoot));
        _path = Path.Combine(Path.GetFullPath(dataRoot), "overlay-settings.v1.json");
    }

    public OverlaySettingsReadResult Load()
    {
        try
        {
            if (!File.Exists(_path))
                return new(OverlaySettingsSnapshot.Default, "defaulted");
            var value = JsonSerializer.Deserialize<OverlaySettingsSnapshot>(
                File.ReadAllText(_path), BridgeProtocol.JsonOptions)?.Normalize();
            return value is not null && value.IsSupported()
                ? new(value, "ready")
                : new(OverlaySettingsSnapshot.Default, "recoveredDefaults");
        }
        catch (JsonException)
        {
            return new(OverlaySettingsSnapshot.Default, "recoveredDefaults");
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            throw new OverlaySettingsException("overlay.read_failed", true, exception);
        }
    }

    public void Save(OverlaySettingsSnapshot snapshot)
    {
        snapshot = snapshot.Normalize();
        if (!snapshot.IsSupported())
            throw new OverlaySettingsException("overlay.invalid_value");
        var directory = Path.GetDirectoryName(_path) ?? throw new IOException();
        var temporary = Path.Combine(directory, $".{Path.GetFileName(_path)}.{Guid.NewGuid():N}.tmp");
        try
        {
            Directory.CreateDirectory(directory);
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write,
                       FileShare.None, 4096, FileOptions.WriteThrough))
            using (var writer = new StreamWriter(stream, new UTF8Encoding(false)))
            {
                writer.Write(JsonSerializer.Serialize(snapshot, BridgeProtocol.JsonOptions));
                writer.Flush();
                stream.Flush(true);
            }
            File.Move(temporary, _path, true);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            TryDelete(temporary);
            throw new OverlaySettingsException("overlay.write_failed", true, exception);
        }
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch { }
    }
}
