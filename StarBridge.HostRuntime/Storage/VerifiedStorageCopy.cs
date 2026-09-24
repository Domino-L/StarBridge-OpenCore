using System.Security.Cryptography;

namespace StarBridge.HostRuntime.Storage;

public sealed record VerifiedStorageCopyResult(string DestinationRoot, int FileCount, long ByteCount);

/// <summary>Copies a quiescent data root without changing its locator or deleting the source.
/// Callers must stop all writers before invoking this operation.</summary>
public static class VerifiedStorageCopy
{
    public static VerifiedStorageCopyResult Copy(string sourceRoot, string destinationRoot,
        Func<string, bool>? includeRelativePath = null, CancellationToken cancellation = default)
    {
        cancellation.ThrowIfCancellationRequested();
        var source = Path.TrimEndingDirectorySeparator(Path.GetFullPath(sourceRoot));
        var destination = StorageMigrationDestination.Validate(source, destinationRoot);
        if (string.Equals(source, destination, StringComparison.OrdinalIgnoreCase))
            return new(destination, 0, 0);
        RequireDirectory(source);
        var files = Enumerate(source, source, includeRelativePath, cancellation).Order(StringComparer.OrdinalIgnoreCase).ToArray();
        var staging = destination + ".starbridge-migration-" + Guid.NewGuid().ToString("N");
        Directory.CreateDirectory(staging);
        long bytes = 0;
        // A failed staging directory is intentionally retained for inspection;
        // neither the source nor a user-selected directory is recursively deleted.
        foreach (var path in files)
        {
            cancellation.ThrowIfCancellationRequested();
            var target = Path.Combine(staging, Path.GetRelativePath(source, path));
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Source contains a reparse point.");
            using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            using (var output = new FileStream(target, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                input.CopyTo(output);
                output.Flush(flushToDisk: true);
            }
            input.Position = 0;
            using var copied = File.OpenRead(target);
            if (!SHA256.HashData(input).AsSpan().SequenceEqual(SHA256.HashData(copied)))
                throw new IOException("Migration verification failed.");
            bytes = checked(bytes + input.Length);
        }
        cancellation.ThrowIfCancellationRequested();
        // Revalidate immediately before publishing. Never merge into a populated target.
        StorageMigrationDestination.Validate(source, destination);
        if (Directory.Exists(destination)) Directory.Delete(destination, recursive: false);
        Directory.Move(staging, destination);
        return new(destination, files.Length, bytes);
    }

    private static IEnumerable<string> Enumerate(string root, string directory, Func<string, bool>? include,
        CancellationToken cancellation)
    {
        RequireDirectory(directory);
        foreach (var entry in Directory.EnumerateFileSystemEntries(directory))
        {
            cancellation.ThrowIfCancellationRequested();
            if (include is not null && !include(Path.GetRelativePath(root, entry))) continue;
            var attributes = File.GetAttributes(entry);
            if ((attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Source contains a reparse point.");
            if ((attributes & FileAttributes.Directory) != 0)
            {
                foreach (var file in Enumerate(root, entry, include, cancellation)) yield return file;
            }
            else yield return entry;
        }
    }

    /// <summary>Recheck a published copy before recovering an interrupted locator switch.</summary>
    internal static void Verify(string source, string destination, Func<string, bool>? include, CancellationToken cancellation)
    {
        var original = Enumerate(source, source, include, cancellation)
            .Select(path => Path.GetRelativePath(source, path)).Order(StringComparer.OrdinalIgnoreCase).ToArray();
        var copied = Enumerate(destination, destination, null, cancellation)
            .Select(path => Path.GetRelativePath(destination, path)).Order(StringComparer.OrdinalIgnoreCase).ToArray();
        if (!original.SequenceEqual(copied, StringComparer.OrdinalIgnoreCase)) throw new IOException("Migration file set changed.");
        foreach (var relative in original)
        {
            cancellation.ThrowIfCancellationRequested();
            using var input = new FileStream(Path.Combine(source, relative), FileMode.Open, FileAccess.Read, FileShare.Read);
            using var output = new FileStream(Path.Combine(destination, relative), FileMode.Open, FileAccess.Read, FileShare.Read);
            if (input.Length != output.Length || !SHA256.HashData(input).AsSpan().SequenceEqual(SHA256.HashData(output)))
                throw new IOException("Migration contents changed.");
        }
    }

    private static void RequireDirectory(string path)
    {
        if (!Directory.Exists(path) || (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
            throw new IOException("Data directory is unavailable or redirected.");
        for (var parent = Directory.GetParent(path); parent is not null; parent = parent.Parent)
            if ((parent.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Redirected data directory ancestor.");
    }
}
