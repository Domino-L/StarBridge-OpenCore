namespace StarBridge.HostRuntime.Notifications;

using System.Globalization;

public sealed record ContinuousPlayNotificationContent(TimeSpan Duration)
{
    // Nearest half hour; exact quarter-hour ties round upward (105 minutes -> 2 hours).
    public double Hours => Math.Round(Math.Max(0, Duration.TotalHours) * 2, MidpointRounding.AwayFromZero) / 2;
    public string Number => Hours.ToString("0.#", CultureInfo.InvariantCulture);
    public string Unit(string locale) => !locale.StartsWith("zh", StringComparison.OrdinalIgnoreCase)
        ? Hours == 1 ? "hour" : "hours" : Traditional(locale) ? "小時" : "小时";
    public string Label(string locale) => !locale.StartsWith("zh", StringComparison.OrdinalIgnoreCase)
        ? "Continuous play" : Traditional(locale) ? "連續遊玩" : "连续游玩";
    public string Now(string locale, DateTimeOffset instant) =>
        (!locale.StartsWith("zh", StringComparison.OrdinalIgnoreCase) ? "Now " : Traditional(locale) ? "現在 " : "现在 ") +
        instant.ToLocalTime().ToString("HH:mm", CultureInfo.InvariantCulture);
    private static bool Traditional(string locale) => locale is "zh-TW" or "zh-Hant" or "zh-HK";
}

public static class ContinuousPlayCardEnvironment
{
    // The trade rule (only the app's own switches): Windows do-not-disturb, quiet time and every full-screen state (2, 3, 7)
    // let it through; a locked or switched desktop (1), presentation mode (4), an inactive desktop or an unknown shell state
    // block it, as they block every card (user 11-14: "免打扰时也照常弹"; spec: game full screen, borderless, window, desktop).
    public static string SuppressionReason(string tradeRule) => tradeRule;
}
