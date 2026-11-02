using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

internal static partial class FirstUseBusinessOwnerTests
{
    internal static async Task RunNativeInstallation()
    {
        await Case("Native consumes one original live installation without reopening auth or completing mode", NativeInstallation);
        await Case("foreign Native binding cannot borrow a drained callback receipt", NativeInstallationForeign);
        await Case("full candidate exit waits for actual installed Native callback and then reconstructs local", NativeInstallationExit);
        await Case("original review control can cancel while installed Native business is physically exiting", NativeInstallationControlExit);
        await Case("mode cancellation revokes Native admission before a blocked lifetime callback exits", NativeInstallationCancelAuthority);
        await Case("total Native disposal waits for its live candidate before disposing either owner", NativeInstallationDisposal);
        await Case("failed withdrawal still waits for actual sampler exit and retains credentials", NativeInstallationFailedDisposal);
    }

    private static async Task NativeInstallation()
    {
        var clock = new ModeClock();
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start(modeTime: clock);
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var root = f.Original.Local.Runtime;
        var control = root.FirstUseOnlineReviewDispatcher;
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!;
        Check(native.InstallBusiness(install) is null && install.Configure(_ => { }) &&
            native.InstallBusiness(install) is null && install.TryActivate(), "Only an actually live graph can replace Native admission.");
        clock.Now = clock.Now.AddMinutes(10);
        Check(!prepared.IsCurrent && install.IsActive, "Temporary review expiry is not installed graph lifetime.");
        var bytes = File.ReadAllBytes(Path.Combine(f.Original.Local.Root, "first-use-mode-v1", "state.bin"));
        var receipt = native.InstallBusiness(install);
        var admittedGeneration = native.Generation;
        Check(receipt is { IsCurrent: true } && ReferenceEquals(receipt, native.InstallBusiness(install)) &&
            native.Read(owner => ReferenceEquals(owner, install.Owner), false) && native.Generation == install.Owner.Generation &&
            ReferenceEquals(control, root.FirstUseOnlineReviewDispatcher), "The same receipt serves actual Native ownership and retains root control.");
        var reply = await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Id(), native.Generation, new { schemaVersion = 1 }));
        Check(reply.Response.Status == BridgeResponseStatuses.Ok, "Native routes through installation, not the sealed authentication lane.");
        Check((await native.DispatchAsync(BridgeEnvelope.Request("account.login", Id(), native.Generation, new { schemaVersion = 1 })))
            .Response.Status != BridgeResponseStatuses.Ok, "Native installation cannot reopen login.");
        Check(native.NotificationActivation(native.Generation, new { schemaVersion = 1 }).SessionGeneration == native.Generation,
            "Native events retain the actual installed generation.");
        Check(f.Original.Store.Read().Phase == "onlinePending" && bytes.SequenceEqual(File.ReadAllBytes(
            Path.Combine(f.Original.Local.Root, "first-use-mode-v1", "state.bin"))) && f.Original.Clock.Timers == 7,
            "Native installation neither commits mode nor duplicates the graph.");
        Check(await Finish(install.RetireAsync()) && !receipt!.IsCurrent && receipt.HasExitedSuccessfully &&
            native.Generation == -1 && native.InstallBusiness(install) is null, "Physical exit permanently closes the installed slot.");
        Check((await Finish(f.Original.Cancel())).State == "local", "Root control still owns cancellation.");
        Check(root.FirstUseMode!.ControlGeneration >= admittedGeneration,
            "Even cancellation before mode commit cannot rewind the admitted transport epoch.");
    }

    private static async Task NativeInstallationForeign()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        await using var other = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var prepared = (await f.Prepare())!;
        var callbacks = (await native.PrepareHandoffAsync(prepared))!;
        Check(await other.PrepareHandoffAsync(prepared) is not null, "Both physical bindings drained their own callbacks.");
        var sources = f.Original.Local.Runtime.RetireFirstUseLocalSourcesAsync(); await Finish(sources);
        var install = prepared.StageInstallation(callbacks, sources)!;
        Check(install.Configure(_ => { }) && install.TryActivate() && other.InstallBusiness(install) is null &&
            other.Generation == -1 && native.InstallBusiness(install) is { IsCurrent: true } &&
            other.InstallBusiness(install) is null, "Only the original receipt's binding can attach before or after the unique installation.");
        Check(await Finish(install.RetireAsync()) && (await Finish(f.Original.Cancel())).State == "local", "Original graph exits normally.");
    }

    private static async Task NativeInstallationExit() => await NativeHeldExit(false);
    private static async Task NativeInstallationControlExit() => await NativeHeldExit(true);

    private static async Task NativeHeldExit(bool throughControl)
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var root = f.Original.Local.Runtime;
        var localGeneration = f.Original.Mode.LocalMode().Generation;
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!;
        Check(install.Configure(_ => { }) && install.TryActivate(), "Original live installation ready.");
        var receipt = native.InstallBusiness(install)!;
        var release = Signal(); var cancelled = Signal();
        var read = native.ReadAsync(async (owner, token) =>
        {
            Check(ReferenceEquals(owner, install.Owner), "Callback captures actual installed owner.");
            using var registration = token.Register(() => cancelled.TrySetResult());
            await release.Task; return true; // Ignore cancellation until actual callback exit.
        });
        try
        {
            using var lifecycle = new HostBridgeDispatcher(Id(), () => native.Generation, []);
            using var preferences = new StarBridge.HostRuntime.Settings.ApplicationPreferencesBridgeDispatcher(f.Original.Local.Root, () => native.Generation);
            using var composite = new CompositeBridgeDispatcher(lifecycle, native, preferences,
                firstUseOnlineReview: root.FirstUseOnlineReviewDispatcher);
            Task exit = throughControl
                ? composite.DispatchAsync(BridgeEnvelope.Request(
                    FirstUseOnlineReviewBridgeDispatcher.CancelRequest, Id(), root.FirstUseMode!.ControlGeneration,
                    new { schemaVersion = 1, revision = f.Original.Mode.Current.Revision })).AsTask()
                : install.RetireAsync();
            await Finish(cancelled.Task);
            Check(!exit.IsCompleted && !read.IsCompleted && native.Generation == -1 && !receipt.IsCurrent &&
                f.Original.Vault.LoadActiveAccountKey() is not null &&
                !await native.RestoreLocalCallbacksAsync(prepared, localGeneration),
                "Closing admission cannot acknowledge callback exit, clear credentials or reconstruct the root.");
            release.TrySetResult();
            try { await Finish(read); throw new InvalidOperationException("Stale callback result escaped."); }
            catch (OperationCanceledException) { }
            await Finish(exit);
            Check(receipt.HasExitedSuccessfully && install.HasCompletedCandidateExit && f.Original.Vault.LoadActiveAccountKey() is null,
                "Only actual Native plus full candidate exit permits credential clear.");
            if (!throughControl) Check((await Finish(f.Original.Cancel())).State == "local", "Explicit root cancellation finishes local intent.");
            Check(root.HasCurrentFirstUseLocalSources(localGeneration) &&
                !await root.RestoreFirstUseLocalSourcesAsync(sources, localGeneration),
                "Original mode cancellation restores real sources once; retired source receipts cannot rebuild again.");
            var bytes = File.ReadAllBytes(Path.Combine(f.Original.Local.Root, "first-use-mode-v1", "state.bin"));
            Check(!await native.RestoreLocalCallbacksAsync(prepared, localGeneration) && native.Read(owner => ReferenceEquals(owner, root), false),
                "Actual mode cancellation owns the fresh local slot; old callback receipts cannot replace it again.");
            await receipt.RetireAsync();
            Check(native.Read(_ => true, false) && native.InstallBusiness(install) is null &&
                bytes.SequenceEqual(File.ReadAllBytes(Path.Combine(f.Original.Local.Root, "first-use-mode-v1", "state.bin"))),
                "Late old-slot retirement cannot close the reconstructed local owner or alter mode.");
            f.Original.Local.RequireLocalStateUnchanged();
        }
        finally { release.TrySetResult(); try { await Finish(read); } catch (OperationCanceledException) { } }
    }

    private static async Task NativeInstallationCancelAuthority()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!;
        Check(install.Configure(_ => { }) && install.TryActivate(), "Original graph active.");
        var receipt = native.InstallBusiness(install)!;
        var lifetime = (CancellationTokenSource)typeof(FirstUseModeRuntime).GetField("_candidateLifetime",
            System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)!.GetValue(f.Original.Mode)!;
        using var entered = new ManualResetEventSlim(); using var release = new ManualResetEventSlim();
        using var registration = lifetime.Token.Register(() => { entered.Set(); release.Wait(TimeSpan.FromSeconds(5)); });
        var cancel = Task.Run(() => f.Original.Cancel());
        try
        {
            Check(entered.Wait(TimeSpan.FromSeconds(3)) && install.IsActive && !cancel.IsCompleted,
                "Lifetime callback holds the actual interval before physical graph retirement.");
            Check(!receipt.IsCurrent && native.Generation == -1 && !native.Read(_ => true, false) &&
                native.InstallBusiness(install) is null && f.Original.Vault.LoadActiveAccountKey() is not null,
                "Revoked original mode transaction immediately stops every Native entry without premature clear.");
            Check((await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Id(), install.Owner.Generation,
                new { schemaVersion = 1 }))).Response.Status != BridgeResponseStatuses.Ok, "A new pipe request cannot enter the held interval.");
        }
        finally { release.Set(); }
        Check((await Finish(cancel)).State == "local" && receipt.HasExitedSuccessfully && install.HasCompletedCandidateExit,
            "Only callback release permits the actual full exit and local return.");
    }

    private static async Task NativeInstallationDisposal()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!;
        Check(install.Configure(_ => { }) && install.TryActivate(), "Actual live graph ready for total shutdown.");
        var receipt = native.InstallBusiness(install)!;
        var release = Signal(); var cancelled = Signal();
        var read = native.ReadAsync(async (_, token) =>
        {
            using var registration = token.Register(() => cancelled.TrySetResult());
            await release.Task; return true;
        });
        Task? exit = null;
        try
        {
            native.Dispose(); // Synchronous caller requests the same physical exit.
            exit = native.DisposeAsync().AsTask();
            await Finish(cancelled.Task);
            Check(!exit.IsCompleted && native.Generation == -1 && !receipt.IsCurrent &&
                f.Original.Vault.LoadActiveAccountKey() is not null && !install.HasCompletedCandidateExit,
                "Neither Dispose entry point can acknowledge a held callback or preempt candidate retirement.");
            release.TrySetResult();
            try { await Finish(read); throw new InvalidOperationException("Disposed callback returned."); }
            catch (OperationCanceledException) { }
            await Finish(exit);
            Check(receipt.HasExitedSuccessfully && install.HasCompletedCandidateExit &&
                f.Original.Vault.LoadActiveAccountKey() is null && f.Original.Clock.Created.All(timer => timer.Disposed) &&
                !f.Original.Mode.LocalMode().Active,
                "Full candidate exit clears only its original credential; final disposal also closes retained root mode.");
            await native.DisposeAsync();
        }
        finally
        {
            release.TrySetResult(); try { await Finish(read); } catch (OperationCanceledException) { }
            if (exit is not null) await Finish(exit); else await native.DisposeAsync();
        }
    }

    private static Task NativeInstallationFailedDisposal() => NativeInstallationFailedExit(false);

    private static async Task NativeInstallationFailedExit(bool preserveSession)
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!;
        Check(install.Configure(_ => { }) && install.TryActivate(), "Actual live graph ready.");
        using var transport = new InstallationPublicationTransport();
        f.Original.Host!.ConfigurePrivacyWriter(new StarBridge.HostRuntime.Privacy.PrivacyRelayWriter(
            new Uri("https://publication.example.invalid/"), transport));
        const System.Reflection.BindingFlags flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
        var publisher = (StarBridge.HostRuntime.Privacy.PrivacyPublicationPair)typeof(AccountBridgeRuntime)
            .GetField("_privacyPublication", flags)!.GetValue(install.Owner)!;
        var visibility = typeof(AccountBridgeRuntime).GetField("_presenceVisibility", flags)!;
        ((IDisposable?)visibility.GetValue(install.Owner))?.Dispose();
        visibility.SetValue(install.Owner, new StarBridge.HostRuntime.Settings.PresenceVisibilityBridge(
            new(f.Original.Local.Root), () => install.Owner.NativeNotificationOwner,
            publisher.ChangeVisibilityAsync, f.Original.Host.SetPresenceVisibilityAuthorityAsync, () => true, () => 1));
        f.Original.Transport.AllowPresenceWrite = true;
        var read = await install.DispatchAsync(BridgeEnvelope.Request("presence.read", Id(), install.Owner.Generation,
            new { schemaVersion = 1 }, f.Original.Host.GameplayTimeContext));
        var presence = await install.DispatchAsync(BridgeEnvelope.Request("presence.set", Id(), install.Owner.Generation,
            new { schemaVersion = 1, mode = "online", expectedRevision = read.Response.Payload.GetProperty("revision").GetString() },
            f.Original.Host.GameplayTimeContext));
        Check(presence.Response.Status == BridgeResponseStatuses.Ok, "Original server presence confirmed.");
        var owner = f.Original.Host.GameplayTimeContext!;
        var policy = new StarBridge.HostRuntime.Privacy.LocalPrivacyStore(f.Original.Local.Root).Save(owner, 0, Id(),
            StarBridge.HostRuntime.Privacy.LocalPrivacySettings.EditorDefaults with { Communities = [] }, () => true);
        Check((await publisher.ApplyAsync(owner, install.Owner.Generation, policy.Revision, default)).State == "applied",
            "Actual publication acknowledged before injecting withdrawal failure.");
        var receipt = native.InstallBusiness(install)!;
        var sampler = typeof(AccountBridgeRuntime).GetField("_gameLog", flags)!.GetValue(install.Owner)!;
        var work = (StarBridge.HostRuntime.Lifecycle.AsyncWorkRetirement)sampler.GetType().GetField("_samplingWork", flags)!.GetValue(sampler)!;
        using var lease = work.Enter(default)!;
        var withdrawal = Signal(); transport.FailClear = true; transport.BeforeClear = () => withdrawal.TrySetResult();
        var shutdown = preserveSession ? install.Owner.ShutdownFirstUseOnlineCandidateAsync() : null;
        Task exit = shutdown is null ? native.DisposeAsync().AsTask() : shutdown;
        try
        {
            await Finish(withdrawal.Task);
            // Await the originally owned retirement, not a synthetic success.
            var candidate = install.RetireAsync();
            Check(!exit.IsCompleted && !candidate.IsCompleted && work.IsClosed && lease.Token.IsCancellationRequested &&
                f.Original.Vault.LoadActiveAccountKey() is not null,
                "Failed withdrawal acknowledged shutdown before the actual sampler callback exited.");
            lease.Dispose();
            if (shutdown is not null)
                Check(!await Finish(shutdown), "Failed withdrawal cannot acknowledge normal shutdown.");
            else
            {
                try { await Finish(exit); throw new Exception("Failed withdrawal must not report successful disposal."); }
                catch (InvalidOperationException) { }
            }
            Check(!await Finish(candidate) && receipt.HasExitedSuccessfully && !install.HasCompletedCandidateExit &&
                !install.Owner.HasPreservedFirstUseSessionExit &&
                f.Original.Vault.LoadActiveAccountKey() is not null && f.Original.Clock.Created.All(timer => timer.Disposed),
                "Physical exit cannot substitute withdrawal confirmation or authorize credential removal.");
        }
        finally
        {
            lease.Dispose();
            try { await Finish(exit); } catch (InvalidOperationException) { }
            if (preserveSession)
                try { await Finish(native.DisposeAsync().AsTask()); } catch (InvalidOperationException) { }
        }
    }
}

