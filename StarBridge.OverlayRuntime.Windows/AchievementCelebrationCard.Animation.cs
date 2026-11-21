namespace StarBridge.OverlayRuntime.Windows;

using System.Windows;
using System.Windows.Media;
using Color = System.Windows.Media.Color;

internal sealed partial class AchievementCelebrationCard
{
    private static double Fraction(double time, double start, double end) => Math.Clamp((time - start) / (end - start), 0, 1);
    private static double EaseOut(double value) => 1 - Math.Pow(1 - value, 3);
    private static double Smooth(double value) => value * value * (3 - 2 * value);
    private static double Pulse(double progress) => progress is > 0 and < 1 ? Math.Sin(Math.PI * progress) : 0;

    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        if (_elapsed >= LifetimeMilliseconds) return;
        if (_glass is null) PrepareGlass(VisualTreeHelper.GetDpi(this).PixelsPerDip);
        var glass = _glass!;
        var still = IsStill(_elapsed);
        var exit = Math.Max(0, _elapsed - EntryMilliseconds - HoldMilliseconds);
        var slide = still ? 0 : _elapsed < EntryMilliseconds
            ? CardWidth * (1 - EaseOut(Fraction(_elapsed, 0, 300)))
            : CardWidth * Smooth(Fraction(exit, 110, 300));
        var front = still ? 1 : EaseSweep(_elapsed, exit);
        // Use the same device-pixel boundary for both sides of the glass.
        var split = Math.Clamp(Math.Round(CardWidth * (1 - front) * glass.Scale) / glass.Scale, 0, CardWidth);
        dc.PushTransform(new TranslateTransform(Bleed + slide, Bleed));
        if (split > 0) DrawSide(dc, glass, lit: false, 0, split);
        if (split < CardWidth) DrawSide(dc, glass, lit: true, split, CardWidth);
        DrawQueueCount(dc, glass.Scale, split);
        DrawLight(dc, glass, _palette, still, exit, front);
        dc.Pop();

