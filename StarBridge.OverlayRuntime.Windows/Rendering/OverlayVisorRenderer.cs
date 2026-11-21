using System.Numerics;
using StarBridge.Core.Overlay;
using Vortice.Direct2D1;
using Vortice.Direct2D1.Effects;
using Vortice.DirectWrite;
using Vortice.DXGI;
using Vortice.Mathematics;

namespace StarBridge.Desktop;

/// <summary>
/// The visor appearance renderer (Direct2D effects on the GPU). Each group is drawn into its own bitmaps only
/// when its content changes; bloom, shadow, feathered haze, perspective tilt and fade are a retained effect
/// chain per group; a frame with no change composes nothing new.
/// </summary>
/// <remarks>
/// 11-07 (user chose method E for sharpness): every group is drawn at twice the pixel size and scaled back when
/// it is composed; the frame (lines, boxes, marks) and the text go to separate layers, so the glow and haze sit
/// only on the frame and the text gets just a thin shadow; both layers turn with the same perspective; groups
/// land on whole pixels.
/// One space (user, 11-07): a single camera sits in front of the screen centre at the viewing distance; each screen
/// side is one plane hinged at the screen edge and folded toward the centre by the 立体程度 angle. Every side group
/// is a rectangle on its plane, so its shape follows from where it sits. The rally at the top and the DM badge at
/// the bottom stay flat.
/// </remarks>
internal sealed class OverlayVisorRenderer : IDisposable
{
    public const float Pad = 40;
    /// <summary>Overall size matches the current overlay (member panel ~255 px wide at 1080p, 35 px rows).</summary>
    // 11-05: the user's own screenshot of today's overlay sets the size. At this scale member names
    // match the current overlay (about 10 units at 1080p) and a 480-unit group is about as wide as
    // the current member panel (~255 units). The size setting scales from here.
    public const float Compact = 0.53f;
    /// <summary>Groups are drawn this many times larger and scaled down after the perspective (method E).</summary>
    public const int Supersample = 2;
    /// <summary>The perspective viewing distance in design units (user, 11-07: fixed at 1000).</summary>
    public const float ViewingDistance = 1000;
    /// <summary>The fixed side-group width before 11-07 (280 px at 2560x1440 medium), kept to compare against in tests.</summary>
    public const float MaxSideWidthPx = 280;
    /// <summary>At most this many text fields of a group scroll at the same time; the rest wait their turn.</summary>
    public const int MaxScrolling = 2;
    /// <summary>The member columns' widths: wider at once, narrower only after the members settle (see OverlayVisorColumnWidths).</summary>
    private readonly OverlayVisorColumnWidths _columns = new();
    private float[] _teamColumns = [.. OverlayVisorDraw.MemberColumns.Select(c => c.Cap)];
    private float _teamWidth = OverlayVisorDraw.Width;
    /// <summary>The members box: the width and height the members are placed by (the maximum, or the fixed size).</summary>
    private (float W, float H) _teamBox = ((float)OverlayDisplaySettings.DefaultVisorMembersWidth, (float)OverlayDisplaySettings.DefaultVisorMembersHeight);
    /// <summary>The events and chat widths (design units): the width each is drawn at, and its box (maximum or fixed).</summary>
    private readonly Dictionary<string, OverlayVisorColumnWidths> _groupDebounce = new() { ["events"] = new(), ["chat"] = new() };
    private readonly Dictionary<string, float> _groupWidth = new() { ["events"] = (float)OverlayDisplaySettings.DefaultVisorMembersWidth, ["chat"] = (float)OverlayDisplaySettings.DefaultVisorMembersWidth };
    private readonly Dictionary<string, float> _groupBox = new() { ["events"] = (float)OverlayDisplaySettings.DefaultVisorMembersWidth, ["chat"] = (float)OverlayDisplaySettings.DefaultVisorMembersWidth };
    public IReadOnlyDictionary<string, float> GroupWidths => _groupWidth;
    /// <summary>The members group's current width and column widths (design units).</summary>
    public float TeamWidth => _teamWidth;
    public IReadOnlyList<float> TeamColumns => _teamColumns;
    private static readonly string[] Order = ["team", "events", "chat", "top", "dm"];
    private static readonly Dictionary<string, (float W, float H)> Box = new()
    {
        // events and chat hold their most lines (review R7: 5 events, 8 chat lines)
        ["team"] = (OverlayVisorDraw.Width, 1000),
        ["events"] = (OverlayVisorDraw.Width, OverlayVisorDraw.EventsBoxHeight(OverlayDisplaySettings.MaxEventNotificationCount)),
        ["chat"] = (OverlayVisorDraw.Width, OverlayVisorDraw.ChatBoxHeight(OverlayDisplaySettings.MaxChatVisibleCount)),
        ["top"] = (OverlayVisorDraw.TopWidth, 220), ["dm"] = (OverlayVisorDraw.Width, 40)
    };

