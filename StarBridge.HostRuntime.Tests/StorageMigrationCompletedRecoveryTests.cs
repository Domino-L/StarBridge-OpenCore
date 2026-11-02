using System.Text.Json;
using StarBridge.HostRuntime.Storage;

internal static class StorageMigrationCompletedRecoveryTests
{
    internal static Task Verify()
    {
        foreach (var mode in new[] { "completed", "writer", "wrong-locator", "missing-destination", "copied", "copying", "pointer-switched", "cancelled", "malformed" })
        {
            var prefix = Path.Combine(Path.GetTempPath(), "starbridge-completed-recovery-");
            var root = prefix + Guid.NewGuid().ToString("N");
            var bootstrap = Path.Combine(root, "bootstrap");
            var source = Path.Combine(root, "source");
            var destination = Path.Combine(root, "destination");
            Directory.CreateDirectory(bootstrap);
            Directory.CreateDirectory(source);
            Directory.CreateDirectory(destination);
            try
            {
                var sourceFile = Path.Combine(source, "data.json");
                var destinationFile = Path.Combine(destination, "data.json");
                File.WriteAllText(sourceFile, "retained source");
                File.WriteAllText(destinationFile, mode is "copied" or "copying" or "pointer-switched" ? "retained source" : "changed live destination");
                var locator = Path.Combine(bootstrap, StorageRootLocator.FileName);
                var journal = Path.Combine(bootstrap, StorageMigrationTransaction.JournalName);
                var phase = mode is "copied" or "copying" ? mode : mode == "pointer-switched" ? "copied" : mode == "malformed" ? "unknown" : "committed";
                File.WriteAllText(locator, mode is "wrong-locator" or "copied" or "copying" ? source : destination);
                File.WriteAllText(journal, JsonSerializer.Serialize(new { schemaVersion = 1, source, destination, phase }));
                File.SetLastWriteTimeUtc(journal, new DateTime(2001, 1, 1, 0, 0, 0, DateTimeKind.Utc));
                var journalTime = File.GetLastWriteTimeUtc(journal);
                var protectedFiles = new[] { locator, journal, sourceFile, destinationFile };
                var before = protectedFiles.Select(File.ReadAllBytes).ToArray();
                if (mode == "missing-destination") { File.Delete(destinationFile); Directory.Delete(destination); }
                using var writer = mode == "completed" ? null : StorageActivityLease.AcquireWriter(bootstrap);
                if (mode is "completed" or "writer")
                {
                    for (var read = 0; read < 2; read++)
                        if (StorageMigrationRecovery.RecoverPending(bootstrap) != "committed")
                            throw new Exception("Completed journal did not remain read-only during restart.");
                }
                else if (mode == "cancelled")
                {
                    try { StorageMigrationRecovery.RecoverPending(bootstrap, new CancellationToken(true)); throw new Exception("Completed recovery ignored cancellation."); }
                    catch (OperationCanceledException) { }
                }
                else if (mode == "malformed")
                {
                    try { StorageMigrationRecovery.RecoverPending(bootstrap); throw new Exception("Malformed completed journal accepted."); }
                    catch (InvalidDataException) { }
                }
                else
                {
                    try { StorageMigrationRecovery.RecoverPending(bootstrap); throw new Exception("Pending or inconsistent recovery bypassed its guard."); }
                    catch (IOException error)
                    {
                        if (mode is "copied" or "copying" or "pointer-switched" && (error.HResult & 0xffff) is not (32 or 33))
                            throw new Exception("Pending recovery did not retain its exclusive activity lease.", error);
                    }
                }
                for (var index = 0; index < protectedFiles.Length; index++)
                {
                    if (mode == "missing-destination" && index == 3) continue;
                    if (!before[index].AsSpan().SequenceEqual(File.ReadAllBytes(protectedFiles[index])))
                        throw new Exception("Recovery mutated a retained source, live destination, locator or journal.");
                }
                if (File.GetLastWriteTimeUtc(journal) != journalTime)
                    throw new Exception("Completed journal was rewritten on a read-only restart.");
                if (mode == "missing-destination" && Directory.Exists(destination))
                    throw new Exception("Recovery recreated a missing completed destination.");
            }
            finally
            {
                // This is the fresh synthetic fixture, never a product data root.
                var absolute = Path.GetFullPath(root);
                if (!absolute.StartsWith(Path.GetFullPath(prefix), StringComparison.OrdinalIgnoreCase) ||
                    Path.GetFileName(absolute).Length != "starbridge-completed-recovery-".Length + 32)
                    throw new InvalidOperationException("Unexpected cleanup target.");
                Directory.Delete(absolute, recursive: true);
            }
        }
        return Task.CompletedTask;
    }
}