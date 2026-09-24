namespace StarBridge.Desktop;

// Presentation-only geometry, shared by the standard and fused event renderers.
// Uses each row's existing clock; no second timer or retained identity cache.
internal static class OverlayEventStackLayout
{
    internal readonly record struct Row(float Height, float Progress = 1, bool Entering = false, bool Exiting = false);
    internal readonly record struct Slot(float Top, float Height, float Visibility, float OffsetY, float SeparatorOpacity);
    internal sealed record Layout(Slot[] Slots, float Height);

    internal static Layout Arrange(IReadOnlyList<Row> rows, float gap)
    {
        var slots = new Slot[rows.Count];
        var top = 0f;
        var precedingVisibility = 0f;
        for (var index = 0; index < rows.Count; index++)
        {
            var row = rows[index];
            var progress = Math.Clamp(row.Progress, 0, 1);
            var eased = progress * progress * (3 - 2 * progress);
            // Preserve the skin's existing single-event entrance/exit choreography.
            var visibility = rows.Count == 1 ? 1 : row.Exiting ? 1 - eased : row.Entering ? eased : 1;
            var separator = precedingVisibility * visibility;
            top += gap * separator;
            var offset = rows.Count == 1 ? 0 : row.Exiting ? -8 * eased : row.Entering ? 12 * (1 - eased) : 0;
            var height = row.Height * visibility;
            slots[index] = new(top, height, visibility, offset, separator);
            top += height;
            precedingVisibility = 1 - (1 - precedingVisibility) * (1 - visibility);
        }
        return new(slots, top);
    }
}
