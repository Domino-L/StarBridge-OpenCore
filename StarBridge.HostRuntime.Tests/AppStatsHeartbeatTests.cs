using System.Net;
using StarBridge.Core.Presence;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Lifecycle;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Support;

internal static class AppStatsHeartbeatTests
{
    internal static (string Name, Func<Task> Test)[] Cases =>
    [
        ("App stats heartbeat discards its unknown startup interval", FirstSample),
        ("App stats heartbeat detects an offline epoch entirely between ticks", EpochRoundtrip),
        ("App stats heartbeat mixed relays never reveal hidden devices or replay skipped usage", MixedRelays),
        ("App stats heartbeat shares capability with the home GET", SharedCapability),
        ("App stats heartbeat physical network failures discard new usage only", PhysicalNetwork),
        ("App stats heartbeat uses actual accepted seconds with legacy fallback", Acknowledgement),
        ("App stats heartbeat counts hidden usage without counting hidden clients online", Visibility),
        ("App stats heartbeat handles network changes during a request", SwitchDuringRequest),
        ("App stats heartbeat visibility changes preserve acknowledgements and usage", VisibilityDuringRequest),
        ("App stats heartbeat caps a new sample at 300 seconds", Splits),
        ("App stats heartbeat retries failed deltas", Retries),
        ("App stats heartbeat discards offline samples and preserves prior pending", Offline),
        ("App stats heartbeat caps pending usage at 300 seconds", Cap),
        ("App stats heartbeat reuses Desktop client ID", ExistingId),
        ("App stats heartbeat repairs invalid client IDs", InvalidIds),
        ("App stats heartbeat concurrent client ID creation converges", ConcurrentId),
        ("App stats heartbeat preserves a concurrent Desktop client ID writer", ConcurrentWriter),
        ("App stats heartbeat null meter still sends online heartbeat", NullMeter),
        ("App stats heartbeat timer starts at 30 seconds and stops on disposal", TimerLifecycle),
        ("App stats heartbeat times out without overlapping requests", Timeout),
        ("App stats heartbeat device lease cancels actual HTTP work", LeaseCancellation),
        ("App stats heartbeat disposal cancels without final flush", Disposal),
        ("App stats heartbeat storage failure stays local and retains usage", StorageFailure)
    ];

    private static async Task EpochRoundtrip()
    {
        using var f = new Fixture();
        using var runtime = f.Create();
        await runtime.HeartbeatAsync();
        f.Online = false;
        await f.Network.PauseAsync();
        f.Online = true;
        f.Meter.Seconds = 30;
        await runtime.HeartbeatAsync();
        f.Meter.Seconds = 7;
        await runtime.HeartbeatAsync();
        f.Deltas(0, 0, 7);
    }

    private static async Task FirstSample()
    {
        foreach (var offline in new[] { false, true })
        {
            using var f = new Fixture();
            using var runtime = f.Create();
            if (offline) { f.Online = false; await f.Network.PauseAsync(); f.Online = true; }
            f.Meter.Seconds = 30;
            await runtime.HeartbeatAsync();
            f.Meter.Seconds = 7;
            await runtime.HeartbeatAsync();
            f.Deltas(0, 7);
        }
    }

