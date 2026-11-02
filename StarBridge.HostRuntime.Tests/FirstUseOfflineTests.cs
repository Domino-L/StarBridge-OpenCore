using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;

internal static partial class FirstUseBusinessOwnerTests
{
    internal static async Task RunOffline()
    {
        await Case("offline retains credentials and rebuilds actual local sources and Native callbacks", OfflineRetainedSession);
        await Case("offline observer cancellation cannot abandon an original held Native callback", () => OfflineHeldCallback(false));
        await Case("Close during offline waits actual exit and retains credentials", () => OfflineHeldCallback(true));
        await Case("offline intent write failure cannot stop the live online graph", OfflineIntentWriteFailure);
        await Case("offline physical timer failure remains pending without revoking or clearing credentials", OfflinePhysicalFailure);
        await Case("offline completion write failure cannot claim local readiness or cold-start online", OfflineCompletionWriteFailure);
        await Case("external mode change during offline drain is preserved without credential deletion", OfflineExternalWrite);
        await Case("unknown intent write outcome shuts down the original graph without clearing credentials", OfflineUnknownIntent);
        await Case("Close during mode read revokes offline qualification before it can escape", OfflineReadCloseRace);
        await Case("total close waits for a held replacement sampler during offline reconstruction", OfflineRecoverySamplerExit);
    }

