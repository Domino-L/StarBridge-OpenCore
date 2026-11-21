namespace StarBridge.Core.Overlay;

/// <summary>
/// Where a visor group sits. <see cref="Slot"/> is a default slot (the group stacks with the others on
/// that edge); otherwise the group is free: (<see cref="X"/>, <see cref="Y"/>) is the corner the user
/// dragged it to in 1080-high layout units, the right edge when <see cref="Right"/> and the bottom edge
/// when <see cref="Bottom"/>. A right group also reads from the screen edge inwards.
/// </summary>
public readonly record struct OverlayVisorSpot(string? Slot, float X = 0, float Y = 0, bool Right = false, bool Bottom = false)
{
    public static OverlayVisorSpot At(string slot) => new(slot);
    public bool Free => Slot is null;
    public bool RightAligned => Slot is { } slot ? slot == OverlayVisorPlacement.BadgeSlot || OverlayVisorLayout.IsRightAligned(slot) : Right;
    /// <summary>Top-left of a w x h group at this free spot.</summary>
    public (float X, float Y) Corner(float w, float h) => (Right ? X - w : X, Bottom ? Y - h : Y);
}

/// <summary>
/// Reads the visor positions from the layout the overlay already saves; the format is unchanged, so
/// an older client reads the same file. A module still at a position the client once shipped was never
/// moved and takes the visor default. A moved module sits exactly where it was saved (11-06 user: free
/// positions, "可以像现在一样自由调整吗"); the visor editor saves the visor block's own rectangle,
/// anchored to the screen half it is in.
/// </summary>
public static class OverlayVisorPlacement
{
    /// <summary>Old module key behind each visor group. Events keep their own side and height settings;
    /// the rally stays at the top centre (its notice module docks to the screen edge).</summary>
    private static readonly (string Group, string Key)[] Sources =
    [
        (OverlayVisorLayout.Team, "Members"),
        (OverlayVisorLayout.Chat, "Chat"),
    ];

    /// <summary>
    /// Every layout the client has shipped: the current default and the two editor templates.
    /// A module within <see cref="UnmovedTolerance"/> of one of these was never moved.
    /// </summary>
    private static readonly string[] ShippedLayouts =
    [
        InformationOverlayDefaults.DefaultLayoutPayload,
        "Notice,0.34,0,0.32,0.055;Squads,0.01,0.36,0.13,0.24;Members,0.84,0.58,0.15,0.18;Chat,0.35,0.78,0.30,0.18",
        "Notice,0.285,0,0.43,0.075;Squads,0.01,0.30,0.18,0.42;Members,0.78,0.54,0.21,0.26;Chat,0.35,0.75,0.30,0.21",
    ];

    private const float UnmovedTolerance = 0.02f;
    private const double EventUnmovedTolerance = 0.02;
    /// <summary>The events' shipped height (EventNotificationY); right side at this height = never moved.</summary>
    public const double DefaultEventY = 0.34;
    private const float Height = 1080;
    private const float EventPlacementHeight = 90;

