using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static partial class FirstUseBusinessOwnerTests
{
    internal static async Task RunNativeComposition()
    {
        await Case("Native composition cannot allocate for local or uninstalled authentication owners", CompositionAdmission);
        await Case("actual consumer composition installs once and retains device controls offline", CompositionFresh);
        await Case("retained restore allocates fresh account observers without replacing device controls", CompositionRetained);
        await Case("partial Native composition closes its original resources and restores local sources", CompositionPartialFailure);
        await Case("factory allocation racing total close cannot escape original disposal", CompositionCloseFactory);
        await Case("ordinary Native shutdown waits real activity delivery before borrowed Composite resources", CompositionOrdinaryShutdown);
    }

    private sealed class CompositionPicker : ICommunityLogoPicker
    {
        internal bool Disposed;
        public Task<CommunityLogoSource?> PickAsync(CancellationToken token) => Task.FromResult<CommunityLogoSource?>(null);
        public string Crop(string sourceRef, double x, double y, double size) => throw new InvalidOperationException();
        public void Clear() { }
        public void Dispose() => Disposed = true;
    }
    private sealed class CompositionExport : IGameplayExportPicker
    {
        public Task<string?> ChooseNewJsonFileAsync(string suggestedName, string locale, CancellationToken token) =>
            throw new InvalidOperationException("Composition cannot export data.");
    }
    private sealed class CompositionDesktop : IDesktopNotificationSink
    {
        internal bool Disposed;
        internal bool Hold;
        internal CancellationToken Token;
        internal readonly TaskCompletionSource Entered = Signal(), Release = Signal();
        public async ValueTask<bool> TryPresentAsync(DesktopNotification notice, CancellationToken token)
        {
            if (!Hold || notice.Test) return false;
            Token = token; Entered.TrySetResult();
            await Release.Task; // Real delivery deliberately ignores cancellation until physical exit.
            return false;
        }
        public void Clear() { }
        public void Dispose() { Disposed = true; Release.TrySetResult(); }
    }
    private sealed class CompositionAudio : INotificationAudioOutput
    {
        public bool TryPlay(byte[] wave) => false;
        public void Stop() { }
        public void Dispose() { }
    }
    private sealed class CompositionCelebration : IAchievementCelebrationSink
    {
        public void Submit(AchievementCelebration notice) => throw new InvalidOperationException("No synthetic award should be issued.");
        public void Clear() { }
    }
    private sealed class CompositionFixture : IDisposable
    {
        internal readonly List<CompositionPicker> Images = [];
        internal readonly List<PlayerActivityRuntime> Observers = [];
        internal readonly CompositionDesktop Desktop = new();
        internal readonly NotificationSettingsBridgeDispatcher Notifications;
        internal readonly NotificationAudioBridgeDispatcher Audio;
        internal readonly PlayerActivityRuntime Device;
        internal readonly AccountBridgeRuntime.NativeBusinessComposition Composition;
        internal bool FailActivity;
        internal Action? BeforeActivity;
        internal CompositionFixture(Fixture f, NativeAccountRuntimeBinding native)
        {
            var root = f.Original.Local.Root;
            Notifications = new(root, () => native.Generation, desktop: Desktop);
            Audio = new(root, null, new CompositionAudio(), () => native.Generation);
            Device = new(root, () => native.Generation, Desktop, () => new(true, true, false, false));
            Composition = new(root, () => { var picker = new CompositionPicker(); Images.Add(picker); return picker; },
                new CompositionExport(), owner => {
                    BeforeActivity?.Invoke();
                    if (FailActivity) throw new IOException("Synthetic activity allocation failure.");
                    var observer = new PlayerActivityRuntime(root, () => owner.Generation, Desktop, () => new(true, true, false, false));
                    Observers.Add(observer); return observer;
                }, new InstallationSink(), new InstallationActivitySink(), new CompositionCelebration(), Notifications, Audio);
        }
        internal async Task AssertDevice(long generation)
        {
            var result = await Device.DispatchAsync(BridgeEnvelope.Request("playerActivity.read", Id(), generation, new { schemaVersion = 1 }));
            Check(result.Response.Status == BridgeResponseStatuses.Ok && result.Response.Payload.GetProperty("writable").GetBoolean(),
                "The sole device-local controls follow actual Native generation and remain writable.");
            Check(!Desktop.Disposed, "Account disposal cannot dispose the borrowed device sink.");
        }
        public void Dispose() { Device.Dispose(); Notifications.Dispose(); Audio.Dispose(); Desktop.Dispose(); }
    }
    private static object? CompositionField(AccountBridgeRuntime owner, string name) => typeof(AccountBridgeRuntime)
        .GetField(name, System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.GetValue(owner);

    private static async Task CompositionAdmission()
    {
        using var f = new Fixture(); await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        using var c = new CompositionFixture(f, native);
        foreach (var owner in new[] { f.Original.Local.Runtime, f.Original.Candidate! })
        {
            try { c.Composition.Configure(owner); throw new Exception("Native composition escaped original installation."); }
            catch (InvalidOperationException) { }
            Check(!owner.TryConfigureAccountBusiness(c.Composition.Configure), "Ordinary startup cannot configure local/auth-only owners.");
        }
        Check(c.Images.Count == 0 && c.Observers.Count == 0 && f.Original.Clock.Timers == 0,
            "Constructing a composition is not permission to allocate or start account consumers.");
        await c.AssertDevice(native.Generation);
    }
    private static async Task CompositionFresh()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        using var c = new CompositionFixture(f, native);
        var result = await Finish(native.InstallConfirmedOnlineAsync(3, c.Composition.Configure));
        var owner = f.Original.Candidate!;
        Check(result.State == "online" && c.Images.Count == 3 && c.Observers.Count == 1 &&
            ReferenceEquals(CompositionField(owner, "_playerActivity"), c.Observers.Single()) &&
            ReferenceEquals(f.Original.Host!.PlayerActivityObserved?.Target, c.Observers.Single()),
            "Real installed SCM callbacks use their owned observer, never the device controls or an old owner.");
        foreach (var field in new[] { "_communityLogo", "_hangarImages", "_achievementIdeaImages", "_gameplayExport", "_overlayCommunities",
            "_liveRoomRefresh", "_activityReceiver", "_communityNotifications", "_achievementCelebration" })
            Check(CompositionField(owner, field) is not null, "Actual Native graph is missing " + field);
        await c.AssertDevice(native.Generation);
        Check((await Finish(f.Original.Mode.ApplyOfflineAsync(4, Id(), native.Generation))).State == "offline" &&
            c.Images.All(p => p.Disposed) && !c.Desktop.Disposed, "Physical account retirement owns pickers, not device sinks.");
        var stale = await c.Observers[0].DispatchAsync(BridgeEnvelope.Request("playerActivity.read", Id(), owner.Generation, new { schemaVersion = 1 }));
        Check(stale.Response.Status != BridgeResponseStatuses.Ok, "Owned retired observer's controls are disposed, not a second writer.");
        await c.AssertDevice(native.Generation);
    }
    private static async Task CompositionRetained()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        using var c = new CompositionFixture(f, native);
        await Finish(native.InstallConfirmedOnlineAsync(3, c.Composition.Configure));
        await Finish(f.Original.Mode.ApplyOfflineAsync(4, Id(), native.Generation));
        f.Original.Mode.RequestResume(6, Id()); await ConfirmRetained(f);
        Check((await Finish(native.InstallConfirmedOnlineAsync(7, c.Composition.Configure))).State == "online" &&
            c.Images.Count == 6 && c.Observers.Count == 2 && !ReferenceEquals(c.Observers[0], c.Observers[1]) &&
            ReferenceEquals(f.Original.Host!.PlayerActivityObserved?.Target, c.Observers[1]) && f.Original.Transport.Revokes == 0,
            "Same original composition allocates a fresh observer after retained identity confirmation, without logout.");
        await c.AssertDevice(native.Generation);
        await Finish(f.Original.Mode.ApplyOfflineAsync(8, Id(), native.Generation));
        Check(c.Images.All(p => p.Disposed) && f.Original.Vault.LoadActiveAccountKey() is not null,
            "Every new graph exits while keeping login and device control lifetime.");
        await c.AssertDevice(native.Generation);
    }
    private static async Task CompositionPartialFailure()
    {
        using var f = new Fixture(); await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        using var c = new CompositionFixture(f, native) { FailActivity = true };
        Check((await Finish(native.InstallConfirmedOnlineAsync(3, c.Composition.Configure))).State == "local" &&
            c.Images.Count == 3 && c.Images.All(p => p.Disposed) && c.Observers.Count == 0 &&
            f.Original.Clock.Timers == 0 && f.Original.Vault.LoadActiveAccountKey() is null &&
            native.Read(owner => ReferenceEquals(owner, f.Original.Local.Runtime), false),
            "Real partially allocated original graph retires before restoring both local graphs.");
        await c.AssertDevice(native.Generation);
    }
    private static async Task CompositionCloseFactory()
    {
        using var f = new Fixture(); await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        using var c = new CompositionFixture(f, native);
        var entered = Signal(); using var release = new ManualResetEventSlim();
        c.BeforeActivity = () => { entered.TrySetResult(); release.Wait(); };
        var physical = native.InstallConfirmedOnlineAsync(3, c.Composition.Configure);
        await Finish(entered.Task); var closing = native.DisposeAsync().AsTask();
        try { Check(!closing.IsCompleted && !physical.IsCompleted, "Original factory lease must physically exit before total disposal."); }
        finally { release.Set(); }
        Check((await Finish(physical)).State == "recoveryRequired", "Total close cannot admit a late graph.");
        await Finish(closing);
        Check(c.Images.All(p => p.Disposed) && c.Observers.Count == 1 && !c.Desktop.Disposed,
            "Rejected newly returned allocation is disposed along with original adopted consumers, not borrowed device sinks.");
        var rejected = await c.Observers[0].DispatchAsync(BridgeEnvelope.Request("playerActivity.read", Id(), 0, new { schemaVersion = 1 }));
        Check(rejected.Response.Status != BridgeResponseStatuses.Ok && f.Original.Clock.Timers == 0,
            "Late factory return owns no live preferences writer or timer.");
    }

    private static async Task CompositionOrdinaryShutdown()
    {
        using var f = new Fixture(); // Ordinary, already constructed SCM root; no candidate or mode intent.
        var revoked = false; f.Original.Local.Transport.RevokeReply = () => revoked = true;
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        using var c = new CompositionFixture(f, native);
        using var host = new HostBridgeDispatcher(Id(), () => native.Generation, ["host.lifecycle"]);
        using var preferences = new StarBridge.HostRuntime.Settings.ApplicationPreferencesBridgeDispatcher(
            f.Original.Local.Root, () => native.Generation);
        using var composite = new CompositeBridgeDispatcher(host, native, preferences,
            notifications: c.Notifications, audio: c.Audio, playerActivity: c.Device);
        Check(f.Original.Local.Runtime.TryConfigureAccountBusiness(c.Composition.Configure), "Ordinary startup uses the same actual composition.");
        var observer = c.Observers.Single();
        observer.ConfigurePolicyOwner(() => f.Original.Local.Host.CurrentContext);
        var store = new PlayerActivityPreferencesStore(f.Original.Local.Root);
        store.Save(new(Enabled: true, Scope: 4, Offline: true, StoppedGame: true), store.Read().Revision);
        PlayerActivityObservation Observe(long sequence, string state) => new(f.Original.Local.Host.Generation,
            "synthetic", "friends", "friends", sequence, true,
            [new("synthetic-peer", "Synthetic", "Pilot-Example", state, false, true)], () => true);
        await observer.ObserveAsync(Observe(1, "online")); c.Desktop.Hold = true;
        var delivery = observer.ObserveAsync(Observe(2, "inGame"));
        try
        {
            await Finish(c.Desktop.Entered.Task);
            var shutdown = native.DisposeAsync().AsTask();
            Check(!shutdown.IsCompleted && c.Desktop.Token.IsCancellationRequested && !c.Desktop.Disposed,
                "Ordinary Native disposal must await original account delivery, not only callback/local source exit.");
            c.Desktop.Release.TrySetResult(); await Finish(delivery); await Finish(shutdown);
            Check(!c.Desktop.Disposed && c.Images.All(p => p.Disposed), "Account graph exits before releasing borrowed Composite resources.");
            composite.Dispose();
            Check(c.Desktop.Disposed && !f.Original.Local.Vault.Deleted && !revoked,
                "Device disposal follows actual exit and ordinary shutdown retains login.");
        }
        finally { c.Desktop.Release.TrySetResult(); await Finish(delivery); }
    }
}
