namespace StarBridge.OverlayRuntime.Windows;

using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using FontFamily = System.Windows.Media.FontFamily;
using Pen = System.Windows.Media.Pen;
using Point = System.Windows.Point;

internal sealed partial class AchievementCelebrationCard
{
    internal const double CutWidth = 22, CutHeight = 12;
    private const double TextX = 114, TextWidth = CardWidth - TextX - 18, ArtSize = 80;
    private const double RefractionRun = CardHeight * CutWidth / CutHeight;
    private static readonly Rect Plate = new(0, 0, CardWidth, CardHeight);
    private static readonly Rect Art = new(18, 14, ArtSize, ArtSize);
    private static readonly Rect Etch = new(CardWidth + 20 - 188, (CardHeight - 188) / 2, 188, 188);
    private static readonly Geometry Outline = Polygon(new(CutWidth, 0), new(CardWidth, 0),
        new(CardWidth, CardHeight), new(CutWidth, CardHeight), new(0, CardHeight - CutHeight), new(0, CutHeight));
    private static readonly Lazy<ImageSource?> DarkMark = new(() => Load("startup_meteor_mark.png", "Brand"));
    private static readonly Lazy<ImageSource?> LightMark = new(() => Load("notification_mark_light.png", "Brand"));
    private static readonly Lazy<ImageSource?> Star = new(() => Load("startup_meteor_star.png", "Brand"));

    private sealed record Palette(Color Main, Color Secondary, Color Seam, double SeamAlpha, double EdgeAlpha, double EtchAlpha)
    {
        internal static Palette Create(bool light, int tier) => (light, tier) switch
        {
            (true, 2) => new(Hex(0xA8740A), Hex(0xD9A23A), Hex(0xA8740A), .95, .85, .22),
            (true, 1) => new(Hex(0x1580B0), Hex(0x2F6BFF), Hex(0x1580B0), .80, .65, .16),
            (true, _) => new(Hex(0x5E7888), Hex(0x1580B0), Hex(0x1580B0), .55, .40, .08),
            (false, 2) => new(Hex(0xF2C35B), Hex(0xFFE3A1), Hex(0xF2C35B), .95, .85, .22),
            (false, 1) => new(Hex(0x54C7EA), Hex(0x2F7BFF), Hex(0x54C7EA), .80, .65, .16),
            _ => new(Hex(0xB9CCD8), Hex(0x54C7EA), Hex(0x5E7888), .55, .40, .08)
        };
    }

    private sealed record GlassCache(double Scale, BitmapSource Unlit, BitmapSource Lit, BitmapSource? Glow,
        Dictionary<int, (DrawingGroup Unlit, DrawingGroup Lit, DrawingGroup? Glow)> SummaryNames);
    private GlassCache? _glass;
    private double _elapsed;
    private bool _hasFrame;
    private int _remaining;
    private DrawingGroup? _queueLabel;
    private ImageSource? Mark => _light ? LightMark.Value : DarkMark.Value;
    private double LightStrength => _light ? .55 : 1;
    private bool IsStill(double ms) => ms < LifetimeMilliseconds &&
        (_reduced || ms >= EntryMilliseconds && ms <= EntryMilliseconds + HoldMilliseconds);

    internal void Advance(double elapsed, int remaining)
    {
        var oldElapsed = _elapsed;
        // A queue change during the hold must not cause a repaint. Keep the
        // count visible at the end of the entrance until the card is dismissed.
        var queueChanged = (!_hasFrame || !_reduced && oldElapsed < EntryMilliseconds) && _remaining != remaining;
        if (queueChanged)
        {
            _remaining = remaining;
            _queueLabel = null;
        }
        _hasFrame = true;
        _elapsed = elapsed;
        if (queueChanged || elapsed != oldElapsed && !(IsStill(elapsed) && IsStill(oldElapsed))) InvalidateVisual();
    }

