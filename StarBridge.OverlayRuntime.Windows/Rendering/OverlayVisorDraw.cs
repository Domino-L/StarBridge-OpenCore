using Vortice.DirectWrite;
using Vortice.Mathematics;

namespace StarBridge.Desktop;

/// <summary>
/// Draws one visor group in its own box, 0..Width wide (design units, scaled by the renderer).
/// A group on the right edge mirrors: name and ship hug the screen edge, the place faces the middle.
/// </summary>
internal sealed class OverlayVisorDraw(OverlayVisorPainter p, OverlayVisorStyle st, bool right, double now, float width = OverlayVisorDraw.Width)
{
    public const float Width = 480, TopWidth = 1100;
    private static float Ease(double x) => 1 - MathF.Pow(1 - (float)Math.Clamp(x, 0, 1), 3);

    private float At(float dx, float w) => right ? width - dx - w : dx;

    private float Seq(float dx, float y, params OverlayVisorRun[] runs)
    {
        var total = runs.Sum(p.Width);
        var x = At(dx, total);
        foreach (var run in runs) { p.Draw(run, x, y); x += p.Width(run); }
        return total;
    }

    private void Rule(float y, float w = -1)
    {
        w = w < 0 ? width : w;
        var on = new Color4(st.Deco.R, st.Deco.G, st.Deco.B, 0.85f); var off = new Color4(st.Deco.R, st.Deco.G, st.Deco.B, 0);
        if (right) p.Gradient(width - w, y, w, 1.2f, off, on); else p.Gradient(0, y, w, 1.2f, on, off);
    }

    private float Label(string text, float y) { Seq(0, y, new OverlayVisorRun(text, false, FontWeight.Medium, 13, st.Dim)); return y + 22; }

    /// <summary>The chat drawn without any plate or outline (the "聊天底框" setting off); the text keeps its thin dark edge.</summary>
    public bool Bare { get; init; }

    /// <summary>
    /// The outline (user, 11-07: "参考游戏", no grid or ticks): a 1 px bright line with rounded corners on the screen-edge
    /// half only: the outer side and the top edge, which fades out toward the centre; the bottom only turns the corner.
    /// Open toward the centre, where the group dissolves.
    /// </summary>
    public void Ticks(float h)
    {
        if (Bare) return;
        float x = -16, y = -14, w = width + 32; h += 28;
        var lit = new Color4(st.Deco.R * 0.4f + 0.6f, st.Deco.G * 0.4f + 0.6f, st.Deco.B * 0.4f + 0.6f, 1);
        const float r = 8, alpha = 0.85f;
        var ox = right ? x + w : x;
        var inward = right ? -1f : 1f;
        p.Line(ox, y + r, ox, y + h - r, lit, alpha, 1f);
        void Corner(float cy, float sy, float tail)
        {
            // a quarter circle from the outer side into the horizontal edge, then the edge fading toward the centre
            var cx = ox + inward * r; var cyy = cy + sy * r;
            var prev = new System.Numerics.Vector2(ox, cyy);
            for (var i = 1; i <= 6; i++)
            {
                var a = MathF.PI / 2 * i / 6;
                var next = new System.Numerics.Vector2(cx - inward * r * MathF.Cos(a), cyy - sy * r * MathF.Sin(a));
                p.Line(prev.X, prev.Y, next.X, next.Y, lit, alpha, 1f);
                prev = next;
            }
            if (tail <= 0) return;
            var on = new Color4(lit.R, lit.G, lit.B, alpha); var off = new Color4(lit.R, lit.G, lit.B, 0);
            var start = ox + inward * r;
            if (right) p.Gradient(start - tail, cy - 0.5f, tail, 1f, off, on); else p.Gradient(start, cy - 0.5f, tail, 1f, on, off);
        }
        Corner(y, 1, w * 0.72f);
        Corner(y + h, -1, 14);
    }

    // ---------------- team ----------------
    private Color4 Dot(OverlayVisorMember m) => m.State switch
    {
        OverlayVisorMemberState.AppOnly => st.Accent,
        OverlayVisorMemberState.Away => st.Warn,
        OverlayVisorMemberState.Offline or OverlayVisorMemberState.Unknown => st.Dim,
        _ => m.SameServer ? st.Ok : st.Accent,
    };

