namespace StarBridge.HostRuntime.Storage;

public static class StorageMigrationRecovery
{
    /// <summary>Run before acquiring the process writer lease. No journal means
    /// no work and does not create the bootstrap directory.</summary>
    public static string RecoverPending(string bootstrap, CancellationToken cancellation = default)
    {
        bootstrap = StorageRootLocator.Normalize(bootstrap);
        if (!File.Exists(Path.Combine(bootstrap, StorageMigrationTransaction.JournalName))) return "none";
        return new StorageMigrationTransaction(bootstrap).Recover(cancellation);
    }
}
