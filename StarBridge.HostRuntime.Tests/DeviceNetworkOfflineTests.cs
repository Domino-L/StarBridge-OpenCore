using System.Net;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Tools;
using StarBridge.HostRuntime.Updates;
using StarBridge.Core.Tools;

internal static class DeviceNetworkOfflineTests
{
    internal static async Task Run()
    {
        await OfflineRoutes();
        foreach (var kind in new[] { "support", "supportBody", "diagnostic", "update", "tool" }) await HeldExit(kind, false);
        await HeldExit("support", true);
        await SavedTool();
        await OfflineReminder();
        await AdmissionEpoch();
        await FirstUseBusinessOwnerTests.RunDeviceNetworkResume();
    }
    private static async Task OfflineRoutes()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture();
        await f.PrepareOrdinary();
        await using var native = new NativeAccountRuntimeBinding(f.Local.Runtime);
        var offline = await f.Mode.ApplyManualOfflineAsync(0, Guid.NewGuid().ToString("N"), native, default).WaitAsync(TimeSpan.FromSeconds(5));
        Check(offline.State == "offline", "Original signed-in root must actually retain login and enter offline");
        using var transport = new Transport();
        var opened = 0;
        using var support = new HelpSupportBridgeDispatcher(new Uri("https://synthetic-support.example.invalid/"), () => native.Generation, transport,
            openScm: () => opened++, network: f.Local.Runtime.DeviceNetwork);
        BridgeEnvelope Request(string name, object? body = null) => BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), native.Generation, body ?? new { schemaVersion = 1 });
        var result = await support.DispatchAsync(Request("helpSupport.stats"));
        Check(result.Response.Status != "ok" && transport.Calls == 0, "Confirmed manual offline must not send anonymous device-owned stats HTTP");
        var history = await support.DispatchAsync(Request("helpSupport.history"));
        Check(history.Response.Status == "ok" && transport.Calls == 0, "Offline keeps bundled history without contacting a service");
        await support.DispatchAsync(Request("helpSupport.feedback", new { schemaVersion = 1, contact = "", message = "synthetic" }));
        await support.DispatchAsync(Request("helpSupport.openScm"));
        var diagnostic = await DiagnosticConnectionProbe.CheckAsync(new Uri("https://synthetic-support.example.invalid/"), default,
            transport, f.Local.Runtime.DeviceNetwork);
        Check(diagnostic.Detail == "connectionPaused" && transport.Calls == 0, "Offline diagnostics reports an unperformed probe, not server failure");
        Check(opened == 0, "Offline cannot launch an online support action; unrelated browser windows are not touched");
        using var update = new Update(); var ready = 0;
        using var updates = new FlutterUpdateBridgeDispatcher(update, () => "0.7.1", () => native.Generation,
            firstFrameReady: () => ready++, network: f.Local.Runtime.DeviceNetwork);
        Check((await updates.DispatchAsync(Request("applicationUpdates.check"))).Response.Status != "ok" && update.Calls == 0,
            "Confirmed offline cannot issue update HTTP");
        Check((await updates.DispatchAsync(Request("applicationUpdates.firstFrameReady"))).Response.Status == "ok" && ready == 1,
            "Local startup receipt remains available offline");
        using var tool = new ExecHangarRuntime(f.Local.Root, new Config(), (_, _) => ValueTask.FromResult("submitted"), network: f.Local.Runtime.DeviceNetwork);
        Check((await tool.ReadAsync(true)).Config is null && transport.Calls == 0, "Cold offline tool does not fetch its missing configuration");
        Console.WriteLine("PASS confirmed offline suppresses device-owned network while retaining local support");
    }
    private static async Task HeldExit(string kind, bool close)
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await f.PrepareOrdinary();
        await using var native = new NativeAccountRuntimeBinding(f.Local.Runtime);
        var isSupport = kind.StartsWith("support", StringComparison.Ordinal);
        var isHttp = isSupport || kind == "diagnostic";
        using var transport = new Transport { Hold = kind is "support" or "diagnostic", HoldBody = kind == "supportBody" };
        using var support = new HelpSupportBridgeDispatcher(new Uri("https://synthetic-support.example.invalid/"), () => native.Generation, transport,
            network: f.Local.Runtime.DeviceNetwork);
        using var source = new Update { Hold = true };
        using var updates = new FlutterUpdateBridgeDispatcher(source, () => "0.7.1", () => native.Generation, network: f.Local.Runtime.DeviceNetwork);
        var config = new Config { Hold = true };
        using var tool = new ExecHangarRuntime(f.Local.Root, config, (_, _) => ValueTask.FromResult("submitted"), network: f.Local.Runtime.DeviceNetwork);
        BridgeEnvelope Request(string name) => BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), native.Generation, new { schemaVersion = 1 });
        Task pending = kind switch {
            "support" or "supportBody" => support.DispatchAsync(Request("helpSupport.stats")).AsTask(),
            "diagnostic" => DiagnosticConnectionProbe.CheckAsync(new Uri("https://synthetic-support.example.invalid/"), default, transport, f.Local.Runtime.DeviceNetwork),
            "update" => updates.DispatchAsync(Request("applicationUpdates.check")).AsTask(),
            _ => tool.ReadAsync(true)
        };
        var entered = isHttp ? transport.Entered : kind == "update" ? source.Entered : config.Entered;
        var canceled = isHttp ? transport.Canceled : kind == "update" ? source.Canceled : config.Canceled;
        var release = isHttp ? transport.Release : kind == "update" ? source.Release : config.Release;
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var vault = File.ReadAllBytes(f.VaultPath);
        var offline = close ? null : f.Mode.ApplyManualOfflineAsync(0, Guid.NewGuid().ToString("N"), native, default);
        var exit = close ? native.DisposeAsync().AsTask() : offline!;
        try
        {
            await canceled.Task.WaitAsync(TimeSpan.FromSeconds(3));
            Check(!exit.IsCompleted && !pending.IsCompleted, "Original " + kind + " operation must actually exit before offline/close acknowledges");
            Check((await support.DispatchAsync(Request("helpSupport.stats"))).Response.Status != "ok", "New device work is denied while draining");
            release.TrySetResult(); await pending.WaitAsync(TimeSpan.FromSeconds(5)); await exit.WaitAsync(TimeSpan.FromSeconds(5));
            if (offline is not null) Check((await offline).State == "offline", "Actual shared exit permits offline receipt");
            Check(vault.SequenceEqual(File.ReadAllBytes(f.VaultPath)), "Device drain does not delete retained credentials");
            if (kind == "update") Check(((Task<BridgeDispatchBatch>)pending).Result.Response.Status != "ok", "Late update result cannot remain usable offline");
            if (isSupport) Check(((Task<BridgeDispatchBatch>)pending).Result.Response.Status != "ok", "Late support result cannot remain usable offline");
            if (kind == "diagnostic") Check(((Task<ApplicationSupportCheck>)pending).Result.Detail == "connectionPaused", "Late health reply cannot claim a connection check during offline transition");
            if (kind == "tool") Check(((Task<ExecHangarSnapshot>)pending).Result.Config is null && !File.Exists(Path.Combine(f.Local.Root, "exec-hangar.v1.json")),
                "Late calibration cannot become a saved local schedule");
        }
        finally { release.TrySetResult(); }
        Console.WriteLine($"PASS device network {kind}: original held exit, late-result refusal and retained credentials ({(close ? "close" : "offline")})");
    }
    private static async Task SavedTool()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await f.PrepareOrdinary();
        await using var native = new NativeAccountRuntimeBinding(f.Local.Runtime);
        var config = new Config();
        using var tool = new ExecHangarRuntime(f.Local.Root, config, (_, _) => ValueTask.FromResult("submitted"), network: f.Local.Runtime.DeviceNetwork);
        var saved = await tool.ReadAsync(true);
        var path = Path.Combine(f.Local.Root, "exec-hangar.v1.json"); var bytes = File.ReadAllBytes(path);
        await f.Mode.ApplyManualOfflineAsync(0, Guid.NewGuid().ToString("N"), native, default);
        var local = await tool.ReadAsync(true);
        Check(config.Calls == 1 && local.Config == saved.Config && bytes.SequenceEqual(File.ReadAllBytes(path)),
            "Offline keeps saved calibration without revalidation, cache replacement or a fake fetch timestamp");
        Console.WriteLine("PASS offline tool retains saved calibration without networking or cache rewrite");
    }
    private static async Task OfflineReminder()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await f.PrepareOrdinary();
        await using var native = new NativeAccountRuntimeBinding(f.Local.Runtime);
        var time = new Clock(); var config = new Config { Value = new("fixture", "fixture", null, time.Now, 0, 65, 120, 0) };
        var delivered = 0;
        using var tool = new ExecHangarRuntime(f.Local.Root, config, (delivery, _) => {
            Check(delivery.IsCurrent(), "Offline local reminder keeps original device authority"); delivered++; return ValueTask.FromResult("submitted");
        }, time, network: f.Local.Runtime.DeviceNetwork);
        var before = await tool.ReadAsync(true);
        await tool.SaveAsync(new(true), before.Revision, () => true);
        await f.Mode.ApplyManualOfflineAsync(0, Guid.NewGuid().ToString("N"), native, default);
        time.Advance(TimeSpan.FromMinutes(180).Add(TimeSpan.FromSeconds(-1))); await tool.TickAsync();
        time.Advance(TimeSpan.FromSeconds(1)); await tool.TickAsync();
        Check(delivered == 1 && config.Calls == 1 && (await tool.ReadAsync()).Reminders.Enabled,
            "Offline preserves a real local scheduled reminder without remote calibration or setting changes");
        Console.WriteLine("PASS offline actual device reminder still delivers from saved calibration without network");
    }
    private static async Task AdmissionEpoch()
    {
        var allowed = true;
        var network = new StarBridge.HostRuntime.Lifecycle.DeviceNetworkAdmission(() => allowed);
        var lease = network.Enter()!;
        allowed = false;
        var exit = network.PauseAsync();
        Check(!lease.IsCurrent && !exit.IsCompleted && network.Enter() is null, "Revoked epoch denies new work and waits original lease");
        allowed = true;
        Check(network.Enter() is null, "Permission returning cannot bypass physical old epoch exit");
        lease.Dispose(); await exit;
        using var next = network.Enter()!;
        Check(next.IsCurrent && !lease.IsCurrent, "New epoch never revives a disposed original lease");
        var final = network.RetireAsync(); Check(!final.IsCompleted && network.Enter() is null, "Total retirement cannot re-admit online work");
        next.Dispose(); await final;
        var unknown = new StarBridge.HostRuntime.Lifecycle.DeviceNetworkAdmission(() => throw new Exception("Synthetic unreadable mode"));
        Check(unknown.Enter() is null, "Mode read failure is not online admission"); await unknown.RetireAsync();
        Console.WriteLine("PASS device admission keeps exact epochs, physical drain, late guards and fail-closed mode reads");
    }
    internal static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    internal sealed class Transport : HttpMessageHandler
    {
        internal int Calls;
        internal bool Hold, HoldBody;
        internal readonly TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously),
            Canceled = new(TaskCreationOptions.RunContinuationsAsynchronously), Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++; if (!HoldBody) Entered.TrySetResult(); using var cancel = token.Register(() => Canceled.TrySetResult());
            if (Hold) await Release.Task; // Intentionally ignore cancellation.
            const string json = "{\"downloadCount\":5,\"onlineUserCount\":2,\"fleetCount\":3,\"overlayUsageSeconds\":0,\"updatedAt\":\"2026-01-01T00:00:00Z\"}";
            return new(HttpStatusCode.OK) { Content = HoldBody ? new StreamContent(new HeldStream(System.Text.Encoding.UTF8.GetBytes(json), this)) : new StringContent(json) };
        }
    }
    private sealed class HeldStream(byte[] bytes, Transport transport) : MemoryStream(bytes)
    {
        private bool _entered;
        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken token = default)
        {
            if (!_entered)
            {
                _entered = true; transport.Entered.TrySetResult();
                using var cancelled = token.Register(() => transport.Canceled.TrySetResult());
                await transport.Release.Task; // Deliberately ignore cancellation even during content read.
            }
            return await base.ReadAsync(buffer, CancellationToken.None);
        }
    }
    internal sealed class Update : IApplicationUpdateSource
    {
        internal int Calls; internal bool Hold;
        internal readonly TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously),
            Canceled = new(TaskCreationOptions.RunContinuationsAsynchronously), Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public async Task<ApplicationUpdateCheck> CheckForUpdateAsync(CancellationToken token)
        { Calls++; Entered.TrySetResult(); using var cancel = token.Register(() => Canceled.TrySetResult()); if (Hold) await Release.Task; return new("current"); }
        public void Dispose() { Release.TrySetResult(); }
    }
    private sealed class Config : IExecHangarConfigClient
    {
        internal int Calls; internal bool Hold;
        internal ExecHangarConfig? Value;
        internal readonly TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously),
            Canceled = new(TaskCreationOptions.RunContinuationsAsynchronously), Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public async Task<ExecHangarConfig> FetchAsync(CancellationToken token)
        { Calls++; Entered.TrySetResult(); using var cancel = token.Register(() => Canceled.TrySetResult()); if (Hold) await Release.Task; return Value ?? new("fixture", "fixture", null, DateTimeOffset.UtcNow.AddHours(-1), 0, 65, 120, 0); }
    }
    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = new(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
        private long _stamp;
        public override DateTimeOffset GetUtcNow() => Now;
        public override long GetTimestamp() => _stamp;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        internal void Advance(TimeSpan duration) { Now += duration; _stamp += duration.Ticks; }
    }
}
