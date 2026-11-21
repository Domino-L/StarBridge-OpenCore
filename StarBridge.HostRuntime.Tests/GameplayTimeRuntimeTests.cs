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
            Require(dueTime == Timeout.InfiniteTimeSpan && period == dueTime,
                "Original sampling timer is installed while paused.");
            return Timer = new(callback, state);
        }
        internal void Tick(int seconds) { Now = Now.AddSeconds(seconds); Timer!.Fire(); }
    }
    private sealed class ManualTimer(TimerCallback callback, object? state) : ITimer
    {
        internal bool Disposed;
        internal void Fire() { if (!Disposed) callback(state); }
        public bool Change(TimeSpan dueTime, TimeSpan period)
        {
            Require(dueTime == TimeSpan.FromSeconds(5) && period == dueTime,
                "Independent five-second Host sampling.");
            return !Disposed;
        }
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
    // Build 71 (11-06): one failed read left recording stopped with no diagnostics
    // until a manual retry or restart. Failures now name a reason code (never
    // contents or account ids) and reload on a backoff without overwriting the file.
    internal static Task FailuresLogAndRecoverOnBackoff()
    {
        var journal = new List<string>();
        using var capture = StarBridge.HostRuntime.Support.IdentityGateJournal.Capture((stage, value) => journal.Add(stage + " " + value));
        using var h = new Harness();
        h.Call("setConsent", true); h.Time.Tick(5); h.Time.Tick(5);
        var path = Directory.GetFiles(h.Root, "*.json", SearchOption.AllDirectories).Single();
        var prefix = Path.GetFileNameWithoutExtension(path)[..8];
        var valid = File.ReadAllText(path);
        var saved = JsonDocument.Parse(valid).RootElement.GetProperty("snapshot").GetProperty("seconds").GetInt64();

        // A field this version does not know (a newer or branch build wrote it).
        var foreign = valid.Replace("\"snapshot\":{", "\"snapshot\":{\"futureField\":1,", StringComparison.Ordinal);
        Require(foreign != valid, "Fixture adds an unknown snapshot field.");
        File.WriteAllText(path, foreign);
        h.Runtime.Dispose(); h.Runtime = h.Create();
        Require(h.Call().GetProperty("error").GetString() == "gameplay.read_failed", "Unknown field is a read failure.");
        Require(journal.Contains($"gameplay-store code=read_failed file={prefix} reason=unknown-field"),
            "Store names the failed check and the file prefix: " + string.Join(" | ", journal));
        Require(journal.Any(e => e.StartsWith("gameplay-runtime code=read_failed exception=none retry=30", StringComparison.Ordinal)),
            "Runtime logs the reason code and its retry delay.");
        Require(journal.All(e => !e.Contains(Owner.Subject, StringComparison.Ordinal) && !e.Contains(h.Root, StringComparison.Ordinal)),
            "No account id or path in the journal.");
        Require(File.ReadAllText(path) == foreign, "An unreadable file is never rewritten.");

        // Still failing at the first retry: backoff doubles, file untouched.
        h.Time.Tick(31);
        Require(h.Call().GetProperty("error").GetString() == "gameplay.read_failed", "Still unreadable after the first retry.");
        Require(File.ReadAllText(path) == foreign, "Retries never rewrite the file.");
        // Same reason again: no second full line, only a count.
        Require(journal.Count(e => e == $"gameplay-store code=read_failed file={prefix} reason=unknown-field") == 1 &&
            journal.Contains($"gameplay-store code=read_failed file={prefix} reason=unknown-field count=2") &&
            journal.Count(e => e.StartsWith("gameplay-runtime code=read_failed exception=", StringComparison.Ordinal)) == 1 &&
            journal.Contains("gameplay-runtime code=read_failed count=2"),
            "Repeats are counted, not logged in full: " + string.Join(" | ", journal));
        // Many more failures stay bounded: counts only at powers of two.
        for (var i = 0; i < 12; i++) { h.Time.Tick(601); h.Call(); }
        Require(journal.Count(e => e.StartsWith("gameplay-store code=read_failed", StringComparison.Ordinal)) <= 5,
            "Fourteen failures write at most five store lines.");
        Require(File.ReadAllText(path) == foreign, "Repeated retries never rewrite the file.");

        // The file becomes readable again: the next backoff reloads by itself, no retry button.
        File.WriteAllText(path, valid);
        h.Time.Tick(30);
        Require(h.Call().GetProperty("error").GetString() == "gameplay.read_failed", "No reload before the backoff passes.");
        h.Time.Tick((int)GameplayTimeRuntime.MaximumRetryDelay.TotalSeconds + 1);
        var recovered = h.Call();
        Require(!recovered.TryGetProperty("error", out _),
            "Reloads after the backoff without a manual retry.");
        Require(recovered.GetProperty("seconds").GetInt64() == saved, "Saved time is intact.");
        Require(journal.Contains("gameplay-runtime code=recovered"), "Recovery is logged.");
        h.Time.Tick(5); h.Time.Tick(5);
        var resumed = h.Seconds();
        Require(resumed > saved, "Recording continues after recovery.");

        // Another process holds the lock: storage_unavailable, then recovers once it is released.
        h.Runtime.Dispose();
        var holder = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        h.Runtime = h.Create();
        Require(h.Call().GetProperty("error").GetString() == "gameplay.storage_unavailable", "Held lock is storage_unavailable.");
        Require(journal.Any(e => e.StartsWith($"gameplay-store code=storage_unavailable file={prefix} exception=IOException", StringComparison.Ordinal)),
            "Held lock is logged with the file prefix.");
        holder.Dispose();
        h.Time.Tick(31);
        var freed = h.Call();
        Require(!freed.TryGetProperty("error", out _) && freed.GetProperty("seconds").GetInt64() == resumed,
            "Recovers once the lock is free.");
        return Task.CompletedTask;
    }

    // CX-GAMEPLAY-DIAG-073-R #1: a page that loaded before, its lease released by an
    // account switch, then a reopen that fails: no disk access until the backoff passes.
    internal static Task SuspendedReopenWaitsForBackoff()
    {
        var journal = new List<string>();
        using var capture = StarBridge.HostRuntime.Support.IdentityGateJournal.Capture((stage, value) => journal.Add(stage + " " + value));
        using var h = new Harness();
        h.Call("setConsent", true); h.Time.Tick(5); h.Time.Tick(5);
        var saved = h.Seconds();
        var path = Directory.GetFiles(h.Root, "*.json", SearchOption.AllDirectories).Single();
        h.Current = (new BridgeAccountContext("test", "scm", "synthetic-other"), 2);
        h.Call(); // Switch away: the first owner's lease is released (Suspend).
        using (var holder = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
        {
            h.Current = (Owner, 3);
            Require(h.Call().GetProperty("error").GetString() == "gameplay.storage_unavailable", "Reopen fails while the lock is held.");
            // Samples every 5 s and reads inside the 30 s backoff must not reopen the file.
            for (var i = 0; i < 5; i++) { h.Time.Tick(5); h.Call(); }
            Require(!journal.Any(e => e.StartsWith("gameplay-store code=storage_unavailable", StringComparison.Ordinal) &&
                    e.Contains(" count=", StringComparison.Ordinal)),
                "No second open inside the backoff: " + string.Join(" | ", journal));
        }
        h.Time.Tick(6); // 31 s since the failure, lock released.
        var back = h.Call();
        Require(!back.TryGetProperty("error", out _) && back.GetProperty("seconds").GetInt64() == saved,
            "Reopens once the backoff passes, saved time intact: " + back.GetRawText());
        return Task.CompletedTask;
    }

    // CX-GAMEPLAY-DIAG-073-R #2: a recording-owner gate that keeps flipping.
    internal static Task OwnerGateFlipsDoNotFlood()
    {
        var journal = new List<string>();
        using var capture = StarBridge.HostRuntime.Support.IdentityGateJournal.Capture((stage, value) => journal.Add(stage + " " + value));
        var owner = new GameplayFailureJournal();
        const string none = "code=none reason=game-identity-not-ready";
        for (var i = 0; i < 20; i++)
        {
            owner.RecordChange("gameplay-owner", none);
            owner.RecordChange("gameplay-owner", none); // Same state on the next sample: nothing.
            owner.RecordChange("gameplay-owner", "code=ok");
        }
        Require(journal.Count(e => e == "gameplay-owner " + none) == 1 && journal.Count(e => e == "gameplay-owner code=ok") == 1,
            "Each reason is written in full once: " + string.Join(" | ", journal));
        Require(journal.Where(e => e.StartsWith("gameplay-owner " + none + " count=", StringComparison.Ordinal))
                .SequenceEqual(new[] { 2, 4, 8, 16 }.Select(n => "gameplay-owner " + none + " count=" + n)),
            "Repeats only at 2, 4, 8, 16: " + string.Join(" | ", journal));
        Require(journal.Count <= 10, "Forty flips write at most ten lines.");
        return Task.CompletedTask;
    }

    // Build 71 restart (11-06 22:50Z): the local owner was "no-binding" for about two
    // seconds after start, then ok. Recording must resume with the file's own consent.
    internal static Task EarlyOwnerGapResumesWithSavedConsent()
    {
        using var h = new Harness();
        h.Call("setConsent", true); h.Time.Tick(5); h.Time.Tick(5);
        var saved = h.Seconds();
        var path = Directory.GetFiles(h.Root, "*.json", SearchOption.AllDirectories).Single();
        var before = File.ReadAllBytes(path);
        h.Runtime.Dispose();
        var ownerReady = false;
        var store = new GameplayTimeStore(h.Root)
        {
            ResolveOwner = owner => ownerReady ? owner
                : throw new StarBridge.HostRuntime.Privacy.LocalPrivacyOwnerUnavailableException()
        };
        h.Runtime = new GameplayTimeRuntime(store, () => h.Current, () => h.Presence, h.Time);
        var gap = h.Runtime.Dispatch(h.Request()).Response;
        Require(gap.Status != "ok" || gap.Payload.TryGetProperty("error", out _), "The gap reports an error.");
        h.Time.Tick(1);
        Require(File.ReadAllBytes(path).SequenceEqual(before), "The gap never writes the file (consent stays as saved).");
        ownerReady = true;
        h.Time.Tick(5);
        var resumed = h.Call();
        Require(!resumed.TryGetProperty("error", out _), "Owner back: no error. " + resumed.GetRawText());
        Require(resumed.GetProperty("consent").GetString() == "allowed", "Saved consent is used again.");
        Require(resumed.GetProperty("seconds").GetInt64() == saved, "Saved time intact.");
        h.Time.Tick(5); h.Time.Tick(5);
        Require(h.Seconds() > saved, "Recording resumes without a retry.");

        // No recording owner at all (the front check): named once, then only counted.
        var journal = new List<string>();
        using var capture = StarBridge.HostRuntime.Support.IdentityGateJournal.Capture((stage, value) => journal.Add(stage + " " + value));
        var noOwner = new GameplayTimeRuntime(new GameplayTimeStore(h.Root), () => (null, 1), () => h.Presence, h.Time, startTimer: false);
        for (var i = 0; i < 3; i++)
            Require(noOwner.Dispatch(h.Request()).Response.Status != "ok", "No owner is refused.");
        noOwner.Dispose();
        Require(journal.Count(e => e == "gameplay-runtime code=refused reason=no-owner") == 1 &&
            journal.Contains("gameplay-runtime code=refused reason=no-owner count=2") &&
            journal.All(e => !e.Contains(Owner.Subject, StringComparison.Ordinal)),
            "Refusal names its check once, then counts: " + string.Join(" | ", journal));
        Require(File.ReadAllBytes(path).Length > 0, "Refusals never touch the file.");
        return Task.CompletedTask;
    }

    private static void Require(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
}
