using System.Globalization;

namespace StarBridge.Desktop;

/// <summary>
/// Owns the timestamp language shared by every desktop communication surface.
/// </summary>
public static class CommunicationTimeFormatter
{
    private static readonly TimeSpan RelativeTimeWindow = TimeSpan.FromDays(7);

    public static string Format(DateTimeOffset publishedAt, DateTimeOffset? now = null)
    {
        if (publishedAt == default)
        {
            return "";
        }

        var current = now ?? DateTimeOffset.Now;
        var elapsed = current - publishedAt;
        if (elapsed <= TimeSpan.Zero)
        {
            return "刚刚";
        }

        if (elapsed < TimeSpan.FromMinutes(1))
        {
            return "刚刚";
        }

        if (elapsed < TimeSpan.FromHours(1))
        {
            return $"{(int)elapsed.TotalMinutes}分钟前";
        }

        if (elapsed < TimeSpan.FromDays(1))
        {
            return $"{(int)elapsed.TotalHours}小时前";
        }

        if (elapsed < RelativeTimeWindow)
        {
            return $"{(int)elapsed.TotalDays}天前";
        }

        var localPublishedAt = publishedAt.ToLocalTime();
        var localCurrent = current.ToLocalTime();
        var absoluteFormat = localPublishedAt.Year == localCurrent.Year
            ? "MM-dd HH:mm"
            : "yyyy-MM-dd HH:mm";
        return localPublishedAt.ToString(absoluteFormat, CultureInfo.InvariantCulture);
    }
}
