using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

internal static partial class FirstUseBusinessOwnerTests
{
    internal static async Task RunOnlineCommit()
    {
        await Case("online mode requires the exact live Native installation", CommitRequiresNative);
        await Case("original installed graph commits once after review expiry and survives normal close", CommitInstalledOnline);
        await Case("failed write waits for actual callback exit and restores both local graphs", CommitWriteFailure);
        await Case("leaving the UI wait does not abandon the original commit recovery", CommitObserverCancellation);
        await Case("closing first cannot save online or preserve an uncommitted session", CommitCloseFirst);
        await Case("Close waits for an in-flight write classification before choosing sign-out", CommitCloseBeforeWrite);
        await Case("unknown external write preserves the exact newer state and credential through Close", CommitUnknownWrite);
        await Case("root-slot Native shutdown waits for an uninstalled OAuth candidate", CommitPendingNativeExit);
        await Case("total close waits for the physically held replacement sampler during recovery", CommitRecoverySamplerExit);
    }

    private static async Task<AccountBridgeRuntime.FirstUseBusinessInstallation> CommitInstallation(Fixture f,
        NativeAccountRuntimeBinding native, bool attach = true)
    {
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var installed = prepared.StageInstallation(callbacks, sources)!;
        Check(installed.Configure(_ => { }) && installed.TryActivate(), "Actual Host graph must be live.");
        if (attach) Check(native.InstallBusiness(installed) is { IsCurrent: true }, "Actual Native slot must be installed.");
        return installed;
    }

