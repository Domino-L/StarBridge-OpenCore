namespace StarBridge.HostRuntime.Support;

using Microsoft.Win32;
using StarBridge.HostRuntime.Settings;
using System.Diagnostics;

internal sealed class WindowsApplicationSupportInspector :
    IApplicationSupportInspector,
    IApplicationSupportActions,
    IApplicationDataLocationReader
{
    internal const string InstallerAppId = FlutterInstallationIdentity.AppId;
    private const string UninstallRegistryPath =
        @"Software\Microsoft\Windows\CurrentVersion\Uninstall";

    private readonly string _dataRoot;
    private readonly string _currentExecutable;
    private readonly Func<string?> _gameLogPath;
    private readonly Action<string> _openDirectory;

    internal WindowsApplicationSupportInspector(
        string dataRoot,
        string? currentExecutable,
        Func<string?>? gameLogPath = null,
        Action<string>? openDirectory = null,
        Func<ProcessStartInfo, Process?>? shellStart = null)
    {
        if (string.IsNullOrWhiteSpace(dataRoot))
        {
            throw new ArgumentException(
                "Application data root is required.",
                nameof(dataRoot));
        }

        _dataRoot = NormalizePath(dataRoot);
        _currentExecutable = NormalizePath(currentExecutable);
        _gameLogPath = gameLogPath ?? (() => null);
        _openDirectory = openDirectory ?? (path => OpenDirectory(path, shellStart ?? Process.Start));
    }

    public ApplicationSupportSnapshot Inspect() => new(
        InspectDataDirectory(),
        InspectGameLog(),
        InspectStartup(),
        InspectInstallations());

    public void OpenDataDirectory()
    {
        if (!Directory.Exists(_dataRoot))
        {
            throw new DirectoryNotFoundException();
        }

        _openDirectory(_dataRoot);
    }

    public int ClearImageCache() => ImageCacheMaintenance.Clear(_dataRoot);

    public void OpenInstalledApps() => Process.Start(new ProcessStartInfo
    {
        FileName = "ms-settings:appsfeatures", UseShellExecute = true
    });

    public ApplicationDataLocation GetDataLocation()
    {
        if (!Path.IsPathFullyQualified(_dataRoot))
            throw new InvalidOperationException();
        return new(_dataRoot, Directory.Exists(_dataRoot));
    }

    private ApplicationSupportCheck InspectDataDirectory()
    {
        if (_dataRoot.Length == 0)
        {
            return new(
                ApplicationSupportStates.Unavailable,
                "pathNotConfigured");
        }

        if (!Directory.Exists(_dataRoot))
        {
            return new(
                ApplicationSupportStates.ActionRequired,
                "pathMissing");
        }

        var probePath = Path.Combine(
            _dataRoot,
            $".starbridge-write-check-{Guid.NewGuid():N}.tmp");
        try
        {
            using (var stream = new FileStream(
                       probePath,
                       FileMode.CreateNew,
                       FileAccess.Write,
                       FileShare.None,
                       bufferSize: 1,
                       FileOptions.WriteThrough))
            {
                stream.WriteByte(0);
                stream.Flush(flushToDisk: true);
            }
            File.Delete(probePath);
            return new(ApplicationSupportStates.Healthy, "writable");
        }
        catch (UnauthorizedAccessException)
        {
            TryDelete(probePath);
            return new(
                ApplicationSupportStates.ActionRequired,
                "accessDenied");
        }
        catch (Exception exception) when (
            exception is IOException or NotSupportedException)
        {
            TryDelete(probePath);
            return new(
                ApplicationSupportStates.ActionRequired,
                "writeFailed");
        }
    }

    private ApplicationSupportCheck InspectGameLog()
    {
        string path;
        try
        {
            path = NormalizePath(_gameLogPath());
        }
        catch
        {
            return new(
                ApplicationSupportStates.Unavailable,
                "selectionUnavailable");
        }

        if (path.Length == 0)
        {
            return new(
                ApplicationSupportStates.ActionRequired,
                "notConfigured");
        }

        if (!File.Exists(path))
        {
            return new(
                ApplicationSupportStates.ActionRequired,
                "fileMissing");
        }

        try
        {
            using var stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);
            _ = stream.Length;
            return new(ApplicationSupportStates.Healthy, "readable");
        }
        catch (UnauthorizedAccessException)
        {
            return new(
                ApplicationSupportStates.ActionRequired,
                "accessDenied");
        }
        catch (Exception exception) when (
            exception is IOException or NotSupportedException)
        {
            return new(
                ApplicationSupportStates.ActionRequired,
                "readFailed");
        }
    }

    private ApplicationStartupCheck InspectStartup()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                WindowsApplicationStartupRegistration.RegistryPath,
                writable: false);
            if (key?.GetValue(WindowsApplicationStartupRegistration.RegistryValueName)
                is not string command || string.IsNullOrWhiteSpace(command))
            {
                return new(
                    ApplicationSupportStates.Healthy,
                    "notEnabled",
                    Registered: false,
                    TargetExists: null,
                    TargetsCurrentExecutable: null);
            }

            if (!TryParseCommand(command, out var executable))
            {
                return new(
                    ApplicationSupportStates.ActionRequired,
                    "invalidCommand",
                    Registered: true,
                    TargetExists: false,
                    TargetsCurrentExecutable: false);
            }

            var targetExists = File.Exists(executable);
            var targetsCurrent = PathsEqual(executable, _currentExecutable);
            var healthy = targetExists && targetsCurrent;
            return new(
                healthy
                    ? ApplicationSupportStates.Healthy
                    : ApplicationSupportStates.ActionRequired,
                healthy
                    ? "enabled"
                    : targetExists ? "targetMismatch" : "targetMissing",
                Registered: true,
                TargetExists: targetExists,
                TargetsCurrentExecutable: targetsCurrent);
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or
            System.Security.SecurityException)
        {
            return new(
                ApplicationSupportStates.Unavailable,
                "readFailed",
                Registered: false,
                TargetExists: null,
                TargetsCurrentExecutable: null);
        }
    }

    private ApplicationInstallationCheck InspectInstallations()
    {
        var entries = new List<InstallationEntry>();
        var warnings = 0;
        foreach (var hive in new[] { RegistryHive.CurrentUser, RegistryHive.LocalMachine })
        {
            foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
            {
                // HKCU Uninstall is shared between views; do not count it twice.
                if (hive == RegistryHive.CurrentUser && view == RegistryView.Registry32) continue;
                try
                {
                    using var baseKey = RegistryKey.OpenBaseKey(hive, view);
                    using var uninstall = baseKey.OpenSubKey(
                        UninstallRegistryPath,
                        writable: false);
                    if (uninstall is null)
                    {
                        continue;
                    }

                    foreach (var keyName in uninstall.GetSubKeyNames().Where(IsInstallerRegistryKey))
                    {
                        try
                        {
                            using var key = uninstall.OpenSubKey(keyName, writable: false);
                            if (key is not null)
                            {
                                entries.Add(ReadInstallation(key));
                            }
                        }
                        catch
                        {
                            warnings++;
                        }
                    }
                }
                catch
                {
                    warnings++;
                }
            }
        }

        return ClassifyInstallations(entries, warnings);
    }

    private InstallationEntry ReadInstallation(RegistryKey key)
    {
        var installDirectory = NormalizePath(ReadString(key, "InstallLocation"));
        TryParseCommand(ReadString(key, "UninstallString"), out var uninstaller);
        if (installDirectory.Length == 0 && uninstaller.Length > 0)
        {
            installDirectory = NormalizePath(Path.GetDirectoryName(uninstaller));
        }

        var validUninstaller = IsTrustedUninstallerPath(uninstaller, installDirectory) &&
                               File.Exists(uninstaller);
        var isCurrent = PathsEqual(
            installDirectory,
            Path.GetDirectoryName(_currentExecutable));
        return new InstallationEntry(validUninstaller, isCurrent);
    }

    internal static ApplicationInstallationCheck ClassifyInstallations(
        IReadOnlyCollection<InstallationEntry> entries,
        int warnings)
    {
        var current = entries.Count(item => item.ValidUninstaller && item.IsCurrent);
        var other = entries.Count(item => item.ValidUninstaller && !item.IsCurrent);
        var orphaned = entries.Count(item => !item.ValidUninstaller);
        var total = entries.Count;

        if (total == 0 && warnings == 0)
        {
            return new(
                ApplicationSupportStates.Healthy,
                "portable",
                "portable",
                current,
                other,
                orphaned,
                warnings);
        }

        if (current == 1 && other == 0 && orphaned == 0 && warnings == 0)
        {
            return new(
                ApplicationSupportStates.Healthy,
                "installed",
                "installed",
                current,
                other,
                orphaned,
                warnings);
        }

        var hasKnownIssue = current > 1 || other > 0 || orphaned > 0 ||
                            (total > 0 && current == 0);
        var state = hasKnownIssue
            ? ApplicationSupportStates.ActionRequired
            : ApplicationSupportStates.Unavailable;
        var detail = warnings > 0 && !hasKnownIssue
            ? "scanPartial"
            : current > 1 || other > 0
                ? "duplicateInstallations"
                : orphaned > 0
                    ? "staleRegistrations"
                    : "currentInstallationMissing";
        return new(
            state,
            detail,
            "ambiguous",
            current,
            other,
            orphaned,
            Math.Max(0, warnings));
    }

    internal static bool TryParseCommand(string? command, out string executable)
    {
        executable = "";
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
        }
        else
        {
            var executableEnd = value.IndexOf(".exe", StringComparison.OrdinalIgnoreCase);
            if (executableEnd < 0)
            {
                return false;
            }
            executable = value[..(executableEnd + 4)].Trim();
        }

        executable = NormalizePath(executable);
        return executable.Length > 0 &&
               Path.IsPathFullyQualified(executable) &&
               ".exe".Equals(Path.GetExtension(executable), StringComparison.OrdinalIgnoreCase);
    }

    internal static bool IsInstallerRegistryKey(string? keyName) =>
        !string.IsNullOrWhiteSpace(keyName) &&
        (keyName.Trim().Equals($"{{{InstallerAppId}}}_is1", StringComparison.OrdinalIgnoreCase) ||
         keyName.Trim().Equals($"{InstallerAppId}_is1", StringComparison.OrdinalIgnoreCase));

    private static bool IsTrustedUninstallerPath(string path, string installDirectory)
    {
        if (path.Length == 0 || !Path.IsPathFullyQualified(path))
        {
            return false;
        }

        var fileName = Path.GetFileName(path);
        return (installDirectory.Length == 0 ||
                PathsEqual(Path.GetDirectoryName(path), installDirectory)) &&
               fileName.StartsWith("unins", StringComparison.OrdinalIgnoreCase) &&
               ".exe".Equals(Path.GetExtension(fileName), StringComparison.OrdinalIgnoreCase);
    }

    private static string ReadString(RegistryKey key, string name) =>
        key.GetValue(name) is string value ? value.Trim() : "";

    private static bool PathsEqual(string? first, string? second) =>
        !string.IsNullOrWhiteSpace(first) &&
        !string.IsNullOrWhiteSpace(second) &&
        NormalizePath(first).Equals(NormalizePath(second), StringComparison.OrdinalIgnoreCase);

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
            return "";
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
            // Probe cleanup is best effort; a later inspection ignores this file.
        }
    }

    private static void OpenDirectory(string directory, Func<ProcessStartInfo, Process?> shellStart)
    {
        // ShellExecute can reuse Explorer and return no new Process. A null
        // process is not an error; an actual launch failure throws instead.
        using var process = shellStart(new ProcessStartInfo
        {
            FileName = directory,
            UseShellExecute = true
        });
    }
}

internal sealed record InstallationEntry(
    bool ValidUninstaller,
    bool IsCurrent);
