namespace StarBridge.HostRuntime.Presence;

// Shared WPF-compatible interval arithmetic. Callers own identity and consent;
// this counter never grants either and has no account / local profile storage.
internal sealed class GameplayTimeSampleCounter
{
    internal static readonly TimeSpan MaximumSampleGap = TimeSpan.FromSeconds(30);
    private DateTimeOffset? _last;
    internal long Seconds { get; private set; }
    internal bool IsRecording => _last is not null;
    internal void Restore(long seconds)
    {
        Suspend(); Seconds = 0;
        if (seconds < 0) throw new ArgumentException("Invalid gameplay total.");
        Seconds = seconds;
    }
    internal void Observe(bool running, DateTimeOffset now)
    {
        var previous = _last; Suspend();
        if (previous is not null)
        {
            var elapsed = now - previous.Value;
            if (elapsed > TimeSpan.Zero && elapsed <= MaximumSampleGap)
                Seconds = checked(Seconds + (long)Math.Round(elapsed.TotalSeconds, MidpointRounding.AwayFromZero));
        }
        if (running) _last = now;
    }
    // Raise the total (for example after a one-time history import) without
    // interrupting the interval currently being observed.
    internal void Rebase(long seconds)
    {
        if (seconds < Seconds) throw new ArgumentException("Gameplay total cannot decrease.");
        Seconds = seconds;
    }
    internal void Suspend() => _last = null;
}
