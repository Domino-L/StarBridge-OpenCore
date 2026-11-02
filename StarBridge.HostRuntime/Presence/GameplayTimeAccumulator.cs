using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Presence;

public enum GameplayRecordingConsent { Unknown, Allowed, Declined }

/// <summary>
/// Account-scoped WPF-compatible sampling policy, without IO, timers or publication.
/// The owner must restore a verified local snapshot and persist an allow decision
/// before applying it here. Suspend on account/IO uncertainty; never bridge that gap.
/// </summary>
public sealed class GameplayTimeAccumulator
{
    public static readonly TimeSpan MaximumSampleGap = GameplayTimeSampleCounter.MaximumSampleGap;
    private BridgeAccountContext? _owner;
    private long _generation;
    private readonly GameplayTimeSampleCounter _counter = new();

    public GameplayRecordingConsent Consent { get; private set; }
    public long PlayTimeSeconds => _counter.Seconds;
    public bool IsRecording => _counter.IsRecording;

    /// <summary>Replaces the active owner only; no old files or totals are promoted.</summary>
    public void Restore(BridgeAccountContext? owner, long generation,
        GameplayRecordingConsent consent = GameplayRecordingConsent.Unknown, long recordedSeconds = 0)
    {
        // A failed restore must also stop the previous sample interval.
        Suspend();
        _owner = null;
        Consent = GameplayRecordingConsent.Unknown;
        _counter.Restore(0);
        if (generation < 0 || recordedSeconds < 0 || !Enum.IsDefined(consent) ||
            owner is not null && !owner.IsComplete)
            throw new ArgumentException("Invalid gameplay statistics snapshot.");
        _generation = generation;
        if (owner is null) return;
        _owner = owner;
        Consent = consent;
        _counter.Restore(recordedSeconds);
    }

    public void ApplyConsent(GameplayRecordingConsent consent)
    {
        Suspend();
        if (_owner is null || !Enum.IsDefined(consent))
        {
            Consent = GameplayRecordingConsent.Unknown;
            throw new InvalidOperationException("A current owner and valid consent are required.");
        }
        Consent = consent;
    }

    /// <summary>Consumes local process observations, not login or page-open time.</summary>
    public void Observe(BridgeAccountContext? owner, long generation,
        LocalGamePresenceSnapshot presence, DateTimeOffset now)
    {
        if (_owner is null || owner != _owner || generation != _generation ||
            Consent != GameplayRecordingConsent.Allowed || presence.SchemaVersion != 1 ||
            presence.State is not ("running" or "notRunning"))
        {
            Suspend();
            return;
        }

        _counter.Observe(presence.State == "running", now);
    }

    /// <summary>Stops immediately, retaining totals but no interval to resume later.</summary>
    public void Suspend() => _counter.Suspend();
}
