using StarBridge.HostRuntime.Storage;

internal static class StorageMigrationDestinationTests
{
    internal static Task VerifiedCopyPreservesSource()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-copy-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var source = Path.Combine(root, "source");
            var target = Path.Combine(root, "target");
            Directory.CreateDirectory(source);
            File.WriteAllText(Path.Combine(source, "中文.json"), "verified content");
            Directory.CreateDirectory(Path.Combine(source, "Updates"));
            File.WriteAllText(Path.Combine(source, "Updates", "keep.txt"), "bootstrap");
            var result = VerifiedStorageCopy.Copy(source, target, path => !path.StartsWith("Updates"));
            if (result.FileCount != 1 || result.ByteCount <= 0 ||
                File.ReadAllText(Path.Combine(target, "中文.json")) != "verified content" ||
                !File.Exists(Path.Combine(source, "中文.json")) || Directory.Exists(Path.Combine(target, "Updates")))
                throw new Exception("Verified copy lost data or copied excluded bootstrap files.");
            try { VerifiedStorageCopy.Copy(source, target); throw new Exception("Nonempty destination accepted."); }
            catch (InvalidOperationException) { }
            var cancelled = Path.Combine(root, "cancelled");
            try { VerifiedStorageCopy.Copy(source, cancelled, cancellation: new CancellationToken(true));
                throw new Exception("Cancellation ignored."); }
            catch (OperationCanceledException) { }
            if (Directory.Exists(cancelled)) throw new Exception("Cancelled copy created its target.");
            var lockedTarget = Path.Combine(root, "locked-target");
            using (var writer = new FileStream(Path.Combine(source, "中文.json"), FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            {
                try { VerifiedStorageCopy.Copy(source, lockedTarget); throw new Exception("Live writer was not rejected."); }
                catch (IOException) { }
            }
            if (Directory.Exists(lockedTarget) || File.ReadAllText(Path.Combine(source, "中文.json")) != "verified content")
                throw new Exception("Failed copy published a target or changed the source.");
        }
        finally { Directory.Delete(root, true); } // Only the unique fixture.
        return Task.CompletedTask;
    }

    internal static Task ValidateWithoutMutation()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-migration-preflight-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var source = Path.Combine(root, "source");
            Directory.CreateDirectory(source);
            var destination = Path.Combine(root, "中文目标");
            if (StorageMigrationDestination.Validate(source, destination) != destination || Directory.Exists(destination))
                throw new Exception("Preflight must preserve Unicode and never create the target.");
            if (StorageMigrationDestination.Validate(source, source) != source)
                throw new Exception("Same path remains a no-op.");
            Reject(source, Path.GetPathRoot(root)!);
            Reject(source, root);
            Reject(source, Path.Combine(source, "nested"));
            Reject(source, "relative-target");
            Reject(source, Path.Combine(root, "damaged-\uFFFD"));
            Directory.CreateDirectory(destination);
            var sentinel = Path.Combine(destination, "keep.txt");
            File.WriteAllText(sentinel, "preserve");
            Reject(source, destination);
            Reject(source, sentinel);
            if (File.ReadAllText(sentinel) != "preserve") throw new Exception("Preflight modified existing data.");
        }
        finally { Directory.Delete(root, true); } // Only this unique temporary fixture.
        return Task.CompletedTask;
    }

    private static void Reject(string source, string destination)
    {
        try { StorageMigrationDestination.Validate(source, destination); }
        catch (Exception e) when (e is ArgumentException or InvalidOperationException or IOException) { return; }
        throw new Exception("Unsafe migration destination was accepted.");
    }
}
