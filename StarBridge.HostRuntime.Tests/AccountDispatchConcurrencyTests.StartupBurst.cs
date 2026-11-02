using System.Reflection;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static partial class AccountDispatchConcurrencyTests
{
    // DL-137 (build 12 night traces, 2026-10-21): about 20 requests arrive together
    // at startup. Under an SCM session the account lane runs one at a time, so
    // three of the four ordinary pipe workers sat waiting at the account gate.
    // A local presence read waited 5.8 s for a worker, and the organization
    // directory (foreground) was admitted only after every earlier barrier.
    private static async Task StartupBurstDoesNotStarveLocalReads()
    {
        var pair = InMemoryBridgeConnection.CreatePair();
        using var dispatcher = new BurstPipeProbe();
        using var lifetime = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var server = NativeHostPipeServer.ServeConnectionAsync(pair.Right, dispatcher, lifetime.Token);
        var localReply = new TaskCompletionSource<BridgeEnvelope>(TaskCreationOptions.RunContinuationsAsynchronously);
        var responses = Task.Run(async () => {
            await foreach (var response in pair.Left.ReadAllAsync(lifetime.Token))
                if (response.CorrelationId == "local-presence") localReply.TrySetResult(response);
        });
        const int burst = 12;
        try
        {
            for (var i = 0; i < burst; i++)
                await pair.Left.SendAsync(BridgeEnvelope.Request(AccountBridgeRequestNames.ReadDirectMessagePrivacy, $"queued-{i}", 1,
                    new { schemaVersion = 1 }), lifetime.Token);
            await pair.Left.SendAsync(BridgeEnvelope.Request("presence.read", "local-presence", 1,
                new { schemaVersion = 1 }), lifetime.Token);
            Check(await Task.WhenAny(localReply.Task, Task.Delay(1000)) == localReply.Task &&
                (await localReply.Task).Status == "ok" && !dispatcher.Release.Task.IsCompleted,
                "A local read waits for a pipe worker held by requests queued at the account gate.");
            await Until(() => dispatcher.Started == burst);
            Check(dispatcher.Started == burst,
                "Every startup request must reach the account gate so it can order them by priority.");
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

    private sealed class BurstPipeProbe : IBridgeRequestDispatcher
    {
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int Started;
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
        {
            if (request.Name == AccountBridgeRequestNames.ReadDirectMessagePrivacy)
            {
                Interlocked.Increment(ref Started);
                await Release.Task.WaitAsync(token);
            }
            return new(BridgeEnvelope.Response(request, new { schemaVersion = 1 }), []);
        }
        public void Dispose() => Release.TrySetResult();
    }

    // Same traces: privacy, inbox, room and fleet-identity reads were barriers, so
    // the organization directory queued behind all of them. They are audited pure
    // reads (one GET, then the shared session write every read already performs).
    // The SCM lane stays exclusive, and nothing passes a queued mutation.
    private static async Task ForegroundReadsPassQueuedStartupReads()
    {
        var host = DispatchProxy.Create<IAccountBridgeHost, StartupReadProbe>();
        var probe = (StartupReadProbe)(object)host;
        probe.ConcurrentReads = false;
        using var dispatcher = new AccountBridgeDispatcher(host);
        var slow = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Until(() => probe.Reads == 1);
        var queued = new[]
        {
            AccountBridgeRequestNames.ReadNotificationInbox,
            AccountBridgeRequestNames.GetOfficialFleetIdentity,
            AccountBridgeRequestNames.GetPartyRooms,
            AccountBridgeRequestNames.ReadDirectMessagePrivacy,
            AccountBridgeRequestNames.ReadFriendRequestPrivacy,
            AccountBridgeRequestNames.ReadRecentlyPlayedPrivacy,
        }.Select(name => dispatcher.DispatchAsync(Request(name))).ToArray();
        await Task.Delay(20);
        var friends = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadFriends));
        await Task.Delay(20);
        try
        {
            Check(probe.StartupReads == 0, "The exclusive lane still runs one request at a time.");
            probe.ReadRelease.TrySetResult(new { schemaVersion = 1 });
            await slow;
            Check(await Task.WhenAny(friends, Task.Delay(1000)) == friends && (await friends).Response.Status == "ok",
                "A foreground directory read waits behind queued privacy, inbox, room and fleet reads.");
            Check(probe.StartupReads <= 1, "Foreground reads must be admitted before queued startup reads.");
        }
        finally { probe.ReadRelease.TrySetResult(new { schemaVersion = 1 }); probe.ReleaseStartupReads(); }
        foreach (var read in queued)
            Check((await read.WaitAsync(TimeSpan.FromSeconds(2))).Response is not null, "Every queued startup read still completes.");
        Check(probe.StartupReads == queued.Length, "Every queued startup read eventually runs.");
    }

    // A reordered startup read still never overtakes a queued account mutation.
    private static async Task StartupReadsKeepWriteFence()
    {
        var host = DispatchProxy.Create<IAccountBridgeHost, StartupReadProbe>();
        var probe = (StartupReadProbe)(object)host;
        probe.ConcurrentReads = false;
        using var dispatcher = new AccountBridgeDispatcher(host);
        var slow = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Until(() => probe.Reads == 1);
        var write = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.Login));
        await Task.Delay(20);
        var privacy = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadDirectMessagePrivacy));
        await Task.Delay(20);
        try
        {
            probe.ReadRelease.TrySetResult(new { schemaVersion = 1 });
            await slow;
            await Until(() => probe.Writes == 1);
            Check(probe.StartupReads == 0, "A startup read may not overlap or overtake a queued account mutation.");
            probe.WriteRelease.TrySetResult(new("signedIn", 1, Probe.Owner, "Fixture", null));
            Check((await write).Response.Status == "ok", "The mutation completes.");
        }
        finally
        {
            probe.ReadRelease.TrySetResult(new { schemaVersion = 1 });
            probe.WriteRelease.TrySetResult(new("signedIn", 1, Probe.Owner, "Fixture", null));
            probe.ReleaseStartupReads();
        }
        Check((await privacy.WaitAsync(TimeSpan.FromSeconds(2))).Response.Status == "ok", "The privacy read resumes after the mutation.");
    }

    public class StartupReadProbe : Probe
    {
        internal int StartupReads;
        private readonly TaskCompletionSource<object> _objects = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly TaskCompletionSource<StarBridge.HostRuntime.PartyRooms.RoomDirectoryView> _rooms =
            new(TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly TaskCompletionSource<AccountBridgeOfficialFleetProjection> _fleet =
            new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal void ReleaseStartupReads()
        {
            _objects.TrySetResult(new { schemaVersion = 1 });
            // Only ordering is under test; an unavailable answer is a valid response.
            _rooms.TrySetException(new AccountBridgeHostException("party_rooms.read_unavailable", true));
            _fleet.TrySetException(new AccountBridgeHostException("officialFleet.unavailable", true));
        }
        protected override object? Invoke(MethodInfo? method, object?[]? args)
        {
            var token = args is { Length: > 0 } && args[^1] is CancellationToken t ? t : CancellationToken.None;
            switch (method!.Name)
            {
                case "ReadNotificationInboxAsync":
                case "ReadDirectMessagePrivacyAsync":
                case "ReadFriendRequestPrivacyAsync":
                case "ReadRecentlyPlayedPrivacyAsync":
                    Interlocked.Increment(ref StartupReads); return _objects.Task.WaitAsync(token);
                case "GetPartyRoomsAsync": Interlocked.Increment(ref StartupReads); return _rooms.Task.WaitAsync(token);
                case "GetOfficialFleetIdentityAsync": Interlocked.Increment(ref StartupReads); return _fleet.Task.WaitAsync(token);
                default: return base.Invoke(method, args);
            }
        }
    }
}
