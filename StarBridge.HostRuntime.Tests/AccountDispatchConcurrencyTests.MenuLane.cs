using StarBridge.HostRuntime;
using StarBridge.NativeBridge;

internal static partial class AccountDispatchConcurrencyTests
{
    // Device trace 2026-10-17: a menu preference read waited 864ms behind
    // startup HTTP reads (5.9s, 4.1s, 2.1s) holding every ordinary pipe worker.
    private static async Task MenuPreferencesDoNotQueueBehindOrdinaryWorkers()
    {
        Check(BridgeRequestPolicy.IsMenuInteraction("applicationPreferences.menu.get") &&
            BridgeRequestPolicy.IsMenuInteraction("applicationPreferences.menu.update") &&
            BridgeRequestPolicy.IsMenuInteraction("applicationPreferences.menu.begin") &&
            !BridgeRequestPolicy.IsMenuInteraction("menuHotkey.window") &&
            !BridgeRequestPolicy.IsMenuInteraction("applicationPreferences.get"),
            "Only the local menu preference stores use the menu lane.");
        var pair = InMemoryBridgeConnection.CreatePair();
        using var dispatcher = new SlowNetworkProbe();
        using var lifetime = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var server = NativeHostPipeServer.ServeConnectionAsync(pair.Right, dispatcher, lifetime.Token);
        var menuReply = new TaskCompletionSource<BridgeEnvelope>(TaskCreationOptions.RunContinuationsAsynchronously);
        var responses = Task.Run(async () => {
            await foreach (var response in pair.Left.ReadAllAsync(lifetime.Token))
                if (response.CorrelationId == "menu-read") menuReply.TrySetResult(response);
        });
        try
        {
            for (var i = 0; i < NativeHostPipeServer.RequestWorkerCount + 2; i++)
                await pair.Left.SendAsync(BridgeEnvelope.Request("communities.media", $"slow-{i}", 1,
                    new { schemaVersion = 1 }), lifetime.Token);
            await Until(() => dispatcher.SlowStarted == NativeHostPipeServer.RequestWorkerCount);
            await pair.Left.SendAsync(BridgeEnvelope.Request("applicationPreferences.menu.get", "menu-read", 1,
                new { schemaVersion = 1 }), lifetime.Token);
            Check(await Task.WhenAny(menuReply.Task, Task.Delay(1000)) == menuReply.Task &&
                (await menuReply.Task).Status == "ok" && !dispatcher.Release.Task.IsCompleted,
                "A menu preference read queued behind ordinary workers waiting on network reads.");
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

    private sealed class SlowNetworkProbe : IBridgeRequestDispatcher
    {
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int SlowStarted;
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
        {
            if (request.Name == "communities.media")
            {
                Interlocked.Increment(ref SlowStarted);
                await Release.Task.WaitAsync(token);
            }
            return new(BridgeEnvelope.Response(request, new { schemaVersion = 1 }), []);
        }
        public void Dispose() => Release.TrySetResult();
    }
}