    /// <summary>
    /// The member columns, from the screen edge inward (user, 11-07: "最重要的就是 这个人他在哪里，开的什么船，之后可能会
    /// 扩展别的吧"). Each column is as wide as its longest entry among the members shown, up to its cap; a longer entry
    /// scrolls inside the column. A later column (status, role) is added here with its own cap and runs.
    /// Caps (design units; ×0.707 = pixels at 1440p medium), user "小而精": fit 80-90% of everyday entries, measured with
    /// --visor-text-widths at the row sizes (ship and place 12 px, names 13 px): the name and ship column 180 (80% of
    /// the ship names in ship-names-zh.txt, every typical handle), the place column 158 (85% of location-names-zh.txt).
    /// </summary>
    internal static readonly (string Key, float Cap)[] MemberColumns = [("lead", 180), ("place", 158)];

    /// <summary>The current column widths (design units, one per <see cref="MemberColumns"/>), set by the renderer.</summary>
    public float[] Columns { get; init; } = [.. MemberColumns.Select(c => c.Cap)];
    /// <summary>The columns are narrowing: a field wider than its column is clipped for that moment instead of scrolling.</summary>
    public bool Narrowing { get; init; }
    /// <summary>A fixed members height (height not adaptive); 0 follows the content.</summary>
    public float FixedHeight { get; init; }

    /// <summary>
    /// The members header (the title line with "you are at", the counts and the rule), the page line under the rows, and
    /// the gap before the first member after the pinned ones.
    /// </summary>
    internal const float TeamHeader = 20 + 24 + 7, PageLine = 20, PinnedGap = 3;

    /// <summary>How many member rows a members height holds at the tightest row spacing, with the header, the page line
    /// and the pinned gap (at least one).</summary>
    internal static int RowsFor(float height) =>
        // Preserve the old dense-spacing capacity throughout the old height range.
        Math.Clamp((int)MathF.Floor((height - TeamHeader - PageLine - PinnedGap) / DenseRowHeight), 1, height <= 554 ? 12 : MaxRows);

    /// <summary>The roster's own page limit; the tallest members height is sized for it.</summary>
    internal const int MaxRows = 20;

    internal const float RowInset = 16, ColumnGap = 10, RowHeight = 40, ShipLine = 19;

    /// <summary>Where a member's health ring sits (design units, the group's own drawing space); the renderer draws it live.</summary>
    public readonly record struct RingSpot(string Key, float X, float Y, OverlayVisorMember Member);
    public List<RingSpot> Rings { get; } = [];

    /// <summary>
    /// The status mark, and under it the health ring (user, 11-10: "在线状态方块下面放圆环（按百分比改变颜色与圆环完整度，
    /// 从上方顶点顺时针扣血）", style 1 of four tried). The ring moves (a flash on a loss, breathing when low, a slow blink
    /// when downed, growing back), so the layered renderer draws it on its own live layer: here only its place is noted.
    /// Drawn in place only outside the layered renderer.
    /// </summary>
    private void StatusAndHealth(OverlayVisorMember m, float y)
    {
        var hollow = m.State is OverlayVisorMemberState.AppOnly or OverlayVisorMemberState.Offline or OverlayVisorMemberState.Unknown;
        var x = right ? width - 5 : 5;
        p.Diamond(x, y + 10, 6, Dot(m), hollow);
        if (p.Pass == OverlayVisorPass.Shapes) Rings.Add(new(m.Name, x, y + ShipLine + 8, m));
        else if (p.Pass == OverlayVisorPass.All) HealthRing(p, st, x, y + ShipLine + 8, HealthLook.Settled(m));
    }

    internal const float HealthRingRadius = 4.2f;

    /// <summary>One moment of a health ring: what it shows, how bright, the loss flash.</summary>
    internal readonly record struct HealthLook(OverlayVisorVitals Vitals, float Fraction, float Alpha, float Flash, float Glow = 0)
    {
        public static HealthLook Settled(OverlayVisorMember m) =>
            new(m.Vitals, m.Vitals == OverlayVisorVitals.Alive ? Math.Clamp(m.Health, 0, 1) : 0, 1, 0);
    }

