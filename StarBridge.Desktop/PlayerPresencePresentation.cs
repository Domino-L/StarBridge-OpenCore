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
