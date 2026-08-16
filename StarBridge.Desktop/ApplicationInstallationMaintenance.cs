using Microsoft.Win32;
using System.Diagnostics;
using System.IO;

namespace StarBridge.Desktop;

internal enum StarBridgeRegistryHive
{
    CurrentUser,
    LocalMachine
}

internal sealed record StarBridgeInstallationEntry(
    StarBridgeRegistryHive Hive,
    RegistryView View,
    string RegistryKeyName,
    string DisplayName,
    string DisplayVersion,
    string InstallDirectory,
    string UninstallExecutable,
    string UninstallArguments,
    bool UninstallerExists,
    bool IsCurrentInstallation)
{
    public bool IsOrphaned => !UninstallerExists;
}

internal sealed record StarBridgeStartupEntry(
    string Command,
    string ExecutablePath,
    bool TargetExists,
    bool TargetsCurrentExecutable)
{
    public bool NeedsCleanup => !TargetExists || !TargetsCurrentExecutable;
}

internal sealed record StarBridgeInstallationScan(
    string CurrentExecutable,
    IReadOnlyList<StarBridgeInstallationEntry> Installations,
    StarBridgeStartupEntry? StartupEntry,
    IReadOnlyList<string> ScanWarnings)
{
    public IReadOnlyList<StarBridgeInstallationEntry> OtherInstallations =>
        Installations.Where(entry => !entry.IsCurrentInstallation).ToArray();

    public IReadOnlyList<StarBridgeInstallationEntry> OrphanedRegistrations =>
        Installations.Where(entry => entry.IsOrphaned).ToArray();

    public bool HasMaintenanceIssue =>
        Installations.Count(entry => entry.IsCurrentInstallation && entry.UninstallerExists) != 1 ||
        OtherInstallations.Count > 0 ||
        OrphanedRegistrations.Count > 0 ||
        StartupEntry?.NeedsCleanup == true ||
        ScanWarnings.Count > 0;
}

internal sealed record StarBridgeCleanupResult(
    int RemovedUninstallRegistrations,
    bool RemovedStartupEntry,
    IReadOnlyList<string> Errors);

internal static class ApplicationInstallationMaintenance
{
    internal const string InstallerAppId = "8F0E3D89-0DC1-4C51-8B6C-1BC7BA90378F";
    internal const string UninstallRegistryPath = @"Software\Microsoft\Windows\CurrentVersion\Uninstall";

    public static bool IsReadOnlyPreviewBuild
    {
        get
        {
#if DEBUG
            return true;
#else
            return false;
#endif
        }
    }

    public static StarBridgeInstallationScan Scan(string? currentExecutable = null)
    {
        var normalizedCurrentExecutable = NormalizePath(
            currentExecutable ?? Environment.ProcessPath ?? "");
        var installations = new List<StarBridgeInstallationEntry>();
        var warnings = new List<string>();

        foreach (var hive in new[] { StarBridgeRegistryHive.CurrentUser, StarBridgeRegistryHive.LocalMachine })
        {
            foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
            {
                ScanInstallations(hive, view, normalizedCurrentExecutable, installations, warnings);
            }
        }

        var distinctInstallations = installations
            .DistinctBy(entry => $"{entry.Hive}|{entry.View}|{entry.RegistryKeyName}", StringComparer.OrdinalIgnoreCase)
            .ToArray();

        return new StarBridgeInstallationScan(
            normalizedCurrentExecutable,
            distinctInstallations,
            ReadStartupEntry(normalizedCurrentExecutable, warnings),
            warnings);
    }

    public static StarBridgeInstallationEntry? SelectUninstallTarget(StarBridgeInstallationScan scan)
    {
        ArgumentNullException.ThrowIfNull(scan);
        return scan.Installations
                   .Where(entry => entry.UninstallerExists && !entry.IsCurrentInstallation)
                   .OrderBy(entry => ParseVersion(entry.DisplayVersion))
                   .FirstOrDefault() ??
               scan.Installations.FirstOrDefault(entry =>
                   entry.UninstallerExists && entry.IsCurrentInstallation);
    }

