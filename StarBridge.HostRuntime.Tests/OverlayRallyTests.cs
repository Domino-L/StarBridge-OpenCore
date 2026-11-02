using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;
using System.Text.Json;
using System.Security.Cryptography;
using StarBridge.HostRuntime.Settings;

internal static class OverlayRallyTests
{
    private sealed class Sink : IInformationOverlayReminderSink
    {
        internal readonly List<InformationOverlayReminder> Items = [];
        internal string Mode = "ok";
        public async ValueTask<bool> TryPresentAsync(InformationOverlayReminder value, CancellationToken token)
        {
            Items.Add(value);
            if (Mode == "timeout") await Task.Delay(Timeout.Infinite, token);
            return Mode == "ok";
        }
        public void ClearReminder() { }
    }
    private sealed class Domain : IBridgeRequestDispatcher
    {
        internal object Value = new { };
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default) =>
            ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.Response(request, Value), []));
        public void Dispose() { }
    }
    private static void Check(bool value, string name)
    {
        if (!value) throw new Exception("FAIL rally: " + name);
        Console.WriteLine("PASS rally: " + name);
    }
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "rally-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var sink = new Sink();
        long generation = 1;
        using var dispatcher = new NotificationSettingsBridgeDispatcher(root, () => generation, overlay: sink);
        var domain = new Domain();
        using var composite = new CompositeBridgeDispatcher(domain, domain, domain, notifications: dispatcher);
        async Task Observe(string action, object value, bool online = true, string source = "fleet", long gen = 1)
        {
            domain.Value = System.Text.Json.JsonSerializer.SerializeToElement(value);
            var batch = await composite.DispatchAsync(BridgeEnvelope.Request("officialFleet.rally", Guid.NewGuid().ToString("N"), gen,
                new { action, sourceRef = source, online }));
            Check(batch.Response.Payload.GetRawText() == BridgePayload.From(domain.Value).GetRawText(), "response preserved: " + action);
        }
        object Rally(string id, string state = "active", string? answer = null, int seconds = 120) => new {
            rally = new { rallyId = id, text = "集合", state, response = answer, expiresAt = DateTimeOffset.UtcNow.AddSeconds(seconds) }
        };
        Task Eligible(bool owner = false, string source = "fleet") => Observe("eligibility", new { canStart = owner }, source: source);
        try
        {
            await Observe("read", Rally("one"));
            Check(sink.Items.Count == 0, "unknown eligibility is deferred");
            await Eligible();
            await Observe("read", Rally("one"));
            var first = sink.Items.Single();
            Check(first.IsCurrent() && first.Rally!.Text == "集合", "first eligible read presents trusted text");
            await Observe("read", Rally("one"));
            Check(sink.Items.Count == 1, "same ID never repeated");
            await Observe("read", Rally("offline"), false);
            await Observe("read", Rally("offline"));
            Check(sink.Items.Count == 1 && !first.IsCurrent(), "offline consumed and replacement invalidates old");
            await Eligible(true);
            await Observe("read", Rally("owner"));
            Check(sink.Items.Count == 1, "owner suppressed");
            await Eligible();
            foreach (var value in new[] { Rally("answered", answer: "coming"), Rally("ended", "ended"),
                Rally("expired", "expired"), Rally("past", seconds: -1) }) await Observe("read", value);
            Check(sink.Items.Count == 1, "responded, ended, expired and elapsed suppressed");
            await Observe("read", Rally("other-source"), source: "unknown");
            Check(sink.Items.Count == 1, "eligibility scoped by source");
            var settingsPath = Path.Combine(root, "notification-settings.v1.json");
            File.WriteAllText(settingsPath, "{\"schemaVersion\":1,\"revision\":0,\"inAppEnabled\":true,\"position\":\"bottomRight\",\"preview\":\"sourceOnly\",\"rallyAlerts\":false}");
            await Observe("read", Rally("disabled"));
            File.Delete(settingsPath);
            await Observe("read", Rally("disabled"));
            Check(sink.Items.Count == 1, "disabled consumed without replay");
            foreach (var action in new[] { "respond", "end" })
            {
                await Observe("read", Rally(action));
                var current = sink.Items.Last();
                await Observe(action, Rally(action));
                Check(!current.IsCurrent(), action + " invalidates");
            }
            foreach (var value in new object[] { new { rally = (object?)null }, Rally("different", "ended"),
                Rally("invalidate", "ended"), Rally("invalidate", answer: "cannot") })
            {
                dispatcher.Reset(); await Eligible(); await Observe("read", Rally("invalidate"));
                var current = sink.Items.Last();
                await Observe("read", value);
                Check(!current.IsCurrent(), "subsequent read invalidates");
            }
            dispatcher.Reset();
            var count = sink.Items.Count;
            await Observe("read", Rally("one"));
            Check(sink.Items.Count == count, "reset clears eligibility");
            await Eligible(); await Observe("read", Rally("one"));
            Check(sink.Items.Count == count + 1, "reset clears seen IDs");
            var beforeReset = sink.Items.Last(); dispatcher.Reset();
            Check(!beforeReset.IsCurrent(), "reset revokes existing reminder");
            await Eligible();
            foreach (var mode in new[] { "false", "timeout" })
            {
                sink.Mode = mode; count = sink.Items.Count;
                await Observe("read", Rally(mode)); await Observe("read", Rally(mode));
                Check(sink.Items.Count == count + 1, mode + " never retries");
            }
            sink.Mode = "ok";
            count = sink.Items.Count;
            await Observe("read", Rally("stale"), gen: 0);
            Check(sink.Items.Count == count, "stale session suppressed");
            await Observe("read", Rally("current"));
            generation++;
            Check(!sink.Items.Last().IsCurrent(), "session change revokes reminder");
        }
        finally
        {
            dispatcher.Dispose();
            Directory.Delete(root, true);
        }
        await IndependentAlerts();
        await SettingsAndPreview();
        await HotkeyLifecycle();
        await DelayedHotkeyLeases();
        await SaveDisablesActiveRally();
        Audio();
    }

    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = new(2026, 10, 24, 0, 0, 0, TimeSpan.Zero);
        internal long Ticks;
        public override DateTimeOffset GetUtcNow() => Now;
        public override long GetTimestamp() => Ticks;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        private readonly List<Timer> _timers = [];
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        {
            var timer = new Timer(this, callback, state); _timers.Add(timer); timer.Change(dueTime, period); return timer;
        }
        private sealed class Timer(Clock clock, TimerCallback callback, object? state) : ITimer
        {
            internal DateTimeOffset Due = DateTimeOffset.MaxValue;
            public bool Change(TimeSpan dueTime, TimeSpan period)
            {
                Due = dueTime == Timeout.InfiniteTimeSpan ? DateTimeOffset.MaxValue : clock.Now + dueTime;
                return true;
            }
            internal void Fire() { Due = DateTimeOffset.MaxValue; callback(state); }
            public void Dispose() => Due = DateTimeOffset.MaxValue;
            public ValueTask DisposeAsync() { Dispose(); return ValueTask.CompletedTask; }
        }
        internal void Advance(TimeSpan elapsed)
        {
            Now += elapsed; Ticks += elapsed.Ticks;
            foreach (var timer in _timers.Where(t => t.Due <= Now).ToArray()) timer.Fire();
        }
    }
    private sealed class Banner : IRallyBannerSink
    {
        internal readonly List<RallyBannerNotice> Items = [];
        internal readonly List<Guid> Cleared = [];
        internal string Mode = "ok";
        public ValueTask<bool> TryPresentAsync(RallyBannerNotice notice, CancellationToken token)
        {
            Items.Add(notice);
            if (Mode == "throw") throw new InvalidOperationException("test rejection");
            // Deliberately ignore cancellation: Host must still bound the wait.
            if (Mode == "timeout") return new(new TaskCompletionSource<bool>().Task);
            return ValueTask.FromResult(Mode == "ok");
        }
        public void Clear(Guid id) => Cleared.Add(id);
    }
    private sealed class Fixture : IDisposable
    {
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "cx69-rally-" + Guid.NewGuid().ToString("N"));
        internal readonly Clock Time = new();
        internal readonly Sink Overlay = new();
        internal readonly Banner Banner = new();
        internal readonly NotificationSettingsBridgeDispatcher Dispatcher;
        internal readonly Hotkeys Hotkeys = new();
        internal readonly List<BridgeEnvelope> Events = [];
        internal int Sounds;
        internal bool SoundResult = true;
        internal Fixture(bool banner = true, bool overlay = true)
        {
            Directory.CreateDirectory(Root);
            Dispatcher = new(Root, () => 1, overlay: overlay ? Overlay : null,
                rallyBanner: banner ? Banner : null, playRally: current => { Sounds++; return current() && SoundResult; }, time: Time,
                hotkeys: Hotkeys, hostEvent: (session, name, payload) => BridgeEnvelope.Event(name, session, 7, payload));
            Dispatcher.EventReady += Events.Add;
        }
        internal void Settings(bool enabled = true, bool overlay = false, string preview = "sourceOnly") =>
            File.WriteAllText(Path.Combine(Root, "notification-settings.v1.json"), JsonSerializer.Serialize(
                new LocalNotificationSettings(InAppEnabled: false, OverlayEnabled: overlay, Preview: preview, RallyAlertsEnabled: enabled), BridgeProtocol.JsonOptions));
        internal async Task<BridgeEnvelope> Call(string name, object payload) =>
            (await Dispatcher.DispatchAsync(BridgeEnvelope.Request("notificationSettings." + name, Guid.NewGuid().ToString("N"), 1, payload))).Response;
        internal async Task Observe(string action, object value, bool online = true)
        {
            var request = BridgeEnvelope.Request("officialFleet.rally", Guid.NewGuid().ToString("N"), 1,
                new { action, sourceRef = "fleet", online });
            var response = BridgeEnvelope.Response(request, JsonSerializer.SerializeToElement(value));
            var observed = await Dispatcher.ObserveAsync(request, response, default);
            Check(ReferenceEquals(response, observed), "banner preserves domain response: " + action);
        }
        internal Task Eligible() => Observe("eligibility", new { canStart = false });
        internal object Rally(string id, string state = "active", string? answer = null) => new
        {
            rally = new { rallyId = id, text = "rally test", state, response = answer, expiresAt = Time.Now.AddMinutes(30) }
        };
        public void Dispose() { Dispatcher.Dispose(); Dispatcher.RallyHotkeysIdle.GetAwaiter().GetResult(); Directory.Delete(Root, true); }
    }
    private sealed class Hotkeys : ISafeHotkeyRuntime
    {
        internal readonly List<(int Command, string? Binding)> Calls = [];
        internal readonly Dictionary<int, string> Routes = [];
        internal readonly Dictionary<int, long> Leases = [];
        internal string Mode = "ok";
        internal Func<Task>? DuringConfigure;
        public event Action<int, long>? HostHotkeyTriggered;
        internal Action CaptureTrigger(int command)
        {
            var lease = Leases.GetValueOrDefault(command);
            return () => HostHotkeyTriggered?.Invoke(command, lease);
        }
        internal void Trigger(int command) => CaptureTrigger(command)();
        public ValueTask ConfigureTemporaryHotkeyAsync(int id, string? binding, CancellationToken token = default) =>
            throw new Exception("Rally must not use menu routes");
        public async ValueTask ConfigureHostHotkeyAsync(int id, string? binding, long lease, CancellationToken token = default)
        {
            Calls.Add((id, binding));
            if (DuringConfigure is { } probe) await probe();
            if (binding != null && Mode != "ok")
                throw Mode == "conflict" ? new InvalidOperationException("conflict") : new ArgumentException("invalid");
            if (binding is null) { Routes.Remove(id); Leases.Remove(id); }
            else { Routes[id] = binding; Leases[id] = lease; }
        }
    }

    private static async Task HotkeyLifecycle()
    {
        const string first = "0123456789abcdef0123456789abcdef";
        const string second = "abcdef0123456789abcdef0123456789";
        using var f = new Fixture();
        await f.Eligible();
        // Crossing another thread into Reset would deadlock if registration held _gate.
        f.Hotkeys.DuringConfigure = async () =>
            await Task.Run(() => { var idle = f.Dispatcher.RallyHotkeysIdle; }).WaitAsync(TimeSpan.FromSeconds(2));
        await f.Observe("read", f.Rally(first)); await f.Dispatcher.RallyHotkeysIdle;
        Check(f.Hotkeys.Calls.SequenceEqual(new[] { (100, (string?)TemporaryHotkeyDefaults.Accept),
            (101, (string?)TemporaryHotkeyDefaults.Decline) }), "rally registers exact Host defaults outside gate");
        await f.Observe("read", f.Rally(first)); await f.Dispatcher.RallyHotkeysIdle;
        Check(f.Hotkeys.Calls.Count == 2, "rally Host routes register once");
        foreach (var command in new[] { 100, 101 })
        {
            if (command == 101) { f.Dispatcher.Reset(); await f.Eligible(); await f.Observe("read", f.Rally(first)); await f.Dispatcher.RallyHotkeysIdle; }
            f.Hotkeys.Trigger(command); f.Hotkeys.Trigger(command); await f.Dispatcher.RallyHotkeysIdle;
            var frame = f.Events.Last();
            Check(frame.Name == "officialFleet.rallyHotkey" && frame.SessionGeneration == 1 && frame.Sequence == 7 &&
                frame.Payload.GetRawText() == JsonSerializer.Serialize(new { schemaVersion = 1, rallyId = first,
                    answer = command == 100 ? "coming" : "cannot" }), "exact rally hotkey event " + command);
            Check(f.Events.Count == (command == 100 ? 1 : 2) && f.Hotkeys.Routes.Count == 0,
                "rally response consumed once and both routes removed " + command);
        }
        foreach (var reason in new[] { "respond", "end", "ended", "answered", "elapsed", "replace", "reset", "disabled", "settings-read", "offline", "dispose" })
        {
            using var x = new Fixture(); await x.Eligible();
            await x.Observe("read", x.Rally(first)); await x.Dispatcher.RallyHotkeysIdle;
            switch (reason)
            {
                case "respond": case "end": await x.Observe(reason, x.Rally(first)); break;
                case "ended": await x.Observe("read", x.Rally(first, "ended")); break;
                case "answered": await x.Observe("read", x.Rally(first, answer: "coming")); break;
                case "elapsed": x.Time.Advance(TimeSpan.FromMinutes(31)); break;
                case "replace": await x.Observe("read", x.Rally(second, "ended")); break;
                case "reset": x.Dispatcher.Reset(); break;
                case "disabled": x.Settings(enabled: false); await x.Observe("read", x.Rally(first)); break;
                case "settings-read": x.Settings(enabled: false); await x.Call("read", new { schemaVersion = 1 }); break;
                case "offline": await x.Observe("read", x.Rally(first), online: false); break;
                case "dispose": x.Dispatcher.Dispose(); break;
            }
            await x.Dispatcher.RallyHotkeysIdle; x.Hotkeys.Trigger(100); x.Hotkeys.Trigger(101);
            Check(x.Hotkeys.Routes.Count == 0 && x.Events.Count == 0, "Host routes removed and stale trigger suppressed: " + reason);
        }
        using var replacement = new Fixture(); await replacement.Eligible();
        await replacement.Observe("read", replacement.Rally(first)); await replacement.Dispatcher.RallyHotkeysIdle;
        await replacement.Observe("read", replacement.Rally(second)); await replacement.Dispatcher.RallyHotkeysIdle;
        replacement.Hotkeys.Trigger(101); await replacement.Dispatcher.RallyHotkeysIdle;
        Check(replacement.Events.Single().Payload.GetProperty("rallyId").GetString() == second,
            "replacement rally receives event after old routes removed");
        foreach (var mode in new[] { "invalid", "conflict" })
        {
            using var x = new Fixture(); x.Hotkeys.Mode = mode; await x.Eligible();
            await x.Observe("read", x.Rally(first)); await x.Dispatcher.RallyHotkeysIdle;
            x.Hotkeys.Trigger(100);
            Check(x.Banner.Items.Count == 1 && x.Sounds == 1 && x.Hotkeys.Routes.Count == 0 && x.Events.Count == 0,
                "hotkey failure preserves banner and sound: " + mode);
            Check(File.ReadAllText(Path.Combine(x.Root, "notification-delivery-diagnostics.log")).Contains("RallyHotkey Failed"),
                "hotkey failure logged without payload: " + mode);
        }
        using var pending = new Fixture(); await pending.Eligible();
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var blockOnce = 0;
        pending.Hotkeys.DuringConfigure = async () =>
        {
            if (Interlocked.Increment(ref blockOnce) == 1) { entered.SetResult(); await release.Task; }
        };
        await pending.Observe("read", pending.Rally(first));
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(2));
        try
        {
            await pending.Observe("read", pending.Rally(second)).WaitAsync(TimeSpan.FromSeconds(2));
            Check(pending.Sounds == 2 && pending.Banner.Items.Count == 2,
                "pending native registration does not block rally replacement or reminders");
        }
        finally { release.TrySetResult(); }
        await pending.Dispatcher.RallyHotkeysIdle;
        Check(pending.Hotkeys.Routes.Count == 2, "stale registration cleanup preserves replacement routes");
        pending.Hotkeys.Trigger(100); await pending.Dispatcher.RallyHotkeysIdle;
        Check(pending.Events.Single().Payload.GetProperty("rallyId").GetString() == second,
            "pending old registration cannot reclaim rally ownership");
        using var silent = new Fixture(); await silent.Eligible();
        await silent.Observe("read", silent.Rally(first), online: false);
        await silent.Call("previewRally", new { schemaVersion = 1 }); await silent.Dispatcher.RallyHotkeysIdle;
        Check(silent.Hotkeys.Calls.Count == 0, "offline and preview do not register Host routes");
    }
    private static async Task DelayedHotkeyLeases()
    {
        const string first = "0123456789abcdef0123456789abcdef";
        const string second = "abcdef0123456789abcdef0123456789";
        long previousLease = 0;
        foreach (var rapidPress in new[] { false, true })
        {
            using var f = new Fixture();
            await f.Eligible(); await f.Observe("read", f.Rally(first));
            await f.Dispatcher.RallyHotkeysIdle;
            var oldLease = f.Hotkeys.Leases[100];
            Check(oldLease > previousLease && f.Hotkeys.Leases[101] == oldLease,
                "owner lease increases across dispatcher instances and covers both commands");
            // Capture each physical press before A ends. Pause queued callbacks,
            // not registration, so releasing them exercises Host consumption.
            var callbacks = new[] { f.Hotkeys.CaptureTrigger(100), f.Hotkeys.CaptureTrigger(101) };
            var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var queued = Task.Run(async () =>
            {
                entered.SetResult();
                await release.Task;
                foreach (var callback in callbacks) callback();
            });
            try
            {
                await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
                if (rapidPress) f.Hotkeys.Trigger(100);
                else await f.Observe("end", f.Rally(first));
                await f.Observe("read", f.Rally(second));
                await f.Dispatcher.RallyHotkeysIdle;
                previousLease = f.Hotkeys.Leases[100];
                Check(previousLease > oldLease && f.Banner.Items.Last().IsCurrent(), "replacement owns a newer live lease");
            }
            finally { release.TrySetResult(); await queued.WaitAsync(TimeSpan.FromSeconds(5)); }
            Check(f.Events.Count == (rapidPress ? 1 : 0) && f.Banner.Items.Last().IsCurrent(),
                "queued old presses cannot respond to or consume replacement: " + rapidPress);
            Check(File.ReadAllText(Path.Combine(f.Root, "notification-delivery-diagnostics.log")).Contains("RallyHotkey Stale"),
                "stale lease emits bounded diagnostic");
            f.Hotkeys.Trigger(101); await f.Dispatcher.RallyHotkeysIdle;
            Check(f.Events.Last().Payload.GetProperty("rallyId").GetString() == second &&
                f.Events.Count == (rapidPress ? 2 : 1), "replacement still accepts its own lease");
            f.Dispatcher.Reset(); await f.Eligible(); await f.Observe("read", f.Rally(first));
            await f.Dispatcher.RallyHotkeysIdle;
            Check(f.Hotkeys.Leases[100] > previousLease, "reset and same ID never reuse lease");
            previousLease = f.Hotkeys.Leases[100];
        }
    }

    private static async Task SaveDisablesActiveRally()
    {
        const string id = "0123456789abcdef0123456789abcdef";
        using var f = new Fixture();
        await f.Eligible();
        await f.Observe("read", f.Rally(id));
        await f.Dispatcher.RallyHotkeysIdle;
        var notice = f.Banner.Items.Single();
        Check(notice.IsCurrent() && f.Hotkeys.Routes.Count == 2, "save starts with active registered rally");
        Task<BridgeEnvelope> Save(int revision, bool enabled) => f.Call("save", new
        {
            schemaVersion = 1, expectedRevision = revision, inAppEnabled = true,
            position = "bottomRight", preview = "sourceOnly", rallyAlerts = enabled
        });
        var disabled = await Save(0, false);
        Check(disabled.Status == "ok" && !notice.IsCurrent() && f.Banner.Cleared.Contains(notice.Id),
            "successful save immediately revokes owner and banner");
        await f.Dispatcher.RallyHotkeysIdle;
        Check(f.Hotkeys.Routes.Count == 0, "save removes both Host routes before idle");
        f.Hotkeys.Trigger(100); f.Hotkeys.Trigger(101);
        Check(f.Events.Count == 0, "disabled saved rally cannot emit hotkey response");
        var enabled = await Save(1, true);
        await f.Observe("read", f.Rally(id));
        await f.Dispatcher.RallyHotkeysIdle;
        Check(enabled.Status == "ok" && f.Banner.Items.Count == 1 && f.Sounds == 1 && f.Hotkeys.Routes.Count == 0,
            "saved re-enable keeps seen rally consumed without replay");
    }

    private static async Task IndependentAlerts()
    {
        using var f = new Fixture();
        await f.Eligible();
        f.Settings(enabled: false);
        await f.Observe("read", f.Rally("disabled"));
        Check(f.Banner.Items.Count == 0 && f.Sounds == 0, "independent switch disables banner and sound");
        f.Settings();
        await f.Observe("read", f.Rally("disabled"));
        Check(f.Banner.Items.Count == 0 && f.Sounds == 0, "disabled rally consumed without replay");
        var celebration = StarBridge.HostRuntime.Achievements.AchievementCelebrationActivity.Shared;
        celebration.Report(true);
        try {
            await f.Observe("read", f.Rally("banner"));
            Check(f.Banner.Items.Count == 1 && f.Banner.Items[0].IsCurrent() && celebration.IsActive,
                "rally banner still presents while achievements own their independent corner");
        }
        finally { celebration.Report(false); }
        var first = f.Banner.Items.Single();
        Check(first.IsCurrent() && first.Text == "rally test" && first.Preview == "sourceOnly" && !first.Sample &&
            first.ExpiresAt == f.Time.Now.AddMinutes(30) && f.Overlay.Items.Count == 0 && f.Sounds == 1,
            "banner and sound independent of overlay and in-app switches");
        await f.Observe("read", f.Rally("banner"));
        Check(f.Banner.Items.Count == 1 && f.Sounds == 1, "banner and sound exactly once per rally");
        await f.Observe("read", f.Rally("offline"), online: false);
        await f.Observe("read", f.Rally("offline"));
        Check(f.Sounds == 1 && f.Banner.Cleared.Contains(first.Id) && !first.IsCurrent(), "offline silent, consumed and clears replaced banner");
        foreach (var mode in new[] { "false", "throw", "timeout" })
        {
            f.Banner.Mode = mode;
            var sounds = f.Sounds;
            await f.Observe("read", f.Rally(mode));
            await f.Observe("read", f.Rally(mode));
            Check(f.Sounds == sounds + 1 && f.Overlay.Items.Count == 0, mode + " banner still sounds once without fallback or retry");
        }
        f.Banner.Mode = "ok";
        foreach (var action in new[] { "respond", "end" })
        {
            await f.Observe("read", f.Rally(action));
            var notice = f.Banner.Items.Last();
            await f.Observe(action, f.Rally(action));
            Check(f.Banner.Cleared.Contains(notice.Id) && !notice.IsCurrent(), "banner clear on " + action);
        }
        foreach (var value in new[] { f.Rally("ended", "ended"), f.Rally("answered", answer: "coming"), new { rally = (object?)null } })
        {
            f.Dispatcher.Reset(); await f.Eligible();
            await f.Observe("read", f.Rally("active"));
            var notice = f.Banner.Items.Last();
            await f.Observe("read", value);
            Check(f.Banner.Cleared.Contains(notice.Id) && !notice.IsCurrent(), "inactive read clears banner");
        }
        await f.Observe("read", f.Rally("reset"));
        var reset = f.Banner.Items.Last(); f.Dispatcher.Reset();
        Check(f.Banner.Cleared.Contains(reset.Id) && !reset.IsCurrent(), "reset clears banner");
        await f.Eligible(); await f.Observe("read", f.Rally("expires"));
        var expired = f.Banner.Items.Last(); f.Time.Advance(TimeSpan.FromMinutes(30));
        Check(!expired.IsCurrent(), "real banner expires using clock");
        using var fallback = new Fixture(banner: false);
        fallback.Settings(); await fallback.Eligible(); await fallback.Observe("read", fallback.Rally("fallback"));
        Check(fallback.Overlay.Items.Single().Rally?.Text == "rally test" && fallback.Sounds == 1,
            "missing banner uses overlay even when overlay switch off");
        using var soundOnly = new Fixture(banner: false, overlay: false);
        await soundOnly.Eligible(); await soundOnly.Observe("read", soundOnly.Rally("sound-only"));
        Check(soundOnly.Sounds == 1, "missing visual sink does not gate sound");
    }
    private static async Task SettingsAndPreview()
    {
        using var f = new Fixture();
        var legacy = new { schemaVersion = 1, revision = 4, inAppEnabled = true, position = "bottomRight", preview = "hiddenDetails", overlayEnabled = false };
        File.WriteAllText(Path.Combine(f.Root, "notification-settings.v1.json"), JsonSerializer.Serialize(legacy));
        var read = await f.Call("read", new { schemaVersion = 1 });
        Check(read.Status == "ok" && read.Payload.GetProperty("rallyAlerts").GetBoolean(), "legacy file defaults rallyAlerts to true");
        async Task<BridgeEnvelope> Save(int revision, bool? enabled)
        {
            var payload = new Dictionary<string, object> { ["schemaVersion"] = 1, ["expectedRevision"] = revision,
                ["inAppEnabled"] = false, ["position"] = "topLeft", ["preview"] = "hiddenDetails" };
            if (enabled.HasValue) payload["rallyAlerts"] = enabled.Value;
            return await f.Call("save", payload);
        }
        var saved = await Save(4, false);
        read = await f.Call("read", new { schemaVersion = 1 });
        Check(saved.Status == "ok" && saved.Payload.GetProperty("revision").GetInt32() == 5 &&
            !read.Payload.GetProperty("rallyAlerts").GetBoolean(), "rallyAlerts false round trip with revision");
        saved = await Save(5, null);
        Check(saved.Status == "ok" && !saved.Payload.GetProperty("rallyAlerts").GetBoolean(), "omitted rallyAlerts preserves false");
        Check((await Save(5, true)).Error?.Code == "notificationSettings.write_conflict", "rallyAlerts retains revision conflict");
        var preview = await f.Call("previewRally", new { schemaVersion = 1 });
        Check(preview.Status == "ok" && preview.Payload.GetProperty("schemaVersion").GetInt32() == 1 &&
            preview.Payload.GetProperty("banner").GetBoolean() && preview.Payload.GetProperty("sound").GetBoolean() && f.Sounds == 1,
            "preview submission result ignores rallyAlerts false");
        var sample = f.Banner.Items.Single();
        Check(sample.Sample && sample.Text == "" && sample.ExpiresAt == f.Time.Now.AddMinutes(30) &&
            sample.Preview == "hiddenDetails" && sample.IsCurrent(), "sample notice fields");
        f.Time.Advance(TimeSpan.FromSeconds(7));
        Check(sample.IsCurrent(), "sample current before 8 seconds");
        f.Time.Advance(TimeSpan.FromSeconds(1));
        Check(!sample.IsCurrent(), "sample expires at 8 seconds without waiting");
        f.Banner.Mode = "false"; f.SoundResult = false;
        preview = await f.Call("previewRally", new { schemaVersion = 1 });
        Check(!preview.Payload.GetProperty("banner").GetBoolean() && !preview.Payload.GetProperty("sound").GetBoolean(),
            "preview reports independent rejections");
        Check((await f.Call("previewRally", new { schemaVersion = 1, extra = true })).Error?.Code == "notificationSettings.invalid_request",
            "preview rejects extra fields");
        Check((await f.Call("previewRally", new { schemaVersion = 2 })).Error?.Code == "notificationSettings.invalid_request",
            "preview rejects unsupported schema");
        saved = await Save(6, true); saved = await Save(7, null);
        Check(saved.Status == "ok" && saved.Payload.GetProperty("rallyAlerts").GetBoolean(), "true round trip and omission");
        Check(NotificationSettingsBridgeDispatcher.AdvertisedCapabilities.Contains("notificationSettings.rallyAlerts") &&
            NotificationSettingsBridgeDispatcher.AdvertisedCapabilities.Contains("notificationSettings.previewRally"), "rally capabilities advertised");
        Check(!BridgeRequestPolicy.RequiresAccountContext("notificationSettings.previewRally"), "preview wire policy is device local");
        using var fallback = new Fixture(banner: false);
        fallback.Settings(enabled: false);
        preview = await fallback.Call("previewRally", new { schemaVersion = 1 });
        var overlay = fallback.Overlay.Items.Single();
        Check(preview.Payload.GetProperty("banner").GetBoolean() && overlay.Rally?.Text == "" &&
            overlay.Rally.Sample && overlay.IsCurrent(), "preview overlay fallback preserves sample with empty text");
        fallback.Time.Advance(TimeSpan.FromSeconds(8));
        Check(!overlay.IsCurrent(), "overlay preview expires at 8 seconds");
        using var noVisual = new Fixture(banner: false, overlay: false);
        preview = await noVisual.Call("previewRally", new { schemaVersion = 1 });
        Check(!preview.Payload.GetProperty("banner").GetBoolean() && preview.Payload.GetProperty("sound").GetBoolean(), "preview sound independent of missing visual sink");
    }
    private sealed class AudioOutput : INotificationAudioOutput
    {
        internal readonly List<byte[]> Played = [];
        public bool TryPlay(byte[] wave) { Played.Add(wave); return true; }
        public void Stop() { }
        public void Dispose() { }
    }
    private static void Audio()
    {
        var root = Path.Combine(Path.GetTempPath(), "cx69-audio-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var rally = NotificationAudioTests.Wave(16);
            var action = NotificationAudioTests.Wave(24);
            File.WriteAllBytes(Path.Combine(root, "rally.wav"), rally);
            File.WriteAllBytes(Path.Combine(root, "action.wav"), action);
            File.WriteAllText(Path.Combine(root, "cue-catalog.v1.json"), JsonSerializer.Serialize(new { schemaVersion = 1, assets = new[] {
                new { assetId = "rally", cueId = NotificationAudioCueIds.Rally, fileName = "rally.wav", tier = "approved", priority = 320, sha256 = Convert.ToHexString(SHA256.HashData(rally)) },
                new { assetId = "action", cueId = NotificationAudioCueIds.Action, fileName = "action.wav", tier = "approved", priority = 320, sha256 = Convert.ToHexString(SHA256.HashData(action)) },
                new { assetId = "achievement", cueId = NotificationAudioCueIds.Achievement, fileName = "achievement.wav", tier = "approved", priority = 320, sha256 = Convert.ToHexString(SHA256.HashData(action)) }
            }}));
            File.WriteAllBytes(Path.Combine(root, "achievement.wav"), action);
            var output = new AudioOutput(); var time = new Clock(); var menu = false;
            var celebration = new StarBridge.HostRuntime.Achievements.AchievementCelebrationActivity();
            var store = new NotificationAudioSettingsStore(root);
            using var audio = new NotificationAudioBridgeDispatcher(root, NotificationAudioCatalog.Load(root), output, () => 1,
                time: time, canPlaySocial: () => true, menuVisible: () => menu, celebration: celebration);
            Check(!audio.TryPlayRally(() => true) && output.Played.Count == 0, "disabled rally audio silent");
            store.Save(0, true, 0);
            Check(!audio.TryPlayRally(() => true) && output.Played.Count == 0, "zero volume rally audio silent");
            store.Save(1, true, 1, doNotDisturb: true);
            Check(!audio.TryPlayRally(() => false), "stale rally audio silent");
            Check(audio.TryPlayRally(() => true) && output.Played.Last().SequenceEqual(rally), "dedicated rally cue and no source DND gate");
            Check(!audio.TryPlayRally(() => true) && output.Played.Count == 1, "rally audio throttled");
            time.Advance(TimeSpan.FromMilliseconds(999));
            Check(!audio.TryPlayRally(() => true), "rally throttle before one second");
            time.Advance(TimeSpan.FromMilliseconds(1));
            File.Delete(Path.Combine(root, "rally.wav"));
            Check(audio.TryPlayRally(() => true) && output.Played.Last().SequenceEqual(action), "missing rally asset falls back to action at one second");
            time.Advance(TimeSpan.FromSeconds(1)); menu = true;
            Check(!audio.TryPlayRally(() => true), "open menu respects disabled menu sound");
            var prefs = new MenuPreferencesStore(root);
            prefs.Save(0, MenuPreferencesStore.Default.Layout, BridgePayload.From(new {
                showClock = true, showContext = true, dimming = .5,
                social = new { friendSort = "onlineFirst", sound = true, notifications = true } }));
            Check(audio.TryPlayRally(() => true), "open menu allows enabled menu sound");
            time.Advance(TimeSpan.FromSeconds(2)); menu = false;
            celebration.Report(true);
            Check(audio.TryPlayAchievement(() => true) && !audio.TryPlayRally(() => true), "achievement excludes rally audio");
            time.Advance(TimeSpan.FromSeconds(6));
            audio.DrainDeferred();
            Check(output.Played.Last().SequenceEqual(NotificationWaveGain.Apply(action, 1, 160)), "rally cannot replace a held achievement");
            audio.StopAchievement(); celebration.Report(false); audio.DrainDeferred();
            Check(output.Played.Last().SequenceEqual(action), "queued rally audio resumes after playback ends");
            var journal = File.ReadAllText(Path.Combine(root, "notification-delivery-diagnostics.log"));
            Check(journal.Contains("ChannelDisabled") && journal.Contains("Throttled") && journal.Contains("NativeAccepted"), "rally audio records delivery diagnostics");
        }
        finally { Directory.Delete(root, true); }
    }
}
