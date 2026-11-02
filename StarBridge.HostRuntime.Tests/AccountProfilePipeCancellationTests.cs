using System.Collections.Concurrent;
using StarBridge.HostRuntime;
using StarBridge.NativeBridge;

internal static partial class AccountPreferenceActionTests
{
    internal static async Task StagedPipeCancellationReachesHttp()
    {
        using var f = new Fixture();
        var stamp = DateTimeOffset.UtcNow.AddHours(-1);
        f.Cache.Save(f.Route, f.Handler.Profile, stamp);
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var cancelled = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        f.Handler.ReadReply = async (_, token) => {
            using var registration = token.Register(() => cancelled.TrySetResult());
            entered.TrySetResult();
            await Task.Delay(Timeout.InfiniteTimeSpan, token);
            throw new InvalidOperationException("Unreachable synthetic response");
        };
        await using var pipe = new ProfilePipe(f.Dispatcher);
        var read = pipe.Send("profile.getDisplayData", "held-profile", new { schemaVersion = 1 }, f.Context);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        Equal("ok", (await pipe.Send("profile.readDisplayCache", "cached-while-held", new { schemaVersion = 1 }, f.Context)).Status, "local cache bypasses held private read");
        var wrong = await pipe.Send("bridge.cancel", "wrong-generation", new { targetCorrelationId = "held-profile" }, generation: 6);
        Equal(false, wrong.Payload.GetProperty("cancelled").GetBoolean(), "wrong generation cannot cancel another read");
        Equal(false, cancelled.Task.IsCompleted, "wrong generation did not reach HTTP cancellation");
        var malformed = await pipe.Send("bridge.cancel", "malformed-cancel", new { targetCorrelationId = "held-profile", force = true });
        Equal("error", malformed.Status, "extra cancellation options must be rejected");
        Equal(false, cancelled.Task.IsCompleted, "malformed cancellation did not affect HTTP");
        var result = await pipe.Send("bridge.cancel", "cancel-held-profile", new { targetCorrelationId = "held-profile" });
        Equal(true, result.Payload.GetProperty("cancelled").GetBoolean(), "pipe cancellation must find ordinary profile IO");
        await cancelled.Task.WaitAsync(TimeSpan.FromSeconds(3));
        Equal("cancelled", (await read).Status, "actual HTTP cancellation response");
        Equal("ok", (await pipe.Send("account.getCurrent", "current-after-cancel", new { schemaVersion = 1 })).Status, "cancellation releases actual account queue");
        Equal(stamp, f.Cache.Load(f.Route)?.CachedAtUtc, "cancelled HTTP cannot change previous cache time");
        Equal(1, f.Handler.ReadTokens.Count, "cancelled profile read is never replayed");
        Equal("ok", (await pipe.Send("profile.clearLocalCache", "clear-after-cancel", new { schemaVersion = 1 }, f.Context)).Status, "explicit clear can finish after real read cancellation");
        Equal<StarBridge.Core.Profiles.ScmCachedProfileContract?>(null, f.Cache.Load(f.Route), "canceled background read cannot repersist explicitly cleared display");
    }

    internal static async Task StagedPipeCancelsBeforeQueueAdmission()
    {
        using var dispatcher = new ProfileQueueProbe();
        await using var pipe = new ProfilePipe(dispatcher);
        var blockers = Enumerable.Range(0, NativeHostPipeServer.RequestWorkerCount).Select(i => pipe.Send("friends.read", "block-" + i,
            new { schemaVersion = 1 }, ProfileQueueProbe.Owner)).ToArray();
        await dispatcher.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var queued = pipe.Send("profile.getDisplayData", "queued-profile", new { schemaVersion = 1 }, ProfileQueueProbe.Owner);
        var cancel = await pipe.Send("bridge.cancel", "cancel-queued-profile", new { targetCorrelationId = "queued-profile" });
        try {
            Equal(true, cancel.Payload.GetProperty("cancelled").GetBoolean(), "queued read is registered before ordinary pipe worker admission");
        } finally { dispatcher.Release.TrySetResult(); }
        await Task.WhenAll(blockers);
        Equal("cancelled", (await queued).Status, "queued cancellation response");
        Equal(0, dispatcher.ProfileCalls, "a canceled queued read must never start private IO");
    }

