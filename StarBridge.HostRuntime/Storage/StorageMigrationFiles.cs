namespace StarBridge.HostRuntime.Storage;

/// <summary>S2 bootstrap-owned files stay with the locator, not inside migrated data.</summary>
public static class StorageMigrationFiles
{
    public static bool IsBootstrapOwned(string relative)
    {
        var first = relative.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)[0];
        return first.Equals("Updates", StringComparison.OrdinalIgnoreCase) || first.Equals("Installer", StringComparison.OrdinalIgnoreCase) ||
            new[] { StorageRootLocator.FileName, "pending-data-root.path", "failed-data-root.path", "desktop-crash.log",
                "desktop-overlay-diagnostics.log", StorageMigrationTransaction.JournalName, StorageMigrationTransaction.LeaseName,
                StorageActivityLease.FileName, StorageMigrationPlanFile.Name, StorageMigrationPlanFile.ResultName }
                .Contains(relative, StringComparer.OrdinalIgnoreCase) ||
            relative.StartsWith(StorageMigrationTransaction.JournalName + ".", StringComparison.OrdinalIgnoreCase) ||
            relative.StartsWith(StorageRootLocator.FileName + ".", StringComparison.OrdinalIgnoreCase);
    }
}
