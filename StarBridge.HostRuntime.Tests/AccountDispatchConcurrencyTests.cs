using System.Diagnostics;
using System.Reflection;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

internal static class AccountDispatchConcurrencyTests
{
    internal static async Task Verify()
    {
        await IndependentRead();
        await WriteBarrier();
        await CapacityAndCancellation();
        await CancelWriterAndActiveReader();
        await UnauditedHostStaysExclusive();
        await EventsAndGeneration();
        Console.WriteLine("PASS bounded independent reads, exclusive account operations, cancellation, event batching and stale generation");
    }

    private static (IAccountBridgeHost Host, Probe Probe) Create()
    {
        var host = DispatchProxy.Create<IAccountBridgeHost, Probe>();
        return (host, (Probe)(object)host);
    }
    private static BridgeEnvelope Request(string name, long generation = 1) =>
        BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), generation, new { schemaVersion = 1 },
            name == AccountBridgeRequestNames.Login ? null : Probe.Owner);

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
        internal readonly TaskCompletionSource<AccountBridgeSessionProjection> WriteRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int Reads, Friends, Writes;
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
                case "ReadFriendsAsync": Interlocked.Increment(ref Friends); return Task.FromResult(new FriendsView(null, DateTimeOffset.UtcNow, [], [], [], [], []));
                case "LoginAsync": Interlocked.Increment(ref Writes); return WriteRelease.Task;
                default: throw new NotSupportedException(method.Name);
            }
        }
    }
}
