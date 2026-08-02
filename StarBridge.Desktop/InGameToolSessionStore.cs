using System.IO;
using System.Text.Json;

namespace StarBridge.Desktop;

internal sealed record InGameToolWindowPlacement(
    double Left,
    double Top,
    double Width,
    double Height)
{
    internal AppWindowBounds ToBounds() =>
        new(Left, Top, Width, Height);

    internal static InGameToolWindowPlacement FromBounds(AppWindowBounds bounds) =>
        new(bounds.Left, bounds.Top, bounds.Width, bounds.Height);
}

internal sealed record InGameToolSessionState
{
    public Dictionary<string, InGameToolWindowPlacement> Placements { get; init; } =
        new(StringComparer.OrdinalIgnoreCase);

    public string[] OpenTools { get; init; } = [];

    public string LastFocusedTool { get; init; } = "";

    public string SocialSection { get; init; } = "";

    public bool SessionWasOpen { get; init; }

    internal static InGameToolSessionState Empty { get; } = new();

    internal InGameToolSessionState Normalize()
    {
        var placements = Placements
            .Where(entry =>
                !string.IsNullOrWhiteSpace(entry.Key) &&
                IsUsable(entry.Value))
            .ToDictionary(
                entry => entry.Key.Trim(),
                entry => entry.Value,
                StringComparer.OrdinalIgnoreCase);
        var openTools = OpenTools
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(value => value.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        return this with
        {
            Placements = placements,
            OpenTools = openTools,
            LastFocusedTool = LastFocusedTool?.Trim() ?? "",
            SocialSection = SocialSection?.Trim() ?? ""
        };
    }

    private static bool IsUsable(InGameToolWindowPlacement placement) =>
        double.IsFinite(placement.Left) &&
        double.IsFinite(placement.Top) &&
        double.IsFinite(placement.Width) &&
        double.IsFinite(placement.Height) &&
        placement.Width > 0 &&
        placement.Height > 0;
}

internal sealed class InGameToolSessionStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true
    };

    private readonly string _path;

    internal InGameToolSessionStore(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        _path = path;
    }

    internal static InGameToolSessionStore CreateDefault() =>
        new(Path.Combine(
            DesktopAppConfig.ConfigDirectory,
            "in-game-tool-session.json"));

    internal InGameToolSessionState Load()
    {
        try
        {
            if (!File.Exists(_path))
            {
                return InGameToolSessionState.Empty;
            }

            return JsonSerializer.Deserialize<InGameToolSessionState>(
                       File.ReadAllText(_path),
                       JsonOptions)
                   ?.Normalize() ??
                   InGameToolSessionState.Empty;
        }
        catch
        {
            return InGameToolSessionState.Empty;
        }
    }

    internal bool TrySave(InGameToolSessionState state)
    {
        var temporaryPath = _path + ".tmp";
        try
        {
            var directory = Path.GetDirectoryName(_path);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            File.WriteAllText(
                temporaryPath,
                JsonSerializer.Serialize(state.Normalize(), JsonOptions));
            File.Move(temporaryPath, _path, overwrite: true);
            return true;
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
            TryDelete(temporaryPath);
            return false;
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
            // A later successful save can replace a stale temporary file.
        }
    }
}
