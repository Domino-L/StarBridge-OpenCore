using System.Diagnostics;
using System.Text.Json;
using StarBridge.HostRuntime.Storage;

internal static class StorageMigration
{
    private const string WpfMutexName = @"Local\StarBridge.Desktop.SingleInstance.9D5E2B18";

    internal static async Task<int> Run(string argument)
    {
        var prepared = false;
        StorageMigrationPlan? plan = null;
        Mutex? wpf = null;
        var ownsWpf = false;
        try
        {
            var bootstrap = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "StarBridge");
            plan = StorageMigrationPlanFile.Read(argument, bootstrap);
            var helperPath = Path.GetFullPath(Environment.ProcessPath ?? throw new InvalidDataException());
            var clientDirectory = Path.GetDirectoryName(plan.ClientPath)!;
            if (!string.Equals(Path.GetFileName(plan.ClientPath), "starbridge_flutter.exe", StringComparison.OrdinalIgnoreCase) ||
                !string.Equals(plan.HostPath, Path.Combine(clientDirectory, "native_host", "StarBridge.NativeHost.exe"), StringComparison.OrdinalIgnoreCase) ||
                !string.Equals(helperPath, Path.Combine(clientDirectory, "native_host", "maintenance", "StarBridge.UpdateHelper.exe"), StringComparison.OrdinalIgnoreCase) ||
                !string.Equals(StorageRootLocator.Read(bootstrap), plan.Source, StringComparison.OrdinalIgnoreCase)) return 4;
            using var client = Pin(plan.ClientPid, plan.ClientStartTicks, plan.ClientPath);
            using var host = Pin(plan.HostPid, plan.HostStartTicks, plan.HostPath);
            wpf = new Mutex(false, WpfMutexName);
            try { ownsWpf = wpf.WaitOne(0); }
            catch (AbandonedMutexException) { ownsWpf = true; }
            if (!ownsWpf) return 4;
            StorageMigrationDestination.Validate(plan.Source, plan.Destination);
            await StorageMigrationHandoff.ReportPreparedAsync(plan.Nonce, CancellationToken.None);
            prepared = true;
            using var limit = new CancellationTokenSource(TimeSpan.FromMinutes(2));
            await Task.WhenAll(client.WaitForExitAsync(limit.Token), host.WaitForExitAsync(limit.Token));
            var state = "migration-failed";
            try
            {
                new StorageMigrationTransaction(plan.Bootstrap).Apply(plan.Destination, limit.Token, plan.Source);
                state = "migrated";
            }
            catch (Exception error) when (error is IOException or InvalidOperationException or OperationCanceledException)
            {
                if (string.Equals(StorageRootLocator.Read(plan.Bootstrap), plan.Destination, StringComparison.OrdinalIgnoreCase))
                    state = "migrated";
            }
            WriteResult(plan, state);
            Restart(plan.ClientPath);
            return state == "migrated" ? 0 : 5;
        }
        catch
        {
            // After a preparation receipt the original UI is allowed to exit.
            // Restore its entry point even when migration itself cannot run.
            if (prepared && plan is not null)
            {
                try { WriteResult(plan, "migration-failed"); } catch { }
                try { Restart(plan.ClientPath); } catch { }
            }
            return 6;
        }
        finally
        {
            if (prepared && plan is not null)
            {
                try
                {
                    StorageMigrationPlanFile.DeleteIfOwned(
                        Path.Combine(plan.Bootstrap, StorageMigrationPlanFile.Name),
                        plan.Bootstrap,
                        plan.Nonce);
                }
                catch { }
            }
            if (ownsWpf) try { wpf?.ReleaseMutex(); } catch (ApplicationException) { }
            wpf?.Dispose();
        }
    }

    private static Process Pin(int pid, long startTicks, string path)
    {
        var process = Process.GetProcessById(pid);
        try
        {
            if (process.HasExited || process.StartTime.ToUniversalTime().Ticks != startTicks ||
                !string.Equals(process.MainModule?.FileName, path, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException();
            return process;
        }
        catch { process.Dispose(); throw; }
    }

    private static void WriteResult(StorageMigrationPlan plan, string state)
    {
        var path = Path.Combine(plan.Bootstrap, StorageMigrationPlanFile.ResultName);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(stream, new { schemaVersion = 1, plan.Nonce, state,
                source = plan.Source, destination = plan.Destination, completedAt = DateTimeOffset.UtcNow }, StorageMigrationPlanFile.Json);
            stream.Flush(true);
        }
        File.Move(temporary, path, overwrite: true);
    }

    private static void Restart(string executable)
    {
        var start = new ProcessStartInfo(executable) { UseShellExecute = false,
            WorkingDirectory = Path.GetDirectoryName(executable)!, WindowStyle = ProcessWindowStyle.Hidden };
        Process.Start(start)?.Dispose();
    }
}