    /// <summary>Light cyan-white above half; amber to a quarter; red below (user, 11-10: "1B，只要掉血就应该被注意").</summary>
    internal static Color4 HealthColor(OverlayVisorStyle st, float fraction) =>
        fraction > 0.5f ? HealthHigh : fraction >= 0.25f ? st.Warn : st.Bad;

    internal static readonly Color4 HealthHigh = new(0.80f, 0.95f, 1f, 1);

    /// <summary>
    /// The ring itself: a faint full track; over it what is left, lost clockwise from twelve o'clock and growing back the
    /// other way ("血量应该顺时针从0点开始扣"). Low (below a quarter) is a still red arc over a clearer red track ("低血量不闪").
    /// Downed: a whole red ring with a medical cross in it, both blinking slowly through Alpha, the cross a little brighter
    /// ("如果放十字呢"; "而且用红色吧"); dead: an X in the faint ring ("阵亡要X"); nothing known: the faint track only.
    /// Revived: once grown full the ring glows softly (Glow), gentler than a loss's flash. No numbers.
    /// </summary>
    internal static void HealthRing(OverlayVisorPainter p, OverlayVisorStyle st, float x, float y, HealthLook look)
    {
        const float r = HealthRingRadius, w = 1.5f;
        switch (look.Vitals)
        {
            case OverlayVisorVitals.Alive:
                var color = HealthColor(st, look.Fraction);
                // below a quarter the whole faint ring breathes in red too, so a short arc is still seen
                // below a quarter the faint ring is clearer red too, so a short arc is still seen; it does not blink
                var low = look.Fraction < 0.25f;
                p.Ring(x, y, r, look.Fraction, color, low ? w + 0.3f : w, low ? 0.5f : 0.22f, look.Alpha);
                if (look.Glow > 0.01f) p.Ring(x, y, r, 1, color, w + 3.5f, 0, 0.3f * look.Glow);
                if (look.Flash > 0.01f)
                {
                    // the loss flash: the whole ring lights up once, briefly, and lets go
                    p.Ring(x, y, r, 1, new Color4(1, 1, 1, 1), w + 1.2f * look.Flash, 0, 0.55f * look.Flash);
                    p.Ring(x, y, r, 1, color, w + 3.5f, 0, 0.18f * look.Flash);
                }
                break;
            case OverlayVisorVitals.Downed:
                // no track under the whole ring, and the ring at most 0.8, so the cross stays the brighter one through the
                // whole blink, at its peak as at its low (reviews R4, R5)
                p.Ring(x, y, r, 1, st.Bad, w, 0, 0.8f * look.Alpha);
                // the medical cross, the X's line width, a little brighter than the ring
                const float d = 2.4f;
                var cross = MathF.Min(1, look.Alpha * 1.15f);
                p.Line(x - d, y, x + d, y, st.Bad, cross, 1.4f);
                p.Line(x, y - d, x, y + d, st.Bad, cross, 1.4f);
                break;
            case OverlayVisorVitals.Dead:
                p.Ring(x, y, r, 0, st.Dim, w, 0.22f);
                const float c = 2.6f;
                p.Line(x - c, y - c, x + c, y + c, st.Bad, 0.9f, 1.4f);
                p.Line(x - c, y + c, x + c, y - c, st.Bad, 0.9f, 1.4f);
                break;
            default:
                // no health known (reading off or stopped, or a member: their health is not shared): no ring at all
                // (user, 11-10: "如果一个人没有开读血，就不画那个人的圆环，在别人视角看也是")
                break;
        }
    }

    /// <summary>
    /// Row spacing in a fixed-height members box (user, 11-10: "信息较少而空间较大可以宽松一些，如果信息较多可以稍微密一点"):
    /// the free room shared by the rows on the page, between these two; the text keeps its size.
    /// </summary>
    internal const float DenseRowHeight = 35, LooseRowHeight = 60;

