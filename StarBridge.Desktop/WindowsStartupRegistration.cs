using Microsoft.Win32;
using System.Diagnostics;

namespace StarBridge.Desktop;

internal static class WindowsStartupRegistration
{
    internal const string StartupArgument = "--startup";
    internal const string RegistryPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    internal const string RegistryValueName = "StarBridge";

    public static bool IsStartupLaunch(IEnumerable<string>? arguments) =>
        (arguments ?? []).Any(argument =>
            StartupArgument.Equals(argument?.Trim(), StringComparison.OrdinalIgnoreCase));

    public static bool ShouldStartInBackground(
        IEnumerable<string>? arguments,
        ApplicationBehaviorSettings settings)
    {
        var normalized = settings.Normalize();
        return IsStartupLaunch(arguments) &&
               normalized.StartMinimized;
    }

    public static string BuildCommand(string executablePath)
    {
        var normalizedPath = (executablePath ?? "").Trim().Trim('"');
        return $"\"{normalizedPath}\" {StartupArgument}";
    }

    public static bool TrySetEnabled(bool enabled, out string? error)
    {
        try
        {
            if (!enabled)
            {
                using var existingKey = Registry.CurrentUser.OpenSubKey(RegistryPath, writable: true);
                existingKey?.DeleteValue(RegistryValueName, throwOnMissingValue: false);
                error = null;
                return true;
            }

            var executablePath = Environment.ProcessPath ??
                                 Process.GetCurrentProcess().MainModule?.FileName;
            if (string.IsNullOrWhiteSpace(executablePath))
            {
                error = "无法确定应用程序路径。";
                return false;
            }

            using var key = Registry.CurrentUser.CreateSubKey(RegistryPath, writable: true);
            if (key is null)
            {
                error = "无法打开当前用户的开机启动设置。";
                return false;
            }

            key.SetValue(RegistryValueName, BuildCommand(executablePath), RegistryValueKind.String);
            error = null;
            return true;
        }
        catch (Exception ex)
        {
            error = UserFacingError.Describe(ex, "无法更新开机启动设置，请稍后重试。");
            return false;
        }
    }

    public static bool TryGetEnabled(out bool enabled, out string? error)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RegistryPath, writable: false);
            enabled = key?.GetValue(RegistryValueName) is string value && !string.IsNullOrWhiteSpace(value);
            error = null;
            return true;
        }
        catch (Exception ex)
        {
            enabled = false;
            error = UserFacingError.Describe(ex, "无法读取开机启动状态，请稍后重试。");
            return false;
        }
    }
}

internal sealed record ApplicationBehaviorApplyResult(
    bool Succeeded,
    ApplicationBehaviorSettings Settings,
    string? Error = null);
