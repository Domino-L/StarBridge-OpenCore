using System.Diagnostics;
using System.Reflection;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime;

internal static partial class AccountDispatchConcurrencyTests
{
    internal static async Task VerifyOfficialActivityLane()
    {
        await ActivityWaitsDoNotOccupyOrdinaryWorkers();
        Console.WriteLine("PASS GOV2 pipe: held official wait leaves ordinary and cancellation workers available");
        await ActivityWaitQueueRetainsBackpressure();
        Console.WriteLine("PASS GOV2 pipe: three active waits plus two queued slots reject overflow without starving ordinary requests");
    }
    internal static async Task Verify()
    {
        await IndependentRead();
        await WriteBarrier();
        await CapacityAndCancellation();
        await CancelWriterAndActiveReader();
        await UnauditedHostStaysExclusive();
        await EventsAndGeneration();
        await ActivityDoesNotHoldWriteBarrier();
        await ActivityCrossesCompositionAndCancels();
        await CommunityActivityCrossesComposition();
        await LoadingReadScheduling();
        await MenuPreferencesDoNotQueueBehindOrdinaryWorkers();
        await ForegroundReadsPassQueuedBackgroundMedia();
        await PriorityKeepsWriteFence();
        await RepeatedCurrentSkipsReadQueueButNotMutations();
        await StartupBurstDoesNotStarveLocalReads();
        await ForegroundReadsPassQueuedStartupReads();
        await StartupReadsKeepWriteFence();
        await ScmResourceReadsOverlap();
        await ScmProjectionAndWritesStayExclusive();
        await ScmResourceReadsNeedHealthySession();
        await MessagesWindowReadPassesQueuedReads();
        await MessagesWindowReadKeepsSendFence();
        Console.WriteLine("PASS bounded independent reads, exclusive account operations, cancellation, event batching and stale generation");
    }

