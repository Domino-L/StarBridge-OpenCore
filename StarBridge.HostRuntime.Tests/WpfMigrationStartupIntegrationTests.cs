using StarBridge.HostRuntime.Updates;

internal static class WpfMigrationStartupIntegrationTests
{
    internal static async Task InstalledHelper(string fixture, string helper, bool partialHandoff = false)
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-installed-startup-" + Guid.NewGuid().ToString("N"));
        var maintenance = Path.Combine(root, "native_host", "maintenance");
        Directory.CreateDirectory(maintenance);
        foreach (var directory in new[] { root, Path.Combine(root, "native_host") })
        {
            foreach (var file in Directory.GetFiles(fixture)) File.Copy(file, Path.Combine(directory, Path.GetFileName(file)));
            File.Copy(Path.Combine(fixture, "FixtureClient.exe"), Path.Combine(directory,
                directory == root ? "starbridge_flutter.exe" : "StarBridge.NativeHost.exe"));
        }
        foreach (var file in Directory.GetFiles(helper)) File.Copy(file, Path.Combine(maintenance, Path.GetFileName(file)));
        async Task<int> Probe(string directory, string version)
        {
            var start = new System.Diagnostics.ProcessStartInfo(Path.Combine(directory, "InstalledProbe.exe"))
                { UseShellExecute = false, CreateNoWindow = true };
            start.ArgumentList.Add(version);
            if (partialHandoff) start.ArgumentList.Add("partial");
            using var process = System.Diagnostics.Process.Start(start)!;
            using var limit = new CancellationTokenSource(TimeSpan.FromSeconds(15));
            await process.WaitForExitAsync(limit.Token);
            return process.ExitCode;
        }
        try
        {
            if (await Probe(helper, "0.6.7") != 3) throw new Exception("Helper accepted an unrelated location.");
            if (await Probe(maintenance, "0.7.0") != 3) throw new Exception("Helper accepted wrong version.");
            if (File.Exists(Path.Combine(root, "handoff-called"))) throw new Exception("Handoff ran before verified startup.");
            if (await Probe(maintenance, "0.6.7") != (partialHandoff ? 6 : 0)) throw new Exception("Helper did not confirm startup with correct handoff outcome.");
            if (await Probe(maintenance, "0.6.7") != 4) throw new Exception("Helper allowed a duplicate startup.");
            if (File.ReadAllText(Path.Combine(root, "handoff-called")) != "called") throw new Exception("Handoff did not run exactly once after startup.");
            Console.WriteLine("PASS installed helper: location, version, startup then handoff, duplicate guard; partial=" + partialHandoff);
        }
        finally
        {
            // Only the synthetic client watches this file. No user process is stopped.
            File.WriteAllText(Path.Combine(root, "stop-fixture"), "");
            foreach (var name in new[] { "fixture-client.pid", "fixture-host.pid" })
            {
                var file = Path.Combine(root, name);
                if (!File.Exists(file)) continue;
                try
                {
                    using var process = System.Diagnostics.Process.GetProcessById(int.Parse(File.ReadAllText(file)));
                    if (!process.HasExited && process.MainModule!.FileName!.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                    {
                        using var limit = new CancellationTokenSource(TimeSpan.FromSeconds(10));
                        await process.WaitForExitAsync(limit.Token);
                    }
                }
                catch (ArgumentException) { }
            }
            Directory.Delete(root, true);
        }
    }

    internal static async Task Run(string fixture)
    {
        foreach (var mode in new[] { "success", "no-receipt", "early-exit", "wrong-version", "cancelled" })
        {
            var root = Path.Combine(Path.GetTempPath(), "starbridge-migration-startup-" + Guid.NewGuid().ToString("N"));
            var client = Path.Combine(root, "client");
            var journal = Path.Combine(root, "journal");
            Directory.CreateDirectory(journal);
            foreach (var directory in new[] { client, Path.Combine(client, "native_host") })
            {
                Directory.CreateDirectory(directory);
                foreach (var file in Directory.GetFiles(fixture))
                    File.Copy(file, Path.Combine(directory, Path.GetFileName(file)));
                File.Copy(Path.Combine(fixture, "FixtureClient.exe"),
                    Path.Combine(directory, directory == client ? "starbridge_flutter.exe" : "StarBridge.NativeHost.exe"));
            }
            var sentinel = Path.Combine(root, "old-client-retained.txt");
            File.WriteAllText(sentinel, "old client remains available");
            using var activation = new FlutterUpdateProcessActivation();
            try
            {
                if (mode is "no-receipt" or "early-exit")
                    File.WriteAllText(Path.Combine(client, "native_host", "fail-startup"), "");
                if (mode == "early-exit")
                    File.WriteAllText(Path.Combine(client, "exit-before-receipt"), "");
                var store = new WpfMigrationConfirmationStore(journal);
                var binding = new WpfMigrationBinding(mode == "wrong-version" ? "0.7.0" : "0.6.7",
                    new('A', 64), new('B', 64), new('C', 64), new('D', 64));
                var confirmation = store.Confirm(binding, true);
                store.MarkInstallStarted(confirmation.Id, binding);
                using var limit = new CancellationTokenSource(TimeSpan.FromSeconds(mode == "no-receipt" ? 3 : 20));
                if (mode == "cancelled") limit.Cancel();
                var passed = false;
                try
                {
                    await activation.StartMigrationAndProbeAsync(Path.Combine(client, "starbridge_flutter.exe"),
                        store, confirmation.Id, binding, limit.Token);
                    passed = true;
                }
                catch (Exception e) when (e is OperationCanceledException or InvalidDataException)
                {
                    if (mode == "early-exit" && (e is not InvalidDataException || limit.IsCancellationRequested))
                        throw new Exception("Early exit must be detected without waiting for timeout.", e);
                }
                if (passed != (mode == "success")) throw new Exception("Unexpected startup result: " + mode);
                var state = new WpfMigrationConfirmationStore(journal).Inspect()!.State;
                var expected = mode switch {
                    "success" => "startup-receipt-matched", "no-receipt" or "early-exit" => "awaiting-startup", _ => "install-started" };
                if (state != expected) throw new Exception("Unexpected persisted phase: " + state);
                if (mode is "success" or "no-receipt" or "early-exit")
                {
                    using var another = new FlutterUpdateProcessActivation();
                    try
                    {
                        await another.StartMigrationAndProbeAsync(Path.Combine(client, "starbridge_flutter.exe"),
                            new WpfMigrationConfirmationStore(journal), confirmation.Id, binding, CancellationToken.None);
                        throw new Exception("Interrupted or completed startup was replayed.");
                    }
                    catch (InvalidOperationException) { }
                }
                else if (File.Exists(Path.Combine(client, "fixture-host.pid")))
                    throw new Exception("Rejected startup launched a process.");
                if (File.ReadAllText(sentinel) != "old client remains available")
                    throw new Exception("Old installation was changed.");
                Console.WriteLine("PASS actual process + pipe + durable journal: " + mode);
            }
            finally
            {
                // Only this activation's disposable candidate is stopped. Never WPF.
                using var stop = new CancellationTokenSource(TimeSpan.FromSeconds(20));
                await activation.QuiesceAsync(stop.Token);
                Directory.Delete(root, recursive: true);
            }
        }
    }
}
