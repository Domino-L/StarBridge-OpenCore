using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class OverlayRuntimeEventTests
{
    private static InformationOverlayRuntimeSnapshot State(string windowState) =>
        new(windowState, windowState == "open", 3, "registered", "manual", "Default", "Default", false);

    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-overlay-events-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(root);
            Check(OverlayBridgeDispatcher.AdvertisedCapabilities.Contains("overlay.runtimeEvents"), "Push support is advertised");
            var generation = 7L;
            var runtime = new PushRuntime { Current = State("closed") };
            var dispatcher = new OverlayBridgeDispatcher(new OverlaySettingsStore(root), new OverlayWorkspaceStore(root),
                () => generation, () => GameLogSessionSnapshot.Empty, runtime);
            var other = new UnusedDispatcher();
            using var composite = new CompositeBridgeDispatcher(other, other, other, overlay: dispatcher);
            var received = new List<BridgeEnvelope>();
            var signal = new SemaphoreSlim(0);
            composite.EventReady += envelope => { lock (received) received.Add(envelope); signal.Release(); };
            Check(runtime.Handlers == 1, "Dispatcher subscribes to the runtime once");

            // Same payload as getState, device scope, current control generation.
            runtime.Current = State("open");
            var response = (await composite.DispatchAsync(BridgeEnvelope.Request("overlay.runtime.getState", "state", generation,
                new { schemaVersion = 1, language = "zh" }))).Response;
            Check(response.Status == "ok", "getState succeeds");
            runtime.Raise(State("open"));
            Check(await signal.WaitAsync(TimeSpan.FromSeconds(5)), "A runtime change reaches the composite");
            BridgeEnvelope first;
            lock (received) first = received.Single();
            Check(first.Name == "overlay.runtime.changed" && first.MessageType == BridgeMessageTypes.Event, "Event name and type");
            Check(first.SessionGeneration == generation && first.AccountContext is null, "Device event on the current generation");
            Check(first.Payload.GetRawText() == response.Payload.GetRawText(), "Event payload equals the getState payload");

            // A burst ends on the newest state, never an older one.
            for (var i = 0; i < 50; i++) runtime.Raise(State(i % 2 == 0 ? "closed" : "suppressed"));
            runtime.Raise(State("failed"));
            var deadline = DateTime.UtcNow.AddSeconds(5);
            while (DateTime.UtcNow < deadline && LastState(received) != "failed") await signal.WaitAsync(TimeSpan.FromMilliseconds(100));
            await Task.Delay(200);
            Check(LastState(received) == "failed", "The last published state is the last raised state");

            // No control generation (account slot retired): nothing is published.
            generation = -1;
            int before;
            lock (received) before = received.Count;
            runtime.Raise(State("closed"));
            await Task.Delay(300);
            lock (received) Check(received.Count == before, "No event without a control generation");

            composite.Dispose();
            Check(runtime.Handlers == 0, "Dispose unsubscribes from the runtime");
            Console.WriteLine("PASS overlay runtime changes are pushed as device events with the getState payload");
        }
        finally
        {
            Check(Path.GetFileName(root).StartsWith("starbridge-overlay-events-", StringComparison.Ordinal), "Unsafe cleanup");
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    private static string? LastState(List<BridgeEnvelope> received)
    {
        lock (received)
            return received.Count == 0 ? null : received[^1].Payload.GetProperty("windowState").GetString();
    }

    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }

    private sealed class PushRuntime : IInformationOverlayRuntime, IInformationOverlayRuntimeStateSource
    {
        private Action<InformationOverlayRuntimeSnapshot>? _changed;
        internal InformationOverlayRuntimeSnapshot Current = InformationOverlayRuntimeSnapshot.Unavailable;
        internal int Handlers => _changed?.GetInvocationList().Length ?? 0;
        public event Action<InformationOverlayRuntimeSnapshot>? StateChanged { add => _changed += value; remove => _changed -= value; }
        internal void Raise(InformationOverlayRuntimeSnapshot snapshot) => _changed?.Invoke(snapshot);
        public ValueTask<InformationOverlayRuntimeSnapshot> ExecuteAsync(InformationOverlayRuntimeCommand command,
            InformationOverlayRuntimeWorkspace workspace, CancellationToken cancellationToken = default) => ValueTask.FromResult(Current);
        public void Dispose() { }
    }

    private sealed class UnusedDispatcher : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default) =>
            throw new InvalidOperationException("Overlay requests must not reach unrelated owners.");
        public void Dispose() { }
    }
}