    private readonly ID2D1DeviceContext _dc;
    private readonly OverlayVisorPainter _p;
    private readonly Dictionary<string, Layer> _layers = [];
    private readonly Vortice.DCommon.PixelFormat _pf = new(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
    private float _builtK = -1;
    private string _builtStyle = "";
    private string _noticeKey = "";
    private double _noticeAt = double.NegativeInfinity;

    public Dictionary<string, (float X, float Y)> Positions { get; private set; } = [];
    public Dictionary<string, (float W, float H)> Sizes { get; private set; } = [];
    /// <summary>The groups drawn tilted in the last frame and the side each leans to (true: right), for the editor
    /// preview's corners (NativeInformationOverlayRuntime.EditorPreview).</summary>
    internal Dictionary<string, bool> Tilted { get; } = [];
    /// <summary>When set, only this group is composited (the editor preview takes each block on its own, so a
    /// neighbour's glow never lands in its image); layout and effects are unchanged.</summary>
    internal string? Only { get; set; }
    public int Redraws { get; private set; }

    private sealed class Layer : IDisposable
    {
        /// <summary>Shapes: the frame only. Text: the text only. Combined / TextCombined: each with its effects, flat.</summary>
        public required ID2D1Bitmap1 Shapes, Text, Combined, TextCombined, HazeMask;
        public required Composite Both;
        public required Shadow Shadow, Bed, TextShadow;
        public required ColorMatrix Bright, TextBright;
        public required GaussianBlur Near, HazeBlur, TextNear;
        /// <summary>N look: only a faint glow on the frame and the text.</summary>
        public required Opacity GameShapeGlow, GameTextGlow;
        /// <summary>The frame and haze fade out on the side toward the screen centre through this mask.</summary>
        public required ID2D1Bitmap1 DissolveMask;
        public required ID2D1Effect Dissolve;
        public required ID2D1Effect Persp, TextPersp, MarqueePersp;
        public required Opacity Fade, TextFade, MarqueeFade;
        /// <summary>The scrolling fields: drawn flat into Marquee when an offset moves, with the text's own shadow.</summary>
        public required ID2D1Bitmap1 Marquee, MarqueeCombined;
        public required Shadow MarqueeShadow;
        public OverlayVisorDraw.ScrollField[] Scrolls = [];
        /// <summary>The health rings: drawn live into Marquee with the scrolling fields.</summary>
        public OverlayVisorDraw.RingSpot[] Rings = [];
        public Matrix3x2 ScrollTransform = Matrix3x2.Identity;
        public string ScrollKey = "";
        /// <summary>Marquee holds something (scrolling fields or rings); cleared once both are gone.</summary>
        public bool LiveDrawn;
        /// <summary>The live layer as last drawn holds a health ring that has a state (11-15 diagnostics).</summary>
        public bool RingLive;
        public double ScrollAt = double.NegativeInfinity;
        public string Signature = "";
        /// <summary>Where the camera was last set up for this group (screen position, angle, screen size).</summary>
        public string SpaceKey = "";
        public bool Right, Tilt;
        public float ContentH = 100;
        public void Dispose()
        {
            foreach (var d in new IDisposable[] { Shapes, Text, Combined, TextCombined, HazeMask, Both, Shadow, Bed, TextShadow, Bright, Near, HazeBlur, Persp, TextPersp, Fade, TextFade,
                MarqueePersp, MarqueeFade, Marquee, MarqueeCombined, MarqueeShadow, TextBright, TextNear, GameShapeGlow, GameTextGlow, DissolveMask, Dissolve })
                d.Dispose();
        }
    }

    /// <summary>
    /// The visor's own opening and closing (user, 11-10, over eight rounds of previews; the research and every round are in
    /// StarBridge-Reviews/visor-intro-research-20261110). In Star Citizen's helmet-HUD line language, after Squadron 42's
    /// flight HUD and Star Citizen's own helmet HUD: the side brackets of an elongated octagon close in from the screen
    /// edges with the top and bottom bars, overshoot a little and lock round the centre (the screen darkens a little while
    /// they close in and lets go at the lock); at the lock the frame flashes, energy runs along it, a line spreads from the
    /// centre and the glass rim flashes in the corners; the corner readouts, the pitch scales and the bottom readouts roll and
    /// settle round a diamond reticle; then the frame fades, it only belongs to the opening. The panels go with it on the
    /// same beat ("乙 只对齐节奏"): each plate opens from its screen-edge side on the brackets' curve and lands on the lock,
    /// the text comes with the same flash. Closing runs it backwards, quicker. Numbers and shapes only, no words.
    /// </summary>
    internal const double BracketLock = 0.32;
    internal static (double Open, double Close) Durations => (BracketLock + 0.62, 0.3);

    /// <summary>Still moving: opening, or closing and not yet gone.</summary>
    internal static bool IntroBusy(double openAt, double closeAt, double now) =>
        double.IsFinite(openAt) && now - openAt < Durations.Open + 0.11 || double.IsFinite(closeAt) && now >= closeAt && now - closeAt < Durations.Close + 0.11;

    private (double OpenAt, double CloseAt) _intro = (double.NegativeInfinity, double.PositiveInfinity);

    /// <summary>A panel's light at one moment of the opening or closing: plate and text alpha, exposure, and the flash.</summary>
    internal readonly record struct Fx(float Panel, float Text, float Exposure, float Flash)
    {
        public static readonly Fx Shown = new(1, 1, 1, 0);
    }

    // the effects for a panel's light, made once and reused (only used while opening or closing)
    private ColorMatrix? _fxPanelGain, _fxTextGain, _fxMarqueeGain;
    private Composite? _fxJoin;
    private GaussianBlur? _fxGlow;

    private void EnsureFx()
    {
        if (_fxJoin is not null) return;
        _fxPanelGain = new ColorMatrix(_dc); _fxTextGain = new ColorMatrix(_dc); _fxMarqueeGain = new ColorMatrix(_dc);
        _fxJoin = new Composite(_dc);
        _fxJoin.InputCount = 3;
        _fxGlow = new GaussianBlur(_dc) { Optimization = GaussianBlurOptimization.Speed };
    }

    private void DisposeFx()
    {
        foreach (var d in new IDisposable?[] { _fxPanelGain, _fxTextGain, _fxMarqueeGain, _fxJoin, _fxGlow }) d?.Dispose();
        _fxPanelGain = _fxTextGain = _fxMarqueeGain = null;
        _fxJoin = null; _fxGlow = null;
    }

    /// <summary>Exposure on the (straight) colour, alpha on the alpha (ColorMatrix works on straight colour).</summary>
    private static Matrix5x4 Gain(float exposure, float alpha) =>
        new(exposure, 0, 0, 0, 0, exposure, 0, 0, 0, 0, exposure, 0, 0, 0, 0, alpha, 0, 0, 0, 0);

    /// <summary>Draws one group with its light for this moment (the transform is already at the group's corner, in layer pixels).</summary>
    private void DrawFx(Layer l, Fx fx, float kL, Matrix3x2 at)
    {
        EnsureFx();
        _fxPanelGain!.Matrix = Gain(fx.Exposure, fx.Panel);
        _fxTextGain!.Matrix = Gain(fx.Exposure * (1 + 0.6f * fx.Flash), fx.Text);
        _fxMarqueeGain!.Matrix = Gain(fx.Exposure, fx.Text);
        Chain(_fxPanelGain, l.Fade); Chain(_fxTextGain, l.TextFade); Chain(_fxMarqueeGain, l.MarqueeFade);
        using (var a = _fxPanelGain.Output) _fxJoin!.SetInput(0, a, true);
        using (var b = _fxTextGain.Output) _fxJoin.SetInput(1, b, true);
        using (var m = _fxMarqueeGain.Output) _fxJoin.SetInput(2, m, true);
        _dc.Transform = at;
        DrawOutput(_fxJoin, interpolationMode: InterpolationMode.HighQualityCubic);
        if (fx.Flash > 0.02f)
        {
            // the flash: the group's own light, blurred and added
            _fxGlow!.StandardDeviation = 5 * kL / 2;
            Chain(_fxGlow, _fxJoin);
            for (var i = 0; i < (fx.Flash > 0.5f ? 2 : 1); i++) DrawOutput(_fxGlow, interpolationMode: InterpolationMode.Linear, compositeMode: CompositeMode.Plus);
        }
        _dc.Transform = at;
    }

    private static float OutBackShared(double v)
    {
        var x = Math.Clamp(v, 0, 1) - 1;
        const double s = 1.9;
        return (float)(1 + (s + 1) * x * x * x + s * x * x);
    }

    /// <summary>
    /// A side panel on the brackets' beat (user, 11-10: "乙 只对齐节奏"): before the lock its plate opens from the screen-edge
    /// side on the brackets' curve, a bright line at its opening edge; at the lock the text comes with the same flash. Closing:
    /// the text goes first, then the plate. The transform is at the group's corner, in layer pixels.
    /// </summary>
    private void DrawPanelOnBeat(Layer l, float kL, Matrix3x2 at, double t, double c)
    {
        var closing = double.IsFinite(c) && c >= 0;
        static float Clamp(double v) => (float)Math.Clamp(v, 0, 1);
        static float Decay(double x, double length) => x < 0 ? 0 : Clamp(1 - x / length) * Clamp(1 - x / length);
        if (!closing && t < BracketLock)
        {
            var size = l.Shapes.PixelSize;
            var reveal = OutBackShared((t - 0.06) / (BracketLock - 0.06));
            if (reveal <= 0) return;
            var width = MathF.Min(size.Width, size.Width * reveal);
            var x0 = l.Right ? size.Width - width : 0;
            _dc.Transform = at;
            _dc.PushAxisAlignedClip(new Rect(x0, -1e5f, width, 2e5f), AntialiasMode.Aliased);
            DrawOutput(l.Fade, interpolationMode: InterpolationMode.HighQualityCubic);
            _dc.PopAxisAlignedClip();
            var edge = l.Right ? x0 : width;
            var h = (l.ContentH + 2 * Pad) * kL;
            using var glow = _dc.CreateSolidColorBrush(_bracketAccent);
            using var white = _dc.CreateSolidColorBrush(new Color4(0.86f, 0.97f, 1, 1));
            glow.Opacity = 0.4f * l.Fade.Value; _dc.DrawLine(new Vector2(edge, Pad * kL * 0.5f), new Vector2(edge, h - Pad * kL * 0.5f), glow, 10 * kL);
            white.Opacity = 0.95f * l.Fade.Value; _dc.DrawLine(new Vector2(edge, Pad * kL * 0.5f), new Vector2(edge, h - Pad * kL * 0.5f), white, 1.6f * kL);
            return;
        }
        var fx = closing
            ? new Fx(Clamp(1 - c / 0.1), Clamp(1 - c / 0.05), 1 + 0.3f * Clamp(c / 0.05), 0.3f * Clamp(c / 0.05))
            : new Fx(1, Clamp((t - BracketLock - 0.01) / 0.06), 1 + 0.6f * Decay(t - BracketLock, 0.16), Decay(t - BracketLock, 0.14));
        if (fx.Panel > 0 || fx.Text > 0) DrawFx(l, fx, kL, at);
    }

    /// <summary>The rally band and the DM badge: they come at the lock with the flash, and go first when closing.</summary>
    private static Fx CentreGroupFx(double t, double c)
    {
        static float Clamp(double v) => (float)Math.Clamp(v, 0, 1);
        static float Decay(double x, double length) => x < 0 ? 0 : Clamp(1 - x / length) * Clamp(1 - x / length);
        if (double.IsFinite(c) && c >= 0) return new Fx(Clamp(1 - c / 0.08), Clamp(1 - c / 0.05), 1 + 0.3f * Clamp(c / 0.05), 0.3f * Clamp(c / 0.05));
        var since = t - BracketLock;
        return new Fx(Clamp(since / 0.05), Clamp((since - 0.01) / 0.06), 1 + 0.6f * Decay(since, 0.16), Decay(since, 0.14));
    }

    /// <summary>Draws a polyline (layout units) from its middle out toward both ends, <paramref name="share"/> of it (0..1).</summary>
    private void DrawFromMiddle(Vector2[] path, float share, float alpha)
    {
        if (share <= 0.001f || alpha <= 0.003f) return;
        var k = _bracketScale;
        var lengths = new float[path.Length - 1];
        for (var i = 0; i < lengths.Length; i++) lengths[i] = Vector2.Distance(path[i], path[i + 1]);
        var total = lengths.Sum();
        float from = total / 2 * (1 - share), to = total / 2 * (1 + share), walked = 0;
        using var pen = _dc.CreateSolidColorBrush(new Color4(0.84f, 0.97f, 1f, 1));
        using var glow = _dc.CreateSolidColorBrush(_bracketAccent);
        for (var i = 0; i < lengths.Length; i++)
        {
            float a0 = walked, a1 = walked + lengths[i];
            walked = a1;
            float s0 = MathF.Max(a0, from), s1 = MathF.Min(a1, to);
            if (s1 <= s0) continue;
            var p = Vector2.Lerp(path[i], path[i + 1], (s0 - a0) / lengths[i]);
            var q = Vector2.Lerp(path[i], path[i + 1], (s1 - a0) / lengths[i]);
            glow.Opacity = 0.3f * alpha; _dc.DrawLine(p * k, q * k, glow, 7 * k);
            pen.Opacity = alpha; _dc.DrawLine(p * k, q * k, pen, MathF.Max(1.3f, 1.6f * k));
        }
    }

    private float _bracketScale = 1;
    private Color4 _bracketAccent;

    /// <summary>
    /// The brackets (user, 11-10: "打开时从两边向中心，以电路一样的精细科技线条向中心收拢打开头盔hud，关闭反之"; "找星际公民相关的";
    /// "可以看看42中队相关的"). Drawn in Squadron 42's flight-HUD language as seen in its CitizenCon 2954 gameplay: an
    /// elongated octagon round the centre built from separate thin segments with gaps (each side a slanted top, a vertical, a
    /// slanted bottom), short segments at its top and bottom corners, short reach lines outward, pale cyan-white, almost no
    /// glow. Opening: the two side brackets travel in from the screen edges along faint rails and lock round the centre, the
    /// corner segments draw out, a faint flash, the panels switch on, and the frame fades (it only belongs to the opening).
    /// Closing runs it backwards: the frame comes back and its brackets spread out to the edges.
    /// </summary>
    private void DrawBracket(OverlayVisorScene s, double t, double c, float w, float h)
    {
        // 11-10 user on the first bracket preview: "方向是对的，但是我觉得需要更加富有细节、张力，现在还是太淡了". So: brighter
        // lines, two layers of brackets, ticks, rolling readouts at the corners, afterimages while they travel, an overshoot
        // into the lock, energy running along the frame and a line spreading from the centre when it locks.
        var k = h / 1080f;
        var layoutWidth = w / k;
        _bracketScale = k; _bracketAccent = s.Style.Deco;
        var closing = double.IsFinite(c) && c >= 0;
        static float Clamp(double v) => (float)Math.Clamp(v, 0, 1);
        static float OutBack(double v)
        {
            var x = Math.Clamp(v, 0, 1) - 1;
            const double s = 1.9;
            return (float)(1 + (s + 1) * x * x * x + s * x * x);
        }
        // spread of a bracket layer: 1 at the screen edges, 0 locked (it goes a little past 0 and springs back)
        float Spread(double delay)
        {
            if (closing)
            {
                var back = Clamp((c - 0.04 - delay * 0.5) / 0.2);
                return back * back;
            }
            return 1 - OutBack((t - delay) / BracketLock);
        }
        float frameAlpha, corners, dim;
        if (closing)
        {
            frameAlpha = Clamp(c / 0.04) * (1 - Clamp((c - 0.2) / 0.08));
            corners = 1 - Clamp(c / 0.06);
            dim = 0.18f * (1 - Clamp(c / 0.12));
        }
        else
        {
            frameAlpha = Clamp(t / 0.05) * (1 - Clamp((t - BracketLock - 0.3) / 0.26));
            corners = Clamp((t - BracketLock) / 0.1);
            // the screen darkens a little while the brackets close in, and lets go when they lock
            dim = t < BracketLock ? 0.28f * Clamp(t / BracketLock) : 0.28f * (1 - Clamp((t - BracketLock) / 0.12));
        }
        if (frameAlpha <= 0.005f && dim <= 0.005f) return;
        using (var veil = _dc.CreateSolidColorBrush(new Color4(0, 0, 0, 1)))
        {
            veil.Opacity = dim * s.Opacity;
            if (dim > 0.005f) _dc.FillRectangle(new Rect(0, 0, w, h), veil);
        }
        var a = frameAlpha * s.Opacity;
        float cx = layoutWidth / 2, halfW = layoutWidth * 0.235f, top = 1080 * 0.2f, bottom = 1080 * 0.8f, slant = 1080 * 0.16f, inset = 1080 * 0.05f;
        var line = new Color4(0.84f, 0.97f, 1f, 1);
        using var pen = _dc.CreateSolidColorBrush(line);
        using var glow = _dc.CreateSolidColorBrush(s.Style.Deco);
        float thin = MathF.Max(1.3f, 1.6f * k), soft = 7 * k;
        void Seg(Vector2 p, Vector2 q, float alpha, float width = 0)
        {
            if (alpha <= 0.003f) return;
            glow.Opacity = 0.3f * alpha; _dc.DrawLine(p * k, q * k, glow, soft);
            pen.Opacity = alpha; _dc.DrawLine(p * k, q * k, pen, width > 0 ? width * k : thin);
        }
        const float gap = 9;
        var lockFlash = closing ? 0 : Clamp(1 - Math.Abs(t - BracketLock - 0.02) / 0.07);
        var pulse = closing ? -1 : (t - BracketLock) / 0.14; // energy running along the frame after the lock
        foreach (var side in new[] { -1f, 1f })
        {
            var restX = cx + side * halfW;
            var edgeX = side < 0 ? 24f : layoutWidth - 24;
            // the outer bracket, its afterimages, and an inner bracket arriving a beat later
            foreach (var (layer, delay, offset, alphaScale) in new[] { (0, 0.0, 0f, 1f), (1, 0.05, 16f, 0.5f) })
            {
                var spread = Spread(delay);
                for (var ghost = layer == 0 && spread > 0.02f ? 3 : 0; ghost >= 0; ghost--)
                {
                    var sp = spread + ghost * 0.07f * MathF.Min(1, spread * 4);
                    var ga = ghost == 0 ? 1 : 0.28f / ghost;
                    var x = restX - side * offset + (edgeX - restX) * sp;
                    var tall = 1 + 0.12f * MathF.Max(0, sp);
                    float y0 = 540 - (540 - top + offset) * tall, y1 = 540 + (bottom - 540 - offset) * tall, sl = slant * tall;
                    var dx = -side * inset;
                    Vector2 tTop = new(x + dx, y0), tMid = new(x, y0 + sl), bMid = new(x, y1 - sl), bBot = new(x + dx, y1);
                    Vector2 G(Vector2 from, Vector2 to) => from + Vector2.Normalize(to - from) * gap;
                    var la = a * alphaScale * ga;
                    Seg(G(tTop, tMid), G(tMid, tTop), la);
                    Seg(G(tMid, bMid), G(bMid, tMid), la, layer == 0 ? 2.2f : 0);
                    Seg(G(bMid, bBot), G(bBot, bMid), la);
                    if (ghost > 0 || layer > 0) continue;
                    // fine ticks along the vertical, on the inner side, every 22 units
                    pen.Opacity = 0.55f * a;
                    for (var y = tMid.Y + 18; y < bMid.Y - 14; y += 22)
                        _dc.DrawLine(new Vector2(x - side * 4, y) * k, new Vector2(x - side * (MathF.Abs(y - 540) < 12 ? 16 : 9), y) * k, pen, MathF.Max(1, 1.1f * k));
                    // reach lines outward, with a small scale on them
                    foreach (var fy in new[] { 0.36f, 0.64f })
                    {
                        var y = y0 + (y1 - y0) * fy;
                        Seg(new Vector2(x + side * 14, y), new Vector2(x + side * 70, y), a * 0.8f);
                        pen.Opacity = 0.5f * a;
                        for (var d = 24f; d <= 68; d += 11) _dc.DrawLine(new Vector2(x + side * d, y - 4) * k, new Vector2(x + side * d, y) * k, pen, MathF.Max(1, k));
                    }
                    if (spread > 0.02f)
                    {
                        // the rails it travels along
                        foreach (var y in new[] { y0, 540f, y1 })
                        {
                            pen.Opacity = 0.35f * a * MathF.Min(1, spread * 3);
                            _dc.DrawLine(new Vector2(edgeX, y) * k, new Vector2(x, y) * k, pen, MathF.Max(1, k));
                        }
                    }
                    if (pulse is >= 0 and <= 1)
                    {
                        // energy running from the middle of the bracket to both ends as it locks
                        foreach (var sign in new[] { -1f, 1f })
                        {
                            var along = (float)pulse;
                            var vertical = (bMid.Y - tMid.Y) / 2;
                            Vector2 head = along < 0.6f
                                ? new Vector2(x, 540 + sign * vertical * along / 0.6f)
                                : Vector2.Lerp(sign < 0 ? tMid : bMid, sign < 0 ? tTop : bBot, (along - 0.6f) / 0.4f);
                            glow.Opacity = 0.6f * s.Opacity; _dc.FillEllipse(new Ellipse(head * k, 9 * k, 9 * k), glow);
                            pen.Opacity = s.Opacity; _dc.FillEllipse(new Ellipse(head * k, 2.4f * k, 2.4f * k), pen);
                        }
                    }
                    if (lockFlash > 0.01f)
                    {
                        glow.Opacity = 0.55f * lockFlash * s.Opacity;
                        _dc.DrawLine(tMid * k, bMid * k, glow, 16 * k);
                    }
                }
            }
            if (corners > 0.01f)
            {
                // corner segments on the top and bottom edges, and a rolling readout beside each
                var length = 130 * corners;
                foreach (var (y, below) in new[] { (top, false), (bottom, true) })
                {
                    var from = new Vector2(restX - side * inset - side * gap, y);
                    Seg(from, from - new Vector2(side * length, 0), a);
                    var settle = closing ? 1 : Clamp((t - BracketLock - 0.04) / 0.2);
                    var value = (side, below) switch { (-1, false) => 42.6, (1, false) => 609.28, (-1, true) => 7.0, _ => 1.0 };
                    var shown = settle >= 1 ? value : value * settle + (1 - settle) * ((uint)HashCode.Combine(side, below, (int)(t * 40)) % 1000 / 10.0);
                    var text = value >= 100 ? shown.ToString("000.00") : value >= 10 ? shown.ToString("00.0") : shown.ToString("0.00");
                    var tx = side < 0 ? from.X - length + 6 : from.X + length - 70;
                    _dc.Transform = Matrix3x2.CreateScale(k);
                    _p.Pass = OverlayVisorPass.All; _p.Alpha = 1;
                    _p.Text(text, tx, below ? y + 6 : y - 22, true, Vortice.DirectWrite.FontWeight.Medium, 12, line, a * corners * 0.9f);
                    _dc.Transform = Matrix3x2.Identity;
                }
            }
        }
        if (corners > 0.01f)
        {
            // the boxed readout centred under the frame, and a small centre mark
            var bw = 92f; var bh = 20f; var by = bottom + 14;
            var box = new Rect((cx - bw / 2) * k, by * k, bw * k, bh * k);
            pen.Opacity = 0.7f * a * corners; _dc.DrawRectangle(box, pen, MathF.Max(1, k));
            var settle = closing ? 1 : Clamp((t - BracketLock - 0.04) / 0.2);
            _dc.Transform = Matrix3x2.CreateScale(k);
            _p.Text((0.92 * settle).ToString("0.00") + " / 1.00", cx - bw / 2 + 12, by + 2, true, Vortice.DirectWrite.FontWeight.Medium, 12, line, a * corners);
            _dc.Transform = Matrix3x2.Identity;
        }
        // 11-10 user, with a picture of Star Citizen's helmet HUD: "还可以加其他地方的效果吗，比如上下". The top and bottom
        // bars close in from the screen's top and bottom edges together with the side brackets (their outline drawing out
        // from the middle), the pitch scales and the diamond reticle settle in the centre, and the visor's glass rim flashes
        // in the corners when everything locks. Numbers and shapes only, no words.
        float vSpread;
        if (closing) { var back = Clamp((c - 0.02) / 0.2); vSpread = back * back; }
        else vSpread = 1 - OutBack((t - 0.03) / (BracketLock - 0.03));
        var draw = closing ? 1 - Clamp((c - 0.06) / 0.16) : Clamp((t - 0.02) / (BracketLock - 0.06));
        // top bar: a shallow trapezoid hanging from the top edge
        {
            var y = 54 - 90 * vSpread;
            float wing = layoutWidth * 0.29f, inner = layoutWidth * 0.245f;
            Vector2[] path = [new(cx - wing, y - 54), new(cx - inner, y), new(cx + inner, y), new(cx + wing, y - 54)];
            DrawFromMiddle(path, draw, a);
            // a second, inner line and the cells along it, lit one by one after the lock
            Seg(new Vector2(cx - inner + 30, y + 14), new Vector2(cx - inner + 30 + (2 * inner - 60) * draw, y + 14), a * 0.45f);
            var cells = closing ? 1 - Clamp(c / 0.06) : Clamp((t - BracketLock) / 0.2);
            for (var i = 0; i < 5; i++)
            {
                var lit = Clamp(cells * 5 - i);
                if (lit <= 0) continue;
                var x = cx - 160 + i * 80;
                pen.Opacity = (i == 0 ? 0.95f : 0.55f) * a * lit;
                _dc.DrawRectangle(new Rect((x - 26) * k, (y + 22) * k, 52 * k, 14 * k), pen, MathF.Max(1, k));
                if (i == 0) { glow.Opacity = 0.25f * a * lit; _dc.FillRectangle(new Rect((x - 26) * k, (y + 22) * k, 52 * k, 14 * k), glow); }
                _dc.FillRectangle(new Rect((x - 12) * k, (y + 27) * k, 24 * k * lit, 4 * k), pen);
            }
        }
        // bottom bar: the mirror image, with four boxed readouts that roll and settle
        {
            var y = 1080 - 58 + 90 * vSpread;
            float wing = layoutWidth * 0.3f, inner = layoutWidth * 0.2f;
            Vector2[] path = [new(cx - wing, y + 58), new(cx - inner, y), new(cx + inner, y), new(cx + wing, y + 58)];
            DrawFromMiddle(path, draw, a);
            var settle = closing ? 1 : Clamp((t - BracketLock - 0.04) / 0.24);
            var values = new[] { 1500.0, 7.0, 0.0, 443.0 };
            for (var i = 0; i < 4; i++)
            {
                var lit = closing ? 1 - Clamp(c / 0.06) : Clamp((t - BracketLock - i * 0.04) / 0.1);
                if (lit <= 0) continue;
                var x = cx - 210 + i * 140;
                pen.Opacity = 0.7f * a * lit;
                _dc.DrawRoundedRectangle(new RoundedRectangle(new System.Drawing.RectangleF((x - 54) * k, (y - 34) * k, 108 * k, 24 * k), 3 * k, 3 * k), pen, MathF.Max(1, k));
                var shown = settle >= 1 ? values[i] : values[i] * settle + (1 - settle) * ((uint)HashCode.Combine(i, (int)(t * 40)) % 1000);
                _dc.Transform = Matrix3x2.CreateScale(k);
                _p.Text(i == 2 ? $"{shown:0}%" : $"{shown:0}", x - 18, y - 32, true, Vortice.DirectWrite.FontWeight.Medium, 13, line, a * lit);
                _dc.Transform = Matrix3x2.Identity;
            }
        }
        // the pitch scales either side of the centre: ticks every 12 units, a number every 5 ticks, rolling into place
        {
            var settle = closing ? 1 - Clamp(c / 0.08) : Clamp((t - BracketLock + 0.06) / 0.22);
            if (settle > 0.01f)
            {
                var roll = (1 - settle) * 60;
                foreach (var side in new[] { -1f, 1f })
                {
                    var x = cx + side * 230;
                    pen.Opacity = 0.65f * a * settle;
                    for (var i = -10; i <= 10; i++)
                    {
                        var y = 540 + i * 12 + roll % 12;
                        if (MathF.Abs(y - 540) > 130) continue;
                        var major = (i + 100) % 5 == 0;
                        var fade = 1 - MathF.Abs(y - 540) / 140;
                        pen.Opacity = (major ? 0.85f : 0.5f) * a * settle * fade;
                        _dc.DrawLine(new Vector2(x, y) * k, new Vector2(x + side * (major ? 14 : 7), y) * k, pen, MathF.Max(1, k));
                        if (major)
                        {
                            _dc.Transform = Matrix3x2.CreateScale(k);
                            _p.Text($"{360 - i * 2 + (int)(roll / 12) * 2}", side < 0 ? x - 42 : x + 20, y - 9, true, Vortice.DirectWrite.FontWeight.Medium, 12, line, a * settle * fade);
                            _dc.Transform = Matrix3x2.Identity;
                        }
                    }
                }
            }
        }
        // the diamond reticle
        if (corners > 0.01f)
        {
            var r = 16 + 10 * (1 - corners);
            Vector2[] d = [new(cx, 540 - r), new(cx + r, 540), new(cx, 540 + r), new(cx - r, 540)];
            for (var i = 0; i < 4; i++)
            {
                var p0 = Vector2.Lerp(d[i], d[(i + 1) % 4], 0.18f); var p1 = Vector2.Lerp(d[i], d[(i + 1) % 4], 0.82f);
                Seg(p0, p1, a * corners);
            }
            foreach (var (dx, dy) in new[] { (-1f, 0f), (1f, 0f), (0f, -1f), (0f, 1f) })
                Seg(new Vector2(cx + dx * (r + 6), 540 + dy * (r + 6)), new Vector2(cx + dx * (r + 22), 540 + dy * (r + 22)), a * corners * 0.8f);
        }
        // the visor's glass rim flashes in the four corners when everything locks
        var rim = closing ? 0.6f * (1 - Clamp(c / 0.1)) : Clamp(1 - Math.Abs(t - BracketLock - 0.03) / 0.12);
        if (rim > 0.01f)
        {
            using var factory = _dc.Factory;
            foreach (var (sx, sy) in new[] { (-1f, -1f), (1f, -1f), (-1f, 1f), (1f, 1f) })
            {
                using var arc = factory.CreatePathGeometry();
                using (var sink = arc.Open())
                {
                    var corner = new Vector2(sx < 0 ? 0 : layoutWidth, sy < 0 ? 0 : 1080);
                    var from = corner + new Vector2(-sx * 40, -sy * 330);
                    var to = corner + new Vector2(-sx * 380, -sy * 30);
                    sink.BeginFigure(from * k, FigureBegin.Hollow);
                    sink.AddQuadraticBezier(new QuadraticBezierSegment { Point1 = (corner + new Vector2(-sx * 70, -sy * 60)) * k, Point2 = to * k });
                    sink.EndFigure(FigureEnd.Open); sink.Close();
                }
                glow.Opacity = 0.35f * rim * s.Opacity; _dc.DrawGeometry(arc, glow, 12 * k);
                pen.Opacity = 0.9f * rim * s.Opacity; _dc.DrawGeometry(arc, pen, MathF.Max(1.3f, 1.8f * k));
            }
        }

        // the lock: a line spreads sideways from the centre out to the brackets
        var wave = closing ? -1 : (t - BracketLock) / 0.12;
        if (wave is >= 0 and <= 1)
        {
            var reach = (float)wave * halfW;
            var fade = 1 - (float)wave;
            glow.Opacity = 0.45f * fade * s.Opacity; _dc.DrawLine(new Vector2(cx - reach, 540) * k, new Vector2(cx + reach, 540) * k, glow, 8 * k);
            pen.Opacity = fade * s.Opacity; _dc.DrawLine(new Vector2(cx - reach, 540) * k, new Vector2(cx + reach, 540) * k, pen, MathF.Max(1, 1.2f * k));
        }
    }


    public OverlayVisorRenderer(ID2D1DeviceContext dc, IDWriteFactory5 dw)
    {
        _dc = dc;
        _p = new OverlayVisorPainter(dc, dw);
    }

    /// <summary>True while the visor has its own motion running (notice pulse and sweep); the frame scheduler keeps ticking.</summary>
    public bool Animating(double now) => OverlayVisorDraw.TopAnimating(now - _noticeAt) || _scrolling || _ringsBusy || _columns.Busy || _groupDebounce.Values.Any(d => d.Busy) ||
        IntroBusy(_intro.OpenAt, _intro.CloseAt, now);
    private bool _ringsBusy;

    /// <summary>
    /// A member's health ring over time (user, 11-10, via the scheduler): "掉血要闪一下…回血顺滑恢复"; "倒地要慢闪，阵亡要X，
    /// 复活可以加小动画"; later "低血量不闪", and the revived ring glows once grown ("长满时亮一下"). A loss takes the ring
    /// down at once and flashes it; healing grows it back smoothly; low stays still; downed blinks slowly; coming back from
    /// downed or dead grows the ring from empty and it glows softly once grown. All of it held back so it never glares;
    /// it asks for frames only while it moves.
    /// </summary>
    private sealed class RingMotion
    {
        public OverlayVisorVitals Vitals;
        public float Target, Shown;
        public double FlashAt = double.NegativeInfinity, GlowAt = double.NegativeInfinity, Since, Last;
        public bool Seen, Reviving;
        public float Loss;
    }

    private readonly Dictionary<string, RingMotion> _ringMotion = [];
    internal const double RingFlash = 0.4, RingGlow = 0.5, RingBlink = 1.8;
    /// <summary>Loss flashes started so far (11-15 diagnostics, counts only; in 0.7.3 only the own ring can flash).</summary>
    internal int RingFlashes { get; private set; }
    /// <summary>
    /// 11-15 diagnostics (counts only): whether the latest frame composed a live layer holding a health ring that has a
    /// state (in 0.7.3 only the own ring has one); frames drawn on the opening/closing beat (no live layer then); and how
    /// often a live layer was emptied.
    /// </summary>
    internal bool LastFrameRingComposed { get; private set; }
    internal int IntroFrames { get; private set; }
    internal int LiveClears { get; private set; }

    /// <summary>The ring's look at <paramref name="now"/>, and whether it is still moving.</summary>
    private (OverlayVisorDraw.HealthLook Look, bool Busy) StepRing(string key, OverlayVisorMember m, double now)
    {
        var target = m.Vitals == OverlayVisorVitals.Alive ? Math.Clamp(float.IsFinite(m.Health) ? m.Health : 0, 0, 1) : 0;
        if (!_ringMotion.TryGetValue(key, out var r)) _ringMotion[key] = r = new RingMotion();
        if (!r.Seen)
        {
            // first sight: shown as it is, nothing to animate yet
            r.Seen = true; r.Vitals = m.Vitals; r.Target = r.Shown = target; r.Since = r.Last = now;
        }
        // at most one frame's worth: a settled ring gets no frames, so the first step after a change must not jump
        var dt = Math.Clamp(now - r.Last, 0, 1 / 30.0);
        r.Last = now;
        if (m.Vitals != r.Vitals)
        {
            // back from downed or dead: the ring grows from empty
            if (m.Vitals == OverlayVisorVitals.Alive && r.Vitals is OverlayVisorVitals.Downed or OverlayVisorVitals.Dead) { r.Shown = 0; dt = 0; r.Reviving = true; }
            else if (m.Vitals == OverlayVisorVitals.Alive) r.Shown = target;
            r.Vitals = m.Vitals; r.Since = now; r.Target = target;
        }
        if (m.Vitals != OverlayVisorVitals.Alive)
        {
            r.Shown = r.Target = 0; r.Reviving = false; r.GlowAt = double.NegativeInfinity;
            if (m.Vitals == OverlayVisorVitals.Downed)
            {
                // a slow blink, from full down to a third and back
                var blink = 0.5 + 0.5 * Math.Cos(2 * Math.PI * (now - r.Since) / RingBlink);
                return (new(m.Vitals, 0, (float)(0.35 + 0.65 * blink), 0), true);
            }
            return (new(m.Vitals, 0, 1, 0), false);
        }
        // a loss: down at once, one flash (it also ends a revival's growth); small steps add up, so a slow drain flashes too
        if (target < r.Target) r.Loss += r.Target - target;
        else if (target > r.Target) r.Loss = 0;
        if (r.Loss >= 0.004f) { r.FlashAt = now; r.Reviving = false; r.Loss = 0; RingFlashes++; }
        r.Target = target;
        if (r.Shown > target) r.Shown = target;
        else if (r.Shown < target)
        {
            // healing: an eased approach with a floor, so the end does not crawl
            var step = (float)Math.Max(dt * 0.3, (target - r.Shown) * (1 - Math.Exp(-dt * 5)));
            r.Shown = MathF.Min(target, r.Shown + step);
            if (r.Shown >= target && r.Reviving) { r.Reviving = false; r.GlowAt = now; }
        }
        else if (r.Reviving) { r.Reviving = false; r.GlowAt = now; }
        var since = now - r.FlashAt;
        var flash = since >= 0 && since < RingFlash ? (float)Math.Pow(1 - since / RingFlash, 2) : 0;
        // the revived ring's glow: up and down again, soft
        var sinceGlow = now - r.GlowAt;
        // busy from the glow's first moment (where it is still 0), so its frames are asked for (review CX-VISOR-INTRO-R4)
        var glowing = sinceGlow >= 0 && sinceGlow < RingGlow;
        var glow = glowing ? (float)Math.Sin(Math.PI * sinceGlow / RingGlow) : 0;
        return (new(OverlayVisorVitals.Alive, r.Shown, 1, flash, glow), flash > 0 || glowing || r.Shown < target || r.Reviving);
    }
    private bool _scrolling;
    /// <summary>How many text fields scroll now, and how many times a scroll layer was redrawn.</summary>
    public int ScrollFields { get; private set; }
    public int ScrollRedraws { get; private set; }

    /// <param name="k">Layer pixels per design unit (already supersampled).</param>
    private void Build(float k, OverlayVisorStyle st)
    {
        var styleKey = $"{st.Bloom}|{st.BloomThreshold}|{st.Haze}";
        if (MathF.Abs(_builtK - k) < 0.0001f && _builtStyle == styleKey && _layers.Count > 0) return;
        foreach (var l in _layers.Values) l.Dispose();
        _layers.Clear();
        _builtK = k; _builtStyle = styleKey;
        foreach (var id in Order)
        {
            var (bw, bh) = Box[id];
            var size = new SizeI((int)MathF.Ceiling((bw + Pad * 2) * k), (int)MathF.Ceiling((bh + Pad * 2) * k));
            // a step that throws must not leave the effects and bitmaps made so far holding the device (review CX-D3D-RELEASE-R1)
            var made = new List<IDisposable>();
            try
            {
                ID2D1Bitmap1 Target() => _dc.CreateBitmap(size, IntPtr.Zero, 0, new BitmapProperties1(_pf, 96, 96, BitmapOptions.Target));
                var shapes = Target(); made.Add(shapes); var text = Target(); made.Add(text); var combined = Target(); made.Add(combined); var textCombined = Target(); made.Add(textCombined); var haze = Target(); made.Add(haze);
                var bloom = id == "top" ? st.Bloom + 0.1f : st.Bloom;
                // the dark bed sits behind the frame and the text together
                var both = new Composite(_dc); made.Add(both); both.SetInput(0, shapes, true); both.SetInput(1, text, true);
                var shadow = new Shadow(_dc); made.Add(shadow); shadow.BlurStandardDeviation = 4.5f * k; shadow.Color = new Vector4(0, 0, 0, 0.95f); shadow.SetInput(0, shapes, true);
                var bed = new Shadow(_dc); made.Add(bed); bed.BlurStandardDeviation = 22f * k; bed.Color = new Vector4(0, 0, 0, 0.75f); Chain(bed, both);
                var bright = new ColorMatrix(_dc); made.Add(bright); bright.Matrix = new Matrix5x4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, bloom, -st.BloomThreshold, -st.BloomThreshold, -st.BloomThreshold, 0); bright.SetInput(0, shapes, true);
                var near = new GaussianBlur(_dc); made.Add(near); near.StandardDeviation = 3f * k; Chain(near, bright);
                var hazeBlur = new GaussianBlur(_dc); made.Add(hazeBlur); hazeBlur.StandardDeviation = (id == "top" ? 46f : 34f) * k; hazeBlur.SetInput(0, haze, true);
                var textShadow = new Shadow(_dc); made.Add(textShadow); textShadow.BlurStandardDeviation = 4.5f * k; textShadow.Color = new Vector4(0, 0, 0, 0.95f); textShadow.SetInput(0, text, true);
                var dissolveMask = Target(); made.Add(dissolveMask);
                var dissolve = new ID2D1Effect(_dc.CreateEffect(EffectGuids.AlphaMask)); made.Add(dissolve); dissolve.SetInput(0, combined, true); dissolve.SetInput(1, dissolveMask, true);
                var persp = new ID2D1Effect(_dc.CreateEffect(EffectGuids.PerspectiveTransform3D)); made.Add(persp);
                Chain(persp, dissolve);
                var textPersp = new ID2D1Effect(_dc.CreateEffect(EffectGuids.PerspectiveTransform3D)); made.Add(textPersp); textPersp.SetInput(0, textCombined, true);
                var fade = new Opacity(_dc); made.Add(fade); fade.Value = 1f; Chain(fade, persp);
                var textFade = new Opacity(_dc); made.Add(textFade); textFade.Value = 1f; Chain(textFade, textPersp);
                var marquee = Target(); made.Add(marquee); var marqueeCombined = Target(); made.Add(marqueeCombined);
                var marqueeShadow = new Shadow(_dc); made.Add(marqueeShadow); marqueeShadow.BlurStandardDeviation = 4.5f * k; marqueeShadow.Color = new Vector4(0, 0, 0, 0.95f); marqueeShadow.SetInput(0, marquee, true);
                var textBright = new ColorMatrix(_dc); made.Add(textBright); textBright.Matrix = bright.Matrix; textBright.SetInput(0, text, true);
                var textNear = new GaussianBlur(_dc); made.Add(textNear); textNear.StandardDeviation = 3f * k; Chain(textNear, textBright);
                var gameShapeGlow = new Opacity(_dc); made.Add(gameShapeGlow); gameShapeGlow.Value = 0.35f; Chain(gameShapeGlow, near);
                var gameTextGlow = new Opacity(_dc); made.Add(gameTextGlow); gameTextGlow.Value = 0.3f; Chain(gameTextGlow, textNear);
                // the game look (user, 11-07: "参考游戏"): a tight shadow, a little dark right behind the text, the tint stays a
                // plate, a thin dark edge on the text
                shadow.BlurStandardDeviation = 1.2f * k; shadow.Color = new Vector4(0, 0, 0, 0.8f);
                bed.BlurStandardDeviation = 5f * k; bed.Color = new Vector4(0, 0, 0, 0.55f);
                hazeBlur.StandardDeviation = 2.5f * k;
                textShadow.BlurStandardDeviation = marqueeShadow.BlurStandardDeviation = 1.3f * k / Compact;
                textShadow.Color = marqueeShadow.Color = new Vector4(0, 0, 0, 1);
                var marqueePersp = new ID2D1Effect(_dc.CreateEffect(EffectGuids.PerspectiveTransform3D)); made.Add(marqueePersp); marqueePersp.SetInput(0, marqueeCombined, true);
                var marqueeFade = new Opacity(_dc); made.Add(marqueeFade); marqueeFade.Value = 1f; Chain(marqueeFade, marqueePersp);
                _layers[id] = new Layer
                {
                    Shapes = shapes, Text = text, Combined = combined, TextCombined = textCombined, HazeMask = haze, Both = both,
                    Shadow = shadow, Bed = bed, TextShadow = textShadow, Bright = bright, Near = near, HazeBlur = hazeBlur,
                    Persp = persp, TextPersp = textPersp, Fade = fade, TextFade = textFade,
                    Marquee = marquee, MarqueeCombined = marqueeCombined, MarqueeShadow = marqueeShadow, MarqueePersp = marqueePersp, MarqueeFade = marqueeFade,
                    TextBright = textBright, TextNear = textNear, GameShapeGlow = gameShapeGlow, GameTextGlow = gameTextGlow, DissolveMask = dissolveMask, Dissolve = dissolve,
                };
            }
            catch
            {
                for (var n = made.Count - 1; n >= 0; n--) made[n].Dispose();
                throw;
            }
        }
    }