    /// <summary>The row spacing for <paramref name="rows"/> rows in a members box of <paramref name="height"/> (0: not fixed).</summary>
    internal static float RowPitch(float height, int rows, bool paged, bool pinnedGap) =>
        height <= 0 || rows <= 0 ? RowHeight
            : Math.Clamp((height - TeamHeader - (paged ? PageLine : 0) - (pinnedGap ? PinnedGap : 0)) / rows, DenseRowHeight, LooseRowHeight);

    private (OverlayVisorRun Name, OverlayVisorRun Ship, OverlayVisorRun Place) RowRuns(OverlayVisorMember m)
    {
        var inGame = m.State == OverlayVisorMemberState.InGame;
        var quiet = new Color4(st.Ink.R, st.Ink.G, st.Ink.B, 0.78f);
        var name = new OverlayVisorRun((m.Pinned ? "★ " : "") + m.Name, true, FontWeight.SemiBold, 16, m.State == OverlayVisorMemberState.Offline ? st.Dim : st.Ink);
        // outside the game the ship line carries the one tag that says why (应用在线, 离开, 离线, 未知); an unknown member
        // looks offline but keeps its name at full strength (11-14 user, "甲 按推荐")
        // body text 15 design units = 12 px at 1440p medium (OverlayVisorPainter.DrawnSize), the name 16 = 13 px
        var ship = new OverlayVisorRun(inGame ? (m.Ship.Length > 0 ? m.Ship : "—") : m.Status, false, FontWeight.Medium, 15,
            inGame ? quiet : m.State == OverlayVisorMemberState.Away ? st.Warn : st.Accent);
        var place = new OverlayVisorRun(m.Place.Length > 0 ? m.Place : "—", false, FontWeight.Medium, 15, m.SameServer ? st.Ok : quiet);
        return (name, ship, place);
    }

    /// <summary>How wide each member column would need to be for its longest entry (before the caps).</summary>
    public float[] NaturalColumns(IReadOnlyList<OverlayVisorMember> members)
    {
        float lead = 0, place = 0;
        foreach (var m in members)
        {
            var (n, s, pl) = RowRuns(m);
            lead = MathF.Max(lead, MathF.Max(p.Width(n), p.Width(s)));
            place = MathF.Max(place, p.Width(pl));
        }
        return [lead, place];
    }

    /// <summary>The narrowest the members group can be: its title, counts and "you are at" line.</summary>
    public float HeaderWidth(OverlayVisorScene s) => MathF.Max(
        p.Width(TitleRun(s.TeamHeading)) + (s.YouAt.Length > 0 ? TitleGap + YouAt(s).Sum(p.Width) : 0),
        Counts(s).Sum(p.Width));

    private const float TitleGap = 14;

    /// <summary>The members group's width for these columns: the dot inset, the columns and the gaps between them.</summary>
    public static float TeamWidth(float[] columns) => RowInset + columns.Sum() + ColumnGap * (columns.Length - 1);

    /// <summary>A text field too long for its fixed width; the renderer scrolls it inside that width.</summary>
    public readonly record struct ScrollField(int Row, int Order, float X, float Y, float W, OverlayVisorRun Run, float TextW);
    public List<ScrollField> Scrolls { get; } = [];
    private int _row;

    /// <summary>A fixed-width field: drawn in place when it fits (hugging the screen edge), otherwise left to scroll.</summary>
    private void Field(int order, float dx, float y, float w, OverlayVisorRun run, bool? alignLeft = null, bool cut = false)
    {
        var tw = p.Width(run);
        var x = At(dx, w);
        if (tw <= w + 0.5f) { p.Draw(run, (alignLeft ?? !right) ? x : x + w - tw, y); return; }
        if (Narrowing || cut)
        {
            // while the columns ease narrower, or a line fades in or out: cut at the field instead of scrolling
            p.Dc.PushAxisAlignedClip(new Rect(x, y - 4, w, OverlayVisorPainter.DrawnSize(run.Size) * 1.7f + 8), Vortice.Direct2D1.AntialiasMode.Aliased);
            p.Draw(run with { Gap = 0 }, x, y);
            p.Dc.PopAxisAlignedClip();
            return;
        }
        Scrolls.Add(new(_row, order, x, y, w, run with { Gap = 0 }, tw));
    }

