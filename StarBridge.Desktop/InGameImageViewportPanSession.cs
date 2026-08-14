namespace StarBridge.Desktop;

using System.Windows;
using System.Windows.Controls;

internal sealed class InGameImageViewportPanSession
{
    private const double OverflowEpsilon = 0.5;
    private Point _pointerOrigin;
    private double _horizontalOrigin;
    private double _verticalOrigin;

    internal bool IsActive { get; private set; }

    internal bool TryBegin(ScrollViewer viewport, Point pointer)
    {
        ArgumentNullException.ThrowIfNull(viewport);

        if (viewport.ScrollableWidth <= OverflowEpsilon &&
            viewport.ScrollableHeight <= OverflowEpsilon)
        {
            End();
            return false;
        }

        _pointerOrigin = pointer;
        _horizontalOrigin = viewport.HorizontalOffset;
        _verticalOrigin = viewport.VerticalOffset;
        IsActive = true;
        return true;
    }

    internal bool Update(ScrollViewer viewport, Point pointer)
    {
        ArgumentNullException.ThrowIfNull(viewport);

        if (!IsActive)
        {
            return false;
        }

        var horizontalOffset = Math.Clamp(
            _horizontalOrigin - (pointer.X - _pointerOrigin.X),
            0,
            viewport.ScrollableWidth);
        var verticalOffset = Math.Clamp(
            _verticalOrigin - (pointer.Y - _pointerOrigin.Y),
            0,
            viewport.ScrollableHeight);
        viewport.ScrollToHorizontalOffset(horizontalOffset);
        viewport.ScrollToVerticalOffset(verticalOffset);
        return true;
    }

    internal void End() => IsActive = false;
}

internal readonly record struct InGameImageWheelZoomPlan(
    double TargetZoom,
    double SourceX,
    double SourceY);

internal static class InGameImageWheelZoom
{
    private const double ZoomPerWheelNotch = 10;
    private const double WheelDeltaPerNotch = 120;

    internal static InGameImageWheelZoomPlan Project(
        double currentZoom,
        int wheelDelta,
        double minimumZoom,
        double maximumZoom,
        Point pointerInImage,
        Size imageSize)
    {
        var targetZoom = Math.Clamp(
            currentZoom + wheelDelta / WheelDeltaPerNotch * ZoomPerWheelNotch,
            minimumZoom,
            maximumZoom);
        var sourceX = imageSize.Width > 0
            ? Math.Clamp(pointerInImage.X / imageSize.Width, 0, 1)
            : 0.5;
        var sourceY = imageSize.Height > 0
            ? Math.Clamp(pointerInImage.Y / imageSize.Height, 0, 1)
            : 0.5;
        return new InGameImageWheelZoomPlan(targetZoom, sourceX, sourceY);
    }

    internal static void RestorePointerAnchor(
        ScrollViewer viewport,
        FrameworkElement scrollContent,
        FrameworkElement image,
        Point pointerInViewport,
        InGameImageWheelZoomPlan plan)
    {
        ArgumentNullException.ThrowIfNull(viewport);
        ArgumentNullException.ThrowIfNull(scrollContent);
        ArgumentNullException.ThrowIfNull(image);

        var contentLeft = Math.Max(0, (scrollContent.ActualWidth - image.ActualWidth) / 2);
        var contentTop = Math.Max(0, (scrollContent.ActualHeight - image.ActualHeight) / 2);
        viewport.ScrollToHorizontalOffset(
            contentLeft + plan.SourceX * image.ActualWidth - pointerInViewport.X);
        viewport.ScrollToVerticalOffset(
            contentTop + plan.SourceY * image.ActualHeight - pointerInViewport.Y);
    }
}

internal enum InGameImageViewportMode
{
    FramedArea,
    FullImage
}

internal sealed record InGameImageViewportModeOption(
    InGameImageViewportMode Value,
    string DisplayName)
{
    public override string ToString() => DisplayName;
}

internal static class InGameImageViewportModePresentation
{
    internal static IReadOnlyList<InGameImageViewportModeOption> Options(
        string? language)
    {
        var zh = language?.Trim().StartsWith(
            "zh",
            StringComparison.OrdinalIgnoreCase) == true;
        return zh
            ?
            [
                new(InGameImageViewportMode.FramedArea, "仅显示框内部分"),
                new(InGameImageViewportMode.FullImage, "显示完整图片")
            ]
            :
            [
                new(InGameImageViewportMode.FramedArea, "Show framed area"),
                new(InGameImageViewportMode.FullImage, "Show full image")
            ];
    }
}

internal readonly record struct InGameImageToolbarLayout(
    bool UseCompactSettings,
    bool ShowExpandedSettings,
    double ToolbarHeight,
    double StatusHeight);

internal static class InGameImageToolbarLayoutPolicy
{
    // 650 DIP of controls + 28 DIP toolbar padding + 16 DIP breathing room.
    internal const double WideMinimumAvailableWidth = 694;
    internal const double WideToolbarHeight = 88;
    internal const double CompactToolbarHeight = 50;
    internal const double StatusHeight = 56;

    internal static InGameImageToolbarLayout Resolve(
        double availableToolbarWidth,
        bool compactSettingsExpanded)
    {
        var useCompact = !double.IsFinite(availableToolbarWidth) ||
                         availableToolbarWidth < WideMinimumAvailableWidth;
        if (!useCompact)
        {
            return new(
                UseCompactSettings: false,
                ShowExpandedSettings: false,
                ToolbarHeight: WideToolbarHeight,
                StatusHeight: StatusHeight);
        }

        return compactSettingsExpanded
            ? new(
                UseCompactSettings: true,
                ShowExpandedSettings: true,
                ToolbarHeight: CompactToolbarHeight,
                StatusHeight: StatusHeight)
            : new(
                UseCompactSettings: true,
                ShowExpandedSettings: false,
                ToolbarHeight: CompactToolbarHeight,
                StatusHeight: StatusHeight);
    }
}
