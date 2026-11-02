using StarBridge.HostRuntime.Lifecycle;
using StarBridge.HostRuntime.Presence;
using StarBridge.Core.Profiles;
using StarBridge.NativeBridge;

internal static class DeferredWorkTimerTests
{
    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
    private static TaskCompletionSource Signal() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static async Task Finish(Task task) => await task.WaitAsync(TimeSpan.FromSeconds(8));
    private static async Task Failed(Task task)
    {
        try { await Finish(task); }
        catch (IOException) { return; }
        throw new InvalidOperationException("Original timer failure was not retained.");
    }
    internal static async Task Run()
    {
        await Case("deferred owner allocates nothing and starts exactly once without resetting cadence", OneTimer);
        await Case("retirement before activation cannot allocate or reopen a timer", BeforeStart);
        await Case("retirement waits for in-progress factory and the original timer exit", FactoryExit);
        await Case("retirement waits for in-progress scheduling without admitting late callbacks", ScheduleExit);
        await Case("asynchronous callbacks retain admission after the native callback returns", CallbackExit);
        await Case("cancelled observers cannot acknowledge drain or reopen queued callbacks", CancelledWaiter);
        await Case("physical disposal failure still waits for admitted callbacks and remains a failure", DisposalFailure);
        await Case("failed timer construction closes admission and cannot be retried", FactoryFailure);
        await Case("rejected scheduling closes and disposes the sole physical timer", ChangeFailure);
        await Case("unexpected callback faults are observed and retained in retirement", CallbackFailure);
        await Case("real System timer retirement waits for asynchronous callback completion", SystemExit);
        await Case("failed gameplay recovery timer construction retires the already-started sampler", GameplayConstructorFailure);
        await Case("failed account graph construction retires earlier module timers", AccountConstructorFailure);
    }
    private static async Task Case(string name, Func<Task> run)
    { await run(); Console.WriteLine("PASS deferred work timer: " + name); }

    private static async Task AccountConstructorFailure()
    {
        foreach (var failurePoint in new[] { 2, 3 })
        {
        using var fixture = new LocalAccountStopTests.Fixture();
        var clock = new Clock { FailOnCreate = failurePoint };
        try
        {
            try
            {
                using var runtime = new StarBridge.HostRuntime.AccountBridgeRuntime(fixture.Host,
                    gameLog: new GameLogSettingsStore(fixture.Root),
                    gameplayTime: new GameplayTimeStore(fixture.Root), backgroundTime: clock);
                throw new InvalidOperationException("Expected account graph construction failure.");
            }
            catch (IOException error) when (error.Message == "Synthetic factory failure.") { }
            Check(clock.Creates == failurePoint && clock.Created.Count == failurePoint - 1,
                "Real account graph did not reach the failing timer factory.");
            Check(clock.Created.All(timer => timer.Disposed), "Failed account graph left an earlier module timer alive.");
        }
        finally
        {
            // The red test also owns cleanup of its synthetic timer.
            foreach (var timer in clock.Created.Where(timer => !timer.Disposed)) await timer.DisposeAsync();
        }
        }
    }

