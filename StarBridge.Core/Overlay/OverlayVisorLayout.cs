namespace StarBridge.Core.Overlay;

/// <summary>A rectangle in visor layout units: the screen height is always 1080, the width follows the screen shape.</summary>
public readonly record struct OverlayVisorRect(float X, float Y, float W, float H)
{
    public float Right => X + W;
    public float Bottom => Y + H;
    public bool Contains(float x, float y) => x >= X && x <= Right && y >= Y && y <= Bottom;
    public bool Hits(OverlayVisorRect other) => X < other.Right && other.X < Right && Y < other.Bottom && other.Y < Bottom;
}

/// <summary>
/// Where the visor appearance's groups may sit. Groups snap to a small set of slots placed
/// around the game's own HUD, measured from 2560x1440 screenshots (chat box open) and expressed
/// in units where the screen is 1080 high. The team list only lives on the left or right edge;
/// groups on one edge stack without overlapping, and a group that does not fit moves to a free
/// slot (bottom centre first, never onto the game's chat box side first).
/// </summary>
public static class OverlayVisorLayout
{
    public const string Team = "team", Events = "events", Chat = "chat";
    public static readonly string[] Groups = [Team, Events, Chat];
    /// <summary>Default slots, and where a default group goes when its edge overflows.</summary>
    public static readonly string[] SlotKeys = ["L-top", "L-mid", "L-bottom", "R-top", "R-mid", "R-bottom", "T-left", "T-right", "B-mid"];
    private static readonly string[] Pref = ["B-mid", "T-left", "T-right", "R-top", "R-mid", "R-bottom", "L-top", "L-mid", "L-bottom"];
    public const float Edge = 56, Gap = 18;
    /// <summary>
    /// The least height (layout units) the chat is placed by: the layout editor's chat preview needs it, and the
    /// overlay keeps the same so the two agree (11-07, a chat of one or two lines).
    /// </summary>
    public const float ChatMinHeight = 104;
    /// <summary>The right column stops above the direct-message badge, which sits just above the game's key hints.</summary>
    public const float RightBottom = 790;
    private static readonly Dictionary<char, (float Lo, float Hi)> Limit = new() { ['L'] = (110, 877), ['R'] = (150, RightBottom) };

    public static IReadOnlyDictionary<string, string> DefaultLayout { get; } =
        // 11-06 user: "事件默认最好贴右边" - events sit on the right edge above the members.
        new Dictionary<string, string> { [Team] = "R-mid", [Events] = "R-top", [Chat] = "L-bottom" };

    public static bool IsSideSlot(string slot) => slot.Length > 0 && slot[0] is 'L' or 'R';
    public static bool IsRightAligned(string slot) => slot.Length > 0 && slot[0] == 'R' || slot == "T-right";

    public static IReadOnlyList<string> Allowed(string group) =>
        group == Team ? SlotKeys.Where(IsSideSlot).ToArray() : SlotKeys;

    /// <summary>
    /// The top of the middle slots: where the members' default height (394 design units at medium,
    /// 8 rows) centred on 520 (left) and 490 (right) put it. 0.7.3 m102 (11-18 user: "这个不是往下延长
    /// 吗，不应该会影响事件的"): a group there keeps this top and grows down, so a taller members block
    /// never reaches up into the events above it.
    /// </summary>
    public const float LeftMidTop = 520 - 394 * 0.53f / 2, RightMidTop = 490 - 394 * 0.53f / 2;

    public static (float X, float Y) Place(string slot, float w, float h, float layoutWidth) => slot switch
    {
        "L-top" => (Edge, 132),
        "L-mid" => (Edge, LeftMidTop),
        // centred in the gap between the game's chat box (ends ~650) and the vitals (start ~895)
        "L-bottom" => (Edge, MathF.Min(877 - h, MathF.Max(668, 772 - h / 2))),
        "R-top" => (layoutWidth - Edge - w, 150),
        "R-mid" => (layoutWidth - Edge - w, RightMidTop),
        "R-bottom" => (layoutWidth - Edge - w, RightBottom - h),
        // top: below the rally (under the game's heading tape), clear of the ship panel and the right column
        "T-left" => (MathF.Max(384, layoutWidth / 2 - 470 - w / 2), 250),
        "T-right" => (MathF.Min(layoutWidth / 2 + 470 - w / 2, layoutWidth - Edge - w - 24 - w), 250),
        // bottom centre: just above the game's speed / distance readout
        _ => (layoutWidth / 2 - w / 2, 846 - h),
    };

