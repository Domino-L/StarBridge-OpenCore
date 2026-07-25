using System.IO;
using System.Text.Json;

namespace StarBridge.Desktop;

internal sealed record LocalPlayReminderSettings(
    bool Enabled = true,
    int FirstReminderMinutes = 120,
    int RepeatReminderMinutes = 120)
{
    private static readonly int[] SupportedFirstReminderMinutes = [60, 90, 120, 180];
    private static readonly int[] SupportedRepeatReminderMinutes = [60, 120];

    public static LocalPlayReminderSettings Default { get; } = new();

    public TimeSpan FirstReminderDelay => TimeSpan.FromMinutes(FirstReminderMinutes);

    public TimeSpan RepeatReminderDelay => TimeSpan.FromMinutes(RepeatReminderMinutes);

    public LocalPlayReminderSettings Normalize() => this with
    {
        FirstReminderMinutes = SupportedFirstReminderMinutes.Contains(FirstReminderMinutes)
            ? FirstReminderMinutes
            : Default.FirstReminderMinutes,
        RepeatReminderMinutes = SupportedRepeatReminderMinutes.Contains(RepeatReminderMinutes)
            ? RepeatReminderMinutes
            : Default.RepeatReminderMinutes
    };
}

internal static class LocalPlayReminderSettingsStore
{
    private static readonly string SettingsPath = Path.Combine(
        DesktopAppConfig.ConfigDirectory,
        "local-play-reminder.settings.json");

    public static LocalPlayReminderSettings Load(bool? legacyEnabled = null)
    {
        try
        {
            return File.Exists(SettingsPath)
                ? (JsonSerializer.Deserialize<LocalPlayReminderSettings>(File.ReadAllText(SettingsPath)) ??
                   LocalPlayReminderSettings.Default).Normalize()
                : LocalPlayReminderSettings.Default with { Enabled = legacyEnabled ?? LocalPlayReminderSettings.Default.Enabled };
        }
        catch
        {
            return LocalPlayReminderSettings.Default;
        }
    }

    public static bool TrySave(LocalPlayReminderSettings settings, out string? error)
    {
        var temporaryPath = SettingsPath + ".tmp";
        try
        {
            Directory.CreateDirectory(DesktopAppConfig.ConfigDirectory);
            File.WriteAllText(
                temporaryPath,
                JsonSerializer.Serialize(settings.Normalize(), new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temporaryPath, SettingsPath, overwrite: true);
            error = null;
            return true;
        }
        catch (Exception ex)
        {
            try
            {
                if (File.Exists(temporaryPath))
                {
                    File.Delete(temporaryPath);
                }
            }
            catch
            {
                // The next successful save can replace a stale temporary file.
            }

            error = UserFacingError.Describe(ex, "连续游玩提醒设置未保存，请稍后重试。");
            return false;
        }
    }
}