    /// <summary>
    /// K1 (user, 11-07: "还是用老版吧"): the name (13 px, bright) over the ship (12 px, quieter) at the screen edge, the
    /// place in a column toward the screen centre. Every row uses the same column widths, so the columns line up.
    /// </summary>
    private float Row(OverlayVisorMember m, float y, float pitch = RowHeight)
    {
        float lead = Columns[0], placeW = Columns[1];
        var top = y;
        // the row's text sits in the middle of its spacing
        y += (pitch - RowHeight) / 2;
        StatusAndHealth(m, y);
        var (name, ship, place) = RowRuns(m);
        Field(0, RowInset, y, lead, name);
        Field(1, RowInset, y + ShipLine, lead, ship);
        Field(2, RowInset + lead + ColumnGap, y + 1, placeW, place, alignLeft: right);
        _row++;
        return top + pitch;
    }

    private OverlayVisorRun TitleRun(string title) => new(title, false, FontWeight.Medium, 13, st.Dim);

    /// <summary>
    /// The counts on one compact line: "8 在线  7 游戏中  5 同服"; when no member's state is known (the read went stale),
    /// "实时状态未知" instead, as the classic overview (11-14).
    /// </summary>
    private OverlayVisorRun[] Counts(OverlayVisorScene s) => s.RealtimeUnknown.Length > 0
        ? [new(s.RealtimeUnknown, false, FontWeight.Medium, 13, st.Dim)]
        : [
        new(s.Online.ToString(), true, FontWeight.SemiBold, 16, st.Ink), new(s.CountLabels[0], false, FontWeight.Medium, 12, st.Dim, 1, 4),
        new(s.InGame.ToString(), true, FontWeight.SemiBold, 16, st.Accent, 0, 12), new(s.CountLabels[1], false, FontWeight.Medium, 12, st.Dim, 1, 4),
        new(s.SameServer.ToString(), true, FontWeight.SemiBold, 16, st.Ok, 0, 12), new(s.CountLabels[2], false, FontWeight.Medium, 12, st.Dim, 1, 4),
    ];

    /// <summary>"你在 美服 #001" as a short mark at the far end of the title line (user, 11-07: "youat可以").</summary>
    private OverlayVisorRun[] YouAt(OverlayVisorScene s) =>
        [new("◆", false, FontWeight.Medium, 11, st.Deco, 2), new(s.YouAt, false, FontWeight.Medium, 13, st.Ink, 0, 4)];