    public static Dictionary<string, OverlayVisorSpot> Spots(
        IEnumerable<InformationOverlayLayoutItem>? layout,
        OverlayEventNotificationSide eventSide,
        double eventY,
        float layoutWidth,
        double eventX = OverlayDisplaySettings.UnsetVisorBadge)
    {
        var result = OverlayVisorLayout.DefaultLayout.ToDictionary(kv => kv.Key, kv => OverlayVisorSpot.At(kv.Value));
        var items = (layout ?? [])
            .Where(item => item is not null)
            .GroupBy(item => item.Key, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First(), StringComparer.OrdinalIgnoreCase);
        foreach (var (group, key) in Sources)
        {
            if (!items.TryGetValue(key, out var item) || Unmoved(item, layoutWidth)) continue;
            var rect = InformationOverlayLayoutGeometry.ResolveItemRect(item, layoutWidth, Height);
            float left = (float)rect.Left, top = (float)rect.Top, w = (float)rect.Width, h = (float)rect.Height;
            var right = item.HorizontalAnchor switch
            {
                OverlayHorizontalAnchor.Right => true,
                OverlayHorizontalAnchor.Left => false,
                _ => left + w / 2 > layoutWidth / 2,
            };
            var bottom = item.VerticalAnchor switch
            {
                OverlayVerticalAnchor.Bottom => true,
                OverlayVerticalAnchor.Top => false,
                _ => top + h / 2 > Height / 2,
            };
            result[group] = new(null, right ? left + w : left, bottom ? top + h : top, right, bottom);
        }
        var eventsRight = eventSide != OverlayEventNotificationSide.Left;
        eventX = OverlayDisplaySettings.NormalizeVisorBadge(eventX);
        // a double tolerance, as the editor reads it (overlay_visor_arrange.dart): at the edge (0.36) both agree
        // (review CX-OVERLAY-M102-R1 P2-3; the float 0.02f made 0.36 "moved" here and "never moved" there)
        if (eventX >= 0 || !eventsRight || Math.Abs(eventY - DefaultEventY) > EventUnmovedTolerance)
        {
            // Events keep the old editor's model: a screen side and a height. Same top as the editor's
            // event preview (InformationOverlayLayoutGeometry.ResolveEventNotificationRect, 90 high). Since 11-12
            // ("应该允许事件随意调整位置了") they may also sit anywhere across: their screen-edge side's x as a screen
            // fraction; unset, they hug that edge as before. The side still decides which way they open and lean.
            var y = (float)Math.Clamp(eventY, 0, 1) * (Height - EventPlacementHeight);
            var x = eventX >= 0 ? (float)eventX * layoutWidth
                : eventsRight ? layoutWidth - OverlayVisorLayout.Edge : OverlayVisorLayout.Edge;
            result[OverlayVisorLayout.Events] = new(null, x, y, eventsRight, false);
        }
        return result;
    }

    /// <summary>
    /// The DM badge (11-06 user: "角标自由"). Unset (-1) keeps the default spot above the game's key hints;
    /// otherwise (<paramref name="x"/>, <paramref name="y"/>) are screen fractions of the badge's screen-edge
    /// side (its right edge on the right half, else its left edge) and its top.
    /// </summary>
    public static OverlayVisorSpot Badge(double x, double y, float layoutWidth)
    {
        x = OverlayDisplaySettings.NormalizeVisorBadge(x);
        y = OverlayDisplaySettings.NormalizeVisorBadge(y);
        if (x < 0 || y < 0) return OverlayVisorSpot.At(BadgeSlot);
        return new(null, (float)x * layoutWidth, (float)y * Height, x >= 0.5, false);
    }

    /// <summary>
    /// 11-06 user: "召集应该可以上下换位 但是固定两个预设位置". The rally sits at the top centre or the bottom
    /// centre, read from where the notice module is docked (it only docks to the top or bottom edge), so
    /// nothing new is stored.
    /// </summary>
    public static bool RallyAtBottom(IEnumerable<InformationOverlayLayoutItem>? layout, float layoutWidth)
    {
        var notice = (layout ?? []).FirstOrDefault(item => item is not null && item.Key.Equals("Notice", StringComparison.OrdinalIgnoreCase));
        if (notice is null) return false;
        return notice.VerticalAnchor switch
        {
            OverlayVerticalAnchor.Bottom => true,
            OverlayVerticalAnchor.Top => false,
            _ => InformationOverlayLayoutGeometry.ResolveItemRect(notice, layoutWidth, Height) is var rect && rect.Top + rect.Height / 2 > Height / 2,
        };
    }

    /// <summary>The badge's default spot (OverlayVisorLayout.DirectMessageBadge).</summary>
    public const string BadgeSlot = "dm";

    private static bool Unmoved(InformationOverlayLayoutItem item, float layoutWidth)
    {
        var (cx, cy) = Centre(item, layoutWidth);
        foreach (var payload in ShippedLayouts)
        {
            var shipped = InformationOverlayLayoutItem.ParseMany(payload)
                .FirstOrDefault(candidate => candidate.Key.Equals(item.Key, StringComparison.OrdinalIgnoreCase));
            if (shipped is null) continue;
            var (sx, sy) = Centre(shipped, layoutWidth);
            if (MathF.Abs(sx - cx) <= UnmovedTolerance * layoutWidth && MathF.Abs(sy - cy) <= UnmovedTolerance * Height) return true;
        }
        return false;
    }

    private static (float X, float Y) Centre(InformationOverlayLayoutItem item, float layoutWidth)
    {
        var rect = InformationOverlayLayoutGeometry.ResolveItemRect(item, layoutWidth, Height);
        return ((float)(rect.Left + rect.Width / 2), (float)(rect.Top + rect.Height / 2));
    }
}