    private sealed class Clock : TimeProvider
    {
        internal int Creates;
        internal int FailOnCreate;
        internal bool HoldFactory, FailFactory;
        internal readonly TaskCompletionSource FactoryEntered = Signal(), ReleaseFactory = Signal();
        internal readonly TaskCompletionSource TimerCreated = Signal();
        internal Timer? Original;
        internal readonly List<Timer> Created = [];
        internal bool HoldExit, FailExit, RejectChange, HoldChange;
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        {
            Interlocked.Increment(ref Creates);
            Check(dueTime == Timeout.InfiniteTimeSpan && period == Timeout.InfiniteTimeSpan,
                "Physical timer is not scheduled before ownership is installed.");
            FactoryEntered.TrySetResult();
            if (HoldFactory && !ReleaseFactory.Task.Wait(TimeSpan.FromSeconds(8))) throw new TimeoutException();
            if (FailFactory || Creates == FailOnCreate) throw new IOException("Synthetic factory failure.");
            Original = new(callback, state) { HoldExit = HoldExit, FailExit = FailExit, RejectChange = RejectChange, HoldChange = HoldChange };
            Created.Add(Original);
            TimerCreated.TrySetResult();
            return Original;
        }
        internal sealed class Timer(TimerCallback callback, object? state) : ITimer
        {
            internal bool HoldExit, FailExit, RejectChange, Disposed, HoldChange;
            internal int Changes, Disposals;
            internal TimeSpan Due, Period;
            internal readonly TaskCompletionSource ExitEntered = Signal(), ReleaseExit = Signal();
            internal readonly TaskCompletionSource ChangeEntered = Signal(), ReleaseChange = Signal();
            internal void Queued() => callback(state);
            public bool Change(TimeSpan dueTime, TimeSpan period)
            {
                Changes++; Due = dueTime; Period = period; ChangeEntered.TrySetResult();
                if (HoldChange && !ReleaseChange.Task.Wait(TimeSpan.FromSeconds(8))) throw new TimeoutException();
                return !Disposed && !RejectChange;
            }
            public void Dispose() => throw new InvalidOperationException("Physical timer needs asynchronous disposal.");
            public async ValueTask DisposeAsync()
            {
                Disposals++; Disposed = true; ExitEntered.TrySetResult();
                if (HoldExit) await ReleaseExit.Task;
                if (FailExit) throw new IOException("Synthetic disposal failure.");
            }
        }
    }
    private static DeferredWorkTimer Create(Clock clock, Func<Task>? callback = null) =>
        new(clock, callback ?? (() => Task.CompletedTask), TimeSpan.FromSeconds(3), TimeSpan.FromSeconds(7));
    private static async Task OneTimer()
    {
        var clock = new Clock(); var timer = Create(clock);
        Check(clock.Creates == 0 && !timer.Change(TimeSpan.Zero, TimeSpan.Zero), "Deferred changes cannot create work.");
        Check(timer.Start() && timer.Start(), "Repeated start is idempotent.");
        Check(clock.Creates == 1 && clock.Original!.Changes == 1 &&
            clock.Original.Due == TimeSpan.FromSeconds(3) && clock.Original.Period == TimeSpan.FromSeconds(7),
            "Exactly one original timer and unchanged cadence.");
        await Finish(timer.RetireAsync());
        Check(clock.Original!.Disposals == 1 && !timer.Start(), "Original timer disposed once, never reopened.");
    }
    private static async Task BeforeStart()
    {
        var clock = new Clock(); var timer = Create(clock);
        timer.Dispose(); await timer.DisposeAsync();
        Check(!timer.Start() && !timer.Change(TimeSpan.Zero, TimeSpan.Zero) && clock.Creates == 0,
            "Retired deferred owner never constructs a timer.");
    }
    private static async Task FactoryExit()
    {
        var clock = new Clock { HoldFactory = true, HoldExit = true }; var timer = Create(clock);
        var start = Task.Run(timer.Start);
        try
        {
            await Finish(clock.FactoryEntered.Task);
            Check(!timer.Start() && clock.Creates == 1, "Concurrent start cannot allocate a second timer.");
            var exit = timer.RetireAsync();
            Check(!exit.IsCompleted && !timer.Start(), "Closed admission does not acknowledge a blocked factory.");
            clock.ReleaseFactory.TrySetResult(); await Finish(start);
            Check(!start.Result, "Constructed timer cannot be activated after retirement.");
            await Finish(clock.Original!.ExitEntered.Task);
            Check(!exit.IsCompleted && clock.Original.Changes == 0, "Original physical exit is still required.");
            clock.Original.ReleaseExit.TrySetResult(); await Finish(exit);
            Check(clock.Creates == 1 && clock.Original.Disposals == 1, "One original owner.");
        }
        finally { clock.ReleaseFactory.TrySetResult(); clock.Original?.ReleaseExit.TrySetResult(); await Finish(start); }
    }
    private static async Task ScheduleExit()
    {
        var clock = new Clock { HoldChange = true }; var calls = 0;
        var timer = Create(clock, () => { calls++; return Task.CompletedTask; });
        var start = Task.Run(timer.Start);
        try
        {
            await Finish(clock.FactoryEntered.Task);
            await Finish(clock.TimerCreated.Task);
            var original = clock.Original!;
            await Finish(original.ChangeEntered.Task); var exit = timer.RetireAsync();
            Check(!exit.IsCompleted && !timer.Start() && original.Disposals == 0,
                "Retirement closes immediately but waits for original scheduling exit.");
            original.Queued(); Check(calls == 0, "Late scheduling cannot admit a callback after retirement.");
            original.ReleaseChange.TrySetResult(); await Finish(start); await Finish(exit);
            Check(!start.Result && clock.Creates == 1 && original.Disposals == 1,
                "Scheduling cannot acknowledge activation or allocate a replacement after closure.");
        }
        finally { clock.Original?.ReleaseChange.TrySetResult(); await Finish(start); }
    }
    private static async Task CallbackExit()
    {
        var entered = Signal(); var release = Signal(); var calls = 0; var clock = new Clock();
        var timer = Create(clock, async () => { calls++; entered.TrySetResult(); await release.Task; });
        timer.Start(); clock.Original!.Queued(); await Finish(entered.Task);
        var exit = timer.RetireAsync();
        try
        {
            await Finish(clock.Original.ExitEntered.Task);
            Check(!exit.IsCompleted, "Native callback return and timer disposal cannot replace asynchronous exit.");
            clock.Original.Queued(); Check(calls == 1, "Old queued callback cannot enter after closure.");
        }
        finally { release.TrySetResult(); await Finish(exit); }
    }
    private static async Task CancelledWaiter()
    {
        var clock = new Clock { HoldExit = true }; var calls = 0;
        var timer = Create(clock, () => { calls++; return Task.CompletedTask; }); timer.Start();
        var exit = timer.RetireAsync(); using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        try { await exit.WaitAsync(cancellation.Token); throw new InvalidOperationException("Observer should cancel."); }
        catch (OperationCanceledException) { }
        Check(!exit.IsCompleted && !timer.Start(), "Observer cancellation is not physical drain.");
        clock.Original!.Queued(); Check(calls == 0, "Cancellation cannot reopen old callbacks.");
        clock.Original.ReleaseExit.TrySetResult(); await Finish(exit);
        Check(ReferenceEquals(exit, timer.RetireAsync()) && clock.Original.Disposals == 1, "Same retirement receipt.");
    }
    private static async Task DisposalFailure()
    {
        var clock = new Clock { FailExit = true }; var release = Signal();
        var timer = Create(clock, () => release.Task); timer.Start(); clock.Original!.Queued();
        var exit = timer.RetireAsync();
        Check(!exit.IsCompleted, "Disposal failure does not abandon an admitted callback.");
        release.TrySetResult(); await Failed(exit); await Failed(timer.RetireAsync());
        Check(!timer.Start() && clock.Original.Disposals == 1, "Failure cannot retry or reopen the timer.");
    }
    private static async Task FactoryFailure()
    {
        var clock = new Clock { FailFactory = true }; var timer = Create(clock);
        try { timer.Start(); throw new InvalidOperationException("Factory should fail."); } catch (IOException) { }
        await Failed(timer.RetireAsync());
        Check(!timer.Start() && clock.Creates == 1, "Failed original construction cannot retry.");
    }
    private static async Task ChangeFailure()
    {
        var clock = new Clock { RejectChange = true }; var timer = Create(clock);
        try { timer.Start(); throw new IOException("Scheduling should fail."); } catch (InvalidOperationException) { }
        try { await Finish(timer.RetireAsync()); throw new IOException("Receipt should fail."); } catch (InvalidOperationException) { }
        Check(!timer.Start() && clock.Creates == 1 && clock.Original!.Disposals == 1, "Unscheduled timer retained and disposed once.");
    }
    private static async Task CallbackFailure()
    {
        var clock = new Clock(); var timer = Create(clock, () => Task.FromException(new IOException("Synthetic callback failure.")));
        timer.Start(); clock.Original!.Queued(); await Failed(timer.RetireAsync());
        Check(!timer.Start() && clock.Original.Disposals == 1, "Faulted callbacks close the original timer.");
    }
    private static async Task SystemExit()
    {
        var entered = Signal(); var release = Signal();
        var timer = new DeferredWorkTimer(TimeProvider.System, async () => { entered.TrySetResult(); await release.Task; },
            TimeSpan.Zero, Timeout.InfiniteTimeSpan);
        timer.Start();
        try
        {
            await Finish(entered.Task); var exit = timer.RetireAsync();
            Check(!exit.IsCompleted && !timer.Start(), "Real timer still owes asynchronous callback exit.");
            release.TrySetResult(); await Finish(exit);
        }
        finally { release.TrySetResult(); await Finish(timer.RetireAsync()); }
    }