    private static string Sig(OverlayVisorScene s, string id) => id switch
    {
        "team" => $"{s.TeamHeading}|{s.Online}|{s.InGame}|{s.SameServer}|{s.RealtimeUnknown}|{s.YouAt}|{s.PageLabel}|" +
            string.Join(";", s.Members.Select(m => $"{m.Name},{m.Ship},{m.Place},{m.Status},{m.State},{m.Pinned},{m.SameServer}")),
        "events" => s.EventsTitle + "|" + string.Join(";", s.Events.Select(e => $"{e.Title},{e.Detail},{e.Time},{MathF.Round(e.Reveal, 3)},{MathF.Round(e.Opacity, 3)},{MathF.Round(e.Leave, 3)}")),
        "chat" => s.ChatTitle + "|" + string.Join(";", s.Chat.Select(c => $"{c.Who},{c.Text},{MathF.Round(c.Opacity, 3)}")),
        "top" => $"{s.NoticeTitle}|{s.NoticeBody}|{s.NoticeTimer}|{s.NoticeHint}|{s.NoticeIsRally}",
        _ => s.DirectMessage ?? "",
    };

    private float DrawGroup(string id, OverlayVisorDraw g, OverlayVisorScene s, double now) => id switch
    {
        "team" => g.Team(s),
        "events" => g.Events(s),
        "chat" => g.Chat(s),
        "top" => g.Top(s, now - _noticeAt),
        _ => g.DirectMessage(s.DirectMessage ?? ""),
    };

