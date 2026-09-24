using System.Globalization;
using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Profiles;

public sealed record LocalProfilePlayStyle(
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<string>? Roles = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<string>? Interests = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<string>? Support = null)
{
    public LocalProfilePlayStyle Copy() => new(Roles?.ToArray(), Interests?.ToArray(), Support?.ToArray());
}
public sealed record LocalProfileTimeWindow(IReadOnlyList<int> Days, string StartTime, string EndTime);
public sealed record LocalProfileSchedule(string TimeZoneId, string Rhythm, IReadOnlyList<LocalProfileTimeWindow> Windows)
{
    public LocalProfileSchedule Copy() => this with
    { Windows = Windows.Select(w => w with { Days = w.Days.ToArray() }).ToArray() };
}

/// <summary>WPF collaboration limits, with strict validation rather than silent truncation.</summary>
internal static class LocalProfileCollaborationPolicy
{
    private static readonly HashSet<string> Roles = new(StringComparer.Ordinal)
    {
        "fleet-command", "squad-command", "action-coordination", "navigator",
        "pilot", "copilot", "gunner", "ship-engineer", "remote-weapon-operator",
        "fighter-pilot", "interceptor-pilot", "bomber-pilot", "carrier-pilot",
        "assault-trooper", "sniper", "heavy-gunner", "boarding-specialist", "vehicle-driver",
        "scout", "route-planner", "scanner-operator", "intel-observer",
        "mining-operator", "salvage-operator", "cargo-specialist", "trader", "resource-processor",
        "medic", "search-and-rescue", "casualty-transport", "field-medic",
        "supply-specialist", "maintenance-engineer", "ship-dispatcher", "transport-driver"
    };
    private static readonly HashSet<string> Interests = new(StringComparer.Ordinal)
    { "fleet-operations", "squad-missions", "pve", "pvp", "bounty", "ground", "trading", "mining", "salvage", "exploration", "racing", "social" };
    private static readonly HashSet<string> Support = new(StringComparer.Ordinal)
    { "command", "pilot", "gunner", "medical", "supply", "engineering", "navigation", "transport", "teaching", "ship-sharing" };

    public static void Validate(LocalProfilePlayStyle? style, LocalProfileSchedule? schedule)
    {
        Selection(style?.Roles, Roles, 5);
        Selection(style?.Interests, Interests, 3);
        Selection(style?.Support, Support, 3);
        if (schedule is null) return;
        if (schedule.Rhythm is not ("casual" or "regular" or "intensive" or "weekends" or "irregular") ||
            schedule.Windows is null || schedule.Windows.Count > 3 ||
            schedule.TimeZoneId is null || schedule.TimeZoneId.Length > 128 ||
            schedule.TimeZoneId.Any(char.IsControl) ||
            (schedule.Windows.Count > 0 && string.IsNullOrWhiteSpace(schedule.TimeZoneId)))
            Invalid();
        if (!string.IsNullOrEmpty(schedule.TimeZoneId))
        {
            try { _ = TimeZoneInfo.FindSystemTimeZoneById(schedule.TimeZoneId); }
            catch (Exception e) when (e is TimeZoneNotFoundException or InvalidTimeZoneException or ArgumentException)
            { Invalid(); }
        }
        foreach (var window in schedule.Windows!)
        {
            if (window is null || window.Days is null || window.Days.Count is < 1 or > 7 ||
                window.Days.Any(d => d is < 0 or > 6) || window.Days.Distinct().Count() != window.Days.Count ||
                !Time(window.StartTime) || !Time(window.EndTime)) Invalid();
        }
    }
    // End <= start means next day, including equal times (a full day), matching WPF.
    private static bool Time(string? value) => value is { Length: 5 } &&
        TimeOnly.TryParseExact(value, "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out _);
    private static void Selection(IReadOnlyList<string>? values, HashSet<string> known, int maximum)
    {
        if (values is not null && (values.Count > maximum || values.Distinct().Count() != values.Count ||
            values.Any(v => v is null || !known.Contains(v)))) Invalid();
    }
    private static void Invalid() => throw new LocalProfileException("profile_local.invalid_request");
}
