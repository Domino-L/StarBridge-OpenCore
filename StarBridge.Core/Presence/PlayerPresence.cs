namespace StarBridge.Core.Presence;

public enum PlayerPresenceKind
{
    Offline,
    AppOnline,
    Away,
    InGame,
    Paused
}

public enum PlayerPresenceVisibilityMode
{
    Online,
    Invisible,
    Offline
}

public readonly record struct PlayerPresenceSharingDecision(
    PlayerPresenceKind PublicPresence,
    bool CanPublishRealtime,
    bool CanReceiveRealtime);

public static class PlayerPresence
{
    public static readonly TimeSpan DefaultAwayAfter = TimeSpan.FromMinutes(15);

    public static PlayerPresenceKind Resolve(
        bool appOnline,
        bool gameRunning,
        DateTimeOffset lastAppInteractionAt,
        DateTimeOffset now,
        TimeSpan? awayAfter = null)
    {
        if (!appOnline)
        {
            return PlayerPresenceKind.Offline;
        }

        if (gameRunning)
        {
            return PlayerPresenceKind.InGame;
        }

        var threshold = awayAfter.GetValueOrDefault(DefaultAwayAfter);
        if (threshold <= TimeSpan.Zero)
        {
            threshold = DefaultAwayAfter;
        }

        return lastAppInteractionAt != default && now - lastAppInteractionAt >= threshold
            ? PlayerPresenceKind.Away
            : PlayerPresenceKind.AppOnline;
    }

    public static PlayerPresenceKind Normalize(string? value, bool online)
    {
        var normalized = NormalizeKey(value);
        if (normalized is "PAUSED" or "STOPPED" or "SUSPENDED" or "SYNCSTOPPED" or "SYNCPAUSED")
        {
            return PlayerPresenceKind.Paused;
        }

        if (!online)
        {
            return PlayerPresenceKind.Offline;
        }

        return normalized switch
        {
            "INGAME" or "GAME" or "PLAYING" or "GAMERUNNING" or "ACTIVE" or "游戏中" => PlayerPresenceKind.InGame,
            "AWAY" or "IDLE" or "AFK" or "暂离" => PlayerPresenceKind.Away,
            "APPONLINE" or "APPLICATIONONLINE" or "ONLINE" or "应用在线" or "在线" => PlayerPresenceKind.AppOnline,
            "OFFLINE" or "离线" => PlayerPresenceKind.Offline,
            _ => PlayerPresenceKind.AppOnline
        };
    }

    public static bool IsOnline(PlayerPresenceKind presence) =>
        presence is PlayerPresenceKind.AppOnline or PlayerPresenceKind.Away or PlayerPresenceKind.InGame;

    public static PlayerPresenceSharingDecision DecideSharing(
        PlayerPresenceKind automaticPresence,
        PlayerPresenceVisibilityMode visibilityMode) =>
        visibilityMode switch
        {
            PlayerPresenceVisibilityMode.Invisible => new(
                PlayerPresenceKind.Offline,
                CanPublishRealtime: false,
                CanReceiveRealtime: true),
            PlayerPresenceVisibilityMode.Offline => new(
                PlayerPresenceKind.Offline,
                CanPublishRealtime: false,
                CanReceiveRealtime: false),
            _ => new(
                automaticPresence,
                CanPublishRealtime: true,
                CanReceiveRealtime: true)
        };

    public static string ToWireValue(PlayerPresenceKind presence) =>
        presence switch
        {
            PlayerPresenceKind.AppOnline => "AppOnline",
            PlayerPresenceKind.Away => "Away",
            PlayerPresenceKind.InGame => "InGame",
            PlayerPresenceKind.Paused => "Paused",
            _ => "Offline"
        };

    private static string NormalizeKey(string? value) =>
        string.IsNullOrWhiteSpace(value)
            ? ""
            : value.Trim()
                .Replace(" ", "", StringComparison.Ordinal)
                .Replace("-", "", StringComparison.Ordinal)
                .Replace("_", "", StringComparison.Ordinal)
                .ToUpperInvariant();
}
