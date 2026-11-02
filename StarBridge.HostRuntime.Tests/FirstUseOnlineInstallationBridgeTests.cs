using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

internal static partial class FirstUseBusinessOwnerTests
{
    internal static Task RunInstallationFailureDiagnostics() => InstallationWireFailure();
    internal static async Task RunOnlineInstallationBridge()
    {
        await Case("installation wire refuses invented, stale and unconfirmed authority", InstallationWireStrict);
        await Case("installation wire returns original correlation through real generation handoff", InstallationWireFresh);
        await Case("cancelled installation observer polls and joins the original held task", InstallationWireObserver);
        await Case("failed actual composition reports original local recovery, never online success", InstallationWireFailure);
        await Case("completed original installation read rejects a newer intent", InstallationWireStale);
        await Case("disposed installation observer cannot publish the physical task's late result", InstallationWireDisposed);
    }

    private static BridgeEnvelope InstallationRequest(NativeAccountRuntimeBinding native, string name,
        long revision = 3, long? generation = null) => BridgeEnvelope.Request(name, Id(), generation ?? native.Generation,
            new { schemaVersion = 1, revision });
    private static JsonElement InstallationPayload(BridgeDispatchBatch batch)
    {
        Check(batch.Response.Status == BridgeResponseStatuses.Ok && batch.Response.AccountContext is null && batch.Events.Count == 0,
            "Installation facts cannot publish account context or fabricate account events.");
        var payload = batch.Response.Payload;
        Check(payload.EnumerateObject().Count() == (payload.TryGetProperty("failure", out _) ? 7 : 6) && payload.GetProperty("schemaVersion").GetInt32() == 1,
            "Exact bounded installation wire only.");
        return payload;
    }

    private static async Task InstallationWireStrict()
    {
        using var f = new Fixture(); await f.Start(confirm: false);
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        using var c = new CompositionFixture(f, native);
        using var route = native.CreateOnlineInstallationDispatcher(c.Composition)!;
        var request = InstallationRequest(native, FirstUseOnlineInstallationBridgeDispatcher.InstallRequest);
        var invalid = new[] {
            request with { Name = "onboarding.onlineInstallation.finish" },
            request with { AccountContext = new("test", "scm", "invented") },
            request with { SessionGeneration = request.SessionGeneration + 1 },
            request with { Payload = JsonSerializer.SerializeToElement(new { schemaVersion = 2, revision = 3 }) },
            request with { Payload = JsonSerializer.SerializeToElement(new { schemaVersion = 1, revision = 3, installed = true }) },
            request with { Payload = JsonDocument.Parse("{\"schemaVersion\":1,\"revision\":3,\"revision\":3}").RootElement.Clone() },
            InstallationRequest(native, request.Name, revision: -1),
            InstallationRequest(native, request.Name, revision: 2)
        };
        foreach (var bad in invalid.Append(request))
            Check((await route.DispatchAsync(bad)).Response.Status != BridgeResponseStatuses.Ok, "Strict installation refusal.");
        var read = InstallationPayload(await route.DispatchAsync(InstallationRequest(native,
            FirstUseOnlineInstallationBridgeDispatcher.ReadRequest)));
        Check(read.GetProperty("phase").GetString() == "idle" && f.Coordinator.Reads == 0 && c.Images.Count == 0,
            "Read/authentication alone cannot prepare or install business.");
        Check(!BridgeRequestPolicy.RequiresAccountContext(request.Name) &&
            !BridgeRequestPolicy.RequiresAccountContext(FirstUseOnlineInstallationBridgeDispatcher.ReadRequest) &&
            BridgeRequestPolicy.RequiresAccountContext("onboarding.onlineInstallation.finish"), "Only exact control names are accountless.");
        f.Quiet();
    }