    /// <summary>The game's own HUD, measured from the user's screenshots.</summary>
    public static IReadOnlyList<(string Name, OverlayVisorRect Area)> GameHud(float layoutWidth)
    {
        var r = layoutWidth - 1920; var c = r / 2;
        return
        [
            ("ship-panel", new(20, 0, 340, 390)),
            ("heading", new(660 + c, 15, 600, 60)),
            ("corner-icon", new(1700 + r, 35, 185, 100)),
            ("game-chat", new(60, 420, 380, 230)),
            ("ladder-left", new(0, 340, 45, 390)),
            ("ladder-right", new(layoutWidth - 45, 320, 45, 420)),
            ("crosshair", new(570 + c, 440, 600, 320)),
            ("speed", new(830 + c, 860, 260, 80)),
            ("vitals", new(35, 895, 260, 150)),
            ("key-hints", new(1660 + r, 845, 225, 200)),
        ];
    }

    /// <summary>Direct-message badge: just above the game's key hints on the right.</summary>
    public static (float X, float Y) DirectMessageBadge(float w, float h, float layoutWidth) => (layoutWidth - Edge - w, 845 - h - 14);

    private static int Order(string slot) => slot.EndsWith("top", StringComparison.Ordinal) ? 0 : slot.EndsWith("mid", StringComparison.Ordinal) ? 1 : 2;

    /// <summary>Places the visible groups. The layout may change when an edge overflows (the effective layout is returned through <paramref name="layout"/>).</summary>
    public static Dictionary<string, (float X, float Y)> Arrange(Dictionary<string, string> layout, IReadOnlyDictionary<string, (float W, float H)> sizes, float layoutWidth, int depth = 0)
    {
        var pos = sizes.ToDictionary(kv => kv.Key, kv => Place(layout[kv.Key], kv.Value.W, kv.Value.H, layoutWidth));
        foreach (var side in new[] { 'L', 'R' })
        {
            var ids = sizes.Keys.Where(id => layout[id][0] == side).OrderBy(id => Order(layout[id])).ToList();
            if (ids.Count == 0) continue;
            var (lo, hi) = Limit[side];
            var total = ids.Sum(id => sizes[id].H) + Gap * (ids.Count - 1);
            if (total > hi - lo && ids.Count > 1 && depth < 3)
            {
                var mover = ids[^1];
                // m102 (11-18 user: "成员不挪，事件让，让不开就重叠"): the members never change sides, and the events above
                // them stay to give way up (to the column top; past that they overlap and the editors warn)
                var stays = mover == Team || mover == Events && ids.Contains(Team);
                var used = layout.Values.ToHashSet();
                var free = Allowed(mover).Where(k => k[0] != side && !used.Contains(k)).OrderBy(k => Array.IndexOf(Pref, k)).ToList();
                if (!stays && free.Count > 0) { layout[mover] = free[0]; return Arrange(layout, sizes, layoutWidth, depth + 1); }
            }
            float y = 0; var tops = new List<(string Id, float Top)>(); string? previous = null;
            foreach (var id in ids)
            {
                // m102: the members are not pushed down by the events above them; those give way up instead
                y = id == Team && previous == Events ? pos[id].Y : MathF.Max(pos[id].Y, y);
                tops.Add((id, y)); y += sizes[id].H + Gap; previous = id;
            }
            var over = MathF.Max(0, y - Gap - hi);
            foreach (var (id, top) in tops) pos[id] = (pos[id].X, MathF.Max(lo, top - over));
        }
        return pos;
    }

    /// <summary>The highest the events go when they give way to the members: the top of their side's column.</summary>
    public static float EventsCeiling(float x, float w, float layoutWidth) =>
        x + w / 2 > layoutWidth / 2 ? Limit['R'].Lo : Limit['L'].Lo;

    /// <summary>The lowest the events go when they give way down: the bottom of the screen.</summary>
    public static float EventsFloor(float h) => 1080 - ScreenMargin - h;

    /// <summary>
    /// Where the events and the members, as Arrange placed them, still overlap (the events gave way up to <see cref="EventsCeiling"/>), or null. The editors warn
    /// about it; the visor draws them as they are (11-18 user: "那就应该在编辑时出现重叠警告，如果无视就允许重叠").
    /// </summary>
    public static OverlayVisorRect? EventsOverlap(IReadOnlyDictionary<string, (float X, float Y)> positions,
        IReadOnlyDictionary<string, (float W, float H)> sizes)
    {
        if (!positions.TryGetValue(Events, out var e) || !positions.TryGetValue(Team, out var t)) return null;
        OverlayVisorRect events = new(e.X, e.Y, sizes[Events].W, sizes[Events].H), team = new(t.X, t.Y, sizes[Team].W, sizes[Team].H);
        if (!events.Hits(team)) return null;
        var left = MathF.Max(events.X, team.X); var top = MathF.Max(events.Y, team.Y);
        return new(left, top, MathF.Min(events.Right, team.Right) - left, MathF.Min(events.Bottom, team.Bottom) - top);
    }

