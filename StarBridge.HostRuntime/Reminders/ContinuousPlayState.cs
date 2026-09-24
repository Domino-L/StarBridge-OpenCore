namespace StarBridge.HostRuntime.Reminders;

public sealed record ContinuousPlaySettings(bool Enabled = true, int FirstReminderMinutes = 120,
    int RepeatReminderMinutes = 120, int Revision = 0)
{
    [System.Text.Json.Serialization.JsonIgnore]
    public bool Valid => Revision >= 0 && FirstReminderMinutes is 60 or 90 or 120 or 180 && RepeatReminderMinutes is 60 or 120;
}
public sealed record PlayProcessObservation(string State, DateTimeOffset? StartedAt = null);
public sealed record ContinuousPlayNotice(TimeSpan Duration, Func<bool> IsCurrent);
public interface IContinuousPlayReminderSink
{
    // Accepted by existing LocalPlayReminder queue; NOT a rendered-frame acknowledgement.
    ValueTask<bool> TryQueueAsync(ContinuousPlayNotice notice, CancellationToken cancellation);
}
internal sealed record ContinuousPlayState(int SchemaVersion = 1,
    DateTimeOffset? SessionStartedAtUtc = null, DateTimeOffset? LastObservedRunningAtUtc = null,
    DateTimeOffset? MissingSinceUtc = null, DateTimeOffset? ProcessStartedAtUtc = null,
    DateTimeOffset? NextReminderAtUtc = null, DateTimeOffset? LastReminderAtUtc = null,
    DateTimeOffset? RetryNotBeforeUtc = null)
{
    internal bool Valid => SchemaVersion == 1 && (SessionStartedAtUtc is null
        ? LastObservedRunningAtUtc is null && NextReminderAtUtc is null && LastReminderAtUtc is null
        : LastObservedRunningAtUtc >= SessionStartedAtUtc && NextReminderAtUtc >= SessionStartedAtUtc);
    internal ContinuousPlayState Configure(ContinuousPlaySettings settings) => SessionStartedAtUtc is null ? this : this with
    {
        NextReminderAtUtc = LastReminderAtUtc is { } last ? last.AddMinutes(settings.RepeatReminderMinutes)
            : SessionStartedAtUtc.Value.AddMinutes(settings.FirstReminderMinutes)
    };
    internal ContinuousPlayState Observe(PlayProcessObservation process, DateTimeOffset now, ContinuousPlaySettings settings)
    {
        if (process.State == "unknown") return this;
        if (process.State != "running")
        {
            if (SessionStartedAtUtc is null) return this;
            if (MissingSinceUtc is null) return this with { MissingSinceUtc = now };
            return now - MissingSinceUtc >= TimeSpan.FromMinutes(15) ? new() : this;
        }
        var started = process.StartedAt <= now ? process.StartedAt : null;
        var changed = started is { } current && ProcessStartedAtUtc is { } previous && Math.Abs((current - previous).TotalSeconds) > 2;
        var longGap = MissingSinceUtc is { } missing && now - missing >= TimeSpan.FromMinutes(15);
        var lateReplacement = changed && LastObservedRunningAtUtc is { } last && started!.Value - last >= TimeSpan.FromMinutes(15);
        if (SessionStartedAtUtc is null || longGap || lateReplacement || LastObservedRunningAtUtc > now)
        {
            var origin = started ?? now;
            return new(SessionStartedAtUtc: origin, LastObservedRunningAtUtc: now,
                ProcessStartedAtUtc: started, NextReminderAtUtc: origin.AddMinutes(settings.FirstReminderMinutes));
        }
        return this with { LastObservedRunningAtUtc = now, MissingSinceUtc = null, ProcessStartedAtUtc = started ?? ProcessStartedAtUtc };
    }
}