    private static async Task CommitRequiresNative()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var installed = await CommitInstallation(f, native, attach: false);
        var original = f.Original.Store.Read();
        try { f.Original.Store.Save(3, Id(), "online", () => true); throw new Exception("Ordinary writer bypassed Native."); }
        catch (LocalFirstUseException error) { Check(error.Code == "firstUse.mode_receipt_required", "Expected receipt refusal."); }
        try { await f.Original.Mode.CommitOnlineAsync(3, Id(), installed); throw new Exception("Missing Native receipt was accepted."); }
        catch (LocalFirstUseException) { }
        Check(f.Original.Store.Read() == original && f.Original.Vault.LoadActiveAccountKey() is not null,
            "Rejected commit does not change mode or sign out the existing candidate.");
        Check(await Finish(installed.RetireAsync()) && (await f.Original.Cancel()).State == "local", "Original cleanup remains available.");
    }

    private static async Task CommitInstalledOnline()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true;
        var clock = new ModeClock(); await f.Start(modeTime: clock);
        var root = f.Original.Local.Runtime;
        await using var native = new NativeAccountRuntimeBinding(root);
        var installed = await CommitInstallation(f, native);
        clock.Now = clock.Now.AddMinutes(10);
        var operation = Id();
        var work = f.Original.Mode.CommitOnlineAsync(3, operation, installed);
        Check(ReferenceEquals(work, f.Original.Mode.CommitOnlineAsync(3, operation, installed)), "Same transaction owns one physical task.");
        Check((await Finish(work)) is { State: "online", Revision: 4 } &&
            f.Original.Mode.Current.State == "online" && f.Original.Store.Read().Phase == "online" &&
            f.Original.Mode.ControlGeneration == native.Generation && native.Generation != root.Generation &&
            f.Original.Clock.Timers == 7 && installed.IsActive, "Durable commit preserves the same graph after temporary review expires.");
        Check(!Directory.Exists(Path.Combine(f.Original.Local.Root, "privacy-local-v1")) &&
            !File.Exists(Path.Combine(f.Original.Local.Root, "sync-privacy.settings.json")),
            "Installing online during setup saves no sharing consent, scope or visibility.");
        var reply = await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Id(), native.Generation, new { schemaVersion = 1 }));
        Check(reply.Response.Status == BridgeResponseStatuses.Ok, "Committed Native business still serves the original installation.");
        var bytes = File.ReadAllBytes(f.Original.VaultPath);
        var release = Signal(); var cancelled = Signal();
        var read = native.ReadAsync(async (_, token) =>
        { using var registration = token.Register(() => cancelled.TrySetResult()); await release.Task; return true; });
        var exit = native.DisposeAsync().AsTask();
        try
        {
            await Finish(cancelled.Task);
            Check(!exit.IsCompleted && bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)), "Normal close waits actual callback without credential clear.");
        }
        finally { release.TrySetResult(); try { await Finish(read); } catch (OperationCanceledException) { } }
        await Finish(exit);
        Check(installed.Owner.HasPreservedFirstUseSessionExit && !installed.HasCompletedCandidateExit &&
            bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Clock.Created.All(timer => timer.Disposed) &&
            f.Original.Store.Read().Phase == "online", "Physical close preserves the durable online login, not a local retirement receipt.");
        var starts = 0;
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Original.Local.Root,
            _ => { starts++; return Task.FromResult(new AccountBridgeRuntime(new EnvironmentLockedAccountBridgeHost("synthetic"))); });
        Check(starts == 1, "Completed online choice permits the ordinary cold-start account owner.");
        f.Original.Local.RequireLocalStateUnchanged();
    }

    private static async Task CommitWriteFailure() => await FailedCommitRecovery(cancelObserver: false);
    private static async Task CommitObserverCancellation() => await FailedCommitRecovery(cancelObserver: true);

    private static async Task FailedCommitRecovery(bool cancelObserver)
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        var root = f.Original.Local.Runtime;
        await using var native = new NativeAccountRuntimeBinding(root);
        var epoch = f.Original.Mode.LocalMode().Generation;
        var installed = await CommitInstallation(f, native);
        var release = Signal(); var cancelled = Signal();
        var read = native.ReadAsync(async (_, token) =>
        { using var registration = token.Register(() => cancelled.TrySetResult()); await release.Task; return true; });
        FileStream? writer = new(Path.Combine(f.Original.Local.Root, "first-use-mode-v1", "state.bin.lock"),
            FileMode.Open, FileAccess.ReadWrite, FileShare.None);
        using var observer = new CancellationTokenSource();
        var operation = Id();
        var physical = f.Original.Mode.CommitOnlineAsync(3, operation, installed);
        var observed = f.Original.Mode.CommitOnlineAsync(3, operation, installed, observer.Token);
        try
        {
            await Finish(cancelled.Task);
            Check(!physical.IsCompleted && !read.IsCompleted && f.Original.Mode.Current.State == "switching" &&
                !root.HasCurrentFirstUseLocalSources(epoch) && f.Original.Vault.LoadActiveAccountKey() is not null,
                "Failed write cannot publish local readiness or clear credentials before original callbacks exit.");
            if (cancelObserver)
            {
                observer.Cancel();
                try { await observed; throw new Exception("Cancelled observer remained attached."); } catch (OperationCanceledException) { }
                Check(!physical.IsCompleted, "UI cancellation cannot abandon the original recovery task.");
            }
            writer.Dispose(); writer = null;
        }
        finally
        {
            writer?.Dispose(); release.TrySetResult();
            try { await Finish(read); } catch (OperationCanceledException) { }
        }
        Check((await Finish(physical)).State == "local" && f.Original.Mode.Current.State == "local" &&
            f.Original.Mode.LocalMode() == (true, epoch) && root.HasCurrentFirstUseLocalSources(epoch) &&
            native.Read(owner => ReferenceEquals(owner, root), false) && installed.HasCompletedCandidateExit &&
            f.Original.Vault.LoadActiveAccountKey() is null && f.Original.Clock.Created.All(timer => timer.Disposed),
            "Only durable local return plus real sources and Native reconstruction completes recovery.");
        f.Original.Local.RequireLocalStateUnchanged();
    }

    private static async Task CommitCloseFirst()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var installed = await CommitInstallation(f, native);
        f.Original.Mode.Close();
        try { await f.Original.Mode.CommitOnlineAsync(3, Id(), installed); throw new Exception("Closed mode committed online."); }
        catch (LocalFirstUseException) { }
        Check(await Finish(f.Original.Mode.CloseOwnedOnlineAsync()!) && installed.HasCompletedCandidateExit &&
            f.Original.Store.Read().Phase == "onlinePending" && f.Original.Vault.LoadActiveAccountKey() is null,
            "Close-first keeps the durable pending choice and performs actual sign-out.");
    }

    // Pause the real Task.Yield before IO without substituting a filesystem or
    // authorizing a fake receipt. This reproduces close/external-write ordering.
    private sealed class CommitQueue : SynchronizationContext
    {
        private SendOrPostCallback? _callback;
        private object? _state;
        public override void Post(SendOrPostCallback callback, object? state)
        { Check(_callback is null, "Only the original commit continuation may be queued."); _callback = callback; _state = state; }
        internal Task Start() => Task.Run(() => _callback!(_state));
    }

    private static Task<FirstUseModeObservation> QueueCommit(Fixture f,
        AccountBridgeRuntime.FirstUseBusinessInstallation installed, CommitQueue queue)
    {
        var original = SynchronizationContext.Current;
        SynchronizationContext.SetSynchronizationContext(queue);
        try { return f.Original.Mode.CommitOnlineAsync(3, Id(), installed); }
        finally { SynchronizationContext.SetSynchronizationContext(original); }
    }

    private static async Task CommitCloseBeforeWrite() => await QueuedCommitClose(externalWrite: false);
    private static async Task CommitUnknownWrite() => await QueuedCommitClose(externalWrite: true);

    private static async Task QueuedCommitClose(bool externalWrite)
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var installed = await CommitInstallation(f, native);
        var bytes = File.ReadAllBytes(f.Original.VaultPath);
        var release = Signal(); var cancelled = Signal();
        var read = native.ReadAsync(async (_, token) =>
        { using var registration = token.Register(() => cancelled.TrySetResult()); await release.Task; return true; });
        var queue = new CommitQueue(); var commit = QueueCommit(f, installed, queue);
        var expected = externalWrite ? f.Original.Store.Save(3, Id(), "onlinePending", () => true) : f.Original.Store.Read();
        var close = f.Original.Mode.CloseOwnedOnlineAsync()!;
        Check(!close.IsCompleted && !commit.IsCompleted && bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)),
            "Close cannot choose strict sign-out while the original write result has not been classified.");
        await queue.Start();
        try
        {
            await Finish(cancelled.Task);
            Check(!close.IsCompleted && !commit.IsCompleted, "Classified cleanup still waits original Native callback.");
        }
        finally { release.TrySetResult(); try { await Finish(read); } catch (OperationCanceledException) { } }
        Check((await Finish(commit)).State == "recoveryRequired" && await Finish(close) && f.Original.Store.Read() == expected,
            "Closing an unfinished commit never overwrites pending or newer external mode.");
        if (externalWrite)
            Check(installed.Owner.HasPreservedFirstUseSessionExit && !installed.HasCompletedCandidateExit &&
                bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Transport.Revokes == 0,
                "Unknown write classification physically shuts down without creating a sign-out proof.");
        else Check(installed.HasCompletedCandidateExit && f.Original.Vault.LoadActiveAccountKey() is null,
            "Known pending after Close requires actual strict sign-out.");
    }

    private static async Task CommitPendingNativeExit()
    {
        using var f = new Fixture();
        await f.Original.Prepare(); f.Original.Mode.RequestOnline(2, Id()); await f.Original.Stage();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        f.Original.Transport.HoldToken = true;
        var login = f.Original.Login(); await Finish(f.Original.Transport.TokenEntered.Task);
        var exit = native.DisposeAsync().AsTask();
        try { Check(!exit.IsCompleted && !login.IsCompleted, "A root slot cannot skip its still-running auth candidate."); }
        finally { f.Original.Transport.ReleaseToken.TrySetResult(); }
        await Finish(login); await Finish(exit);
        Check(f.Original.Vault.LoadActiveAccountKey() is null && f.Original.Store.Read().Phase == "onlinePending",
            "Actual pending candidate exit precedes total Native disposal, without committing online.");
    }

    private sealed class CommitRecoveryClock(Action creating) : TimeProvider
    {
        internal readonly TaskCompletionSource Disposing = Signal(), Release = Signal();
        internal bool Disposed;
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        { creating(); return new HeldTimer(this); }
        private sealed class HeldTimer(CommitRecoveryClock clock) : ITimer
        {
            public bool Change(TimeSpan dueTime, TimeSpan period) => !clock.Disposed;
            public void Dispose() { }
            public async ValueTask DisposeAsync()
            { clock.Disposing.TrySetResult(); await clock.Release.Task; clock.Disposed = true; }
        }
    }

    private static async Task CommitRecoverySamplerExit()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        var root = f.Original.Local.Runtime;
        await using var native = new NativeAccountRuntimeBinding(root);
        var installed = await CommitInstallation(f, native);
        Task? totalExit = null;
        var clock = new CommitRecoveryClock(() => totalExit = native.DisposeAsync().AsTask());
        // Replace only the existing dormant-sampler factory, retaining the real
        // sampler/local graph and physical ITimer disposal as the test surface.
        typeof(AccountBridgeRuntime).GetField("_newDormantGameLog",
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.SetValue(root,
            (Func<StarBridge.HostRuntime.Presence.GameLogRuntime>)(() => new(new(f.Original.Local.Root),
                () => (null, -1), () => null, time: clock, startTimer: false)));
        var release = Signal(); var cancelled = Signal();
        var read = native.ReadAsync(async (_, token) =>
        { using var registration = token.Register(() => cancelled.TrySetResult()); await release.Task; return true; });
        FileStream? writer = new(Path.Combine(f.Original.Local.Root, "first-use-mode-v1", "state.bin.lock"),
            FileMode.Open, FileAccess.ReadWrite, FileShare.None);
        var commit = f.Original.Mode.CommitOnlineAsync(3, Id(), installed);
        try
        {
            await Finish(cancelled.Task); writer.Dispose(); writer = null; release.TrySetResult();
            try { await Finish(read); } catch (OperationCanceledException) { }
            await Finish(clock.Disposing.Task);
            Check(installed.HasCompletedCandidateExit && totalExit is { IsCompleted: false } && !commit.IsCompleted &&
                f.Original.Store.Read().Phase == "local" && f.Original.Mode.Current.State != "local" && !clock.Disposed,
                "Closed candidate and durable local write cannot acknowledge a replacement sampler's physical exit.");
        }
        finally { writer?.Dispose(); release.TrySetResult(); clock.Release.TrySetResult(); }
        Check((await Finish(commit)).State == "recoveryRequired", "Close during reconstruction never claims local readiness.");
        await Finish(totalExit!);
        Check(clock.Disposed && f.Original.Vault.LoadActiveAccountKey() is null,
            "Total Native exit waits for the actual replacement timer and retains actual sign-out.");
    }
}

