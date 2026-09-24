using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Storage;

internal static class StorageMigrationTransactionTests
{
    internal static Task Verify()
    {
        foreach (var mode in new[] { "normal", "bootstrap", "copied", "copying", "changed-copy", "changed-source", "pointer-switched", "unrelated-pointer" })
        {
            var fixture = Path.Combine(Path.GetTempPath(), "starbridge-migration-transaction-" + Guid.NewGuid().ToString("N"));
            var bootstrap = Path.Combine(fixture, "bootstrap");
            var source = mode == "bootstrap" ? bootstrap : Path.Combine(fixture, "source");
            var destination = Path.Combine(fixture, "中文目标");
            Directory.CreateDirectory(bootstrap); Directory.CreateDirectory(source);
            try
            {
                File.WriteAllText(Path.Combine(source, "data.json"), "original");
                if (source == bootstrap)
                {
                    File.WriteAllText(Path.Combine(source, StorageMigrationPlanFile.Name), "do not migrate");
                    File.WriteAllText(Path.Combine(source, StorageMigrationPlanFile.ResultName), "do not migrate");
                }
                if (source != bootstrap) File.WriteAllText(Path.Combine(bootstrap, StorageRootLocator.FileName), source, new UTF8Encoding(true));
                if (StorageRootLocator.Read(bootstrap) != source) throw new Exception("Locator BOM compatibility failed.");
                var transaction = new StorageMigrationTransaction(bootstrap);
                if (mode is "normal" or "bootstrap")
                {
                    transaction.Apply(destination);
                    if (File.Exists(Path.Combine(destination, StorageMigrationTransaction.JournalName)) ||
                        File.Exists(Path.Combine(destination, StorageActivityLease.FileName)) ||
                        File.Exists(Path.Combine(destination, StorageMigrationTransaction.LeaseName)) ||
                        File.Exists(Path.Combine(destination, StorageMigrationPlanFile.Name)) ||
                        File.Exists(Path.Combine(destination, StorageMigrationPlanFile.ResultName))) throw new Exception("Control files copied.");
                }
                else
                {
                    VerifiedStorageCopy.Copy(source, destination);
                    File.WriteAllText(Path.Combine(bootstrap, StorageMigrationTransaction.JournalName), JsonSerializer.Serialize(new {
                        schemaVersion = 1, source, destination, phase = mode == "copying" ? "copying" : "copied" }));
                    if (mode == "changed-copy") File.WriteAllText(Path.Combine(destination, "data.json"), "changed");
                    if (mode == "changed-source") File.WriteAllText(Path.Combine(source, "data.json"), "changed");
                    if (mode == "pointer-switched") File.WriteAllText(Path.Combine(bootstrap, StorageRootLocator.FileName), destination);
                    if (mode == "unrelated-pointer") File.WriteAllText(Path.Combine(bootstrap, StorageRootLocator.FileName), fixture);
                    if (mode is "changed-copy" or "changed-source" or "unrelated-pointer")
                    {
                        try { transaction.Recover(); throw new Exception("Changed migration accepted."); }
                        catch (IOException) { }
                        if (StorageRootLocator.Read(bootstrap) != (mode == "unrelated-pointer" ? fixture : source)) throw new Exception("Failure switched locator.");
                        continue;
                    }
                    if (transaction.Recover() != "committed") throw new Exception("Interrupted migration did not recover.");
                }
                if (StorageRootLocator.Read(bootstrap) != destination ||
                    File.ReadAllText(Path.Combine(source, "data.json")) != "original" ||
                    File.ReadAllText(Path.Combine(destination, "data.json")) != "original") throw new Exception("Migration lost source or destination.");
                File.WriteAllText(Path.Combine(destination, "data.json"), "new live data");
                if (transaction.Recover() != "committed" || File.ReadAllText(Path.Combine(destination, "data.json")) != "new live data")
                    throw new Exception("Repeated recovery overwrote active data.");
                var next = Path.Combine(fixture, "next");
                transaction.Apply(next);
                if (StorageRootLocator.Read(bootstrap) != next || !File.Exists(Path.Combine(destination, "data.json")))
                    throw new Exception("Second migration lost retained source.");
            }
            finally { Directory.Delete(fixture, recursive: true); } // Only this newly-created test fixture.
        }
        var controls = Path.Combine(Path.GetTempPath(), "starbridge-migration-control-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(controls);
        var culture = System.Globalization.CultureInfo.CurrentCulture;
        try
        {
            var bootstrap = Path.Combine(controls, "bootstrap");
            Directory.CreateDirectory(bootstrap);
            var source = Path.Combine(controls, "source");
            Directory.CreateDirectory(source);
            var file = Path.Combine(source, "data.json");
            File.WriteAllText(file, "keep");
            var locator = Path.Combine(bootstrap, StorageRootLocator.FileName);
            File.WriteAllText(locator, source);
            var transaction = new StorageMigrationTransaction(bootstrap);
            var target = Path.Combine(controls, "target");
            try { transaction.Apply(target, expectedSource: bootstrap); throw new Exception("Changed confirmed source accepted."); }
            catch (IOException) { }
            if (Directory.Exists(target) || File.Exists(Path.Combine(bootstrap, StorageMigrationTransaction.JournalName)))
                throw new Exception("Stale confirmation mutated migration state.");
            using (StorageActivityLease.AcquireWriter(bootstrap))
            using (StorageActivityLease.AcquireWriter(bootstrap))
            {
                try { transaction.Apply(target); throw new Exception("Active clients allowed migration."); }
                catch (IOException) { }
                if (Directory.Exists(target) || File.Exists(Path.Combine(bootstrap, StorageMigrationTransaction.JournalName)))
                    throw new Exception("Blocked migration changed data.");
            }
            using (StorageActivityLease.AcquireMigration(bootstrap))
            {
                try { using var writer = StorageActivityLease.AcquireWriter(bootstrap); throw new Exception("Writer entered during migration."); }
                catch (IOException) { }
                try { using var other = StorageActivityLease.AcquireMigration(bootstrap); throw new Exception("Concurrent migration entered."); }
                catch (IOException) { }
            }
            using (StorageActivityLease.AcquireWriter(bootstrap)) { } // Released exclusive handle permits restart.
            using (var lease = new FileStream(Path.Combine(bootstrap, StorageMigrationTransaction.LeaseName), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
            {
                try { transaction.Apply(target); throw new Exception("Concurrent migration accepted."); }
                catch (IOException) { }
            }
            try { transaction.Apply(target, new CancellationToken(true)); throw new Exception("Cancellation ignored."); }
            catch (OperationCanceledException) { }
            using (var writer = new FileStream(file, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            {
                try { transaction.Apply(target); throw new Exception("Live data writer accepted."); }
                catch (IOException) { }
            }
            if (StorageRootLocator.Read(bootstrap) != source || File.ReadAllText(file) != "keep" || Directory.Exists(target) ||
                transaction.Recover() != "source-retained") throw new Exception("Failed migration switched or removed data.");
            System.Globalization.CultureInfo.CurrentCulture = System.Globalization.CultureInfo.GetCultureInfo("en-US");
            Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
            var legacy = Path.Combine(controls, "caf\u00e9");
            File.WriteAllBytes(locator, Encoding.GetEncoding(1252).GetBytes(legacy));
            if (StorageRootLocator.Read(bootstrap) != legacy) throw new Exception("Legacy ANSI path encoding changed.");
            foreach (var invalid in new[] { "", "relative", "broken-\uFFFD" })
            {
                File.WriteAllText(locator, invalid);
                try { StorageRootLocator.Read(bootstrap); throw new Exception("Malformed locator silently accepted."); }
                catch (InvalidDataException) { }
            }
        }
        finally { System.Globalization.CultureInfo.CurrentCulture = culture; Directory.Delete(controls, recursive: true); }
        return Task.CompletedTask;
    }
}
