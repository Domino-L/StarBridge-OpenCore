namespace StarBridge.HostRuntime.Support;

using Microsoft.Win32;
using System.Diagnostics;

internal sealed record FlutterInstallationRecord(string Directory, string UninstallCommand, string Product);
internal sealed record FlutterInstallationPlan(string Ticket, string Mode, string Directory, bool CanUninstall, bool CanClean);

/// <summary>Only the per-user Flutter installer record is mutable. No caller-supplied paths,
/// no WPF keys, no recursive deletion, no user-data cleanup and no automatic replay.</summary>
internal sealed class FlutterInstallationMaintenance
{
    private readonly Func<FlutterInstallationRecord?> _read;
    private readonly Action _removeRegistration;
    private readonly Action<string> _launch;
    private readonly Func<DateTimeOffset> _now;
    private readonly string _currentDirectory;
    private (FlutterInstallationPlan Plan, FlutterInstallationRecord? Record, DateTimeOffset Until)? _pending;

    internal FlutterInstallationMaintenance(string? currentExecutable)
        : this(currentExecutable, ReadRegistration, RemoveRegistration, path =>
        {
            _ = Process.Start(new ProcessStartInfo(path) { UseShellExecute = true })
                ?? throw new InvalidOperationException("Uninstaller did not start.");
        }) { }

    internal FlutterInstallationMaintenance(string? currentExecutable,
        Func<FlutterInstallationRecord?> read, Action removeRegistration, Action<string> launch,
        Func<DateTimeOffset>? now = null)
    {
        _currentDirectory = Path.GetDirectoryName(currentExecutable ?? "") ?? "";
        _read = read;
        _removeRegistration = removeRegistration;
        _launch = launch;
        _now = now ?? (() => DateTimeOffset.UtcNow);
    }

    internal FlutterInstallationPlan Prepare()
    {
        _pending = null;
        var record = _read();
        var state = Classify(record);
        var plan = new FlutterInstallationPlan(Guid.NewGuid().ToString("N"), state.Mode,
            record?.Directory ?? "", state.Uninstall, state.Clean);
        _pending = (plan, record, _now().AddMinutes(2));
        return plan;
    }

    internal void Execute(string ticket, string action)
    {
        var pending = _pending;
        _pending = null; // Consume even an uncertain launch; never replay.
        if (pending is null || pending.Value.Plan.Ticket != ticket || _now() > pending.Value.Until)
            throw new InvalidOperationException("Scan expired. Scan again.");
        var record = _read();
        if (record != pending.Value.Record) throw new InvalidOperationException("Installation changed.");
        var state = Classify(record);
        if (action == "clean" && state.Clean && pending.Value.Plan.CanClean)
            _removeRegistration();
        else if (action == "uninstall" && state.Uninstall && pending.Value.Plan.CanUninstall)
            _launch(Path.Combine(record!.Directory, "unins000.exe"));
        else throw new InvalidOperationException("Action is not available.");
    }

    private (string Mode, bool Uninstall, bool Clean) Classify(FlutterInstallationRecord? record)
    {
        if (record is null) return ("portable", false, false);
        if (record.Product != FlutterInstallationIdentity.Product ||
            !Path.IsPathFullyQualified(record.Directory) ||
            record.Directory.StartsWith(@"\\", StringComparison.Ordinal) ||
            Path.GetFullPath(record.Directory) != Path.TrimEndingDirectorySeparator(record.Directory) ||
            string.Equals(Path.GetPathRoot(record.Directory), record.Directory, StringComparison.OrdinalIgnoreCase))
            return ("unverified", false, false);
        // An offline/unavailable drive is not evidence that an install was removed.
        try
        {
            if (!new DriveInfo(Path.GetPathRoot(record.Directory)!).IsReady)
                return ("unverified", false, false);
        }
        catch (IOException) { return ("unverified", false, false); }
        // Reject directory junctions and symbolic links all the way to the volume.
        for (var part = new DirectoryInfo(record.Directory); part != null; part = part.Parent)
        {
            if (part.Exists && (part.Attributes & FileAttributes.ReparsePoint) != 0)
                return ("unverified", false, false);
        }
        var uninstaller = Path.Combine(record.Directory, "unins000.exe");
        if (!string.Equals(record.UninstallCommand, "\"" + uninstaller + "\"", StringComparison.OrdinalIgnoreCase))
            return ("unverified", false, false);
        // Missing directory only: a damaged or merely inaccessible install is not an orphan.
        try { _ = File.GetAttributes(record.Directory); }
        catch (DirectoryNotFoundException) { return ("orphaned", false, true); }
        catch (FileNotFoundException) { return ("orphaned", false, true); }
        catch (UnauthorizedAccessException) { return ("unverified", false, false); }
        foreach (var name in new[] { FlutterInstallationIdentity.Executable, "unins000.exe", "unins000.dat" })
        {
            var path = Path.Combine(record.Directory, name);
            if (!File.Exists(path) || (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                return ("damaged", false, false);
        }
        var current = string.Equals(Path.TrimEndingDirectorySeparator(_currentDirectory), record.Directory, StringComparison.OrdinalIgnoreCase);
        return (current ? "installed" : "other", true, false);
    }

    private static FlutterInstallationRecord? ReadRegistration()
    {
        using var hive = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64);
        using var key = hive.OpenSubKey(FlutterInstallationIdentity.RegistryPath);
        return key == null ? null : new(Path.TrimEndingDirectorySeparator(key.GetValue("InstallLocation") as string ?? ""),
            key.GetValue("UninstallString") as string ?? "", key.GetValue("StarBridgeProduct") as string ?? "");
    }

    private static void RemoveRegistration()
    {
        using var hive = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64);
        // The fixed leaf key only. Never remove the shared Uninstall parent.
        hive.DeleteSubKey(FlutterInstallationIdentity.RegistryPath, throwOnMissingSubKey: true);
    }
}
