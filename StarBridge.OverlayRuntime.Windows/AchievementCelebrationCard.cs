namespace StarBridge.OverlayRuntime.Windows;

using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

// The accepted preview's slanted card and fast preload/release + diagonal seal
// reveal. Animation changes only drawing clips/opacity/transforms, not layout.
internal sealed class AchievementCelebrationCard : FrameworkElement
{
    internal const double CardWidth = 336, CardHeight = 104;
    private const double Slant = CardHeight * .2, ImageX = 22, ImageY = 18, ImageSize = 68, TextX = 104;
    internal const double EntryMilliseconds = 1800, HoldMilliseconds = 4000, ExitMilliseconds = 180;
    private readonly bool _light, _reduced;
    private readonly string _locale;
    private readonly string _name, _memory;
    private readonly ImageSource? _earned, _locked;
    private double _elapsed;
    private int _remaining;
    private readonly TranslateTransform _exit = new();

    internal AchievementCelebrationCard(string? locale, bool light, bool reduced, string id = "first-entry", int rank = 0,
        string? displayName = null, string? localImagePath = null)
    {
        _locale = locale ?? CultureInfo.CurrentUICulture.Name;
        _light = light; _reduced = reduced;
        Width = CardWidth; Height = CardHeight;
        // Keep texture sampling explicit on the hardware window path. The
        // software/offscreen renderer can choose a different default from the
        // layered desktop window, especially for a large master drawn at 68 DIP.
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
        RenderTransform = _exit;
        var english = _locale.StartsWith("en", StringComparison.OrdinalIgnoreCase);
        var traditional = _locale.StartsWith("zh-TW", StringComparison.OrdinalIgnoreCase);
        var (prefix, name, memory) = id switch {
            "journey-lorville" => (id, english ? "Lorville Dusk" : traditional ? "羅威爾黃昏" : "罗威尔黄昏", english ? "Dusk lingers; the towers stand like mountains" : traditional ? "夕照未盡，塔影如山" : "夕照未尽，塔影如山"),
            "journey-area18" => (id, english ? "Neon Area18" : traditional ? "霓虹十八區" : "霓虹十八区", english ? "The city that never dims" : traditional ? "燈火通明，不眠不休" : "灯火通明，不眠不休"),
            "journey-orison" => (id, english ? "Orison Above the Clouds" : traditional ? "雲上奧里森" : "云上奥里森", english ? "A city afloat on a sea of cloud" : traditional ? "雲海之上，自有人間" : "云海之上，自有人间"),
            "journey-new-babbage" => (id, english ? "Snowfall over New Babbage" : traditional ? "雪落新巴貝奇" : "雪落新巴贝奇", english ? "Snow falls quietly; the lights come on to meet you" : traditional ? "雪落無聲，燈火相迎" : "雪落无声，灯火相迎"),
            "journey-stanton" => (id, english ? "Stanton Pilgrimage" : traditional ? "巡禮斯坦頓" : "巡礼斯坦顿", english ? "Four cities reached; the stars are home" : traditional ? "四城皆至，星海為家" : "四城皆至，星海为家"),
            "hangar-home" => ("home", english ? "A Ship to Call Home" : traditional ? "星海有歸舟" : "星海有归舟", english ? "And all I ask is a tall ship\nand a star to steer her by;" : traditional ? "滿船清夢壓星河" : "满船清梦压星河"),
            "hangar-collection" => ("collection", english ? "Poetry in Motion" : traditional ? "舷影成詩" : "舷影成诗", english ? "I am a part of all\nthat I have met;" : traditional ? "星河欲轉千帆舞" : "星河欲转千帆舞"),
            "hangar-paths" => ("paths", english ? "The World Is Your Oyster" : traditional ? "萬途皆可往" : "万途皆可往", english ? "I dwell in Possibility -" : traditional ? "大海從魚躍，長空任鳥飛" : "大海从鱼跃，长空任鸟飞"),
            _ => ("first-entry", english ? "First Light" : "初入星海", english ? "Look’d up in perfect silence\nat the stars" : traditional ? "星漢燦爛，若出其裏" : "星汉灿烂，若出其里")
        };
        _name = name + (rank > 0 ? " · " + StarBridge.Core.Achievements.HangarAchievementPolicy.Roman(rank) : ""); _memory = memory;
        _earned = Load(prefix + "-earned.png"); _locked = Load(prefix + "-locked.png");
        if (id.StartsWith("scm-", StringComparison.Ordinal) && displayName is not null)
        {
            _name = displayName; _memory = "";
            _earned = LoadLocal(localImagePath);
            _locked = LoadLocal(localImagePath?.Replace("-512.webp", "-locked-512.webp", StringComparison.Ordinal));
        }
        System.Windows.Automation.AutomationProperties.SetName(this,
            (english ? "Achievement unlocked: " : "成就已解锁：") + _name);
    }
    internal double LifetimeMilliseconds => (_reduced ? 0 : EntryMilliseconds + ExitMilliseconds) + HoldMilliseconds;
    internal bool HasArtwork => _earned is not null && _locked is not null;
    internal string Memory => _memory;
    internal void Advance(double elapsed, int remaining)
    {
        _elapsed = elapsed; _remaining = remaining;
        var exit = _reduced ? 0 : Fraction(elapsed, EntryMilliseconds + HoldMilliseconds, LifetimeMilliseconds);
        Opacity = 1 - exit; _exit.Y = exit * 8;
        InvalidateVisual();
    }
    private static ImageSource? Load(string file)
    {
        try
        {
            var image = new BitmapImage(new Uri($"pack://application:,,,/StarBridge.OverlayRuntime.Windows;component/Assets/Achievements/{file}"));
            image.Freeze(); return image;
        }
        catch { return null; } // An optional image never suppresses the achievement text.
    }
    private static ImageSource? LoadLocal(string? relative)
    {
        // Only bundled artwork, never ImageUrl, a URI, an arbitrary file or a WIC network codec.
        if (relative is null || !relative.StartsWith("Assets/Achievements/scm-holiday-", StringComparison.Ordinal) ||
            !relative.EndsWith("-512.webp", StringComparison.Ordinal) || relative.Contains("..") || relative.Contains('\\') ||
            relative["Assets/Achievements/".Length..].Contains('/')) return null;
        try
        {
            using var bitmap = SkiaSharp.SKBitmap.Decode(System.IO.Path.Combine(AppContext.BaseDirectory, relative));
            if (bitmap is null) return null;
            using var converted = bitmap.Copy(SkiaSharp.SKColorType.Bgra8888);
            var image = BitmapSource.Create(converted.Width, converted.Height, 96, 96, PixelFormats.Pbgra32, null,
                converted.GetPixels(), converted.ByteCount, converted.RowBytes);
            image.Freeze(); return image;
        }
        catch { return null; }
    }
    internal static double Fraction(double ms, double start, double end) => Math.Clamp((ms - start) / (end - start), 0, 1);
    private static double Out(double value) => 1 - Math.Pow(1 - value, 3);
    private static double Move(double ms, double start, double end, double from, double to) =>
        from + (to - from) * Out(Fraction(ms, start, end));
    private static Brush Color(string hex) => new SolidColorBrush((System.Windows.Media.Color)ColorConverter.ConvertFromString(hex));
    private static Geometry Polygon(params Point[] points)
    {
        var geometry = new StreamGeometry();
        using (var context = geometry.Open()) { context.BeginFigure(points[0], true, true); context.PolyLineTo(points.Skip(1).ToArray(), true, false); }
        geometry.Freeze(); return geometry;
    }
    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        var t = _reduced ? EntryMilliseconds : _elapsed;
        var left = Move(t, 300, 378, 120, -40);
        var right = t < 445 ? Move(t, 315, 445, 60, CardWidth - 28) : Move(t, 445, 545, CardWidth - 28, CardWidth + 40);
        dc.PushClip(new RectangleGeometry(new Rect(Math.Max(0, left), 0, Math.Max(0, right - Math.Max(0, left)), CardHeight)));
        dc.PushClip(Polygon(new(Slant, 0), new(CardWidth, 0), new(CardWidth, CardHeight), new(0, CardHeight)));
        dc.DrawRectangle(Color(_light ? "#f7fafb" : "#111920"), null, new(0, 0, CardWidth, CardHeight));
        dc.DrawLine(new Pen(Color(_light ? "#bfd0dc" : "#365061"), 1), new(Slant, .5), new(CardWidth, .5));
        DrawImage(dc, t);
        var english = _locale.StartsWith("en", StringComparison.OrdinalIgnoreCase);
        var traditional = _locale.StartsWith("zh-TW", StringComparison.OrdinalIgnoreCase);
        // The stack is centred as a whole, so a card without a memory line is not top-heavy.
        var name = Format(_name, NameSize(english && _name.Contains(" · ") ? 15 : 19), _light ? "#182b36" : "#e8f0f5", true);
        var memory = _memory.Length == 0 ? null : Format(_memory, 12, _light ? "#536875" : "#aabcc7");
        var top = (CardHeight - (19 + name.Height + (memory is null ? 0 : 5 + memory.Height))) / 2;
        Draw(dc, Format(english ? "ACHIEVEMENT UNLOCKED" : traditional ? "成就已解鎖" : "成就已解锁", 11, _light ? "#286b92" : "#93c8e8"),
            TextX, top, Fraction(t, 345, 500));
        Draw(dc, name, TextX, top + 19, Fraction(t, 325, 485));
        if (memory is not null) Draw(dc, memory, TextX, top + 19 + name.Height + 5, Fraction(t, 410, 640));
        if (_remaining > 0) Draw(dc, Format($"+{_remaining}", 11, _light ? "#536875" : "#aabcc7"), CardWidth - 38, 10, Fraction(t, 410, 600));
        dc.Pop(); dc.Pop();
        if (!_reduced && t < 365)
        {
            var x = t < 60 ? CardWidth + 6 : Move(t, 60, 210, CardWidth + 6, 60);
            var gather = t < 210 ? 1 : t < 300 ? Move(t, 210, 285, 1, .52) : Move(t, 300, 335, .52, 1);
            dc.PushOpacity(1 - Fraction(t, 335, 365));
            dc.DrawRectangle(Color(_light ? "#286b92" : "#93c8e8"), null, new(x, CardHeight / 2 - 24.5 * gather, 1.6, 49 * gather));
            dc.Pop();
        }
    }
    private void DrawImage(DrawingContext dc, double t)
    {
        var bounds = new Rect(ImageX, ImageY, ImageSize, ImageSize);
        var imageRight = ImageX + ImageSize;
        dc.PushClip(new RectangleGeometry(bounds));
        dc.DrawRectangle(Color(_light ? "#e5e9eb" : "#080c10"), null, bounds);
        if (_locked is not null) dc.DrawImage(_locked, bounds);
        var progress = Out(Fraction(t, 730, 1180));
        if (progress > 0)
        {
            // Reveal from top right toward bottom left; the moving seal is the
            // diagonal boundary, not a crossfade to a newly awarded collection.
            var distance = progress * ImageSize * 2;
            dc.PushClip(Polygon(new(imageRight - distance, ImageY), new(imageRight, ImageY), new(imageRight, ImageY + distance)));
            if (_earned is not null) dc.DrawImage(_earned, bounds);
            else { dc.DrawRectangle(Color(_light ? "#c9dce7" : "#284459"), null, bounds); Draw(dc, Format("✦", 36, "#93c8e8"), ImageX + 18, ImageY + 11, 1); }
            dc.Pop();
            if (progress < 1)
            {
                dc.PushOpacity(Fraction(t, 730, 780) * (1 - Fraction(t, 1100, 1200)));
                dc.DrawLine(new Pen(Color(_light ? "#ffffff" : "#b9d5e5"), 2.5), new(imageRight - distance, ImageY), new(imageRight, ImageY + distance));
                dc.Pop();
            }
        }
        dc.Pop();
    }
    private FormattedText Format(string value, double size, string color, bool bold = false, double maxWidth = CardWidth - TextX - 18)
    {
        var typeface = new Typeface(new FontFamily("Segoe UI, Microsoft YaHei UI"), FontStyles.Normal,
            bold ? FontWeights.SemiBold : FontWeights.Normal, FontStretches.Normal);
        return new(value, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, typeface, size, Color(color),
            VisualTreeHelper.GetDpi(this).PixelsPerDip) { MaxTextWidth = maxWidth, Trimming = TextTrimming.CharacterEllipsis };
    }
    // A long English title stays on one line instead of pushing the stack out of the card.
    private double NameSize(double size)
    {
        var limit = CardWidth - TextX - 18;
        var width = Format(_name, size, "#000000", true, 10000).Width;
        return width < limit ? size : Math.Max(14, Math.Floor(size * limit / width * 2) / 2);
    }
    private static void Draw(DrawingContext dc, FormattedText text, double x, double y, double opacity)
    {
        if (opacity <= 0) return;
        dc.PushOpacity(opacity);
        dc.DrawText(text, new(x, y)); dc.Pop();
    }
}
