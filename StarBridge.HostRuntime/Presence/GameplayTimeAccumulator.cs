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
    public static readonly TimeSpan MaximumSampleGap = TimeSpan.FromSeconds(30);
    private BridgeAccountContext? _owner;
    private long _generation;
    private DateTimeOffset? _lastSample;

    public GameplayRecordingConsent Consent { get; private set; }
    public long PlayTimeSeconds { get; private set; }
    public bool IsRecording => _lastSample is not null;

    /// <summary>Replaces the active owner only; no old files or totals are promoted.</summary>
    public void Restore(BridgeAccountContext? owner, long generation,
        GameplayRecordingConsent consent = GameplayRecordingConsent.Unknown, long recordedSeconds = 0)
    {
        // A failed restore must also stop the previous sample interval.
        Suspend();
        _owner = null;
        Consent = GameplayRecordingConsent.Unknown;
        PlayTimeSeconds = 0;
        if (generation < 0 || recordedSeconds < 0 || !Enum.IsDefined(consent) ||
            owner is not null && !owner.IsComplete)
            throw new ArgumentException("Invalid gameplay statistics snapshot.");
        _generation = generation;
        if (owner is null) return;
        _owner = owner;
        Consent = consent;
        PlayTimeSeconds = recordedSeconds;
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

        var previous = _lastSample;
        Suspend();
        if (previous is not null)
        {
            var elapsed = now - previous.Value;
            if (elapsed > TimeSpan.Zero && elapsed <= MaximumSampleGap)
            {
                // Preserve WPF rounding, including the final confirmed-exit sample.
                var seconds = (long)Math.Round(elapsed.TotalSeconds, MidpointRounding.AwayFromZero);
                PlayTimeSeconds = checked(PlayTimeSeconds + seconds);
            }
        }
        if (presence.State == "running") _lastSample = now;
    }

    /// <summary>Stops immediately, retaining totals but no interval to resume later.</summary>
    public void Suspend() => _lastSample = null;
}
