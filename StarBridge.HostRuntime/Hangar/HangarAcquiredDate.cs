using System.Globalization;
using System.Text.RegularExpressions;

namespace StarBridge.HostRuntime.Hangar;

/// <summary>
/// Turns the pledge date text read from the RSI hangar page ("Sep 01, 2026", "2026年9月1日") into a calendar
/// date. User 11-12: the personal hangar shows "入库时间" from the official hangar, never the time the client
/// imported the ship. Date only, read as written (no time-zone shift, no machine culture); anything that
/// does not read cleanly is unknown (null) rather than guessed.
/// </summary>
internal static partial class HangarAcquiredDate
{
    private static readonly DateOnly Earliest = new(2011, 1, 1);

    private static readonly string[] EnglishFormats =
    [
        "MMM d, yyyy", "MMM dd, yyyy", "MMMM d, yyyy", "MMMM dd, yyyy",
        "MMM. d, yyyy", "MMM. dd, yyyy", "d MMM yyyy", "dd MMM yyyy", "d MMMM yyyy", "dd MMMM yyyy",
        "yyyy-MM-dd", "yyyy/MM/dd", "yyyy/M/d", "yyyy-M-d"
    ];

    public static DateOnly? Parse(string? text, DateTimeOffset? now = null)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var value = LabelRegex().Replace(text.Replace(' ', ' '), "").Trim();
        if (value.Length == 0 || value.Length > 64) return null;
        value = SpaceRegex().Replace(value, " ");

        DateOnly? date = null;
        var chinese = ChineseRegex().Match(value);
        if (chinese.Success)
        {
            if (int.TryParse(chinese.Groups["y"].Value, NumberStyles.None, CultureInfo.InvariantCulture, out var y) &&
                int.TryParse(chinese.Groups["m"].Value, NumberStyles.None, CultureInfo.InvariantCulture, out var m) &&
                int.TryParse(chinese.Groups["d"].Value, NumberStyles.None, CultureInfo.InvariantCulture, out var d) &&
                y >= 1 && m is >= 1 and <= 12 && d >= 1 && d <= DateTime.DaysInMonth(y, m))
                date = new DateOnly(y, m, d);
        }
        else if (DateTime.TryParseExact(value, EnglishFormats, CultureInfo.InvariantCulture,
                     DateTimeStyles.AllowWhiteSpaces, out var exact))
            date = DateOnly.FromDateTime(exact);

        var latest = DateOnly.FromDateTime((now ?? DateTimeOffset.UtcNow).UtcDateTime.AddDays(1));
        return date is { } found && found >= Earliest && found <= latest ? found : null;
    }

    /// <summary>"yyyy-MM-dd" or null, as sent to the client.</summary>
    public static string? Format(string? text, DateTimeOffset? now = null) =>
        Parse(text, now)?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    // Also drops a colon left behind by readers that only stripped the label (full-width "：" before 11-13).
    [GeneratedRegex(@"^\s*(?:(?:Created|Acquired|创建|建立|入库|获得|获取)\s*)?[:：]?\s*", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex LabelRegex();

    [GeneratedRegex(@"\s+", RegexOptions.CultureInvariant)]
    private static partial Regex SpaceRegex();

    [GeneratedRegex(@"^(?<y>\d{4})\s*年\s*(?<m>\d{1,2})\s*月\s*(?<d>\d{1,2})\s*日?$", RegexOptions.CultureInvariant)]
    private static partial Regex ChineseRegex();
}