    internal static async Task StagedPipeLocalDisplayHasCapacity()
    {
        using var dispatcher = new ProfileQueueProbe();
        await using var pipe = new ProfilePipe(dispatcher);
        var blockers = Enumerable.Range(0, NativeHostPipeServer.RequestWorkerCount).Select(i => pipe.Send("friends.read", "block-display-" + i,
            new { schemaVersion = 1 }, ProfileQueueProbe.Owner)).ToArray();
        await dispatcher.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        try {
            Equal("ok", (await pipe.Send("profile.readDisplayCache", "local-display", new { schemaVersion = 1 }, ProfileQueueProbe.Owner)).Status,
                "bounded local display must not wait for every occupied ordinary worker");
            Equal(false, dispatcher.Release.Task.IsCompleted, "ordinary IO is still held");
        } finally { dispatcher.Release.TrySetResult(); }
        await Task.WhenAll(blockers);
    }

    internal static async Task StagedPipePreservesIndependentRootRetirement()
    {
        using var f = new Fixture();
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var reply = new TaskCompletionSource<System.Net.Http.HttpResponseMessage>(TaskCreationOptions.RunContinuationsAsynchronously);
        f.Handler.ReadReply = async (_, _) => { entered.TrySetResult(); return await reply.Task; };
        await using var pipe = new ProfilePipe(f.Dispatcher);
        var pending = pipe.Send("profile.getDisplayData", "retired-profile", new { schemaVersion = 1 }, f.Context);
        try {
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
            Equal(true, (await pipe.Send("bridge.cancel", "cancel-retired-profile", new { targetCorrelationId = "retired-profile" })).Payload.GetProperty("cancelled").GetBoolean(), "read cancellation accepted");
            // A real independent account transition must survive cancellation
            // of a transport that has not actually returned yet.
            await f.Host.LogoutAsync(f.Context, default);
        } finally { reply.TrySetResult(JsonRead(f.Handler.Profile)); }
        Equal("cancelled", (await pending).Status, "retired read cannot return old profile");
        var changed = await pipe.AccountChanged.Task.WaitAsync(TimeSpan.FromSeconds(3));
        Equal(8L, changed.SessionGeneration, "actual root retirement still reaches UI");
        Equal<BridgeAccountContext?>(null, f.Host.CurrentContext, "retired source stays signed out");
    }

    internal static async Task StagedPipeCancellationCannotCrossConnectionOrWrite()
    {
        using (var f = new Fixture()) {
            var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            f.Handler.ReadReply = async (_, token) => {
                entered.TrySetResult(); await Task.Delay(Timeout.InfiniteTimeSpan, token);
                throw new InvalidOperationException("Unreachable synthetic response");
            };
            await using var a = new ProfilePipe(f.Dispatcher);
            await using var b = new ProfilePipe(f.Dispatcher);
            var active = a.Send("profile.getDisplayData", "same-id", new { schemaVersion = 1 }, f.Context);
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
            Equal(false, (await b.Send("bridge.cancel", "foreign-cancel", new { targetCorrelationId = "same-id" })).Payload.GetProperty("cancelled").GetBoolean(), "another pipe cannot cancel the owner connection");
            Equal(false, active.IsCompleted, "foreign cancellation did not stop the read");
            await a.Send("bridge.cancel", "own-cancel", new { targetCorrelationId = "same-id" });
            Equal("cancelled", (await active).Status, "owner connection can still cancel its read");
        }
        using var dispatcher = new ProfileQueueProbe();
        await using var pipe = new ProfilePipe(dispatcher);
        var blockers = Enumerable.Range(0, NativeHostPipeServer.RequestWorkerCount).Select(i => pipe.Send("friends.read", "write-block-" + i, new { schemaVersion = 1 }, ProfileQueueProbe.Owner)).ToArray();
        await dispatcher.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var write = pipe.Send("profile.patchPreferences", "queued-write", new { schemaVersion = 1 }, ProfileQueueProbe.Owner);
        try { Equal(false, (await pipe.Send("bridge.cancel", "cancel-write", new { targetCorrelationId = "queued-write" })).Payload.GetProperty("cancelled").GetBoolean(), "read-only transport cancellation cannot cancel a write"); }
        finally { dispatcher.Release.TrySetResult(); }
        await Task.WhenAll(blockers);
        Equal("ok", (await write).Status, "original write path remains intact");
        Equal(1, dispatcher.WriteCalls, "write not lost or replayed");
    }