    private static async Task OfflineRetainedSession()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        var root = f.Original.Local.Runtime;
        await using var native = new NativeAccountRuntimeBinding(root);
        var installed = await CommitInstallation(f, native);
        await Finish(f.Original.Mode.CommitOnlineAsync(3, Id(), installed));
        foreach (var phase in new[] { "offlinePending", "offline" })
        {
            try { f.Original.Store.Save(4, Id(), phase, () => true); throw new Exception("Untyped offline receipt accepted."); }
            catch (LocalFirstUseException error) { Check(error.Code == "firstUse.mode_receipt_required", "Actual receipt required."); }
        }
        try { await f.Original.Mode.ApplyOfflineAsync(4, Id(), root.Generation); throw new Exception("Retired root stopped online candidate."); }
        catch (LocalFirstUseException) { }
        var bytes = File.ReadAllBytes(f.Original.VaultPath);
        var op = Id(); var generation = native.Generation;
        var work = f.Original.Mode.ApplyOfflineAsync(4, op, generation);
        Check(ReferenceEquals(work, f.Original.Mode.ApplyOfflineAsync(4, op, generation)), "Offline shares the original task.");
        Check((await Finish(work)) is { State: "offline", Revision: 6, PublicationSuspended: true } &&
            f.Original.Mode.Current.State == "offline" && f.Original.Mode.LocalMode().Active &&
            root.HasCurrentFirstUseLocalSources(f.Original.Mode.LocalMode().Generation) &&
            native.Read(owner => ReferenceEquals(owner, root), false) && native.Generation == generation && generation > root.Generation &&
            f.Original.Mode.ControlGeneration == native.Generation && installed.Owner.HasPreservedFirstUseSessionExit &&
            !installed.HasCompletedCandidateExit && !installed.IsActive &&
            f.Original.Clock.Created.All(timer => timer.Disposed), "Real stop and reconstruction precede offline readiness.");
        Check(bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Transport.Revokes == 0 &&
            f.Original.Store.ReadCredentialCheckpoint() is null,
            "Offline neither changes credentials nor creates a later credential-clear authorization.");
        var starts = 0;
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Original.Local.Root,
            _ => { starts++; throw new Exception("Offline restored online implicitly."); });
        Check(starts == 0 && cold.FirstUseMode!.Current.State == "offline" &&
            bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)), "Cold offline creates only device-local owners.");
        // The old fresh-login path is not a retained-session resume implementation.
        try { f.Original.Mode.RequestOnline(6, Id()); throw new Exception("Fresh login overwrote retained session."); }
        catch (LocalFirstUseException error) { Check(error.Code == "firstUse.resume_required", "Retained session resume required."); }
        f.Original.Local.RequireLocalStateUnchanged();
    }

    private static async Task OfflineHeldCallback(bool close)
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var installed = await CommitInstallation(f, native);
        await Finish(f.Original.Mode.CommitOnlineAsync(3, Id(), installed));
        var bytes = File.ReadAllBytes(f.Original.VaultPath);
        var release = Signal(); var cancelled = Signal();
        var read = native.ReadAsync(async (_, token) =>
        { using var registration = token.Register(() => cancelled.TrySetResult()); await release.Task; return true; });
        using var observer = new CancellationTokenSource();
        var op = Id(); var generation = native.Generation;
        var work = f.Original.Mode.ApplyOfflineAsync(4, op, generation);
        var observed = f.Original.Mode.ApplyOfflineAsync(4, op, generation, observer.Token);
        Task? exit = null;
        try
        {
            await Finish(cancelled.Task);
            Check(!work.IsCompleted && f.Original.Store.Read().Phase == "offlinePending" &&
                f.Original.Mode.Current.State == "switching" && !f.Original.Mode.LocalMode().Active,
                "Offline intent cannot substitute for cancellation-ignoring callback exit.");
            observer.Cancel();
            try { await observed; throw new Exception("Observer did not cancel."); } catch (OperationCanceledException) { }
            if (close) { exit = native.DisposeAsync().AsTask(); Check(!exit.IsCompleted, "Total close awaits offline transition."); }
            Check(!work.IsCompleted && bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)), "Physical owner remains attached.");
        }
        finally { release.TrySetResult(); try { await Finish(read); } catch (OperationCanceledException) { } }
        Check((await Finish(work)).State == (close ? "recoveryRequired" : "offline"), "Closed mode cannot report restored local readiness.");
        if (exit is not null) await Finish(exit);
        Check(installed.Owner.HasPreservedFirstUseSessionExit && !installed.HasCompletedCandidateExit &&
            bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Transport.Revokes == 0,
            "UI cancellation and application close cannot turn offline into logout.");
    }

    private static async Task OfflineIntentWriteFailure()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var installed = await CommitInstallation(f, native);
        await Finish(f.Original.Mode.CommitOnlineAsync(3, Id(), installed));
        var before = f.Original.Store.Read(); var bytes = File.ReadAllBytes(f.Original.VaultPath);
        using (var writer = new FileStream(Path.Combine(f.Original.Local.Root, "first-use-mode-v1", "state.bin.lock"),
            FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            Check((await Finish(f.Original.Mode.ApplyOfflineAsync(4, Id(), native.Generation))).State == "recoveryRequired",
                "A failed intent write remains visible.");
        Check(f.Original.Store.Read() == before && f.Original.Mode.Current.State == "online" && installed.IsActive &&
            native.Read(owner => ReferenceEquals(owner, installed.Owner), false) &&
            bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Clock.Created.All(timer => !timer.Disposed),
            "Failure before durable intent leaves the original graph and credential intact.");
        Check((await Finish(f.Original.Mode.ApplyOfflineAsync(4, Id(), native.Generation))).State == "offline",
            "An exactly unwritten intent can be retried after the actual writer conflict is released.");
    }

    private static async Task OfflinePhysicalFailure()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var installed = await CommitInstallation(f, native);
        await Finish(f.Original.Mode.CommitOnlineAsync(3, Id(), installed));
        f.Original.Clock.Created[0].FailDispose = true;
        var bytes = File.ReadAllBytes(f.Original.VaultPath);
        Check((await Finish(f.Original.Mode.ApplyOfflineAsync(4, Id(), native.Generation))).State == "recoveryRequired" &&
            f.Original.Store.Read().Phase == "offlinePending" && !f.Original.Mode.LocalMode().Active &&
            !installed.Owner.HasPreservedFirstUseSessionExit && f.Original.Transport.Revokes == 0 &&
            bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)), "Faulted physical exit cannot mint offline readiness or sign-out.");
        try { await Finish(native.DisposeAsync().AsTask()); throw new Exception("Faulted exit became total success."); }
        catch (IOException error) when (error.Message == "Synthetic timer retirement failure.") { }
    }

    private static async Task OfflineCompletionWriteFailure() => await OfflineAfterDrain(external: false);
    private static async Task OfflineExternalWrite() => await OfflineAfterDrain(external: true);
    private static async Task OfflineAfterDrain(bool external)
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var installed = await CommitInstallation(f, native);
        await Finish(f.Original.Mode.CommitOnlineAsync(3, Id(), installed));
        var bytes = File.ReadAllBytes(f.Original.VaultPath);
        var release = Signal(); var cancelled = Signal();
        var read = native.ReadAsync(async (_, token) =>
        { using var registration = token.Register(() => cancelled.TrySetResult()); await release.Task; return true; });
        var work = f.Original.Mode.ApplyOfflineAsync(4, Id(), native.Generation);
        FileStream? writer = null; FirstUseModeChoice? expected = null;
        try
        {
            await Finish(cancelled.Task);
            expected = external ? f.Original.Store.Save(5, Id(), "onlinePending", () => true) : f.Original.Store.Read();
            if (!external) writer = new(Path.Combine(f.Original.Local.Root, "first-use-mode-v1", "state.bin.lock"),
                FileMode.Open, FileAccess.ReadWrite, FileShare.None);
            release.TrySetResult();
            try { await Finish(read); } catch (OperationCanceledException) { }
            Check((await Finish(work)).State == "recoveryRequired" && f.Original.Store.Read() == expected &&
                !f.Original.Mode.LocalMode().Active && installed.Owner.HasPreservedFirstUseSessionExit &&
                bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Transport.Revokes == 0,
                "Unknown/newer or failed completion never overwrites state, restores local early, or clears the retained credential.");
        }
        finally { writer?.Dispose(); release.TrySetResult(); }
        var starts = 0;
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Original.Local.Root,
            _ => { starts++; throw new Exception("Pending mode restored online implicitly."); });
        Check(starts == 0 && cold.FirstUseMode!.Current.State != "online", "Unfinished offline blocks automatic account restore.");
    }

    private static async Task OfflineUnknownIntent()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var installed = await CommitInstallation(f, native);
        await Finish(f.Original.Mode.CommitOnlineAsync(3, Id(), installed));
        var bytes = File.ReadAllBytes(f.Original.VaultPath);
        var queue = new CommitQueue(); var original = SynchronizationContext.Current;
        Task<FirstUseModeObservation> work;
        SynchronizationContext.SetSynchronizationContext(queue);
        try { work = f.Original.Mode.ApplyOfflineAsync(4, Id(), native.Generation); }
        finally { SynchronizationContext.SetSynchronizationContext(original); }
        var external = f.Original.Store.Save(4, Id(), "onlinePending", () => true);
        await queue.Start();
        Check((await Finish(work)).State == "recoveryRequired" && !installed.IsActive &&
            installed.Owner.HasPreservedFirstUseSessionExit && f.Original.Clock.Created.All(timer => timer.Disposed) &&
            f.Original.Store.Read() == external && bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)),
            "External state before intent write cannot leave any original online background owner running.");
    }

    private sealed class OfflineReadClock(Action reading) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() { reading(); return DateTimeOffset.UtcNow; }
    }
    private static async Task OfflineReadCloseRace()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var installed = await CommitInstallation(f, native);
        await Finish(f.Original.Mode.CommitOnlineAsync(3, Id(), installed));
        await Finish(f.Original.Mode.ApplyOfflineAsync(4, Id(), native.Generation));
        const System.Reflection.BindingFlags flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
        var modeStore = (FirstUseModeStore)typeof(FirstUseModeRuntime).GetProperty("ModeStore", flags)!.GetValue(f.Original.Mode)!;
        var closing = false;
        typeof(FirstUseModeStore).GetField("_time", flags)!.SetValue(modeStore, new OfflineReadClock(() =>
        { if (!closing) { closing = true; f.Original.Mode.Close(); } }));
        Check(!f.Original.Mode.LocalMode().Active && closing, "Read-time close invalidates the final offline epoch qualification.");
    }

    private static async Task OfflineRecoverySamplerExit()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        var root = f.Original.Local.Runtime;
        await using var native = new NativeAccountRuntimeBinding(root);
        var installed = await CommitInstallation(f, native);
        await Finish(f.Original.Mode.CommitOnlineAsync(3, Id(), installed));
        var bytes = File.ReadAllBytes(f.Original.VaultPath);
        Task? totalExit = null;
        var clock = new CommitRecoveryClock(() => totalExit = native.DisposeAsync().AsTask());
        typeof(AccountBridgeRuntime).GetField("_newDormantGameLog",
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.SetValue(root,
            (Func<StarBridge.HostRuntime.Presence.GameLogRuntime>)(() => new(new(f.Original.Local.Root),
                () => (null, -1), () => null, time: clock, startTimer: false)));
        var work = f.Original.Mode.ApplyOfflineAsync(4, Id(), native.Generation);
        try
        {
            await Finish(clock.Disposing.Task);
            Check(totalExit is { IsCompleted: false } && !work.IsCompleted && !clock.Disposed &&
                f.Original.Mode.Current.State != "offline" && f.Original.Store.Read().Phase == "offline",
                "A durable offline choice and original graph exit cannot acknowledge the new sampler's physical exit.");
        }
        finally { clock.Release.TrySetResult(); }
        Check((await Finish(work)).State == "recoveryRequired", "Close during offline reconstruction cannot claim readiness.");
        await Finish(totalExit!);
        Check(clock.Disposed && bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Transport.Revokes == 0,
            "Total exit waits for the actual replacement timer without signing out.");
    }
}