    /// <param name="k">Layer pixels per design unit (already supersampled).</param>
    /// <summary>Draws <paramref name="draw"/> at <paramref name="opacity"/> (a layer only when it is less than full).</summary>
    private void WithOpacity(float opacity, Action draw)
    {
        if (opacity >= 0.999f) { draw(); return; }
        if (opacity <= 0.001f) return;
        _dc.PushLayer(new LayerParameters1 { ContentBounds = new Vortice.RawRectF(-1e6f, -1e6f, 1e6f, 1e6f), MaskAntialiasMode = AntialiasMode.PerPrimitive,
            MaskTransform = Matrix3x2.Identity, Opacity = opacity, LayerOptions = LayerOptions1.None }, null);
        draw();
        _dc.PopLayer();
    }

    /// <summary>
    /// The solid plate's colour behind a group: the decoration colour's own dark (m102b, 11-18 user: "保持主题色不脏"),
    /// so a high background opacity keeps the theme's hue. The fixed cool near-black it replaces turned a warm theme's tint
    /// muddy; for the default blue it is nearly the same colour.
    /// </summary>
    internal static Color4 PlateColor(Color4 deco) => new(deco.R * PlateShade, deco.G * PlateShade, deco.B * PlateShade, 1);

    private const float PlateShade = 0.09f;

