using Microsoft.Win32;
using StarBridge.HostRuntime.Storage;

namespace StarBridge.HostRuntime.Updates;

internal sealed record WpfMigrationRegistration(string Scope, string Directory, string UninstallCommand);
internal sealed record WpfMigrationPreflightResult(string InstallationState, string DataState,
    bool CanRemoveWpf = false);

/// <summary>Read-only inventory, not cleanup authorization. Never reads account data,
/// executes registry commands, promotes files, or treats an unknown installation as absent.</summary>
internal static class WpfMigrationPreflight
{
    private const string Key = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\{8F0E3D89-0DC1-4C51-8B6C-1BC7BA90378F}_is1";

    internal static WpfMigrationPreflightResult Inspect() => Inspect(ReadRegistrations, HostDataRoot.BootstrapDirectory);

    internal static WpfMigrationPreflightResult Inspect(Func<IReadOnlyList<WpfMigrationRegistration>> read,
        string bootstrap)
    {
        try
        {
            var records = read();
            if (records.Count == 0) return new("not-registered", "not-checked");
            if (records.Count != 1) return new("ambiguous", "not-checked");
            var record = records[0];
            if (!IsPlainDirectory(record.Directory)) return new("unverified", "not-checked");
            var uninstaller = Path.Combine(record.Directory, "unins000.exe");
            if (!string.Equals(record.UninstallCommand, "\"" + uninstaller + "\"", StringComparison.OrdinalIgnoreCase))
                return new("unverified", "not-checked");
            foreach (var name in new[] { "Star Bridge.exe", "unins000.exe", "unins000.dat" })
            {
                var path = Path.Combine(record.Directory, name);
                if (!File.Exists(path) || (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                    return new("damaged", "not-checked");
            }
            // Signature and running-process checks are still required before any action.
            var state = record.Scope == "current-user" ? "registered-current-user" : "registered-other-scope";
            if (!IsPlainDirectory(bootstrap)) return new(state, "unverified");
            var locator = Path.Combine(bootstrap, StorageRootLocator.FileName);
            // Do not let File.Exists's access-error fallback silently select the default root.
            try { _ = File.GetAttributes(locator); }
            catch (FileNotFoundException) { }
            var data = StorageRootLocator.Read(bootstrap);
            if (!IsPlainDirectory(data)) return new(state, "unverified");
            if (Contains(record.Directory, data) || Contains(data, record.Directory))
                return new(state, "overlaps-installation");
            return new(state, "separate-root-located");
        }
        catch (Exception e) when (e is IOException or InvalidDataException or UnauthorizedAccessException or
            System.Security.SecurityException or ArgumentException or NotSupportedException)
        {
            return new("unverified", "unverified");
        }
    }

    private static bool Contains(string parent, string child) =>
        string.Equals(parent, child, StringComparison.OrdinalIgnoreCase) ||
        child.StartsWith(Path.TrimEndingDirectorySeparator(parent) + Path.DirectorySeparatorChar,
            StringComparison.OrdinalIgnoreCase);

    private static bool IsPlainDirectory(string path)
    {
        if (!Path.IsPathFullyQualified(path) || path.StartsWith(@"\\", StringComparison.Ordinal) ||
            !string.Equals(Path.TrimEndingDirectorySeparator(Path.GetFullPath(path)), path, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(Path.GetPathRoot(path), path, StringComparison.OrdinalIgnoreCase)) return false;
        for (var part = new DirectoryInfo(path); part is not null; part = part.Parent)
            if ((File.GetAttributes(part.FullName) & FileAttributes.ReparsePoint) != 0) return false;
        return Directory.Exists(path);
    }

    private static IReadOnlyList<WpfMigrationRegistration> ReadRegistrations()
    {
        var result = new List<WpfMigrationRegistration>();
        foreach (var hive in new[] { RegistryHive.CurrentUser, RegistryHive.LocalMachine })
        foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
        {
            using var root = RegistryKey.OpenBaseKey(hive, view);
            using var key = root.OpenSubKey(Key, writable: false);
            if (key is null) continue;
            var record = new WpfMigrationRegistration(hive == RegistryHive.CurrentUser ? "current-user" : "all-users",
                Path.TrimEndingDirectorySeparator(key.GetValue("InstallLocation") as string ?? ""),
                key.GetValue("UninstallString") as string ?? "");
            // Windows may expose an identical registration through both registry views.
            if (!result.Contains(record)) result.Add(record);
        }
        return result;
    }
}
