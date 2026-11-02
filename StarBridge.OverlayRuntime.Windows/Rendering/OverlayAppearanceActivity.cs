namespace StarBridge.Desktop;

// Presentation activity metadata only: no event text, source, account or payload.
internal readonly record struct OverlayAppearanceActivity(long Sequence, DateTimeOffset OccurredAt)
{
    private static long _next;
    internal static OverlayAppearanceActivity Create(DateTimeOffset occurredAt) =>
        new(Interlocked.Increment(ref _next), occurredAt);
}

internal readonly record struct OverlayAppearanceSignal(long Sequence, long OccurredAtMs);

// Tracks presentation revisions only; an owner replacement invalidates even if
// its first visual version equals the previous owner's final version.
internal sealed class OverlayAppearanceFrameInvalidator
{
    private (long Owner, long Version)? _last;
    private bool _motionWasActive;
    internal bool Observe(long owner, long visualVersion)
    {
        var next = (owner, visualVersion);
        var changed = _last != next;
        _last = next;
        return changed;
    }

    // Paint once at the end as well: a stopped timer must not leave the last
    // fractional enter/exit position visible until the pet changes its cel.
    internal bool ObserveContinuousMotion(bool active)
    {
        var mustPaint = active || _motionWasActive;
        _motionWasActive = active;
        return mustPaint;
    }
}

// Optional appearance consumers share the same bounded history/lifecycle policy.
// A cursor consumes ineligible/stale observations immediately; it never queues them.
internal static class OverlayAppearanceSamplingDeadline
{
    // Zero preserves the requested native frame cadence. Optional held-cel
    // consumers may sleep to a nearer bounded deadline; never slow native motion.
    internal static long IntervalTicks(int framesPerSecond, int sampleDelayMs, long frequency)
    {
        var normalizedFrequency = Math.Max(1, frequency);
        var delay = Math.Clamp(sampleDelayMs, 0, 200);
        return delay == 0
            ? Math.Max(1, normalizedFrequency / Math.Clamp(framesPerSecond, 1, 240))
            : Math.Max(1, (long)Math.Ceiling(normalizedFrequency * (delay / 1000d)));
    }
}

internal sealed class OverlayAppearanceActivityCursor
{
    private long _highWater, _epoch = long.MinValue, _clock;
    private DateTimeOffset _notBefore;
    private bool _baseline = true;
    internal void Rebase() => _baseline = true;
    internal IReadOnlyList<OverlayAppearanceSignal> Observe(
        IEnumerable<OverlayAppearanceActivity> activities, long epoch, bool eligible,
        DateTimeOffset observedAt, long nowMs)
    {
        _clock = Math.Max(_clock, nowMs);
        // Epochs are renderer-owner revisions, never raw scene/account identifiers.
        if(epoch < _epoch) return [];
        if(epoch != _epoch) { _epoch = epoch; _baseline = true; }
        if(_baseline) _notBefore = observedAt;
        List<OverlayAppearanceSignal> admitted = [];
        foreach(var activity in activities.Where(a => a.Sequence > 0).DistinctBy(a => a.Sequence).OrderBy(a => a.Sequence))
        {
            if(activity.Sequence <= _highWater) continue;
            _highWater = activity.Sequence;
            var age = (observedAt - activity.OccurredAt).TotalMilliseconds;
            if(_baseline || !eligible || activity.OccurredAt < _notBefore || age < 0 || age > 5000) continue;
            admitted.Add(new(activity.Sequence, _clock - (long)age));
        }
        _baseline = false;
        return admitted;
    }
}