    // Called while the HWND is hidden and whenever its target scale changes.
    // The animation composites two complementary clips of opaque-or-translucent
    // pixels in the caches. Neither clip paints over the other.
    internal void PrepareGlass(double scale)
    {
        if (_glass?.Scale == scale) return;
        var layout = MeasureText(scale);
        var names = new Dictionary<int, (DrawingGroup, DrawingGroup, DrawingGroup?)>();
        if (_summaryCount > 0)
        {
            foreach (var count in Enumerable.Range(0, 21).Select(step => SummaryCountAt(420 + step * 17)).Distinct())
            {
                var name = SummaryName(count);
                names[count] = (
                    Drawing(dc => DrawName(dc, layout, false, name)),
                    Drawing(dc => DrawName(dc, layout, true, name)),
                    _reduced ? null : Drawing(dc => DrawNameGlow(dc, layout, name)));
            }
        }
        if (!_reduced && RarityLevel == 2) _ = Star.Value;
        _glass = new(scale, Bake(scale, dc => DrawGlass(dc, layout, _palette, false)),
            Bake(scale, dc => DrawGlass(dc, layout, _palette, true)),
            _reduced ? null : Bake(scale, dc => DrawEngravingGlow(dc, layout)), names);
        _queueLabel = null;
        InvalidateVisual();
    }

    private void DrawGlass(DrawingContext dc, TextLayout text, Palette palette, bool lit)
    {
        dc.PushClip(Outline);
        var white = Colors.White;
        var black = Colors.Black;
        var opacity = _light ? .95 : .93;
        dc.DrawRectangle(Gradient(Hex(_light ? 0xF4F7FA : 0x0E151C), opacity,
            Hex(_light ? 0xE4EBF0 : 0x06090D), opacity, vertical: true), null, Plate);
        Line(dc, white, _light ? .85 : .16, 1, CutWidth, .5, CardWidth, .5);
        dc.DrawRectangle(Gradient(black, _light ? .14 : .32, black, 0, vertical: true), null, new(0, 1, CardWidth, 4));
        Line(dc, white, _light ? .54 : .045, 1, CutWidth + 3, 4.5, CardWidth, 4.5);
        Line(dc, white, _light ? .50 : .06, 1, CutWidth, CardHeight - 2.5, CardWidth, CardHeight - 2.5);
        Line(dc, black, _light ? .15 : .60, 1, CutWidth, CardHeight - .5, CardWidth, CardHeight - .5);
        dc.DrawRectangle(Gradient(white, 0, white, _light ? .62 : .07), null, new(CardWidth - 26, 0, 26, CardHeight));
        dc.DrawGeometry(Brush(white, _light ? .34 : .025), null,
            Polygon(new(314, 0), new(350, 0), new(350 - RefractionRun, CardHeight), new(314 - RefractionRun, CardHeight)));

        var etchTint = _light ? Hex(0x203344) : !lit || RarityLevel == 0 ? white : palette.Main;
        DrawEtch(dc, etchTint, lit ? palette.EtchAlpha : .05, shadow: true);
        DrawArtwork(dc, palette, lit);
        var title = English ? "ACHIEVEMENT UNLOCKED" : Traditional ? "成就已解鎖" : "成就已解锁";
        Engrave(dc, title, 10.5, true, text.Top, palette.Main, .6, lit, text.Scale);
        if (_summaryCount == 0) DrawName(dc, text, lit, _name);
        Engrave(dc, _memory, 11.5, false, text.MemoryY, Hex(_light ? 0x536875 : 0xAABCC7), .5, lit, text.Scale, 2);
        Engrave(dc, RarityLine, 10.5, true, text.RarityY, RarityLevel == 0 ? Hex(_light ? 0x536875 : 0x91A5B2) : palette.Main,
            .5, lit, text.Scale);
        dc.Pop();
    }

    private void DrawEtch(DrawingContext dc, Color tint, double alpha, bool shadow)
    {
        if (Mark is not { } mark) return;
        var mask = new ImageBrush(mark) { Stretch = Stretch.Uniform };
        mask.Freeze();
        if (shadow)
        {
            var inset = Etch;
            inset.Offset(1, 1);
            dc.PushOpacityMask(mask);
            dc.DrawRectangle(Gradient(Colors.Black, 0, Colors.Black, alpha * .65), null, inset);
            dc.Pop();
        }
        dc.PushOpacityMask(mask);
        dc.DrawRectangle(Gradient(tint, alpha * .12, tint, alpha), null, Etch);
        dc.Pop();
    }