    private static async Task MixedRelays()
    {
        foreach (var cachedModern in new[] { false, true })
        {
            using var f = new Fixture();
            f.Visibility = PlayerPresenceVisibilityMode.Invisible;
            f.Handler.Legacy = !cachedModern;
            using var runtime = f.Create();
            await runtime.HeartbeatAsync();
            f.Handler.Legacy = true;
            f.Handler.Bodies.Clear();
            f.Meter.Seconds = 30;
            await runtime.HeartbeatAsync();
            f.Meter.Seconds = 9;
            await runtime.HeartbeatAsync();
            Check(f.Handler.Bodies.Count == 0 && f.Handler.Probes == 0,
                "cold or cached modern hidden client never reaches a legacy heartbeat handler or GET probe");
            f.Visibility = PlayerPresenceVisibilityMode.Online;
            f.Meter.Seconds = 7;
            await runtime.HeartbeatAsync();
            f.Deltas(7);
            Check(f.Handler.Bodies.Single().GetProperty("protocol").GetInt32() == 1,
                "visible legacy fallback uses whole-request v1 semantics");
            await runtime.HeartbeatAsync();
            f.Deltas(7, 0);
            f.Visibility = PlayerPresenceVisibilityMode.Invisible;
            f.Handler.Legacy = false;
            f.Time.Advance(599);
            f.Meter.Seconds = 30;
            await runtime.HeartbeatAsync();
            f.Deltas(7, 0);
            f.Time.Advance(1);
            f.Meter.Seconds = 8;
            await runtime.HeartbeatAsync();
            f.Deltas(7, 0, 8);
            Check(!f.Handler.Bodies.Last().GetProperty("countOnline").GetBoolean() &&
                f.Handler.Paths.Last() == "/api/app-stats/v2/heartbeat", "upgrade recovers hidden v2 usage at ten minutes");
        }
        using var online = new Fixture();
        online.Handler.Legacy = true;
        using var host = online.Create();
        await host.HeartbeatAsync();
        Check(online.Handler.Paths.SequenceEqual(new[] { "/api/app-stats/v2/heartbeat", "/api/app-stats/heartbeat" }),
            "new route is always attempted before learning legacy fallback");
    }

    private static async Task SharedCapability()
    {
        using var f = new Fixture();
        var capability = new AppStatsHeartbeatRuntime.RelayCapability();
        f.Visibility = PlayerPresenceVisibilityMode.Invisible;
        using var runtime = f.Create(capability: capability);
        await runtime.HeartbeatAsync();
        f.Handler.Bodies.Clear();
        f.Handler.Status = HttpStatusCode.ServiceUnavailable;
        f.Meter.Seconds = 40;
        await runtime.HeartbeatAsync();
        f.Handler.Status = HttpStatusCode.OK;
        f.Handler.Legacy = true;
        f.Meter.Seconds = 30;
        await runtime.HeartbeatAsync();
        using var home = new HelpSupportBridgeDispatcher(new Uri("http://127.0.0.1/"), () => 1, f.Handler,
            network: f.Network, appStatsCapability: capability);
        await home.DispatchAsync(StarBridge.NativeBridge.BridgeEnvelope.Request(
            "helpSupport.stats", Guid.NewGuid().ToString(), 1, new { schemaVersion = 1 }));
        f.Meter.Seconds = 30;
        await runtime.HeartbeatAsync();
        f.Deltas(40); // A GET claiming v2 cannot override the route's 404.
        f.Handler.Legacy = false;
        f.Time.Advance(600);
        f.Meter.Seconds = 7;
        await runtime.HeartbeatAsync();
        f.Deltas(40, 47); // Keep legal pending; never replay discarded hidden seconds.
    }

    private static async Task PhysicalNetwork()
    {
        foreach (var failure in new Exception[] { new HttpRequestException(), new TaskCanceledException(), new OperationCanceledException(), new IOException() })
        {
            using var f = new Fixture();
            using var runtime = f.Create();
            await runtime.HeartbeatAsync();
            f.Handler.Bodies.Clear();
            f.Meter.TakeCalls = 0;
            f.Handler.Status = HttpStatusCode.ServiceUnavailable;
            f.Meter.Seconds = 40;
            await runtime.HeartbeatAsync();
            f.Handler.Status = HttpStatusCode.OK;
            f.Handler.Failure = failure;
            f.Meter.Seconds = 60;
            await runtime.HeartbeatAsync();
            f.Handler.Failure = null;
            f.Meter.Seconds = 17;
            await runtime.HeartbeatAsync();
            f.Meter.Seconds = 7;
            await runtime.HeartbeatAsync();
            f.Deltas(40, 100, 40, 7);
        }
    }

