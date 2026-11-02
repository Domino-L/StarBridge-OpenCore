using StarBridge.Core.Tools;
using StarBridge.HostRuntime.Tools;
using StarBridge.NativeBridge;
using System.Text.Json;

internal static class ExecHangarGameOverlayTests
{
    internal static async Task Run()
    {
        var checks = 0;
        void Check(bool value, string why) { checks++; if (!value) throw new Exception(why); }
        var origin = new DateTimeOffset(2026, 10, 10, 0, 0, 0, TimeSpan.Zero);
        var config = new ExecHangarConfig("fixture", "fixture", null, origin, 0, 65, 120, 0);
        var now = origin.AddMinutes(10);
        ExecHangarSnapshot Snapshot() { var schedule = new ExecHangarSchedule(config); return new(1, 0, new(), config, now, now, true, false, "idle", schedule.Phases(now), schedule.Windows(now)); }
        var value = Snapshot();
        long generation = 3;
        var sink = new Sink();
        var reads = 0;
        TaskCompletionSource<ExecHangarSnapshot>? pending = null;
        using var overlay = new ExecHangarGameOverlay(_ => { reads++; return pending?.Task ?? Task.FromResult(value); }, sink, () => generation);
        Check(!overlay.Read().Pinned, "No automatic game overlay on startup");
        await overlay.TickAsync(); Check(reads == 0, "Unpinned overlay does not read or change the hangar runtime");
        foreach (var position in ExecHangarGameOverlay.Positions)
        {
            overlay.Change(position, () => true); await overlay.TickAsync();
            Check(sink.Frame?.Position == position && sink.Current?.Invoke() == true, "Every approved anchor uses the same authoritative clock");
        }
        Check(sink.Frame!.Open && sink.Frame.Green == 5 && sink.Frame.Boundary == origin.AddMinutes(65), "Open snapshot retains exact lamps and close boundary");
        var old = sink.Current!;
        overlay.Change(null, () => true); Check(!old() && !overlay.Read().Pinned && sink.Frame is null, "Unpin immediately revokes outstanding render grants");
        overlay.Change("topLeft", () => true);
        pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var work = overlay.TickAsync(); overlay.Change(null, () => true); pending.SetResult(value); await work; pending = null;
        Check(sink.Frame is null, "Late read cannot recreate a cancelled game overlay");
        overlay.Change("topLeft", () => true); await overlay.TickAsync(); old = sink.Current!; generation++;
        Check(!old() && !overlay.Read().Pinned, "Account generation change retires the session display");
        overlay.Change("bottomCenter", () => true);
        value = value with { Reliable = false }; await overlay.TickAsync();
        Check(sink.Frame is null && overlay.Read().Pinned, "Invalid calibration hides without discarding the user's pin choice");
        value = value with { Reliable = true, FetchedAt = now.AddHours(-7) }; await overlay.TickAsync();
        Check(sink.Frame is null, "Expired snapshot never shows a clock");
        now = origin.AddMinutes(63); value = Snapshot(); await overlay.TickAsync();
        Check(sink.Frame!.Leaving && sink.Frame.Green == 0 && sink.Frame.Red == 0, "All lamps off is independently projected as leave now");
        now = origin.AddMinutes(65); value = Snapshot(); await overlay.TickAsync();
        Check(!sink.Frame!.Open && sink.Frame.Red == 5 && sink.Frame.Boundary == origin.AddMinutes(185), "Exact closure switches lamps and targets the next open");
        pending = new(TaskCreationOptions.RunContinuationsAsynchronously); work = overlay.TickAsync();
        overlay.Change("topRight", () => true); pending.SetResult(value); await work; pending = null;
        Check(sink.Frame is null, "Late previous-position frame cannot overwrite a repositioning intent");
        foreach (var position in new[] { "center", "../topLeft", "", "TOPLEFT" })
        {
            try { overlay.Change(position, () => true); throw new Exception("Unexpected accepted position"); }
            catch (ArgumentException) { checks++; }
        }
        try { overlay.Change("topLeft", () => false); throw new Exception("Unexpected retired commit"); }
        catch (OperationCanceledException) { checks++; }

        var root = Path.Combine(AppContext.BaseDirectory, "game-overlay-test-" + Guid.NewGuid().ToString("N"));
        using var runtime = new ExecHangarRuntime(root, new Client(config), (_, _) => ValueTask.FromResult("submitted"));
        var bridge = new ExecHangarBridgeDispatcher(runtime, () => generation, overlay);
        BridgeEnvelope Request(string action, object payload) => BridgeEnvelope.Request("execHangar.gameOverlay." + action, Guid.NewGuid().ToString("N"), generation, payload);
        foreach (var position in ExecHangarGameOverlay.Positions)
            Check((await bridge.DispatchAsync(Request("pin", new { schemaVersion = 1, position }))).Response.Status != BridgeResponseStatuses.Error, "Six exact position intents reach only display state");
        var read = Request("read", new { schemaVersion = 1 });
        Check((await bridge.DispatchAsync(read with { SessionGeneration = generation - 1 })).Response.Status == BridgeResponseStatuses.Error, "Retired bridge generation rejected");
        foreach (var payload in new[] { "{\"schemaVersion\":1,\"position\":\"center\"}",
            "{\"schemaVersion\":1,\"position\":\"topLeft\",\"enabled\":true}",
            "{\"schemaVersion\":1,\"position\":\"topLeft\",\"path\":\"C:/private\"}",
            "{\"schemaVersion\":1,\"position\":\"topLeft\",\"position\":\"topRight\"}" })
            Check((await bridge.DispatchAsync(Request("pin", new { schemaVersion = 1, position = "topLeft" }) with {
                Payload = JsonSerializer.Deserialize<JsonElement>(payload) })).Response.Status == BridgeResponseStatuses.Error, "Extra/duplicate/invalid pin fields rejected");
        Check((await bridge.DispatchAsync(Request("unpin", new { schemaVersion = 1 }))).Response.Status != BridgeResponseStatuses.Error && !overlay.Read().Pinned, "Explicit unpin stops game display");
        Check(!Directory.Exists(root), "Display pin/unpin does not touch hangar settings, receipts or monitoring");
        overlay.Change("topLeft", () => true); await overlay.TickAsync(); old = sink.Current!;
        overlay.Dispose(); Check(!old() && sink.Disposed, "Disposal revokes grants and disposes the native surface");
        Console.WriteLine($"PASS game hangar overlay: {checks} assertions; anchors, clock, stale replies, generation, cancellation, calibration and exact display intents");
    }
    private sealed class Sink : IExecHangarGameOverlaySink
    {
        public bool Available => true;
        internal bool Disposed;
        internal ExecHangarGameOverlayFrame? Frame;
        internal Func<bool>? Current;
        public void Present(ExecHangarGameOverlayFrame frame, Func<bool> isCurrent) { Frame = frame; Current = isCurrent; }
        public void Clear() { Frame = null; Current = null; }
        public void Dispose() { Clear(); Disposed = true; }
    }
    private sealed class Client(ExecHangarConfig config) : IExecHangarConfigClient
    { public Task<ExecHangarConfig> FetchAsync(CancellationToken token) => Task.FromResult(config); }
}
