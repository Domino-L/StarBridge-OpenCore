namespace StarBridge.Desktop;

/// <summary>
/// Derives the menu-overlay editor layout from the width actually owned by the
/// editor workspace. The window width is deliberately not an input.
/// </summary>
public static class MenuOverlaySettingsResponsiveLayout
{
    public const double NavigationWidth = 190;
    public const double SettingsWidth = 520;
    public const double InterColumnGap = 12;
    public const double MinimumPreviewWidth = 520;
    public const double WideMinimumWidth =
        NavigationWidth +
        SettingsWidth +
        (InterColumnGap * 2) +
        MinimumPreviewWidth;

    public static MenuOverlaySettingsResponsiveState Resolve(double workspaceWidth)
    {
        var hasMeasurement = double.IsFinite(workspaceWidth) && workspaceWidth > 0;
        var compact = !hasMeasurement || workspaceWidth < WideMinimumWidth;

        return new MenuOverlaySettingsResponsiveState(
            compact,
            compact ? 0 : NavigationWidth,
            compact ? 0 : SettingsWidth);
    }
}

public readonly record struct MenuOverlaySettingsResponsiveState(
    bool UsesCompactDrawers,
    double NavigationColumnWidth,
    double SettingsColumnWidth);
