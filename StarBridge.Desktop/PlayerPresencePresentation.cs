using StarBridge.Core.Presence;

namespace StarBridge.Desktop;

internal sealed record PlayerPresenceVisibilityOption(
    PlayerPresenceVisibilityMode Mode,
    string DisplayName,
    string Description)
{
    public override string ToString() => DisplayName;
}

internal static class PlayerPresenceVisibilityCatalog
{
    public static IReadOnlyList<PlayerPresenceVisibilityOption> Options { get; } =
    [
        new(PlayerPresenceVisibilityMode.Online, "在线", "应用启动后对外显示在线；游戏中或暂离时会按实际状态更新。"),
        new(PlayerPresenceVisibilityMode.Invisible, "隐身", "对外显示离线且不上传即时状态，仍可接收在线内容。"),
        new(PlayerPresenceVisibilityMode.Offline, "离线模式", "停止即时状态收发，游玩时长只在本地记录。")
    ];

    public static PlayerPresenceVisibilityOption Find(PlayerPresenceVisibilityMode mode) =>
        Options.First(option => option.Mode == mode);
}

internal static class PlayerPresencePresentation
{
    public static PlayerPresenceKind Resolve(string? liveStatus, string? onlineStatus)
    {
        var online = string.Equals(onlineStatus, "Online", StringComparison.OrdinalIgnoreCase) ||
                     string.Equals(onlineStatus, "在线", StringComparison.OrdinalIgnoreCase) ||
                     string.Equals(onlineStatus, "应用在线", StringComparison.OrdinalIgnoreCase) ||
                     string.Equals(onlineStatus, "暂离", StringComparison.OrdinalIgnoreCase) ||
                     string.Equals(onlineStatus, "游戏中", StringComparison.OrdinalIgnoreCase) ||
                     string.Equals(onlineStatus, "运行中", StringComparison.OrdinalIgnoreCase) ||
                     string.Equals(onlineStatus, "游戏运行中", StringComparison.OrdinalIgnoreCase);
        return PlayerPresence.Normalize(liveStatus ?? onlineStatus, online);
    }

    public static PlayerPresenceKind ResolveShared(string? liveStatus, string? onlineStatus)
    {
        var presence = Resolve(liveStatus, onlineStatus);
        return presence == PlayerPresenceKind.Paused
            ? PlayerPresenceKind.Offline
            : presence;
    }

    public static string Format(PlayerPresenceKind presence, string language = "zh")
    {
        var zh = language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        return presence switch
        {
            PlayerPresenceKind.AppOnline => zh ? "应用在线" : "App online",
            PlayerPresenceKind.Away => zh ? "暂离" : "Away",
            PlayerPresenceKind.InGame => zh ? "游戏中" : "In game",
            PlayerPresenceKind.Paused => zh ? "离线" : "Offline",
            _ => zh ? "离线" : "Offline"
        };
    }

    public static System.Windows.Media.Brush Brush(PlayerPresenceKind presence) =>
        presence switch
        {
            PlayerPresenceKind.AppOnline => StatusPalette.InfoBrush,
            PlayerPresenceKind.Away => StatusPalette.WarningBrush,
            PlayerPresenceKind.InGame => StatusPalette.SuccessBrush,
            _ => StatusPalette.DisabledBrush
        };

    public static string FormatLocal(
        PlayerPresenceKind automaticPresence,
        PlayerPresenceVisibilityMode visibilityMode,
        string language = "zh")
    {
        var zh = language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        return visibilityMode switch
        {
            PlayerPresenceVisibilityMode.Invisible => automaticPresence == PlayerPresenceKind.InGame
                ? zh ? "隐身 · 游戏记录中" : "Invisible · game tracking"
                : zh ? "隐身" : "Invisible",
            PlayerPresenceVisibilityMode.Offline => automaticPresence == PlayerPresenceKind.InGame
                ? zh ? "离线模式 · 游戏记录中" : "Offline mode · game tracking"
                : zh ? "离线模式" : "Offline mode",
            _ => Format(automaticPresence, language)
        };
    }

    public static System.Windows.Media.Brush LocalBrush(
        PlayerPresenceKind automaticPresence,
        PlayerPresenceVisibilityMode visibilityMode) =>
        visibilityMode == PlayerPresenceVisibilityMode.Online
            ? Brush(automaticPresence)
            : StatusPalette.DisabledBrush;
}

internal static class PlayerSessionStatePresentation
{
    public const string NotInGame = "未进入游戏";
    public const string NotInServer = "未进入服务器";
    public const string WaitingForRecognition = "等待识别";
    public const string WaitingForServerSync = "等待服务器同步";

    public static string ResolveShip(
        PlayerPresenceKind presence,
        bool? hasServerSession,
        string? ship) =>
        ResolveRuntimeValue(presence, hasServerSession, ship);

    public static string ResolveLocation(
        PlayerPresenceKind presence,
        bool? hasServerSession,
        string? location) =>
        ResolveRuntimeValue(presence, hasServerSession, location);

    public static string ResolveServer(
        PlayerPresenceKind presence,
        bool? hasServerSession,
        string? server)
    {
        if (presence != PlayerPresenceKind.InGame)
        {
            return NotInGame;
        }

        if (hasServerSession == false)
        {
            return NotInServer;
        }

        if (HasRecognizedValue(server))
        {
            return server!.Trim();
        }

        return hasServerSession == true
            ? WaitingForRecognition
            : WaitingForServerSync;
    }

    public static bool HasRecognizedValue(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var text = value.Trim();
        return !text.Equals("Unknown", StringComparison.OrdinalIgnoreCase) &&
               !text.Equals("None", StringComparison.OrdinalIgnoreCase) &&
               !text.Equals("N/A", StringComparison.OrdinalIgnoreCase) &&
               !text.Equals("未知", StringComparison.OrdinalIgnoreCase) &&
               !text.Equals("无", StringComparison.OrdinalIgnoreCase) &&
               !text.Equals("未连接", StringComparison.OrdinalIgnoreCase) &&
               !text.Equals("地点：未知星域", StringComparison.OrdinalIgnoreCase) &&
               !text.Equals("飞船：未知", StringComparison.OrdinalIgnoreCase) &&
               !text.StartsWith("等待", StringComparison.OrdinalIgnoreCase) &&
               !IsSessionStateText(text);
    }

    public static bool IsSessionStateText(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var text = value.Trim();
        return text.Equals(NotInGame, StringComparison.OrdinalIgnoreCase) ||
               text.Equals(NotInServer, StringComparison.OrdinalIgnoreCase) ||
               text.Equals(WaitingForRecognition, StringComparison.OrdinalIgnoreCase) ||
               text.Equals(WaitingForServerSync, StringComparison.OrdinalIgnoreCase);
    }

    private static string ResolveRuntimeValue(
        PlayerPresenceKind presence,
        bool? hasServerSession,
        string? value)
    {
        if (presence != PlayerPresenceKind.InGame)
        {
            return NotInGame;
        }

        if (hasServerSession == false)
        {
            return NotInServer;
        }

        if (HasRecognizedValue(value))
        {
            return value!.Trim();
        }

        return hasServerSession == true
            ? WaitingForRecognition
            : WaitingForServerSync;
    }
}
