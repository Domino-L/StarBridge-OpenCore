using System.IO;
using System.Text.Json;

namespace StarBridge.Desktop;

internal sealed record ApplicationBehaviorSettings(
    bool LaunchAtStartup,
    bool KeepRunningInBackground,
    bool StartMinimized,
    bool BackgroundHintShown,
    bool CloseBehaviorChoiceMade = false)
{
    public static ApplicationBehaviorSettings Default { get; } = new(
        LaunchAtStartup: false,
        KeepRunningInBackground: false,
        StartMinimized: false,
        BackgroundHintShown: false,
        CloseBehaviorChoiceMade: false);

    public ApplicationBehaviorSettings Normalize()
    {
        return this with
        {
            StartMinimized = LaunchAtStartup && StartMinimized
        };
    }

    public string Serialize() => JsonSerializer.Serialize(Normalize());

    public bool ShouldPromptForCloseBehavior(
        bool isExplicitExitRequested,
        bool isUpdateRestartRequested)
    {
        return !KeepRunningInBackground &&
               !CloseBehaviorChoiceMade &&
               !isExplicitExitRequested &&
               !isUpdateRestartRequested;
    }

    public static ApplicationBehaviorSettings Parse(string? payload)
    {
        if (string.IsNullOrWhiteSpace(payload))
        {
            return Default;
        }

        try
        {
            return (JsonSerializer.Deserialize<ApplicationBehaviorSettings>(payload) ?? Default).Normalize();
        }
        catch (JsonException)
        {
            return Default;
        }
    }
}

internal static class ApplicationClosePromptCopy
{
    public static string Build(bool isGameplayDataRecordingEnabled)
    {
        const string backgroundOutcome =
            "保持后台运行后，星海舰桥会进入系统托盘，并继续提供状态同步、游戏记录与通知。";
        const string settingsHint = "你可以随时在应用设置中更改关闭行为。";
        if (!isGameplayDataRecordingEnabled)
        {
            return $"{backgroundOutcome}\n\n{settingsHint}";
        }

        const string recordingWarning =
            "你已开启游玩时长记录。完全退出后，星海舰桥无法累计退出期间的游玩时长。若准备继续游戏，建议保持后台运行。";
        return $"{backgroundOutcome}\n\n{recordingWarning}\n\n{settingsHint}";
    }
}

internal static class ApplicationBehaviorSettingsStore
{
    private static readonly string SettingsPath = Path.Combine(
        DesktopAppConfig.ConfigDirectory,
        "application-behavior.json");

    public static ApplicationBehaviorSettings Load()
    {
        try
        {
            return File.Exists(SettingsPath)
                ? ApplicationBehaviorSettings.Parse(File.ReadAllText(SettingsPath))
                : ApplicationBehaviorSettings.Default;
        }
        catch
        {
            return ApplicationBehaviorSettings.Default;
        }
    }

    public static bool TrySave(ApplicationBehaviorSettings settings, out string? error)
    {
        var temporaryPath = SettingsPath + ".tmp";
        try
        {
            Directory.CreateDirectory(DesktopAppConfig.ConfigDirectory);
            File.WriteAllText(temporaryPath, settings.Normalize().Serialize());
            File.Move(temporaryPath, SettingsPath, overwrite: true);
            error = null;
            return true;
        }
        catch (Exception ex)
        {
            TryDeleteTemporaryFile(temporaryPath);
            error = UserFacingError.Describe(ex, "启动与后台设置未保存，请稍后重试。");
            return false;
        }
    }

    private static void TryDeleteTemporaryFile(string path)
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
            // A stale temporary file can be replaced by the next successful save.
        }
    }
}
