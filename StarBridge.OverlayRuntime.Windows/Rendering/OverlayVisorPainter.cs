using System.IO;
using System.Numerics;
using Vortice.Direct2D1;
using Vortice.DirectWrite;
using Vortice.Mathematics;

namespace StarBridge.Desktop;

/// <summary>Which part of a group a drawing pass puts into its layer: the frame (lines, boxes, marks) or the text.</summary>
internal enum OverlayVisorPass { All, Shapes, Text }

internal readonly record struct OverlayVisorRun(string Text, bool Numeric, FontWeight Weight, float Size, Color4 Color, float Dy = 0, float Gap = 0, bool Boxed = false);

/// <summary>
/// Direct2D / DirectWrite painter for the visor appearance with cached text formats and widths.
/// Uses the client's own bundled fonts (Source Han Sans, Rajdhani) when they can be found next to
/// the app, otherwise the Windows UI fonts.
/// </summary>
internal sealed class OverlayVisorPainter : IDisposable
{
    private readonly ID2D1DeviceContext _dc;
    private readonly IDWriteFactory5 _dw;
    private readonly IDWriteFontCollection1? _fonts;
    private readonly Dictionary<(bool, int, float), IDWriteTextFormat> _formats = [];
    private readonly Dictionary<(string, bool, int, float), float> _widths = [];
    public readonly string Han, Num;
    public float Alpha = 1;
    /// <summary>The frame and the text go to separate layers: the frame gets the glow and haze, the text only a thin shadow.</summary>
    public OverlayVisorPass Pass = OverlayVisorPass.All;
    public Matrix3x2 Base = Matrix3x2.Identity;
    public ID2D1DeviceContext Dc => _dc;

    public OverlayVisorPainter(ID2D1DeviceContext dc, IDWriteFactory5 dw)
    {
        _dc = dc; _dw = dw;
        Han = "Microsoft YaHei UI"; Num = "Bahnschrift";
        try
        {
            if (FindFontDirectory() is { } dir)
            {
                using var builder = dw.CreateFontSetBuilder();
                foreach (var name in new[] { "SourceHanSansCN-VF.ttf", "Rajdhani-Medium.ttf", "Rajdhani-SemiBold.ttf", "Rajdhani-Bold.ttf" })
                {
                    var path = Path.Combine(dir, name);
                    if (!File.Exists(path)) continue;
                    using var file = dw.CreateFontFileReference(path, null);
                    builder.AddFontFile(file);
                }
                using var set = builder.CreateFontSet();
                _fonts = dw.CreateFontCollectionFromFontSet(set);
                if (_fonts.FindFamilyName("Source Han Sans CN VF", out _)) Han = "Source Han Sans CN VF";
                if (_fonts.FindFamilyName("Rajdhani", out _)) Num = "Rajdhani";
            }
        }
        catch (Exception exception)
        {
            DesktopRuntimeDiagnostics.WriteDiagnosticLog($"overlay-visor fonts fallback=system error={exception.GetType().Name}");
        }
    }

