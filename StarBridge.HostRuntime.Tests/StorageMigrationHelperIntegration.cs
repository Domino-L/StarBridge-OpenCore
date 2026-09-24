using System.Diagnostics;
using System.Text.Json;
using StarBridge.HostRuntime.Storage;

internal static class StorageMigrationHelperIntegration
{
    internal static async Task Run(string helper, string fixture)
    {
        foreach (var mode in new[] { "success", "occupied", "wrong-process" }) await Case(helper, fixture, mode);
    }
    private static async Task Case(string helper, string fixture, string mode)
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-storage-integration-" + Guid.NewGuid().ToString("N"));
        var bootstrap = Path.Combine(root, "bootstrap");
        var source = Path.Combine(root, "source");
        var target = Path.Combine(root, "target");
        var clientRoot = Path.Combine(root, "client");
        Directory.CreateDirectory(bootstrap); Directory.CreateDirectory(source);
        File.WriteAllText(Path.Combine(bootstrap, StorageRootLocator.FileName), source);
        File.WriteAllText(Path.Combine(source, "sentinel"), "retained data");
        var owned = new List<Process>();
        using var limit = new CancellationTokenSource(TimeSpan.FromSeconds(60));
        try
        {
            FlutterUpdateHelperIntegration.BuildFixture(clientRoot, fixture);
            var client = Process.Start(new ProcessStartInfo(Path.Combine(clientRoot, "starbridge_flutter.exe"))
                { UseShellExecute = false, WindowStyle = ProcessWindowStyle.Hidden })!;
            owned.Add(client);
            var hostFile = Path.Combine(clientRoot, "fixture-host.pid");
            await WaitFile(hostFile);
            var host = Process.GetProcessById(int.Parse(File.ReadAllText(hostFile))); owned.Add(host);
            var nonce = Guid.NewGuid().ToString("N");
            File.WriteAllText(Path.Combine(root, "plan.json"), JsonSerializer.Serialize(new { schemaVersion = 1, nonce,
                clientPid = client.Id, clientStartTicks = client.StartTime.ToUniversalTime().Ticks + (mode == "wrong-process" ? 1 : 0),
                hostPid = host.Id, hostStartTicks = host.StartTime.ToUniversalTime().Ticks }));
            var start = new ProcessStartInfo(helper) { UseShellExecute = false, WindowStyle = ProcessWindowStyle.Hidden };
            start.ArgumentList.Add("--isolated-storage-plan"); start.ArgumentList.Add(Path.Combine(root, "plan.json"));
            var worker = Process.Start(start)!; owned.Add(worker);
            if (mode == "wrong-process")
            {
                await worker.WaitForExitAsync(limit.Token);
                if (worker.ExitCode == 0 || File.Exists(Path.Combine(root, "ready.json")) || client.HasExited || host.HasExited)
                    throw new Exception("Invalid process identity accepted or original disturbed.");
                Console.WriteLine("PASS migration helper rejects incorrect process identity before exit");
                return;
            }
            await WaitFile(Path.Combine(root, "ready.json"));
            using (var ready = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "ready.json"))))
                if (ready.RootElement.GetProperty("nonce").GetString() != nonce || ready.RootElement.GetProperty("helperPid").GetInt32() != worker.Id)
                    throw new Exception("Wrong helper receipt.");
            if (client.HasExited || host.HasExited || Directory.Exists(target) || StorageRootLocator.Read(bootstrap) != source)
                throw new Exception("Helper mutated before owners exited.");
            if (mode == "occupied") { Directory.CreateDirectory(target); File.WriteAllText(Path.Combine(target, "keep"), "untouched"); }
            File.WriteAllText(Path.Combine(clientRoot, "stop-fixture"), "stop isolated original");
            await worker.WaitForExitAsync(limit.Token);
            if (!client.HasExited || !host.HasExited || worker.ExitCode != (mode == "success" ? 0 : 5))
                throw new Exception("Helper exit sequencing failed.");
            if (StorageRootLocator.Read(bootstrap) != (mode == "success" ? target : source) || File.ReadAllText(Path.Combine(source, "sentinel")) != "retained data")
                throw new Exception("Migration root or retained source incorrect.");
            if (mode == "success" && File.ReadAllText(Path.Combine(target, "sentinel")) != "retained data") throw new Exception("Copy missing.");
            if (mode == "occupied" && File.ReadAllText(Path.Combine(target, "keep")) != "untouched") throw new Exception("Target overwritten.");
            using var restart = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "restart.json")));
            var restarted = Process.GetProcessById(restart.RootElement.GetProperty("clientPid").GetInt32()); owned.Add(restarted);
            if (restarted.HasExited || restarted.MainModule?.FileName != Path.Combine(clientRoot, "starbridge_flutter.exe"))
                throw new Exception("Original client executable not restarted.");
            Console.WriteLine($"PASS migration helper {mode}: waits for owners, preserves source and restarts isolated client");
        }
        finally
        {
            foreach (var process in owned.AsEnumerable().Reverse())
            {
                if (!process.HasExited) { process.Kill(entireProcessTree: true); await process.WaitForExitAsync(); }
                process.Dispose();
            }
            await Task.Delay(200);
            Directory.Delete(root, recursive: true); // Newly-created fixture only; never a user data root.
        }
        async Task WaitFile(string path)
        { while (!File.Exists(path) || new FileInfo(path).Length == 0) await Task.Delay(30, limit.Token); }
    }
}
