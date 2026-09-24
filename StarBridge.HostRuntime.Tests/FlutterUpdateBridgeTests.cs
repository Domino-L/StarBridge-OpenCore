using StarBridge.HostRuntime.Updates;
using StarBridge.HostRuntime;
using StarBridge.NativeBridge;

internal static class FlutterUpdateBridgeTests
{
    internal static async Task Verify()
    {
        long generation = 4;
        using var dispatcher = new FlutterUpdateBridgeDispatcher(null, () => "0.6.6", () => generation);
        var request = BridgeEnvelope.Request(FlutterUpdateBridgeDispatcher.RequestName, Guid.NewGuid().ToString("N"), 4,
            new { schemaVersion = 1 });
        var result = (await dispatcher.DispatchAsync(request)).Response;
        if (result.Status != "ok" || result.Payload.GetProperty("state").GetString() != "channel-unconfigured" ||
            result.Payload.GetProperty("currentVersion").GetString() != "0.6.6") throw new Exception("Unconfigured update status is not honest.");
        if (result.Payload.EnumerateObject().Count() != 5 ||
            result.Payload.GetProperty("availableVersion").ValueKind != System.Text.Json.JsonValueKind.Null ||
            result.Payload.GetProperty("notes").ValueKind != System.Text.Json.JsonValueKind.Null)
            throw new Exception("Update response omitted nullable fields required by Flutter.");
        using (var composite = new StarBridge.HostRuntime.CompositeBridgeDispatcher(new RejectRoute(), new RejectRoute(), new RejectRoute(),
            updates: new FlutterUpdateBridgeDispatcher(null, () => "0.6.6", () => generation)))
            if ((await composite.DispatchAsync(request)).Response.Status != "ok") throw new Exception("Composite update route missing.");
        if ((await dispatcher.DispatchAsync(request with { AccountContext = new("test", "test", "test") })).Response.Status != "error")
            throw new Exception("Update request unexpectedly accepted account context.");
        foreach (var payload in new object[] { new { schemaVersion = 2 }, new { schemaVersion = "1" },
            new { schemaVersion = 1, url = "https://example.invalid/untrusted" } })
        {
            var invalid = BridgeEnvelope.Request(FlutterUpdateBridgeDispatcher.RequestName, Guid.NewGuid().ToString("N"), 4, payload);
            if ((await dispatcher.DispatchAsync(invalid)).Response.Status != "error") throw new Exception("Unsafe update request accepted.");
        }
        generation++;
        if ((await dispatcher.DispatchAsync(request)).Response.Status != "error") throw new Exception("Stale update request accepted.");
        generation = 4;
        if ((await dispatcher.DispatchAsync(request, new CancellationToken(true))).Response.Status != "cancelled") throw new Exception("Cancellation ignored.");
        dispatcher.Dispose();
        if ((await dispatcher.DispatchAsync(request)).Response.Status != "error") throw new Exception("Disposed update dispatcher accepted request.");
        var stages = 0;
        var handoffs = 0;
        var fail = false;
        var installer = new FlutterUpdateInstallation((version, token) => {
            stages++;
            if (version != "0.6.7") throw new Exception("Wrong confirmed version.");
            return Task.FromResult("owned-candidate");
        }, (path, token) => {
            handoffs++;
            if (path != "owned-candidate") throw new Exception("UI chose candidate path.");
            if (fail) throw new IOException("Uncertain helper result.");
            return Task.CompletedTask;
        });
        using var installDispatcher = new FlutterUpdateBridgeDispatcher(null, () => "0.6.6", () => generation, installation: installer);
        using var routed = new CompositeBridgeDispatcher(new RejectRoute(), new RejectRoute(), new RejectRoute(), updates: installDispatcher);
        BridgeEnvelope Command(string name, object payload) => BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), generation, payload);
        async Task<string> Prepare() {
            var response = (await routed.DispatchAsync(Command(FlutterUpdateBridgeDispatcher.PrepareRequestName,
                new { schemaVersion = 1, version = "0.6.7" }))).Response;
            if (response.Status != "ok") throw new Exception("Prepare route failed.");
            return response.Payload.GetProperty("ticket").GetString()!;
        }
        async Task<string?> Handoff(string ticket) => (await routed.DispatchAsync(Command(FlutterUpdateBridgeDispatcher.HandoffRequestName,
            new { schemaVersion = 1, ticket }))).Response.Status;
        var first = await Prepare();
        if (stages != 1 || handoffs != 0 || await Handoff(first) != "ok" || handoffs != 1 || await Handoff(first) != "error")
            throw new Exception("Installation was premature or replayable.");
        var stale = await Prepare();
        generation++;
        if (await Handoff(stale) != "error" || handoffs != 1) throw new Exception("Old-session ticket was accepted.");
        var uncertain = await Prepare();
        fail = true;
        if (await Handoff(uncertain) != "error" || await Handoff(uncertain) != "error" || handoffs != 2)
            throw new Exception("Uncertain handoff was replayed.");
        var injected = Command(FlutterUpdateBridgeDispatcher.PrepareRequestName,
            new { schemaVersion = 1, version = "0.6.7", path = "untrusted" });
        if ((await routed.DispatchAsync(injected)).Response.Status != "error") throw new Exception("Installation accepted UI path.");
        await VerifyProgress();
    }
    private static async Task VerifyProgress()
    {
        long generation = 1, sequence = 100;
        Action<FlutterUpdateProgress>? late = null;
        var staging = new TaskCompletionSource<string>();
        var installation = new FlutterUpdateInstallation((version, progress, token) => {
            late = progress;
            progress!(new("downloading", 0, null));
            progress(new("downloading", 1, null)); // throttled
            progress(new("verifying", 10, null));
            progress(new("verified", 10, null));
            return staging.Task;
        }, (_, _) => throw new Exception("Progress must not start installation."));
        using var dispatcher = new FlutterUpdateBridgeDispatcher(null, () => "0.7.0", () => generation,
            installation: installation, progressEvent: (owner, payload) =>
                BridgeEnvelope.Event(FlutterUpdateBridgeDispatcher.ProgressEventName, owner, ++sequence, payload));
        using var composite = new CompositeBridgeDispatcher(new RejectRoute(), new RejectRoute(), new RejectRoute(), updates: dispatcher);
        var events = new List<BridgeEnvelope>();
        composite.EventReady += events.Add;
        var request = BridgeEnvelope.Request(FlutterUpdateBridgeDispatcher.PrepareRequestName, "prepare-progress", 1,
            new { schemaVersion = 1, version = "0.7.1" });
        var pending = composite.DispatchAsync(request).AsTask();
        if (events.Count != 3 || pending.IsCompleted) throw new Exception("Progress pacing or final-response boundary broken.");
        foreach (var item in events)
            if (item.Name != FlutterUpdateBridgeDispatcher.ProgressEventName || item.Sequence <= 100 ||
                item.SessionGeneration != 1 || item.AccountContext != null ||
                item.Payload.EnumerateObject().Count() != 6 ||
                item.Payload.GetProperty("requestId").GetString() != request.CorrelationId ||
                item.Payload.GetProperty("totalBytes").ValueKind != System.Text.Json.JsonValueKind.Null)
                throw new Exception("Progress lost correlation, shared sequence or explicit unknown size.");
        generation++;
        late!(new("verified", 11, null));
        if (events.Count != 3) throw new Exception("Old-session progress leaked.");
        staging.SetResult("owned-fixture");
        if ((await pending).Response.Status != "error") throw new Exception("Old-session download became installable.");
        generation = 1;
        late(new("verified", 12, null));
        if (events.Count != 3) throw new Exception("Finished operation emitted late progress.");
    }
    private sealed class RejectRoute : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default) =>
            throw new Exception("Update request routed to an unrelated owner.");
        public void Dispose() { }
    }
}
