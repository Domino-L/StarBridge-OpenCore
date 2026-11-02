using System.Security.Cryptography;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Hangar;
using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static class BackgroundRetirementTests
{
    private static readonly BridgeAccountContext Owner = new("fixture", "scm", "synthetic-background");
    private static readonly DateTimeOffset Origin = DateTimeOffset.UtcNow;
    internal static async Task Run()
    {
        await Case("hangar replacement retains every former request until actual exit", HangarGenerations);
        await Case("shared activity waits for a cancellation-ignoring read", ActivityRead);
        await Case("shared activity invalidates and drains an already submitted native notice", ActivityOutput);
        await Case("organization notifications wait for the actual feed exit", OrganizationRead);
        await Case("organization notifications drain native submission without replay", OrganizationOutput);
        await Case("achievement retirement rejects late cloud receipts and releases the outbox owner", Achievements);
        await Case("overlay retirement drains external foreground reads", OverlayRead);
        await Case("overlay retirement drains independent module-source reads", OverlayModules);
        await Case("room refresh retirement awaits actual transport completion", RoomDriver);
        await Case("player activity retires account output but preserves device controls", () => PlayerActivity(false));
        await Case("player activity retains unknown-environment retry output through retirement", () => PlayerActivity(true));
    }
    private static async Task Case(string label, Func<Task> run)
    { await run(); Console.WriteLine("PASS first-use background stop: " + label); }
    private static void Check(bool value, string label) { if (!value) throw new InvalidOperationException(label); }
    private static TaskCompletionSource Done() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static async Task Finish(Task task)
    { try { await task.WaitAsync(TimeSpan.FromSeconds(3)); } catch (OperationCanceledException) { } }

    private sealed class Held : IDisposable
    {
        internal readonly TaskCompletionSource Started = Done(), Release = Done();
        internal CancellationToken Token;
        internal async Task<T> Read<T>(T value, CancellationToken token)
        { Token = token; Started.TrySetResult(); await Release.Task; return value; }
        public void Dispose() => Release.TrySetResult();
    }
    private sealed class Temp : IDisposable
    {
        internal string Root { get; } = Path.Combine(Path.GetTempPath(), "starbridge-background-stop", Guid.NewGuid().ToString("N"));
        internal Temp() => Directory.CreateDirectory(Root);
        public void Dispose()
        {
            var resolved = Path.GetFullPath(Root);
            var parent = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "starbridge-background-stop"));
            if (Path.GetDirectoryName(resolved) != parent || !Guid.TryParseExact(Path.GetFileName(resolved), "N", out _) ||
                File.GetAttributes(resolved).HasFlag(FileAttributes.ReparsePoint)) throw new InvalidOperationException("Unsafe fixture cleanup");
            Directory.Delete(resolved, true);
        }
    }
    private sealed class Clock : TimeProvider
    {
        internal int Timers;
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        { Timers++; return new QuietTimer(); }
        private sealed class QuietTimer : ITimer
        {
            public bool Change(TimeSpan dueTime, TimeSpan period) => true;
            public void Dispose() { }
            public ValueTask DisposeAsync() => ValueTask.CompletedTask;
        }
    }
    private static async Task HangarGenerations()
    {
        using var first = new Held(); using var last = new Held();
        var callbacks = 0; var sends = 0;
        using var sync = new HangarAutoSync((_, _, revision, token) => {
            sends++; return (revision == 1 ? first : last).Read(HangarPublicationOutcome.Complete, token);
        }, _ => callbacks++);
        var one = sync.Queue(Owner, 1, 1);
        await first.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var two = sync.Queue(Owner, 1, 2);
        await last.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var retired = sync.RetireAsync();
        Check(!retired.IsCompleted && first.Token.IsCancellationRequested && last.Token.IsCancellationRequested,
            "latest task is not the whole retired generation set");
        await sync.Queue(Owner, 2, 3);
        last.Release.TrySetResult(); await Finish(two);
        Check(!retired.IsCompleted && sends == 2 && callbacks == 0, "former request still owns its retirement lease");
        first.Release.TrySetResult(); await Finish(one); await Finish(retired);
        Check(callbacks == 0 && sends == 2, "no late invalidation or new publication after retirement");
    }
    private sealed class ActivityReader : ISharedActivityReader
    {
        internal SharedActivityRead Next = new(1, Origin, []);
        internal Held? Pending;
        internal int Reads;
        public Task<SharedActivityRead> ReadActivityAsync(BridgeAccountContext owner, long generation, string scope, string id, CancellationToken token)
        { Reads++; return Pending is null ? Task.FromResult(Next) : Pending.Read(Next, token); }
    }
    private sealed class ActivitySink : ISharedActivitySink
    {
        internal Held? Pending;
        internal SharedActivityNotice? Notice;
        internal int Calls;
        public async ValueTask<bool> TryPresentActivityAsync(SharedActivityNotice notice, CancellationToken token)
        { Calls++; Notice = notice; return Pending is null || await Pending.Read(true, token); }
    }
    private static async Task ActivityRead()
    {
        using var held = new Held(); var reader = new ActivityReader { Pending = held }; var sink = new ActivitySink(); var clock = new Clock();
        using var module = new SharedActivityReceiver(reader, sink, () => (Owner, 1, "organization", "A"), clock);
        var reading = module.TickAsync(); await held.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var retired = module.RetireAsync();
        Check(!retired.IsCompleted && held.Token.IsCancellationRequested, "cancel notification is not read exit");
        module.Start(); await module.TickAsync();
        Check(reader.Reads == 1 && clock.Timers == 0, "retired receiver cannot recreate a timer or read");
        held.Release.TrySetResult(); await Finish(reading); await Finish(retired);
        Check(sink.Calls == 0, "late read cannot present");
    }
    private static async Task ActivityOutput()
    {
        using var held = new Held(); var reader = new ActivityReader(); var sink = new ActivitySink { Pending = held };
        using var module = new SharedActivityReceiver(reader, sink, () => (Owner, 1, "organization", "A"));
        await module.TickAsync();
        reader.Next = new(1, Origin, [new("synthetic-peer", "Synthetic", [new("synthetic-event", "PlayerDied", Origin)])]);
        var output = module.TickAsync(); await held.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var retired = module.RetireAsync();
        Check(!retired.IsCompleted && held.Token.IsCancellationRequested && sink.Notice?.IsCurrent() == false,
            "queued native notice is invalid immediately but its submission must still exit");
        held.Release.TrySetResult(); await Finish(output); await Finish(retired);
        await module.TickAsync(); Check(sink.Calls == 1, "no replay after retirement");
    }
    private sealed class OrganizationReader : ICommunityNotificationReader
    {
        internal CommunityNotificationFeed Next = Feed(0);
        internal Held? Pending;
        internal int Reads;
        public Task<CommunityNotificationFeed> ReadNotificationsAsync(BridgeAccountContext owner, long generation, CancellationToken token)
        { Reads++; return Pending is null ? Task.FromResult(Next) : Pending.Read(Next, token); }
    }
    private static CommunityNotificationFeed Feed(int tick) => new(Origin.AddSeconds(tick), [
        new("organization-A", "Synthetic", Origin.AddDays(-1), true,
            new(tick + 1, 1, true, Origin.AddSeconds(tick), Origin.AddSeconds(tick), "Synthetic", "Synthetic"),
            true, [new("task-" + tick, Origin.AddSeconds(tick))])]);
    private static async Task OrganizationRead()
    {
        using var held = new Held(); var reader = new OrganizationReader { Pending = held }; var clock = new Clock(); var changes = 0;
        using var module = new CommunityNotificationRuntime(reader, () => (Owner, 1), (_, _) => ValueTask.CompletedTask,
            clock, (_, _) => changes++);
        var reading = module.TickAsync(); await held.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var retired = module.RetireAsync();
        Check(!retired.IsCompleted && held.Token.IsCancellationRequested, "feed has not exited");
        module.Start(); module.Invalidate(); await module.TickAsync();
        Check(clock.Timers == 0 && reader.Reads == 1, "no rearm or protected read");
        held.Release.TrySetResult(); await Finish(reading); await Finish(retired);
        Check(changes == 0, "late feed cannot update pending tasks");
    }
    private static async Task OrganizationOutput()
    {
        using var held = new Held(); var reader = new OrganizationReader(); var calls = 0; CommunityNotificationNotice? notice = null;
        using var module = new CommunityNotificationRuntime(reader, () => (Owner, 1), async (value, token) =>
        { calls++; notice = value; await held.Read(true, token); });
        await module.TickAsync(); reader.Next = Feed(1);
        var output = module.TickAsync(); await held.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var retired = module.RetireAsync();
        Check(!retired.IsCompleted && held.Token.IsCancellationRequested && notice?.IsCurrent() == false, "native output is still in flight");
        held.Release.TrySetResult(); await Finish(output); await Finish(retired);
        await module.TickAsync(); Check(calls == 1, "second candidate and later ticks cannot replay after retirement");
    }
    private sealed class Cloud(Held held) : IAchievementRemote
    {
        internal int Reads, Writes;
        public Task<AchievementSnapshot> ReadAchievementsAsync(BridgeAccountContext owner, long generation, CancellationToken token)
        { Reads++; return held.Read(new AchievementSnapshot(1, []), token); }
        public Task<AchievementReceipt> ObserveFirstEntryAsync(BridgeAccountContext owner, long generation, FirstEntryObservation observation, CancellationToken token)
        { Writes++; throw new InvalidOperationException("Retired cloud evidence cannot be reported"); }
    }
    private static async Task Achievements()
    {
        using var temp = new Temp(); using var held = new Held(); var cloud = new Cloud(held); var changes = 0;
        var outbox = new AchievementOutbox(temp.Root);
        using var module = new AchievementRuntime(outbox, cloud, () => (Owner, 1), () => null, _ => changes++, startTimer: false);
        var reading = module.TickAsync(true); await held.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var retired = module.RetireAsync();
        Check(!retired.IsCompleted && held.Token.IsCancellationRequested, "cloud read has not exited");
        module.Wake(); await module.TickAsync(true); Check(cloud.Reads == 1, "no new cloud read");
        held.Release.TrySetResult(); await Finish(reading); await Finish(retired);
        using var reopened = outbox.Open(Owner);
        Check(changes == 0 && cloud.Writes == 0 && reopened.Read() is null, "late receipt cannot grant, publish or retain the storage writer");
    }
    private sealed class OverlayReader : IOverlayCommunityReader
    {
        internal Held? Targets, Content;
        internal int Reads;
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token)
        {
            Reads++; IReadOnlyList<OverlayCommunityTarget> rows = [new("A", "Synthetic", "A")];
            return Targets is null ? Task.FromResult(rows) : Targets.Read(rows, token);
        }
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token)
        {
            Reads++; var value = new InformationOverlayCommunityContent(target.Code, "Synthetic", []);
            return Content is null ? Task.FromResult(value) : Content.Read(value, token);
        }
    }
    private static async Task OverlayRead()
    {
        using var held = new Held(); var reader = new OverlayReader { Targets = held };
        using var module = new OverlayCommunitySource(() => (Owner, 1), reader, false);
        var reading = module.RefreshAsync(); await held.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var retired = module.RetireAsync(); Check(!retired.IsCompleted && held.Token.IsCancellationRequested, "external read is not a driver task");
        held.Release.TrySetResult(); await Finish(reading); await Finish(retired);
        await module.RefreshAsync(); await module.PrepareForDisplayAsync(default);
        Check(reader.Reads == 1 && module.Read() is null, "no stale content or new read after retired completion");
    }
    private static async Task OverlayModules()
    {
        using var held = new Held(); var reader = new OverlayReader { Content = held };
        using var module = new OverlayCommunitySource(() => (Owner, 1), reader, false);
        module.SetModuleMode(() => true);
        var reading = module.RefreshModuleSourcesAsync(Owner, 1, ["A"], default);
        await held.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var retired = module.RetireAsync(); Check(!retired.IsCompleted && held.Token.IsCancellationRequested, "module child read still owns parent work");
        held.Release.TrySetResult(); await Finish(reading); await Finish(retired);
        var before = reader.Reads;
        await module.RefreshModuleSourcesAsync(Owner, 1, ["A"], default);
        Check(before == reader.Reads && module.Read() is null, "retired resource sessions cannot be resurrected");
    }
    private static async Task RoomDriver()
    {
        using var held = new Held();
        using var module = new OverlayRoomRefreshDriver(() => (Owner, 1, true), async (_, token) => await held.Read(true, token));
        await held.Started.Task.WaitAsync(TimeSpan.FromSeconds(3)); module.Dispose();
        Check(!module.Completion.IsCompleted && held.Token.IsCancellationRequested, "cancel cannot acknowledge an unfinished room request");
        held.Release.TrySetResult(); await Finish(module.Completion);
    }
    private sealed class DesktopSink : IDesktopNotificationSink
    {
        internal readonly Held Pending = new();
        internal DesktopNotification? Notice;
        internal int AccountCalls, LocalTests;
        public async ValueTask<bool> TryPresentAsync(DesktopNotification notice, CancellationToken token)
        {
            if (notice.Test) { LocalTests++; return true; }
            AccountCalls++; Notice = notice; return await Pending.Read(true, token);
        }
        public void Clear() { }
        public void Dispose() => Pending.Dispose();
    }
    private static PlayerActivityObservation Observation(int sequence, string state, long generation = 1) => new(generation, "synthetic", "friends", "friends", sequence,
        true, [new("synthetic-peer", "Synthetic", "Pilot-Example", state, false, true)], () => true);
    private static void ConfigureActivity(string root)
    {
        var store = new PlayerActivityPreferencesStore(root);
        store.Save(new(Enabled: true, Scope: 4, Offline: true, StoppedGame: true), store.Read().Revision);
    }
    private static async Task AssertDeviceControls(PlayerActivityRuntime module, string root, long generation, byte[] original)
    {
        var read = await module.DispatchAsync(BridgeEnvelope.Request("playerActivity.read", Guid.NewGuid().ToString("N"), generation,
            new { schemaVersion = 1 }));
        var test = await module.DispatchAsync(BridgeEnvelope.Request("playerActivity.test", Guid.NewGuid().ToString("N"), generation,
            new { schemaVersion = 1 }));
        Check(read.Response.Error is null && test.Response.Error is null && test.Response.Payload.GetProperty("submitted").GetBoolean() &&
            SHA256.HashData(File.ReadAllBytes(Path.Combine(root, "notification.settings.json"))).SequenceEqual(original),
            "account retirement must not dispose or rewrite device-local settings and test reminders");
    }
    private static async Task PlayerActivity(bool retry)
    {
        using var temp = new Temp(); ConfigureActivity(temp.Root); using var sink = new DesktopSink();
        var original = SHA256.HashData(File.ReadAllBytes(Path.Combine(temp.Root, "notification.settings.json")));
        var known = true;
        using var module = new PlayerActivityRuntime(temp.Root, () => 1, sink, () => new(known, true, false, false));
        await module.ObserveAsync(Observation(1, "online"));
        Task observation;
        if (retry) { known = false; observation = module.ObserveAsync(Observation(2, "inGame")); await observation; known = true; }
        else observation = module.ObserveAsync(Observation(2, "inGame"));
        await sink.Pending.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var retired = module.RetireAccountActivityAsync();
        Check(!retired.IsCompleted && sink.Pending.Token.IsCancellationRequested && sink.Notice?.IsCurrent() == false && !module.ShouldObserve(),
            "account output is revoked but its actual callback still needs exit");
        sink.Pending.Release.TrySetResult(); await Finish(observation); await Finish(retired);
        await module.ObserveAsync(Observation(3, "online"));
        await AssertDeviceControls(module, temp.Root, 1, original);
        Check(sink.AccountCalls == 1 && sink.LocalTests == 1, "no account replay; a local test is still local");
    }
    internal static async Task AccountComposition(AccountBridgeRuntime runtime, ScmAccountBridgeHost host, string root, Func<bool> deleted)
    {
        ConfigureActivity(root); using var sink = new DesktopSink();
        var original = SHA256.HashData(File.ReadAllBytes(Path.Combine(root, "notification.settings.json")));
        using var module = new PlayerActivityRuntime(root, () => host.Generation, sink, () => new(true, true, false, false));
        Check(runtime.ConfigurePlayerActivity(module), "actual account composition installs its device observation owner");
        await module.ObserveAsync(Observation(1, "online", host.Generation));
        var output = module.ObserveAsync(Observation(2, "inGame", host.Generation));
        await sink.Pending.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var stopping = runtime.StopAccountForLocalModeAsync(host.Generation);
        Check(!stopping.IsCompleted && !deleted() && sink.Pending.Token.IsCancellationRequested && sink.Notice?.IsCurrent() == false,
            "real account transition waits before removing credentials");
        sink.Pending.Release.TrySetResult(); await Finish(output);
        var result = await stopping.WaitAsync(TimeSpan.FromSeconds(3));
        Check(result is { State: "sessionStopped", BusinessBackgroundStopped: true } && deleted(), "actual background exit precedes real sign-out");
        Check(!runtime.ConfigurePlayerActivity(module), "retired account cannot install new observers");
        await AssertDeviceControls(module, root, host.Generation, original);
    }
}