    public static string Describe(StarBridgeInstallationScan scan)
    {
        ArgumentNullException.ThrowIfNull(scan);
        var current = scan.Installations.Count(entry => entry.IsCurrentInstallation && entry.UninstallerExists);
        var other = scan.OtherInstallations.Count(entry => entry.UninstallerExists);
        var orphaned = scan.OrphanedRegistrations.Count;
        var staleStartup = scan.StartupEntry?.NeedsCleanup == true ? 1 : 0;

        if (current == 1 && other == 0 && orphaned == 0 && staleStartup == 0 && scan.ScanWarnings.Count == 0)
        {
            return "当前正式安装与开机启动项正常";
        }

        var details = new List<string>();
        if (current == 0)
        {
            details.Add("当前运行副本没有对应的正式安装项");
        }
        else if (current > 1)
        {
            details.Add($"当前目录存在 {current} 个重复安装项");
        }

        if (other > 0)
        {
            details.Add($"发现 {other} 个其他安装实例");
        }

        if (orphaned > 0)
        {
            details.Add($"发现 {orphaned} 个失效卸载项");
        }

        if (staleStartup > 0)
        {
            details.Add("开机启动项指向其他或不存在的程序");
        }

        if (scan.ScanWarnings.Count > 0)
        {
            details.Add($"有 {scan.ScanWarnings.Count} 处注册信息无法读取");
        }

        return details.Count == 0 ? "未发现需要处理的安装残留" : string.Join("；", details);
    }

    public static StarBridgeCleanupResult CleanupOrphansAndStaleStartup(StarBridgeInstallationScan scan)
    {
        ArgumentNullException.ThrowIfNull(scan);
        var removedRegistrations = 0;
        var removedStartup = false;
        var errors = new List<string>();

        foreach (var entry in scan.OrphanedRegistrations)
        {
            try
            {
                using var baseKey = OpenBaseKey(entry.Hive, entry.View);
                using var uninstallKey = baseKey.OpenSubKey(UninstallRegistryPath, writable: true);
                if (uninstallKey is null || !IsInstallerRegistryKey(entry.RegistryKeyName))
                {
                    continue;
                }

                uninstallKey.DeleteSubKeyTree(entry.RegistryKeyName, throwOnMissingSubKey: false);
                removedRegistrations++;
            }
            catch (Exception ex)
            {
                errors.Add(UserFacingError.Describe(ex, $"无法移除 {entry.DisplayName} {entry.DisplayVersion} 的失效卸载项。"));
            }
        }

        if (scan.StartupEntry?.NeedsCleanup == true)
        {
            try
            {
                using var runKey = Registry.CurrentUser.OpenSubKey(
                    WindowsStartupRegistration.RegistryPath,
                    writable: true);
                runKey?.DeleteValue(WindowsStartupRegistration.RegistryValueName, throwOnMissingValue: false);
                removedStartup = true;
            }
            catch (Exception ex)
            {
                errors.Add(UserFacingError.Describe(ex, "无法移除失效的开机启动项。"));
            }
        }

        return new StarBridgeCleanupResult(removedRegistrations, removedStartup, errors);
    }

    public static bool TryStartUninstaller(
        StarBridgeInstallationEntry entry,
        out string? error)
    {
        ArgumentNullException.ThrowIfNull(entry);
        try
        {
            if (!entry.UninstallerExists ||
                !IsTrustedUninstallerPath(entry.UninstallExecutable, entry.InstallDirectory))
            {
                error = "官方卸载器不存在或路径无效。";
                return false;
            }

            Process.Start(new ProcessStartInfo
            {
                FileName = entry.UninstallExecutable,
                Arguments = entry.UninstallArguments,
                UseShellExecute = true,
                WorkingDirectory = Path.GetDirectoryName(entry.UninstallExecutable) ?? ""
            });
            error = null;
            return true;
        }
        catch (Exception ex)
        {
            error = UserFacingError.Describe(ex, "无法启动官方卸载器，请在 Windows 已安装的应用中卸载星海舰桥。");
            return false;
        }
    }

    internal static bool IsInstallerRegistryKey(string? keyName) =>
        !string.IsNullOrWhiteSpace(keyName) &&
        (keyName.Trim().Equals($"{{{InstallerAppId}}}_is1", StringComparison.OrdinalIgnoreCase) ||
         keyName.Trim().Equals($"{InstallerAppId}_is1", StringComparison.OrdinalIgnoreCase));

    internal static bool TryParseCommand(
        string? command,
        out string executable,
        out string arguments)
    {
        executable = "";
        arguments = "";
        var value = Environment.ExpandEnvironmentVariables(command?.Trim() ?? "");
        if (value.Length == 0)
        {
            return false;
        }

        if (value[0] == '"')
        {
            var closingQuote = value.IndexOf('"', 1);
            if (closingQuote <= 1)
            {
                return false;
            }

            executable = value[1..closingQuote];
            arguments = value[(closingQuote + 1)..].Trim();
        }
        else
        {
            var executableEnd = value.IndexOf(".exe", StringComparison.OrdinalIgnoreCase);
            if (executableEnd < 0)
            {
                return false;
            }

            executableEnd += 4;
            executable = value[..executableEnd].Trim();
            arguments = value[executableEnd..].Trim();
        }

        executable = NormalizePath(executable);
        return Path.IsPathFullyQualified(executable) &&
               ".exe".Equals(Path.GetExtension(executable), StringComparison.OrdinalIgnoreCase);
    }