        // The hinge stays at the edge of the screen even while the plate slides.
        dc.PushTransform(new TranslateTransform(Bleed, Bleed));
        var hinge = still ? 1 : EaseOut(Fraction(_elapsed, 0, 140)) * (1 - Smooth(Fraction(exit, 110, 300)));
        DrawSeam(dc, _palette, hinge);
        dc.Pop();
    }

    private static double EaseSweep(double elapsed, double exit) =>
        Smooth(Fraction(elapsed, 280, 600)) * (1 - Smooth(Fraction(exit, 0, 150)));

    private void DrawSide(DrawingContext dc, GlassCache glass, bool lit, double left, double right)
    {
        var clipped = right - left < CardWidth;
        if (clipped) dc.PushClip(new RectangleGeometry(new Rect(left, 0, right - left, CardHeight)));
        dc.DrawImage(lit ? glass.Lit : glass.Unlit, Plate);
        if (_summaryCount > 0)
        {
            var name = glass.SummaryNames[SummaryCountAt(_elapsed)];
            dc.DrawDrawing(lit ? name.Lit : name.Unlit);
        }
        if (clipped) dc.Pop();
    }

    private void DrawQueueCount(DrawingContext dc, double scale, double split)
    {
        if (_remaining <= 0 || split >= CardWidth) return;
        _queueLabel ??= Drawing(drawing =>
        {
            var label = Format($"+{_remaining}", 10.5, false, Brush(Hex(_light ? 0x536875 : 0xAABCC7)),
                scale, maxWidth: 40);
            drawing.DrawText(label, new(CardWidth - 12 - label.Width, 10));
        });
        dc.PushClip(new RectangleGeometry(new Rect(split, 0, CardWidth - split, CardHeight)));
        dc.DrawDrawing(_queueLabel);
        dc.Pop();
    }

    private void DrawSeam(DrawingContext dc, Palette palette, double progress)
    {
        if (progress <= 0) return;
        var strength = progress * palette.SeamAlpha * LightStrength;
        dc.DrawRectangle(Gradient(palette.Seam, 0, palette.Seam, strength * .32), null, new(CardWidth - 22, 0, 22, CardHeight));
        var width = RarityLevel == 0 ? 1.6 : 2.4;
        dc.DrawRectangle(Brush(palette.Seam, strength), null, new(CardWidth - width, 0, width, CardHeight));
        if (RarityLevel == 2)
            dc.DrawRectangle(Brush(palette.Secondary, strength * .62), null, new(CardWidth - 5, 8, 1, CardHeight - 16));
    }

    private void DrawLight(DrawingContext dc, GlassCache glass, Palette palette, bool still, double exit, double front)
    {
        if (front is > 0 and < 1)
        {
            var x = CardWidth * (1 - front);
            dc.PushClip(Outline);
            dc.DrawRectangle(Gradient(palette.Secondary, 0, palette.Secondary, .32 * LightStrength * Pulse(front)),
                null, new(x - 26, 0, 26, CardHeight));
            dc.Pop();
        }

        var glow = still ? 0 : Pulse(Fraction(_elapsed, 380, Math.Min(900, EntryMilliseconds)));
        if (glow > 0 && glass.Glow is { } engravingGlow)
        {
            dc.PushOpacity(glow * (RarityLevel == 0 ? .60 : 1));
            dc.DrawImage(engravingGlow, Plate);
            if (_summaryCount > 0 && glass.SummaryNames[SummaryCountAt(_elapsed)].Glow is { } summaryGlow)
                dc.DrawDrawing(summaryGlow);
            dc.Pop();
        }

        if (front > 0)
        {
            var edge = still || exit > 0 ? palette.EdgeAlpha :
                1 - (1 - palette.EdgeAlpha) * Fraction(_elapsed, 600, Math.Min(900, EntryMilliseconds));
            var left = Math.Max(CutWidth, CardWidth * (1 - front));
            LongEdges(dc, palette.Main, edge, left, CardWidth, 1.2);
        }
        var cut = still || exit > 0 ? palette.EdgeAlpha :
            Fraction(_elapsed, 560, 640) * (1 - (1 - palette.EdgeAlpha) * Fraction(_elapsed, 640, Math.Min(980, EntryMilliseconds)));
        cut *= 1 - Smooth(Fraction(exit, 0, 80));
        if (cut > 0)
        {
            EdgeLight(dc, palette.Secondary, cut, 1.4, CutWidth, .7, .6, CutHeight);
            EdgeLight(dc, palette.Secondary, cut, 1.4, CutWidth, CardHeight - .7, .6, CardHeight - CutHeight);
            if (RarityLevel > 0)
                EdgeLight(dc, palette.Main, cut * (RarityLevel == 2 ? .55 : .30), 1, .6, CutHeight, .6, CardHeight - CutHeight);
        }
        if (still || RarityLevel != 2) return;

        var second = Fraction(_elapsed, 700, 1060);
        if (second is > 0 and < 1)
        {
            var head = CardWidth - (CardWidth - CutWidth) * Smooth(second);
            LongEdges(dc, palette.Secondary, Pulse(second), head, Math.Min(CardWidth, head + 60), 2);
        }
        var flash = Pulse(Fraction(_elapsed, 980, 1100));
        if (flash > 0 && Star.Value is { } star)
        {
            var size = 30 * flash;
            dc.PushOpacity(flash * LightStrength);
            dc.DrawImage(star, FitImage(star, new(CutWidth / 2 - size / 2, CutHeight / 2 - size / 2, size, size)));
            dc.Pop();
        }
    }

    private void LongEdges(DrawingContext dc, Color color, double alpha, double left, double right, double width)
    {
        EdgeLight(dc, color, alpha, width, left, .7, right, .7);
        EdgeLight(dc, color, alpha * .8, width, left, CardHeight - .7, right, CardHeight - .7);
    }

    private void EdgeLight(DrawingContext dc, Color color, double alpha, double width, double x1, double y1, double x2, double y2)
    {
        var strength = alpha * LightStrength;
        Line(dc, color, .06 * strength, 7, x1, y1, x2, y2);
        Line(dc, color, .16 * strength, 3.2, x1, y1, x2, y2);
        Line(dc, color, strength, width, x1, y1, x2, y2);
    }
}
