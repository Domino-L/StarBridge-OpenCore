using System.Windows;
using StarBridge.Core.Overlay;

namespace StarBridge.Desktop;

/// <summary>
/// WPF adapter for the shared information-overlay layout geometry module.
/// </summary>
internal static class OverlaySurfaceLayout
{
    public const double EventNotificationEdgeInset =
        InformationOverlayLayoutGeometry.EventNotificationEdgeInset;
    public const double EventNotificationVerticalInset =
        InformationOverlayLayoutGeometry.EventNotificationVerticalInset;

    public static Rect ResolveItemRect(
        OverlayLayoutItem item,
        double surfaceWidth,
        double surfaceHeight) =>
        ToWpfRect(InformationOverlayLayoutGeometry.ResolveItemRect(
            item,
            surfaceWidth,
            surfaceHeight));

    public static IReadOnlyDictionary<string, Rect> ResolveItems(
        IEnumerable<OverlayLayoutItem> items,
        double surfaceWidth,
        double surfaceHeight) =>
        InformationOverlayLayoutGeometry.ResolveItems(
                items,
                surfaceWidth,
                surfaceHeight)
            .ToDictionary(
                entry => entry.Key,
                entry => ToWpfRect(entry.Value),
                StringComparer.OrdinalIgnoreCase);

    public static void ApplyRectToItem(
        OverlayLayoutItem item,
        Rect rect,
        double surfaceWidth,
        double surfaceHeight)
    {
        InformationOverlayLayoutGeometry.ApplyRectToItem(
            item,
            new InformationOverlayRect(rect.Left, rect.Top, rect.Width, rect.Height),
            surfaceWidth,
            surfaceHeight);
    }

    public static Rect ResolveEventNotificationRect(
        double surfaceWidth,
        double surfaceHeight,
        OverlayEventNotificationSide side,
        double normalizedY,
        double preferredHeight,
        double snapSize = 0) =>
        ToWpfRect(InformationOverlayLayoutGeometry.ResolveEventNotificationRect(
            surfaceWidth,
            surfaceHeight,
            side,
            normalizedY,
            preferredHeight,
            snapSize));

    public static double ResolveEventNotificationWidth(double surfaceWidth) =>
        InformationOverlayLayoutGeometry.ResolveEventNotificationWidth(surfaceWidth);

    public static OverlayHorizontalAnchor ResolveHorizontalAnchor(OverlayLayoutItem item) =>
        item.HorizontalAnchor;

    public static OverlayVerticalAnchor ResolveVerticalAnchor(OverlayLayoutItem item) =>
        item.VerticalAnchor;

    private static Rect ToWpfRect(InformationOverlayRect rect) =>
        new(rect.Left, rect.Top, rect.Width, rect.Height);
}
