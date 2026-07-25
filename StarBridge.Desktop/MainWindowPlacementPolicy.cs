namespace StarBridge.Desktop;

internal readonly record struct AppWindowBounds(
    double Left,
    double Top,
    double Width,
    double Height)
{
    internal double Right => Left + Width;

    internal double Bottom => Top + Height;
}

internal static class MainWindowPlacementPolicy
{
    internal static AppWindowBounds FitAndCenter(
        AppWindowBounds requested,
        AppWindowBounds workingArea,
        double margin = 8)
    {
        var safeMargin = NormalizeMargin(margin, workingArea);
        var availableWidth = Math.Max(1, workingArea.Width - (safeMargin * 2));
        var availableHeight = Math.Max(1, workingArea.Height - (safeMargin * 2));
        var width = Math.Min(NormalizeLength(requested.Width, availableWidth), availableWidth);
        var height = Math.Min(NormalizeLength(requested.Height, availableHeight), availableHeight);

        return new AppWindowBounds(
            workingArea.Left + ((workingArea.Width - width) / 2),
            workingArea.Top + ((workingArea.Height - height) / 2),
            width,
            height);
    }

    internal static AppWindowBounds EnsureVisible(
        AppWindowBounds requested,
        AppWindowBounds workingArea,
        double margin = 8)
    {
        if (!IsUsable(requested) || !IsUsable(workingArea))
        {
            return FitAndCenter(requested, workingArea, margin);
        }

        var safeMargin = NormalizeMargin(margin, workingArea);
        var availableWidth = Math.Max(1, workingArea.Width - (safeMargin * 2));
        var availableHeight = Math.Max(1, workingArea.Height - (safeMargin * 2));
        if (requested.Width > availableWidth || requested.Height > availableHeight)
        {
            return FitAndCenter(requested, workingArea, safeMargin);
        }

        const double titleBarHeight = 48;
        const double minimumVisibleTitleWidth = 160;
        const double minimumVisibleTitleHeight = 28;
        var titleRight = requested.Right;
        var titleBottom = requested.Top + Math.Min(titleBarHeight, requested.Height);
        var visibleWidth = Math.Max(
            0,
            Math.Min(titleRight, workingArea.Right) - Math.Max(requested.Left, workingArea.Left));
        var visibleHeight = Math.Max(
            0,
            Math.Min(titleBottom, workingArea.Bottom) - Math.Max(requested.Top, workingArea.Top));

        return visibleWidth >= Math.Min(minimumVisibleTitleWidth, requested.Width) &&
               visibleHeight >= Math.Min(minimumVisibleTitleHeight, requested.Height)
            ? requested
            : FitAndCenter(requested, workingArea, safeMargin);
    }

    private static double NormalizeLength(double value, double fallback) =>
        double.IsFinite(value) && value > 0 ? value : fallback;

    private static double NormalizeMargin(double margin, AppWindowBounds workingArea)
    {
        if (!double.IsFinite(margin) || margin < 0)
        {
            return 0;
        }

        return Math.Min(margin, Math.Max(0, Math.Min(workingArea.Width, workingArea.Height) / 4));
    }

    private static bool IsUsable(AppWindowBounds bounds) =>
        double.IsFinite(bounds.Left) &&
        double.IsFinite(bounds.Top) &&
        double.IsFinite(bounds.Width) &&
        double.IsFinite(bounds.Height) &&
        bounds.Width > 0 &&
        bounds.Height > 0;
}
