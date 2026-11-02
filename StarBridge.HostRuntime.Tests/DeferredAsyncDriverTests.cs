using StarBridge.HostRuntime.Lifecycle;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static class DeferredAsyncDriverTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "deferred-driver-fixture");
    private static TaskCompletionSource Signal() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static async Task Finish(Task task) => await task.WaitAsync(TimeSpan.FromSeconds(8));
    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
    private static async Task Case(string name, Func<Task> run)
    { await run(); Console.WriteLine("PASS deferred async driver: " + name); }

    internal static async Task Run()
    {
        await Case("dormant construction and one original start", OneStart);
        await Case("closed dormant owner never starts", CloseBeforeStart);
        await Case("retirement reserves slow synchronous factory completion", FactoryExit);
        await Case("cancelled observer cannot acknowledge physical exit", CancelledObserver);
        await Case("cancellation callback fault does not skip physical work drain", StopFailure);
        await Case("original work fault cannot restart and remains a retirement failure", WorkFailure);
        await Case("multiple original work faults and stop fault all remain in the receipt", MultipleFailures);
        await Case("room driver is dormant until activation and drains a late original read", RoomDriver);
        await Case("retired dormant room driver cannot activate", DormantRoomExit);
        await Case("community source starts both original siblings once and drains both", CommunityDrivers);
        await Case("retired dormant community source cannot activate", DormantCommunityExit);
        await Case("failed community sibling immediately seals startup but awaits its late sibling", CommunitySiblingFailure);
    }

    private static async Task OneStart()
    {
        var release = Signal(); var runs = 0; var stops = 0;
        var driver = new DeferredAsyncDriver(() => { runs++; return release.Task; }, () => stops++);
        Check(runs == 0 && !driver.IsStarted && driver.Completion.IsCompletedSuccessfully, "Construction must be dormant.");
        Check(driver.Start() && driver.Start() && runs == 1, "Repeated activation must not create another loop.");
        var exit = driver.RetireAsync();
        Check(ReferenceEquals(exit, driver.RetireAsync()) && ReferenceEquals(exit, driver.Completion) &&
            !exit.IsCompleted && stops == 1 && !driver.Start(), "Retirement seals one original receipt.");
        release.TrySetResult(); await Finish(exit);
    }

    private static async Task CloseBeforeStart()
    {
        var runs = 0;
        var driver = new DeferredAsyncDriver(() => { runs++; return Task.CompletedTask; }, () => { });
        await Finish(driver.RetireAsync());
        Check(!driver.Start() && !driver.IsStarted && runs == 0, "Closed dormant owner cannot allocate work.");
    }

    private static async Task FactoryExit()
    {
        var entered = Signal(); var releasePrefix = Signal(); var releaseWork = Signal(); var stopped = Signal();
        var driver = new DeferredAsyncDriver(() =>
        {
            entered.TrySetResult();
            if (!releasePrefix.Task.Wait(TimeSpan.FromSeconds(8))) throw new TimeoutException();
            return releaseWork.Task;
        }, () => stopped.TrySetResult());
        var start = Task.Run(driver.Start);
        try
        {
            await Finish(entered.Task);
            // If user code ran under the lifecycle lock this reservation could
            // not return until releasePrefix, defeating immediate close.
            var exit = await Task.Factory.StartNew(driver.RetireAsync, CancellationToken.None,
                TaskCreationOptions.DenyChildAttach, TaskScheduler.Default).WaitAsync(TimeSpan.FromSeconds(2));
            await Finish(stopped.Task);
            Check(!exit.IsCompleted && !driver.Start(), "Slow prefix still owns physical exit after admission closes.");
            releasePrefix.TrySetResult();
            Check(!await start.WaitAsync(TimeSpan.FromSeconds(8)) && !exit.IsCompleted,
                "Returning from a closed factory does not grant activation or physical exit.");
            releaseWork.TrySetResult(); await Finish(exit);
        }
        finally { releasePrefix.TrySetResult(); releaseWork.TrySetResult(); await Finish(driver.RetireAsync()); }
    }

    private static async Task CancelledObserver()
    {
        var release = Signal(); var driver = new DeferredAsyncDriver(() => release.Task, () => { });
        driver.Start(); var exit = driver.RetireAsync();
        using var observer = new CancellationTokenSource(); observer.Cancel();
        try { await exit.WaitAsync(observer.Token); throw new InvalidOperationException("Expected observer cancellation."); }
        catch (OperationCanceledException) { }
        Check(!exit.IsCompleted && ReferenceEquals(exit, driver.RetireAsync()) && !driver.Start(), "Observer does not own the loop.");
        release.TrySetResult(); await Finish(exit);
    }

    private static async Task StopFailure()
    {
        var release = Signal(); var stops = 0; var error = new IOException("Synthetic stop fault.");
        var driver = new DeferredAsyncDriver(() => release.Task, () => { stops++; throw error; });
        driver.Start(); var exit = driver.RetireAsync();
        Check(!exit.IsCompleted && stops == 1, "Failed cancellation must still await the original work.");
        release.TrySetResult();
        try { await Finish(exit); throw new InvalidOperationException("Expected original stop failure."); }
        catch (IOException actual) when (ReferenceEquals(error, actual)) { }
        Check(ReferenceEquals(exit, driver.RetireAsync()) && stops == 1 && !driver.Start(), "Failure is not success or permission to retry.");
    }

    private static async Task WorkFailure()
    {
        var error = new IOException("Synthetic driver fault."); var runs = 0;
        var driver = new DeferredAsyncDriver(() => { runs++; throw error; }, () => { });
        Check(!driver.Start() && !driver.Start() && runs == 1, "Fault closes the sole startup admission.");
        try { await Finish(driver.RetireAsync()); throw new InvalidOperationException("Expected original driver failure."); }
        catch (IOException actual) when (ReferenceEquals(error, actual)) { }
    }

    private static async Task RoomDriver()
    {
        var entered = Signal(); var release = Signal(); var reads = 0;
        using var driver = new OverlayRoomRefreshDriver(() => (Owner, 1, true), (_, _) =>
        { reads++; entered.TrySetResult(); return release.Task; }, startDriver: false);
        Check(reads == 0 && driver.Completion.IsCompletedSuccessfully, "Configured room driver must not read yet.");
        Check(driver.StartDeferredWork() && driver.StartDeferredWork(), "Actual room driver starts once.");
        await Finish(entered.Task);
        var exit = driver.RetireAsync();
        Check(!exit.IsCompleted && reads == 1 && !driver.StartDeferredWork(), "Ignored cancellation still owns the physical read.");
        release.TrySetResult(); await Finish(exit);
        Check(reads == 1, "Retired room driver does not repeat a late read.");
    }

    private static async Task MultipleFailures()
    {
        var first = new IOException("Synthetic first fault.");
        var second = new IOException("Synthetic second fault.");
        var stopped = new IOException("Synthetic stop fault.");
        var driver = new DeferredAsyncDriver(() => Task.WhenAll(Task.FromException(first), Task.FromException(second)),
            () => throw stopped);
        Check(!driver.Start(), "Faulted original group cannot confirm activation.");
        var exit = driver.RetireAsync();
        try { await Finish(exit); throw new InvalidOperationException("Expected original faults."); }
        catch (IOException) { }
        var failures = exit.Exception!.Flatten().InnerExceptions;
        Check(failures.Count == 3 && failures.Contains(first) && failures.Contains(second) && failures.Contains(stopped),
            "Awaiting a group must not reduce its original exception set.");
    }

    private static async Task DormantRoomExit()
    {
        var reads = 0;
        using var driver = new OverlayRoomRefreshDriver(() => (Owner, 1, true), (_, _) =>
        { reads++; return Task.CompletedTask; }, startDriver: false);
        await Finish(driver.RetireAsync());
        Check(!driver.StartDeferredWork() && reads == 0, "Dormant room retirement cannot be undone.");
    }

    private static async Task CommunityDrivers()
    {
        var reader = new HeldReader();
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, startDriver: false,
            waitForWake: (_, _) => Task.CompletedTask);
        source.ReadForDisplay();
        Check(reader.Reads == 0 && reader.Changes == 0, "Display intent does not start deferred drivers.");
        Check(source.StartDeferredWork() && source.StartDeferredWork(), "Actual community drivers start once.");
        await Finish(reader.ReadEntered.Task); await Finish(reader.ChangeEntered.Task);
        var exit = source.RetireAsync();
        Check(!exit.IsCompleted && reader.Reads == 1 && reader.Changes == 1 && !source.StartDeferredWork(),
            "Both original physical reads remain part of exit.");
        reader.ReadRelease.TrySetResult(new("A", "Example", []));
        Check(!exit.IsCompleted, "Finishing only one sibling cannot acknowledge exit.");
        reader.ChangeRelease.TrySetResult(new("fixture", 1, true));
        await Finish(exit);
        Check(source.ReadForDisplay() is null && reader.Reads == 1 && reader.Changes == 1,
            "Late original completions cannot republish a retired source.");
    }

    private static async Task DormantCommunityExit()
    {
        var reader = new HeldReader();
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, startDriver: false);
        await Finish(source.RetireAsync());
        Check(!source.StartDeferredWork() && reader.Reads == 0 && reader.Changes == 0,
            "Dormant community retirement cannot allocate either sibling.");
    }

    private static async Task CommunitySiblingFailure()
    {
        var reader = new HeldReader(); var wake = Signal(); var failure = new IOException("Synthetic wake fault.");
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, startDriver: false,
            waitForWake: (_, _) => wake.Task);
        source.ReadForDisplay();
        Check(source.StartDeferredWork(), "Dormant original group can start.");
        await Finish(reader.ChangeEntered.Task);
        wake.TrySetException(failure);
        await Finish(reader.ChangeCancelled.Task);
        Check(!source.StartDeferredWork() && !source.Completion.IsCompleted,
            "A failed wake seals startup immediately without acknowledging the late sibling.");
        var exit = source.RetireAsync();
        reader.ChangeRelease.TrySetResult(new("fixture", 1, true));
        try { await Finish(exit); throw new InvalidOperationException("Expected original sibling failure."); }
        catch (IOException actual) when (ReferenceEquals(failure, actual)) { }
        Check(!source.StartDeferredWork() && source.ReadForDisplay() is null && reader.Changes == 1,
            "Failed original group cannot restart or publish after retirement.");
    }

    private sealed class HeldReader : IOverlayCommunityReader, IOverlayCommunityChangeReader
    {
        internal int Reads, Changes;
        internal readonly TaskCompletionSource ReadEntered = Signal(), ChangeEntered = Signal(), ChangeCancelled = Signal();
        internal readonly TaskCompletionSource<InformationOverlayCommunityContent> ReadRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource<OverlayActivityCursor> ChangeRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) =>
            Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>([new("A", "Example", "fixture")]);
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token)
        { Reads++; ReadEntered.TrySetResult(); return ReadRelease.Task; }
        public Task<OverlayActivityCursor> WaitForChangesAsync(BridgeAccountContext owner, long generation, OverlayActivityCursor after, CancellationToken token)
        { Changes++; token.Register(() => ChangeCancelled.TrySetResult()); ChangeEntered.TrySetResult(); return ChangeRelease.Task; }
    }
}
