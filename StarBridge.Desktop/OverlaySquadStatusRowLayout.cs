namespace StarBridge.Desktop;

internal readonly record struct OverlaySquadStatusColumn(float Left, float Width)
{
    public float Right => Left + Width;
}

/// <summary>
/// Allocates the three squad-status fields without allowing their draw boxes
/// to overlap. The renderer supplies measured text widths; this module owns
/// compact-format selection and column compression.
/// </summary>
internal readonly record struct OverlaySquadStatusRowLayout(
    OverlaySquadStatusColumn Primary,
    OverlaySquadStatusColumn Summary,
    OverlaySquadStatusColumn Server,
    bool UseCompactMetricFormat)
{
    public const float CompactThreshold = 280;

    public static OverlaySquadStatusRowLayout Resolve(
        float contentWidth,
        float primaryTextWidth,
        float summaryTextWidth,
        float serverTextWidth)
    {
        var width = Math.Max(1, contentWidth);
        var compact = width < CompactThreshold;
        var gap = compact ? 4f : 8f;
        var available = Math.Max(1, width - gap * 2);
        var desired = new[]
        {
            Math.Max(1, primaryTextWidth + 2),
            Math.Max(1, summaryTextWidth + 2),
            Math.Max(1, serverTextWidth + 2)
        };
        var desiredTotal = desired.Sum();
        if (desiredTotal > available)
        {
            var scale = available / desiredTotal;
            for (var index = 0; index < desired.Length; index++)
            {
                desired[index] = Math.Max(1, desired[index] * scale);
            }
        }

        var primary = new OverlaySquadStatusColumn(0, desired[0]);
        var summary = new OverlaySquadStatusColumn(
            primary.Right + gap,
            desired[1]);
        var server = new OverlaySquadStatusColumn(
            summary.Right + gap,
            Math.Max(1, width - (summary.Right + gap)));
        return new OverlaySquadStatusRowLayout(
            primary,
            summary,
            server,
            compact);
    }
}