    /// <summary>The Flutter client ships its fonts under data/flutter_assets/assets/fonts; the overlay host runs from the same install.</summary>
    internal static string? FindFontDirectory()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        for (var i = 0; i < 4 && dir is not null; i++, dir = dir.Parent)
        {
            var candidate = Path.Combine(dir.FullName, "data", "flutter_assets", "assets", "fonts");
            if (File.Exists(Path.Combine(candidate, "SourceHanSansCN-VF.ttf"))) return candidate;
        }
        return null;
    }

    // 11-07 (user chose method E): at 2560x1440 and medium size, body text is drawn 12 px and titles 13 px.
    // Medium at 1440p draws a design unit as 1440 / 1080 * Compact pixels; body text is 15 units or less.
    private const float Medium1440 = 1440f / 1080f * OverlayVisorRenderer.Compact;
    private const float BodyScale = 12f / (15f * Medium1440), TitleScale = 13f / (16f * Medium1440);

    /// <summary>The size a design font size is drawn at (body text 12 px, titles 13 px at 1440p medium).</summary>
    internal static float DrawnSize(float size) => size <= 15 ? size * BodyScale : size * TitleScale;

    public IDWriteTextFormat Format(bool numeric, FontWeight weight, float size)
    {
        size = DrawnSize(size);
        var key = (numeric, (int)weight, size);
        if (_formats.TryGetValue(key, out var format)) return format;
        var family = numeric ? Num : Han;
        format = _fonts is not null && _fonts.FindFamilyName(family, out _)
            ? _dw.CreateTextFormat(family, _fonts, weight, Vortice.DirectWrite.FontStyle.Normal, FontStretch.Normal, size, "zh-cn")
            : _dw.CreateTextFormat(family, null, weight, Vortice.DirectWrite.FontStyle.Normal, FontStretch.Normal, size, "zh-cn");
        format.WordWrapping = WordWrapping.NoWrap;
        return _formats[key] = format;
    }

    public float Measure(string text, bool numeric, FontWeight weight, float size)
    {
        if (text.Length == 0) return 0;
        var key = (text, numeric, (int)weight, size);
        if (_widths.TryGetValue(key, out var width)) return width;
        using var layout = _dw.CreateTextLayout(text, Format(numeric, weight, size), 4000, 400);
        if (_widths.Count > 4000) _widths.Clear();
        return _widths[key] = layout.Metrics.WidthIncludingTrailingWhitespace;
    }

    public float Width(OverlayVisorRun run) => run.Gap + Measure(run.Text, run.Numeric, run.Weight, run.Size) + (run.Boxed ? 10 : 0);

    public ID2D1SolidColorBrush Brush(Color4 color, float alpha = 1) => _dc.CreateSolidColorBrush(new Color4(color.R, color.G, color.B, color.A * alpha * Alpha));

    public void Text(string text, float x, float y, bool numeric, FontWeight weight, float size, Color4 color, float alpha = 1)
    {
        if (text.Length == 0 || Pass == OverlayVisorPass.Shapes) return;
        using var brush = Brush(color, alpha);
        _dc.DrawText(text, Format(numeric, weight, size), new Rect(x, y, 4000, DrawnSize(size) * 1.7f), brush, DrawTextOptions.None);
    }

    public void Draw(OverlayVisorRun run, float x, float y)
    {
        x += run.Gap;
        if (run.Boxed)
        {
            var w = Measure(run.Text, run.Numeric, run.Weight, run.Size);
            using var brush = Brush(run.Color, 0.9f);
            if (Pass != OverlayVisorPass.Text) _dc.DrawRectangle(new Rect(x + 0.5f, y + run.Dy + 2.5f, w + 9, DrawnSize(run.Size) * 1.42f), brush, 1f);
            Text(run.Text, x + 5, y + run.Dy + 1, run.Numeric, run.Weight, run.Size, run.Color);
        }
        else Text(run.Text, x, y + run.Dy, run.Numeric, run.Weight, run.Size, run.Color);
    }

    public void Line(float x1, float y1, float x2, float y2, Color4 color, float alpha = 1, float width = 1) { if (Pass == OverlayVisorPass.Text) return; using var b = Brush(color, alpha); _dc.DrawLine(new(x1, y1), new(x2, y2), b, width); }
    public void Fill(float x, float y, float w, float h, Color4 color, float alpha = 1) { if (Pass == OverlayVisorPass.Text) return; using var b = Brush(color, alpha); _dc.FillRectangle(new Rect(x, y, w, h), b); }
    public void Stroke(float x, float y, float w, float h, Color4 color, float alpha = 1, float width = 1) { if (Pass == OverlayVisorPass.Text) return; using var b = Brush(color, alpha); _dc.DrawRectangle(new Rect(x, y, w, h), b, width); }
    public void RoundStroke(float x, float y, float w, float h, float r, Color4 color, float alpha = 1, float width = 1) { if (Pass == OverlayVisorPass.Text) return; using var b = Brush(color, alpha); _dc.DrawRoundedRectangle(new RoundedRectangle(new System.Drawing.RectangleF(x, y, w, h), r, r), b, width); }

    public void Diamond(float cx, float cy, float size, Color4 color, bool hollow = false)
    {
        if (Pass == OverlayVisorPass.Text) return;
        _dc.Transform = Matrix3x2.CreateRotation(MathF.PI / 4, new(cx, cy)) * Base;
        if (hollow) Stroke(cx - size / 2, cy - size / 2, size, size, color, 1, 1.4f); else Fill(cx - size / 2, cy - size / 2, size, size, color);
        _dc.Transform = Base;
    }

    /// <summary>
    /// A ring of radius <paramref name="r"/>: a faint full track, and over it the part that is left of
    /// <paramref name="fraction"/>, lost clockwise from the top (user, 11-10: "从上方顶点顺时针扣血").
    /// </summary>
    public void Ring(float cx, float cy, float r, float fraction, Color4 color, float width, float trackAlpha = 0.22f, float alpha = 1)
    {
        if (Pass == OverlayVisorPass.Text) return;
        if (trackAlpha > 0) using (var track = Brush(color, trackAlpha)) _dc.DrawEllipse(new Ellipse(new(cx, cy), r, r), track, width);
        fraction = Math.Clamp(fraction, 0, 1);
        if (fraction <= 0 || alpha <= 0) return;
        using var brush = Brush(color, alpha);
        if (fraction >= 0.999f) { _dc.DrawEllipse(new Ellipse(new(cx, cy), r, r), brush, width); return; }
        // the remaining arc runs clockwise from where the loss ends back to the top
        var start = -MathF.PI / 2 + (1 - fraction) * 2 * MathF.PI;
        var end = -MathF.PI / 2 + 2 * MathF.PI;
        using var factory = _dc.Factory; // a getter adds a reference: released here
        using var geometry = factory.CreatePathGeometry();
        using (var sink = geometry.Open())
        {
            sink.BeginFigure(new(cx + r * MathF.Cos(start), cy + r * MathF.Sin(start)), FigureBegin.Hollow);
            sink.AddArc(new ArcSegment
            {
                Point = new(cx + r * MathF.Cos(end), cy + r * MathF.Sin(end)), Size = new(r, r), RotationAngle = 0,
                SweepDirection = SweepDirection.Clockwise, ArcSize = fraction > 0.5f ? ArcSize.Large : ArcSize.Small,
            });
            sink.EndFigure(FigureEnd.Open);
            sink.Close();
        }
        _dc.DrawGeometry(geometry, brush, width);
    }

    public void Gradient(float x, float y, float w, float h, Color4 from, Color4 to)
    {
        if (Pass == OverlayVisorPass.Text) return;
        using var stops = _dc.CreateGradientStopCollection([new GradientStop(0, from), new GradientStop(1, to)]);
        using var brush = _dc.CreateLinearGradientBrush(new LinearGradientBrushProperties(new(x, y), new(x + w, y)), stops);
        brush.Opacity = Alpha;
        _dc.FillRectangle(new Rect(x, y, w, h), brush);
    }

    public void Dispose()
    {
        foreach (var format in _formats.Values) format.Dispose();
        _formats.Clear();
        _fonts?.Dispose();
    }
}
