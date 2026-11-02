using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static partial class FirstUseModeTests
{
    internal static async Task<int> OrganizationPolicyWorker(string root, string ownerJson)
    {
        var resolved = Path.GetFullPath(root);
        var parent = Path.Combine(Path.GetTempPath(), "starbridge-first-use-account-stop") + Path.DirectorySeparatorChar;
        if (!resolved.StartsWith(parent, StringComparison.OrdinalIgnoreCase) || !Guid.TryParseExact(Path.GetFileName(resolved), "N", out _)) return 2;
        var owner = JsonSerializer.Deserialize<BridgeAccountContext>(ownerJson, BridgeProtocol.JsonOptions)!;
        var store = new OfflineAccountStore(resolved);
        using var lease = store.BeginOrganizationRead(owner, () => true) ?? throw new Exception("Worker failed admission");
        Console.WriteLine("READY");
        var command = await Console.In.ReadLineAsync();
        if (command == "deny")
            try { store.CompleteOrganizationRead(lease, true, () => true); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        else if (command != "exit") return 2;
        return 0;
    }

    internal static async Task OfflineCommunityPolicyActualProcess()
    {
        foreach (var command in new[] { "deny", "exit" })
        {
            using var f = new LocalAccountStopTests.Fixture(sampling: true);
            var owner = f.Host.CurrentContext!;
            var store = new OfflineAccountStore(f.Root);
            store.Observe(owner, "Synthetic Pilot", () => true);
            store.ObserveOrganizations(owner, 1, null, null, [new("old", "Old", null, true)], () => true);
            var executable = Environment.ProcessPath!;
            var start = new ProcessStartInfo(executable) {
                UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true,
                RedirectStandardOutput = true, RedirectStandardError = true };
            if (Path.GetFileNameWithoutExtension(executable).Equals("dotnet", StringComparison.OrdinalIgnoreCase))
                start.ArgumentList.Add(Assembly.GetExecutingAssembly().Location);
            start.ArgumentList.Add("--organization-policy-worker");
            start.ArgumentList.Add(f.Root);
            start.ArgumentList.Add(JsonSerializer.Serialize(owner, BridgeProtocol.JsonOptions));
            using var worker = Process.Start(start) ?? throw new Exception("Worker did not start");
            try
            {
                Require(await worker.StandardOutput.ReadLineAsync().WaitAsync(TimeSpan.FromSeconds(5)) == "READY", "Independent process holds a real read lease");
                var late = store.BeginOrganizationRead(owner, () => true)!;
                var path = Path.Combine(f.Root, "offline-account-v1", "organizations-policy.bin");
                using (File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read))
                {
                    await worker.StandardInput.WriteLineAsync(command);
                    worker.StandardInput.Close();
                    await worker.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5));
                    Require(worker.ExitCode == 0, "Isolated worker completed without a visible client");
                }
                store.ObserveOrganizations(owner, 1, null, null, [new("late", "Late response", null, true)], () => true, late);
                store.CompleteOrganizationRead(late, false, () => true);
                Require(new OfflineAccountStore(f.Root).ReadSelectedOrganizations(owner, () => true) is null,
                    "Another process's unresolved exit or failed refusal write remains blocked after a stale success");
                var fresh = store.BeginOrganizationRead(owner, () => true)!;
                store.ObserveOrganizations(owner, 1, null, null, [new("fresh", "Fresh", null, true)], () => true, fresh);
                store.CompleteOrganizationRead(fresh, false, () => true);
                Require(store.ReadSelectedOrganizations(owner, () => true)?.Items.Single().Name == "Fresh", "A fresh read after physical process exit heals the policy");
            }
            finally
            {
                if (!worker.HasExited)
                {
                    worker.StandardInput.Close();
                    try { await worker.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5)); }
                    catch (TimeoutException) { worker.Kill(entireProcessTree: true); await worker.WaitForExitAsync(); }
                }
            }
        }
    }
}
