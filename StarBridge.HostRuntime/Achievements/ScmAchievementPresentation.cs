namespace StarBridge.HostRuntime.Achievements;

// Exact names from scm_holiday_art.dart; no numeric-id guesses or remote image loads.
internal static class ScmAchievementPresentation
{
    private static readonly IReadOnlyDictionary<string, string> Holidays = new Dictionary<string, string>(StringComparer.Ordinal) {
        ["新春快乐"] = "spring-festival", ["辞旧迎新"] = "new-years-eve", ["花灯初上"] = "lantern-festival",
        ["粽情端午"] = "dragon-boat", ["鹊桥相会"] = "qixi", ["月圆人团圆"] = "mid-autumn", ["腊八寒冬"] = "laba",
        ["新年新气象"] = "new-year", ["星际有情人"] = "valentine", ["星际整蛊师"] = "april-fools", ["星际劳模"] = "labor-day",
        ["童心未泯"] = "childrens-day", ["星际鬼才"] = "halloween", ["星际圣诞"] = "christmas",
        ["登高望远"] = "double-ninth",
        ["国庆节"] = "national-day",
    };
    internal static bool ValidId(string? id) => id is { Length: > 4 and <= 24 } && id.StartsWith("scm-", StringComparison.Ordinal) &&
        long.TryParse(id.AsSpan(4), System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var number) &&
        number > 0 && id == $"scm-{number}";
    internal static string? Artwork(ScmAchievementItem item) => item.Type == "HOLIDAY" && Holidays.TryGetValue(item.Name.Trim(), out var slug)
        ? $"Assets/Achievements/scm-holiday-{slug}-512.webp" : null;
}