    private sealed class NoResetTraffic : IGameplayTimeResetRemote
    {
        internal int Requests;
        public Task<GameplayTimeResetState> ReadAsync(BridgeAccountContext owner, CancellationToken cancellation)
        { Requests++; throw new InvalidOperationException("Synthetic inactive owner must not send reset traffic."); }
        public Task<GameplayTimeResetResult> ResetAsync(BridgeAccountContext owner, GameplayTimeResetRequest request,
            CancellationToken cancellation)
        { Requests++; throw new InvalidOperationException("Synthetic inactive owner must not send reset traffic."); }
    }
    private static async Task GameplayConstructorFailure()
    {
        var clock = new Clock { FailOnCreate = 2 }; var remote = new NoResetTraffic();
        var root = Path.Combine(Path.GetTempPath(), "starbridge-deferred-timer", Guid.NewGuid().ToString("N"));
        try
        {
            using var runtime = new GameplayTimeRuntime(new(root), () => (null, 1), time: clock, resetRemote: remote);
            throw new InvalidOperationException("Second original timer should fail to construct.");
        }
        catch (IOException) { }
        await Finish(clock.Original!.ExitEntered.Task);
        Check(clock.Creates == 2 && clock.Original.Disposals == 1 && remote.Requests == 0,
            "Failed owner retires its first physical sampler without network or replacement.");
    }
}
