namespace StarBridge.Desktop;

using System.IO;
using System.Text.Json;

internal sealed record DesktopAppConfig(
    string? LogPath,
    string? PlayerName,
    string? PlayerId,
    string? AvatarPath,
    string? OverlayHotkey,
    string? OverlayLayout,
    string? Callsign,
    string? OverlaySettings,
    string? Language,
    string? NetworkServerUrl,
    string? NetworkServerKey,
    string? AccountName,
    string? AuthToken,
    string? FleetStateJson,
    bool AllowEmailNotifications = true,
    bool EnableOverlayGlobalHotkey = true,
    string? AccountId = null,
    DateTimeOffset? FleetStateCachedAtUtc = null)
{
    public static readonly string ConfigDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "StarBridge");

    private static readonly string ConfigPath = Path.Combine(ConfigDirectory, "desktop.config");
    private static readonly string OverlaySettingsPath = Path.Combine(ConfigDirectory, "overlay.settings");
    private static readonly string OverlayLayoutPath = Path.Combine(ConfigDirectory, "overlay.layout");
    private static readonly string OverlayRenderModePath = Path.Combine(ConfigDirectory, "overlay.render-mode");
    private static readonly string ActiveOverlayPresetPath = Path.Combine(ConfigDirectory, "overlay.active-preset");
    private static readonly string OverlayPresetManifestPath = Path.Combine(ConfigDirectory, "overlay.presets");
    private static readonly string EntitlementNoticeStatePath = Path.Combine(ConfigDirectory, "entitlement.notices");
    private static readonly string FallbackConfigDirectory = Path.Combine(AppContext.BaseDirectory, "config");
    private static readonly string FallbackConfigPath = Path.Combine(FallbackConfigDirectory, "desktop.config");
    private static readonly string FallbackOverlaySettingsPath = Path.Combine(FallbackConfigDirectory, "overlay.settings");
    private static readonly string FallbackOverlayLayoutPath = Path.Combine(FallbackConfigDirectory, "overlay.layout");
    private static readonly string FallbackOverlayRenderModePath = Path.Combine(FallbackConfigDirectory, "overlay.render-mode");
    private static readonly string FallbackActiveOverlayPresetPath = Path.Combine(FallbackConfigDirectory, "overlay.active-preset");
    private static readonly string FallbackOverlayPresetManifestPath = Path.Combine(FallbackConfigDirectory, "overlay.presets");
    private static readonly string FallbackEntitlementNoticeStatePath = Path.Combine(FallbackConfigDirectory, "entitlement.notices");

    public static DesktopAppConfig Load()
    {
        var path = File.Exists(ConfigPath)
            ? ConfigPath
            : FallbackConfigPath;

        if (!File.Exists(path))
        {
            return new DesktopAppConfig(null, null, null, null, null, null, null, null, null, null, null, null, null, null);
        }

        string[] lines;
        try
        {
            lines = File.ReadAllLines(path);
        }
        catch
        {
            return new DesktopAppConfig(null, null, null, null, null, null, null, null, null, null, null, null, null, null);
        }

        return new DesktopAppConfig(
            lines.Length > 0 ? EmptyToNull(lines[0]) : null,
            lines.Length > 1 ? EmptyToNull(lines[1]) : null,
            lines.Length > 2 ? EmptyToNull(lines[2]) : null,
            lines.Length > 3 ? EmptyToNull(lines[3]) : null,
            lines.Length > 4 ? EmptyToNull(lines[4]) : null,
            lines.Length > 5 ? EmptyToNull(lines[5]) : null,
            lines.Length > 6 ? EmptyToNull(lines[6]) : null,
            lines.Length > 7 ? EmptyToNull(lines[7]) : null,
            lines.Length > 8 ? EmptyToNull(lines[8]) : null,
            lines.Length > 9 ? EmptyToNull(lines[9]) : null,
            lines.Length > 10 ? LocalSecretProtector.Unprotect(EmptyToNull(lines[10])) : null,
            lines.Length > 11 ? EmptyToNull(lines[11]) : null,
            lines.Length > 12 ? LocalSecretProtector.Unprotect(EmptyToNull(lines[12])) : null,
            lines.Length > 13 ? EmptyToNull(lines[13]) : null,
            lines.Length > 14 && bool.TryParse(lines[14], out var allowEmailNotifications)
                ? allowEmailNotifications
                : true,
            lines.Length > 15 && bool.TryParse(lines[15], out var enableOverlayGlobalHotkey)
                ? enableOverlayGlobalHotkey
                : true,
            lines.Length > 16 ? EmptyToNull(lines[16]) : null,
            lines.Length > 17 && DateTimeOffset.TryParse(
                lines[17],
                System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.RoundtripKind,
                out var fleetStateCachedAtUtc)
                ? fleetStateCachedAtUtc.ToUniversalTime()
                : null);
    }

    public static void Save(DesktopAppConfig config)
    {
        var lines = new[]
        {
            config.LogPath ?? "",
            config.PlayerName ?? "",
            config.PlayerId ?? "",
            config.AvatarPath ?? "",
            config.OverlayHotkey ?? "",
            config.OverlayLayout ?? "",
            config.Callsign ?? "",
            config.OverlaySettings ?? "",
            config.Language ?? "",
            config.NetworkServerUrl ?? "",
            LocalSecretProtector.Protect(config.NetworkServerKey) ?? "",
            config.AccountName ?? "",
            LocalSecretProtector.Protect(config.AuthToken) ?? "",
            config.FleetStateJson ?? "",
            config.AllowEmailNotifications.ToString(),
            config.EnableOverlayGlobalHotkey.ToString(),
            config.AccountId ?? "",
            config.FleetStateCachedAtUtc?.ToUniversalTime().ToString("O", System.Globalization.CultureInfo.InvariantCulture) ?? ""
        };

        try
        {
            Directory.CreateDirectory(ConfigDirectory);
            File.WriteAllLines(ConfigPath, lines);
            return;
        }
        catch
        {
            Directory.CreateDirectory(FallbackConfigDirectory);
            File.WriteAllLines(FallbackConfigPath, lines);
        }
    }

    public static string? LoadOverlaySettings()
    {
        return ReadOptionalText(OverlaySettingsPath) ?? ReadOptionalText(FallbackOverlaySettingsPath);
    }

    public static void SaveOverlaySettings(string value)
    {
        WriteTextWithFallback(OverlaySettingsPath, FallbackOverlaySettingsPath, value);
    }

    public static string? LoadOverlayLayout()
    {
        return ReadOptionalText(OverlayLayoutPath) ?? ReadOptionalText(FallbackOverlayLayoutPath);
    }

    public static void SaveOverlayLayout(string value)
    {
        WriteTextWithFallback(OverlayLayoutPath, FallbackOverlayLayoutPath, value);
    }

    public static string? LoadOverlayRenderMode()
    {
        return ReadOptionalText(OverlayRenderModePath) ?? ReadOptionalText(FallbackOverlayRenderModePath);
    }

    public static void SaveOverlayRenderMode(string value)
    {
        WriteTextWithFallback(OverlayRenderModePath, FallbackOverlayRenderModePath, value);
    }

    public static string? LoadActiveOverlayPreset()
    {
        return ReadOptionalText(ActiveOverlayPresetPath) ?? ReadOptionalText(FallbackActiveOverlayPresetPath);
    }

    public static void SaveActiveOverlayPreset(string value)
    {
        WriteTextWithFallback(ActiveOverlayPresetPath, FallbackActiveOverlayPresetPath, value);
    }

    public static string? LoadOverlayPresetManifest()
    {
        return ReadOptionalText(OverlayPresetManifestPath) ?? ReadOptionalText(FallbackOverlayPresetManifestPath);
    }

    public static void SaveOverlayPresetManifest(string value)
    {
        WriteTextWithFallback(OverlayPresetManifestPath, FallbackOverlayPresetManifestPath, value);
    }

    public static HashSet<string> LoadAcknowledgedEntitlementNotices()
    {
        var payload = ReadOptionalText(EntitlementNoticeStatePath) ??
                      ReadOptionalText(FallbackEntitlementNoticeStatePath);
        if (string.IsNullOrWhiteSpace(payload))
        {
            return new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        }

        try
        {
            return new HashSet<string>(
                JsonSerializer.Deserialize<string[]>(payload) ?? [],
                StringComparer.OrdinalIgnoreCase);
        }
        catch (JsonException)
        {
            return new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        }
    }

    public static void SaveAcknowledgedEntitlementNotices(IEnumerable<string> noticeKeys)
    {
        var payload = JsonSerializer.Serialize(noticeKeys
            .Where(key => !string.IsNullOrWhiteSpace(key))
            .Select(key => key.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(key => key, StringComparer.OrdinalIgnoreCase)
            .ToArray());
        WriteTextWithFallback(
            EntitlementNoticeStatePath,
            FallbackEntitlementNoticeStatePath,
            payload);
    }

    public static string? LoadOverlayPresetSettings(string preset)
    {
        return ReadOptionalText(GetPresetPath(ConfigDirectory, preset, "settings")) ??
               ReadOptionalText(GetPresetPath(FallbackConfigDirectory, preset, "settings"));
    }

    public static void SaveOverlayPresetSettings(string preset, string value)
    {
        WriteTextWithFallback(
            GetPresetPath(ConfigDirectory, preset, "settings"),
            GetPresetPath(FallbackConfigDirectory, preset, "settings"),
            value);
    }

    public static string? LoadOverlayPresetLayout(string preset)
    {
        return ReadOptionalText(GetPresetPath(ConfigDirectory, preset, "layout")) ??
               ReadOptionalText(GetPresetPath(FallbackConfigDirectory, preset, "layout"));
    }

    public static void SaveOverlayPresetLayout(string preset, string value)
    {
        WriteTextWithFallback(
            GetPresetPath(ConfigDirectory, preset, "layout"),
            GetPresetPath(FallbackConfigDirectory, preset, "layout"),
            value);
    }

    public static void DeleteOverlayPreset(string preset)
    {
        DeleteOptionalFile(GetPresetPath(ConfigDirectory, preset, "settings"));
        DeleteOptionalFile(GetPresetPath(FallbackConfigDirectory, preset, "settings"));
        DeleteOptionalFile(GetPresetPath(ConfigDirectory, preset, "layout"));
        DeleteOptionalFile(GetPresetPath(FallbackConfigDirectory, preset, "layout"));
    }

    private static string? EmptyToNull(string value)
    {
        return string.IsNullOrWhiteSpace(value) ? null : value;
    }

    private static string GetPresetPath(string directory, string preset, string kind)
    {
        var safePreset = new string(preset.Select(character =>
            char.IsLetterOrDigit(character) ? character : '-').ToArray()).ToLowerInvariant();
        return Path.Combine(directory, $"overlay.{safePreset}.{kind}");
    }

    private static string? ReadOptionalText(string path)
    {
        try
        {
            return File.Exists(path) ? EmptyToNull(File.ReadAllText(path)) : null;
        }
        catch
        {
            return null;
        }
    }

    private static void DeleteOptionalFile(string path)
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
            // Best effort cleanup; stale preset files are harmless and should not block the UI.
        }
    }

    private static void WriteTextWithFallback(string path, string fallbackPath, string value)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, value);
            return;
        }
        catch
        {
            Directory.CreateDirectory(Path.GetDirectoryName(fallbackPath)!);
            File.WriteAllText(fallbackPath, value);
        }
    }
}
