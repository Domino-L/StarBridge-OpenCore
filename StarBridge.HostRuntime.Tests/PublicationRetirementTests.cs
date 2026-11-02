using StarBridge.Core.Events;
using StarBridge.Core.Friends;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class PublicationRetirementTests
{
    private static readonly PrivacyPublicationInput Input = new(new("test", "legacy", "retirement-fixture"),
        1, "Synthetic_Handle", true, null, GameLogSessionSnapshot.Empty);
    private static TaskCompletionSource Signal() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }

    internal static async Task Run()
    {
        await FriendManual(); Console.WriteLine("PASS friend publisher waits for actual manual callback exit");
        await EventManual(); Console.WriteLine("PASS event publisher waits for actual manual callback exit");
        await PrivacyManual(); Console.WriteLine("PASS privacy publisher waits for actual manual callback exit");
        foreach (var kind in new[] { "friend", "event", "privacy" })
        {
            await TimerExit(kind, fail: false); Console.WriteLine($"PASS {kind} publisher waits for physical timer disposal");
            await TimerExit(kind, fail: true); Console.WriteLine($"PASS {kind} publisher retains the original timer exit failure");
        }
        await EventLive(); Console.WriteLine("PASS event publisher drains real live journal wake and preserves borrowed journal");
    }

    private static async Task HeldExit(Func<Task> retire, Task callback, TaskCompletionSource entered,
        TaskCompletionSource release, Func<Task> staleWake, CancellationToken transport)
    {
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        Task? reentered = null;
        using var registration = transport.Register(() => {
            var nested = Task.Run(() => { reentered = retire(); });
            Check(nested.Wait(TimeSpan.FromSeconds(2)), "Publisher cancellation holds its exit reservation lock.");
        });
        try
        {
            var exit = retire();
            Check(!exit.IsCompleted, "Publisher cleanup acknowledged before the original cancellation-ignoring callback exited.");
            Check(ReferenceEquals(exit, retire()), "Publisher cleanup did not retain its original exit receipt.");
            Check(transport.IsCancellationRequested && ReferenceEquals(exit, reentered),
                "Publisher cancellation callback did not observe the same original exit.");
            using var observer = new CancellationTokenSource(); observer.Cancel();
            try { await exit.WaitAsync(observer.Token); throw new InvalidOperationException("Expected observer cancellation."); }
            catch (OperationCanceledException) { }
            Check(!exit.IsCompleted, "Cancelling the observer changed physical callback exit.");
            await staleWake();
            release.TrySetResult();
            await callback.WaitAsync(TimeSpan.FromSeconds(3));
            await exit.WaitAsync(TimeSpan.FromSeconds(3));
            await staleWake();
        }
        finally { release.TrySetResult(); await callback.WaitAsync(TimeSpan.FromSeconds(3)); }
    }
    private static async Task FriendManual()
    {
        var remote = new HeldRemote();
        using var runtime = new FriendSharingRuntime(remote, () => Input, () => true,
            () => PlayerPresenceVisibilityMode.Online, false);
        var callback = runtime.TickAsync();
        await HeldExit(runtime.RetireAsync, callback, remote.Entered, remote.Release, runtime.TickAsync, remote.Token);
        Check(remote.Reads == 1 && remote.Writes == 0, "Retired friend reader admitted another read or positive publication.");
    }
    private static async Task EventManual()
    {
        using var fixture = new Fixture();
        using var journal = new LocalGameEventJournal(Path.Combine(fixture.Root, "local-event-log.json")); journal.Load();
        var remote = new HeldRemote();
        using var runtime = new EventSharingRuntime(remote, remote, journal, () => Input, () => true, false);
        var callback = runtime.TickAsync();
        await HeldExit(runtime.RetireAsync, callback, remote.Entered, remote.Release, runtime.TickAsync, remote.Token);
        Check(remote.Reads == 1 && remote.Writes == 0, "Retired event reader admitted another read or feed.");
        journal.Append("life", "PlayerDied", "synthetic after publisher exit");
        await journal.FlushAsync();
    }
    private static async Task PrivacyManual()
    {
        using var fixture = new Fixture();
        var store = new LocalPrivacyStore(fixture.Root);
        store.Save(Input.Owner, 0, Guid.NewGuid().ToString("N"), LocalPrivacySettings.EditorDefaults with {
            PublicationEnabled = true }, () => true);
        var entered = Signal(); var release = Signal(); var writes = 0;
        CancellationToken transport = default;
        using var runtime = new PrivacyPublication(store, () => Input, async (_, _, token) => {
            transport = token;
            Interlocked.Increment(ref writes); entered.TrySetResult(); await release.Task;
        }, false);
        var callback = runtime.ApplyAsync(Input.Owner, Input.Generation, 1, default);
        await HeldExit(runtime.RetireAsync, callback, entered, release, runtime.TickAsync, transport);
        Check(writes == 1, "Retired privacy publisher admitted another send.");
    }
    private sealed class HeldRemote : IFriendSharingRemote, IEventSharingRemote, IEventFeedRemote
    {
        internal readonly TaskCompletionSource Entered = Signal(), Release = Signal();
        internal int Reads, Writes;
        internal CancellationToken Token;
        internal bool HoldRead = true, HoldAppend;
        public async Task<FriendSharingRemoteSnapshot> ReadFriendSharingAsync(BridgeAccountContext o, long g, CancellationToken t)
        { Token = t; Interlocked.Increment(ref Reads); if (HoldRead) { Entered.TrySetResult(); await Release.Task; }
          return new(1, 1, Guid.NewGuid().ToString("N"), DateTimeOffset.UtcNow, FriendSharedFields.All); }
        public Task<FriendSharingRemoteSnapshot> SaveFriendSharingAsync(BridgeAccountContext o, long g, long r,
            string op, FriendSharedFields f, CancellationToken t) => throw new InvalidOperationException("Unexpected save.");
        public Task<string> WriteFriendLiveAsync(PrivacyPublicationInput input, string action, long r, string? session,
            long sequence, FriendSharingSource? source, CancellationToken t)
        { Interlocked.Increment(ref Writes); return Task.FromResult(session ?? "synthetic-session"); }
        public async Task<EventSharingRemoteSnapshot> ReadEventsAsync(BridgeAccountContext o, long g, CancellationToken t)
        { Token = t; Interlocked.Increment(ref Reads); if (HoldRead) { Entered.TrySetResult(); await Release.Task; }
          return new(1, 1, Guid.NewGuid().ToString("N"), DateTimeOffset.UtcNow, true, new(new(true, SharedActivityEventTypes.All), [])); }
        public Task<EventSharingRemoteSnapshot> SaveEventsAsync(BridgeAccountContext o, long g, long r, string op,
            bool enabled, SharedEventPreferences preferences, CancellationToken t) => throw new InvalidOperationException("Unexpected save.");
        public async Task<EventFeedReceipt> WriteEventFeedAsync(BridgeAccountContext o, long g, string action, long r,
            string? session, long sequence, SharedActivityEvent[] events, CancellationToken t)
        { Interlocked.Increment(ref Writes);
          if (action == "append" && HoldAppend) { Entered.TrySetResult(); await Release.Task; }
          return new EventFeedReceipt(session ?? "synthetic-session", sequence); }
    }
    private static async Task TimerExit(string kind, bool fail)
    {
        using var fixture = new Fixture();
        using var journal = new LocalGameEventJournal(Path.Combine(fixture.Root, "local-event-log.json")); journal.Load();
        var clock = new Clock { FailExit = fail };
        var remote = new HeldRemote();
        var samples = 0;
        PrivacyPublicationInput? Current() { Interlocked.Increment(ref samples); return Input; }
        IDisposable runtime;
        Func<Task> retire, tick; Func<bool> start;
        switch (kind)
        {
            case "friend":
                var friend = new FriendSharingRuntime(remote, Current, () => true,
                    () => PlayerPresenceVisibilityMode.Online, false, clock);
                runtime = friend; retire = friend.RetireAsync; tick = friend.TickAsync; start = friend.StartDeferredWork; break;
            case "event":
                var events = new EventSharingRuntime(remote, remote, journal, Current, () => true, false, clock);
                runtime = events; retire = events.RetireAsync; tick = events.TickAsync; start = events.StartDeferredWork; break;
            default:
                var store = new LocalPrivacyStore(fixture.Root);
                store.Save(Input.Owner, 0, Guid.NewGuid().ToString("N"), LocalPrivacySettings.EditorDefaults with {
                    PublicationEnabled = true }, () => true);
                store.SetPublicationConsent(Input.Owner, 1, true, () => true);
                var privacy = new PrivacyPublication(store, Current, async (_, _, _) => {
                    Interlocked.Increment(ref remote.Writes); remote.Entered.TrySetResult(); await remote.Release.Task;
                }, false, timeProvider: clock);
                runtime = privacy; retire = privacy.RetireAsync; tick = privacy.TickAsync; start = privacy.StartDeferredWork; break;
        }
        using (runtime)
        {
            Check(start() && clock.Original is not null, "Publisher did not own its physical timer.");
            var timer = clock.Original!;
            try
            {
                timer.Fire();
                await remote.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
                var exit = retire();
                await timer.ExitEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
                Check(!exit.IsCompleted && ReferenceEquals(exit, retire()), "Physical timer exit was skipped or replaced.");
                Check(!start(), "Retired publisher can restart its timer.");
                var samplesBefore = samples; var readsBefore = remote.Reads; var writesBefore = remote.Writes;
                timer.Fire(); await tick();
                Check(samples == samplesBefore && remote.Reads == readsBefore && remote.Writes == writesBefore,
                    "Queued stale wake reached retired business.");
                timer.Release.TrySetResult();
                Check(!exit.IsCompleted, "Physical disposal skipped the original running timer callback.");
                remote.Release.TrySetResult();
                try
                {
                    await exit.WaitAsync(TimeSpan.FromSeconds(3));
                    Check(!fail, "Timer disposal failure became a successful receipt.");
                }
                catch (IOException error) when (fail && error.Message == "Synthetic timer disposal failure.") { }
                Check(ReferenceEquals(exit, retire()) && timer.Disposals == 1, "Physical timer was disposed twice.");
            }
            finally { timer.Release.TrySetResult(); remote.Release.TrySetResult(); }
        }
    }
    private static async Task EventLive()
    {
        using var fixture = new Fixture();
        using var journal = new LocalGameEventJournal(Path.Combine(fixture.Root, "local-event-log.json")); journal.Load();
        var remote = new HeldRemote { HoldRead = false };
        var clock = new Clock();
        using var runtime = new EventSharingRuntime(remote, remote, journal, () => Input, () => true, false, clock);
        Check(runtime.StartDeferredWork(), "Live event wake was not attached to the original journal.");
        await runtime.TickAsync();
        remote.HoldAppend = true;
        journal.Append("life", "PlayerDied", "synthetic live retirement event");
        await remote.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var exit = runtime.RetireAsync();
        try
        {
            var timer = clock.Original!;
            await timer.ExitEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
            timer.Release.TrySetResult();
            Check(!exit.IsCompleted, "Timer exit acknowledged a still-running live journal send.");
            var writes = remote.Writes;
            journal.Append("life", "PlayerRespawned", "synthetic detached retirement event");
            remote.Release.TrySetResult();
            await exit.WaitAsync(TimeSpan.FromSeconds(3));
            await runtime.TickAsync(); timer.Fire();
            journal.Append("life", "PlayerDowned", "synthetic borrowed journal after exit");
            await journal.FlushAsync();
            Check(remote.Writes == writes && journal.IsWritable, "Retired live owner sent again or disposed the borrowed journal.");
        }
        finally { remote.Release.TrySetResult(); clock.Original!.Release.TrySetResult(); }
    }
    internal sealed class Clock : TimeProvider
    {
        internal Timer? Original;
        internal readonly List<Timer> Created = [];
        internal bool FailExit;
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        { Original = new(callback, state, FailExit); Created.Add(Original); return Original; }
        internal sealed class Timer(TimerCallback callback, object? state, bool fail) : ITimer
        {
            internal readonly TaskCompletionSource ExitEntered = Signal(), Release = Signal();
            internal int Disposals;
            internal void Fire() => callback(state); // Deliver even after disposal to model an already queued callback.
            public bool Change(TimeSpan dueTime, TimeSpan period) => true;
            public async ValueTask DisposeAsync()
            {
                Interlocked.Increment(ref Disposals); ExitEntered.TrySetResult(); await Release.Task;
                if (fail) throw new IOException("Synthetic timer disposal failure.");
            }
            public void Dispose() => throw new InvalidOperationException("Original physical timer must be retired asynchronously.");
        }
    }
    private sealed class Fixture : IDisposable
    {
        internal string Root { get; } = Directory.CreateTempSubdirectory("publication-retirement-").FullName;
        public void Dispose() => Directory.Delete(Root, true);
    }
}
