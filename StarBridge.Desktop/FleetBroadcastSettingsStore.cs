using StarBridge.Core.FleetBroadcasts;
using System.IO;
using System.Text.Json;

namespace StarBridge.Desktop;

internal sealed record FleetBroadcastSenderSettings(
    string Preset,
    double DurationSeconds,
    int RepeatCount,
    double FontScale)
{
    internal static FleetBroadcastSenderSettings Default { get; } = new("emergency", 10, 2, 1);

    internal FleetBroadcastAppearanceContract ToAppearance()
    {
        var colors = Preset.ToLowerInvariant() switch
        {
            "command" => ("#29AFFF", "#E60A2638", "#FFFFFFFF"),
            "rally" => ("#FFC94A", "#E6332A12", "#FFFFFFFF"),
            "medical" => ("#45E58B", "#E60D2A20", "#FFFFFFFF"),
            _ => ("#FF5D66", "#E6101822", "#FFFFFFFF")
        };
        return FleetBroadcastPolicy.NormalizeAppearance(new FleetBroadcastAppearanceContract(
            colors.Item1,
            colors.Item2,
            colors.Item3,
            DurationSeconds,
            RepeatCount,
            FontScale));
    }
}

internal static class FleetBroadcastSettingsStore
{
    private const string FileName = "fleet-broadcast-settings.json";
    private static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web) { WriteIndented = true };

    internal static FleetBroadcastSenderSettings Load(string accountKey)
    {
        try
        {
            var path = Path.Combine(DesktopStorageRoot.CurrentRoot, FileName);
            if (!File.Exists(path))
            {
                return FleetBroadcastSenderSettings.Default;
            }

            var rows = JsonSerializer.Deserialize<Dictionary<string, FleetBroadcastSenderSettings>>(
                File.ReadAllText(path),
                Options);
            return rows is not null && rows.TryGetValue(NormalizeKey(accountKey), out var settings)
                ? Normalize(settings)
                : FleetBroadcastSenderSettings.Default;
        }
        catch
        {
            return FleetBroadcastSenderSettings.Default;
        }
    }

    internal static void Save(string accountKey, FleetBroadcastSenderSettings settings)
    {
        var path = Path.Combine(DesktopStorageRoot.CurrentRoot, FileName);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        Dictionary<string, FleetBroadcastSenderSettings> rows;
        try
        {
            rows = File.Exists(path)
                ? JsonSerializer.Deserialize<Dictionary<string, FleetBroadcastSenderSettings>>(File.ReadAllText(path), Options) ?? []
                : [];
        }
        catch
        {
            rows = [];
        }

        rows[NormalizeKey(accountKey)] = Normalize(settings);
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(rows, Options));
        File.Move(temporary, path, overwrite: true);
    }

    private static FleetBroadcastSenderSettings Normalize(FleetBroadcastSenderSettings? value)
    {
        var settings = value ?? FleetBroadcastSenderSettings.Default;
        var preset = settings.Preset.ToLowerInvariant() is "emergency" or "command" or "rally" or "medical"
            ? settings.Preset.ToLowerInvariant()
            : "emergency";
        return new FleetBroadcastSenderSettings(
            preset,
            Math.Clamp(settings.DurationSeconds, 6, 20),
            Math.Clamp(settings.RepeatCount, 1, 3),
            Math.Clamp(settings.FontScale, 0.9, 1.5));
    }

    private static string NormalizeKey(string? value) =>
        string.IsNullOrWhiteSpace(value) ? "local" : value.Trim().ToLowerInvariant();
}
