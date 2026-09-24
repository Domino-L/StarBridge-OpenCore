using StarBridge.HostRuntime.Support;

internal static class FlutterInstallationMaintenanceTests
{
    internal static void CleanIsolatedStaleInstallation(string directory)
    {
        var root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(directory));
        var fixture = Path.GetFullPath(Path.Combine("artifacts", "flutter-install-validation-20260915-01", "app"));
        Require(string.Equals(root, fixture, StringComparison.OrdinalIgnoreCase), "dedicated isolated target only");
        Require(!Directory.Exists(root), "fixture directory must already be absent");
        var maintenance = new FlutterInstallationMaintenance(Path.Combine(root, FlutterInstallationIdentity.Executable));
        var plan = maintenance.Prepare();
        Require(string.Equals(plan.Directory, root, StringComparison.OrdinalIgnoreCase), "exact isolated registration");
        Require(plan.CanClean && !plan.CanUninstall && plan.Mode == "orphaned", "isolated stale record only");
        maintenance.Execute(plan.Ticket, "clean");
        Require(maintenance.Prepare().Mode == "portable", "registration removed");
    }

    // Explicit opt-in, read-only real Windows registration check. Never launches
    // an uninstaller, removes registration, or starts the fixture application.
    internal static void InspectIsolatedInstallation(string directory, string expectedMode)
    {
        if (expectedMode is not ("installed" or "portable")) throw new ArgumentException("Unexpected mode.");
        var root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(directory));
        var executable = Path.Combine(root, FlutterInstallationIdentity.Executable);
        var plan = new FlutterInstallationMaintenance(executable).Prepare();
        Require(plan.Mode == expectedMode, "actual maintenance mode: " + plan.Mode);
        Require(plan.CanUninstall == (expectedMode == "installed"), "actual uninstall eligibility");
        Require(!plan.CanClean, "not an orphan");
        if (expectedMode == "installed") Require(string.Equals(plan.Directory, root, StringComparison.OrdinalIgnoreCase), "exact isolated installation target");
        var summary = new WindowsApplicationSupportInspector(Path.Combine(root, "probe-not-created"), executable).Inspect();
        Require(summary.Installation.CurrentInstallations == (expectedMode == "installed" ? 1 : 0), "installation counted once");
        Require(summary.Installation.OtherInstallations == 0, "WPF is not counted");
    }

    internal static Task OwnershipConfirmationAndReplayGuards()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-flutter-maintenance-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var install = Path.Combine(root, "install");
            Directory.CreateDirectory(install);
            foreach (var name in new[] { "starbridge_flutter.exe", "unins000.exe", "unins000.dat" })
                File.WriteAllText(Path.Combine(install, name), "isolated fixture, never executed");
            FlutterInstallationRecord? record = new(install, "\"" + Path.Combine(install, "unins000.exe") + "\"", FlutterInstallationIdentity.Product);
            var launched = 0;
            var removed = 0;
            var now = DateTimeOffset.UtcNow;
            var maintenance = new FlutterInstallationMaintenance(Path.Combine(install, "starbridge_flutter.exe"), () => record,
                () => removed++, path => { Require(path == Path.Combine(install, "unins000.exe"), "fixed uninstaller"); launched++; }, () => now);
            var plan = maintenance.Prepare();
            Require(plan.CanUninstall && !plan.CanClean && plan.Mode == "installed", "installed");
            maintenance.Execute(plan.Ticket, "uninstall");
            Reject(() => maintenance.Execute(plan.Ticket, "uninstall"));
            Require(launched == 1 && removed == 0, "one-shot");
            plan = maintenance.Prepare();
            record = record with { Product = "StarBridge.WPF" };
            Reject(() => maintenance.Execute(plan.Ticket, "uninstall"));
            Require(!maintenance.Prepare().CanUninstall && !maintenance.Prepare().CanClean, "WPF rejected");
            record = record with { Product = FlutterInstallationIdentity.Product, UninstallCommand = "\"" + Path.Combine(install, "unins000.exe") + "\" /SILENT" };
            Require(!maintenance.Prepare().CanUninstall, "injected arguments rejected");
            record = record with { UninstallCommand = "\"" + Path.Combine(install, "unins000.exe") + "\"" };
            plan = maintenance.Prepare();
            now = now.AddMinutes(3);
            Reject(() => maintenance.Execute(plan.Ticket, "uninstall"));
            File.Delete(Path.Combine(install, "unins000.dat"));
            plan = maintenance.Prepare();
            Require(!plan.CanUninstall && !plan.CanClean && plan.Mode == "damaged", "damaged is not orphan");
            Directory.Delete(install, true); // Isolated test fixture only.
            plan = maintenance.Prepare();
            Require(plan.CanClean && !plan.CanUninstall, "missing directory is orphan");
            Directory.CreateDirectory(install);
            Reject(() => maintenance.Execute(plan.Ticket, "clean"));
            Directory.Delete(install);
            plan = maintenance.Prepare();
            maintenance.Execute(plan.Ticket, "clean");
            Require(removed == 1 && launched == 1, "only stale registration cleaned");
            record = null;
            plan = maintenance.Prepare();
            Require(plan.Mode == "portable" && !plan.CanClean && !plan.CanUninstall, "portable");
            Require(!WindowsApplicationSupportInspector.IsInstallerRegistryKey("{8F0E3D89-0DC1-4C51-8B6C-1BC7BA90378F}_is1"), "WPF scan excluded");
            Require(WindowsApplicationSupportInspector.IsInstallerRegistryKey(FlutterInstallationIdentity.KeyName), "Flutter scan included");
        }
        finally { Directory.Delete(root, true); }
        return Task.CompletedTask;
    }

    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private static void Reject(Action action)
    {
        try { action(); }
        catch (InvalidOperationException) { return; }
        throw new InvalidOperationException("Unsafe operation accepted.");
    }
}