    private void DrawArtwork(DrawingContext dc, Palette palette, bool lit)
    {
        dc.PushClip(new RectangleGeometry(Art));
        dc.DrawRectangle(Brush(Hex(_light ? 0xD2DCE4 : 0x030508)), null, Art);
        var artwork = _earned is null ? null : lit ? _earned : _locked ?? _earned;
        if (artwork is not null) dc.DrawImage(artwork, Art);
        else if (Mark is { } mark)
        {
            dc.PushOpacity(lit ? 1 : .30);
            var bounds = Rect.Inflate(Art, -12, -12);
            dc.DrawImage(mark, FitImage(mark, bounds));
            dc.Pop();
        }
        var sheen = Gradient(Colors.White, _light ? .36 : .17, Colors.White, 0);
        sheen.StartPoint = new(1, 0); sheen.EndPoint = new(0, 1);
        dc.DrawRectangle(sheen, null, Art);
        dc.DrawRectangle(Gradient(Colors.Black, _light ? .27 : .65, Colors.Black, 0), null, new(Art.X, Art.Y, 9, Art.Height));
        dc.DrawRectangle(Gradient(Colors.Black, _light ? .22 : .52, Colors.Black, 0, vertical: true), null, new(Art.X, Art.Y, Art.Width, 6));
        var edge = lit ? palette.Main : Colors.White;
        Line(dc, edge, lit ? .75 * LightStrength : .08, 1, Art.Right - .5, Art.Top, Art.Right - .5, Art.Bottom);
        Line(dc, edge, lit ? .45 * LightStrength : .06, 1, Art.Left, Art.Bottom - .5, Art.Right, Art.Bottom - .5);
        dc.Pop();
    }

    private static Rect FitImage(ImageSource image, Rect bounds)
    {
        var fit = Math.Min(bounds.Width / image.Width, bounds.Height / image.Height);
        var width = fit * image.Width;
        var height = fit * image.Height;
        return new(bounds.X + (bounds.Width - width) / 2, bounds.Y + (bounds.Height - height) / 2, width, height);
    }

    internal sealed record TextLayout(double Scale, double NameSize, double Top, double NameY, double MemoryY,
        double RarityY, double Bottom, double MemoryHeight);
    internal TextLayout MeasureText(double scale)
    {
        var size = _name.Length > 9 ? 17d : 20d;
        if (English && _name.Contains(" · ", StringComparison.Ordinal)) size = Math.Min(size, 15);
        var width = Format(_name, size, true, Brushes.Black, scale, maxWidth: 10000).Width;
        if (width > TextWidth) size = Math.Max(_summaryCount > 0 ? 11.5 : 14, Math.Floor(size * TextWidth / width * 2) / 2);
        var headingHeight = Format("成就已解锁", 10.5, true, Brushes.Black, scale).Height;
        var nameHeight = Format(_name, size, true, Brushes.Black, scale).Height;
        var memoryHeight = _memory.Length == 0 ? 0 : 2 + Format(_memory, 11.5, false, Brushes.Black, scale, 2).Height;
        var rarityHeight = RarityLine.Length == 0 ? 0 : 3 + Format(RarityLine, 10.5, true, Brushes.Black, scale).Height;
        var top = (CardHeight - headingHeight - 3 - nameHeight - memoryHeight - rarityHeight) / 2;
        var nameY = top + headingHeight + 3;
        return new(scale, size, top, nameY, nameY + nameHeight + 2, nameY + nameHeight + memoryHeight + 3,
            CardHeight - top, Math.Max(0, memoryHeight - 2));
    }

    private void DrawName(DrawingContext dc, TextLayout text, bool lit, string name) =>
        Engrave(dc, name, text.NameSize, true, text.NameY, Hex(_light ? 0x182B36 : 0xE8F0F5), 1, lit, text.Scale);

