using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using System.Reflection;

internal static partial class AccountDispatchConcurrencyTests
{
    internal static async Task CurrentDiagnostics()
    {
        AccountCurrentDiagnostics.Flush();
        var previous = HostDataRoot.CurrentRoot;
        var root = Path.Combine(previous, "current-diag-" + Guid.NewGuid().ToString("N"));
        HostDataRoot.UsePreparedRoot(root);
        var host = DispatchProxy.Create<IProjectingHost, ProjectingProbe>();
        var probe = (ProjectingProbe)(object)host;
        probe.Fast = new("signedIn", 1, Probe.Owner, "diag-private-display", null);
        using var dispatcher = new AccountBridgeDispatcher(host);
        string Log() => File.ReadAllText(Path.Combine(root, "account-current-diagnostics.log"));
        void Last(string expected)
        {
            AccountCurrentDiagnostics.Flush();
            var line = File.ReadAllLines(Path.Combine(root, "account-current-diagnostics.log")).Last(line => !line.Contains(" summary "));
            Check(line.Contains(expected) && line.Contains("waitMs=") && line.Contains("workMs=") &&
                line.Contains("readers=") && line.Contains("queuedShared="), "Missing safe diagnostic fields: " + expected);
        }
        try
        {
            var privateRequest = StarBridge.NativeBridge.BridgeEnvelope.Request(
                AccountBridgeRequestNames.GetCurrent, "diag-private-correlation", 1,
                new { schemaVersion = 1, diagnosticToken = "synthetic-diag-token-never-log" });
            Check((await dispatcher.DispatchAsync(privateRequest)).Response.Status == "ok", "Projection response");
            Check(!File.Exists(Path.Combine(root, "account-current-diagnostics.log")), "Projection wrote a detail");
            AccountCurrentDiagnostics.Flush();
            Check(Log().Contains("summary path=projection reason=none count=1"), "Missing projection summary");
            Console.WriteLine("PASS current diagnostics projection hit");

            probe.Fast = null;
            Check((await dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.GetCurrent))).Response.Status == "ok", "Full response");
            Last("path=full reason=hostDeclined");
            Console.WriteLine("PASS current diagnostics host decline");
            probe.Fast = new("signedIn", 1, Probe.Owner, "diag-private-display", null);

            var slow = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
            await Until(() => probe.Reads == 1);
            dispatcher.PublishDomainInvalidation("communities.changed", 1);
            var pending = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.GetCurrent));
            probe.ReadRelease.TrySetResult(new { schemaVersion = 1 });
            await Task.WhenAll(slow, pending);
            Last("path=full reason=pendingEvents");
            Console.WriteLine("PASS current diagnostics pending events");

            var write = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.Login));
            await Until(() => probe.Writes == 1);
            var blocked = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.GetCurrent));
            Check(!blocked.IsCompleted, "Barrier still blocks current");
            probe.WriteRelease.TrySetResult(new("signedIn", 1, Probe.Owner, "Fixture", null));
            await Task.WhenAll(write, blocked);
            Last("path=full reason=gateBarrierRunning");
            Console.WriteLine("PASS current diagnostics running barrier");

            Check(!Log().Contains(Probe.Owner.Subject) && !Log().Contains("diag-private-display") &&
                !Log().Contains("synthetic-diag-token-never-log") && !Log().Contains("diag-private-correlation"), "Account data leaked");
            Console.WriteLine("PASS current diagnostics excludes account data");
            var badRoot = Path.Combine(root, "file-as-directory");
            File.WriteAllText(badRoot, "fixture");
            HostDataRoot.UsePreparedRoot(badRoot);
            Check((await dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.GetCurrent))).Response.Status == "ok", "Writer failure affected response");
            Console.WriteLine("PASS current diagnostics write failure preserves response");
        }
        finally
        {
            probe.ReadRelease.TrySetResult(new { schemaVersion = 1 });
            probe.WriteRelease.TrySetResult(new("signedIn", 1, Probe.Owner, "Fixture", null));
            AccountCurrentDiagnostics.Flush();
            HostDataRoot.UsePreparedRoot(previous);
        }
    }
}
