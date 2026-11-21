using System.Globalization;
using System.Text.Json;

namespace StarBridge.HostRuntime.Support;

// Relay gives a whole UTC hour (user 11-14: "今天" is the viewer's local calendar day);
// the bridge only ever carries the resulting day count, never a time of day.
internal static class LastOnlineDays
{
    internal const string HeaderName = "X-StarBridge-Last-Online";
    internal const string HeaderValue = "hour-v1";
    internal const string HourField = "lastOnlineHour";
    internal const int Cap = 30;

    internal static void Apply(HttpRequestMessage request) => request.Headers.Add(HeaderName, HeaderValue);

    /// <summary>Missing or null is "unknown". Anything but an exact whole UTC hour is invalid.</summary>
    internal static DateTimeOffset? ReadHour(JsonElement row)
    {
        if (!row.TryGetProperty(HourField, out var value) || value.ValueKind == JsonValueKind.Null) return null;
        if (value.ValueKind != JsonValueKind.String) throw new JsonException("Invalid lastOnlineHour.");
        return ParseHour(value.GetString()) ?? throw new JsonException("Invalid lastOnlineHour.");
    }

    internal static DateTimeOffset? ParseHour(string? text)
    {
        if (text is not { Length: 20 } || !text.EndsWith('Z') ||
            !DateTimeOffset.TryParseExact(text, "yyyy-MM-dd'T'HH':00:00Z'", CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var hour) ||
            hour <= DateTimeOffset.UnixEpoch) return null;
        return hour;
    }

    /// <summary>Local calendar days between the two instants: same local date 0, across one local midnight 1.</summary>
    internal static int CalendarDays(DateTimeOffset at, DateTimeOffset now, TimeZoneInfo zone)
    {
        var days = (TimeZoneInfo.ConvertTime(now, zone).Date - TimeZoneInfo.ConvertTime(at, zone).Date).Days;
        // A skewed local clock may put the relay hour slightly ahead; it is still "today".
        return Math.Clamp(days, 0, Cap);
    }

    /// <summary>The relay hour wins; the legacy precise time is only a fallback for an older relay.</summary>
    internal static int? Resolve(DateTimeOffset? hour, DateTimeOffset? legacyAt, DateTimeOffset now, TimeZoneInfo? zone = null) =>
        (hour ?? legacyAt) is { } at ? CalendarDays(at, now, zone ?? TimeZoneInfo.Local) : null;
}
