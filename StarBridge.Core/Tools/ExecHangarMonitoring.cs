namespace StarBridge.Core.Tools;

/// <summary>A finite device-local watch. A null watch preserves an existing continuous setup.</summary>
public sealed record ExecHangarMonitoring(Guid Id, DateTimeOffset StartedAt, DateTimeOffset EndsAt,
    bool OnlyNext, DateTimeOffset? Target = null, DateTimeOffset? MutedBoundary = null)
{
    public void Validate()
    {
        if (Id == Guid.Empty || EndsAt <= StartedAt || EndsAt - StartedAt > TimeSpan.FromDays(2) ||
            Target is {} target && (target < StartedAt || target > StartedAt.AddDays(2)) ||
            MutedBoundary is {} muted && (muted < StartedAt || muted > StartedAt.AddDays(2)))
            throw new ArgumentException("Invalid monitoring session.");
    }
    public bool Active(DateTimeOffset now) => now >= StartedAt && now <= EndsAt &&
        (!OnlyNext || Target is null || now <= Target.Value);
}

public sealed record ExecHangarPlan(bool Active, string State, ExecHangarNotice? Next,
    ExecHangarNotice? Outside, DateTimeOffset? EndsAt, bool OnlyNext, DateTimeOffset? Target = null,
    ExecHangarNotice? Waiting = null, DateTimeOffset? MutedBoundary = null, DateTimeOffset? StartedAt = null);

public static class ExecHangarMonitor
{
    public static string Receipt(ExecHangarNotice notice, ExecHangarMonitoring? watch) =>
        watch is null ? notice.Key : $"{watch.Id:N}:{notice.Key}";

    public static IReadOnlyList<ExecHangarNotice> Eligible(ExecHangarSchedule schedule, DateTimeOffset now,
        ExecHangarReminders rules, ExecHangarMonitoring? watch, DateTimeOffset? mutedBoundary = null)
    {
        var start = watch?.StartedAt is {} began && began > now.AddMinutes(-120) ? began : now.AddMinutes(-120);
        return schedule.Notices(start, now.AddDays(2), rules).Where(n => Includes(n, watch, mutedBoundary)).ToArray();
    }
    public static bool Includes(ExecHangarNotice notice, ExecHangarMonitoring? watch, DateTimeOffset? mutedBoundary = null) =>
        (watch is null || notice.Boundary >= watch.StartedAt && notice.Boundary <= watch.EndsAt &&
            (!watch.OnlyNext || watch.Target is null || notice.Boundary == watch.Target)) && notice.Boundary != (watch?.MutedBoundary ?? mutedBoundary);

    public static ExecHangarPlan Plan(ExecHangarSchedule schedule, DateTimeOffset now, ExecHangarReminders rules,
        ExecHangarMonitoring? watch, IReadOnlyCollection<string> receipts, DateTimeOffset? mutedBoundary = null)
    {
        var active = rules.Enabled && (watch?.Active(now) ?? true);
        var eligible = Eligible(schedule, now, rules, watch, mutedBoundary);
        var waiting = eligible.Where(n => n.Boundary > now).OrderBy(n => n.Boundary).FirstOrDefault();
        var next = eligible.Where(n => n.Due >= now &&
            !receipts.Contains(Receipt(n, watch))).OrderBy(n => n.Due).FirstOrDefault();
        var outside = schedule.Notices(now, now.AddDays(2), rules).Where(n => n.Boundary != (watch?.MutedBoundary ?? mutedBoundary) &&
            (watch is null || n.Boundary > watch.EndsAt))
            .OrderBy(n => n.Boundary).ThenBy(n => n.Due).FirstOrDefault();
        return new(active, !rules.Enabled ? "stopped" : watch?.OnlyNext == true && watch.Target is {} target && now > target ? "complete" :
            watch is not null && now > watch.EndsAt ? "expired" : !rules.HasRules ? "noRules" : next is not null ? "watching" : waiting is not null ? "waiting" :
                (watch?.MutedBoundary ?? mutedBoundary) is {} muted && muted > now ? "muted" : "noEvent",
            active ? next : null, next is null && waiting is null ? outside : null,
            watch is { OnlyNext: true, Target: {} until } && until < watch.EndsAt ? until : watch?.EndsAt, watch?.OnlyNext ?? false, watch?.Target,
            active ? waiting : null, watch?.MutedBoundary ?? mutedBoundary, watch?.StartedAt);
    }

    /// <summary>Starting or editing inside a lead interval yields one unclaimed current reminder, never a backlog.</summary>
    public static ExecHangarNotice? Immediate(ExecHangarSchedule schedule, DateTimeOffset now,
        ExecHangarReminders rules, ExecHangarMonitoring watch) => Immediate(schedule, now, rules, watch, []);

    public static ExecHangarNotice? Immediate(ExecHangarSchedule schedule, DateTimeOffset now,
        ExecHangarReminders rules, ExecHangarMonitoring? watch, IReadOnlyCollection<string> receipts,
        DateTimeOffset? mutedBoundary = null) => Eligible(schedule, now, rules, watch, mutedBoundary)
        .Where(n => n.Due <= now && n.Boundary > now && n.Kind is not ("open" or "close") &&
            !receipts.Contains(Receipt(n, watch)))
        .OrderBy(n => n.Boundary).ThenByDescending(n => n.Due).Select(n => n with { Due = now }).FirstOrDefault();
}
