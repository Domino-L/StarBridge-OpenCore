using System.Diagnostics;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;

internal static class FirstUseColdOnlineRecoveryTests
{
    internal static async Task Run()
    {
        using var f = new LocalAccountStopTests.Fixture();
        var store = new FirstUseModeStore(f.Root);
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        await f.Runtime.FirstUseMode!.ApplyLocalAsync(0, Op(), f.Host.Generation);
        var local = store.Read();
        var pending = store.BeginOnline(local, Op(), () => true);
        store.MarkOnlineCandidateStarted(pending, () => true);
        using (var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline))
        {
            var bytes = File.ReadAllBytes(Path.Combine(f.Root, "first-use-mode-v1", "state.bin"));
            Check((await cold.FirstUseMode!.RecoverColdOnlineAsync(pending.Revision, Op())).State == "recoveryRequired" &&
                bytes.SequenceEqual(File.ReadAllBytes(Path.Combine(f.Root, "first-use-mode-v1", "state.bin"))),
                "A live original owner cannot be replaced or acknowledged by a cold root");
        }

        using var exited = new LocalAccountStopTests.Fixture(initialSession: false);
        var opaque = Path.Combine(exited.Root, "opaque-credential.fixture");
        File.WriteAllBytes(opaque, [91, 92, 93]);
        var start = new ProcessStartInfo("dotnet") { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true };
        start.ArgumentList.Add(typeof(FirstUseColdOnlineRecoveryTests).Assembly.Location);
        start.ArgumentList.Add("--first-use-online-recovery-child"); start.ArgumentList.Add(exited.Root);
        using (var child = Process.Start(start)!)
        {
            await child.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(20));
            Check(child.ExitCode == 0, "Synthetic original owner child must complete");
        }
        using var recovered = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(exited.Root, NoOnline,
            localGameProbe: () => new("notRunning"));
        var mode = recovered.FirstUseMode!;
        var origin = new FirstUseModeStore(exited.Root).ReadOnlineOrigin()!;
        Check(origin.Owner.ReadExit() == "exited" && mode.HasColdOnlinePending && mode.Current.State == "signInRequired",
            "Actual exited process supplies provenance without implicitly restoring authentication");
        using (var cancelled = new CancellationTokenSource())
        {
            cancelled.Cancel();
            try { await mode.RecoverColdOnlineAsync(origin.Pending.Revision, Op(), cancelled.Token); throw new Exception("Canceled recovery committed"); }
            catch (OperationCanceledException) { }
        }
        var batch = await recovered.FirstUseOnlineReviewDispatcher!.DispatchAsync(StarBridge.NativeBridge.BridgeEnvelope.Request(
            "onboarding.onlineReview.v2.cancel", Op(), mode.ControlGeneration,
            new { schemaVersion = 2, revision = origin.Pending.Revision }));
        Check(batch.Response.Status == "ok" && batch.Response.AccountContext is null && batch.Events.Count == 0,
            "Actual v2 recovery control returns only the original device mode, not account authority");
        var result = mode.Current;
        Check(result is { State: "local", PublicationSuspended: true } && result.Revision == origin.Pending.Revision + 1 && mode.LocalMode().Active &&
            File.ReadAllBytes(opaque).SequenceEqual(new byte[] { 91, 92, 93 }) && !exited.Vault.Deleted &&
            exited.Transport.AllRequests == 0 && exited.Vault.Loads == 0,
            "Explicit recovery returns original local mode without vault reads, deletes, auth restore or network");
        exited.RequireLocalStateUnchanged();
        Console.WriteLine("PASS cold online recovery: original owner running/exited, explicit cancellation, retained opaque credentials and unchanged local profiles");
    }
    internal static async Task Child(string root)
    {
        var store = new FirstUseModeStore(root);
        using var original = new LocalAccountStopTests.Fixture(sharedRoot: root, initializeLocalState: false, preserveRoot: true);
        var owner = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(root, _ => Task.FromResult(original.Runtime), localGameProbe: () => new("notRunning"));
        await owner.FirstUseMode!.ApplyLocalAsync(0, Op(), original.Host.Generation);
        owner.FirstUseMode.RequestOnline(store.Read().Revision, Op());
        store.MarkOnlineCandidateStarted(store.Read(), () => true);
        // Failure may occur immediately after reserving the candidate, before any
        // auth factory runs. The conservative started record survives real exit.
    }
    private static Task<AccountBridgeRuntime> NoOnline(CancellationToken token) => throw new Exception("Recovery constructed an account");
    private static string Op() => Guid.NewGuid().ToString("N");
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