    internal static bool PathsEqual(string? first, string? second) =>
        !string.IsNullOrWhiteSpace(first) &&
        !string.IsNullOrWhiteSpace(second) &&
        NormalizePath(first).Equals(NormalizePath(second), StringComparison.OrdinalIgnoreCase);

    private static void ScanInstallations(
        StarBridgeRegistryHive hive,
        RegistryView view,
        string currentExecutable,
        ICollection<StarBridgeInstallationEntry> installations,
        ICollection<string> warnings)
    {
        try
        {
            using var baseKey = OpenBaseKey(hive, view);
            using var uninstallKey = baseKey.OpenSubKey(UninstallRegistryPath, writable: false);
            if (uninstallKey is null)
            {
                return;
            }

            foreach (var keyName in uninstallKey.GetSubKeyNames().Where(IsInstallerRegistryKey))
            {
                try
                {
                    using var entryKey = uninstallKey.OpenSubKey(keyName, writable: false);
                    if (entryKey is null)
                    {
                        continue;
                    }

                    var displayName = ReadString(entryKey, "DisplayName", "星海舰桥");
                    var displayVersion = ReadString(entryKey, "DisplayVersion", "未知版本");
                    var installDirectory = NormalizePath(ReadString(entryKey, "InstallLocation", ""));
                    var uninstallCommand = ReadString(entryKey, "UninstallString", "");
                    TryParseCommand(uninstallCommand, out var uninstallExecutable, out var uninstallArguments);
                    if (installDirectory.Length == 0 && uninstallExecutable.Length > 0)
                    {
                        installDirectory = NormalizePath(Path.GetDirectoryName(uninstallExecutable) ?? "");
                    }

                    var isCurrent = PathsEqual(installDirectory, Path.GetDirectoryName(currentExecutable)) ||
                                    PathsEqual(
                                        Path.Combine(installDirectory, "Star Bridge.exe"),
                                        currentExecutable);
                    installations.Add(new StarBridgeInstallationEntry(
                        hive,
                        view,
                        keyName,
                        displayName,
                        displayVersion,
                        installDirectory,
                        uninstallExecutable,
                        uninstallArguments,
                        IsTrustedUninstallerPath(uninstallExecutable, installDirectory) && File.Exists(uninstallExecutable),
                        isCurrent));
                }
                catch (Exception ex)
                {
                    warnings.Add($"{hive}/{view}/{keyName}: {ex.Message}");
                }
            }
        }
        catch (Exception ex)
        {
            warnings.Add($"{hive}/{view}: {ex.Message}");
        }
    }

    private static StarBridgeStartupEntry? ReadStartupEntry(
        string currentExecutable,
        ICollection<string> warnings)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                WindowsStartupRegistration.RegistryPath,
                writable: false);
            if (key?.GetValue(WindowsStartupRegistration.RegistryValueName) is not string command ||
                string.IsNullOrWhiteSpace(command))
            {
                return null;
            }

            TryParseCommand(command, out var executable, out _);
            return new StarBridgeStartupEntry(
                command,
                executable,
                File.Exists(executable),
                PathsEqual(executable, currentExecutable));
        }
        catch (Exception ex)
        {
            warnings.Add($"开机启动项: {ex.Message}");
            return null;
        }
    }

    private static RegistryKey OpenBaseKey(StarBridgeRegistryHive hive, RegistryView view) =>
        RegistryKey.OpenBaseKey(
            hive == StarBridgeRegistryHive.CurrentUser ? RegistryHive.CurrentUser : RegistryHive.LocalMachine,
            view);

    private static bool IsTrustedUninstallerPath(string? path, string? installDirectory = null)
    {
        if (string.IsNullOrWhiteSpace(path) || !Path.IsPathFullyQualified(path))
        {
            return false;
        }

        var fileName = Path.GetFileName(path);
        var isInInstallDirectory = string.IsNullOrWhiteSpace(installDirectory) ||
                                   PathsEqual(Path.GetDirectoryName(path), installDirectory);
        return isInInstallDirectory &&
               fileName.StartsWith("unins", StringComparison.OrdinalIgnoreCase) &&
               ".exe".Equals(Path.GetExtension(fileName), StringComparison.OrdinalIgnoreCase);
    }

    private static string ReadString(RegistryKey key, string name, string fallback) =>
        key.GetValue(name) is string value && !string.IsNullOrWhiteSpace(value)
            ? value.Trim()
            : fallback;

    private static string NormalizePath(string? path)
    {
        var value = (path ?? "").Trim().Trim('"');
        if (value.Length == 0)
        {
            return "";
        }

        try
        {
            return Path.TrimEndingDirectorySeparator(Path.GetFullPath(value));
        }
        catch
        {
            return value;
        }
    }

    private static Version ParseVersion(string? value) =>
        Version.TryParse(value, out var version) ? version : new Version();
}
