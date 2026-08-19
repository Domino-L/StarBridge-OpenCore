namespace StarBridge.Core.FleetBroadcasts;

public sealed record FleetBroadcastAppearanceContract(
    string AccentColor,
    string BackgroundColor,
    string TextColor,
    double DurationSeconds,
    int RepeatCount,
    double FontScale);

public sealed record FleetBroadcastAuthorContract(
    string AccountId,
    string Callsign,
    string GameName,
    string RoleTitle);

public sealed record FleetBroadcastContract(
    string Id,
    string FleetCode,
    string Message,
    FleetBroadcastAuthorContract Author,
    FleetBroadcastAppearanceContract Appearance,
    DateTimeOffset SentAt,
    DateTimeOffset ExpiresAt);

public sealed record FleetBroadcastFeedContract(
    string FleetCode,
    FleetBroadcastContract[] Broadcasts,
    bool CanPublish,
    DateTimeOffset ServerTime);

public sealed record FleetBroadcastPublishRequestContract(
    string FleetCode,
    string? Message,
    FleetBroadcastAppearanceContract? Appearance,
    string? ClientRequestId);

public sealed record FleetBroadcastMutationResponseContract(
    FleetBroadcastContract? Broadcast,
    string Status,
    string? Error = null);

public static class FleetBroadcastPolicy
{
    public const int MaximumMessageLength = 180;
    public const int MaximumRequestIdLength = 80;
    public const int MaximumRetainedBroadcasts = 100;
    public static readonly TimeSpan DeliveryWindow = TimeSpan.FromMinutes(10);
    public static readonly TimeSpan PublishCooldown = TimeSpan.FromSeconds(15);

    public static FleetBroadcastAppearanceContract DefaultAppearance { get; } = new(
        "#FF5D66",
        "#E6101822",
        "#FFFFFFFF",
        10,
        2,
        1);

    public static (string Message, string? Error) NormalizeMessage(string? value)
    {
        var message = string.IsNullOrWhiteSpace(value) ? "" : value.Trim();
        if (message.Length == 0)
        {
            return ("", "请输入广播内容。");
        }

        if (message.Length > MaximumMessageLength)
        {
            return (message[..MaximumMessageLength], $"广播内容不能超过 {MaximumMessageLength} 个字符。");
        }

        return (message, null);
    }

    public static string NormalizeRequestId(string? value)
    {
        var requestId = string.IsNullOrWhiteSpace(value) ? "" : value.Trim();
        return requestId.Length <= MaximumRequestIdLength
            ? requestId
            : requestId[..MaximumRequestIdLength];
    }

    public static FleetBroadcastAppearanceContract NormalizeAppearance(
        FleetBroadcastAppearanceContract? appearance)
    {
        var value = appearance ?? DefaultAppearance;
        return new FleetBroadcastAppearanceContract(
            NormalizeColor(value.AccentColor, DefaultAppearance.AccentColor),
            NormalizeColor(value.BackgroundColor, DefaultAppearance.BackgroundColor),
            NormalizeColor(value.TextColor, DefaultAppearance.TextColor),
            Math.Clamp(value.DurationSeconds, 6, 20),
            Math.Clamp(value.RepeatCount, 1, 3),
            Math.Clamp(value.FontScale, 0.9, 1.5));
    }

    private static string NormalizeColor(string? value, string fallback)
    {
        var color = string.IsNullOrWhiteSpace(value) ? "" : value.Trim().ToUpperInvariant();
        if ((color.Length is 7 or 9) &&
            color[0] == '#' &&
            color[1..].All(Uri.IsHexDigit))
        {
            return color;
        }

        return fallback;
    }
}