    /// <summary>
    /// The plate for a background opacity (0..1, its real opacity since 11-13): up to 15% the faint decoration-colour tint
    /// the visor always had (at 15% exactly the old 100%), above it a dark plate that is solid at 100%, the tint on top.
    /// </summary>
    internal static (float Dark, float Tint) Plate(float background)
    {
        var v = Math.Clamp(background, 0, 1);
        return (MathF.Max(0, (v - LegacyBackground) / (1 - LegacyBackground)), 0.13f * MathF.Min(1, v / LegacyBackground));
    }

    /// <summary>The rally's haze for a background opacity: its old strength at 15%, solid at 100%.</summary>
    internal static float TopHaze(float old, float background)
    {
        var v = Math.Clamp(background, 0, 1);
        return v <= LegacyBackground ? old * v / LegacyBackground : old + (1 - old) * (v - LegacyBackground) / (1 - LegacyBackground);
    }

    private const float LegacyBackground = (float)StarBridge.Core.Overlay.InformationOverlayDefaults.LegacyBackgroundScale;

    private float DrawLayer(string id, Layer l, OverlayVisorScene s, float k, double now)
    {
        var st = s.Style;
        var side = id is "team" or "events" or "chat";
        var drawWidth = id switch { "top" => OverlayVisorDraw.TopWidth, "team" => _teamWidth, "events" or "chat" => _groupWidth[id], _ => OverlayVisorDraw.Width };
        // a side group on the right edge stays against its own box's edge
        var shift = !side || !l.Right ? 0 : id == "team" ? _teamBox.W - drawWidth : _groupBox[id] - drawWidth;
        var tr = Matrix3x2.CreateTranslation(Pad + shift, Pad) * Matrix3x2.CreateScale(k);
        var h = 0f;
        foreach (var (bitmap, pass) in new[] { (l.Shapes, OverlayVisorPass.Shapes), (l.Text, OverlayVisorPass.Text) })
        {
            _dc.Target = bitmap; _dc.BeginDraw(); _dc.Clear(new Color4(0, 0, 0, 0));
            _dc.Transform = tr; _p.Base = tr; _p.Alpha = 1; _p.Pass = pass;
            var g = new OverlayVisorDraw(_p, st, l.Right, now, drawWidth)
            {
                Columns = _teamColumns, Narrowing = id == "team" ? _columns.Narrowing : side && _groupDebounce.TryGetValue(id, out var d) && d.Narrowing,
                Bare = id == "chat" && !s.ChatPlate,
                FixedHeight = s.MembersAutoHeight ? 0 : _teamBox.H,
            };
            h = DrawGroup(id, g, s, now);
            if (pass == OverlayVisorPass.Shapes) l.Rings = [.. g.Rings];
            if (pass == OverlayVisorPass.Text) { l.Scrolls = [.. g.Scrolls]; l.ScrollTransform = tr; l.ScrollKey = ""; }
            _p.Pass = OverlayVisorPass.All;
            _dc.Transform = Matrix3x2.Identity; _p.Base = Matrix3x2.Identity;
            _dc.EndDraw().CheckError();
        }
        h = MathF.Min(h, Box[id].H);

        var dissolving = side;
        // the module's background opacity is the plate's real opacity (11-13 user, "背景可以"; 100% is solid)
        var look = s.ModuleOpacity.GetValueOrDefault(id, OverlayVisorModuleOpacity.Full);
        _dc.Target = l.HazeMask; _dc.BeginDraw(); _dc.Clear(new Color4(0, 0, 0, 0));
        _dc.Transform = tr;
        if (id == "top") _p.Fill(OverlayVisorDraw.TopWidth / 2 - 240, 56, 480, 96, new Color4(0, 0, 0, 1), TopHaze(st.Haze * 0.85f, look.Background));
        else if (id != "dm")
        {
            const float e = 10;
            // when dissolving, the haze reaches further toward the centre so there is something to fade out
            var reach = dissolving ? DissolveReach : 0;
            var left = -e - (l.Right ? reach : 0);
            // a very faint plate in the decoration colour (11-12 "颜色应该影响背景"; the chat goes without one when its
            // plate is turned off)
            if (!(id == "chat" && !s.ChatPlate))
            {
                var (dark, tint) = Plate(look.Background);
                if (dark > 0) _p.Fill(left, -e, drawWidth + 2 * e + reach, h + 2 * e, PlateColor(st.Deco), dark);
                _p.Fill(left, -e, drawWidth + 2 * e + reach, h + 2 * e, st.Deco, tint);
            }
        }
        _dc.Transform = Matrix3x2.Identity;
        _dc.EndDraw().CheckError();
        DrawDissolveMask(l, tr, drawWidth, h, dissolving);

        // the frame: haze, the dark bed, its tight shadow, the frame itself and its glow. The module's background opacity
        // takes the haze, its decoration opacity the rest (user, 11-10: "分模块都让面罩用上")
        _dc.Target = l.Combined; _dc.BeginDraw(); _dc.Clear(new Color4(0, 0, 0, 0));
        DrawOutput(l.HazeBlur);
        WithOpacity(look.Decoration, () =>
        {
            DrawOutput(l.Bed);
            DrawOutput(l.Shadow); _dc.DrawImage(l.Shapes);
            DrawOutput(l.GameShapeGlow, compositeMode: CompositeMode.Plus);
        });
        _dc.EndDraw().CheckError();
        // the text: a thin dark edge and a faint glow
        _dc.Target = l.TextCombined; _dc.BeginDraw(); _dc.Clear(new Color4(0, 0, 0, 0));
        DrawOutput(l.TextShadow); _dc.DrawImage(l.Text);
        DrawOutput(l.GameTextGlow, compositeMode: CompositeMode.Plus);
        _dc.EndDraw().CheckError();
        _dc.Target = null;

        // flat groups never turn; side groups get their camera once they have a place on screen (Place)
        foreach (var persp in new[] { l.Persp, l.TextPersp, l.MarqueePersp }) persp.SetValue((int)PerspectiveTransform3DProperties.Rotation, new Vector3(0, 0, 0));
        l.ContentH = h; l.SpaceKey = ""; Redraws++;
        return h;
    }

