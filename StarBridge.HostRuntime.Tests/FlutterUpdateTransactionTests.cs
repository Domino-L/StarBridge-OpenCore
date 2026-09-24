using System.Text.Json;
using StarBridge.HostRuntime.Updates;

internal static class FlutterUpdateTransactionTests
{
    internal static async Task Verify()
    {
        using (var fixture = new Fixture())
        {
            var activation = new Activation("success");
            var transaction = new FlutterUpdateTransaction(fixture.Install, fixture.Root);
            try
            {
                await transaction.ApplyAsync("0.6.7", activation,
                    prepared: _ => throw new IOException("Caller did not accept handoff."));
                throw new Exception("Unconfirmed handoff installed a candidate.");
            }
            catch (IOException) { }
            fixture.AssertVersion("old");
            if (activation.QuiesceCalls != 0 || activation.Restarts != 0 || Directory.Exists(Path.Combine(fixture.Root, "backup")))
                throw new Exception("Handoff failure changed original process or backup state.");
        }
        using (var fixture = new Fixture())
        {
            var activation = new Activation("success");
            var transaction = new FlutterUpdateTransaction(fixture.Install, fixture.Root, TimeSpan.FromMilliseconds(150));
            try
            {
                await transaction.ApplyAsync("0.6.7", activation,
                    prepared: token => Task.Delay(Timeout.Infinite, token));
                throw new Exception("Handoff timeout was ignored.");
            }
            catch (OperationCanceledException) { }
            fixture.AssertVersion("old");
            if (activation.QuiesceCalls != 0 || activation.Restarts != 0)
                throw new Exception("Handoff timeout disturbed the original application.");
        }
        foreach (var mode in new[] { "success", "wrong-nonce", "wrong-version", "no-frame", "no-host", "timeout", "blocked-stop" })
        {
            using var fixture = new Fixture();
            var activation = new Activation(mode);
            var transaction = new FlutterUpdateTransaction(fixture.Install, fixture.Root, TimeSpan.FromMilliseconds(150));
            if (mode == "blocked-stop")
            {
                try { await transaction.ApplyAsync("0.6.7", activation); throw new Exception("Live candidate overwritten."); }
                catch (IOException) { }
                fixture.AssertVersion("new");
                if (!Directory.Exists(Path.Combine(fixture.Root, "backup"))) throw new Exception("Backup lost while candidate live.");
                await transaction.RecoverAsync(new Activation("success"));
                fixture.AssertVersion("old");
                continue;
            }
            var status = await transaction.ApplyAsync("0.6.7", activation);
            if (status != (mode == "success" ? "committed" : "rolled-back")) throw new Exception("Wrong transaction outcome.");
            fixture.AssertVersion(mode == "success" ? "new" : "old");
            if (mode != "success" && (activation.Restarts != 1 || !Directory.Exists(Path.Combine(fixture.Root, "failed"))))
                throw new Exception("Rollback did not retain the failed version and restart old version.");
            var calls = activation.QuiesceCalls;
            if (await transaction.RecoverAsync(activation) != status || activation.QuiesceCalls != calls)
                throw new Exception("Terminal recovery repeated process operations.");
        }

        // Power-loss fixtures cover both sides of each directory rename, with the
        // journal intentionally one step behind. Only this dedicated temp tree moves.
        foreach (var mode in new[] { "prepared", "backup-moved", "candidate-moved", "old-restored", "restore-pending" })
        {
            using var fixture = new Fixture();
            var phase = "prepared";
            if (mode != "prepared")
            {
                Directory.Move(fixture.Install, Path.Combine(fixture.Root, "backup"));
                phase = "backing-up";
            }
            if (mode is "candidate-moved" or "old-restored" or "restore-pending")
            {
                Directory.Move(Path.Combine(fixture.Root, "candidate"), fixture.Install);
                phase = "activating";
            }
            if (mode is "old-restored" or "restore-pending")
            {
                Directory.Move(fixture.Install, Path.Combine(fixture.Root, "failed"));
                Directory.Move(Path.Combine(fixture.Root, "backup"), fixture.Install);
                phase = mode == "old-restored" ? "rolling-back" : "restoring";
            }
            File.WriteAllText(Path.Combine(fixture.Root, "state.json"), JsonSerializer.Serialize(new {
                schemaVersion = 1, installationName = "client", version = "0.6.7", nonce = new string('A', 64), phase }));
            var transaction = new FlutterUpdateTransaction(fixture.Install, fixture.Root);
            if (await transaction.RecoverAsync(new Activation("success")) != "rolled-back") throw new Exception("Recovery failed.");
            fixture.AssertVersion("old");
        }
        using (var fixture = new Fixture())
        {
            var transaction = new FlutterUpdateTransaction(fixture.Install, fixture.Root);
            using var lease = new FileStream(Path.Combine(fixture.Root, "transaction.lock"), FileMode.CreateNew, FileAccess.Write, FileShare.None);
            try { await transaction.ApplyAsync("0.6.7", new Activation("success")); throw new Exception("Concurrent transaction accepted."); }
            catch (IOException) { }
            fixture.AssertVersion("old");
        }
    }

    private sealed class Activation(string mode) : IFlutterUpdateActivation
    {
        public int QuiesceCalls, Restarts;
        public Task QuiesceAsync(CancellationToken cancellation)
        {
            QuiesceCalls++;
            if (mode == "blocked-stop" && QuiesceCalls > 1) throw new IOException("Candidate still running.");
            return Task.CompletedTask;
        }
        public async Task<FlutterUpdateReady> StartAndProbeAsync(string executable, string nonce, CancellationToken cancellation)
        {
            if (mode == "timeout") await Task.Delay(Timeout.Infinite, cancellation);
            return new(mode is "wrong-nonce" or "blocked-stop" ? "stale" : nonce,
                mode == "wrong-version" ? "0.6.6" : "0.6.7", 1, mode != "no-frame", mode != "no-host");
        }
        public Task StartRestoredAsync(string executable, CancellationToken cancellation) { Restarts++; return Task.CompletedTask; }
    }
    private sealed class Fixture : IDisposable
    {
        private readonly string _parent = Path.Combine(Path.GetTempPath(), "starbridge-update-transaction-test-" + Guid.NewGuid().ToString("N"));
        public string Install => Path.Combine(_parent, "client");
        public string Root => Path.Combine(_parent, ".starbridge-update-test");
        public Fixture()
        {
            foreach (var (directory, content) in new[] { (Install, "old"), (Path.Combine(Root, "candidate"), "new") })
                foreach (var file in FlutterUpdateStager.RequiredFiles)
                {
                    var path = Path.Combine(directory, file);
                    Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                    File.WriteAllText(path, content);
                }
        }
        public void AssertVersion(string value)
        {
            if (File.ReadAllText(Path.Combine(Install, "starbridge_flutter.exe")) != value) throw new Exception("Wrong active slot.");
        }
        public void Dispose() => Directory.Delete(_parent, recursive: true);
    }
}