    /// <summary>Distance every group keeps from the screen edge, in layout units.</summary>
    public const float ScreenMargin = 8;
    /// <summary>Who keeps its place when two groups overlap: user-placed before default, then this order.</summary>
    private static readonly string[] Priority = [Team, Events, Chat];

    /// <summary>
    /// Places default-slot groups (stacking as before) and free groups (where the user put them), then
    /// keeps every group on screen and apart: a group that overlaps one placed before it moves up or down
    /// just clear of it, whichever is the smaller move that stays on screen and hits nothing; if neither
    /// fits it stays. <paramref name="spots"/> gets the effective spots (an overflowing edge may move a
    /// default group to another slot).
    /// </summary>
    public static Dictionary<string, (float X, float Y)> Arrange(Dictionary<string, OverlayVisorSpot> spots,
        IReadOnlyDictionary<string, (float W, float H)> sizes, float layoutWidth)
    {
        var slotLayout = sizes.Keys.Where(id => spots[id].Slot is not null).ToDictionary(id => id, id => spots[id].Slot!);
        var pos = slotLayout.Count == 0 ? new Dictionary<string, (float X, float Y)>()
            : Arrange(slotLayout, sizes.Where(kv => slotLayout.ContainsKey(kv.Key)).ToDictionary(kv => kv.Key, kv => kv.Value), layoutWidth);
        foreach (var (id, slot) in slotLayout) spots[id] = OverlayVisorSpot.At(slot);
        foreach (var (id, (w, h)) in sizes)
        {
            var (x, y) = spots[id].Free ? spots[id].Corner(w, h) : pos[id];
            pos[id] = (Math.Clamp(x, ScreenMargin, MathF.Max(ScreenMargin, layoutWidth - ScreenMargin - w)),
                Math.Clamp(y, ScreenMargin, MathF.Max(ScreenMargin, 1080 - ScreenMargin - h)));
        }
        var order = sizes.Keys.OrderBy(id => spots[id].Free ? 0 : 1).ThenBy(id => Array.IndexOf(Priority, id)).ToList();
        // 0.7.3 m102 (11-18 user: "事件如果要向下和成员重叠时，应该自己向上避开 而不是向下挤压成员"): the
        // members keep their place before the events, wherever either was put
        int e = order.IndexOf(Events), t = order.IndexOf(Team);
        if (e >= 0 && t > e)
        {
            order.RemoveAt(t);
            order.Insert(e, Team);
        }
        OverlayVisorRect Box(string id, float y) => new(pos[id].X, y, sizes[id].W, sizes[id].H);
        for (var i = 1; i < order.Count; i++)
        {
            var id = order[i];
            var placed = order.Take(i).ToList();
            var h = sizes[id].H;
            if (id == Events && placed.Contains(Team) &&
                new OverlayVisorRect(pos[id].X, pos[id].Y - Gap, sizes[id].W, h + 2 * Gap).Hits(Box(Team, pos[Team].Y)))
            {
                // events on (or within a gap of) the members give way, the members never: from above they go up
                // to a gap above them, no higher than the top of their side's column (clear of the game's corner
                // icons); placed lower down they go a gap below them, no lower than the screen allows. Past that
                // the two overlap (11-18 user: "如果无视就允许重叠"; the editors warn, EventsOverlap). A spot that
                // hits another group is left to the usual rule below.
                // they only ever move away from the members: a ceiling or floor never pushes them closer (review
                // CX-OVERLAY-M102-R1 P2-1)
                var teamH = sizes[Team].H;
                var to = pos[id].Y + h / 2 <= pos[Team].Y + teamH / 2
                    ? MathF.Min(pos[id].Y, MathF.Max(EventsCeiling(pos[id].X, sizes[id].W, layoutWidth), pos[Team].Y - Gap - h))
                    : MathF.Max(pos[id].Y, MathF.Min(EventsFloor(h), pos[Team].Y + teamH + Gap));
                if (!placed.Any(other => other != Team && Box(id, to).Hits(Box(other, pos[other].Y))))
                {
                    pos[id] = (pos[id].X, to);
                    continue;
                }
            }
            if (!placed.Any(other => Box(id, pos[id].Y).Hits(Box(other, pos[other].Y)))) continue;
            var options = placed.SelectMany(other => new[] { pos[other].Y - Gap - h, pos[other].Y + sizes[other].H + Gap })
                .Where(y => y >= ScreenMargin && y + h <= 1080 - ScreenMargin)
                .Where(y => !placed.Any(other => Box(id, y).Hits(Box(other, pos[other].Y))))
                .OrderBy(y => MathF.Abs(y - pos[id].Y)).ToList();
            if (options.Count > 0) pos[id] = (pos[id].X, options[0]);
        }
        return pos;
    }
}
