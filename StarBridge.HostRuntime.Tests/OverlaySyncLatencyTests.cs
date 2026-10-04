using System.Threading.Channels;
using System.Collections.Concurrent;
using System.Diagnostics;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Support;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;
using StarBridge.Core.Events;
using StarBridge.HostRuntime;
using StarBridge.Core.Profiles;
using StarBridge.Core.Overlay;

internal static class OverlaySyncLatencyTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "latency-fixture");
    internal static async Task Run()
    {
        var failures = new List<string>();
        foreach (var test in new Func<Task>[] { LocalSamplingIsResponsive, LiveJournalSendsWithoutHeartbeat,
            LiveBurstIsSingleFlightAndRevocationWins, OrganizationChangeDoesNotWaitForPoll, OrganizationWaitCancelsOldDemand,
            ReceiverDoesNotWaitFiveSeconds, ReceiverBackoffAndCancellation, ReceiverMembershipChurnPreservesBackoff,
            ReceiverContextFailureCancelsRead, ReceiverLatestProbeClassifiesCancellation, RoomRefreshRequiresVisibleDemand,
            RoomReadCancelsOldScope, NativeCompositionHonorsVisibleDemand, ModuleRoomDemandWithoutFirstFrame,
            ModuleRoomDemandCancelsOldScope, ModuleAutomaticDiscoveryIsBounded, RoomDiscoverySchedule,
            RoomRefreshRecoversFromScopeFailure, LegacyPasswordLoginTests.OverlayLiveChangeAdapter,
            SlowRecoveryStillExpiresAuthority, AnonymousModulesStayLocal })
        {
            try { await test(); Console.WriteLine("PASS sync latency " + test.Method.Name); }
            catch (Exception error) { failures.Add(test.Method.Name + ": " + error.Message); }
        }
        if (failures.Count != 0) throw new InvalidOperationException(string.Join(Environment.NewLine, failures));
    }
    private static Task AnonymousModulesStayLocal()
    {
        var host = new CompositionHost { Account = null, HasRoom = false };
        using var runtime = new AccountBridgeRuntime(host);
        var sources = new OverlayPresetSources(new(OverlaySourceMode.Community, "A", OverlaySceneChoiceStore.Hash(Owner)), modules:
            new Dictionary<OverlaySourceModule, OverlaySourceBinding> { [OverlaySourceModule.Chat] = new(OverlaySourceMode.Room) });
        var result = runtime.ReadOverlayModules(sources);
        Check(result.FailureCode is null && result.Frame is not null, "Anonymous local display does not need a signed-in account.");
        var modules = result.Frame!.ReadModules(DateTimeOffset.UtcNow);
        Check(modules[OverlaySourceModule.Members].Source is { Mode: OverlaySourceMode.Local, Available: true } &&
            modules[OverlaySourceModule.Chat].Source is { Mode: OverlaySourceMode.Room, Available: false } &&
            modules.Values.All(m => m.Snapshot is null) && host.RoomReads == 0 && host.CommunityReads.IsEmpty,
            "Unavailable private binding falls back locally without granting a remote source or making I/O.");
        host.Account = Owner;
        Check(result.Frame.ReadModules(DateTimeOffset.UtcNow).Values.All(m => !m.Source.Available),
            "Signing in immediately invalidates the old anonymous frame, even before generation advances.");
        host.Account = null; host.CurrentGeneration++;
        Check(result.Frame.ReadModules(DateTimeOffset.UtcNow).Values.All(m => !m.Source.Available),
            "A later anonymous session cannot reuse the previous anonymous frame.");
        return Task.CompletedTask;
    }

    private sealed class Clock : TimeProvider
    {
        internal TimeSpan Period;
        internal DateTimeOffset Now = DateTimeOffset.UnixEpoch;
        public override DateTimeOffset GetUtcNow() => Now;
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        { Period = period; return new Timer(); }
        private sealed class Timer : ITimer
        {
            public bool Change(TimeSpan dueTime, TimeSpan period) => true;
            public void Dispose() { }
            public ValueTask DisposeAsync() => ValueTask.CompletedTask;
        }
    }

    private sealed class FailingEventReader : ISharedActivityReader
    {
        internal int Reads;
        public Task<SharedActivityRead> ReadActivityAsync(BridgeAccountContext owner, long generation, string scope, string id, CancellationToken token)
        { Reads++; throw new HttpRequestException("synthetic unavailable feed"); }
    }
    private static async Task ReceiverMembershipChurnPreservesBackoff()
    {
        var clock = new Clock();
        var reader = new FailingEventReader();
        var context = new SharedActivitySubscription(Owner, 1, "organization", "A", new object());
        using var receiver = new SharedActivityReceiver(reader, new FeedSink(), () => context, clock);
        receiver.Start();
        await receiver.TickAsync();
        clock.Now = clock.Now.AddSeconds(1);
        await receiver.TickAsync();
        Check(reader.Reads == 2, "two failures establish a three-second retry delay");
        context = new(null, 1, null, null);
        await receiver.TickAsync();
        context = new(Owner, 1, "organization", "A", new object());
        await receiver.TickAsync();
        Check(reader.Reads == 2, "same-source expiry/rejoin must not accelerate failed feed reads");
        clock.Now = clock.Now.AddSeconds(3);
        await receiver.TickAsync();
        Check(reader.Reads == 3, "same-source retry resumes at its original deadline");
        context = new(Owner, 1, "organization", "B", new object());
        await receiver.TickAsync();
        Check(reader.Reads == 4, "an explicitly different source need not wait for the previous source's failure");
    }

    private static Task LocalSamplingIsResponsive()
    {
        var clock = new Clock();
        using var runtime = new GameLogRuntime(new GameLogSettingsStore(Path.Combine(Path.GetTempPath(), "starbridge-latency-unused")),
            () => (null, 1), () => null, () => new("notRunning"), clock);
        Check(clock.Period <= TimeSpan.FromMilliseconds(500), "actual log timer must observe local changes within 500ms, currently " + clock.Period);
        return Task.CompletedTask;
    }

    private sealed class FeedReader : ISharedActivityReader
    {
        public Task<SharedActivityRead> ReadActivityAsync(BridgeAccountContext owner, long generation, string scope, string id, CancellationToken token) =>
            Task.FromResult(new SharedActivityRead(1, DateTimeOffset.UtcNow, []));
    }
    private sealed class FeedSink : ISharedActivitySink
    {
        public ValueTask<bool> TryPresentActivityAsync(SharedActivityNotice notice, CancellationToken token) => ValueTask.FromResult(true);
    }
    private static Task ReceiverDoesNotWaitFiveSeconds()
    {
        var clock = new Clock();
        using var receiver = new SharedActivityReceiver(new FeedReader(), new FeedSink(), () => (Owner, 1, "organization", "A"), clock);
        receiver.Start();
        Check(clock.Period <= TimeSpan.FromSeconds(1), "event feed fallback is bounded to one second while the current scene is active");
        return Task.CompletedTask;
    }

    private sealed class Remote : IEventSharingRemote, IEventFeedRemote
    {
        internal readonly TaskCompletionSource Delivery = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly EventSharingRemoteSnapshot _saved = new(1, 1, Guid.NewGuid().ToString("N"), DateTimeOffset.UtcNow, true,
            new(new(true, SharedActivityEventTypes.All), []));
        public Task<EventSharingRemoteSnapshot> ReadEventsAsync(BridgeAccountContext owner, long generation, CancellationToken token) => Task.FromResult(_saved);
        public Task<EventSharingRemoteSnapshot> SaveEventsAsync(BridgeAccountContext owner, long generation, long revision, string operation,
            bool enabled, SharedEventPreferences settings, CancellationToken token) => throw new NotSupportedException();
        public Task<EventFeedReceipt> WriteEventFeedAsync(BridgeAccountContext owner, long generation, string action, long revision,
            string? session, long sequence, SharedActivityEvent[] events, CancellationToken token)
        {
            if (events.Any(e => e.Type == "PlayerRespawned")) Delivery.TrySetResult();
            return Task.FromResult(new EventFeedReceipt(session ?? Guid.NewGuid().ToString("N"), sequence));
        }
    }

    private static async Task LiveJournalSendsWithoutHeartbeat()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-sync-latency-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            using var journal = new LocalGameEventJournal(Path.Combine(root, "local-event-log.json"));
            journal.Load();
            var remote = new Remote();
            var input = new PrivacyPublicationInput(Owner, 1, "Fixture", true, null, GameLogSessionSnapshot.Empty);
            using var runtime = new EventSharingRuntime(remote, remote, journal, () => input, () => true);
            await runtime.TickAsync(); // The existing authenticated lease has been accepted.
            var timing = Stopwatch.StartNew();
            journal.Append("life", "PlayerRespawned", "fixture event");
            await remote.Delivery.Task.WaitAsync(TimeSpan.FromSeconds(1));
            Console.WriteLine($"MEASURE journal append -> fake authenticated send callback: {timing.Elapsed.TotalMilliseconds:F1}ms");
        }
        finally
        {
            var resolved = Path.GetFullPath(root);
            Check(Path.GetDirectoryName(resolved) == Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath())) &&
                Path.GetFileName(resolved).StartsWith("starbridge-sync-latency-", StringComparison.Ordinal), "fixture cleanup is scoped");
            Directory.Delete(resolved, true);
        }
    }

    private sealed class BlockingRemote : IEventSharingRemote, IEventFeedRemote
    {
        private readonly EventSharingRemoteSnapshot _saved = new(1, 1, Guid.NewGuid().ToString("N"), DateTimeOffset.UtcNow, true,
            new(new(true, SharedActivityEventTypes.All), []));
        internal readonly Channel<(string Action, SharedActivityEvent[] Events)> Calls = Channel.CreateUnbounded<(string, SharedActivityEvent[])>();
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly ConcurrentQueue<string> Sent = new();
        internal int MaximumConcurrency;
        private int _active, _blocked;
        public Task<EventSharingRemoteSnapshot> ReadEventsAsync(BridgeAccountContext owner, long generation, CancellationToken token) => Task.FromResult(_saved);
        public Task<EventSharingRemoteSnapshot> SaveEventsAsync(BridgeAccountContext owner, long generation, long revision, string operation,
            bool enabled, SharedEventPreferences settings, CancellationToken token) => throw new NotSupportedException();
        public async Task<EventFeedReceipt> WriteEventFeedAsync(BridgeAccountContext owner, long generation, string action, long revision,
            string? session, long sequence, SharedActivityEvent[] events, CancellationToken token)
        {
            var count = Interlocked.Increment(ref _active);
            MaximumConcurrency = Math.Max(MaximumConcurrency, count);
            try
            {
                foreach (var item in events) Sent.Enqueue(item.Id);
                if (events.Length > 0 || action == "stop") Calls.Writer.TryWrite((action, events));
                if (events.Length > 0 && Interlocked.CompareExchange(ref _blocked, 1, 0) == 0)
                    await Release.Task.WaitAsync(token);
                return new(session ?? Guid.NewGuid().ToString("N"), sequence);
            }
            finally { Interlocked.Decrement(ref _active); }
        }
    }

    private static async Task LiveBurstIsSingleFlightAndRevocationWins()
    {
        foreach (var revoke in new[] { false, true })
        {
            var root = Path.Combine(Path.GetTempPath(), "starbridge-sync-burst-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            try
            {
                using var journal = new LocalGameEventJournal(Path.Combine(root, "local-event-log.json"));
                journal.Load();
                var remote = new BlockingRemote();
                var allowed = true;
                var input = new PrivacyPublicationInput(Owner, 1, "Fixture", true, null, GameLogSessionSnapshot.Empty);
                using var runtime = new EventSharingRuntime(remote, remote, journal, () => input, () => allowed);
                await runtime.TickAsync();
                journal.Append("life", "PlayerRespawned", "first fixture event");
                var first = await remote.Calls.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
                Check(first.Events.Length == 1, "the first live event starts transport promptly");
                for (var i = 0; i < 20; i++) journal.Append("life", "PlayerRespawned", "burst fixture " + i);
                if (revoke) allowed = false;
                remote.Release.SetResult();
                var tail = await remote.Calls.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
                if (revoke) Check(tail.Action == "stop" && remote.Sent.Count == 1, "revocation wins over an already queued live wake");
                else Check(tail.Events.Length == 20 && remote.Sent.Count == 21 && remote.Sent.Distinct().Count() == 21,
                    "events arriving during a send enter one trailing batch without loss or duplication");
                Check(remote.MaximumConcurrency == 1, "wake bursts never create a parallel publisher");
            }
            finally
            {
                Check(Path.GetDirectoryName(root) == Path.TrimEndingDirectorySeparator(Path.GetTempPath()) &&
                    Path.GetFileName(root).StartsWith("starbridge-sync-burst-", StringComparison.Ordinal), "fixture cleanup is scoped");
                Directory.Delete(root, true);
            }
        }
    }

    private sealed class CommunityReader : IOverlayCommunityReader, IOverlayCommunityChangeReader
    {
        internal string Presence = "AppOnline";
        internal readonly Channel<OverlayActivityCursor> Changes = Channel.CreateUnbounded<OverlayActivityCursor>();
        internal readonly TaskCompletionSource Updated = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) =>
            Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>([new("A", "Example", "fixture")]);
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token)
        {
            if (Presence == "InGame") Updated.TrySetResult();
            return Task.FromResult(new InformationOverlayCommunityContent("A", "Example", [new("Peer", "Peer", "Member", Presence, "", "", "", false)]));
        }
        public Task<OverlayActivityCursor> WaitForChangesAsync(BridgeAccountContext owner, long generation, OverlayActivityCursor after, CancellationToken token) =>
            Changes.Reader.ReadAsync(token).AsTask();
    }

    private static async Task OrganizationChangeDoesNotWaitForPoll()
    {
        var reader = new CommunityReader();
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader);
        source.ReadForDisplay();
        using (var initial = new CancellationTokenSource(TimeSpan.FromSeconds(1)))
            while (source.Read()?.Members.Single().Presence != "AppOnline") await Task.Delay(5, initial.Token);
        reader.Presence = "InGame";
        var timing = Stopwatch.StartNew();
        reader.Changes.Writer.TryWrite(new(Guid.NewGuid().ToString("N"), 1, true));
        await reader.Updated.Task.WaitAsync(TimeSpan.FromSeconds(1));
        Console.WriteLine($"MEASURE fake organization invalidation -> authenticated snapshot callback: {timing.Elapsed.TotalMilliseconds:F1}ms");
        Check(source.Read()?.Members.Single().Presence == "InGame", "a live authorized change is reflected without the 15-second polling delay");
    }

    private sealed class DemandReader : IOverlayCommunityReader, IOverlayCommunityChangeReader
    {
        internal readonly Channel<(long Generation, TaskCompletionSource Cancelled)> Waits = Channel.CreateUnbounded<(long, TaskCompletionSource)>();
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) =>
            Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>([new("A", "Example", "fixture")]);
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token) =>
            Task.FromResult(new InformationOverlayCommunityContent("A", "Example", []));
        public async Task<OverlayActivityCursor> WaitForChangesAsync(BridgeAccountContext owner, long generation, OverlayActivityCursor after, CancellationToken token)
        {
            var cancelled = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            Waits.Writer.TryWrite((generation, cancelled));
            try { await Task.Delay(Timeout.Infinite, token); return new(); }
            catch (OperationCanceledException) { cancelled.TrySetResult(); throw; }
        }
    }
    private static async Task OrganizationWaitCancelsOldDemand()
    {
        var reader = new DemandReader();
        var generation = 1L;
        using var source = new OverlayCommunitySource(() => (Owner, generation), reader);
        source.ReadForDisplay();
        var old = await reader.Waits.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
        generation = 2;
        await old.Cancelled.Task.WaitAsync(TimeSpan.FromSeconds(1));
        var next = await reader.Waits.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
        Check(next.Generation == 2, "new account demand bypasses old cursor and failure backoff");
        source.SuspendDisplayDemand();
        await next.Cancelled.Task.WaitAsync(TimeSpan.FromSeconds(1));
        await Task.Delay(300);
        Check(!reader.Waits.Reader.TryRead(out _), "closing the display cancels its wait without restarting HTTP");
        source.Dispose();
        await source.Completion.WaitAsync(TimeSpan.FromSeconds(1));
    }

    private sealed class ReceiverReader : ISharedActivityReader
    {
        internal int Reads;
        internal bool Fail, Block, ReaderTimeout;
        internal readonly TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Cancelled = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public async Task<SharedActivityRead> ReadActivityAsync(BridgeAccountContext owner, long generation, string scope, string id, CancellationToken token)
        {
            Reads++;
            if (Fail) throw new IOException("fixture");
            if (ReaderTimeout) throw new OperationCanceledException("synthetic reader timeout");
            if (Block)
            {
                Entered.TrySetResult();
                try { await Task.Delay(Timeout.Infinite, token); }
                catch (OperationCanceledException) { Cancelled.TrySetResult(); throw; }
            }
            return new(1, DateTimeOffset.UtcNow, []);
        }
    }
    private static async Task ReceiverBackoffAndCancellation()
    {
        var clock = new Clock(); var reader = new ReceiverReader { Fail = true };
        (BridgeAccountContext? Owner, long Generation, string? Scope, string? Id) scope = (Owner, 1, null, null);
        using var receiver = new SharedActivityReceiver(reader, new FeedSink(), () => scope, clock);
        receiver.Start();
        await receiver.TickAsync();
        Check(reader.Reads == 0, "inactive display scope never polls event feed");
        scope = (Owner, 1, "organization", "A");
        foreach (var seconds in new[] { 1, 3, 5, 15 })
        {
            var before = reader.Reads;
            await receiver.TickAsync();
            Check(reader.Reads == before + 1, "one retry per backoff boundary");
            clock.Now = clock.Now.AddSeconds(seconds).AddMilliseconds(-1);
            await receiver.TickAsync();
            Check(reader.Reads == before + 1, "rapid timer ticks do not bypass retry backoff");
            clock.Now = clock.Now.AddMilliseconds(1);
        }
        reader.Fail = false; reader.Block = true;
        scope = (Owner, 2, "room", "B");
        var pending = receiver.TickAsync();
        await reader.Entered.Task.WaitAsync(TimeSpan.FromSeconds(1));
        scope = (Owner, 2, null, null);
        await reader.Cancelled.Task.WaitAsync(TimeSpan.FromSeconds(1));
        await pending.WaitAsync(TimeSpan.FromSeconds(1));
    }

    private static async Task ReceiverContextFailureCancelsRead()
    {
        var reader = new ReceiverReader { Block = true };
        var fails = false;
        using var receiver = new SharedActivityReceiver(reader, new FeedSink(),
            () => Volatile.Read(ref fails) ? throw new IOException("synthetic authority probe failure") : (Owner, 1L, "organization", "A"));
        var pending = receiver.TickAsync();
        await reader.Entered.Task.WaitAsync(TimeSpan.FromSeconds(1));
        Volatile.Write(ref fails, true);
        await reader.Cancelled.Task.WaitAsync(TimeSpan.FromSeconds(1));
        await pending.WaitAsync(TimeSpan.FromSeconds(1));
    }

    private static async Task ReceiverLatestProbeClassifiesCancellation()
    {
        var clock = new Clock(); var reader = new ReceiverReader();
        var capture = 0; var stamp = new object();
        using var receiver = new SharedActivityReceiver(reader, new FeedSink(), () =>
        {
            var thisCapture = ++capture;
            return new SharedActivitySubscription(Owner, 1, "organization", "A", stamp)
            { IsAuthorized = () => thisCapture == capture };
        }, clock);
        receiver.Start();
        await receiver.TickAsync();
        reader.ReaderTimeout = true;
        await receiver.TickAsync();
        await receiver.TickAsync();
        Check(reader.Reads == 2, "A current-reader timeout retains backoff even when an equal subscription had an older validation closure.");
        clock.Now = clock.Now.AddSeconds(1);
        await receiver.TickAsync();
        Check(reader.Reads == 3, "Reader timeout retries at the ordinary server-failure boundary.");
    }

    private static async Task RoomRefreshRequiresVisibleDemand()
    {
        var enabled = false;
        var reads = 0;
        var fail = false;
        var waits = Channel.CreateUnbounded<(TimeSpan Delay, TaskCompletionSource Release)>();
        async Task Pause(TimeSpan delay, CancellationToken token)
        {
            var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            waits.Writer.TryWrite((delay, release));
            await release.Task.WaitAsync(token);
        }
        async Task<(TimeSpan Delay, TaskCompletionSource Release)> Next() =>
            await waits.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
        using var driver = new OverlayRoomRefreshDriver(() => (Owner, 1, enabled), (_, _) =>
        { reads++; return fail ? Task.FromException(new IOException("fixture")) : Task.CompletedTask; }, Pause);
        var idle = await Next();
        Check(reads == 0, "a closed overlay performs no background room reads");
        enabled = true; idle.Release.SetResult();
        var active = await Next();
        Check(reads == 1 && active.Delay <= TimeSpan.FromSeconds(1), "room fallback must avoid Flutter's eight-second directory period");
        fail = true;
        foreach (var seconds in new[] { 1, 3, 5, 15 })
        {
            active.Release.SetResult(); active = await Next();
            Check(active.Delay == TimeSpan.FromSeconds(seconds), "room failures keep bounded backoff");
        }
        var beforeClose = reads;
        enabled = false; active.Release.SetResult();
        idle = await Next();
        Check(reads == beforeClose, "closing stops room demand without continuing retries");
        driver.Dispose();
        await driver.Completion.WaitAsync(TimeSpan.FromSeconds(1));
    }

    private static async Task RoomReadCancelsOldScope()
    {
        var enabled = true; var generation = 1L;
        var calls = Channel.CreateUnbounded<TaskCompletionSource>();
        using var driver = new OverlayRoomRefreshDriver(() => (Owner, generation, enabled), async (_, token) =>
        {
            var cancelled = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            calls.Writer.TryWrite(cancelled);
            try { await Task.Delay(Timeout.Infinite, token); }
            catch (OperationCanceledException) { cancelled.TrySetResult(); throw; }
        });
        var first = await calls.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
        generation = 2;
        await first.Task.WaitAsync(TimeSpan.FromSeconds(1));
        var second = await calls.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
        enabled = false;
        await second.Task.WaitAsync(TimeSpan.FromSeconds(1));
        await Task.Delay(300);
        Check(!calls.Reader.TryRead(out _), "closing cancels in-flight room read and performs no further reads");
        driver.Dispose(); await driver.Completion.WaitAsync(TimeSpan.FromSeconds(1));
    }

    private static async Task RoomRefreshRecoversFromScopeFailure()
    {
        var fail = true;
        var called = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var driver = new OverlayRoomRefreshDriver(
            () => Volatile.Read(ref fail) ? throw new ArgumentException("synthetic invalid source context") : (Owner, 1, true),
            (_, _) => { called.TrySetResult(); return Task.CompletedTask; });
        await Task.Delay(300);
        Check(!driver.Completion.IsCompleted && !called.Task.IsCompleted, "invalid context suspends demand instead of terminating the shared driver");
        Volatile.Write(ref fail, false);
        await called.Task.WaitAsync(TimeSpan.FromSeconds(2));
        driver.Dispose();
        await driver.Completion.WaitAsync(TimeSpan.FromSeconds(1));
    }

    private sealed class LiveSink : IInformationOverlayLiveUpdateSink, ISharedActivitySink
    {
        internal bool Visible;
        internal int Refreshes;
        internal InformationOverlayModuleDemand? Demand;
        public bool IsVisible => Volatile.Read(ref Visible);
        public InformationOverlayModuleDemand? ModuleDemand => Volatile.Read(ref Demand);
        public void RequestContentRefresh() => Interlocked.Increment(ref Refreshes);
        public ValueTask<bool> TryPresentActivityAsync(SharedActivityNotice notice, CancellationToken token) => ValueTask.FromResult(true);
    }
    private sealed class CompositionHost : IAccountBridgeHost, IOverlayCommunityReader, IOverlayCommunityChangeReader, ISharedActivityReader
    {
        internal long CurrentGeneration = 1;
        internal BridgeAccountContext? Account = Owner;
        public long Generation => Volatile.Read(ref CurrentGeneration);
        public BridgeAccountContext? CurrentContext => Volatile.Read(ref Account);
        public event Action<long>? AccountChanged { add { } remove { } }
        internal bool HasRoom = true;
        public InformationOverlayRoomContent? CurrentRoomOverlay => HasRoom ? new("fixture-room", "Room", "", 4, "Fixture", [], []) : null;
        internal int RoomReads, EventReads;
        internal bool ServeCommunities;
        internal Func<string, CancellationToken, Task>? PendingCommunityRead;
        internal readonly ConcurrentDictionary<string, int> CommunityReads = new();
        internal readonly Channel<OverlayActivityCursor> CommunityChanges = Channel.CreateUnbounded<OverlayActivityCursor>();
        internal int ChangeWaits, ActiveChangeWaits, MaximumChangeWaits, NoticeVersion;
        public async Task<OverlayActivityCursor> WaitForChangesAsync(BridgeAccountContext owner, long generation,
            OverlayActivityCursor after, CancellationToken token)
        {
            Interlocked.Increment(ref ChangeWaits);
            var count = Interlocked.Increment(ref ActiveChangeWaits);
            MaximumChangeWaits = Math.Max(MaximumChangeWaits, count);
            try { return await CommunityChanges.Reader.ReadAsync(token); }
            finally { Interlocked.Decrement(ref ActiveChangeWaits); }
        }
        internal readonly TaskCompletionSource RoomRead = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal Func<CancellationToken, Task>? PendingRoomRead;
        public async Task<StarBridge.HostRuntime.PartyRooms.RoomDirectoryView> GetPartyRoomsAsync(BridgeAccountContext context, CancellationToken token)
        { Interlocked.Increment(ref RoomReads); RoomRead.TrySetResult(); if (PendingRoomRead is { } pending) await pending(token); return new("fixture-room", DateTimeOffset.UtcNow, []); }
        public Task<SharedActivityRead> ReadActivityAsync(BridgeAccountContext owner, long generation, string scope, string id, CancellationToken token)
        { Interlocked.Increment(ref EventReads); return Task.FromResult(new SharedActivityRead(1, DateTimeOffset.UtcNow, [])); }
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) =>
            ServeCommunities ? Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>([new("A", "Alpha", "A"), new("B", "Beta", "B")]) :
                throw new Exception("room display must not read unrelated organizations");
        public async Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token)
        {
            if (!ServeCommunities) throw new Exception("room display must not read unrelated organizations");
            CommunityReads.AddOrUpdate(target.Code, 1, (_, count) => count + 1);
            if (PendingCommunityRead is { } pending) await pending(target.Code, token);
            return new InformationOverlayCommunityContent(target.Code, target.Name, [])
                { AnnouncementText = "Notice " + target.Code + (NoticeVersion == 0 ? "" : "-" + NoticeVersion) };
        }
        private static Task<T> Unexpected<T>() => throw new Exception("Unexpected account operation");
        public Task<AccountBridgeSessionProjection> GetCurrentAsync(CancellationToken t) => Unexpected<AccountBridgeSessionProjection>();
        public Task<AccountBridgeSessionProjection> LoginAsync(CancellationToken t) => Unexpected<AccountBridgeSessionProjection>();
        public Task CancelLoginAsync() => Task.CompletedTask;
        public Task LogoutAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<bool>();
        public Task<AccountBridgeProfileProjection> GetProfileAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<AccountBridgeProfileProjection>();
        public Task<PersonalProfileDocumentContract> GetPersonalProfileAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<PersonalProfileDocumentContract>();
        public Task<PersonalProfileDocumentContract> UpdatePersonalProfileAsync(BridgeAccountContext c, PersonalProfilePresentationUpdateContract p, CancellationToken t) => Unexpected<PersonalProfileDocumentContract>();
        public Task<AccountBridgeOfficialFleetProjection> GetOfficialFleetAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<AccountBridgeOfficialFleetProjection>();
        public Task<AccountBridgeCompatibilityProjection> GetCompatibilityStateAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<AccountBridgeCompatibilityProjection>();
        public Task<AccountBridgeCompatibilityProjection> LinkLegacyAccountAsync(BridgeAccountContext c, AccountBridgeLegacyCredential? p, CancellationToken t) => Unexpected<AccountBridgeCompatibilityProjection>();
        public Task<AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<AccountBridgeCompatibilityProjection>();
        public Task<AccountBridgeProfileProjection> PatchPreferencesAsync(BridgeAccountContext c, AccountBridgePreferencePatch p, CancellationToken t) => Unexpected<AccountBridgeProfileProjection>();
        public Task<bool> ClearProfileCacheAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<bool>();
        public Task<AccountBridgeIdentityProjection> GetGameIdentityPolicyAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<AccountBridgeIdentityProjection>();
    }
    private static async Task ModuleRoomDemandWithoutFirstFrame()
    {
        var host = new CompositionHost { HasRoom = false };
        var sink = new LiveSink { Visible = true, Demand = new(
            new OverlayPresetSources(new(OverlaySourceMode.Room)),
            [OverlaySourceModule.Members, OverlaySourceModule.Chat]) };
        using var runtime = new AccountBridgeRuntime(host);
        // No legacy selection and no cached room frame: the actual composed
        // room driver must get its demand from visible v2 modules alone.
        runtime.ConfigureOverlayCommunitySource(Path.Combine(Path.GetTempPath(), "starbridge-module-demand-unused"), startDriver: false);
        runtime.ConfigureLiveOverlayUpdates(sink);
        await host.RoomRead.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(host.RoomReads == 1, "two modules share the existing room driver");
        host.HasRoom = true; // Legacy auto would keep reading now; v2 hidden intent must win.
        sink.Demand = new(OverlayPresetSources.Default, []);
        await Task.Delay(1300);
        var reads = host.RoomReads;
        await Task.Delay(1100);
        Check(reads == 1 && host.RoomReads == reads, "hidden modules withdraw room demand");
    }

    internal static async Task ModuleCommunityDemandWithoutFirstFrame()
    {
        // Install the v2 demand before authentication. Otherwise the constructor's
        // legacy idle prewarmer can race the baseline counter capture and be
        // mistaken for a duplicate module read. No roster/page is seeded here.
        var host = new CompositionHost { HasRoom = false, ServeCommunities = true, Account = null };
        var key = OverlaySceneChoiceStore.Hash(Owner);
        var sources = new OverlayPresetSources(new(OverlaySourceMode.Community, "A", key), modules:
            new Dictionary<OverlaySourceModule, OverlaySourceBinding>
            { [OverlaySourceModule.Notice] = new(OverlaySourceMode.Community, "B", key) });
        var sink = new LiveSink { Visible = true, Demand = new(sources,
            [OverlaySourceModule.Members, OverlaySourceModule.Overview, OverlaySourceModule.Notice]) };
        using var runtime = new AccountBridgeRuntime(host);
        runtime.ConfigureOverlayCommunitySource(Path.Combine(Path.GetTempPath(), "starbridge-multi-demand-" + Guid.NewGuid().ToString("N")));
        runtime.ConfigureLiveOverlayUpdates(sink);
        Check(host.CommunityReads.IsEmpty, "Anonymous startup must not warm organization data.");
        Volatile.Write(ref host.Account, Owner);
        var until = DateTime.UtcNow.AddSeconds(3);
        while (DateTime.UtcNow < until && (!host.CommunityReads.ContainsKey("A") || !host.CommunityReads.ContainsKey("B")))
            await Task.Delay(20);
        Check(host.CommunityReads.ContainsKey("A") && host.CommunityReads.ContainsKey("B"),
            "Visible module organizations must load without opening an organization page or seeding its roster.");
        var frame = runtime.ReadOverlayModules(sources, activeModules: sink.Demand.ActiveModules).Frame;
        Check(frame?.ReadModules(DateTimeOffset.UtcNow)[OverlaySourceModule.Notice].Snapshot?.Community?.AnnouncementText == "Notice B",
            "A non-selected organization's notice must come from its own live authorized resource.");
        Check(host.CommunityReads["A"] == 1 && host.CommunityReads["B"] == 1,
            $"Two modules using A must share one organization read. A={host.CommunityReads["A"]}; B={host.CommunityReads["B"]}.");
        host.NoticeVersion = 1;
        var changeAt = Stopwatch.StartNew();
        host.CommunityChanges.Writer.TryWrite(new("module-fixture", 1, true));
        until = DateTime.UtcNow.AddSeconds(3);
        while (DateTime.UtcNow < until && runtime.ReadOverlayModules(sources, activeModules: sink.Demand.ActiveModules)
            .Frame?.ReadModules(DateTimeOffset.UtcNow)[OverlaySourceModule.Notice].Snapshot?.Community?.AnnouncementText != "Notice B-1")
            await Task.Delay(20);
        Check(runtime.ReadOverlayModules(sources, activeModules: sink.Demand.ActiveModules)
            .Frame?.ReadModules(DateTimeOffset.UtcNow)[OverlaySourceModule.Notice].Snapshot?.Community?.AnnouncementText == "Notice B-1",
            "A non-selected module source must react to the shared change feed before the 15-second fallback.");
        Check(host.MaximumChangeWaits == 1, "All visible organizations share one change subscription, never one per module.");
        Console.WriteLine($"MEASURE module invalidation -> refreshed notice: {changeAt.Elapsed.TotalMilliseconds:F1}ms");
        host.NoticeVersion = 2;
        host.CommunityChanges.Writer.TryWrite(new("module-fixture", 2, true));
        until = DateTime.UtcNow.AddSeconds(3);
        while (DateTime.UtcNow < until && runtime.ReadOverlayModules(sources, activeModules: sink.Demand.ActiveModules)
            .Frame?.ReadModules(DateTimeOffset.UtcNow)[OverlaySourceModule.Notice].Snapshot?.Community?.AnnouncementText != "Notice B-2")
            await Task.Delay(20);
        Check(runtime.ReadOverlayModules(sources, activeModules: sink.Demand.ActiveModules)
            .Frame?.ReadModules(DateTimeOffset.UtcNow)[OverlaySourceModule.Notice].Snapshot?.Community?.AnnouncementText == "Notice B-2",
            "Established multi-source subscriptions deliver later changes too, not only their initial cursor refresh.");
        sink.Visible = false;
        var count = host.CommunityReads.Values.Sum();
        await Task.Delay(350);
        Check(host.CommunityReads.Values.Sum() == count, "Closing suppresses further multi-source reads.");
        Check(host.ActiveChangeWaits == 0, "Closing cancels the multi-source change wait too.");
        await ModuleCommunityCloseCancelsRead();
    }

    private static async Task ModuleCommunityCloseCancelsRead()
    {
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var cancelled = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var host = new CompositionHost { HasRoom = false, ServeCommunities = true };
        host.PendingCommunityRead = async (code, token) =>
        {
            if (code != "B") return;
            entered.TrySetResult();
            try { await Task.Delay(Timeout.Infinite, token); }
            catch (OperationCanceledException) { cancelled.TrySetResult(); throw; }
        };
        var sink = new LiveSink { Visible = true, Demand = new(new(new(OverlaySourceMode.Auto), modules:
            new Dictionary<OverlaySourceModule, OverlaySourceBinding>
            { [OverlaySourceModule.Members] = new(OverlaySourceMode.Community, "B", OverlaySceneChoiceStore.Hash(Owner)) }),
            [OverlaySourceModule.Members]) };
        using var runtime = new AccountBridgeRuntime(host);
        runtime.ConfigureOverlayCommunitySource(Path.Combine(Path.GetTempPath(), "starbridge-multi-cancel-" + Guid.NewGuid().ToString("N")));
        runtime.ConfigureLiveOverlayUpdates(sink);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(2));
        var focused = await runtime.DispatchAsync(BridgeEnvelope.Request(OverlayCommunitySource.FocusRequest,
            Guid.NewGuid().ToString(), 1, new { schemaVersion = 1, code = "A" }, Owner), default);
        Check(focused.Response.Error is null, "The unrelated organization focus is accepted.");
        await Task.Delay(350);
        Check(!cancelled.Task.IsCompleted && host.CommunityReads["B"] == 1,
            "Navigating to an unrelated organization must not cancel or restart the explicitly bound B read.");
        sink.Visible = false;
        await cancelled.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.ReadOverlayModules(sink.Demand.Sources!, activeModules: sink.Demand.ActiveModules)
            .Frame?.ReadModules(DateTimeOffset.UtcNow)[OverlaySourceModule.Members].Snapshot is null,
            "Closing cancels pending module content without publishing a fabricated first frame.");
    }

    private static async Task ModuleAutomaticDiscoveryIsBounded()
    {
        var host = new CompositionHost { HasRoom = false };
        var sink = new LiveSink { Visible = true, Demand = new(OverlayPresetSources.Default, [OverlaySourceModule.Members]) };
        using var runtime = new AccountBridgeRuntime(host);
        runtime.ConfigureOverlayCommunitySource(Path.Combine(Path.GetTempPath(), "starbridge-module-demand-unused"), startDriver: false);
        runtime.ConfigureLiveOverlayUpdates(sink);
        await host.RoomRead.Task.WaitAsync(TimeSpan.FromSeconds(2));
        for (var i = 0; i < 5; i++)
        {
            // Repeated workspace sync/slider saves rebuild equal demand objects.
            sink.Demand = new(new(OverlaySourceBinding.Follow), [OverlaySourceModule.Members]);
            await Task.Delay(250);
        }
        Check(host.RoomReads == 1, "automatic mode without a room must not poll the directory every second");
        host.HasRoom = true;
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(2));
        while (host.RoomReads < 2) await Task.Delay(10, deadline.Token);
        Check(host.RoomReads >= 2, "confirmed room membership promotes discovery without waiting fifteen seconds");
    }

    private sealed class RoomScheduleClock : TimeProvider
    {
        internal long Ticks;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override long GetTimestamp() => Ticks;
    }
    private static async Task RoomDiscoverySchedule()
    {
        var clock = new RoomScheduleClock();
        var waits = Channel.CreateUnbounded<(TimeSpan Delay, TaskCompletionSource Release)>();
        async Task Wait(TimeSpan delay, CancellationToken token)
        {
            var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            waits.Writer.TryWrite((delay, release));
            await release.Task.WaitAsync(token);
            clock.Ticks += delay.Ticks;
        }
        async Task<(TimeSpan Delay, TaskCompletionSource Release)> Next() =>
            await waits.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2));
        var reads = 0; var live = false; var visible = true; var fail = false; object intent = new();
        using var driver = new OverlayRoomRefreshDriver(() => (Owner, 1, visible), (_, _) =>
            { reads++; return fail ? Task.FromException(new IOException("synthetic discovery unavailable")) : Task.CompletedTask; }, Wait,
            () => TimeSpan.FromSeconds(live ? 1 : 15), () => intent, clock);
        var tick = await Next();
        for (var i = 0; i < 59; i++)
        {
            Check(reads == 1 && tick.Delay == TimeSpan.FromMilliseconds(250), "discovery checkpoints must not send HTTP");
            tick.Release.SetResult(); tick = await Next();
        }
        Check(reads == 1, "no second discovery before the exact fifteen-second boundary");
        tick.Release.SetResult(); tick = await Next();
        Check(reads == 2, "one shared discovery at fifteen seconds");
        live = true;
        for (var i = 0; i < 4; i++) { tick.Release.SetResult(); tick = await Next(); }
        Check(reads == 3, "active room uses one-second cadence");
        live = false; intent = new();
        tick.Release.SetResult(); tick = await Next();
        Check(reads == 4, "new intent wakes discovery without waiting for its old deadline");
        visible = false;
        tick.Release.SetResult(); tick = await Next();
        tick.Release.SetResult(); tick = await Next();
        Check(reads == 4, "hidden demand sends nothing during discovery wait");
        visible = true;
        tick.Release.SetResult(); tick = await Next();
        Check(reads == 5, "reopen starts an immediate read");
        fail = true;
        for (var i = 0; i < 60; i++) { tick.Release.SetResult(); tick = await Next(); }
        Check(reads == 6, "first discovery failure occurs only at its normal deadline");
        for (var i = 0; i < 59; i++)
        {
            tick.Release.SetResult(); tick = await Next();
            Check(reads == 6, "a failing server must not accelerate discovery retries");
        }
        driver.Dispose(); await driver.Completion.WaitAsync(TimeSpan.FromSeconds(2));
    }

    private static async Task ModuleRoomDemandCancelsOldScope()
    {
        var calls = Channel.CreateUnbounded<TaskCompletionSource>();
        var host = new CompositionHost { HasRoom = false, PendingRoomRead = async token =>
        {
            var cancelled = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            calls.Writer.TryWrite(cancelled);
            try { await Task.Delay(Timeout.Infinite, token); }
            catch (OperationCanceledException) { cancelled.TrySetResult(); throw; }
        } };
        var room = new InformationOverlayModuleDemand(new(new(OverlaySourceMode.Room)), [OverlaySourceModule.Members]);
        var sink = new LiveSink { Visible = true, Demand = room };
        using var runtime = new AccountBridgeRuntime(host);
        runtime.ConfigureOverlayCommunitySource(Path.Combine(Path.GetTempPath(), "starbridge-module-demand-unused"), startDriver: false);
        runtime.ConfigureLiveOverlayUpdates(sink);
        async Task<TaskCompletionSource> Next(string stage)
        {
            try { return await calls.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)); }
            catch (TimeoutException) { throw new InvalidOperationException("No room read after " + stage); }
        }
        async Task Cancelled(TaskCompletionSource pending, string stage)
        {
            try { await pending.Task.WaitAsync(TimeSpan.FromSeconds(2)); }
            catch (TimeoutException) { throw new InvalidOperationException("Room read not cancelled after " + stage); }
        }
        var pending = await Next("open");
        sink.Demand = new(OverlayPresetSources.Default, []);
        await Cancelled(pending, "hide");
        await Task.Delay(200);
        sink.Demand = room;
        pending = await Next("show");
        sink.Demand = new(new OverlayPresetSources(new(OverlaySourceMode.Room), modules:
            new Dictionary<OverlaySourceModule, OverlaySourceBinding>
            { [OverlaySourceModule.Members] = new(OverlaySourceMode.Community, "another-fixture", OverlaySceneChoiceStore.Hash(Owner)) }),
            [OverlaySourceModule.Members]);
        await Cancelled(pending, "source switch");
        await Task.Delay(200);
        sink.Demand = room;
        pending = await Next("switch back");
        sink.Visible = false;
        await Cancelled(pending, "close");
        await Task.Delay(200);
        sink.Visible = true;
        pending = await Next("reopen");
        Interlocked.Increment(ref host.CurrentGeneration);
        await Cancelled(pending, "generation");
        pending = await Next("generation");
        host.Account = null;
        await Cancelled(pending, "logout");
        await Task.Delay(300);
        Check(!calls.Reader.TryRead(out _), "logout stops actual module reads instead of retaining old owner demand");
        // Invalid v2 is distinct from legacy; it may never borrow account auto.
        sink.Demand = new(null, [OverlaySourceModule.Members]);
        host.HasRoom = true;
        host.Account = Owner;
        await Task.Delay(300);
        Check(!calls.Reader.TryRead(out _), "damaged source configuration does not fall back to legacy room polling");
    }
    private static async Task NativeCompositionHonorsVisibleDemand()
    {
        var host = new CompositionHost(); var sink = new LiveSink();
        using var runtime = new AccountBridgeRuntime(host);
        runtime.ConfigureOverlayCommunitySource(Path.Combine(Path.GetTempPath(), "starbridge-latency-unused"));
        runtime.ConfigureLiveOverlayUpdates(sink);
        runtime.ConfigureSharedActivity(sink);
        await Task.Delay(300);
        Check(host.RoomReads == 0 && host.EventReads == 0, "real Host composition performs no room/feed HTTP while Native is closed");
        sink.Visible = true;
        await host.RoomRead.Task.WaitAsync(TimeSpan.FromSeconds(1));
        using (var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(1)))
            while (sink.Refreshes == 0) await Task.Delay(5, deadline.Token);
        Check(host.RoomReads > 0 && sink.Refreshes > 0, "authorized room read signals the Native refresh boundary directly");
        sink.Visible = false;
        await Task.Delay(1100);
        var roomReads = host.RoomReads; var eventReads = host.EventReads;
        await Task.Delay(1100);
        Check(host.RoomReads == roomReads && host.EventReads == eventReads, "closing Native stops both actual composed foreground drivers");
    }

    private static async Task SlowRecoveryStillExpiresAuthority()
    {
        var now = DateTimeOffset.UnixEpoch;
        var reader = new SlowReader();
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, false, () => now);
        await source.RefreshAsync();
        now = now.AddSeconds(35);
        reader.Fail = true; await source.RefreshAsync();
        Check(source.Read() is not null, "t35 transient failure retains the original authority");
        now = now.AddSeconds(1); reader.Fail = false; reader.Pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var recovery = source.RefreshAsync();
        now = DateTimeOffset.UnixEpoch.AddSeconds(40);
        Check(source.Read() is null, "an in-flight retry supplies no authority at the original t40 deadline");
        now = now.AddSeconds(1); reader.Pending.SetResult(new("A", "Example", []));
        await recovery;
        Check(source.Read() is not null, "t41 recovery explains a one-second unavailable sequence without proving the user's root cause");
    }
    private sealed class SlowReader : IOverlayCommunityReader
    {
        internal bool Fail;
        internal TaskCompletionSource<InformationOverlayCommunityContent>? Pending;
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) =>
            Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>([new("A", "Example", "fixture")]);
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token) =>
            Fail ? Task.FromException<InformationOverlayCommunityContent>(new IOException("fixture")) : Pending?.Task ?? Task.FromResult(new InformationOverlayCommunityContent("A", "Example", []));
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
