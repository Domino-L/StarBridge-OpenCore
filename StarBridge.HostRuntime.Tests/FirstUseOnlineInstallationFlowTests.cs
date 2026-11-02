using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

internal static partial class FirstUseBusinessOwnerTests
{
    internal static async Task RunOnlineInstallationFlow()
    {
        await Case("installation flow refuses login without explicit identity confirmation", FlowUnconfirmed);
        await Case("one Native flow installs and commits the original confirmed fresh graph", FlowFresh);
        await Case("retained flow resumes without browser login and can enter offline again", FlowRetained);
        await Case("observer cancellation and duplicate calls retain one physical installation", FlowObserver);
        await Case("changed local evidence cannot install late ownership facts", FlowChangedSource);
        await Case("fresh cancellation during Native drain restores the original local callbacks", () => FlowCancelNativeDrain(false, false));
        await Case("retained cancellation during Native drain preserves login and local callbacks", () => FlowCancelNativeDrain(true, false));
        await Case("late cancelled drain cannot cancel or adopt a newer online intent", () => FlowCancelNativeDrain(false, true));
        await Case("fresh cancellation awaits the original held sampler before local reconstruction", () => FlowCancelSampler(false));
        await Case("retained cancellation awaits the original held sampler without sign-out", () => FlowCancelSampler(true));
        await Case("failed fresh composition restores both local graphs through original receipts", () => FlowConfigurationFailure(false));
        await Case("failed retained composition restores offline without clearing login", () => FlowConfigurationFailure(true));
        await Case("total Native close waits for the physically held composition callback", FlowCloseConfiguration);
    }