    private static async Task InstallationWireFresh()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        using var c = new CompositionFixture(f, native);
        using var preferences = new ApplicationPreferencesBridgeDispatcher(f.Original.Local.Root, () => native.Generation);
        using var host = new InstallationNoopDispatcher();
        using var composite = new CompositeBridgeDispatcher(host, native, preferences,
            firstUseOnlineInstallation: native.CreateOnlineInstallationDispatcher(c.Composition));
        var request = InstallationRequest(native, FirstUseOnlineInstallationBridgeDispatcher.InstallRequest);
        var result = await Finish(composite.DispatchAsync(request).AsTask());
        var payload = InstallationPayload(result);
        Check(result.Response.SessionGeneration == request.SessionGeneration && result.Response.CorrelationId == request.CorrelationId &&
            payload.GetProperty("controlGeneration").GetInt64() == native.Generation && native.Generation > request.SessionGeneration &&
            payload.GetProperty("phase").GetString() == "completed" && payload.GetProperty("modeState").GetString() == "online" &&
            payload.GetProperty("modeRevision").GetInt64() == 4 && c.Images.Count == 3 && c.Observers.Count == 1 && f.Original.Clock.Timers == 7,
            "Real Composite route bypasses the retired lease and consumes real composition once, preserving original response generation.");
        Check((await composite.DispatchAsync(InstallationRequest(native, FirstUseOnlineInstallationBridgeDispatcher.InstallRequest)))
            .Response.Status != BridgeResponseStatuses.Ok, "Completed installation cannot replay old confirmation.");
        Check(InstallationPayload(await composite.DispatchAsync(InstallationRequest(native,
            FirstUseOnlineInstallationBridgeDispatcher.ReadRequest))).GetProperty("modeState").GetString() == "online",
            "Fresh control generation rereads the actual completed attempt.");
        Check((await composite.DispatchAsync(request)).Response.Status != BridgeResponseStatuses.Ok,
            "Old generation cannot start another installation.");
        Check((await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Id(), native.Generation,
            new { schemaVersion = 1 }))).Response.Status == BridgeResponseStatuses.Ok, "Installed account requires its separate real read.");
        await native.DisposeAsync(); // Device sinks remain alive until original consumers physically exit.
    }

    private static async Task InstallationWireObserver()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start(); f.Coordinator.Hold = true;
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        using var c = new CompositionFixture(f, native);
        using var route = native.CreateOnlineInstallationDispatcher(c.Composition)!;
        using var token = new CancellationTokenSource();
        var request = InstallationRequest(native, FirstUseOnlineInstallationBridgeDispatcher.InstallRequest);
        var leaving = route.DispatchAsync(request, token.Token).AsTask(); await Finish(f.Coordinator.Entered.Task);
        token.Cancel();
        Check((await Finish(leaving)).Response.Status == BridgeResponseStatuses.Cancelled && !f.Coordinator.Token.IsCancellationRequested,
            "Transport observer cancellation is not physical or mode cancellation.");
        Check(InstallationPayload(await route.DispatchAsync(InstallationRequest(native, FirstUseOnlineInstallationBridgeDispatcher.ReadRequest)))
            .GetProperty("phase").GetString() == "running", "Polling must not relabel held original IO as completed.");
        var joined = route.DispatchAsync(InstallationRequest(native, request.Name)).AsTask();
        Check(!joined.IsCompleted && c.Images.Count == 0 && f.Coordinator.Reads == 1, "Duplicate observer joins one physical attempt.");
        f.Coordinator.Release.TrySetResult();
        Check(InstallationPayload(await Finish(joined)).GetProperty("modeState").GetString() == "online" && c.Images.Count == 3,
            "One actual composition after original IO exit.");
        await native.DisposeAsync();
    }

    private static async Task InstallationWireFailure()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        using var c = new CompositionFixture(f, native) { FailActivity = true };
        using var route = native.CreateOnlineInstallationDispatcher(c.Composition)!;
        var payload = InstallationPayload(await Finish(route.DispatchAsync(InstallationRequest(native,
            FirstUseOnlineInstallationBridgeDispatcher.InstallRequest)).AsTask()));
        Check(payload.GetProperty("phase").GetString() == "completed" && payload.GetProperty("modeState").GetString() == "local" &&
            c.Images.All(p => p.Disposed) && f.Original.Clock.Timers == 0 &&
            native.Read(owner => ReferenceEquals(owner, f.Original.Local.Runtime), false),
            "Protocol completion only means physical task exit; failed install recovers exact local owner.");
        Check(payload.TryGetProperty("failure", out var failure) &&
            failure.EnumerateObject().Count() == 2 &&
            failure.GetProperty("stage").GetString() == "configureBusiness" &&
            failure.GetProperty("kind").GetString() == "storage",
            "Failed restoration must retain a bounded stage and category after local recovery.");
        Check(!payload.GetRawText().Contains("Synthetic activity allocation failure", StringComparison.Ordinal),
            "Diagnostic must not publish exception text or private payloads.");
        f.Original.Local.RequireLocalStateUnchanged();
    }

    private static async Task InstallationWireStale()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        using var c = new CompositionFixture(f, native);
        using var route = native.CreateOnlineInstallationDispatcher(c.Composition)!;
        await Finish(route.DispatchAsync(InstallationRequest(native, FirstUseOnlineInstallationBridgeDispatcher.InstallRequest)).AsTask());
        await Finish(f.Original.Mode.ApplyOfflineAsync(4, Id(), native.Generation));
        Check((await route.DispatchAsync(InstallationRequest(native, FirstUseOnlineInstallationBridgeDispatcher.ReadRequest)))
            .Response.Status != BridgeResponseStatuses.Ok, "Old online receipt cannot cover a newer physical offline decision.");
        Check(InstallationPayload(await route.DispatchAsync(InstallationRequest(native,
            FirstUseOnlineInstallationBridgeDispatcher.ReadRequest, revision: 6))).GetProperty("phase").GetString() == "idle",
            "New intent has no installation grant or inherited old success.");
    }

    private static async Task InstallationWireDisposed()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start(); f.Coordinator.Hold = true;
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        using var c = new CompositionFixture(f, native);
        using var route = native.CreateOnlineInstallationDispatcher(c.Composition)!;
        var pending = route.DispatchAsync(InstallationRequest(native, FirstUseOnlineInstallationBridgeDispatcher.InstallRequest)).AsTask();
        await Finish(f.Coordinator.Entered.Task); route.Dispose(); f.Coordinator.Release.TrySetResult();
        Check((await Finish(pending)).Response.Status != BridgeResponseStatuses.Ok && f.Original.Mode.Current.State == "online",
            "Closing borrowed observer does not abandon physical installation or publish late success.");
        await native.DisposeAsync();
    }

    private sealed class InstallationNoopDispatcher : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default) =>
            throw new InvalidOperationException("Control route escaped to unrelated lifecycle owner.");
        public void Dispose() { }
    }
}

