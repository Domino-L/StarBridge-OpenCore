using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class GameplayTimeAccumulatorTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "synthetic-a");
    private static readonly LocalGamePresenceSnapshot Running = new(1, "running");
    private static readonly LocalGamePresenceSnapshot Stopped = new(1, "notRunning");
    private static readonly DateTimeOffset Epoch = DateTimeOffset.UnixEpoch;

    internal static Task ConsentAndOwnership()
    {
        var tracker = new GameplayTimeAccumulator();
        tracker.Restore(Owner, 1);
        Sample(tracker, 0); Sample(tracker, 5);
        Require(tracker.PlayTimeSeconds == 0 && !tracker.IsRecording, "Unknown consent must not record.");
        tracker.ApplyConsent(GameplayRecordingConsent.Allowed);
        Sample(tracker, 6); Sample(tracker, 11);
        Require(tracker.PlayTimeSeconds == 5 && tracker.IsRecording, "Allowed current owner records.");
        tracker.ApplyConsent(GameplayRecordingConsent.Declined);
        Sample(tracker, 16);
        Require(tracker.PlayTimeSeconds == 5 && !tracker.IsRecording, "Decline immediately stops without clearing totals.");
        tracker.ApplyConsent(GameplayRecordingConsent.Allowed);
        Sample(tracker, 20); Sample(tracker, 25);
        Require(tracker.PlayTimeSeconds == 10, "Re-allow cannot backfill the declined interval.");
        foreach (var other in new[] {
            Owner with { Environment = "other" }, Owner with { Authority = "other" }, Owner with { Subject = "Synthetic-a" }
        })
        {
            tracker.Observe(other, 1, Running, Epoch.AddSeconds(30));
            Require(!tracker.IsRecording && tracker.PlayTimeSeconds == 10, "All three owner fields are exact and isolated.");
            Sample(tracker, 25);
        }
        tracker.Observe(Owner, 2, Running, Epoch.AddSeconds(30));
        Require(!tracker.IsRecording && tracker.PlayTimeSeconds == 10, "Stale generation breaks the sample interval.");
        tracker.Restore(Owner with { Subject = "synthetic-b" }, 2);
        Require(tracker.Consent == GameplayRecordingConsent.Unknown && tracker.PlayTimeSeconds == 0, "New owner inherits neither consent nor totals.");
        tracker.Restore(Owner, 3, GameplayRecordingConsent.Allowed, 10);
        tracker.Observe(Owner, 3, Running, Epoch.AddHours(2));
        Require(tracker.PlayTimeSeconds == 10, "Restored persisted total has no stale interval.");
        tracker.Restore(null, 4);
        Require(tracker.PlayTimeSeconds == 0 && !tracker.IsRecording && tracker.Consent == GameplayRecordingConsent.Unknown, "Logout removes the active account projection.");
        return Task.CompletedTask;
    }

    internal static Task Sampling()
    {
        var tracker = Allowed();
        Sample(tracker, 0); Sample(tracker, 30);
        Require(tracker.PlayTimeSeconds == 30, "Thirty seconds remains a valid sample.");
        Sample(tracker, 61); Sample(tracker, 3661);
        Require(tracker.PlayTimeSeconds == 30, "Stalls and sleep are not gameplay.");
        Sample(tracker, 3666);
        Require(tracker.PlayTimeSeconds == 35, "Normal sampling resumes without backfill.");
        Sample(tracker, 3666); Sample(tracker, 3660);
        Require(tracker.PlayTimeSeconds == 35, "Duplicate or backward timestamps add nothing.");
        Sample(tracker, 3660.5);
        Require(tracker.PlayTimeSeconds == 36, "Half-second rounding preserves WPF behavior.");
        tracker.Observe(Owner, 1, Stopped, Epoch.AddSeconds(3665.5));
        Require(tracker.PlayTimeSeconds == 41 && !tracker.IsRecording, "Confirmed exit accounts for the final valid sample once.");
        tracker.Observe(Owner, 1, Stopped, Epoch.AddSeconds(3670.5));
        Require(tracker.PlayTimeSeconds == 41, "Idle polls never add time.");
        Sample(tracker, 4000);
        Require(tracker.PlayTimeSeconds == 41, "A new run starts a fresh interval.");
        return Task.CompletedTask;
    }

    internal static Task Uncertainty()
    {
        var tracker = Allowed();
        Sample(tracker, 0); Sample(tracker, 5);
        foreach (var unknown in new[] { new LocalGamePresenceSnapshot(1, "unknown"), new(1, "invented"), new(2, "running") })
        {
            tracker.Observe(Owner, 1, unknown, Epoch.AddSeconds(10));
            Require(!tracker.IsRecording && tracker.PlayTimeSeconds == 5, "Unknown/schema failure stops sampling, not totals.");
            Sample(tracker, 10);
        }
        tracker.Suspend();
        Sample(tracker, 20);
        Require(tracker.PlayTimeSeconds == 5, "Suspend never backfills a failed-save interval.");
        tracker.Observe(null, 1, Running, Epoch.AddSeconds(25));
        Require(!tracker.IsRecording && tracker.PlayTimeSeconds == 5, "No identity means no attribution.");
        try { tracker.Restore(Owner, 1, GameplayRecordingConsent.Allowed, -1); throw new Exception("Expected validation failure."); }
        catch (ArgumentException) { }
        Require(!tracker.IsRecording && tracker.Consent == GameplayRecordingConsent.Unknown, "Bad storage cannot retain active consent.");
        tracker.Restore(Owner, 1, GameplayRecordingConsent.Allowed, long.MaxValue);
        Sample(tracker, 0);
        try { Sample(tracker, 1); throw new Exception("Expected overflow failure."); }
        catch (OverflowException) { }
        Require(!tracker.IsRecording && tracker.PlayTimeSeconds == long.MaxValue, "Overflow cannot wrap or leave recording active.");
        return Task.CompletedTask;
    }

    private static GameplayTimeAccumulator Allowed()
    {
        var value = new GameplayTimeAccumulator();
        value.Restore(Owner, 1, GameplayRecordingConsent.Allowed);
        return value;
    }
    private static void Sample(GameplayTimeAccumulator value, double seconds) =>
        value.Observe(Owner, 1, Running, Epoch.AddSeconds(seconds));
    private static void Require(bool value, string message)
    { if (!value) throw new InvalidOperationException(message); }
}
