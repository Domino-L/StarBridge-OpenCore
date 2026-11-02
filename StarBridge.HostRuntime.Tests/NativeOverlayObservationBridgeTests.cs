using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

internal static class NativeOverlayObservationBridgeTests
{
    private static NativeOverlayObservation Snapshot(long count = 0, string? outcome = null) =>
        new("11111111111111111111111111111111", 2, "closed", false, false,
            new("registered", "Alt+F10", 1, count, outcome), new(null, null, false, false));
    private static BridgeEnvelope Request(object? body = null) => BridgeEnvelope.Request(
        NativeOverlayObservationBridgeDispatcher.ReadRequest, Guid.NewGuid().ToString("N"), 2, body ?? new { schemaVersion = 1 });
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    internal static async Task Run()
    {
        await Projection(); await StrictRequests(); await InvalidOwnerProjection(); await Lifetime(); await ExactComposition();
    }
    private static async Task Projection()
    {
        var reader = new Reader(); using var dispatcher = new NativeOverlayObservationBridgeDispatcher(reader, () => 2);
        var reply = (await dispatcher.DispatchAsync(Request())).Response;
        Check(reply.Status == "ok" && reply.AccountContext is null && reader.Reads == 1, "pure accountless observation");
        var payload = reply.Payload;
        Check(payload.EnumerateObject().Count() == 8 && payload.GetProperty("hotkey").EnumerateObject().Count() == 5 &&
            payload.GetProperty("preview").EnumerateObject().Count() == 4, "finite projection");
        Check(payload.GetProperty("hotkey").GetProperty("acceptedInputCount").GetInt64() == 0 &&
            payload.GetProperty("hotkey").GetProperty("lastOutcome").ValueKind == JsonValueKind.Null,
            "registration is not input acceptance");
        Check(new[] { "ready", "confirmed", "localSettingsReady", "handle", "path", "accountId", "windowHandle", "content" }
            .All(name => !payload.GetRawText().Contains('"' + name + '"', StringComparison.OrdinalIgnoreCase)), "no grants or content");
        reader.Value = Snapshot(1, "failed");
        reply = (await dispatcher.DispatchAsync(Request())).Response;
        Check(reply.Status == "ok" && reply.Payload.GetProperty("hotkey").GetProperty("lastOutcome").GetString() == "failed",
            "accepted message can still fail");
        reader.Value = Snapshot() with { Preview = new("22222222222222222222222222222222", 0, true, true) };
        reply = (await dispatcher.DispatchAsync(Request())).Response;
        Check(reply.Status == "ok" && reply.Payload.GetProperty("preview").GetProperty("firstFrameCommitted").GetBoolean(),
            "actual preview surface fact remains separate from normal window");
        Console.WriteLine("PASS native observation: finite read-only facts never grant readiness or human acceptance");
    }
    private static async Task StrictRequests()
    {
        var reader = new Reader(); using var dispatcher = new NativeOverlayObservationBridgeDispatcher(reader, () => 2);
        foreach (var raw in new[] { "{}", "[]", "{\"schemaVersion\":true}", "{\"schemaVersion\":2}",
            "{\"schemaVersion\":1,\"schemaVersion\":1}", "{\"schemaVersion\":1,\"workspace\":{}}" })
        {
            using var document = JsonDocument.Parse(raw);
            Check((await dispatcher.DispatchAsync(Request(document.RootElement))).Response.Error?.Code == "firstUse.invalid_request", "strict schema");
        }
        foreach (var request in new[] { Request() with { Name = "onboarding.nativeOverlayObservation.open" },
            Request() with { AccountContext = new("fixture", "scm", "fixture") } })
            Check((await dispatcher.DispatchAsync(request)).Response.Status == "error", "exact no-authority read");
        Check(reader.Reads == 0, "invalid requests never reach Native");
        Check(!BridgeRequestPolicy.RequiresAccountContext(NativeOverlayObservationBridgeDispatcher.ReadRequest) &&
            BridgeRequestPolicy.RequiresAccountContext("onboarding.nativeOverlayObservation.open") &&
            BridgeRequestPolicy.RequiresAccountContext("friends.read"), "no prefix or business exemptions");
        Console.WriteLine("PASS native observation: malformed/contextual/mutating requests never reach the Native owner");
    }
    private static async Task InvalidOwnerProjection()
    {
        var reader = new Reader(); using var dispatcher = new NativeOverlayObservationBridgeDispatcher(reader, () => 2);
        foreach (var value in new NativeOverlayObservation?[] { null, Snapshot() with { RuntimeId = "private path" },
            Snapshot() with { AppliedRevision = -1 }, Snapshot() with { WindowState = "ready" },
            Snapshot() with { Hotkey = Snapshot().Hotkey with { Binding = "bad\nchord" } },
            Snapshot(0, "open"), Snapshot(1), Snapshot() with { Hotkey = Snapshot().Hotkey with { AcceptedInputCount = 9007199254740992 } },
            Snapshot() with { Preview = new(null, null, true, false) },
            Snapshot() with { Preview = new("22222222222222222222222222222222", null, false, false) } })
        {
            reader.Value = value;
            Check((await dispatcher.DispatchAsync(Request())).Response.Error?.Code == "firstUse.native_observation_unavailable", "incompatible owner facts rejected");
        }
        Console.WriteLine("PASS native observation: missing or inconsistent Native facts remain unavailable");
    }
    private static async Task Lifetime()
    {
        long generation = 2; var reader = new Reader(); var dispatcher = new NativeOverlayObservationBridgeDispatcher(reader, () => generation);
        generation++;
        Check((await dispatcher.DispatchAsync(Request())).Response.Error?.Code == "firstUse.context_changed" && reader.Reads == 0, "pre-read stale");
        generation = 2; reader.AfterRead = () => generation++;
        Check((await dispatcher.DispatchAsync(Request())).Response.Error?.Code == "firstUse.context_changed", "post-read stale");
        generation = 2; reader.AfterRead = () => throw new Exception("private diagnostic");
        var failed = (await dispatcher.DispatchAsync(Request())).Response;
        Check(failed.Status == "error" && !failed.Error!.Message.Contains("private"), "sanitized owner failure");
        using var cancel = new CancellationTokenSource(); reader.AfterRead = cancel.Cancel;
        Check((await dispatcher.DispatchAsync(Request(), cancel.Token)).Response.Status == BridgeResponseStatuses.Cancelled, "post-read cancel");
        reader.AfterRead = dispatcher.Dispose;
        Check((await dispatcher.DispatchAsync(Request())).Response.Error?.Code == "firstUse.context_changed", "disposed while reading");
        var reads = reader.Reads;
        Check((await dispatcher.DispatchAsync(Request())).Response.Status == "error" && reader.Reads == reads, "sealed read");
        Console.WriteLine("PASS native observation: generations, cancellation, failure and disposal invalidate observations");
    }
    private static async Task ExactComposition()
    {
        var reader = new Reader(); var bridge = new NativeOverlayObservationBridgeDispatcher(reader, () => 2);
        var composite = new CompositeBridgeDispatcher(new Unused(), new Unused(), new Unused(), firstUseOverlayObservation: bridge);
        Check((await composite.DispatchAsync(Request())).Response.Status == "ok" && reader.Reads == 1, "exact composed route");
        Check((await composite.DispatchAsync(Request() with { Name = "onboarding.nativeOverlayObservation.open" })).Response.Status == "error" && reader.Reads == 1,
            "no mutation route or fallback");
        composite.Dispose();
        Check((await bridge.DispatchAsync(Request())).Response.Status == "error" && reader.Reads == 1, "bridge closed, borrowed owner untouched");
        Console.WriteLine("PASS native observation: composition routes only one read and disposes no Native owner");
    }
    private sealed class Reader : INativeOverlayObservationReader
    {
        internal NativeOverlayObservation? Value = Snapshot(); internal int Reads; internal Action? AfterRead;
        public ValueTask<NativeOverlayObservation?> ReadNativeOverlayObservationAsync(CancellationToken token = default)
        { Reads++; AfterRead?.Invoke(); return ValueTask.FromResult(Value); }
    }
    private sealed class Unused : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default) =>
            throw new InvalidOperationException("Observation reached a business owner");
        public void Dispose() { }
    }
}
