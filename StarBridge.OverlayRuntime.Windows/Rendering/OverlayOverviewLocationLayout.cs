namespace StarBridge.Desktop;

internal enum OverlayOverviewLocationOrientation
{
    Horizontal,
    Vertical
}

internal sealed record OverlayOverviewLocationLayoutResult(
    OverlayOverviewLocationOrientation Orientation,
    IReadOnlyList<OverlayOverviewLocationCount> VisibleItems);

/// <summary>
/// Resolves only the presentation shape of the typed overview locations. Width
/// selects orientation; height selects the vertical row count. Text measurement
/// and content length deliberately never participate, so data refreshes cannot
/// make the module change shape.
/// </summary>
internal static class OverlayOverviewLocationLayout
{
    // The existing overview metric row already switches to its compact geometry
    // at this measured module width. Reusing it keeps both rows on one breakpoint.
    internal const double HorizontalThreshold = OverlaySquadStatusRowLayout.CompactThreshold;

    internal static OverlayOverviewLocationLayoutResult Resolve(
        double moduleWidth,
        double moduleHeight,
        IReadOnlyList<OverlayOverviewLocationCount> locations)
    {
        ArgumentNullException.ThrowIfNull(locations);

        var orientation = double.IsFinite(moduleWidth) && moduleWidth >= HorizontalThreshold
            ? OverlayOverviewLocationOrientation.Horizontal
            : OverlayOverviewLocationOrientation.Vertical;
        if (locations.Count == 0)
        {
            return new OverlayOverviewLocationLayoutResult(orientation, []);
        }

        var visibleCount = orientation == OverlayOverviewLocationOrientation.Horizontal
            ? Math.Min(2, locations.Count)
            : Math.Min(
                locations.Count,
                Math.Clamp(OverlayRosterPlanner.ResolveCapacity(moduleHeight) - 1, 1, 2));
        return new OverlayOverviewLocationLayoutResult(
            orientation,
            locations.Take(visibleCount).ToArray());
    }
}
