namespace StarBridge.Desktop;

/// <summary>
/// Derives the information-overlay editor layout from the space actually owned
/// by its workspace and toolbar. Window width is deliberately not an input.
/// </summary>
public static class OverlayEditorResponsiveLayout
{
    public const double CategoryWidth = 196;
    public const double SettingsWidth = 400;
    public const double MinimumPreviewWidth = 640;
    public const double WideMinimumWidth = CategoryWidth + SettingsWidth + MinimumPreviewWidth;
    public const double InlineToolbarMinimumWidth = 1060;
    public const double StandardFullScreenInlineMinimumWidth = 568;
    public const double CompactFullScreenInlineMinimumWidth = 724;

    public static OverlayEditorResponsiveState Resolve(
        double workspaceWidth,
        double toolbarWidth,
        bool isFullScreen)
    {
        var hasWorkspaceMeasurement = double.IsFinite(workspaceWidth) && workspaceWidth > 0;
        var hasToolbarMeasurement = double.IsFinite(toolbarWidth) && toolbarWidth > 0;
        var compact = isFullScreen || !hasWorkspaceMeasurement || workspaceWidth < WideMinimumWidth;
        var overflow = !hasToolbarMeasurement || toolbarWidth < InlineToolbarMinimumWidth;
        var showsCompactSidebarButtons = compact && !isFullScreen;
        var fullScreenInlineMinimumWidth = showsCompactSidebarButtons
            ? CompactFullScreenInlineMinimumWidth
            : StandardFullScreenInlineMinimumWidth;
        var showsFullScreenInline = hasToolbarMeasurement && toolbarWidth >= fullScreenInlineMinimumWidth;

        return new OverlayEditorResponsiveState(
            compact,
            overflow,
            showsFullScreenInline,
            compact ? 0 : CategoryWidth,
            compact ? 0 : SettingsWidth);
    }
}

public readonly record struct OverlayEditorResponsiveState(
    bool UsesCompactSidebars,
    bool UsesToolbarOverflow,
    bool ShowsFullScreenInline,
    double CategoryColumnWidth,
    double SettingsColumnWidth);