    private static async Task Acknowledgement()
    {
        foreach (var (json, expected) in new[] { ("{}", 0L), ("{\"overlayUsageSecondsAccepted\":null}", 0L),
            ("{\"overlayUsageSecondsAccepted\":0}", 100L), ("{\"overlayUsageSecondsAccepted\":30}", 70L),
            ("{\"overlayUsageSecondsAccepted\":-1}", 100L), ("{\"overlayUsageSecondsAccepted\":600}", 0L) })
        {
            using var f = new Fixture();
            using var runtime = f.Create();
            await runtime.HeartbeatAsync();
            f.Handler.Bodies.Clear();
            f.Meter.TakeCalls = 0;
            f.Handler.ResponseJson = json;
            f.Meter.Seconds = 100;
            await runtime.HeartbeatAsync();
            f.Handler.ResponseJson = "{}";
            await runtime.HeartbeatAsync();
            f.Deltas(100, expected);
        }
    }

    private static async Task Visibility()
    {
        using var f = new Fixture();
        using var runtime = f.Create();
        await runtime.HeartbeatAsync();
        f.Handler.Bodies.Clear();
        f.Meter.TakeCalls = 0;
        f.Handler.Status = HttpStatusCode.ServiceUnavailable;
        f.Meter.Seconds = 40;
        await runtime.HeartbeatAsync();
        foreach (var mode in new[] { PlayerPresenceVisibilityMode.Invisible, PlayerPresenceVisibilityMode.Offline })
        {
            f.Visibility = mode;
            f.Meter.Seconds = 30;
            await runtime.HeartbeatAsync();
        }
        Check(f.Handler.Bodies.Count == 3, "hidden presence still sends every heartbeat");
        f.Visibility = PlayerPresenceVisibilityMode.Online;
        f.Handler.Status = HttpStatusCode.OK;
        f.Meter.Seconds = 17;
        await runtime.HeartbeatAsync();
        f.Meter.Seconds = 11;
        await runtime.HeartbeatAsync();
        f.Visibility = PlayerPresenceVisibilityMode.InGame;
        f.Meter.Seconds = 9;
        await runtime.HeartbeatAsync();
        f.Deltas(40, 70, 100, 117, 11, 9);
        Check(f.Handler.Bodies.Select(b => b.GetProperty("countOnline").GetBoolean())
            .SequenceEqual(new[] { true, false, false, true, true, true }), "visibility only controls online count");
        Check(f.Meter.TakeCalls == 6, "all visibility modes drain and report usage");
    }

    private static async Task SwitchDuringRequest()
    {
        using var f = new Fixture();
        using var runtime = f.Create();
        await runtime.HeartbeatAsync();
        f.Handler.Bodies.Clear();
        f.Meter.TakeCalls = 0;
        f.Handler.BeforeResponse = () => f.Online = false;
        f.Meter.Seconds = 20;
        await runtime.HeartbeatAsync();
        f.Handler.BeforeResponse = null;
        f.Online = true;
        f.Meter.Seconds = 17;
        await runtime.HeartbeatAsync();
        f.Meter.Seconds = 10;
        await runtime.HeartbeatAsync();
        f.Deltas(20, 0, 10);
    }

    private static async Task VisibilityDuringRequest()
    {
        using var f = new Fixture();
        using var runtime = f.Create();
        await runtime.HeartbeatAsync();
        f.Handler.Bodies.Clear();
        f.Meter.TakeCalls = 0;
        foreach (var mode in new[] { PlayerPresenceVisibilityMode.Invisible,
            PlayerPresenceVisibilityMode.Offline, PlayerPresenceVisibilityMode.Online })
        {
            f.Handler.BeforeResponse = () => f.Visibility = mode;
            f.Meter.Seconds = 20;
            await runtime.HeartbeatAsync();
        }
        f.Handler.BeforeResponse = null;
        f.Meter.Seconds = 9;
        await runtime.HeartbeatAsync();
        f.Deltas(20, 20, 20, 9);
        Check(f.Handler.Bodies.Select(b => b.GetProperty("countOnline").GetBoolean())
            .SequenceEqual(new[] { true, false, false, true }), "each request samples current visibility");
    }