    private static (IAccountBridgeHost Host, Probe Probe) Create()
    {
        var host = DispatchProxy.Create<IAccountBridgeHost, Probe>();
        return (host, (Probe)(object)host);
    }
    private static async Task CommunityActivityCrossesComposition()
    {
        var (host, probe) = Create();
        using var runtime = new StarBridge.HostRuntime.AccountBridgeRuntime(host);
        using var composite = new StarBridge.HostRuntime.CompositeBridgeDispatcher(runtime, runtime, runtime);
        var socialRequest = Request(AccountBridgeRequestNames.WaitSocialActivity);
        var communityRequest = Request(AccountBridgeRequestNames.WaitCommunityActivity);
        var social = composite.DispatchAsync(socialRequest).AsTask();
        var community = composite.DispatchAsync(communityRequest).AsTask();
        try
        {
            await Until(() => probe.ActivityWaits == 2);
            var duplicate = await composite.DispatchAsync(Request(AccountBridgeRequestNames.WaitCommunityActivity));
            Check(duplicate.Response.Error?.Code == "bridge.backpressure", "Community wait has its own bounded slot.");
            await composite.DispatchAsync(BridgeEnvelope.Request("bridge.cancel", Guid.NewGuid().ToString("N"), 1,
                new { targetCorrelationId = communityRequest.CorrelationId }));
            Check(await Task.WhenAny(community, Task.Delay(1000)) == community &&
                (await community).Response.Status == "cancelled" && !social.IsCompleted,
                "Cancelling organization wait must not cancel social activity.");
        }
        finally { probe.ActivityRelease.TrySetResult(new { schemaVersion = 1 }); await Task.WhenAll(social, community); }
    }
    private static async Task ActivityCrossesCompositionAndCancels()
    {
        var (host, probe) = Create();
        using var runtime = new StarBridge.HostRuntime.AccountBridgeRuntime(host);
        using var composite = new StarBridge.HostRuntime.CompositeBridgeDispatcher(runtime, runtime, runtime);
        var request = Request(AccountBridgeRequestNames.WaitSocialActivity);
        var wait = composite.DispatchAsync(request).AsTask();
        try {
            await Task.WhenAny(wait, Task.Delay(100));
            Check(probe.ActivityWaits == 1 && !wait.IsCompleted, "Social wait must cross the real composite and runtime routing.");
            var cancel = BridgeEnvelope.Request("bridge.cancel", Guid.NewGuid().ToString("N"), 1,
                new { targetCorrelationId = request.CorrelationId });
            await composite.DispatchAsync(cancel);
            Check(await Task.WhenAny(wait, Task.Delay(1000)) == wait && (await wait).Response.Status == "cancelled",
                "Cancellation must release the actual Host wait, not only the Flutter future.");
        } finally { probe.ActivityRelease.TrySetResult(new { schemaVersion = 1 }); await wait; }
    }
    private static async Task ActivityDoesNotHoldWriteBarrier()
    {
        var (host, probe) = Create();
        using var dispatcher = new AccountBridgeDispatcher(host);
        var wait = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.WaitSocialActivity));
        await Until(() => probe.ActivityWaits == 1);
        var duplicate = await dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.WaitSocialActivity));
        Check(duplicate.Response.Error?.Code == "bridge.backpressure", "Only one activity wait may occupy a worker.");
        var write = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.Login));
        try {
            await Until(() => probe.Writes == 1);
            probe.WriteRelease.SetResult(new("signedIn", 1, Probe.Owner, "Fixture", null));
            Check((await write).Response.Status == "ok" && !wait.IsCompleted, "Long poll cannot block an account write.");
            probe.Advance();
        } finally { probe.ActivityRelease.TrySetResult(new { schemaVersion = 1 }); }
        Check((await wait).Response.Status is "error" or "cancelled", "A wait from the previous generation cannot escape.");
    }
    private static BridgeEnvelope Request(string name, long generation = 1) =>
        BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), generation, new { schemaVersion = 1 },
            name == AccountBridgeRequestNames.Login ? null : Probe.Owner);

    private static async Task LoadingReadScheduling()
    {
        var failures = new List<Exception>();
        foreach (var verify in new Func<Task>[] { LocalPolicyDoesNotWaitForNetworkRead, ActivityWaitsDoNotOccupyOrdinaryWorkers })
        {
            try { await verify(); }
            catch (Exception error) { failures.Add(error); Console.WriteLine("FAIL loading scheduling: " + error.Message); }
        }
        if (failures.Count > 0) throw new AggregateException(failures);
        await LocalPolicyRetainsWriteBarrier();
        await UnauditedPolicyRemainsExclusive();
        await ActivityWaitQueueRetainsBackpressure();
    }

    private static async Task LocalPolicyDoesNotWaitForNetworkRead()
    {
        var (host, probe) = Create();
        using var dispatcher = new AccountBridgeDispatcher(host);
        var slow = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Until(() => probe.Reads == 1);
        var policy = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.GetGameIdentityPolicy));
        try
        {
            Check(await Task.WhenAny(policy, Task.Delay(1000)) == policy,
                "A local identity-policy snapshot waits behind an independent network read.");
            Check((await policy).Response.Status == "ok" && probe.Policies == 1 && !slow.IsCompleted,
                "Policy must return the authorized snapshot while the network read remains pending.");
        }
        finally { probe.ReadRelease.TrySetResult(new { schemaVersion = 1 }); await Task.WhenAll(slow, policy); }
        probe.Advance();
        var stale = await dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.GetGameIdentityPolicy));
        Check(stale.Response.Status == "error" && stale.Response.Error?.Code == BridgeErrorCodes.StaleGeneration && probe.Policies == 1,
            "An old-generation policy request cannot reach the Host or return identity data.");
    }

    private static async Task LocalPolicyRetainsWriteBarrier()
    {
        var (host, probe) = Create();
        using var dispatcher = new AccountBridgeDispatcher(host);
        var slow = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Until(() => probe.Reads == 1);
        var write = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.Login));
        var policy = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.GetGameIdentityPolicy));
        try
        {
            Check(probe.Policies == 0 && probe.Writes == 0, "Policy cannot bypass a waiting account write.");
            probe.ReadRelease.TrySetResult(new { schemaVersion = 1 });
            await slow;
            await Until(() => probe.Writes == 1);
            Check(probe.Policies == 0, "Policy cannot overlap the account mutation.");
        }
        finally { probe.ReadRelease.TrySetResult(new { schemaVersion = 1 }); probe.WriteRelease.TrySetResult(new("signedIn", 1, Probe.Owner, "Fixture", null)); await Task.WhenAll(slow, write, policy); }
        Check((await policy).Response.Status == "ok" && probe.Policies == 1, "Policy resumes after the mutation barrier.");
    }

    private static async Task UnauditedPolicyRemainsExclusive()
    {
        var (host, probe) = Create(); probe.ConcurrentReads = false;
        using var dispatcher = new AccountBridgeDispatcher(host);
        var slow = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Until(() => probe.Reads == 1);
        var policy = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.GetGameIdentityPolicy));
        try { Check(probe.Policies == 0, "An unaudited session must retain serialized identity-policy reads."); }
        finally { probe.ReadRelease.TrySetResult(new { schemaVersion = 1 }); await Task.WhenAll(slow, policy); }
        Check((await policy).Response.Status == "ok", "Serialized policy still completes successfully.");
    }

    private static async Task ActivityWaitsDoNotOccupyOrdinaryWorkers()
    {
        var pair = InMemoryBridgeConnection.CreatePair();
        using var dispatcher = new LoadingPipeProbe();
        using var lifetime = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var server = NativeHostPipeServer.ServeConnectionAsync(pair.Right, dispatcher, lifetime.Token);
        var policyReply = new TaskCompletionSource<BridgeEnvelope>(TaskCreationOptions.RunContinuationsAsynchronously);
        var controlReply = new TaskCompletionSource<BridgeEnvelope>(TaskCreationOptions.RunContinuationsAsynchronously);
        var responses = Task.Run(async () => {
            await foreach (var response in pair.Left.ReadAllAsync(lifetime.Token))
            {
                if (response.CorrelationId == "local-policy") policyReply.TrySetResult(response);
                if (response.CorrelationId == "cancel-activity") controlReply.TrySetResult(response);
            }
        });
        try
        {
            foreach (var name in new[] { AccountBridgeRequestNames.WaitSocialActivity, "officialFleet.wait",
                AccountBridgeRequestNames.WaitCommunityActivity,
                AccountBridgeRequestNames.ReadFriends, AccountBridgeRequestNames.ReadCommunities })
                await pair.Left.SendAsync(Request(name), lifetime.Token);
            await Until(() => dispatcher.ActivityStarted == 3 && dispatcher.OrdinaryStarted == 2);
            await pair.Left.SendAsync(BridgeEnvelope.Request(AccountBridgeRequestNames.GetGameIdentityPolicy, "local-policy", 1,
                new { schemaVersion = 1 }, Probe.Owner), lifetime.Token);
            await pair.Left.SendAsync(BridgeEnvelope.Request("bridge.cancel", "cancel-activity", 1,
                new { targetCorrelationId = "synthetic-wait" }), lifetime.Token);
            Check(await Task.WhenAny(controlReply.Task, Task.Delay(1000)) == controlReply.Task &&
                (await controlReply.Task).Status == "ok", "Cancellation retains its independent control worker.");
            Check(await Task.WhenAny(policyReply.Task, Task.Delay(1000)) == policyReply.Task &&
                (await policyReply.Task).Status == "ok" && !dispatcher.Release.Task.IsCompleted,
                "Long polls consume ordinary pipe workers and block a local policy request.");
        }
        finally
        {
            dispatcher.Release.TrySetResult();
            lifetime.Cancel();
            await pair.Left.DisposeAsync();
            try { await Task.WhenAll(server, responses); }
            catch (OperationCanceledException) when (lifetime.IsCancellationRequested) { }
            await pair.Right.DisposeAsync();
        }
    }

    private sealed class LoadingPipeProbe : IBridgeRequestDispatcher
    {
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int ActivityStarted, OrdinaryStarted;
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
        {
            if (BridgeRequestPolicy.IsActivityWait(request.Name))
            {
                Interlocked.Increment(ref ActivityStarted); await Release.Task.WaitAsync(token);
            }
            else if (request.Name is AccountBridgeRequestNames.ReadFriends or AccountBridgeRequestNames.ReadCommunities)
            {
                Interlocked.Increment(ref OrdinaryStarted); await Release.Task.WaitAsync(token);
            }
            return new(BridgeEnvelope.Response(request, new { schemaVersion = 1 }), []);
        }
        public void Dispose() => Release.TrySetResult();
    }

    private static async Task ActivityWaitQueueRetainsBackpressure()
    {
        var pair = InMemoryBridgeConnection.CreatePair();
        using var dispatcher = new LoadingPipeProbe();
        using var lifetime = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var server = NativeHostPipeServer.ServeConnectionAsync(pair.Right, dispatcher, lifetime.Token);
        var overflowReply = new TaskCompletionSource<BridgeEnvelope>(TaskCreationOptions.RunContinuationsAsynchronously);
        var policyReply = new TaskCompletionSource<BridgeEnvelope>(TaskCreationOptions.RunContinuationsAsynchronously);
        var responses = Task.Run(async () => {
            await foreach (var response in pair.Left.ReadAllAsync(lifetime.Token))
            {
                if (response.CorrelationId == "activity-overflow") overflowReply.TrySetResult(response);
                if (response.CorrelationId == "policy-after-backpressure") policyReply.TrySetResult(response);
            }
        });
        try
        {
            await pair.Left.SendAsync(Request(AccountBridgeRequestNames.WaitSocialActivity), lifetime.Token);
            await pair.Left.SendAsync(Request("officialFleet.wait"), lifetime.Token);
            await pair.Left.SendAsync(Request(AccountBridgeRequestNames.WaitCommunityActivity), lifetime.Token);
            await Until(() => dispatcher.ActivityStarted == 3);
            await pair.Left.SendAsync(Request(AccountBridgeRequestNames.WaitSocialActivity), lifetime.Token);
            await pair.Left.SendAsync(Request("officialFleet.wait"), lifetime.Token);
            await pair.Left.SendAsync(BridgeEnvelope.Request(AccountBridgeRequestNames.WaitSocialActivity, "activity-overflow", 1,
                new { schemaVersion = 1 }, Probe.Owner), lifetime.Token);
            Check(await Task.WhenAny(overflowReply.Task, Task.Delay(1000)) == overflowReply.Task &&
                (await overflowReply.Task).Error?.Code == BridgeErrorCodes.Backpressure,
                "A saturated activity queue must reject excess waits with backpressure.");
            Check(dispatcher.ActivityStarted == 3, "Activity waits cannot expand their three active workers.");
            await pair.Left.SendAsync(BridgeEnvelope.Request(AccountBridgeRequestNames.GetGameIdentityPolicy, "policy-after-backpressure", 1,
                new { schemaVersion = 1 }, Probe.Owner), lifetime.Token);
            Check(await Task.WhenAny(policyReply.Task, Task.Delay(1000)) == policyReply.Task && (await policyReply.Task).Status == "ok",
                "Activity backpressure cannot disconnect the pipe or block an ordinary local request.");
        }
        finally
        {
            dispatcher.Release.TrySetResult(); lifetime.Cancel(); await pair.Left.DisposeAsync();
            try { await Task.WhenAll(server, responses); }
            catch (OperationCanceledException) when (lifetime.IsCancellationRequested) { }
            await pair.Right.DisposeAsync();
        }
    }

    private static async Task IndependentRead()
    {
        var (host, probe) = Create();
        using var dispatcher = new AccountBridgeDispatcher(host);
        var slow = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Until(() => probe.Reads == 1);
        var clock = Stopwatch.StartNew();
        var fast = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadFriends));
        try
        {
            Check(await Task.WhenAny(fast, Task.Delay(1000)) == fast,
                "Independent friends read is blocked behind a slow organization read.");
            Check((await fast).Response.Status == "ok", "Independent read must succeed, not merely fail early.");
            Console.WriteLine($"Independent read completed while organization remained blocked: {clock.ElapsedMilliseconds}ms");
        }
        finally { probe.ReadRelease.TrySetResult(new { schemaVersion = 1 }); await Task.WhenAll(slow, fast); }
    }

    private static async Task WriteBarrier()
    {
        var (host, probe) = Create();
        using var dispatcher = new AccountBridgeDispatcher(host);
        var slow = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Until(() => probe.Reads == 1);
        var write = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.Login));
        var later = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadFriends));
        Check(probe.Writes == 0 && probe.Friends == 0, "A queued writer must fence later reads.");
        probe.ReadRelease.SetResult(new { schemaVersion = 1 });
        await slow;
        await Until(() => probe.Writes == 1);
        Check(probe.Friends == 0, "Reads must not overlap an account mutation.");
        probe.WriteRelease.SetResult(new("signedIn", 1, Probe.Owner, "Fixture", null));
        await Task.WhenAll(write, later);
        Check(probe.Friends == 1, "A read resumes after the write barrier.");
    }

    private static async Task CapacityAndCancellation()
    {
        var (host, probe) = Create();
        using var dispatcher = new AccountBridgeDispatcher(host);
        var reads = Enumerable.Range(0, 4).Select(_ => dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities))).ToArray();
        await Until(() => probe.Reads == 4);
        using var cancellation = new CancellationTokenSource();
        var waiting = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities), cancellation.Token);
        Check(probe.Reads == 4, "At most four independent reads may enter the host.");
        cancellation.Cancel();
        try { await waiting; throw new InvalidOperationException("Cancelled queue entry was executed."); }
        catch (OperationCanceledException) { }
        probe.ReadRelease.SetResult(new { schemaVersion = 1 });
        await Task.WhenAll(reads);
        Check((await dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadFriends))).Response.Status == "ok",
            "Cancelling a waiter must not leak the gate.");
    }

    private static async Task EventsAndGeneration()
    {
        var (host, probe) = Create();
        using var dispatcher = new AccountBridgeDispatcher(host);
        var published = new List<BridgeEnvelope>();
        dispatcher.EventReady += published.Add;
        var slow = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Until(() => probe.Reads == 1);
        var fast = await dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadFriends));
        Check(fast.Events.Count == 0 && published.Count == 0, "Independent reads have no unsolicited events.");
        dispatcher.PublishDomainInvalidation("communities.changed", 1);
        var fenced = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadFriends));
        Check(probe.Friends == 1, "Pending invalidations fence later reads so events cannot starve.");
        probe.Advance();
        probe.ReadRelease.SetResult(new { schemaVersion = 1 });
        var result = await slow;
        Check(result.Response.Status == "error", "Old-generation read results must not escape.");
        Check(result.Events.Select(e => e.Name).SequenceEqual(new[] { "communities.changed", "account.changed" }),
            "Buffered invalidations retain their order and are returned after the last response.");
        Check(result.Events[0].Sequence < result.Events[1].Sequence, "Event sequences remain ordered.");
        Check((await fenced).Response.Status == "error" && probe.Friends == 1,
            "A queued old-generation request cannot reach the host after the drain.");
    }

    private static async Task UnauditedHostStaysExclusive()
    {
        var (host, probe) = Create();
        probe.ConcurrentReads = false;
        using var dispatcher = new AccountBridgeDispatcher(host);
        var slow = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Until(() => probe.Reads == 1);
        var later = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadFriends));
        Check(probe.Friends == 0, "Unaudited session transports must retain serialized reads.");
        probe.ReadRelease.SetResult(new { schemaVersion = 1 });
        await Task.WhenAll(slow, later);
        Check(probe.Friends == 1, "Exclusive reads still make progress after the previous response.");
    }

    private static async Task CancelWriterAndActiveReader()
    {
        var (host, probe) = Create();
        using var dispatcher = new AccountBridgeDispatcher(host);
        using var readerCancellation = new CancellationTokenSource();
        using var writerCancellation = new CancellationTokenSource();
        var slow = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities), readerCancellation.Token);
        await Until(() => probe.Reads == 1);
        var writer = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.Login), writerCancellation.Token);
        var later = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadFriends));
        Check(probe.Friends == 0, "The queued writer initially fences later reads.");
        writerCancellation.Cancel();
        try { await writer; throw new InvalidOperationException("Cancelled writer entered the host."); }
        catch (OperationCanceledException) { }
        Check((await later.WaitAsync(TimeSpan.FromSeconds(2))).Response.Status == "ok" && probe.Writes == 0,
            "Cancelling a writer releases admission without executing a mutation.");
        readerCancellation.Cancel();
        Check((await slow).Response.Status == "cancelled", "An active cancelled read must not return its data.");
        var nextWrite = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.Login));
        await Until(() => probe.Writes == 1);
        probe.WriteRelease.SetResult(new("signedIn", 1, Probe.Owner, "Fixture", null));
        Check((await nextWrite).Response.Status == "ok", "Cancelled reads release the exclusive resource.");
    }

    private static async Task Until(Func<bool> condition)
    {
        var deadline = DateTime.UtcNow.AddSeconds(2);
        while (!condition()) { if (DateTime.UtcNow > deadline) throw new TimeoutException("Fixture did not enter host."); await Task.Delay(1); }
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }

    public class Probe : DispatchProxy
    {
        internal static readonly BridgeAccountContext Owner = new("test", "fixture", "owner");
        internal readonly TaskCompletionSource<object> ReadRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource<object> ActivityRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int ActivityWaits;
        internal readonly TaskCompletionSource<AccountBridgeSessionProjection> WriteRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int Reads, Friends, Writes, Policies, Currents, MediaStarted, Avatars;
        internal readonly TaskCompletionSource<object> MediaRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal bool ConcurrentReads = true;
        private long _generation = 1;
        private Action<long>? _changed;
        internal void Advance() { _generation++; _changed?.Invoke(_generation); }
        protected override object? Invoke(MethodInfo? method, object?[]? args)
        {
            switch (method!.Name)
            {
                case "get_Generation": return _generation;
                case "get_CurrentContext": return Owner;
                case "get_SupportsConcurrentReads": return ConcurrentReads;
                case "add_AccountChanged": _changed += (Action<long>)args![0]!; return null;
                case "remove_AccountChanged": _changed -= (Action<long>)args![0]!; return null;
                case "ReadCommunitiesAsync": Interlocked.Increment(ref Reads); return ReadRelease.Task.WaitAsync((CancellationToken)args![^1]!);
                case "WaitSocialActivityAsync":
                case "WaitCommunityActivityAsync": Interlocked.Increment(ref ActivityWaits); return ActivityRelease.Task.WaitAsync((CancellationToken)args![^1]!);
                case "ReadCommunityMediaAsync": Interlocked.Increment(ref MediaStarted); return MediaRelease.Task.WaitAsync((CancellationToken)args![^1]!);
                case "ReadAvatarAsync": Interlocked.Increment(ref Avatars); return Task.FromResult<object>(new { schemaVersion = 1 });
                case "ReadFriendsAsync": Interlocked.Increment(ref Friends); return Task.FromResult(new FriendsView(null, DateTimeOffset.UtcNow, [], [], [], [], []));
                case "GetGameIdentityPolicyAsync": Interlocked.Increment(ref Policies); return Task.FromResult(new AccountBridgeIdentityProjection("unknown", null, false));
                case "LoginAsync": Interlocked.Increment(ref Writes); return WriteRelease.Task;
                case "GetCurrentAsync": Interlocked.Increment(ref Currents); return Task.FromResult(new AccountBridgeSessionProjection("signedIn", 1, Owner, "Fixture", null));
                default: throw new NotSupportedException(method.Name);
            }
        }
    }
}