    public float Team(OverlayVisorScene s)
    {
        // the header stays inside the members width (review R3): a long title or place scrolls in place, the counts are cut
        _row = -1;
        // the title at the screen edge; "you are at" at the other end of the same line, at most half the width
        var title = TitleRun(s.TeamTitle);
        // the source name scrolls when too long, the count after it stays whole (11-13 user, B: "过长时使用其他文字同样的滚动"):
        // the count's width is kept first, "you are at" at most half the width and never over the count, the name what is
        // left (review R3)
        var count = TitleRun(s.TeamCount.Length > 0 ? " · " + s.TeamCount : "");
        var countW = s.TeamCount.Length > 0 ? p.Width(count) : 0;
        var mark = s.YouAt.Length > 0 ? YouAt(s) : [];
        var markW = MathF.Min(mark.Sum(p.Width), MathF.Min(width / 2, MathF.Max(0, width - countW - TitleGap - 1)));
        var titleW = mark.Length > 0 ? MathF.Max(1, width - markW - TitleGap) : width;
        var nameW = MathF.Min(p.Width(title), MathF.Max(1, titleW - countW));
        Field(10, right ? countW : 0, 0, nameW, title);
        if (countW > 0) p.Draw(count, right ? width - countW : nameW, 0);
        if (mark.Length > 0)
        {
            var diamond = mark[0];
            var dw = p.Width(diamond);
            // on the right edge the mark reads from the centre side; on the left it ends at the centre side
            var markX = right ? 0 : width - markW;
            p.Draw(diamond, markX, 0);
            Field(11, right ? width - dw - (markW - dw) : markX + dw, 0, MathF.Max(1, markW - dw), mark[1] with { Gap = 0 }, alignLeft: true);
        }
        var y = 20f;
        p.Dc.PushAxisAlignedClip(new Rect(0, y - 4, width, 32), Vortice.Direct2D1.AntialiasMode.Aliased);
        Seq(0, y, Counts(s));
        p.Dc.PopAxisAlignedClip();
        y += 24;
        Rule(y); y += 7;
        _row = 0;
        var pinnedDone = false;
        var rowsTop = y;
        var pitch = RowPitch(FixedHeight, s.Members.Count, s.PageLabel.Length > 0,
            s.Members.Any(x => x.Pinned) && s.Members.Any(x => !x.Pinned));
        foreach (var m in s.Members)
        {
            if (!m.Pinned && !pinnedDone && s.Members.Any(x => x.Pinned)) { y += PinnedGap; pinnedDone = true; Rule(y - 2, width * 0.6f); }
            y = Row(m, y, pitch);
        }
        if (s.Members.Count > 0)
        {
            // a very faint divider between the name and ship column and the place column, so they read as columns
            var dx = RowInset + Columns[0] + ColumnGap / 2;
            var lx = right ? width - dx : dx;
            p.Line(lx, rowsTop - 2, lx, y - 6, st.Deco, 0.22f, 1f);
        }
        if (s.PageLabel.Length > 0) { Seq(0, y + 1, new OverlayVisorRun(s.PageLabel, false, FontWeight.Normal, 12, st.Dim)); y += PageLine; }
        // a fixed height keeps the outline at that height whatever the number of rows
        if (FixedHeight > 0) y = MathF.Max(y, FixedHeight);
        Ticks(y);
        return y;
    }

    /// <summary>
    /// The events and chat groups' heights for their most lines (the user's line counts), which the layout places them
    /// by (review R4, 11-07 "2放"): the members below stay put however many lines show, and the editor shows the same.
    /// </summary>
    internal static float EventsBoxHeight(int lines) => 22 + lines * EventLine;
    internal static float ChatBoxHeight(int lines) => 22 + lines * ChatLine;
    private const float EventLine = 70, ChatLine = 28, EventTimeGap = 10, ChatWhoGap = 10;

    /// <summary>How wide the events group would need to be for its widest line (before the width setting).</summary>
    public float EventsNaturalWidth(OverlayVisorScene s) => s.Events.Select(e => MathF.Max(
        p.Width(EventTitle(e)) + EventTimeGap + p.Width(EventTime(e)), p.Width(EventDetail(e))))
        .Append(p.Width(new OverlayVisorRun(s.EventsTitle, false, FontWeight.Medium, 13, st.Dim))).Max();

    /// <summary>How wide the chat group would need to be for its widest line (before the width setting).</summary>
    public float ChatNaturalWidth(OverlayVisorScene s) => s.Chat.Select(c => p.Width(ChatWho(c)) + ChatWhoGap + p.Width(ChatText(c)))
        .Append(p.Width(new OverlayVisorRun(s.ChatTitle, false, FontWeight.Medium, 13, st.Dim))).Max();

    // the title in its kind's status colour (11-12); the chat names stay the fixed cyan
    private OverlayVisorRun EventTitle(OverlayVisorEvent e) => new(e.Title, false, FontWeight.SemiBold, 16, st.Tone(e.Tone));
    private OverlayVisorRun EventTime(OverlayVisorEvent e) => new(e.Time, true, FontWeight.Medium, 13, st.Dim);
    private OverlayVisorRun EventDetail(OverlayVisorEvent e) => new(e.Detail, false, FontWeight.Medium, 15, st.Ink);
    private OverlayVisorRun ChatWho(OverlayVisorChatLine c) => new(c.Who, true, FontWeight.SemiBold, 16, st.Accent);
    private OverlayVisorRun ChatText(OverlayVisorChatLine c) => new(c.Text, false, FontWeight.Medium, 15, st.Ink);