    private static async Task Splits()
    {
        using var f = new Fixture();
        using var runtime = f.Create();
        await runtime.HeartbeatAsync();
        f.Handler.Bodies.Clear();
        f.Meter.TakeCalls = 0;
        f.Meter.Seconds = 625;
        for (var i = 0; i < 4; i++) await runtime.HeartbeatAsync();
        f.Deltas(300, 0, 0, 0);
        var body = f.Handler.Bodies[0];
        Check(body.GetProperty("protocol").GetInt32() == 2 && body.EnumerateObject().Count() == 6 && body.GetProperty("version").GetString() == "0.7.2" &&
            body.GetProperty("overlayActive").GetBoolean() && body.GetProperty("countOnline").GetBoolean(), "anonymous wire shape and open overlay");
        Check(f.Meter.TakeCalls == 4, "one meter sample per heartbeat");
    }

    private static async Task Retries()
    {
        using var f = new Fixture();
        using var runtime = f.Create();
        await runtime.HeartbeatAsync();
        f.Handler.Bodies.Clear();
        f.Meter.TakeCalls = 0;
        f.Meter.Seconds = 320;
        f.Handler.Status = HttpStatusCode.ServiceUnavailable;
        await runtime.HeartbeatAsync();
        f.Handler.Status = HttpStatusCode.OK;
        f.Meter.Seconds = 15;
        await runtime.HeartbeatAsync();
        f.Meter.IsOverlayOpen = false;
        await runtime.HeartbeatAsync();
        f.Deltas(300, 300, 0);
        Check(!f.Handler.Bodies.Last().GetProperty("overlayActive").GetBoolean(), "closed overlay still flushes pending");
        Check(f.Diagnostics.Count == 1 && !f.Diagnostics[0].Contains(f.Root), "one bounded failure diagnostic");
    }

    private static async Task Offline()
    {
        using var f = new Fixture();
        using var runtime = f.Create();
        await runtime.HeartbeatAsync();
        f.Handler.Bodies.Clear();
        f.Meter.TakeCalls = 0;
        f.Visibility = PlayerPresenceVisibilityMode.Invisible;
        f.Handler.Status = HttpStatusCode.ServiceUnavailable;
        f.Meter.Seconds = 42;
        await runtime.HeartbeatAsync();
        f.Online = false;
        f.Meter.Seconds = 123;
        await runtime.HeartbeatAsync();
        f.Meter.Seconds = 45;
        await runtime.HeartbeatAsync();
        Check(f.Handler.Bodies.Count == 1, "offline never requests");
        f.Online = true;
        f.Handler.Status = HttpStatusCode.OK;
        f.Meter.Seconds = 17; // Mixed recovery interval is discarded as well.
        await runtime.HeartbeatAsync();
        f.Meter.Seconds = 9;
        await runtime.HeartbeatAsync();
        f.Deltas(42, 42, 9);
        Check(f.Handler.Bodies.All(b => !b.GetProperty("countOnline").GetBoolean()),
            "hidden network recovery remains excluded from online count");
        Check(f.Meter.TakeCalls == 5, "offline and recovery samples are drained");
    }

