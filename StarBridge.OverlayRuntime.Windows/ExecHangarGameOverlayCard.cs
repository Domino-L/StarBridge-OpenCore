namespace StarBridge.OverlayRuntime.Windows;

using System.Globalization;
using System.Windows;
using System.Windows.Media;
using StarBridge.HostRuntime.Tools;

/// <summary>Transparent, read-only game display: title/lamps and one boundary countdown.</summary>
public sealed class ExecHangarGameOverlayCard : FrameworkElement
{
    public const double CardWidth = 140, CardHeight = 52;
    private ExecHangarGameOverlayFrame? _frame;
    private string? _locale;
    public ExecHangarGameOverlayCard() { Width = CardWidth; Height = CardHeight; IsHitTestVisible = false; }
    public void Update(ExecHangarGameOverlayFrame frame, string? locale)
    {
        _frame = frame; _locale = locale;
        var title = Text(Title(locale), 14, Brushes.White, true);
        var caption = Text(Label(frame, locale), 12, Brushes.White);
        var clock = Text(Countdown(frame), 20, Brushes.White, true);
        Width = Math.Ceiling(Math.Max(3 + title.Width + 8 + 4 * 11 + 8,
            3 + caption.Width + 8 + clock.Width) + 4);
        InvalidateVisual();
    }
    private static string Title(string? locale) => English(locale) ? "Executive Hangar" : Traditional(locale) ? "行政機庫" : "行政机库";
    private static bool English(string? locale) => locale?.StartsWith("en", StringComparison.OrdinalIgnoreCase) == true;
    private static bool Traditional(string? locale) => locale is "zh-TW" or "zh-HK" or "zh-Hant";
    private static string Label(ExecHangarGameOverlayFrame frame, string? locale) =>
        frame.Leaving ? English(locale) ? "Leave now" : Traditional(locale) ? "請離場" : "请离场"
        : frame.Open ? English(locale) ? "Closes in" : Traditional(locale) ? "距關閉" : "距关闭"
        : English(locale) ? "Opens in" : Traditional(locale) ? "距開啟" : "距开启";
    public static string Countdown(ExecHangarGameOverlayFrame frame)
    {
        var seconds = Math.Max(0, (long)Math.Ceiling((frame.Boundary - frame.Now).TotalSeconds));
        return $"{seconds / 3600:00}:{seconds % 3600 / 60:00}:{seconds % 60:00}";
    }
    protected override void OnRender(DrawingContext dc)
    {
        if (_frame is not {} frame) return;
        var white = Brushes.White;
        var green = new SolidColorBrush(Color.FromRgb(55, 212, 158));
        var red = new SolidColorBrush(Color.FromRgb(251, 105, 114));
        var off = new Pen(new SolidColorBrush(Color.FromRgb(164, 180, 188)), 1);
        var title = Text(Title(_locale), 14, white, true);
        DrawText(dc, title, new(3, 1));
        for (var i = 0; i < 5; i++)
        {
            var point = new Point(3 + title.Width + 8 + i * 11 + 3.5, 10);
            dc.DrawEllipse(new SolidColorBrush(Color.FromArgb(160, 0, 0, 0)), null, point, 4.5, 4.5);
            dc.DrawEllipse(i < frame.Green ? green : i < frame.Green + frame.Red ? red : null,
                i >= frame.Green + frame.Red ? off : null, point, 3.5, 3.5);
        }
        var caption = Text(Label(frame, _locale), 12, frame.Leaving ? red : white);
        DrawText(dc, caption, new(3, 28));
        DrawText(dc, Text(Countdown(frame), 20, frame.Leaving ? red : white, true), new(3 + caption.Width + 8, 22));
    }
    private FormattedText Text(string value, double size, Brush brush, bool bold = false) => new(value,
        CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
        new Typeface(new FontFamily("Segoe UI, Microsoft YaHei UI"), FontStyles.Normal, bold ? FontWeights.SemiBold : FontWeights.Normal, FontStretches.Normal),
        size, brush, VisualTreeHelper.GetDpi(this).PixelsPerDip);
    private static void DrawText(DrawingContext dc, FormattedText text, Point at)
    {
        // Thin dark outline protects legibility over bright game scenes without a panel background.
        var geometry = text.BuildGeometry(at);
        dc.DrawGeometry(null, new Pen(new SolidColorBrush(Color.FromArgb(200, 0, 0, 0)), 2), geometry);
        dc.DrawText(text, at);
    }
}
