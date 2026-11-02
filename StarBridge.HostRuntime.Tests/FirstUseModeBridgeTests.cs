using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

internal static partial class FirstUseModeTests
{
    internal static async Task RunModeBridge()
    {
        await Case("mode bridge observes ordinary readiness without credentials or retirement", ModeBridgeRead);
        await Case("composed mode bridge exits actual Native leases without holding its own account lease", ModeBridgeOffline);
        await Case("mode bridge rejects malformed stale and account-scoped writes before effects", ModeBridgeGuards);
        await Case("mode bridge observer cancellation retains original physical exit and durable intent", ModeBridgeCancel);
        await Case("mode bridge final write failure exposes recovery instead of offline readiness", ModeBridgeFailure);
        await Case("mode bridge borrowed disposal cannot close account or device ownership", ModeBridgeDispose);
        await Case("real connection orders mixed owner events without changing generation or account identity", ModeConnectionSequence);
        await Case("device payload serialization cannot relabel a callback after mode closure", ModeDeviceEpochChange);
    }

    private static BridgeEnvelope ModeRequest(FirstUseModeRuntime mode, string name, object payload) =>
        BridgeEnvelope.Request(name, Op(), mode.ControlGeneration, payload);
    private static BridgeEnvelope OfflineRequest(FirstUseModeRuntime mode, long revision = 0) =>
        ModeRequest(mode, FirstUseModeBridgeDispatcher.OfflineRequest, new { schemaVersion = 1, revision });
    private static async Task ModeBridgeRead()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true); var mode = await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        using var bridge = native.CreateModeDispatcher()!;
        var batch = await bridge.DispatchAsync(ModeRequest(mode, FirstUseModeBridgeDispatcher.ReadRequest, new { schemaVersion = 1 }));
        var body = batch.Response.Payload;
        Require(batch.Response.Status == "ok" && body.EnumerateObject().Count() == 6 &&
            body.GetProperty("state").GetString() == "online" && body.GetProperty("canEnterOffline").GetBoolean() &&
            body.GetProperty("activeMode").GetString() == "online" && !body.GetProperty("publicationSuspended").GetBoolean(),
            "Fixed mode projection reports the real original owner");
        Require(batch.Response.AccountContext is null && batch.Events.Count == 0 &&
            f.Vault.Loads == 0 && f.Vault.Deletions == 0 && new FirstUseModeStore(f.Root).Read().Revision == 0,
            "Read never authenticates, reads credentials or writes a choice");
    }

    private static async Task ModeBridgeOffline()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true); var mode = await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        using var bridge = native.CreateModeDispatcher()!;
        using var composite = new CompositeBridgeDispatcher(new ModeProbe(), native, new ModeProbe(), firstUseMode: bridge);
        var batch = await composite.DispatchAsync(OfflineRequest(mode)).AsTask().WaitAsync(TimeSpan.FromSeconds(5));
        Require(batch.Response.Status == "ok" && batch.Response.Payload.GetProperty("state").GetString() == "offline" &&
            batch.Response.Payload.GetProperty("publicationSuspended").GetBoolean() &&
            !batch.Response.Payload.GetProperty("canEnterOffline").GetBoolean() && mode.LocalMode().Active &&
            native.Read(owner => ReferenceEquals(owner, f.Runtime), false), "Composed real lifecycle completes and reconstructs local Native");
        Require(f.Vault.Loads == 0 && f.Vault.Deletions == 0, "Offline is not logout or implicit credential restore");
        Require((await composite.DispatchAsync(OfflineRequest(mode, 2))).Response.Error?.Code == "firstUse.context_changed",
            "A second offline write cannot invent another transition");
    }

    private static async Task ModeBridgeGuards()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true); var mode = await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        using var bridge = native.CreateModeDispatcher()!;
        using var duplicate = JsonDocument.Parse("{\"schemaVersion\":1,\"revision\":0,\"revision\":0}");
        foreach (var request in new[] {
            OfflineRequest(mode, 1), OfflineRequest(mode) with { SessionGeneration = mode.ControlGeneration + 1 },
            OfflineRequest(mode) with { AccountContext = f.Host.CurrentContext },
            ModeRequest(mode, FirstUseModeBridgeDispatcher.OfflineRequest, new { schemaVersion = 2, revision = 0 }),
            ModeRequest(mode, FirstUseModeBridgeDispatcher.OfflineRequest, new { schemaVersion = 1, revision = 0, token = "synthetic" }),
            ModeRequest(mode, FirstUseModeBridgeDispatcher.OfflineRequest, duplicate.RootElement.Clone()),
            ModeRequest(mode, "onboarding.mode.resume", new { schemaVersion = 1, revision = 0 })
        }) Require((await bridge.DispatchAsync(request)).Response.Status == "error", "Invalid mode input rejected");
        Require(mode.Current.State == "online" && new FirstUseModeStore(f.Root).Read().Revision == 0 &&
            native.Generation == f.Host.Generation && f.Vault.Loads == 0 && f.Vault.Deletions == 0,
            "Rejected protocol cannot select identity, retire runtime or access credentials");
    }

    private static async Task ModeBridgeCancel()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true); var mode = await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        using var bridge = native.CreateModeDispatcher()!;
        var release = RootSignal(); var cancelled = RootSignal();
        var read = native.ReadAsync(async (_, token) =>
        { using var registration = token.Register(() => cancelled.TrySetResult()); await release.Task; return true; });
        using var observer = new CancellationTokenSource();
        var work = bridge.DispatchAsync(OfflineRequest(mode), observer.Token).AsTask();
        try
        {
            await cancelled.Task.WaitAsync(TimeSpan.FromSeconds(5)); observer.Cancel();
            Require((await work.WaitAsync(TimeSpan.FromSeconds(5))).Response.Status == BridgeResponseStatuses.Cancelled &&
                new FirstUseModeStore(f.Root).Read().Phase == "offlinePending" && !mode.LocalMode().Active,
                "Cancelled pipe wait cannot abandon or acknowledge the physical transition");
            var state = await bridge.DispatchAsync(ModeRequest(mode, FirstUseModeBridgeDispatcher.ReadRequest, new { schemaVersion = 1 }));
            Require(state.Response.Payload.GetProperty("state").GetString() == "switching" &&
                !state.Response.Payload.GetProperty("canEnterOffline").GetBoolean(), "Independent mode read remains usable during Native drain");
        }
        finally { release.TrySetResult(); await Cancelled(read); }
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        while (mode.Current.State == "switching") await Task.Delay(10, deadline.Token);
        Require(mode.Current.State == "offline" && mode.LocalMode().Active && f.Vault.Deletions == 0,
            "Original transition finishes after its observer has left");
    }

    private static async Task ModeBridgeFailure()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true); var mode = await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        using var bridge = native.CreateModeDispatcher()!;
        var release = RootSignal(); var cancelled = RootSignal();
        var read = native.ReadAsync(async (_, token) =>
        { using var registration = token.Register(() => cancelled.TrySetResult()); await release.Task; return true; });
        var work = bridge.DispatchAsync(OfflineRequest(mode)).AsTask();
        try
        {
            await cancelled.Task.WaitAsync(TimeSpan.FromSeconds(5));
            using var writer = new FileStream(ModePath(f.Root) + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None);
            release.TrySetResult(); await Cancelled(read);
            var batch = await work.WaitAsync(TimeSpan.FromSeconds(5));
            Require(batch.Response.Status == "ok" && batch.Response.Payload.GetProperty("state").GetString() == "recoveryRequired" &&
                !batch.Response.Payload.GetProperty("canEnterOffline").GetBoolean() && !mode.LocalMode().Active && f.Vault.Deletions == 0,
                "Protocol success transports actual recovery, not a successful mode switch");
        }
        finally { release.TrySetResult(); try { await read; } catch (OperationCanceledException) { } }
    }

    private static async Task ModeBridgeDispose()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true); var mode = await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        var bridge = native.CreateModeDispatcher()!; bridge.Dispose();
        Require((await bridge.DispatchAsync(OfflineRequest(mode))).Response.Error?.Code == "firstUse.context_changed" &&
            mode.Current.State == "online" && native.Generation == f.Host.Generation && f.Vault.Deletions == 0,
            "Borrowed dispatcher disposal only revokes that route");
    }

    private static async Task ModeDeviceEpochChange()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true); var mode = await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        var generation = native.Generation;
        var payload = new ModeClosingPayload(mode.Close);
        try
        {
            native.DeviceUpdateProgress(generation, payload);
            throw new InvalidOperationException("Closed mode callback escaped serialization.");
        }
        catch (OperationCanceledException) { }
        Require(payload.Reads == 1 && mode.ControlGeneration == -1 && f.Vault.Deletions == 0,
            "Actual mode closure during payload serialization rejects, never retags or signs out");
    }

    private sealed class ModeClosingPayload(Action close)
    {
        [System.Text.Json.Serialization.JsonIgnore] public int Reads { get; private set; }
        public int SchemaVersion { get { Reads++; close(); return 1; } }
    }

    private sealed class ModeProbe : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default) =>
            throw new InvalidOperationException("Mode control incorrectly reached an unrelated route.");
        public void Dispose() { }
    }

    private static async Task ModeConnectionSequence()
    {
        var pair = InMemoryBridgeConnection.CreatePair();
        using var dispatcher = new ModeEventProbe();
        using var lifetime = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var server = NativeHostPipeServer.ServeConnectionAsync(pair.Right, dispatcher, lifetime.Token);
        try
        {
            await pair.Left.SendAsync(BridgeEnvelope.Request("synthetic.sequence", Op(), 7), lifetime.Token);
            var messages = new List<BridgeEnvelope>();
            await foreach (var envelope in pair.Left.ReadAllAsync(lifetime.Token))
            {
                messages.Add(envelope);
                if (messages.Count == 4) break;
            }
            Require(messages[0].MessageType == BridgeMessageTypes.Response &&
                messages.Skip(1).Select(item => item.Sequence).SequenceEqual(new long?[] { 1, 2, 3 }),
                "One actual connection sequences response-batch events, not independent owner counters");
            Require(messages[1].SessionGeneration == 7 && messages[2].SessionGeneration == 7 &&
                messages[3].SessionGeneration == 3 && messages[3].AccountContext == ModeEventProbe.OldAccount,
                "Transport sequencing cannot relabel a stale account event as current device authority");
        }
        finally
        {
            lifetime.Cancel(); await pair.Left.DisposeAsync();
            try { await server; } catch (OperationCanceledException) { }
            await pair.Right.DisposeAsync();
        }
    }

    private sealed class ModeEventProbe : IBridgeRequestDispatcher
    {
        internal static readonly BridgeAccountContext OldAccount = new("synthetic", "synthetic", "synthetic-old");
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default) =>
            ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.Response(request), [
                BridgeEnvelope.Event("synthetic.account", 7, 900),
                BridgeEnvelope.Event("synthetic.device", 7, 0),
                BridgeEnvelope.Event("synthetic.stale", 3, 1) with { AccountContext = OldAccount }
            ]));
        public void Dispose() { }
    }
}