    private static async Task Cap()
    {
        using var f = new Fixture();
        using var runtime = f.Create();
        await runtime.HeartbeatAsync();
        f.Handler.Bodies.Clear();
        f.Meter.TakeCalls = 0;
        f.Handler.Status = HttpStatusCode.ServiceUnavailable;
        f.Meter.Seconds = 3550;
        await runtime.HeartbeatAsync();
        f.Meter.Seconds = long.MaxValue;
        await runtime.HeartbeatAsync();
        f.Handler.Status = HttpStatusCode.OK;
        await runtime.HeartbeatAsync();
        await runtime.HeartbeatAsync();
        f.Deltas(300, 300, 300, 0);
    }

    private static async Task ExistingId()
    {
        using var f = new Fixture();
        var desktopId = Guid.NewGuid().ToString("N");
        File.WriteAllText(f.IdPath, desktopId);
        var before = File.GetLastWriteTimeUtc(f.IdPath);
        using var runtime = f.Create();
        await runtime.HeartbeatAsync();
        Check(f.Handler.Bodies[0].GetProperty("clientId").GetString() == desktopId &&
            File.ReadAllText(f.IdPath) == desktopId && File.GetLastWriteTimeUtc(f.IdPath) == before,
            "Desktop N format reused without a write");
    }

