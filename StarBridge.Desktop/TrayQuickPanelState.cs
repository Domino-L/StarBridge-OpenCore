using System.Drawing;
using System.Globalization;
using System.Windows.Media;
using StarBridge.Core.Presence;

namespace StarBridge.Desktop;

internal sealed record TrayQuickPanelState(
    string VersionText,
    string RuntimeStatusText,
    PlayerPresenceKind Presence,
    bool IsGameRunning,
    bool IsOverlayRunning,
    string OverlayStatusText,
    string OverlayActionText,
    string SceneText,
    ImageSource? AvatarSource,
    string AvatarInitial)
{
    public static TrayQuickPanelState Unavailable { get; } = new(
        "V--",
        "应用状态不可用",
        PlayerPresenceKind.Offline,
        false,
        false,
        "未开启",
        "开启浮层",
        "等待主窗口",
        null,
        "星");
}

internal static class TrayQuickPanelIdentity
{
    public static string ResolveAvatarInitial(string? displayName)
    {
        var normalized = displayName?.Trim();
        return string.IsNullOrWhiteSpace(normalized)
            ? "星"
            : StringInfo.GetNextTextElement(normalized).ToUpperInvariant();
    }
}

internal enum TrayTaskbarEdge
{
    Bottom,
    Top,
    Left,
    Right
}

internal static class TrayQuickPanelPlacement
{
    public static TrayTaskbarEdge ResolveTaskbarEdge(Rectangle bounds, Rectangle workingArea)
    {
        var candidates = new (TrayTaskbarEdge Edge, int Size)[]
        {
            (TrayTaskbarEdge.Bottom, Math.Max(0, bounds.Bottom - workingArea.Bottom)),
            (TrayTaskbarEdge.Top, Math.Max(0, workingArea.Top - bounds.Top)),
            (TrayTaskbarEdge.Left, Math.Max(0, workingArea.Left - bounds.Left)),
            (TrayTaskbarEdge.Right, Math.Max(0, bounds.Right - workingArea.Right))
        };
        return candidates.OrderByDescending(candidate => candidate.Size).First().Edge;
    }

    public static Point Resolve(
        Rectangle bounds,
        Rectangle workingArea,
        Point cursor,
        Size panelSize,
        int gap)
    {
        var edge = ResolveTaskbarEdge(bounds, workingArea);
        var x = edge switch
        {
            TrayTaskbarEdge.Left => workingArea.Left + gap,
            TrayTaskbarEdge.Right => workingArea.Right - panelSize.Width - gap,
            _ => cursor.X - panelSize.Width / 2
        };
        var y = edge switch
        {
            TrayTaskbarEdge.Top => workingArea.Top + gap,
            TrayTaskbarEdge.Bottom => workingArea.Bottom - panelSize.Height - gap,
            _ => cursor.Y - panelSize.Height / 2
        };

        return new Point(
            ClampToWorkingArea(x, workingArea.Left + gap, workingArea.Right - panelSize.Width - gap),
            ClampToWorkingArea(y, workingArea.Top + gap, workingArea.Bottom - panelSize.Height - gap));
    }

    private static int ClampToWorkingArea(int value, int minimum, int maximum)
    {
        if (maximum < minimum)
        {
            return minimum;
        }

        return Math.Clamp(value, minimum, maximum);
    }
}