    private static List<string> Visible(OverlayVisorScene s)
    {
        var v = new List<string>();
        if (s.ShowTeam) v.Add("team");
        if (s.ShowEvents && s.Events.Count > 0) v.Add("events");
        if (s.ShowChat && s.Chat.Count > 0) v.Add("chat");
        if (s.ShowNotice) v.Add("top");
        if (s.DirectMessage is not null) v.Add("dm");
        return v;
    }

    /// <summary>Redraws what changed and draws the frame into <paramref name="target"/> (pixel units, DPI 96).</summary>
    public void Render(ID2D1Bitmap1 target, Vector2 offset, OverlayVisorScene s, int pixelWidth, int pixelHeight, double now)
    {
        var scale = pixelHeight / 1080f;
        var layoutWidth = pixelWidth / scale;
        var g = Compact * s.Style.SizeFactor;
        var k = scale * g;
        var kL = k * Supersample;
        Build(kL, s.Style);
        var noticeKey = s.ShowNotice ? $"{s.NoticeTitle}|{s.NoticeBody}" : "";
        if (noticeKey != _noticeKey) { _noticeKey = noticeKey; _noticeAt = noticeKey.Length > 0 ? now : double.NegativeInfinity; }

        var vis = Visible(s);
        // a hidden members group has nothing to wait for: the columns start again from its content when it comes back
        if (vis.Contains("team")) Columns(s, now); else _columns.Reset();
        foreach (var id in new[] { "events", "chat" })
            if (vis.Contains(id)) GroupWidth(id, s, now); else _groupDebounce[id].Reset();
        var eff = new Dictionary<string, OverlayVisorSpot>(s.Spots);
        for (var pass = 0; pass < 2; pass++)
        {
            foreach (var id in vis)
            {
                var l = _layers[id];
                var right = id switch { "top" => false, "dm" => s.Badge.RightAligned, _ => eff[id].RightAligned };
                // side panels tilt toward their edge; a group the user placed freely tilts toward its anchored side
                var tilt = id is "team" or "events" or "chat" && (eff[id].Free || OverlayVisorLayout.IsSideSlot(eff[id].Slot!));
                // The style is part of the key: a palette or look change redraws once; an idle scene still redraws nothing.
                var look = s.ModuleOpacity.GetValueOrDefault(id, OverlayVisorModuleOpacity.Full);
                var sig = Sig(s, id) + $"|{right}|{tilt}|{kL}|{s.Style.GetHashCode()}|{s.ChatPlate}|{look.Background:F3}|{look.Decoration:F3}" +
                    (id == "team" ? $"|{string.Join(",", _teamColumns.Select(c => c.ToString("F1")))}|{_columns.Narrowing}|{_teamBox}|{s.MembersAutoHeight}" : "") +
                    (id is "events" or "chat" ? $"|{_groupWidth[id]:F1}|{_groupBox[id]}|{_groupDebounce[id].Narrowing}" : "") + (id == "top" && OverlayVisorDraw.TopAnimating(now - _noticeAt) ? $"|{now:F3}" : "");
                if (right != l.Right || tilt != l.Tilt || sig != l.Signature) { l.Right = right; l.Tilt = tilt; l.Signature = sig; DrawLayer(id, l, s, kL, now); }
            }
            // the members are placed by their box (the maximum, or the fixed size) and the events, whenever they are on,
            // by their three-line height, so nothing moves when members or events come and go (review R4)
            // events and chat (11-07 "2放") by their width box and the height of their most lines, whenever they are on.
            // "On" is their setting, not whether they show something right now: an event or a chat line arriving must
            // not push the members (build 86)
            var placedGroups = vis.Where(id => id is "team").ToList();
            // (what shows is always placed; switched on, the place is kept while there is nothing to show)
            if (s.ShowEvents || s.EventsPlaced == true) placedGroups.Add("events");
            if (s.ShowChat || s.ChatPlaced == true) placedGroups.Add("chat");
            var sizes = placedGroups.ToDictionary(id => id, id => id switch
            {
                "team" => (_teamBox.W * g, _teamBox.H * g),
                "events" => (s.EventsWidth * g, OverlayVisorDraw.EventsBoxHeight(s.EventsCount) * g),
                _ => (s.ChatWidth * g, MathF.Max(OverlayVisorLayout.ChatMinHeight, OverlayVisorDraw.ChatBoxHeight(s.ChatCount) * g)),
            });
            Positions = OverlayVisorLayout.Arrange(eff, sizes, layoutWidth);
            Sizes = sizes;
            if (!vis.Any(id => id is "team" or "events" or "chat" && eff[id].RightAligned != _layers[id].Right)) break;
        }
        // Top centre, or bottom centre: the band's lower edge just above the game's speed readout (starts at
        // 860) and its text (from 52 design units down) below the crosshair area (ends at 760).
        if (vis.Contains("top")) Positions["top"] = (layoutWidth / 2 - OverlayVisorDraw.TopWidth * g / 2, s.RallyBottom ? 858 - 180 * g : 84 - 60 * g);
        if (vis.Contains("dm"))
        {
            float w = OverlayVisorDraw.Width * g, h = 30 * g;
            // A free badge hangs from its saved edge: its text reads from that edge (DrawLayer mirrors on the right).
            var (x, y) = s.Badge.Free ? s.Badge.Corner(w, h) : OverlayVisorLayout.DirectMessageBadge(w, h, layoutWidth);
            Positions["dm"] = (Math.Clamp(x, -w, layoutWidth), Math.Clamp(y, OverlayVisorLayout.ScreenMargin, 1080 - OverlayVisorLayout.ScreenMargin - h));
            Sizes["dm"] = (w, h);
        }

        float Calm(string id) => id switch { "team" => s.TeamCalm, "events" => s.EventsCalm, "chat" => s.ChatCalm, "top" => s.NoticeCalm, _ => 1 };
        _intro = (s.OpenAt, s.CloseAt);
        foreach (var id in vis)
        {
            // the module's text opacity takes its text (and the live layer: scrolling text, the health ring)
            var shown = Math.Clamp(Calm(id) * s.Opacity, 0, 1);
            var text = s.ModuleOpacity.GetValueOrDefault(id, OverlayVisorModuleOpacity.Full).Text;
            _layers[id].Fade.Value = shown;
            _layers[id].TextFade.Value = _layers[id].MarqueeFade.Value = shown * Math.Clamp(text, 0, 1);
        }
        // Scrolling fields: offsets follow the clock; a scroll layer is redrawn only when an offset moved, at most
        // 30 times a second. Everything else is only composed.
        _scrolling = false; ScrollFields = 0; _ringsBusy = false; LastFrameRingComposed = false;
        Dictionary<string, OverlayVisorMember>? current = null;
        if (vis.Contains("team") && _layers.TryGetValue("team", out var team))
        {
            // members no longer on the panel are forgotten; coming back they are shown as they are, without motion
            var onPanel = team.Rings.Select(r => r.Key).ToHashSet();
            foreach (var gone in _ringMotion.Keys.Where(k => !onPanel.Contains(k)).ToList()) _ringMotion.Remove(gone);
        }
        foreach (var id in vis)
        {
            var l = _layers[id];
            if (l.Scrolls.Length == 0 && l.Rings.Length == 0)
            {
                if (l.LiveDrawn) ClearLive(l);
                continue;
            }
            if (l.Scrolls.Length > 0) { _scrolling = true; ScrollFields += l.Scrolls.Length; }
            var offsets = ScrollOffsets(l.Scrolls, now);
            if (l.Rings.Length > 0) current ??= s.Members.GroupBy(m => m.Name).ToDictionary(g => g.Key, g => g.First());
            var rings = new OverlayVisorDraw.HealthLook[l.Rings.Length];
            var ringsMoving = false;
            for (var i = 0; i < l.Rings.Length; i++)
            {
                var spot = l.Rings[i];
                var (look, busy) = StepRing(spot.Key, current!.GetValueOrDefault(spot.Key, spot.Member), now);
                rings[i] = look; ringsMoving |= busy;
            }
            _ringsBusy |= ringsMoving;
            var key = string.Join(",", offsets.Select(o => MathF.Round(o * 4))) + "|" +
                string.Join(",", rings.Select(r => $"{r.Vitals}{(r.Fraction > 0.5f ? 2 : r.Fraction >= 0.25f ? 1 : 0)}{MathF.Round(r.Fraction * 240)}:{MathF.Round(r.Alpha * 40)}:{MathF.Round(r.Flash * 40)}:{MathF.Round(r.Glow * 40)}"));
            // at most 30 redraws a second while moving; the settled look is always drawn
            if (key == l.ScrollKey || ((_scrolling || ringsMoving) && now - l.ScrollAt < 1 / 30.0 && l.ScrollKey.Length > 0)) continue;
            l.ScrollKey = key; l.ScrollAt = now; ScrollRedraws++;
            DrawScrolls(l, offsets, rings, s.Style);
        }

        // whole pixels, so the scaled-down layers do not shimmer between frames
        (float X, float Y) Corner((float X, float Y) pos) => (MathF.Round(pos.X * scale - Pad * k), MathF.Round(pos.Y * scale - Pad * k));
        Tilted.Clear();
        foreach (var id in vis)
            if (_layers[id].Tilt && Positions.TryGetValue(id, out var at))
            {
                Place(_layers[id], Corner(at), s.Style.Tilt, s.Style.Distance, scale, pixelWidth, pixelHeight);
                Tilted[id] = _layers[id].Right;
            }

        _dc.Target = target; _dc.BeginDraw(); _dc.Clear(new Color4(0, 0, 0, 0));
        var off = Matrix3x2.CreateTranslation(offset);
        // the opening or closing: the frame first (behind the panels), then each group on its beat
        var openT = double.IsFinite(s.OpenAt) ? now - s.OpenAt : double.PositiveInfinity;
        var closeT = double.IsFinite(s.CloseAt) ? now - s.CloseAt : double.NegativeInfinity;
        var opening = openT >= 0 && openT < Durations.Open + 0.1;
        var closingNow = closeT >= 0 && closeT < Durations.Close + 0.1;
        if (opening || closingNow)
        {
            _dc.Transform = off;
            DrawBracket(s, opening ? openT : double.PositiveInfinity, closingNow ? closeT : double.NegativeInfinity, pixelWidth, pixelHeight);
        }
        foreach (var id in Order)
        {
            if (!vis.Contains(id) || !Positions.TryGetValue(id, out var pos)) continue;
            if (Only is not null && id != Only) continue;
            var (x, y) = Corner(pos);
            _dc.Transform = Matrix3x2.CreateScale(1f / Supersample) * Matrix3x2.CreateTranslation(x, y) * off;
            if (closeT >= 0 || opening)
            {
                if (id == "team") IntroFrames++;
                if (id is "team" or "events" or "chat") DrawPanelOnBeat(_layers[id], kL, _dc.Transform, openT, closeT);
                else if (CentreGroupFx(openT, closeT) is var fx && (fx.Panel > 0 || fx.Text > 0)) DrawFx(_layers[id], fx, kL, _dc.Transform);
                continue;
            }
            DrawOutput(_layers[id].Fade, interpolationMode: InterpolationMode.HighQualityCubic);
            DrawOutput(_layers[id].TextFade, interpolationMode: InterpolationMode.HighQualityCubic);
            if (_layers[id].Scrolls.Length > 0 || _layers[id].Rings.Length > 0)
            {
                DrawOutput(_layers[id].MarqueeFade, interpolationMode: InterpolationMode.HighQualityCubic);
                // the layer as last drawn, not this frame's rings: a redraw held back by the 30-a-second limit composes the
                // older layer (review CX-HUD-RINGFLICKER-073-R3 P2)
                if (id == "team" && _layers[id].RingLive && _layers[id].Rings.Length > 0) LastFrameRingComposed = true;
            }
        }
        _dc.Transform = Matrix3x2.Identity;
        _dc.EndDraw().CheckError();
        _dc.Target = null;
    }