    private static Task InvalidIds()
    {
        using var f = new Fixture();
        foreach (var invalid in new[] { "", "bad", new string('A', 32), new string('g', 32), new string('a', 31), Guid.NewGuid().ToString() })
        {
            File.WriteAllText(f.IdPath, invalid);
            var id = AppStatsClientId.LoadOrCreate(HostDataRoot.CurrentRoot);
            Check(id.Length == 32 && id.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f'), "lowercase N format");
            Check(File.ReadAllText(f.IdPath) == id, "invalid content replaced");
            Check(AppStatsClientId.LoadOrCreate(HostDataRoot.CurrentRoot) == id, "repair is stable");
        }
        return Task.CompletedTask;
    }

    private static async Task ConcurrentId()
    {
        using var f = new Fixture();
        var ids = await Task.WhenAll(Enumerable.Range(0, 32).Select(_ => Task.Run(() =>
            AppStatsClientId.LoadOrCreate(f.Root))));
        Check(ids.Distinct().Count() == 1 && File.ReadAllText(f.IdPath) == ids[0], "one persisted concurrent ID");
        Check(Directory.GetFiles(f.Root).Length == 1, "only the shared client ID file is created");
    }

    private static async Task NullMeter()
    {
        using var f = new Fixture();
        using var runtime = f.Create(nullMeter: true);
        await runtime.HeartbeatAsync();
        await runtime.HeartbeatAsync();
        f.Deltas(0, 0);
        Check(f.Handler.Bodies.All(b => !b.GetProperty("overlayActive").GetBoolean()), "no overlay without a meter");
    }

    private static async Task ConcurrentWriter()
    {
        using var f = new Fixture();
        using var runtime = f.Create();
        var desktopId = Guid.NewGuid().ToString("N");
        using (var writer = new FileStream(f.IdPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
        {
            f.Meter.Seconds = 19;
            await runtime.HeartbeatAsync();
            Check(f.Handler.Bodies.Count == 0, "held Desktop file prevents premature anonymous ID");
            writer.Write(System.Text.Encoding.UTF8.GetBytes(desktopId));
        }
        await runtime.HeartbeatAsync();
        f.Deltas(0); // The held writer coincides with the discarded startup sample.
        Check(f.Handler.Bodies[0].GetProperty("clientId").GetString() == desktopId &&
            File.ReadAllText(f.IdPath) == desktopId, "retry reuses completed Desktop ID without overwriting");
    }

    private static async Task TimerLifecycle()
    {
        using var f = new Fixture();
        using var runtime = f.Create();
        var timer = f.Time.Timers.Single();
        Check(timer.Due == TimeSpan.FromSeconds(30) && timer.Period == timer.Due, "30-second schedule");
        Check(f.Handler.Bodies.Count == 0, "no startup heartbeat");
        // Invoke the actual timer callback and observe entry without wall-clock sleeps.
        f.Handler.Hold = true;
        timer.Fire();
        await f.Handler.Entered.Task;
        runtime.Dispose();
        await f.Handler.Exited.Task;
        Check(timer.Disposed, "timer disposed");
        await runtime.HeartbeatAsync();
        f.Deltas(0);
    }

    private static async Task Timeout()
    {
        using var f = new Fixture();
        using var runtime = f.Create();
        await runtime.HeartbeatAsync();
        f.Handler.Bodies.Clear();
        f.Meter.TakeCalls = 0;
        f.Meter.Seconds = 71;
        f.Handler.Hold = true;
        var first = runtime.HeartbeatAsync();
        await f.Handler.Entered.Task;
        await runtime.HeartbeatAsync();
        Check(f.Handler.Bodies.Count == 1 && f.Meter.TakeCalls == 1, "one in-flight request");
        var timeout = f.Time.Timers.Last();
        Check(timeout.Due == TimeSpan.FromSeconds(10), "10-second injected deadline");
        timeout.Fire();
        await first;
        Check(f.Handler.Cancelled && f.Diagnostics.Count == 1, "timeout cancels actual handler");
        f.Handler.Hold = false;
        await runtime.HeartbeatAsync();
        f.Deltas(71, 0);
    }

    private static async Task LeaseCancellation()
    {
        using var f = new Fixture();
        using var runtime = f.Create();
        await runtime.HeartbeatAsync();
        f.Handler.Bodies.Clear();
        f.Meter.TakeCalls = 0;
        f.Meter.Seconds = 90;
        f.Handler.Hold = true;
        var send = runtime.HeartbeatAsync();
        await f.Handler.Entered.Task;
        f.Online = false;
        await f.Network.PauseAsync();
        await send;
        Check(f.Handler.Cancelled, "device offline cancellation reaches HTTP");
        f.Online = true;
        f.Handler.Hold = false;
        await runtime.HeartbeatAsync();
        f.Deltas(90, 0);
    }

    private static async Task Disposal()
    {
        using var f = new Fixture();
        using var runtime = f.Create();
        f.Handler.Hold = true;
        var send = runtime.HeartbeatAsync();
        await f.Handler.Entered.Task;
        runtime.Dispose();
        runtime.Dispose();
        await send;
        await runtime.HeartbeatAsync();
        Check(f.Handler.Cancelled && f.Handler.Bodies.Count == 1 && f.Diagnostics.Count == 0,
            "disposal cancels and never flushes or diagnoses shutdown");
    }

    private static async Task StorageFailure()
    {
        using var f = new Fixture();
        using var runtime = f.Create();

        // A directory at the file path fails without touching any real product data.
        Directory.CreateDirectory(f.IdPath);
        f.Meter.Seconds = 42;
        await runtime.HeartbeatAsync();
        Check(f.Handler.Bodies.Count == 0 && f.Diagnostics.Count == 1, "storage error does not escape");
        Directory.Delete(f.IdPath);
        await runtime.HeartbeatAsync();
        f.Deltas(0);
    }

    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }

    private sealed class Fixture : IDisposable
    {
        private readonly string _previous = HostDataRoot.CurrentRoot;
        internal string Root { get; } = Path.Combine(Path.GetTempPath(), "cx86-" + Guid.NewGuid().ToString("N"));
        internal string IdPath => Path.Combine(Root, "app-client-id.txt");
        internal readonly Meter Meter = new();
        internal readonly Handler Handler = new();
        internal readonly Clock Time = new();
        internal readonly List<string> Diagnostics = [];
        internal bool Online = true;
        internal PlayerPresenceVisibilityMode Visibility = PlayerPresenceVisibilityMode.Online;
        internal readonly DeviceNetworkAdmission Network;
        internal Fixture()
        {
            Directory.CreateDirectory(Root);
            HostDataRoot.UsePreparedRoot(Root);
            Network = new(() => Online);
        }
        internal AppStatsHeartbeatRuntime Create(bool nullMeter = false, AppStatsHeartbeatRuntime.RelayCapability? capability = null) => new(
            new Uri("http://127.0.0.1/"), nullMeter ? null : Meter, Network, "0.7.2", Time,
            HostDataRoot.CurrentRoot, Handler, Diagnostics.Add, () => Visibility, capability);
        internal void Deltas(params long[] expected) => Check(Handler.Bodies.Select(b =>
            b.GetProperty("overlayUsageSecondsDelta").GetInt64()).SequenceEqual(expected), "unexpected deltas");
        public void Dispose()
        {
            HostDataRoot.UsePreparedRoot(_previous);
            Directory.Delete(Root, true);
        }
    }

    private sealed class Meter : IInformationOverlayUsageMeter
    {
        public bool IsOverlayOpen { get; set; } = true;
        internal long Seconds;
        internal int TakeCalls;
        public long TakeOpenSeconds() { TakeCalls++; return Interlocked.Exchange(ref Seconds, 0); }
    }

    private sealed class Handler : HttpMessageHandler
    {
        internal readonly List<JsonElement> Bodies = [];
        internal HttpStatusCode Status = HttpStatusCode.OK;
        internal bool Hold, Cancelled;
        internal Exception? Failure;
        internal string? ResponseJson = "{\"heartbeatProtocol\":2}";
        internal int Probes;
        internal bool Legacy;
        internal readonly List<string> Paths = [];
        internal Action? BeforeResponse;
        internal readonly TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Exited = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.Method == HttpMethod.Get)
            {
                Check(request.RequestUri!.AbsolutePath == "/api/app-stats" && !request.Headers.Any(), "read-only anonymous discovery");
                Probes++;
                return new(Status) { Content = new StringContent(ResponseJson ?? "{}") };
            }
            var path = request.RequestUri!.AbsolutePath;
            Paths.Add(path);
            if (Legacy && path == "/api/app-stats/v2/heartbeat") return new(HttpStatusCode.NotFound);
            Check(request.Method == HttpMethod.Post && path == (Legacy ? "/api/app-stats/heartbeat" : "/api/app-stats/v2/heartbeat"),
                "fixed POST route");
            Check(!request.Headers.Any(), "no account credentials or custom headers");
            using var json = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            Bodies.Add(json.RootElement.Clone());
            Entered.TrySetResult();
            try
            {
                if (Hold) await Task.Delay(System.Threading.Timeout.InfiniteTimeSpan, token);
                if (Failure is not null) throw Failure;
                BeforeResponse?.Invoke();
                return new(Status) { Content = ResponseJson is null ? null : new StringContent(ResponseJson) };
            }
            catch (OperationCanceledException) { Cancelled = true; throw; }
            finally { Exited.TrySetResult(); }
        }
    }

    private sealed class Clock : TimeProvider
    {
        private DateTimeOffset _now = DateTimeOffset.Parse("2026-10-28T00:00:00Z");
        public override DateTimeOffset GetUtcNow() => _now;
        internal void Advance(int seconds) => _now = _now.AddSeconds(seconds);
        internal readonly List<Timer> Timers = [];
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        {
            var timer = new Timer(callback, state, dueTime, period);
            Timers.Add(timer);
            return timer;
        }
        internal sealed class Timer(TimerCallback callback, object? state, TimeSpan due, TimeSpan period) : ITimer
        {
            internal TimeSpan Due = due;
            internal TimeSpan Period = period;
            internal bool Disposed;
            internal void Fire() { if (!Disposed) callback(state); }
            public bool Change(TimeSpan nextDue, TimeSpan nextPeriod)
            { Due = nextDue; Period = nextPeriod; return !Disposed; }
            public void Dispose() => Disposed = true;
            public ValueTask DisposeAsync() { Dispose(); return ValueTask.CompletedTask; }
        }
    }
}