    private static async Task FlowUnconfirmed()
    {
        using var f = new Fixture(); await f.Start(confirm: false);
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var generation = native.Generation; var bytes = File.ReadAllBytes(f.Original.VaultPath);
        Check(!f.Original.Mode.HasInstalledOnlineForCompletion, "Authentication without installation cannot finish online setup.");
        try { await native.InstallConfirmedOnlineAsync(3, _ => throw new Exception("Unconfirmed composition ran."));
            throw new Exception("Unconfirmed identity installed."); }
        catch (LocalFirstUseException error) { Check(error.Code == "firstUse.context_changed", "Expected identity refusal."); }
        Check(native.Generation == generation && f.Coordinator.Reads == 0 &&
            bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)), "No Native drain, ownership read or credential mutation.");
        f.Quiet();
    }

    private static async Task FlowFresh()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var configurations = 0; Action<AccountBridgeRuntime> configure = owner =>
        { Check(ReferenceEquals(owner, f.Original.Candidate), "Original candidate, never a copied account."); configurations++; };
        var result = await Finish(native.InstallConfirmedOnlineAsync(3, configure));
        Check(f.Original.Mode.HasInstalledOnlineForCompletion, "Only the real live Native graph can qualify online completion.");
        Check(result is { State: "online", Revision: 4 } && f.Original.Mode.Current == result &&
            native.Generation == f.Original.Candidate!.Generation && configurations == 1 && f.Original.Clock.Timers == 7 &&
            f.Coordinator.Reads == 1, "The single flow consumes real Native, local and SCM receipts before mode commit.");
        Check((await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Id(), native.Generation,
            new { schemaVersion = 1 }))).Response.Status == BridgeResponseStatuses.Ok, "Actual installed business serves the pipe.");
        try { await native.InstallConfirmedOnlineAsync(3, configure); throw new Exception("Completed installation replayed."); }
        catch (LocalFirstUseException) { }
        Check(configurations == 1 && f.Original.Clock.Timers == 7, "Completed mode cannot replay old confirmation.");
    }

    private static async Task FlowRetained()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        Action<AccountBridgeRuntime> configure = _ => { };
        await Finish(native.InstallConfirmedOnlineAsync(3, configure));
        Check((await Finish(f.Original.Mode.ApplyOfflineAsync(4, Id(), native.Generation))).State == "offline", "First physical offline exit.");
        var browser = f.Original.BrowserOpens; var requests = f.Original.Transport.TokenRequests;
        f.Original.Mode.RequestResume(6, Id()); await ConfirmRetained(f);
        var next = f.Original.Candidate!;
        var result = await Finish(native.InstallConfirmedOnlineAsync(7, configure));
        Check(result is { State: "online", Revision: 8 } && native.Generation == next.Generation &&
            f.Original.Transport.TokenRequests == requests + 1 && f.Original.BrowserOpens == browser &&
            f.Original.Transport.Revokes == 0 && f.Original.Vault.LoadActiveAccountKey() is not null,
            "Retained resume refreshes the actual credential without a new browser or sign-out.");
        Check((await Finish(f.Original.Mode.ApplyOfflineAsync(8, Id(), native.Generation))).State == "offline" &&
            f.Original.Transport.Revokes == 0, "The newly installed owner supports another physical offline transition.");
        f.Original.Local.RequireLocalStateUnchanged();
    }

    private static async Task FlowObserver()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start(); f.Coordinator.Hold = true;
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var configurations = 0; Action<AccountBridgeRuntime> configure = _ => configurations++;
        using var observer = new CancellationTokenSource();
        var observed = native.InstallConfirmedOnlineAsync(3, configure, observer.Token);
        await Finish(f.Coordinator.Entered.Task);
        var physical = native.InstallConfirmedOnlineAsync(3, configure);
        try { await native.InstallConfirmedOnlineAsync(3, _ => { }); throw new Exception("Foreign composition joined."); }
        catch (LocalFirstUseException error) { Check(error.Code == "firstUse.operation_in_progress", "One original composition only."); }
        observer.Cancel();
        try { await observed; throw new Exception("Observer cancellation ignored."); } catch (OperationCanceledException) { }
        Check(!physical.IsCompleted && !f.Coordinator.Token.IsCancellationRequested && f.Original.Clock.Timers == 0,
            "UI wait abandonment is neither physical exit nor explicit mode cancellation.");
        f.Coordinator.Release.TrySetResult();
        Check((await Finish(physical)).State == "online" && configurations == 1 && f.Coordinator.Reads == 1,
            "Same physical attempt completes exactly once after real IO exit.");
    }

    private static async Task FlowChangedSource()
    {
        using var f = new Fixture(); await f.Start(); f.Coordinator.Hold = true;
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var configurations = 0;
        var physical = native.InstallConfirmedOnlineAsync(3, _ => configurations++);
        await Finish(f.Coordinator.Entered.Task);
        var identities = new LocalFirstUseStore(f.Original.Local.Root); var source = identities.Read();
        identities.InvalidateSourceIdentity(source.Revision, Id(), source.SelectedSourceKey!, () => true);
        f.Coordinator.Release.TrySetResult();
        var result = await Finish(physical);
        Check(result.State == "local" && configurations == 0 && f.Original.Clock.Timers == 0 &&
            f.Original.Vault.LoadActiveAccountKey() is null && native.Read(owner => ReferenceEquals(owner, f.Original.Local.Runtime), false),
            "Changed source never transfers authority; original candidate exits and old local callbacks stay installed.");
    }

    private static async Task FlowConfigurationFailure(bool retained)
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        if (retained) { await EnterOffline(f, native); f.Original.Mode.RequestResume(6, Id()); await ConfirmRetained(f); }
        var bytes = File.ReadAllBytes(f.Original.VaultPath); var revokes = f.Original.Transport.Revokes;
        var result = await Finish(native.InstallConfirmedOnlineAsync(retained ? 7 : 3,
            _ => throw new IOException("Synthetic Native composition failure.")));
        Check(result.State == (retained ? "offline" : "local") && f.Original.Mode.Current == result &&
            native.Read(owner => ReferenceEquals(owner, f.Original.Local.Runtime), false) &&
            f.Original.Local.Runtime.HasCurrentFirstUseLocalSources(f.Original.Mode.LocalMode().Generation),
            "Failed composition consumes exact exit receipts to rebuild both actual local graphs.");
        Check(retained ? bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Transport.Revokes == revokes :
            f.Original.Vault.LoadActiveAccountKey() is null, "Exit preserves retained login, but clears a genuinely fresh cancelled login.");
        var failure = native.ObserveOnlineInstallation(retained ? 7 : 3).Failure;
        Check(failure is { Stage: "configureBusiness", Kind: "storage" },
            "Both retained and fresh recovery preserve the original bounded failure.");
        f.Original.Local.RequireLocalStateUnchanged();
    }

    private static async Task FlowCancelNativeDrain(bool retained, bool newerIntent)
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        if (retained) { await EnterOffline(f, native); f.Original.Mode.RequestResume(6, Id()); await ConfirmRetained(f); }
        var revision = f.Original.Store.Read().Revision; var release = Signal(); var cancelled = Signal();
        var held = native.ReadAsync(async (_, token) =>
        { using var registration = token.Register(() => cancelled.TrySetResult()); await release.Task; return true; });
        var configurations = 0;
        var physical = native.InstallConfirmedOnlineAsync(revision, _ => configurations++);
        await Finish(cancelled.Task);
        var local = await f.Original.Cancel();
        Check(local.State == (retained ? "offline" : "local") && !physical.IsCompleted && native.Generation == -1,
            "Saved local choice is not the still-held Native callback exit.");
        var bytes = File.ReadAllBytes(f.Original.VaultPath); var requests = f.Original.Transport.Requests;
        if (newerIntent) f.Original.Mode.RequestOnline(local.Revision, Id());
        release.TrySetResult();
        try { await Finish(held); throw new Exception("Old Native callback result survived retirement."); } catch (OperationCanceledException) { }
        var result = await Finish(physical);
        if (newerIntent)
        {
            Check(result.State == "recoveryRequired" && f.Original.Store.Read().Phase == "onlinePending" &&
                f.Original.Store.Read().Revision == local.Revision + 1 && native.Generation == -1 &&
                bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Transport.Requests == requests,
                "No mode write, Native revival, credential adoption or network request on behalf of a newer intent.");
        }
        else
        {
            Check(result == local && native.Read(owner => ReferenceEquals(owner, f.Original.Local.Runtime), false) &&
                f.Original.Local.Runtime.HasCurrentFirstUseLocalSources(f.Original.Mode.LocalMode().Generation),
                "Original cancellation proof rebuilds real sources and callback slot after actual old callback exit.");
            Check(retained ? f.Original.Transport.Revokes == 0 && f.Original.Vault.LoadActiveAccountKey() is not null :
                f.Original.Vault.LoadActiveAccountKey() is null, "Original fresh/retained exit semantics stay distinct.");
        }
        Check(configurations == 0, "Cancelled preparation never configures online business.");
    }

    private static async Task FlowCloseConfiguration()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        using var release = new ManualResetEventSlim(); var entered = Signal();
        var physical = native.InstallConfirmedOnlineAsync(3, _ => { entered.TrySetResult();
            Check(release.Wait(TimeSpan.FromSeconds(5)), "Test releases original synchronous composition."); });
        await Finish(entered.Task);
        var exit = native.DisposeAsync().AsTask();
        try
        {
            Check(!exit.IsCompleted && !physical.IsCompleted && f.Original.Vault.LoadActiveAccountKey() is not null,
                "Closing admission cannot dispose a physically held configuration or clear its credentials early.");
        }
        finally { release.Set(); }
        Check((await Finish(physical)).State == "recoveryRequired", "Closed Native owner cannot publish late online readiness.");
        await Finish(exit);
        Check(f.Original.Vault.LoadActiveAccountKey() is null && f.Original.Clock.Timers == 0,
            "Original configuration exits before final fresh candidate cleanup and synchronous disposal.");
    }

    private static async Task FlowCancelSampler(bool retained)
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        if (retained) { await EnterOffline(f, native); f.Original.Mode.RequestResume(6, Id()); await ConfirmRetained(f); }
        var flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
        var sampler = typeof(AccountBridgeRuntime).GetField("_gameLog", flags)!.GetValue(f.Original.Local.Runtime)!;
        var work = (StarBridge.HostRuntime.Lifecycle.AsyncWorkRetirement)sampler.GetType().GetField("_samplingWork", flags)!.GetValue(sampler)!;
        using var lease = work.Enter(default)!;
        var cancelled = Signal(); using var callback = lease.Token.Register(() => cancelled.TrySetResult());
        var configurations = 0;
        var physical = native.InstallConfirmedOnlineAsync(f.Original.Store.Read().Revision, _ => configurations++);
        await Finish(cancelled.Task);
        var returned = await f.Original.Cancel();
        Check(returned.State == (retained ? "offline" : "local") && !physical.IsCompleted && native.Generation == -1,
            "Actual root sampler exit, not a cancelled flag or saved mode, holds original installation recovery.");
        lease.Dispose();
        Check((await Finish(physical)) == returned && configurations == 0 &&
            native.Read(owner => ReferenceEquals(owner, f.Original.Local.Runtime), false) &&
            f.Original.Local.Runtime.HasCurrentFirstUseLocalSources(f.Original.Mode.LocalMode().Generation),
            "Original source exit permits one new local sampler and original Native callback reconstruction.");
        Check(retained ? f.Original.Transport.Revokes == 0 && f.Original.Vault.LoadActiveAccountKey() is not null :
            f.Original.Vault.LoadActiveAccountKey() is null, "Sampler recovery does not alter original credential exit semantics.");
    }
}