    private void Engrave(DrawingContext dc, string value, double size, bool bold, double y, Color ink,
        double depth, bool lit, double scale, int lines = 1)
    {
        if (value.Length == 0) return;
        var text = Format(value, size, bold, Brush(Colors.Black, (_light ? .22 : .60) * depth), scale, lines);
        dc.DrawText(text, new(TextX, y + 1));
        text.SetForegroundBrush(Brush(Colors.White, (_light ? .70 : .09) * depth));
        dc.DrawText(text, new(TextX, y - .7));
        text.SetForegroundBrush(lit ? Brush(ink) : Brush(Hex(_light ? 0xAABAC6 : 0x465662), .55));
        dc.DrawText(text, new(TextX, y));
    }

    private void DrawEngravingGlow(DrawingContext dc, TextLayout text)
    {
        dc.PushClip(Outline);
        DrawEtch(dc, _light ? Hex(0x203344) : _palette.Main, .15 * LightStrength, shadow: false);
        if (_summaryCount == 0) DrawNameGlow(dc, text, _name);
        dc.Pop();
    }

    private void DrawNameGlow(DrawingContext dc, TextLayout text, string name)
    {
        var shape = Format(name, text.NameSize, true, Brushes.White, text.Scale).BuildGeometry(new(TextX, text.NameY));
        dc.DrawGeometry(null, Pen(_palette.Main, .12 * LightStrength, 6), shape);
        dc.DrawGeometry(null, Pen(_palette.Main, .26 * LightStrength, 2.2), shape);
    }

    private FormattedText Format(string value, double size, bool bold, Brush brush, double scale, int lines = 1, double maxWidth = TextWidth)
    {
        var family = English ? "Segoe UI, Microsoft YaHei UI" : "Microsoft YaHei UI, Segoe UI";
        var font = new Typeface(new FontFamily(family), FontStyles.Normal,
            bold ? FontWeights.SemiBold : FontWeights.Normal, FontStretches.Normal);
        return new(value, CultureInfo.CurrentUICulture, System.Windows.FlowDirection.LeftToRight, font, size, brush, scale)
        {
            MaxTextWidth = maxWidth, MaxLineCount = lines, Trimming = TextTrimming.CharacterEllipsis
        };
    }

    private static DrawingGroup Drawing(Action<DrawingContext> draw)
    {
        var group = new DrawingGroup();
        using (var dc = group.Open()) draw(dc);
        group.Freeze();
        return group;
    }

    private static BitmapSource Bake(double scale, Action<DrawingContext> draw)
    {
        var visual = new DrawingVisual();
        RenderOptions.SetBitmapScalingMode(visual, BitmapScalingMode.HighQuality);
        using (var dc = visual.RenderOpen()) draw(dc);
        var dpi = scale * 96;
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(CardWidth * scale), (int)Math.Ceiling(CardHeight * scale),
            dpi, dpi, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        bitmap.Freeze();
        return bitmap;
    }

    private static Color Hex(int value) => Color.FromRgb((byte)(value >> 16), (byte)(value >> 8), (byte)value);
    private static Color Tint(Color color, double alpha) => Color.FromArgb((byte)Math.Round(Math.Clamp(alpha, 0, 1) * 255), color.R, color.G, color.B);
    private static SolidColorBrush Brush(Color color, double alpha = 1) => new(Tint(color, alpha));
    private static Pen Pen(Color color, double alpha, double width) => new(Brush(color, alpha), width);
    private static LinearGradientBrush Gradient(Color from, double fromAlpha, Color to, double toAlpha, bool vertical = false) =>
        new(Tint(from, fromAlpha), Tint(to, toAlpha), vertical ? 90 : 0);
    private static void Line(DrawingContext dc, Color color, double alpha, double width, double x1, double y1, double x2, double y2) =>
        dc.DrawLine(Pen(color, alpha, width), new(x1, y1), new(x2, y2));

    private static Geometry Polygon(Point start, params Point[] rest)
    {
        var shape = new StreamGeometry();
        using (var path = shape.Open())
        {
            path.BeginFigure(start, true, true);
            path.PolyLineTo(rest, true, false);
        }
        shape.Freeze();
        return shape;
    }
}
