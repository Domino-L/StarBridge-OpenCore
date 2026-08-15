using System.Globalization;

namespace StarBridge.Desktop;

public sealed record FleetActivityHeaderWindow(
    string[] DayIds,
    string DaysText,
    string StartTime,
    string EndTime,
    bool EndsNextDay = false);

public sealed record FleetActivityHeaderSummary(
    string CompactText,
    string FullText);

public static class FleetActivityHeaderPresentation
{
    public static FleetActivityHeaderSummary Resolve(
        IReadOnlyList<FleetActivityHeaderWindow> windows,
        DateTimeOffset fleetNow,
        bool useChinese)
    {
        if (windows.Count == 0)
        {
            return new FleetActivityHeaderSummary(
                useChinese ? "未设置" : "Not configured",
                useChinese ? "尚未设置组织活动时间。" : "Organization activity hours are not configured.");
        }

        var fullText = string.Join(
            Environment.NewLine,
            windows.Select(window =>
                $"{window.DaysText} {FormatRange(window, useChinese)}"));
        var occurrences = windows
            .SelectMany(window => BuildOccurrences(window, fleetNow))
            .Where(occurrence => occurrence.End >= fleetNow)
            .OrderBy(occurrence => occurrence.Start <= fleetNow ? fleetNow : occurrence.Start)
            .ThenBy(occurrence => occurrence.Start)
            .ToArray();
        if (occurrences.Length == 0)
        {
            return new FleetActivityHeaderSummary(
                $"{windows[0].DaysText} {FormatRange(windows[0], useChinese)}{FormatAdditionalCount(windows.Count - 1, useChinese)}",
                fullText);
        }

        var next = occurrences[0];
        string prefix;
        string range;
        if (next.Start <= fleetNow && next.End >= fleetNow)
        {
            prefix = useChinese ? "进行中 ·" : "Active ·";
            var nextDay = next.End.Date > fleetNow.Date;
            range = useChinese
                ? $"至 {(nextDay ? "次日 " : "")}{next.End:HH:mm}"
                : $"until {(nextDay ? "next day " : "")}{next.End:HH:mm}";
        }
        else
        {
            var dayOffset = (next.Start.Date - fleetNow.Date).Days;
            prefix = dayOffset switch
            {
                0 => useChinese ? "今天" : "Today",
                1 => useChinese ? "明天" : "Tomorrow",
                _ => FormatDay(next.Start.DayOfWeek, useChinese)
            };
            range = FormatRange(next.Window, useChinese);
        }

        return new FleetActivityHeaderSummary(
            $"{prefix} {range}{FormatAdditionalCount(windows.Count - 1, useChinese)}",
            fullText);
    }

    private static IEnumerable<FleetActivityOccurrence> BuildOccurrences(
        FleetActivityHeaderWindow window,
        DateTimeOffset fleetNow)
    {
        if (!TryParseClock(window.StartTime, out var startClock) ||
            !TryParseClock(window.EndTime, out var endClock))
        {
            yield break;
        }

        var dayIds = (window.DayIds is { Length: > 0 } ? window.DayIds : AllDayIds)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        for (var offset = -1; offset <= 7; offset++)
        {
            var date = fleetNow.Date.AddDays(offset);
            if (!dayIds.Contains(GetDayId(date.DayOfWeek)))
            {
                continue;
            }

            var start = new DateTimeOffset(date.Add(startClock), fleetNow.Offset);
            var end = new DateTimeOffset(date.Add(endClock), fleetNow.Offset);
            if (window.EndsNextDay || end <= start)
            {
                end = end.AddDays(1);
            }

            yield return new FleetActivityOccurrence(window, start, end);
        }
    }

    private static bool TryParseClock(string? value, out TimeSpan time) =>
        TimeSpan.TryParseExact(
            (value ?? "").Trim(),
            "hh\\:mm",
            CultureInfo.InvariantCulture,
            out time);

    private static string FormatRange(FleetActivityHeaderWindow window, bool useChinese) =>
        window.EndsNextDay
            ? useChinese
                ? $"{window.StartTime}–次日 {window.EndTime}"
                : $"{window.StartTime}–next day {window.EndTime}"
            : $"{window.StartTime}–{window.EndTime}";

    private static string FormatAdditionalCount(int count, bool useChinese) => count <= 0
        ? ""
        : useChinese ? $" · 另 {count} 段" : $" · +{count}";

    private static string FormatDay(DayOfWeek day, bool useChinese) => useChinese
        ? day switch
        {
            DayOfWeek.Monday => "周一",
            DayOfWeek.Tuesday => "周二",
            DayOfWeek.Wednesday => "周三",
            DayOfWeek.Thursday => "周四",
            DayOfWeek.Friday => "周五",
            DayOfWeek.Saturday => "周六",
            DayOfWeek.Sunday => "周日",
            _ => "最近"
        }
        : day.ToString();

    private static string GetDayId(DayOfWeek day) => day switch
    {
        DayOfWeek.Monday => "mon",
        DayOfWeek.Tuesday => "tue",
        DayOfWeek.Wednesday => "wed",
        DayOfWeek.Thursday => "thu",
        DayOfWeek.Friday => "fri",
        DayOfWeek.Saturday => "sat",
        DayOfWeek.Sunday => "sun",
        _ => "mon"
    };

    private static readonly string[] AllDayIds = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

    private sealed record FleetActivityOccurrence(
        FleetActivityHeaderWindow Window,
        DateTimeOffset Start,
        DateTimeOffset End);
}
