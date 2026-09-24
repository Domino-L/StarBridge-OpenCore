using StarBridge.Core.Hangar;

namespace StarBridge.HostRuntime.Hangar;

internal sealed record LegacyHangarFileResult(string State, LegacyHangarRead? Snapshot = null);

// Explicit authorized path only. The coordinator must verify ownership and hold
// the application storage lease. A filename is not proof of account ownership.
internal static class LegacyHangarMigrationFile
{
    internal static LegacyHangarFileResult Inspect(string path, MigrationOwner owner)
    {
        try
        {
            if (!Path.IsPathFullyQualified(path) || path.StartsWith(@"\\", StringComparison.Ordinal) ||
                path.IndexOf(':', 2) >= 0) return new("unavailable");
            path = Path.GetFullPath(path);
            if (!string.Equals(Path.GetExtension(path), ".database", StringComparison.OrdinalIgnoreCase))
                return new("unavailable");
            for (var part = new FileInfo(path).Directory; part is not null; part = part.Parent)
                if ((File.GetAttributes(part.FullName) & FileAttributes.ReparsePoint) != 0)
                    return new("unavailable");
            if ((File.GetAttributes(path) & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != 0)
                return new("unavailable");
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (stream.Length > 4 * 1024 * 1024) return new("needs-review");
            var bytes = new byte[(int)stream.Length];
            stream.ReadExactly(bytes);
            var snapshot = LegacyHangarMigrationReader.Read(bytes, owner);
            return new(snapshot.Source.State == MigrationSourceState.Complete ? "read" : "needs-review", snapshot);
        }
        catch (FileNotFoundException) { return new("not-present"); }
        catch (DirectoryNotFoundException) { return new("not-present"); }
        catch (InvalidDataException) { return new("needs-review"); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException or
            NotSupportedException or System.Security.SecurityException)
        {
            return new("unavailable");
        }
    }
}
