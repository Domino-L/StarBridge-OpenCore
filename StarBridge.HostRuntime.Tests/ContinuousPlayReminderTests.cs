using StarBridge.HostRuntime.Reminders;
using StarBridge.HostRuntime;
using StarBridge.NativeBridge;

internal static class ContinuousPlayReminderTests
{
    private static readonly DateTimeOffset Origin = new(2026, 9, 10, 0, 0, 0, TimeSpan.Zero);
    internal static async Task DefaultsAndRepeat()
    {
        using var f = new Fixture();
        Check(await f.Runtime.ReadAsync() == new ContinuousPlaySettings(), "WPF defaults");
        await f.Tick(119); Check(f.Sink.Calls == 0, "not early");
        await f.Tick(120); Check(f.Sink.Calls == 1, "first due");
        await f.Tick(121); Check(f.Sink.Calls == 1, "no duplicate");
        await f.Tick(240); Check(f.Sink.Calls == 2, "repeat due");
    }
    internal static async Task DisabledAndReenabled()
    {
        using var f = new Fixture();
        await f.Runtime.SaveAsync(new(false), 0);
        await f.Tick(130); Check(f.Sink.Calls == 0, "disabled");
        await f.Runtime.SaveAsync(new(true), 1);
        await f.Tick(131); Check(f.Sink.Calls == 1, "reenable overdue once");
        await f.Tick(132); Check(f.Sink.Calls == 1, "no catchup flood");
    }
    internal static async Task IntervalChangeUsesSessionAndLastAccepted()
    {
        using var f = new Fixture(); await f.Tick(0);
        await f.Runtime.SaveAsync(new(true, 60, 60), 0);
        await f.Tick(60); Check(f.Sink.Calls == 1, "new first");
        await f.Runtime.SaveAsync(new(true, 180, 120), 1);
        await f.Tick(120); Check(f.Sink.Calls == 1, "new repeat no early");
        await f.Tick(180); Check(f.Sink.Calls == 2, "new repeat from last accepted");
    }
    internal static Task ShortRestartAndFifteenMinuteReset()
    {
        var settings = new ContinuousPlaySettings();
        var state = new ContinuousPlayState().Observe(new("running", Origin), Origin.AddMinutes(100), settings);
        state = state.Observe(new("notRunning"), Origin.AddMinutes(101), settings);
        state = state.Observe(new("running", Origin.AddMinutes(110)), Origin.AddMinutes(110), settings);
        Check(state.SessionStartedAtUtc == Origin, "short process restart retains session");
        state = state.Observe(new("notRunning"), Origin.AddMinutes(111), settings);
        state = state.Observe(new("notRunning"), Origin.AddMinutes(126), settings);
        Check(state.SessionStartedAtUtc is null, "exact 15 minute reset");
        state = state.Observe(new("running", Origin.AddMinutes(130)), Origin.AddMinutes(130), settings);
        Check(state.SessionStartedAtUtc == Origin.AddMinutes(130), "new session");
        state = state.Observe(new("running", Origin.AddMinutes(160)), Origin.AddMinutes(161), settings);
        Check(state.SessionStartedAtUtc == Origin.AddMinutes(160), "unobserved late replacement");
        return Task.CompletedTask;
    }
    internal static async Task RestartRecoversCheckpoint()
    {
        using var f = new Fixture(); await f.Tick(120);
        f.Runtime.Dispose();
        using var restored = new ContinuousPlayReminderRuntime(f.Store, () => f.Process, f.Sink, f.Clock);
        f.Clock.Now = Origin.AddMinutes(121); await restored.TickAsync();
        Check(f.Sink.Calls == 1, "restart does not repeat accepted reminder");
        f.Clock.Now = Origin.AddMinutes(240); await restored.TickAsync(); Check(f.Sink.Calls == 2, "restart repeats on due");
    }
    internal static async Task SuppressionAndFailureAreBounded()
    {
        using var f = new Fixture(); f.Sink.Accept = false;
        await f.Tick(120); Check(f.Sink.Calls == 1, "suppressed attempt");
        await f.Tick(120.1); Check(f.Sink.Calls == 1, "suppressed throttle");
        f.Sink.Throw = true; await f.Tick(121); await f.Tick(121.1);
        Check(f.Sink.Calls == 2 && f.Store.State.LastReminderAtUtc is null, "failure not accepted");
        f.Sink.Throw = false; f.Sink.Accept = true; await f.Tick(122);
        Check(f.Sink.Calls == 3 && f.Store.State.LastReminderAtUtc == Origin.AddMinutes(122), "recovered queue");
    }
    internal static async Task UnknownAndStorageFailureDoNotNotify()
    {
        using var f = new Fixture(); f.Process = new("unknown"); await f.Tick(120);
        Check(f.Sink.Calls == 0, "unknown not running");
        f.Process = new("running", Origin); f.Store.FailStateSave = true; await f.Tick(121);
        Check(f.Sink.Calls == 0, "no queue if checkpoint fails");
        f.Store.FailStateSave = false; await f.Tick(121.1); Check(f.Sink.Calls == 0, "storage backoff");
        await f.Tick(122); Check(f.Sink.Calls == 1, "storage recovered");
    }
    internal static async Task SaveInvalidatesPendingQueue()
    {
        using var f = new Fixture(); f.Sink.Hold = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var tick = f.Tick(120); await f.Sink.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));
        var save = f.Runtime.SaveAsync(new(false), 0);
        Check(!f.Sink.Current!(), "disable invalidates pending callback");
        f.Sink.Hold.SetResult(true); await tick; await save;
        Check(f.Store.State.LastReminderAtUtc is null, "stale queue not marked accepted");
    }
    internal static async Task BridgePersistsWithRevisionAndRejectsAccount()
    {
        using var f = new Fixture(); using var bridge = new ContinuousPlayBridgeDispatcher(f.Runtime, () => 2);
        Check(!BridgeRequestPolicy.RequiresAccountContext("playReminder.read") &&
            !BridgeRequestPolicy.RequiresAccountContext("playReminder.save"), "device scope allowlist");
        using var composite = new StarBridge.HostRuntime.CompositeBridgeDispatcher(
            new RejectDispatcher(), new RejectDispatcher(), new RejectDispatcher(), playReminder: bridge);
        var read = await composite.DispatchAsync(BridgeEnvelope.Request("playReminder.read", "read", 2,
            new { schemaVersion = 1 }));
        Check(read.Response.Status == "ok" && read.Response.Payload.GetProperty("enabled").GetBoolean() &&
            read.Response.Payload.GetProperty("revision").GetInt32() == 0 && read.Response.AccountContext is null,
            "composite routes signed-out device read with Flutter wire keys");
        var saved = await bridge.DispatchAsync(BridgeEnvelope.Request("playReminder.save", "save", 2,
            new { schemaVersion = 1, expectedRevision = 0, enabled = false, firstReminderMinutes = 90, repeatReminderMinutes = 60 }));
        Check(saved.Response.Status == "ok" && !f.Store.Settings.Enabled && f.Store.Settings.Revision == 1, "saved");
        var stale = await bridge.DispatchAsync(BridgeEnvelope.Request("playReminder.save", "stale", 2,
            new { schemaVersion = 1, expectedRevision = 0, enabled = true, firstReminderMinutes = 90, repeatReminderMinutes = 60 }));
        Check(stale.Response.Error?.Code == "playReminder.conflict", "stale revision");
        var account = await bridge.DispatchAsync(BridgeEnvelope.Request("playReminder.read", "account", 2,
            new { schemaVersion = 1 }, new("test", "local", "fixture")));
        Check(account.Response.Error?.Code == "playReminder.invalid_request", "device only");
    }
    internal static Task WpfSettingsCompatibilityAndCorruption()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-play-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var path = Path.Combine(root, "local-play-reminder.settings.json");
            File.WriteAllText(path, "{\"Enabled\":false,\"FirstReminderMinutes\":90,\"RepeatReminderMinutes\":60}");
            var store = new ContinuousPlayStore(root);
            Check(store.ReadSettings() == new ContinuousPlaySettings(false, 90, 60), "WPF format");
            store.SaveSettings(new(true, 180, 120, 1));
            Check(new ContinuousPlayStore(root).ReadSettings().Revision == 1, "real restart persistence");
            File.WriteAllText(path, "broken");
            try { store.ReadSettings(); throw new Exception("expected corrupt failure"); }
            catch (System.Text.Json.JsonException) { }
            Check(File.ReadAllText(path) == "broken", "corrupt data not overwritten");
        }
        finally { Directory.Delete(root, true); }
        return Task.CompletedTask;
    }
    private static void Check(bool condition, string label) { if (!condition) throw new Exception(label); }
    private sealed class RejectDispatcher : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
            => throw new Exception("Reminder must not use account or another dispatcher");
        public void Dispose() { }
    }
    private sealed class Clock : TimeProvider { internal DateTimeOffset Now = Origin; public override DateTimeOffset GetUtcNow() => Now; }
    private sealed class Store : IContinuousPlayStore
    {
        internal ContinuousPlaySettings Settings = new(); internal ContinuousPlayState State = new(); internal bool FailStateSave;
        public ContinuousPlaySettings ReadSettings() => Settings;
        public ContinuousPlayState ReadState() => State;
        public void SaveSettings(ContinuousPlaySettings value) => Settings = value;
        public void SaveState(ContinuousPlayState value) { if (FailStateSave) throw new IOException(); State = value; }
    }
    private sealed class Sink : IContinuousPlayReminderSink
    {
        internal int Calls; internal bool Accept = true; internal bool Throw;
        internal TaskCompletionSource<bool>? Hold; internal Func<bool>? Current;
        internal TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public async ValueTask<bool> TryQueueAsync(ContinuousPlayNotice notice, CancellationToken cancellation)
        { Calls++; Current = notice.IsCurrent; Started.TrySetResult(); if (Throw) throw new IOException(); return Hold is null ? Accept : await Hold.Task.WaitAsync(cancellation); }
    }
    private sealed class Fixture : IDisposable
    {
        internal readonly Clock Clock = new(); internal readonly Store Store = new(); internal readonly Sink Sink = new();
        internal PlayProcessObservation Process = new("running", Origin); internal readonly ContinuousPlayReminderRuntime Runtime;
        internal Fixture() { Runtime = new(Store, () => Process, Sink, Clock); }
        internal Task Tick(double minutes) { Clock.Now = Origin.AddMinutes(minutes); return Runtime.TickAsync(); }
        public void Dispose() => Runtime.Dispose();
    }
}