    /// <summary>How far (design units) the dissolve runs past the content toward the screen centre.</summary>
    private const float DissolveReach = 56;

    /// <summary>
    /// The dissolve mask: solid over the content and the screen-edge side, fading out over DissolveReach past the side
    /// toward the centre (user, 11-07: "渐隐", a plain linear fade). A group that does not dissolve gets a solid mask. Drawn once per content change, never per frame.
    /// </summary>
    private void DrawDissolveMask(Layer l, Matrix3x2 tr, float width, float h, bool dissolving)
    {
        _dc.Target = l.DissolveMask; _dc.BeginDraw(); _dc.Clear(new Color4(0, 0, 0, dissolving ? 0 : 1));
        if (dissolving)
        {
            _dc.Transform = tr;
            const float big = 2000;
            float innerEdge = l.Right ? 0 : width, fadeEnd = l.Right ? -DissolveReach : width + DissolveReach;
            using var solid = _dc.CreateSolidColorBrush(new Color4(1, 1, 1, 1));
            _dc.FillRectangle(l.Right ? new Rect(innerEdge, -big, big, 2 * big) : new Rect(-big, -big, big + innerEdge, 2 * big), solid);
            using var stops = _dc.CreateGradientStopCollection([new GradientStop(0, new Color4(1, 1, 1, 1)), new GradientStop(1, new Color4(1, 1, 1, 0))]);
            using var fade = _dc.CreateLinearGradientBrush(new LinearGradientBrushProperties(new(innerEdge, 0), new(fadeEnd, 0)), stops);
            _dc.FillRectangle(new Rect(MathF.Min(innerEdge, fadeEnd), -big, DissolveReach, 2 * big), fade);
            _dc.Transform = Matrix3x2.Identity;
        }
        _dc.EndDraw().CheckError();
        _dc.Target = null;
    }

    /// <summary>
    /// Sets up the one camera for a side group whose layer's top-left lands at <paramref name="corner"/> (screen
    /// pixels): the hinge is the screen edge on the group's side, the perspective origin the screen centre, the depth
    /// the viewing distance. Layer pixels are screen pixels times the supersampling, measured from the corner.
    /// Only redone when the place, the angle, the distance or the screen changes.
    /// </summary>
    /// <param name="scale">Screen pixels per design unit of a 1080-high screen; the visor size does not change the camera.</param>
    /// <param name="distance">The viewing distance in design units (the style's, 1000 unless set).</param>
    private static void Place(Layer l, (float X, float Y) corner, float degrees, float distance, float scale, int pixelWidth,
        int pixelHeight)
    {
        var key = $"{corner.X}|{corner.Y}|{degrees}|{distance}|{scale}|{pixelWidth}|{pixelHeight}|{l.Right}";
        if (key == l.SpaceKey) return;
        l.SpaceKey = key;
        var hinge = ((l.Right ? pixelWidth : 0) - corner.X) * Supersample;
        var centre = new Vector2((pixelWidth / 2f - corner.X) * Supersample, (pixelHeight / 2f - corner.Y) * Supersample);
        foreach (var persp in new[] { l.Persp, l.TextPersp, l.MarqueePersp })
        {
            persp.SetValue((int)PerspectiveTransform3DProperties.Depth, distance * scale * Supersample);
            persp.SetValue((int)PerspectiveTransform3DProperties.PerspectiveOrigin, centre);
            persp.SetValue((int)PerspectiveTransform3DProperties.RotationOrigin, new Vector3(hinge, centre.Y, 0));
            persp.SetValue((int)PerspectiveTransform3DProperties.Rotation, new Vector3(0, l.Right ? -degrees : degrees, 0));
        }
    }

    /// <summary>
    /// The member columns for this frame (user, 11-07: "固定位置会导致空间浪费，随动又会上下对不齐"): each column is as
    /// wide as its longest entry among the members shown, up to its cap, and every row uses that width. The group is as
    /// wide as the columns, but never narrower than its title and counts.
    /// </summary>
    /// <remarks>
    /// 11-07 members size: the column caps scale with the members width (at the default width they are the measured
    /// caps). Width adaptive: each column follows its longest entry up to its cap, and the group is never wider than the
    /// width. Width fixed: the group keeps the width and the columns share it in the caps' proportion; longer entries
    /// scroll either way.
    /// </remarks>
    private void Columns(OverlayVisorScene s, double now)
    {
        _teamBox = (s.MembersWidth, s.MembersHeight);
        var specs = OverlayVisorDraw.MemberColumns;
        var room = s.MembersWidth - OverlayVisorDraw.RowInset - OverlayVisorDraw.ColumnGap * (specs.Length - 1);
        var share = room / specs.Sum(c => c.Cap);
        var caps = specs.Select(c => MathF.Floor(c.Cap * share)).ToArray();
        if (!s.MembersAutoWidth)
        {
            _columns.Reset();
            _teamColumns = caps;
            _teamWidth = s.MembersWidth;
            return;
        }
        var measure = new OverlayVisorDraw(_p, s.Style, false, now);
        var natural = measure.NaturalColumns(s.Members);
        var target = natural.Select((w, i) => MathF.Ceiling(MathF.Min(w, caps[i]))).ToArray();
        // a lower maximum applies at once (review R3); only content getting shorter waits before narrowing
        _columns.Clamp(caps);
        _teamColumns = [.. _columns.Update(target, now)];
        _teamWidth = MathF.Min(s.MembersWidth, MathF.Max(OverlayVisorDraw.TeamWidth(_teamColumns), MathF.Ceiling(measure.HeaderWidth(s))));
    }

