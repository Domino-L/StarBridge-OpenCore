using System.Text.Json;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class GameplayTimeRuntimeTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "synthetic-playtime");
    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = DateTimeOffset.UnixEpoch;
        internal ManualTimer? Timer;
        public override DateTimeOffset GetUtcNow() => Now;
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        {
            Require(dueTime == TimeSpan.FromSeconds(5) && period == dueTime, "Independent five-second Host sampling.");
            return Timer = new(callback, state);
        }
        internal void Tick(int seconds) { Now = Now.AddSeconds(seconds); Timer!.Fire(); }
    }
    private sealed class ManualTimer(TimerCallback callback, object? state) : ITimer
    {
        internal bool Disposed;
        internal void Fire() { if (!Disposed) callback(state); }
        public bool Change(TimeSpan dueTime, TimeSpan period) => !Disposed;
        public void Dispose() => Disposed = true;
        public ValueTask DisposeAsync() { Dispose(); return ValueTask.CompletedTask; }
    }
    private sealed class Harness : IDisposable
    {
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "starbridge-gameplay-test-" + Guid.NewGuid().ToString("N"));
        internal readonly Clock Time = new();
        internal (BridgeAccountContext? Context, long Generation) Current = (Owner, 1);
        internal LocalGamePresenceSnapshot Presence = new(1, "running");
        internal int Observations;
        internal GameplayTimeRuntime Runtime;
        internal Harness()
        {
            Runtime = Create();
        }
        internal GameplayTimeRuntime Create() => new(new GameplayTimeStore(Root), () => Current,
            () => { Observations++; return Presence; }, Time);
        internal BridgeEnvelope Request(string name = "read", bool? allowed = null,
            BridgeAccountContext? owner = null, long? generation = null) =>
            BridgeEnvelope.Request("gameplayTime." + name, Guid.NewGuid().ToString("N"),
                generation ?? Current.Generation,
                allowed is null ? new { schemaVersion = 1 } : (object)new { schemaVersion = 1, allowed = allowed.Value },
                owner ?? Current.Context);
        internal JsonElement Call(string name = "read", bool? allowed = null)
        {
            var result = Runtime.Dispatch(Request(name, allowed)).Response;
            Require(result.Status == "ok", "Expected successful scoped response.");
            return result.Payload;
        }
        internal long Seconds() => Call().GetProperty("seconds").GetInt64();
        public void Dispose()
        {
            Runtime.Dispose();
            if (Directory.Exists(Root)) Directory.Delete(Root, true); // Only this test's unique fixture directory.
        }
    }

    internal static Task ConsentAndReopen()
    {
        using var h = new Harness();
        Require(h.Call().GetProperty("consent").GetString() == "allowed", "New accounts record by default.");
        Require(h.Call().GetProperty("showOnProfile").GetBoolean(), "New accounts show time by default.");
        Require(Directory.GetFiles(h.Root, "*.json", SearchOption.AllDirectories).Length == 1, "Defaults saved before recording.");
        h.Call("setConsent", true);
        h.Time.Tick(5); h.Time.Tick(5);
        Require(h.Seconds() == 5, "Independent timer records without any page/read operation.");
        h.Call("setConsent", false); h.Time.Tick(5);
        Require(h.Seconds() == 5 && !h.Call().GetProperty("recording").GetBoolean(), "Stop preserves and suspends.");
        h.Runtime.Dispose();
        Require(h.Time.Timer!.Disposed, "Disposal cancels timer.");
        h.Runtime = h.Create();
        Require(h.Call().GetProperty("consent").GetString() == "declined" && h.Seconds() == 5, "Reopen preserves choice and total.");
        h.Call("setConsent", true); h.Time.Tick(3600); h.Time.Tick(5);
        Require(h.Seconds() == 10, "Reopen/resume never adds the closed gap.");
        h.Time.Tick(3600);
        Require(h.Seconds() == 10, "Sleep is excluded.");
        h.Presence = new(1, "unknown"); h.Time.Tick(5);
        Require(!h.Call().GetProperty("recording").GetBoolean(), "Uncertain observation pauses.");
        h.Presence = new(1, "running"); h.Time.Tick(5); h.Time.Tick(5);
        Require(h.Seconds() == 15, "Recovery starts a fresh interval.");
        h.Presence = new(1, "notRunning"); h.Time.Tick(5); h.Time.Tick(5);
        Require(h.Seconds() == 20 && !h.Call().GetProperty("recording").GetBoolean(), "Final exit interval counted once.");
        return Task.CompletedTask;
    }

    internal static Task OwnershipAndProtocol()
    {
        using var h = new Harness();
        h.Call("setConsent", true); h.Time.Tick(5); h.Time.Tick(5);
        var original = h.Current;
        foreach (var owner in new[] { Owner with { Environment = "other" }, Owner with { Authority = "other" },
            Owner with { Subject = "other" } })
        {
            h.Current = (owner, h.Current.Generation + 1); h.Runtime.Suspend();
            Require(h.Seconds() == 0 && h.Call().GetProperty("consent").GetString() == "allowed", "All owner fields isolate.");
            var stale = h.Runtime.Dispatch(h.Request("setConsent", true, original.Context, original.Generation));
            Require(stale.Response.Error?.Code == "gameplay.account_changed", "Stale owner cannot enable recording.");
        }
        h.Current = (Owner, h.Current.Generation + 1); h.Runtime.Suspend(); h.Time.Tick(5);
        Require(h.Seconds() == 5, "Returning owner resumes without counting time spent on another account.");
        var bad = h.Request("setConsent", true) with { Payload = BridgePayload.From(new { schemaVersion = 2, allowed = true }) };
        Require(h.Runtime.Dispatch(bad).Response.Error?.Code == "gameplay.invalid_request", "Version is required.");
        bad = h.Request() with { Payload = JsonDocument.Parse("{\"schemaVersion\":1,\"schemaVersion\":1}").RootElement.Clone() };
        Require(h.Runtime.Dispatch(bad).Response.Error?.Code == "gameplay.invalid_request", "Duplicate fields rejected.");
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        Require(h.Runtime.Dispatch(h.Request("setConsent", false), cancelled.Token).Response.Status == "error", "Cancelled write not applied.");
        h.Current = (null, 99); h.Runtime.Suspend(); h.Time.Tick(5);
        Require(h.Runtime.Dispatch(h.Request()).Response.Error?.Code == "gameplay.account_changed", "Signed-out projection has no data.");
        return Task.CompletedTask;
    }

    internal static Task StorageFailures()
    {
        using var h = new Harness();
        h.Call("setConsent", true); h.Time.Tick(5); h.Time.Tick(5);
        var path = Directory.GetFiles(h.Root, "*.json", SearchOption.AllDirectories).Single();
        var valid = File.ReadAllText(path);
        using (var other = new GameplayTimeRuntime(new(h.Root), () => h.Current, startTimer: false))
        {
            var duplicate = other.Dispatch(h.Request()).Response.Payload;
            Require(duplicate.GetProperty("error").GetString() == "gameplay.storage_unavailable", "Only one recorder per account.");
        }
        File.WriteAllText(path, "{}");
        h.Time.Tick(5);
        Require(h.Call().GetProperty("error").GetString() == "gameplay.read_failed", "Damaged file pauses without replacement.");
        Require(!h.Call().GetProperty("recording").GetBoolean(), "Failure stops active accumulation.");
        h.Call("setConsent", false);
        h.Time.Tick(5); h.Time.Tick(5);
        Require(h.Call().GetProperty("consent").GetString() == "declined", "Stop stays effective even if the write fails.");
        Require(File.ReadAllText(path) == "{}", "Unreadable original preserved.");
        File.WriteAllText(path, valid);
        var restored = h.Call("retry");
        Require(!restored.TryGetProperty("error", out _) && h.Seconds() == 10, "Retry saves pending confirmed interval once.");
        h.Call("retry");
        Require(h.Seconds() == 10, "Retry is idempotent.");
        h.Runtime.Dispose(); h.Runtime = h.Create();
        Require(h.Call().GetProperty("consent").GetString() == "declined", "Retried stop survives restart.");
        // A failed allow is not active until an explicit successful retry.
        valid = File.ReadAllText(path);
        File.WriteAllText(path, "{}");
        h.Call("setConsent", true); h.Time.Tick(5);
        Require(!h.Call().GetProperty("recording").GetBoolean(), "Failed permission save cannot enable recording.");
        File.WriteAllText(path, valid);
        h.Call("retry"); h.Time.Tick(5); h.Time.Tick(5);
        Require(h.Seconds() == 15, "Allow retry resumes only from new confirmed samples.");
        h.Runtime.Dispose();
        File.WriteAllText(path, "{}");
        h.Runtime = h.Create();
        Require(!h.Call().TryGetProperty("seconds", out _), "Bad initial storage is not zero time.");
        h.Call("setConsent", true);
        Require(File.ReadAllText(path) == "{}", "Allow cannot reset corrupt storage.");
        h.Call("setConsent", false);
        Require(h.Call().GetProperty("consent").GetString() == "declined", "Stop intent survives missing initial state.");
        File.WriteAllText(path, valid);
        h.Call("retry"); h.Time.Tick(5); h.Time.Tick(5);
        Require(h.Call().GetProperty("consent").GetString() == "declined" && !h.Call().GetProperty("recording").GetBoolean(),
            "Recovery cannot restore/default Allowed over a stop made during initial read failure.");
        valid = File.ReadAllText(path);
        File.WriteAllText(path, "{}");
        h.Call("setConsent", true);
        File.WriteAllText(path, valid);
        var visible = h.Request("setVisibility") with { Payload = BridgePayload.From(new { schemaVersion = 1, showOnProfile = false }) };
        h.Runtime.Dispatch(visible);
        h.Time.Tick(5); h.Time.Tick(5);
        Require(h.Call().GetProperty("recording").GetBoolean(), "A successful visibility save also applies its persisted pending consent.");
        return Task.CompletedTask;
    }
    private static void Require(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
}
