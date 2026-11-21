using System.Text.Json;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

// 11-08: an old online user whose guide receipt and local identity were missing saw
// "identity not confirmed" with the recording switch shown off, although the switch
// was on in the saved file. Recording permission is now separate from the owner:
// the saved settings stay readable, nothing is recorded or written.
internal static class GameplayRecordingGateTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "synthetic-recording-gate");

    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = DateTimeOffset.UnixEpoch;
        internal ManualTimer? Timer;
        public override DateTimeOffset GetUtcNow() => Now;
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period) =>
            Timer = new(callback, state);
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
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "starbridge-recording-gate-" + Guid.NewGuid().ToString("N"));
        internal readonly Clock Time = new();
        internal bool Allowed = true;
        internal bool OwnerResolves = true;
        internal GameplayTimeRuntime Runtime;
        internal Harness() { Runtime = Create(); }
        internal GameplayTimeRuntime Create()
        {
            var store = new GameplayTimeStore(Root)
            {
                ResolveOwner = owner => OwnerResolves ? owner
                    : throw new StarBridge.HostRuntime.Privacy.LocalPrivacyOwnerUnavailableException()
            };
            return new(store, () => (Owner, 1), () => new LocalGamePresenceSnapshot(1, "running"), Time,
                recordingAllowed: () => Allowed);
        }
        internal JsonElement Call(string name = "read", object? body = null)
        {
            var result = Runtime.Dispatch(BridgeEnvelope.Request("gameplayTime." + name, Guid.NewGuid().ToString("N"), 1,
                body ?? new { schemaVersion = 1 }, Owner)).Response;
            Require(result.Status == "ok", "Expected a projection for " + name + ": " + result.Error?.Code);
            return result.Payload;
        }
        internal string File() => Directory.GetFiles(Root, "*.json", SearchOption.AllDirectories).Single();
        public void Dispose()
        {
            Runtime.Dispose();
            if (Directory.Exists(Root)) Directory.Delete(Root, true); // Only this test's unique fixture directory.
        }
    }

    internal static Task Run()
    {
        WithheldShowsSavedSettingsAndRecordsNothing();
        RestartWhileWithheldNeverWrites();
        OwnerLossKeepsTheShownSwitches();
        return Task.CompletedTask;
    }

    private static void WithheldShowsSavedSettingsAndRecordsNothing()
    {
        using var h = new Harness();
        h.Call("setConsent", new { schemaVersion = 1, allowed = true });
        h.Call("setVisibility", new { schemaVersion = 1, showOnProfile = false });
        h.Time.Tick(5); h.Time.Tick(5);
        var saved = h.Call().GetProperty("seconds").GetInt64();
        Require(saved > 0, "Recording ran while allowed.");
        var bytes = System.IO.File.ReadAllBytes(h.File());

        h.Allowed = false;
        var withheld = h.Call();
        Require(withheld.GetProperty("consent").GetString() == "allowed", "Withheld read shows the saved consent: " + withheld.GetRawText());
        Require(!withheld.GetProperty("showOnProfile").GetBoolean(), "Withheld read shows the saved visibility.");
        Require(!withheld.GetProperty("recording").GetBoolean(), "Nothing records while withheld.");
        Require(withheld.GetProperty("error").GetString() == "gameplay.account_changed", "The identity notice code is kept for the client.");
        h.Time.Tick(5); h.Time.Tick(5); h.Time.Tick(5);
        Require(h.Call().GetProperty("seconds").GetInt64() == saved, "No time is added while withheld.");

        var stop = h.Call("setConsent", new { schemaVersion = 1, allowed = false });
        Require(stop.GetProperty("consent").GetString() == "allowed", "A switch change is not applied while withheld.");
        h.Call("setVisibility", new { schemaVersion = 1, showOnProfile = true });
        h.Call("retry");
        Require(System.IO.File.ReadAllBytes(h.File()).SequenceEqual(bytes), "Nothing is written while withheld.");

        h.Allowed = true;
        var back = h.Call();
        Require(!back.TryGetProperty("error", out var error) || error.ValueKind == JsonValueKind.Null, "Allowed again: no notice. " + back.GetRawText());
        h.Time.Tick(5); h.Time.Tick(5);
        Require(h.Call().GetProperty("seconds").GetInt64() > saved, "Recording resumes with the saved consent, no retry needed.");
    }

    private static void RestartWhileWithheldNeverWrites()
    {
        using var h = new Harness();
        h.Call("setConsent", new { schemaVersion = 1, allowed = true });
        h.Time.Tick(5); h.Time.Tick(5);
        var bytes = System.IO.File.ReadAllBytes(h.File());
        h.Runtime.Dispose();
        h.Allowed = false;
        h.Runtime = h.Create();
        var cold = h.Call();
        Require(cold.GetProperty("consent").GetString() == "allowed" && cold.GetProperty("seconds").GetInt64() > 0,
            "A restart while withheld still reads the saved settings: " + cold.GetRawText());
        h.Time.Tick(5); h.Time.Tick(5);
        Require(System.IO.File.ReadAllBytes(h.File()).SequenceEqual(bytes), "A restart while withheld never writes.");

        // A new account file is not created with defaults either.
        using var fresh = new Harness { Allowed = false };
        fresh.Runtime.Dispose(); fresh.Runtime = fresh.Create();
        var none = fresh.Call();
        Require(!none.GetProperty("recording").GetBoolean() && none.GetProperty("error").GetString() == "gameplay.account_changed",
            "A new account waits for a confirmed identity.");
        // Opening the account takes its lock, which may create an empty lock file
        // (CX-RECORDING-GATE-R1 #2, documented); no data file and no bytes.
        Require(!Directory.Exists(fresh.Root) || Directory.GetFiles(fresh.Root, "*", SearchOption.AllDirectories)
                .All(file => file.EndsWith(".lock", StringComparison.Ordinal) && new FileInfo(file).Length == 0),
            "Nothing but an empty lock file exists for a new account while withheld.");

        // CX-RECORDING-GATE-R1 #1: an unreadable guide file is not consulted while
        // withheld, so it cannot replace the saved settings with a generic error.
        using var broken = new Harness { Allowed = false };
        broken.Runtime.Dispose();
        Directory.CreateDirectory(Path.Combine(broken.Root, "local-first-use-v1"));
        System.IO.File.WriteAllBytes(Path.Combine(broken.Root, "local-first-use-v1", "state.bin"), new byte[] { 1, 2, 3, 4 });
        broken.Runtime = broken.Create();
        var guarded = broken.Call();
        Require(guarded.GetProperty("error").GetString() == "gameplay.account_changed",
            "Withheld read ignores the unreadable guide file: " + guarded.GetRawText());
    }

    private static void OwnerLossKeepsTheShownSwitches()
    {
        using var h = new Harness();
        h.Call("setConsent", new { schemaVersion = 1, allowed = true });
        h.Call("setVisibility", new { schemaVersion = 1, showOnProfile = false });
        h.OwnerResolves = false;
        var lost = h.Call();
        // User 11-15 ("1 推荐，2 可以"): a temporary owner loss after a confirmed login is a
        // connection pause held for up to 30 minutes, not "check your Handle". The full
        // owner-continuity rules live in GameplayTransient073Tests.
        Require((!lost.TryGetProperty("error", out var lostError) || lostError.ValueKind == JsonValueKind.Null) &&
            lost.GetProperty("pauseReason").GetString() == "connection", "Owner loss is a connection pause: " + lost.GetRawText());
        Require(lost.GetProperty("consent").GetString() == "allowed" && !lost.GetProperty("showOnProfile").GetBoolean(),
            "Owner loss keeps the switches it showed, not off/defaults: " + lost.GetRawText());
        h.OwnerResolves = true;
        var back = h.Call();
        Require(back.GetProperty("consent").GetString() == "allowed" && (!back.TryGetProperty("error", out var error) || error.ValueKind == JsonValueKind.Null),
            "Owner back: saved settings again. " + back.GetRawText());
    }

    private static void Require(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
}