    private sealed class ProfileQueueProbe : IBridgeRequestDispatcher
    {
        internal static readonly BridgeAccountContext Owner = new("integration", "synthetic", "owner");
        internal TaskCompletionSource Started { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal TaskCompletionSource Release { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private int _started;
        internal int ProfileCalls;
        internal int WriteCalls;
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
        {
            if (request.Name == "friends.read") {
                if (Interlocked.Increment(ref _started) == NativeHostPipeServer.RequestWorkerCount) Started.TrySetResult();
                await Release.Task.WaitAsync(token);
            }
            if (request.Name == "profile.getDisplayData") Interlocked.Increment(ref ProfileCalls);
            if (request.Name == "profile.patchPreferences") Interlocked.Increment(ref WriteCalls);
            return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, cancelled = false }), []);
        }
        public void Dispose() => Release.TrySetResult();
    }

    private sealed class ProfilePipe : IAsyncDisposable
    {
        private readonly (IBridgeConnection Left, IBridgeConnection Right) _pair = InMemoryBridgeConnection.CreatePair();
        private readonly CancellationTokenSource _lifetime = new(TimeSpan.FromSeconds(15));
        private readonly ConcurrentDictionary<string, TaskCompletionSource<BridgeEnvelope>> _responses = new();
        private readonly Task _server, _reader;
        internal TaskCompletionSource<BridgeEnvelope> AccountChanged { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal ProfilePipe(IBridgeRequestDispatcher dispatcher)
        {
            _server = NativeHostPipeServer.ServeConnectionAsync(_pair.Right, dispatcher, _lifetime.Token);
            _reader = Task.Run(async () => {
                await foreach (var envelope in _pair.Left.ReadAllAsync(_lifetime.Token)) {
                    if (envelope.MessageType == BridgeMessageTypes.Event && envelope.Name == "account.changed") AccountChanged.TrySetResult(envelope);
                    if (envelope.CorrelationId is { } id && _responses.TryRemove(id, out var response)) response.TrySetResult(envelope);
                }
            });
        }
        internal async Task<BridgeEnvelope> Send(string name, string id, object payload, BridgeAccountContext? owner = null, long generation = 7)
        {
            var response = new TaskCompletionSource<BridgeEnvelope>(TaskCreationOptions.RunContinuationsAsynchronously);
            if (!_responses.TryAdd(id, response)) throw new InvalidOperationException("Duplicate synthetic RPC");
            await _pair.Left.SendAsync(BridgeEnvelope.Request(name, id, generation, payload, owner), _lifetime.Token);
            return await response.Task.WaitAsync(TimeSpan.FromSeconds(4));
        }
        public async ValueTask DisposeAsync()
        {
            _lifetime.Cancel();
            await _pair.Left.DisposeAsync();
            try { await Task.WhenAll(_server, _reader); }
            catch (OperationCanceledException) when (_lifetime.IsCancellationRequested) { }
            await _pair.Right.DisposeAsync();
            _lifetime.Dispose();
        }
    }
}
