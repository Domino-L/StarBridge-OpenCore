namespace StarBridge.Desktop;

internal readonly record struct FindFleetDirectoryMetrics(
    double MinItemWidth,
    double MaxItemWidth,
    int MaxColumns,
    double ItemGap,
    double SidebarMinWidth,
    double SplitGap);

internal readonly record struct FindFleetGridResolution(
    int ColumnCount,
    double ItemWidth,
    double ContentWidth);

internal readonly record struct FindFleetSplitResolution(
    bool UseFilterDrawer,
    double SidebarWidth,
    double SidebarMinWidth,
    double SplitGap,
    double CollapseThreshold);

/// <summary>
/// Owns the complete responsive contract for the Find Fleet directory.
/// Callers provide only the width that their own layout pass has actually
/// made available; window chrome and host padding never enter this seam.
/// </summary>
internal static class FindFleetDirectoryLayout
{
    internal const double MinItemWidth = 520d;
    internal const double MaxItemWidth = 700d;
    internal const int MaxColumns = 4;
    internal const double ItemGap = 12d;
    internal const double SidebarMinWidth = 320d;
    internal const double SplitGap = 14d;

    internal static FindFleetDirectoryMetrics ProductionMetrics { get; } = new(
        MinItemWidth,
        MaxItemWidth,
        MaxColumns,
        ItemGap,
        SidebarMinWidth,
        SplitGap);

    internal static FindFleetGridResolution ResolveGrid(double availableWidth) =>
        ResolveGrid(availableWidth, ProductionMetrics);

    internal static FindFleetGridResolution ResolveGrid(
        double availableWidth,
        FindFleetDirectoryMetrics metrics)
    {
        ValidateAvailableWidth(availableWidth, nameof(availableWidth));
        ValidateMetrics(metrics);

        var columnsByMinimum = (int)Math.Floor(
            (availableWidth + metrics.ItemGap) /
            (metrics.MinItemWidth + metrics.ItemGap));
        var columnCount = Math.Clamp(columnsByMinimum, 1, metrics.MaxColumns);
        var widthAfterGaps = Math.Max(0d, availableWidth - (columnCount - 1) * metrics.ItemGap);
        var naturalItemWidth = widthAfterGaps / columnCount;
        var itemWidth = Math.Min(metrics.MaxItemWidth, naturalItemWidth);
        var contentWidth = columnCount * itemWidth + (columnCount - 1) * metrics.ItemGap;

        return new FindFleetGridResolution(columnCount, itemWidth, contentWidth);
    }

    internal static FindFleetSplitResolution ResolveSplit(
        double splitAvailableWidth,
        double verticalScrollBarWidth) =>
        ResolveSplit(splitAvailableWidth, verticalScrollBarWidth, ProductionMetrics);

    internal static FindFleetSplitResolution ResolveSplit(
        double splitAvailableWidth,
        double verticalScrollBarWidth,
        FindFleetDirectoryMetrics metrics)
    {
        ValidateAvailableWidth(splitAvailableWidth, nameof(splitAvailableWidth));
        ValidateAvailableWidth(verticalScrollBarWidth, nameof(verticalScrollBarWidth), allowZero: true);
        ValidateMetrics(metrics);

        var threshold = metrics.MinItemWidth +
                        metrics.SidebarMinWidth +
                        metrics.SplitGap +
                        verticalScrollBarWidth;
        var useDrawer = splitAvailableWidth < threshold;
        return useDrawer
            ? new FindFleetSplitResolution(true, 0d, 0d, 0d, threshold)
            : new FindFleetSplitResolution(
                false,
                metrics.SidebarMinWidth,
                metrics.SidebarMinWidth,
                metrics.SplitGap,
                threshold);
    }

    private static void ValidateAvailableWidth(
        double width,
        string parameterName,
        bool allowZero = false)
    {
        if (!double.IsFinite(width) || width < 0d || (!allowZero && width == 0d))
        {
            throw new ArgumentOutOfRangeException(parameterName, width, "Available width must be finite and positive.");
        }
    }

    private static void ValidateMetrics(FindFleetDirectoryMetrics metrics)
    {
        if (metrics.MinItemWidth <= 0d ||
            metrics.MaxItemWidth < metrics.MinItemWidth ||
            metrics.MaxColumns < 1 ||
            metrics.ItemGap < 0d ||
            metrics.SidebarMinWidth < 0d ||
            metrics.SplitGap < 0d)
        {
            throw new ArgumentOutOfRangeException(nameof(metrics), metrics, "Find Fleet layout metrics are invalid.");
        }
    }
}
