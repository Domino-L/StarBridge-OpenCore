using StarBridge.HostRuntime.Updates;

internal static class WpfMigrationConfirmationTests
{
    internal static Task Verify()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-confirmation-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var binding = new WpfMigrationBinding("0.7.0", new string('A', 64), new string('B', 64), new string('C', 64), new string('D', 64));
            var store = new WpfMigrationConfirmationStore(root);
            Reject(() => store.Confirm(binding, false));
            if (Directory.EnumerateFileSystemEntries(root).Any()) throw new Exception("Declining consent wrote files.");
            Reject(() => store.Confirm(binding with { InstallerSha256 = "invalid" }, true));
            var confirmed = store.Confirm(binding, true);
            if (new WpfMigrationConfirmationStore(root).Inspect() != confirmed) throw new Exception("Confirmation did not survive reopening.");
            Reject(() => store.Confirm(binding, true));
            foreach (var changed in new[] {
                binding with { Version = "0.7.1" },
                binding with { InstallerSha256 = new string('E', 64) },
                binding with { OldInstallationFingerprint = new string('E', 64) },
                binding with { DestinationFingerprint = new string('E', 64) },
                binding with { DataLocationFingerprint = new string('E', 64) } })
                Reject(() => store.MarkInstallStarted(confirmed.Id, changed));
            Reject(() => store.MarkInstallStarted(Guid.NewGuid().ToString("N"), binding));
            using (var held = new FileStream(Path.Combine(root, "migration.lock"), FileMode.Open, FileAccess.ReadWrite, FileShare.None))
                Reject(() => store.MarkInstallStarted(confirmed.Id, binding));
            store.MarkInstallStarted(confirmed.Id, binding);
            if (new WpfMigrationConfirmationStore(root).Inspect()?.State != "install-started") throw new Exception("Interrupted start was lost.");
            Reject(() => store.MarkInstallStarted(confirmed.Id, binding));
            var journal = Path.Combine(root, "confirmation.json");
            File.WriteAllText(journal, "{}");
            Reject(() => store.Inspect());
            File.WriteAllText(journal, new string('x', 16385));
            Reject(() => store.Inspect());
        }
        finally { Directory.Delete(root, recursive: true); } // Only the newly created isolated fixture.
        VerifyStartup();
        return Task.CompletedTask;
    }

    private static void VerifyStartup()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-startup-journal-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var clock = new TestClock();
            var binding = new WpfMigrationBinding("0.7.0", new('A', 64), new('B', 64), new('C', 64), new('D', 64));
            var store = new WpfMigrationConfirmationStore(root, clock);
            var confirmation = store.Confirm(binding, true);
            var nonce = new string('E', 64);
            var receipt = new FlutterUpdateStartupReceipt(nonce, binding.Version, 1, 123, 456, true, true);
            Reject(() => store.AwaitStartup(confirmation.Id, binding, nonce, 123));
            Reject(() => store.MatchStartupReceipt(confirmation.Id, binding, receipt));
            store.MarkInstallStarted(confirmation.Id, binding);
            Reject(() => store.AwaitStartup(confirmation.Id, binding, nonce, 123));
            store.ReserveStartup(confirmation.Id, binding);
            Reject(() => new WpfMigrationConfirmationStore(root).ReserveStartup(confirmation.Id, binding));
            Reject(() => store.AwaitStartup(confirmation.Id, binding, "invalid", 123));
            Reject(() => store.AwaitStartup(confirmation.Id, binding, nonce, 0));
            store.AwaitStartup(confirmation.Id, binding, nonce, 123);
            if (store.Inspect()?.State != "awaiting-startup") throw new Exception("Startup wait was not persisted.");
            Reject(() => store.AwaitStartup(confirmation.Id, binding, nonce, 123));
            Reject(() => store.MarkInstallStarted(confirmation.Id, binding));
            Reject(() => new WpfMigrationConfirmationStore(root, clock).MatchStartupReceipt(confirmation.Id, binding, receipt));
            Reject(() => store.MatchStartupReceipt("different-attempt", binding, receipt));
            Reject(() => store.MatchStartupReceipt(confirmation.Id, binding with { DataLocationFingerprint = new('F', 64) }, receipt));
            foreach (var invalid in new[] {
                receipt with { Nonce = new('F', 64) }, receipt with { Version = "0.7.1" },
                receipt with { ClientProcessId = 999 }, receipt with { HostProcessId = 0 },
                receipt with { FirstFrameRendered = false }, receipt with { HostReady = false } })
                Reject(() => store.MatchStartupReceipt(confirmation.Id, binding, invalid));
            clock.Now = clock.Now.AddMinutes(2);
            Reject(() => store.MatchStartupReceipt(confirmation.Id, binding, receipt));
            clock.Now = clock.Now.AddMinutes(-3);
            Reject(() => store.MatchStartupReceipt(confirmation.Id, binding, receipt));
            clock.Now = clock.Now.AddMinutes(1).AddSeconds(10);
            if (store.Inspect()?.State != "awaiting-startup") throw new Exception("Rejected receipt changed state.");
            store.MatchStartupReceipt(confirmation.Id, binding, receipt);
            if (new WpfMigrationConfirmationStore(root).Inspect()?.State != "startup-receipt-matched")
                throw new Exception("Receipt match was not persisted.");
            Reject(() => store.MatchStartupReceipt(confirmation.Id, binding, receipt));
            Reject(() => store.Confirm(binding, true));
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    private sealed class TestClock : TimeProvider
    {
        internal DateTimeOffset Now = new(2026, 9, 19, 12, 0, 0, TimeSpan.Zero);
        public override DateTimeOffset GetUtcNow() => Now;
    }

    private static void Reject(Action action)
    {
        try { action(); }
        catch (Exception e) when (e is InvalidOperationException or InvalidDataException or IOException or System.Text.Json.JsonException) { return; }
        throw new Exception("Unsafe confirmation operation was accepted.");
    }
}
