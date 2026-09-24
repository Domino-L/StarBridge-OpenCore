namespace StarBridge.HostRuntime.Storage;

/// <summary>Cross-process exclusion for clients participating in storage handoff.
/// Writers must acquire before resolving the locator and retain until all stores
/// are disposed. Older clients do not participate and require separate shutdown.</summary>
public static class StorageActivityLease
{
    public const string FileName = "data-root-activity.lock";

    public static IDisposable AcquireWriter(string bootstrap) => Open(bootstrap, exclusive: false);

    public static IDisposable AcquireMigration(string bootstrap) => Open(bootstrap, exclusive: true);

    private static FileStream Open(string bootstrap, bool exclusive)
    {
        bootstrap = StorageRootLocator.Normalize(bootstrap);
        for (var directory = new DirectoryInfo(bootstrap); directory is not null; directory = directory.Parent)
        {
            if (directory.Exists && (directory.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Redirected storage activity directory.");
        }
        Directory.CreateDirectory(bootstrap);
        var path = Path.Combine(bootstrap, FileName);
        if (Path.Exists(path) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
            throw new IOException("Redirected storage activity file.");
        // Identical shared handles coexist; the exclusive handle conflicts in
        // both directions. Never unlink this file: its identity is the lock.
        return new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite,
            exclusive ? FileShare.None : FileShare.ReadWrite);
    }
}