    /// <summary>
    /// The events or chat width for this frame (11-07 "2放"), by the members' rule: adaptive follows the widest line up
    /// to the width (wider at once, narrower after the lines settle), fixed keeps the width; longer text scrolls.
    /// </summary>
    private void GroupWidth(string id, OverlayVisorScene s, double now)
    {
        var (auto, box) = id == "events" ? (s.EventsAutoWidth, s.EventsWidth) : (s.ChatAutoWidth, s.ChatWidth);
        _groupBox[id] = box;
        var debounce = _groupDebounce[id];
        if (!auto) { debounce.Reset(); _groupWidth[id] = box; return; }
        var measure = new OverlayVisorDraw(_p, s.Style, false, now);
        var natural = id == "events" ? measure.EventsNaturalWidth(s) : measure.ChatNaturalWidth(s);
        debounce.Clamp([box]);
        _groupWidth[id] = debounce.Update([MathF.Ceiling(MathF.Min(natural, box))], now)[0];
    }

    // Scroll timing (design units): wait, scroll slowly to the end, wait, scroll back three times as fast.
    private const float ScrollHold = 1.75f, ScrollEndHold = 1.0f, ScrollSpeed = 28f, ScrollTail = 8f;

    /// <summary>
    /// Scroll offsets for a group's fields at <paramref name="now"/>. The fields are dealt, in row order, to
    /// <see cref="MaxScrolling"/> lanes and each lane plays its fields in turn, so at most that many move at once;
    /// lanes start 2.3 s apart.
    /// </summary>
    internal static float[] ScrollOffsets(IReadOnlyList<OverlayVisorDraw.ScrollField> fields, double now)
    {
        var offsets = new float[fields.Count];
        var lanes = fields.Select((f, i) => (f, i)).OrderBy(x => x.f.Row).ThenBy(x => x.f.Order)
            .Select((x, n) => (x, lane: n % MaxScrolling)).GroupBy(x => x.lane, x => x.x);
        static float Distance(OverlayVisorDraw.ScrollField f) => f.TextW - f.W + ScrollTail;
        static float Cycle(OverlayVisorDraw.ScrollField f) => ScrollHold + Distance(f) / ScrollSpeed + ScrollEndHold + Distance(f) / (ScrollSpeed * 3);
        foreach (var lane in lanes)
        {
            var turn = lane.ToArray();
            var total = turn.Sum(x => Cycle(x.f));
            var phase = (float)((now + lane.Key * 2.3) % total);
            foreach (var (f, i) in turn)
            {
                var c = Cycle(f);
                if (phase >= c) { phase -= c; continue; }
                var d = Distance(f);
                var run = d / ScrollSpeed;
                offsets[i] = phase < ScrollHold ? 0
                    : phase < ScrollHold + run ? (phase - ScrollHold) * ScrollSpeed
                    : phase < ScrollHold + run + ScrollEndHold ? d
                    : MathF.Max(0, d - (phase - ScrollHold - run - ScrollEndHold) * ScrollSpeed * 3);
                break;
            }
        }
        return offsets;
    }

    /// <summary>Draws the scrolling fields flat into their layer, clipped, with the cut sides faded out.</summary>
    /// <summary>Empties the live layer once it has nothing left (it is still composed while opening or closing).</summary>
    private void ClearLive(Layer l)
    {
        foreach (var bitmap in new[] { l.Marquee, l.MarqueeCombined })
        {
            _dc.Target = bitmap; _dc.BeginDraw(); _dc.Clear(new Color4(0, 0, 0, 0)); _dc.EndDraw().CheckError();
        }
        _dc.Target = null;
        l.LiveDrawn = false; l.RingLive = false; l.ScrollKey = ""; LiveClears++;
    }

    private void DrawScrolls(Layer l, float[] offsets, OverlayVisorDraw.HealthLook[] rings, OverlayVisorStyle st)
    {
        l.LiveDrawn = true;
        l.RingLive = rings.Any(r => r.Vitals != OverlayVisorVitals.Unknown);
        _dc.Target = l.Marquee; _dc.BeginDraw(); _dc.Clear(new Color4(0, 0, 0, 0));
        _dc.Transform = l.ScrollTransform; _p.Base = l.ScrollTransform; _p.Alpha = 1;
        for (var i = 0; i < l.Scrolls.Length; i++)
        {
            var f = l.Scrolls[i];
            var o = offsets[i];
            var d = f.TextW - f.W + ScrollTail;
            const float fade = 12;
            var e = MathF.Min(0.45f, fade / f.W);
            var leftAlpha = o > 0.5f ? 0f : 1f; var rightAlpha = o < d - 0.5f ? 0f : 1f;
            using var stops = _dc.CreateGradientStopCollection([new GradientStop(0, new Color4(1, 1, 1, leftAlpha)), new GradientStop(e, new Color4(1, 1, 1, 1)),
                new GradientStop(1 - e, new Color4(1, 1, 1, 1)), new GradientStop(1, new Color4(1, 1, 1, rightAlpha))]);
            using var mask = _dc.CreateLinearGradientBrush(new LinearGradientBrushProperties(new(f.X, 0), new(f.X + f.W, 0)), stops);
            var top = f.Y - 4; var bottom = f.Y + OverlayVisorPainter.DrawnSize(f.Run.Size) * 1.7f + 4;
            _dc.PushLayer(new LayerParameters1 { ContentBounds = new Vortice.RawRectF(f.X, top, f.X + f.W, bottom), MaskAntialiasMode = AntialiasMode.PerPrimitive,
                MaskTransform = Matrix3x2.Identity, Opacity = 1, OpacityBrush = mask, LayerOptions = LayerOptions1.None }, null);
            _p.Draw(f.Run, f.X - o, f.Y);
            _dc.PopLayer();
        }
        _dc.Transform = Matrix3x2.Identity; _p.Base = Matrix3x2.Identity;
        _dc.EndDraw().CheckError();
        _dc.Target = l.MarqueeCombined; _dc.BeginDraw(); _dc.Clear(new Color4(0, 0, 0, 0));
        DrawOutput(l.MarqueeShadow); _dc.DrawImage(l.Marquee);
        // the health rings over it, without the text's dark edge (on a thin ring it reads as a dark spot)
        _dc.Transform = l.ScrollTransform; _p.Base = l.ScrollTransform; _p.Alpha = 1; _p.Pass = OverlayVisorPass.All;
        for (var i = 0; i < l.Rings.Length; i++) OverlayVisorDraw.HealthRing(_p, st, l.Rings[i].X, l.Rings[i].Y, rings[i]);
        _dc.Transform = Matrix3x2.Identity; _p.Base = Matrix3x2.Identity;
        _dc.EndDraw().CheckError();
        _dc.Target = null;
    }

    /// <summary>
    /// Where a point of a side plane lands on screen (screen pixels): <paramref name="u"/> along the plane from the
    /// screen edge, <paramref name="y"/> down, with the camera of <see cref="Place"/>. Shared with the tests.
    /// </summary>
    internal static Vector2 SpacePoint(bool right, float u, float y, float degrees, float distance, int w, int h)
    {
        var a = degrees * MathF.PI / 180;
        var x = right ? w - u * MathF.Cos(a) : u * MathF.Cos(a);
        var f = distance / (distance + u * MathF.Sin(a));
        return new Vector2(w / 2f + (x - w / 2f) * f, h / 2f + (y - h / 2f) * f);
    }

    // Vortice adds a COM reference every time Output is read. One that is never released keeps the effect, the device
    // context and the whole D3D11 device alive after the HUD closes (about 50 NVIDIA driver threads per device, 11-08).
    private static void Chain(ID2D1Effect to, ID2D1Effect from)
    {
        using var output = from.Output;
        to.SetInput(0, output, true);
    }

    private void DrawOutput(ID2D1Effect effect, InterpolationMode interpolationMode = InterpolationMode.Linear,
        CompositeMode compositeMode = CompositeMode.SourceOver)
    {
        using var output = effect.Output;
        _dc.DrawImage(output, interpolationMode: interpolationMode, compositeMode: compositeMode);
    }


    public void Dispose()
    {
        DisposeFx();
        foreach (var l in _layers.Values) l.Dispose();
        _layers.Clear();
        _p.Dispose();
    }
}

/// <summary>
/// Column widths that do not jump about (user, 11-07): a column that needs more room widens at once; one that needs
/// less waits until the wanted widths have stayed the same for <see cref="SettleSeconds"/>, then eases narrower over
/// <see cref="NarrowSeconds"/>. A change while waiting or easing starts the wait again from where the columns are.
/// Works for any number of columns, so later columns follow the same rule.
/// </summary>
internal sealed class OverlayVisorColumnWidths
{
    public const double SettleSeconds = 5, NarrowSeconds = 0.3;
    private float[] _shown = [], _wanted = [], _from = [];
    private double _changedAt = double.NegativeInfinity, _narrowAt = double.NaN;

    public bool Narrowing => !double.IsNaN(_narrowAt);
    public bool Waiting { get; private set; }
    /// <summary>True while a narrowing is waiting or easing: the frame scheduler keeps ticking.</summary>
    public bool Busy => Narrowing || Waiting;

    /// <summary>A lower cap applies at once: no column is shown (or eases from) wider than its cap.</summary>
    public void Clamp(float[] caps)
    {
        if (_shown.Length != caps.Length) return;
        for (var i = 0; i < caps.Length; i++)
        {
            _shown[i] = MathF.Min(_shown[i], caps[i]);
            if (_from.Length == caps.Length) _from[i] = MathF.Min(_from[i], caps[i]);
        }
    }

    /// <summary>Forgets the shown widths: the next update starts from what it wants, with nothing waiting.</summary>
    public void Reset() { _shown = []; _wanted = []; _from = []; _narrowAt = double.NaN; Waiting = false; }

    public float[] Update(float[] wanted, double now)
    {
        if (_shown.Length != wanted.Length) { _shown = [.. wanted]; _wanted = [.. wanted]; _narrowAt = double.NaN; Waiting = false; return _shown; }
        if (!wanted.SequenceEqual(_wanted)) { _wanted = [.. wanted]; _changedAt = now; _narrowAt = double.NaN; }
        for (var i = 0; i < wanted.Length; i++) if (wanted[i] > _shown[i]) _shown[i] = wanted[i];
        if (!wanted.Where((w, i) => w < _shown[i] - 0.01f).Any()) { Waiting = false; _narrowAt = double.NaN; return _shown; }
        if (!Narrowing)
        {
            if (now - _changedAt < SettleSeconds) { Waiting = true; return _shown; }
            Waiting = false; _narrowAt = now; _from = [.. _shown];
        }
        var t = (float)Math.Clamp((now - _narrowAt) / NarrowSeconds, 0, 1);
        var e = 1 - MathF.Pow(1 - t, 3);
        for (var i = 0; i < wanted.Length; i++) if (wanted[i] < _from[i]) _shown[i] = _from[i] + (wanted[i] - _from[i]) * e;
        if (t >= 1) _narrowAt = double.NaN;
        return _shown;
    }
}