    // ---------------- events ----------------
    public float Events(OverlayVisorScene s)
    {
        var y = Label(s.EventsTitle, 0);
        var rule = MathF.Min(300, width);
        _row = 0;
        foreach (var e in s.Events)
        {
            var bar = right ? width + 8 : -10.5f;
            var title = EventTitle(e);
            var tw = p.Width(title);
            // the title line stays inside the width (its own clip, not the bar or the rule); a long detail scrolls in
            // place once the event has settled
            var titleLine = new Rect(0, y - 6, width, 30);
            var (open, room, line) = EventOpening(e);
            p.Alpha = e.Opacity;
            var moving = open < 1 || room < 1;
            // while the row is still taking its room it shows only that much, so it never covers the row below
            var tall = EventLine * room;
            if (open > 0)
            {
                // the part opened so far, measured from the screen edge (the bar's side) inward
                var edge = right ? width + 12 : -14f;
                var span = (width + 26) * open;
                var reveal = right ? new Rect(edge - span, y - 8, span, tall) : new Rect(edge, y - 8, span, tall);
                if (moving) p.Dc.PushAxisAlignedClip(reveal, Vortice.Direct2D1.AntialiasMode.Aliased);
                p.Dc.PushAxisAlignedClip(titleLine, Vortice.Direct2D1.AntialiasMode.Aliased);
                Seq(0, y, title);
                Seq(tw + EventTimeGap, y + 3, EventTime(e));
                p.Dc.PopAxisAlignedClip();
                Field(1, 0, y + 24, width, EventDetail(e), cut: moving || e.Opacity < 0.999f);
                p.Fill(bar, y + 2, 2.5f, 46, st.Deco, 0.3f);
                Rule(y + 54, rule);
                if (moving) p.Dc.PopAxisAlignedClip();
            }
            if (line > 0.01f)
            {
                // the bright line at the inner end of the opening, with a faint afterglow on the opened side
                var x = right ? width + 12 - (width + 26) * open : -14 + (width + 26) * open;
                var toEdge = right ? 1 : -1;
                for (var i = 0; i < 6; i++)
                    p.Fill(x + toEdge * i * 5 - (toEdge < 0 ? 5 : 0), y - 4, 5, MathF.Max(0, tall - 8), st.Deco, line * 0.16f * (1 - i / 6f));
                p.Fill(x - 7, y - 6, 14, MathF.Max(0, tall - 4), st.Deco, line * 0.18f);
                p.Fill(x - 1, y - 8, 2, tall, new Color4(0.92f, 0.98f, 1, 1), line);
            }
            p.Alpha = 1;
            _row++;
            y += EventLine * room;
        }
        Ticks(y);
        return y;
    }

    /// <summary>
    /// An event opening from the screen edge and closing back to it (build 86, user: "不要标记 从贴边处展开", "只展开，不加
    /// 别的", then "可以"): how much of the row is open from the edge (0..1), how much room it takes (it grows at the
    /// start and closes up after leaving, so the rows next to it slide instead of jumping), and how bright the line is.
    /// </summary>
    /// <summary>The least leaving progress: a leaving event on its first frame (progress 0) is already leaving.</summary>
    internal const float LeavingStarted = 1e-4f;

    internal static (float Open, float Room, float Line) EventOpening(OverlayVisorEvent e)
    {
        if (e.Leave > 0)
        {
            // the line goes back to the edge from where the event had opened to, then goes out while the row closes up
            var from = Math.Clamp(e.LeaveFrom, 0, 1);
            var fromOpen = from >= 1 ? 1 : Ease(from);
            var fromRoom = from >= 1 ? 1 : Ease(from / 0.4);
            var back = Ease(e.Leave / 0.75);
            var after = (float)Math.Clamp((e.Leave - 0.75) / 0.25, 0, 1);
            return (fromOpen * (1 - back), fromRoom * (1 - Ease(after)), 1 - after);
        }
        if (e.Reveal >= 1) return (1, 1, 0);
        var open = Ease(e.Reveal);
        // the line is at full strength while it moves and fades once the row is open
        return (open, Ease(e.Reveal / 0.4), e.Reveal < 0.9 ? 1 : (float)(1 - (e.Reveal - 0.9) / 0.1));
    }

