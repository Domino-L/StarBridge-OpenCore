using System.Collections.Concurrent;
using System.Reflection;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static class ActivityWaitLaneTests
{
    internal static async Task RunAsync()
    {
        await ThreeWaitsAndProtectedLanes();
        await QueuedCancellation();
        await OrdinaryRegistrationBudget();
    }

    private static BridgeEnvelope Wait(string name, string id) => BridgeEnvelope.Request(name, id, 1,
        name == "officialFleet.wait"
            ? new { schemaVersion = 1, sourceRef = "officialFleet:7", instance = "", version = -1 }
            : (object)new { schemaVersion = 1, instance = "", version = -1 }, Host.Owner);

    private static async Task ThreeWaitsAndProtectedLanes()
    {
        await using var scene = new Pipe();
        await scene.Send(Wait("social.wait", "social"));
        await scene.Send(Wait("communities.wait", "communities"));
        await scene.Send(Wait("officialFleet.wait", "official"));
        try { await Until(() => scene.HostProbe.Started.Count == 3); }
        catch { throw new InvalidOperationException("Wait admission: started=" + scene.HostProbe.Started.Count + "; responses=" +
            string.Join(",", scene.Responses.Select(p => p.Key + ":" + p.Value.Status + ":" + p.Value.Error?.Code))); }
        Check(!scene.HostProbe.Release.Task.IsCompleted, "all three distinct waits execute together while held");
        Check(!BridgeRequestPolicy.IsActivityWait("officialFleet.waitRuntimeActivity"), "runtime activity remains in ordinary lane");
        await scene.Send(BridgeEnvelope.Request(AccountBridgeRequestNames.GetGameIdentityPolicy, "ordinary", 1,
            new { schemaVersion = 1 }, Host.Owner));
        Check((await scene.Reply("ordinary")).Status == "ok", "ordinary request completes while all three waits hold");
        await scene.Send(Cancel("social", "wrong-generation", 2));
        Check(!(await scene.Reply("wrong-generation")).Payload.GetProperty("cancelled").GetBoolean(),
            "another generation cannot cancel a held wait");
        await scene.Send(Cancel("social", "cancel-active"));
        Check((await scene.Reply("cancel-active")).Payload.GetProperty("cancelled").GetBoolean(),
            "control cancellation reaches active wait with all workers held");
        Check((await scene.Reply("social")).Status == "cancelled", "active cancellation emits cancelled serialized response");
    }

    private static async Task QueuedCancellation()
    {
        await using var scene = new Pipe();
        await scene.Send(Wait("social.wait", "social"));
        await scene.Send(Wait("communities.wait", "communities"));
        // Park the third worker at the transport/dispatcher seam so the review's
        // official wait is deterministically queued even with the new capacity.
        await scene.Send(Wait("social.wait", "transport-blocker"));
        await Until(() => scene.HostProbe.Started.Count == 2 && scene.BlockerStarted.Task.IsCompleted);
        await scene.Send(Wait("officialFleet.wait", "official-old"));
        await scene.Send(Wait("communities.wait", "queue-filler"));
        await scene.Send(Wait("social.wait", "overflow"));
        Check((await scene.Reply("overflow")).Error?.Code == BridgeErrorCodes.Backpressure,
            "three active plus two queued is still a hard bound");
        await scene.Send(Cancel("official-old", "wrong-generation", 2));
        Check(!(await scene.Reply("wrong-generation")).Payload.GetProperty("cancelled").GetBoolean(),
            "queued cancellation is generation bound");
        await scene.Send(Cancel("official-old", "cancel-queued"));
        Check((await scene.Reply("cancel-queued")).Payload.GetProperty("cancelled").GetBoolean(),
            "bridge.cancel reaches queued official wait");
        Check((await scene.Reply("official-old")).Status == "cancelled", "queued wait is removed before workers are released");
        await scene.Send(Wait("officialFleet.wait", "official-new"));
        // Reader-order barrier proves replacement admission before freeing any worker.
        await scene.Send(BridgeEnvelope.Request(AccountBridgeRequestNames.GetGameIdentityPolicy, "barrier", 1,
            new { schemaVersion = 1 }, Host.Owner));
        Check((await scene.Reply("barrier")).Status == "ok" && !scene.Responses.ContainsKey("official-new"),
            "cancel frees the full queue slot for a new wait of the same name");
        scene.BlockerRelease.TrySetResult();
        await Until(() => scene.HostProbe.Started.Count(n => n == "WaitOfficialFleetActivityAsync") == 1);
        Check(!scene.Dispatched.ContainsKey("official-old") && scene.HostProbe.Started.Count(n => n == "WaitOfficialFleetActivityAsync") == 1,
            "old queued wait never dispatches and replacement enters real account dispatcher once");
        scene.HostProbe.Release.TrySetResult(new { schemaVersion = 1 });
        Check((await scene.Reply("official-new")).Status == "ok", "replacement has no same-name backpressure");
    }

    private static BridgeEnvelope Cancel(string target, string id, long generation = 1) =>
        BridgeEnvelope.Request("bridge.cancel", id, generation, new { targetCorrelationId = target });

    private static async Task OrdinaryRegistrationBudget()
    {
        await using var scene = new Pipe();
        await scene.Send(Wait("social.wait", "social"));
        await scene.Send(Wait("communities.wait", "communities"));
        await scene.Send(Wait("officialFleet.wait", "official"));
        await Until(() => scene.HostProbe.Started.Count == 3);
        BridgeEnvelope Read(int id) => BridgeEnvelope.Request("profile.getDisplayData", "held-read-" + id, 1,
            new { schemaVersion = 1 }, Host.Owner);
        for (var i = 0; i < 16; i++) await scene.Send(Read(i));
        await Until(() => scene.Dispatched.Keys.Count(k => k.StartsWith("held-read-")) == 16);
        var ordinaryCapacity = 16 + BridgeProtocol.DefaultQueueCapacity;
        for (var i = 16; i < ordinaryCapacity; i++) await scene.Send(Read(i));
        var overflow = "held-read-" + ordinaryCapacity;
        await scene.Send(Read(ordinaryCapacity));
        Check((await scene.Reply(overflow)).Error?.Code == BridgeErrorCodes.Backpressure,
            "ordinary request bound remains sixteen running plus default queue capacity");
        Check(scene.Responses.Keys.All(k => !k.StartsWith("held-read-") || k == overflow),
            "wait registrations preserve the entire ordinary read registration budget");
        await scene.Send(Cancel("official", "cancel-with-full-ordinary"));
        Check((await scene.Reply("cancel-with-full-ordinary")).Payload.GetProperty("cancelled").GetBoolean() &&
            (await scene.Reply("official")).Status == "cancelled",
            "control still cancels held wait with every ordinary worker and queue slot occupied");
    }
    private static async Task Until(Func<bool> predicate)
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        while (!predicate()) await Task.Delay(1, deadline.Token);
    }
    private static void Check(bool value, string message)
    {
        if (!value) throw new InvalidOperationException(message);
        Console.WriteLine("PASS GOV3 pipe: " + message);
    }

    private sealed class Pipe : IBridgeRequestDispatcher, IAsyncDisposable
    {
        private readonly (IBridgeConnection Left, IBridgeConnection Right) _pair = InMemoryBridgeConnection.CreatePair();
        private readonly CancellationTokenSource _lifetime = new(TimeSpan.FromSeconds(30));
        private readonly AccountBridgeDispatcher _dispatcher;
        private readonly Task _server, _responses;
        internal Host HostProbe { get; }
        internal ConcurrentDictionary<string, BridgeEnvelope> Responses { get; } = new();
        internal ConcurrentDictionary<string, byte> Dispatched { get; } = new();
        internal TaskCompletionSource BlockerStarted { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal TaskCompletionSource BlockerRelease { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal Pipe()
        {
            var host = DispatchProxy.Create<IAccountBridgeHost, Host>();
            HostProbe = (Host)(object)host;
            _dispatcher = new(host);
            _server = NativeHostPipeServer.ServeConnectionAsync(_pair.Right, this, _lifetime.Token);
            _responses = ReadResponses();
        }
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
        {
            Dispatched.TryAdd(request.CorrelationId!, 0);
            if (request.CorrelationId!.StartsWith("held-read-"))
            {
                await BlockerRelease.Task.WaitAsync(token);
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1 }), []);
            }
            if (request.CorrelationId == "transport-blocker")
            {
                BlockerStarted.TrySetResult();
                await BlockerRelease.Task.WaitAsync(token);
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1 }), []);
            }
            var result = await _dispatcher.DispatchAsync(request, token);
            return new(result.Response, result.Events);
        }
        internal ValueTask Send(BridgeEnvelope request) => _pair.Left.SendAsync(request, _lifetime.Token);
        internal async Task<BridgeEnvelope> Reply(string id)
        {
            await Until(() => Responses.ContainsKey(id));
            return Responses[id];
        }
        private async Task ReadResponses()
        {
            await foreach (var response in _pair.Left.ReadAllAsync(_lifetime.Token))
                Responses.TryAdd(response.CorrelationId!, response);
        }
        public void Dispose() => _dispatcher.Dispose();
        public async ValueTask DisposeAsync()
        {
            HostProbe.Release.TrySetResult(new { schemaVersion = 1 });
            BlockerRelease.TrySetResult();
            _lifetime.Cancel();
            await _pair.Left.DisposeAsync();
            try { await Task.WhenAll(_server, _responses); }
            catch (OperationCanceledException) when (_lifetime.IsCancellationRequested) { }
            await _pair.Right.DisposeAsync();
            Dispose();
            _lifetime.Dispose();
        }
    }

    public class Host : DispatchProxy
    {
        internal static readonly BridgeAccountContext Owner = new("synthetic", "fixture", "owner");
        internal ConcurrentBag<string> Started { get; } = new();
        internal TaskCompletionSource<object> Release { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override object? Invoke(MethodInfo? method, object?[]? args)
        {
            switch (method!.Name)
            {
                case "get_Generation": return 1L;
                case "get_CurrentContext": return Owner;
                case "get_SupportsConcurrentReads": return true;
                case "add_AccountChanged": case "remove_AccountChanged": return null;
                case "WaitSocialActivityAsync": case "WaitCommunityActivityAsync": case "WaitOfficialFleetActivityAsync":
                    Started.Add(method.Name);
                    return Release.Task.WaitAsync((CancellationToken)args![^1]!);
                case "GetGameIdentityPolicyAsync": return Task.FromResult(new AccountBridgeIdentityProjection("unknown", null, false));
                default: throw new NotSupportedException(method.Name);
            }
        }
    }
}
