namespace StarBridge.HostRuntime.Settings;

// Per-user, cross-process and cross-session exclusion. Unlike a named mutex this
// handle may be disposed after await on another thread; process exit releases it.
internal static class ApplicationStartupLease
{
    internal static IDisposable Acquire() => AcquireAt(Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "StarBridge", "maintenance", "startup.lock"));

    internal static IDisposable AcquireAt(string path)
    {
        if (!Path.IsPathFullyQualified(path) || path.StartsWith(@"\\", StringComparison.Ordinal) ||
            !string.Equals(path, Path.GetFullPath(path), StringComparison.OrdinalIgnoreCase))
            throw new IOException("Invalid startup lease path.");
        var parent = Path.GetDirectoryName(path)!;
        RequirePlainAncestors(parent);
        Directory.CreateDirectory(parent);
        RequirePlainAncestors(parent);
        try
        {
            if ((File.GetAttributes(path) & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != 0)
                throw new IOException("Invalid startup lease file.");
        }
        catch (FileNotFoundException) { }
        // Do not delete on release: unlinking would let callers lock different files.
        return new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
    }

    private static void RequirePlainAncestors(string path)
    {
        for (var part = new DirectoryInfo(path); part is not null; part = part.Parent)
        {
            try
            {
                if ((File.GetAttributes(part.FullName) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("Linked startup lease directory.");
            }
            catch (DirectoryNotFoundException) { }
            catch (FileNotFoundException) { }
        }
    }
}
