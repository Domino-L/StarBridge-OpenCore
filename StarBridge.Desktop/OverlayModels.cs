using System.Windows.Media;
using StarBridge.Core.Overlay;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;

namespace StarBridge.Desktop;

internal enum OverlaySkinRenderKind
{
    Default,
    NightShadow,
    LagrangeWeave,
    Verdict
}

internal static class OverlayStartupTransitionPolicy
{
    public static OverlayDisplaySettings ResolveForOpen(
        OverlayDisplaySettings settings,
        bool isGameForeground)
    {
        if (!settings.EnableStartupTransition ||
            !settings.SkipStartupTransitionWhenGameForeground ||
            !isGameForeground)
        {
            return settings;
        }

        return settings with { EnableStartupTransition = false };
    }
}

public sealed record OverlayCommandState(
    string? NoticeTitle,
    string? NoticeText,
    string? FleetTaskTitle,
    string? FleetTaskBrief,
    string? RallyPoint,
    string? RequiredShip);

public sealed record OverlayChatMessage(
    long Sequence,
    string ChannelId,
    string SenderCallsign,
    string SenderGameId,
    string Text,
    DateTimeOffset CreatedAt,
    bool IsSystem,
    bool IsSelf,
    string SenderColor,
    string? SourceLabel = null);

public sealed record MemberAvatarRow(
    string Name,
    string Initials,
    string Status,
    string? AvatarPath = null,
    Brush? NameBrush = null,
    bool IsCommander = false,
    string GameId = "",
    string? Callsign = null,
    string? AccountId = null,
    bool IsSelf = false,
    string? LiveStatus = null)
{
    public string PresenceText => PlayerPresencePresentation.Format(
        PlayerPresencePresentation.ResolveShared(LiveStatus, Status));
    public Brush StatusBrush => PlayerPresencePresentation.Brush(
        PlayerPresencePresentation.ResolveShared(LiveStatus, Status));
}

public sealed class OverlayLayoutItem : InformationOverlayLayoutItem
{
    public OverlayLayoutItem(
        string key,
        string title,
        double x,
        double y,
        double width,
        double height,
        Brush brush,
        OverlayHorizontalAnchor? horizontalAnchor = null,
        OverlayVerticalAnchor? verticalAnchor = null,
        bool isLocked = false,
        double textOpacity = 1.0,
        double backgroundOpacity = 1.0,
        double decorationOpacity = 1.0)
        : base(
            key,
            x,
            y,
            width,
            height,
            horizontalAnchor,
            verticalAnchor,
            isLocked,
            textOpacity,
            backgroundOpacity,
            decorationOpacity)
    {
        Title = title;
        Brush = brush;
    }

    public string Title { get; }

    public Brush Brush { get; }

    public static new IEnumerable<OverlayLayoutItem> ParseMany(string? value)
    {
        foreach (var item in InformationOverlayLayoutItem.ParseMany(value))
        {
            yield return new OverlayLayoutItem(
                item.Key,
                GetTitle(item.Key),
                item.X,
                item.Y,
                item.Width,
                item.Height,
                GetBrush(item.Key),
                item.HorizontalAnchor,
                item.VerticalAnchor,
                item.IsLocked,
                item.TextOpacity,
                item.BackgroundOpacity,
                item.DecorationOpacity);
        }
    }

    private static string GetTitle(string key)
    {
        return key switch
        {
            "Notice" => "通讯事件",
            "Squads" => "舰队总览",
            "Members" => "成员状态",
            "Chat" => "场景通讯",
            _ => key
        };
    }

    private static Brush GetBrush(string key)
    {
        return key switch
        {
            "Notice" => Brushes.Yellow,
            "Squads" => Brushes.DeepSkyBlue,
            "Members" => Brushes.Gray,
            "Chat" => Brushes.MediumPurple,
            _ => Brushes.DeepSkyBlue
        };
    }
}
