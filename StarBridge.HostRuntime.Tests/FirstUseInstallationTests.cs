using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static partial class FirstUseBusinessOwnerTests
{
    private static async Task InstallationDormant()
    {
        using var f = new Fixture(); await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        Check(prepared.StageInstallation(callbacks, Task.CompletedTask) is null, "Installation needs the original local exit.");
        var install = prepared.StageInstallation(callbacks, sources)!;
        Check(ReferenceEquals(install, prepared.StageInstallation(callbacks, sources)) && !install.IsActive,
            "One original dormant installation is staged.");
        var calls = 0;
        Check(install.Configure(owner =>
        {
            calls++;
            owner.ConfigureOverlayCommunitySource(f.Original.Local.Root);
            owner.ConfigureLiveOverlayUpdates(new InstallationSink());
            owner.ConfigureSharedActivity(new InstallationActivitySink());
        }) && install.Configure(_ => calls++), "Original configuration is idempotent.");
        Check(calls == 1 && f.Original.Clock.Timers == 0 && f.Original.Host!.BusinessStartupDeferred &&
            install.Owner.NativeNotificationOwner.Context is null && install.Owner.FirstUseAuthenticationSealed &&
            f.Original.Store.Read().Phase == "onlinePending" && native.Generation == -1,
            "Configuration is dormant, not Native replacement or online mode completion.");
        try { install.Owner.ConfigureLiveOverlayUpdates(new InstallationSink()); throw new Exception("Configuration scope escaped."); }
        catch (InvalidOperationException) { }
        var rejected = await install.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Id(), install.Owner.Generation, new { schemaVersion = 1 }));
        Check(rejected.Response.Status != BridgeResponseStatuses.Ok, "Dormant business dispatcher cannot serve online work.");
        Check(await Finish(install.RetireAsync()) && (await f.Original.Cancel()).State == "local", "Original dormant graph retires.");
    }

    private static async Task InstallationActivation()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!;
        Check(!install.TryActivate(), "Activation cannot skip original configuration.");
        Check(install.Configure(owner =>
        {
            owner.ConfigureOverlayCommunitySource(f.Original.Local.Root);
            owner.ConfigureLiveOverlayUpdates(new InstallationSink());
        }), "Original dormant Native configuration required.");
        Check(!install.Owner.AvatarStoreOpen, "Avatar store stays closed before the installation is live.");
        Check(install.TryActivate() && install.TryActivate() && install.IsActive && f.Original.Clock.Timers == 7 &&
            f.Original.Clock.Created.All(timer => timer.Changes == 1), "Exactly six original Host timers start once.");
        Check(install.Owner.NativeNotificationOwner.Context == f.Original.Host!.GameplayTimeContext &&
            install.Owner.NativeNotificationOwner.Context is not null && install.Owner.FirstUseAuthenticationSealed,
            "Host sources use actual installed storage without reopening authentication.");
        Check(install.Owner.AvatarStoreOpen, "A live installation can keep and clear the stored avatar.");
        var current = await install.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Id(), install.Owner.Generation, new { schemaVersion = 1 }));
        Check(current.Response.Status == BridgeResponseStatuses.Ok, "Independent installed lane serves actual account business.");
        Check((await f.Original.Login()).Response.Status != BridgeResponseStatuses.Ok &&
            (await install.DispatchAsync(BridgeEnvelope.Request("account.login", Id(), install.Owner.Generation, new { schemaVersion = 1 }))).Response.Status != BridgeResponseStatuses.Ok,
            "Neither lane can reopen the retired authentication dispatcher.");
        Check(native.Generation == -1 && f.Original.Store.Read().Phase == "onlinePending",
            "Host activation does not forge Native or durable mode completion.");
        Check(await Finish(install.RetireAsync()) && f.Original.Clock.Created.All(timer => timer.Disposed) &&
            !install.TryActivate() && install.Owner.NativeNotificationOwner.Context is null && !install.Owner.AvatarStoreOpen,
            "All original Host timers physically exit before the original vault is removed.");
        Check((await f.Original.Cancel()).State == "local", "Original mode can finish local cancellation.");
    }

    private static async Task InstallationConfigurationExit()
    {
        using var f = new Fixture(); await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!;
        var entered = Signal(); var release = Signal(); var rejected = false;
        var configure = Task.Run(() => install.Configure(owner =>
        {
            owner.ConfigureOverlayCommunitySource(f.Original.Local.Root);
            entered.TrySetResult();
            if (!release.Task.Wait(TimeSpan.FromSeconds(8))) throw new TimeoutException();
            try { owner.ConfigureLiveOverlayUpdates(new InstallationSink()); }
            catch (InvalidOperationException) { rejected = true; }
        }));
        try
        {
            await Finish(entered.Task);
            var exit = install.RetireAsync();
            Check(!exit.IsCompleted && f.Original.Vault.LoadActiveAccountKey() is not null && !install.TryActivate(),
                "Closing a slow configuration cannot acknowledge graph exit or clear original credentials.");
            release.TrySetResult();
            Check(!await Finish(configure) && rejected, "Late configuration cannot allocate another Native owner.");
            Check(await Finish(exit) && f.Original.Vault.LoadActiveAccountKey() is null &&
                (await f.Original.Cancel()).State == "local", "Actual callback exit precedes credential removal.");
        }
        finally { release.TrySetResult(); }
    }

    private static async Task InstallationConfigurationThread()
    {
        using var f = new Fixture(); await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!;
        var refused = false;
        Check(install.Configure(owner =>
        {
            Task.Factory.StartNew(() =>
            {
                try { owner.ConfigureOverlayCommunitySource(f.Original.Local.Root); }
                catch (InvalidOperationException) { refused = true; }
            }, CancellationToken.None, TaskCreationOptions.None, new ConfigurationInlineScheduler()).GetAwaiter().GetResult();
            owner.ConfigureOverlayCommunitySource(f.Original.Local.Root);
        }) && refused && f.Original.Clock.Timers == 0, "Only the original synchronous composition callback has configuration authority.");
        Check(await Finish(install.RetireAsync()) && (await f.Original.Cancel()).State == "local", "Dormant callback graph exits.");
    }

    // Force the actual Task wait-inlining path: a child task can run on the
    // original thread yet must never inherit synchronous configuration authority.
    private sealed class ConfigurationInlineScheduler : TaskScheduler
    {
        protected override void QueueTask(Task task) { }
        protected override bool TryExecuteTaskInline(Task task, bool taskWasPreviouslyQueued) => TryExecuteTask(task);
        protected override IEnumerable<Task>? GetScheduledTasks() => [];
    }

    private static async Task InstallationRequestExit()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true;
        var clock = new AdmissionOwnershipClock(); f.Original.DataOwnerTime = clock; await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!;
        Check(install.Configure(_ => { }) && install.TryActivate(), "Actual Host business activation required.");
        f.Coordinator.Hold = true; clock.Timestamp += TimeSpan.FromMinutes(2).Ticks;
        var request = install.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Id(), install.Owner.Generation, new { schemaVersion = 1 })).AsTask();
        Check(!request.IsCompleted, "Actual original business IO must be held.");
        foreach (var name in new[] { "account.logout", "account.loginLegacy", "account.login", "account.cancelLogin" })
            Check((await install.DispatchAsync(BridgeEnvelope.Request(name, Id(), install.Owner.Generation,
                new { schemaVersion = 1 }))).Response.Status != BridgeResponseStatuses.Ok &&
                f.Original.Vault.LoadActiveAccountKey() is not null && f.Original.Transport.Revokes == 0,
                "Business lane must not bypass held IO with authentication or logout: " + name);
        var exit = install.RetireAsync();
        Check(!exit.IsCompleted && f.Coordinator.Token.IsCancellationRequested && !install.IsActive &&
            f.Original.Vault.LoadActiveAccountKey() is not null, "Independent request admission owns its original physical IO.");
        f.Coordinator.Release.TrySetResult();
        Check((await Finish(request)).Response.Status == BridgeResponseStatuses.Cancelled && await Finish(exit),
            "A late original request cannot return a business reply after retirement.");
        Check(f.Original.Vault.LoadActiveAccountKey() is null && f.Original.Clock.Created.All(timer => timer.Disposed) &&
            (await f.Original.Cancel()).State == "local", "Request and graph exit permit credential clear.");
    }

    private static async Task InstallationConfigurationFailure()
    {
        using var f = new Fixture(); await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!;
        try
        {
            install.Configure(owner => { owner.ConfigureOverlayCommunitySource(f.Original.Local.Root); throw new IOException("Synthetic Native configuration failure."); });
            throw new Exception("Expected original Native configuration failure.");
        }
        catch (IOException) { }
        Check(await Finish(install.RetireAsync()) && !install.TryActivate() && !install.Configure(_ => { }) &&
            f.Original.Vault.LoadActiveAccountKey() is null && f.Original.Clock.Timers == 0,
            "Failed configuration seals all admissions and retires its partial dormant graph.");
        Check((await f.Original.Cancel()).State == "local", "Failure retains explicit mode completion.");
    }

    private static async Task InstallationExpiredReview()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true;
        var clock = new ModeClock(); await f.Start(modeTime: clock);
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!;
        Check(install.Configure(_ => { }) && install.TryActivate(), "Original reviewed installation activates.");
        clock.Now = clock.Now.AddMinutes(10);
        Check(!prepared.IsCurrent && install.IsActive && install.Owner.NativeNotificationOwner.Context is not null,
            "Consumed installed lifecycle must not reuse expired temporary review checks.");
        var response = await install.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Id(), install.Owner.Generation, new { schemaVersion = 1 }));
        Check(response.Response.Status == BridgeResponseStatuses.Ok && await Finish(install.RetireAsync()),
            "Original installed business remains usable, then exits normally.");
        Check((await f.Original.Cancel()).State == "local", "Pending mode can still cancel after review expiry.");
    }

    private static async Task InstallationSamplerExit()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!;
        Check(install.Configure(_ => { }) && install.TryActivate(), "Original sampler must activate.");
        const System.Reflection.BindingFlags flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
        var sampler = typeof(AccountBridgeRuntime).GetField("_gameLog", flags)!.GetValue(install.Owner)!;
        var work = (StarBridge.HostRuntime.Lifecycle.AsyncWorkRetirement)sampler.GetType().GetField("_samplingWork", flags)!.GetValue(sampler)!;
        using var lease = work.Enter(default)!;
        try
        {
            var exit = install.RetireAsync();
            Check(!exit.IsCompleted && work.IsClosed && lease.Token.IsCancellationRequested &&
                f.Original.Vault.LoadActiveAccountKey() is not null,
                "Candidate credential must remain until the complete original sampler physically exits.");
            lease.Dispose();
            Check(await Finish(exit) && f.Original.Vault.LoadActiveAccountKey() is null &&
                (await f.Original.Cancel()).State == "local", "Physical sampler exit permits actual credential removal.");
        }
        finally { lease.Dispose(); }
    }

    private static async Task InstallationActivationFailure()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; f.Original.Clock.FailAt = 3; await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!;
        Check(install.Configure(_ => { }), "Original dormant graph must configure before failure.");
        try { install.TryActivate(); throw new Exception("Expected partial timer activation failure."); }
        catch (IOException) { }
        try { await Finish(install.RetireAsync()); throw new Exception("Expected original physical exit fault."); }
        catch (IOException) { }
        Check(!install.IsActive && !install.TryActivate() && f.Original.Clock.Created.All(timer => timer.Disposed) &&
            f.Original.Vault.LoadActiveAccountKey() is not null && (await f.Original.Cancel()).State == "recoveryRequired",
            "A faulted partial graph closes every sibling but cannot acknowledge credential removal or local completion.");
    }

    private sealed class InstallationSink : IInformationOverlayLiveUpdateSink
    {
        public bool IsVisible => false;
        public void RequestContentRefresh() { }
    }
    private sealed class InstallationActivitySink : ISharedActivitySink
    {
        public ValueTask<bool> TryPresentActivityAsync(SharedActivityNotice notice, CancellationToken token) => ValueTask.FromResult(false);
    }
}

