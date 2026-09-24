using System.Text.Json;
namespace StarBridge.HostRuntime.Reminders;

internal interface IContinuousPlayStore
{
    ContinuousPlaySettings ReadSettings();
    ContinuousPlayState ReadState();
    void SaveSettings(ContinuousPlaySettings value);
    void SaveState(ContinuousPlayState value);
}
internal sealed class ContinuousPlayStore(string dataRoot) : IContinuousPlayStore
{
    private readonly string _root = Path.GetFullPath(dataRoot);
    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };
    public ContinuousPlaySettings ReadSettings()
    {
        var value = Read<ContinuousPlaySettings>("local-play-reminder.settings.json") ?? new();
        if (!value.Valid) throw new InvalidDataException();
        return value;
    }
    public ContinuousPlayState ReadState()
    {
        var value = Read<ContinuousPlayState>("local-play-session.json") ?? new();
        if (!value.Valid) throw new InvalidDataException();
        return value;
    }
    public void SaveSettings(ContinuousPlaySettings value) => Write("local-play-reminder.settings.json", value);
    public void SaveState(ContinuousPlayState value) => Write("local-play-session.json", value);
    private T? Read<T>(string name) where T : class
    {
        CheckRoot();
        var path = Path.Combine(_root, name);
        if (!File.Exists(path)) return null;
        var info = new FileInfo(path);
        if (info.Attributes.HasFlag(FileAttributes.ReparsePoint) || info.Length is <= 0 or > 8192) throw new InvalidDataException();
        using var document = JsonDocument.Parse(File.ReadAllBytes(path));
        var names = document.RootElement.EnumerateObject().Select(p => p.Name).ToArray();
        if (names.Distinct(StringComparer.Ordinal).Count() != names.Length) throw new InvalidDataException();
        if (typeof(T) == typeof(ContinuousPlaySettings) &&
            new[] { "Enabled", "FirstReminderMinutes", "RepeatReminderMinutes" }.Except(names).Any()) throw new InvalidDataException();
        return document.RootElement.Deserialize<T>(Json) ?? throw new InvalidDataException();
    }
    private void Write<T>(string name, T value)
    {
        CheckRoot(); Directory.CreateDirectory(_root);
        var path = Path.Combine(_root, name);
        if (File.Exists(path) && File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint)) throw new IOException();
        var temp = Path.Combine(_root, ".play-reminder-" + Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            using (var file = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { JsonSerializer.Serialize(file, value, Json); file.Flush(true); }
            CheckRoot(); File.Move(temp, path, overwrite: true);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
    private void CheckRoot()
    {
        for (var directory = new DirectoryInfo(_root); directory is not null; directory = directory.Parent)
            if (directory.Exists && directory.Attributes.HasFlag(FileAttributes.ReparsePoint)) throw new IOException();
    }
}