    // ---------------- chat ----------------
    public float Chat(OverlayVisorScene s)
    {
        var y = Label(s.ChatTitle, 0);
        _row = 0;
        foreach (var c in s.Chat)
        {
            p.Alpha = c.Opacity;
            // the name, then the message in the rest of the width; a long message scrolls there (it used to run past the
            // group's edge)
            var who = ChatWho(c);
            var ww = MathF.Min(p.Width(who), width / 2);
            Field(0, 0, y, ww, who, cut: true);
            Field(1, ww + ChatWhoGap, y, MathF.Max(1, width - ww - ChatWhoGap), ChatText(c), alignLeft: !right, cut: c.Opacity < 0.999f);
            _row++;
            y += ChatLine;
        }
        p.Alpha = 1;
        Ticks(y);
        return y;
    }

    // ---------------- top: rally or fleet notice ----------------
    public float Top(OverlayVisorScene s, double noticeAge)
    {
        const float cx = TopWidth / 2, ry = 60;
        var color = s.NoticeIsRally ? st.Warn : st.Accent;
        p.Alpha = Ease(noticeAge / 0.35);
        var pulse = MathF.Max(0, 1 - (float)noticeAge / 0.8f);
        if (pulse > 0) p.Stroke(cx - 300 - pulse * 30, ry - 8 - pulse * 8, 600 + pulse * 60, 120 + pulse * 16, color, pulse * 0.6f, 1.5f);
        var head = s.NoticeTimer.Length > 0 ? $"{s.NoticeTitle}  ·  {s.NoticeTimer}" : s.NoticeTitle;
        Center(head, cx, ry, false, FontWeight.SemiBold, 14, color);
        Center(TopBody(s.NoticeBody), cx, ry + 22, false, FontWeight.SemiBold, s.NoticeIsRally ? 30 : 24, st.Warm);
        if (s.NoticeHint.Length > 0) Center(s.NoticeHint, cx, ry + 74, false, FontWeight.Medium, 14, st.Dim);
        var bw = 560f; var bx = cx - bw / 2; var by = ry + 104;
        p.Gradient(bx, by + 0.5f, bw, 1.4f, new Color4(color.R, color.G, color.B, 0), new Color4(color.R, color.G, color.B, 0.5f));
        if (noticeAge < 2.4) { var hx = bx + bw * Ease(noticeAge / 1.6); p.Gradient(hx - 70, by - 1, 72, 4.5f, new Color4(1, 0.95f, 0.85f, 0), new Color4(1, 0.97f, 0.9f, 1)); }
        p.Alpha = 1;
        return 180;
    }

    public static bool TopAnimating(double noticeAge) => noticeAge is >= 0 and < 2.4;

    /// <summary>
    /// The top line's body as drawn. A rally's body comes already quoted for its language
    /// (NativeInformationOverlayRuntime.RallySlotFor: 「…」 or “…”), and its hidden-details and
    /// sample texts are messages, not quotes: nothing is added here. Before m102 a rally was
    /// wrapped in 「」 again here and showed "「「集合」」" (found 11-18).
    /// </summary>
    internal static string TopBody(string body) => body;

    // ---------------- the DM badge ----------------
    public float DirectMessage(string text)
    {
        var purple = OverlayVisorStyle.Rgb(195, 155, 255); var lilac = OverlayVisorStyle.Rgb(226, 207, 255);
        var label = "✉ " + text;
        var w = p.Measure(label, false, FontWeight.Medium, 15) + 22;
        var x = right ? width - w : 0;
        p.Fill(x, 0, w, 30, new Color4(0.04f, 0.03f, 0.08f, 0.6f));
        p.Stroke(x + 0.5f, 0.5f, w - 1, 29, purple, 1, 1);
        p.Text(label, x + 11, 4, false, FontWeight.Medium, 15, lilac);
        return 30;
    }

    private void Center(string text, float cx, float y, bool numeric, FontWeight weight, float size, Color4 color) =>
        p.Text(text, cx - p.Measure(text, numeric, weight, size) / 2, y, numeric, weight, size, color);
}
