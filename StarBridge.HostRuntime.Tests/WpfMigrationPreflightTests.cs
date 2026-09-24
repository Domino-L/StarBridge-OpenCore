using StarBridge.HostRuntime.Updates;

internal static class WpfMigrationPreflightTests
{
    internal static Task Verify()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-migration-preflight-" + Guid.NewGuid().ToString("N"));
        var install = Path.Combine(root, "client");
        var data = Path.Combine(root, "data");
        Directory.CreateDirectory(install);
        Directory.CreateDirectory(data);
        foreach (var name in new[] { "Star Bridge.exe", "unins000.exe", "unins000.dat" })
            File.WriteAllText(Path.Combine(install, name), "fixture-not-executable");
        var record = new WpfMigrationRegistration("current-user", install, "\"" + Path.Combine(install, "unins000.exe") + "\"");
        try
        {
            Check(WpfMigrationPreflight.Inspect(() => [], data), "not-registered", "not-checked");
            Check(WpfMigrationPreflight.Inspect(() => [record, record], data), "ambiguous", "not-checked");
            Check(WpfMigrationPreflight.Inspect(() => [record], data), "registered-current-user", "separate-root-located");
            Check(WpfMigrationPreflight.Inspect(() => [record with { Scope = "all-users" }], data), "registered-other-scope", "separate-root-located");
            Check(WpfMigrationPreflight.Inspect(() => [record with { UninstallCommand = record.UninstallCommand + " /unexpected" }], data), "unverified", "not-checked");
            Check(WpfMigrationPreflight.Inspect(() => [record with { Directory = "relative" }], data), "unverified", "not-checked");
            Check(WpfMigrationPreflight.Inspect(() => throw new UnauthorizedAccessException(), data), "unverified", "unverified");
            var locator = Path.Combine(data, "data-root.path");
            File.WriteAllText(locator, install);
            Check(WpfMigrationPreflight.Inspect(() => [record], data), "registered-current-user", "overlaps-installation");
            if (File.ReadAllText(locator) != install) throw new Exception("Preflight changed locator.");
            File.WriteAllText(locator, "relative");
            Check(WpfMigrationPreflight.Inspect(() => [record], data), "unverified", "unverified");
            File.Delete(Path.Combine(install, "unins000.dat"));
            Check(WpfMigrationPreflight.Inspect(() => [record], data), "damaged", "not-checked");
        }
        finally { Directory.Delete(root, recursive: true); } // Only this test's newly created fixture.
        return Task.CompletedTask;
    }

    private static void Check(WpfMigrationPreflightResult result, string installation, string data)
    {
        if (result.InstallationState != installation || result.DataState != data || result.CanRemoveWpf)
            throw new Exception("Preflight misclassified evidence or granted cleanup authority.");
    }
}
