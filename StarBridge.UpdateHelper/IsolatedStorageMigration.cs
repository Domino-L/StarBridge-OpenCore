using System.Diagnostics;
using System.Text.Json;
using StarBridge.HostRuntime.Storage;

// Deliberately fixture-only: no production command or user-controlled roots.
internal static class IsolatedStorageMigration
{
    internal sealed record Plan(int SchemaVersion, string Nonce, int ClientPid, long ClientStartTicks,
        int HostPid, long HostStartTicks);
    internal static async Task<int> Run(string argument)
    {
        var json = new JsonSerializerOptions(JsonSerializerDefaults.Web)
            { UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow };
        try
        {
            var path = Path.GetFullPath(argument);
            var root = Path.GetDirectoryName(path)!;
            if (Path.GetFileName(path) != "plan.json" ||
                !Path.GetFileName(root).StartsWith("starbridge-storage-integration-", StringComparison.Ordinal) ||
                !string.Equals(Path.GetDirectoryName(root), Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath())), StringComparison.OrdinalIgnoreCase)) return 3;
            for (var directory = new DirectoryInfo(root); directory is not null; directory = directory.Parent)
                if ((directory.Attributes & FileAttributes.ReparsePoint) != 0) return 3;
            if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0 || new FileInfo(path).Length > 8192) return 3;
            var plan = JsonSerializer.Deserialize<Plan>(File.ReadAllText(path), json) ?? throw new InvalidDataException();
            if (plan.SchemaVersion != 1 || !Guid.TryParseExact(plan.Nonce, "N", out _) || plan.ClientPid == plan.HostPid) return 4;
            var bootstrap = Path.Combine(root, "bootstrap");
            var source = Path.Combine(root, "source");
            var target = Path.Combine(root, "target");
            var executable = Path.Combine(root, "client", "starbridge_flutter.exe");
            using var client = Pin(plan.ClientPid, plan.ClientStartTicks, executable);
            using var host = Pin(plan.HostPid, plan.HostStartTicks, Path.Combine(root, "client", "native_host", "StarBridge.NativeHost.exe"));
            using var ownership = new FileStream(Path.Combine(root, "helper.lock"), FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None);
            if (StorageRootLocator.Read(bootstrap) != source) return 4;
            StorageMigrationDestination.Validate(source, target);
            if (File.Exists(Path.Combine(bootstrap, StorageMigrationTransaction.JournalName))) return 4;
            Write("ready.json", new { schemaVersion = 1, plan.Nonce, helperPid = Environment.ProcessId });
            using var limit = new CancellationTokenSource(TimeSpan.FromSeconds(120));
            // Exact process handles, not PID polling; never force-stop either owner.
            await Task.WhenAll(client.WaitForExitAsync(limit.Token), host.WaitForExitAsync(limit.Token));
            var migrated = false;
            try
            {
                new StorageMigrationTransaction(bootstrap).Apply(target, limit.Token, expectedSource: source);
                migrated = true;
            }
            catch (Exception error) when (error is IOException or InvalidOperationException or OperationCanceledException)
            {
                // A switched pointer may mean only the final journal write failed.
                // Do not relabel uncertain state as success or change it backwards.
            }
            Write("result.json", new { schemaVersion = 1, plan.Nonce, state = migrated ? "migrated" : "migration-failed" });
            var start = new ProcessStartInfo(executable) { UseShellExecute = false,
                WorkingDirectory = Path.GetDirectoryName(executable)!, WindowStyle = ProcessWindowStyle.Hidden };
            start.Environment["SB_STORAGE_FIXTURE_RESTART"] = "1";
            using var restarted = Process.Start(start) ?? throw new IOException();
            Write("restart.json", new { schemaVersion = 1, plan.Nonce, clientPid = restarted.Id });
            return migrated ? 0 : 5;

            void Write(string name, object value)
            {
                var destination = Path.Combine(root, name);
                var temporary = destination + "." + Guid.NewGuid().ToString("N");
                using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                { JsonSerializer.Serialize(output, value, json); output.Flush(true); }
                File.Move(temporary, destination); // Never overwrite another run's receipt.
            }
        }
        catch { return 6; }
    }

    private static Process Pin(int pid, long start, string path)
    {
        var process = Process.GetProcessById(pid);
        try
        {
            if (process.HasExited || process.StartTime.ToUniversalTime().Ticks != start ||
                !string.Equals(process.MainModule?.FileName, path, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException();
            return process;
        }
        catch { process.Dispose(); throw; }
    }
}
