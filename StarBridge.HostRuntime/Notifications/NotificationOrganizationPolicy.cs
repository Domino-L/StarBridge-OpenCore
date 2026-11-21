using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Notifications;

// Evaluate wall time at delivery, including after resume. No timer needs to run
// while Windows sleeps. The half-open interval includes start, excludes end.
internal static class NotificationOrganizationPolicy
{
    internal static TimeZoneInfo LocalZone(TimeProvider time)
    {
        // Windows can change zones while this Host remains alive. Refresh only
        // the in-process .NET cache; never change the OS zone or its settings.
        if (ReferenceEquals(time, TimeProvider.System)) TimeZoneInfo.ClearCachedData();
        return time.LocalTimeZone;
    }
    internal static bool Quiet(NotificationQuietHours? q, DateTimeOffset utc, TimeZoneInfo zone)
    {
        if (q is not { Enabled: true }) return false;
        var local = TimeZoneInfo.ConvertTime(utc, zone);
        var minute = local.Hour * 60 + local.Minute;
        return q.StartMinute < q.EndMinute ? minute >= q.StartMinute && minute < q.EndMinute :
            minute >= q.StartMinute || minute < q.EndMinute;
    }
    internal static bool Allows(NotificationPolicyRule rule, NotificationEventKind kind, DateTimeOffset utc, TimeZoneInfo zone) =>
        NotificationSourcePolicy.Allows(rule.Mode, kind) &&
        (kind != NotificationEventKind.OrganizationChat || rule.TypeRules?.FirstOrDefault(t => t.Type == "chat")?.Mode != "disabled") &&
        (kind != NotificationEventKind.OrganizationAnnouncement ||
            (rule.TypeRules?.FirstOrDefault(t => t.Type == "announcement")?.Mode ?? "inherit") is "inherit" or "enabled") &&
        !Quiet(rule.QuietHours, utc, zone);
    internal static bool AllowsEvent(NotificationPolicyRule rule, NotificationEventKind kind, DateTimeOffset? occurredAt,
        DateTimeOffset now, TimeZoneInfo zone) => Allows(rule, kind, now, zone) &&
        (rule.QuietHours is not { Enabled: true } || !CrossedQuiet(rule.QuietHours, occurredAt ?? now, now, zone));

    // A delayed output that crosses even an entire quiet interval is retired;
    // ending quiet hours never brings an old card or sound back to life.
    internal static bool CrossedQuiet(NotificationQuietHours? q, DateTimeOffset start, DateTimeOffset end, TimeZoneInfo zone)
    {
        if (end < start) return true;
        if (q is not { Enabled: true }) return false;
        if (end - start >= TimeSpan.FromDays(1)) return true;
        // At most 1441 minute boundaries, including DST gaps/repeated hours.
        // UTC stepping visits both repeated intervals and skips missing ones.
        if (Quiet(q, start, zone) || Quiet(q, end, zone)) return true;
        var cursor = new DateTimeOffset(start.UtcDateTime.AddTicks(-(start.Ticks % TimeSpan.TicksPerMinute)), TimeSpan.Zero).AddMinutes(1);
        for (; cursor < end; cursor = cursor.AddMinutes(1)) if (Quiet(q, cursor, zone)) return true;
        return false;
    }
    /// <summary>
    /// 0.7.3 reminder-card defaults (user): chat raises no card unless the user turned chat on for that
    /// source; an unconfigured announcement row follows the source mode for both cards and sound.
    /// A choice the user saved is kept either way. Allows also owns this default without CardRule.
    /// </summary>
    internal static NotificationPolicyRule? CardRule(NotificationPolicyRule rule, NotificationEventKind kind)
    {
        var types = rule.TypeRules ?? [];
        if (kind == NotificationEventKind.OrganizationChat)
            return types.FirstOrDefault(t => t.Type == "chat")?.Mode is "inherit" or "enabled" ? rule : null;
        if (kind == NotificationEventKind.OrganizationAnnouncement && !types.Any(t => t.Type == "announcement"))
            return rule with { TypeRules = [.. types, new NotificationTypeRule("announcement", "inherit")] };
        return rule;
    }

    internal static bool AllowsCard(NotificationPolicyRule rule, NotificationEventKind kind, DateTimeOffset? occurredAt,
        DateTimeOffset now, TimeZoneInfo zone) => CardRule(rule, kind) is { } card && AllowsEvent(card, kind, occurredAt, now, zone);

    internal static bool Current(NotificationPolicyStore store, BridgeAccountContext owner, string source, NotificationEventKind kind,
        long revision, DateTimeOffset admittedAt, TimeZoneInfo zone, TimeProvider time, bool card = false)
    {
        try {
            var nowZone = LocalZone(time);
            if (!zone.Equals(nowZone) || !zone.HasSameRules(nowZone)) return false;
            var saved = store.Read(owner); var rule = saved.Rule(source);
            if (card && CardRule(rule, kind) is not { } cardRule) return false;
            else if (card) rule = CardRule(rule, kind)!;
            var now = time.GetUtcNow();
            return saved.SuppressionRevision(source) == revision && Allows(rule, kind, now, nowZone) &&
                !CrossedQuiet(rule.QuietHours, admittedAt, now, nowZone);
        } catch (Exception e) when (e is IOException or InvalidDataException or UnauthorizedAccessException or System.Text.Json.JsonException) { return false; }
    }
}
