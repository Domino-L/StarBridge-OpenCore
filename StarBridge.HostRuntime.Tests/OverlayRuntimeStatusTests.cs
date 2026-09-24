using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class OverlayRuntimeStatusTests
{
    internal static async Task ReadOnlyBoundaryAndExactRouting()
    {
        var reader = new Reader();
        using var dispatcher = new OverlayRuntimeStatusBridgeDispatcher(reader, () => 2);
        using var composite = new CompositeBridgeDispatcher(new Unused(), new Unused(), new Unused(), overlayRuntimeStatus: dispatcher);
        var result = (await composite.DispatchAsync(Request())).Response;
        Require(result.Status == "ok" && result.AccountContext is null);
        Require(result.Payload.GetProperty("hotkeyBinding").GetString() == "Alt+F10");
        Require(result.Payload.EnumerateObject().Count() == 5 && reader.Reads == 1);
        Require(!BridgeRequestPolicy.RequiresAccountContext(OverlayRuntimeStatusBridgeDispatcher.RequestName));
        var invalid = new[] { Request(new { schemaVersion = 1, workspace = new { } }),
            Request() with { AccountContext = new("test", "scm", "synthetic") },
            Request(new { schemaVersion = 2 }), Request() with { Name = "overlay.runtime.getState" } };
        foreach (var request in invalid) Require((await dispatcher.DispatchAsync(request)).Response.Status == "error");
        Require(reader.Reads == 1);
    }
    internal static async Task StaleCancelledDisposedAndFailure()
    {
        long generation = 2;
        var reader = new Reader();
        using var dispatcher = new OverlayRuntimeStatusBridgeDispatcher(reader, () => generation);
        reader.BeforeReturn = () => generation++;
        Require((await dispatcher.DispatchAsync(Request())).Response.Status == "error");
        Require(reader.Reads == 1);
        generation = 2;
        reader.BeforeReturn = () => throw new Exception("private state");
        var failed = (await dispatcher.DispatchAsync(Request())).Response;
        Require(failed.Status == "error" && !failed.Error!.Message.Contains("private"));
        using var cts = new CancellationTokenSource();
        cts.Cancel();
        Require((await dispatcher.DispatchAsync(Request(), cts.Token)).Response.Status == BridgeResponseStatuses.Cancelled);
        dispatcher.Dispose();
        Require((await dispatcher.DispatchAsync(Request())).Response.Status == "error");
    }
    private static BridgeEnvelope Request(object? body = null) => BridgeEnvelope.Request(
        OverlayRuntimeStatusBridgeDispatcher.RequestName, Guid.NewGuid().ToString("N"), 2, body ?? new { schemaVersion = 1 });
    private static void Require(bool condition) { if (!condition) throw new Exception("Runtime snapshot boundary failed."); }
    private sealed class Reader : IRuntimeOverlayStatusReader
    {
        public int Reads;
        public Action? BeforeReturn;
        public ValueTask<RuntimeOverlayStatus> ReadStatusAsync(CancellationToken cancellationToken = default)
        {
            Reads++;
            BeforeReturn?.Invoke();
            return ValueTask.FromResult(new RuntimeOverlayStatus("open", "registered", "Alt+F10", 2));
        }
    }
    private sealed class Unused : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default) =>
            throw new Exception("Wrong runtime route");
        public void Dispose() { }
    }
}
