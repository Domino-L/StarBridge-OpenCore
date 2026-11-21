namespace StarBridge.HostRuntime.Achievements;

// Exact names from scm_holiday_art.dart; no numeric-id guesses or remote image loads.
// The display name follows scm_achievement_wire.dart: SCM's `title` (成就标题,
// e.g. 中登) with stray symbols trimmed, else `name` (成就名称, e.g. 资深玩家).
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
    // Daily and limited-event titles from scm_holiday_art.dart (approved art
    // delivery 分类对照.tsv). The card uses 512 rasters of the same flat SVGs.
    private static readonly IReadOnlyDictionary<string, string> Daily = new Dictionary<string, string>(StringComparer.Ordinal) {
        ["萌新启航"] = "account-rookie", ["中登"] = "account-regular", ["纵横星海"] = "account-veteran",
        ["攻略新手"] = "guide-beginner", ["攻略达人"] = "guide-adept", ["攻略大师"] = "guide-master",
        ["初涉商海"] = "trade-beginner", ["商业精英"] = "trade-adept", ["商业大亨"] = "trade-master",
        ["猎头帮"] = "bounty-beginner", ["猎头帮首脑"] = "bounty-leader",
    };
    private static readonly IReadOnlyDictionary<string, string> LimitedEvents = new Dictionary<string, string>(StringComparer.Ordinal) {
        ["春节精英"] = "spring-elite", ["签到达人"] = "checkin-streak", ["春节欢庆"] = "spring-participant",
    };
    // The card standing for further unlocks beyond the single-card cap (build 105).
    internal const string SummaryId = "scm-summary";
    internal static bool ValidId(string? id) => id is { Length: > 4 and <= 24 } && id.StartsWith("scm-", StringComparison.Ordinal) &&
        long.TryParse(id.AsSpan(4), System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var number) &&
        number > 0 && id == $"scm-{number}";
    // Same cleanup as scmDisplayTitle: whitespace, symbols (So/Sk, emoji as
    // whole code points), U+FE0F and × * · • - – — _ ~ | at either end only.
    internal static string? DisplayTitle(string? raw)
    {
        if (raw is null) return null;
        var runes = raw.EnumerateRunes().ToList();
        static bool Mark(System.Text.Rune rune) => System.Text.Rune.IsWhiteSpace(rune) ||
            System.Text.Rune.GetUnicodeCategory(rune) is System.Globalization.UnicodeCategory.OtherSymbol or System.Globalization.UnicodeCategory.ModifierSymbol ||
            rune.Value is 0xFE0F or '×' or '*' or '·' or '•' or '-' or '–' or '—' or '_' or '~' or '|';
        var start = 0; var end = runes.Count;
        while (start < end && Mark(runes[start])) start++;
        while (end > start && Mark(runes[end - 1])) end--;
        return start == end ? null : string.Concat(runes.Skip(start).Take(end - start).Select(r => r.ToString()));
    }
    internal static string DisplayName(ScmAchievementItem item) =>
        (DisplayTitle(item.Title) ?? item.Name).Replace('\n', ' ').Replace('\t', ' ');
    // Art matches the display name exactly, never a substring, as
    // scm_holiday_art.dart does. Holiday and limited-event rows ignore a trailing
    // ! or ！ (SCM writes 春节欢庆！); a holiday row with a limited-event title
    // (SCM lists 春节欢庆 under holidays) reuses that limited-event art.
    internal static string? Artwork(ScmAchievementItem item)
    {
        var title = (DisplayTitle(item.Title) ?? item.Name).Trim();
        var festive = item.Type is "HOLIDAY" or "EVENT_LIMITED";
        if (festive) title = System.Text.RegularExpressions.Regex.Replace(title, "[!！]+$", "");
        return item.Type switch
        {
            "HOLIDAY" when Holidays.TryGetValue(title, out var slug) => $"Assets/Achievements/scm-holiday-{slug}-512.webp",
            "HOLIDAY" or "EVENT_LIMITED" when LimitedEvents.TryGetValue(title, out var slug) => $"Assets/Achievements/scm-event-{slug}-512.webp",
            "NORMAL" or "SPECIAL" when Daily.TryGetValue(title, out var slug) => $"Assets/Achievements/scm-daily-{slug}-512.webp",
            _ => null,
        };
    }
}
