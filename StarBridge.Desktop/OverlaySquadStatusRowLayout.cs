namespace StarBridge.Desktop;

internal readonly record struct OverlaySquadStatusColumn(float Left, float Width)
{
    public float Right => Left + Width;
}

/// <summary>
/// Allocates the three overview funnel fields without allowing their draw boxes
/// to overlap. Module width is the only input: changing counts, copy, or language
/// cannot move a column boundary while the user leaves the module size unchanged.
/// </summary>
internal readonly record struct OverlaySquadStatusRowLayout(
    OverlaySquadStatusColumn Primary,
    OverlaySquadStatusColumn Summary,
    OverlaySquadStatusColumn Server,
    bool UseCompactMetricFormat)
{
    public const float CompactThreshold = 280;

    public static OverlaySquadStatusRowLayout Resolve(float contentWidth)
    {
        var width = Math.Max(1, contentWidth);
        var compact = width < CompactThreshold;
        // Keep the boundaries identical to the WPF */*/* grid and to the
        // editor's Star columns. Renderers may add padding inside a column,
        // but copy and renderer-specific gaps must never move the funnel.
        var columnWidth = width / 3f;
        var primary = new OverlaySquadStatusColumn(0, columnWidth);
        var summary = new OverlaySquadStatusColumn(
            primary.Right,
            columnWidth);
        var server = new OverlaySquadStatusColumn(
            summary.Right,
            Math.Max(0, width - summary.Right));
        return new OverlaySquadStatusRowLayout(
            primary,
            summary,
            server,
            compact);
    }
}
