using System.Globalization;
using System.Windows;
using System.Windows.Media;
using Color = System.Windows.Media.Color;
using ColorConverter = System.Windows.Media.ColorConverter;
using Pen = System.Windows.Media.Pen;
using Point = System.Windows.Point;

namespace StarBridge.Desktop;

internal sealed class OverlaySkinPreviewCard : FrameworkElement
{
    public static readonly DependencyProperty SkinProperty = DependencyProperty.Register(
        nameof(Skin),
        typeof(OverlaySkin),
        typeof(OverlaySkinPreviewCard),
        new FrameworkPropertyMetadata(
            OverlaySkin.Default,
            FrameworkPropertyMetadataOptions.AffectsRender));

    private static readonly Typeface DisplayTypeface = new("Bahnschrift SemiCondensed");
    private static readonly Typeface DataTypeface = new("Consolas");

    public OverlaySkinPreviewCard()
    {
        SnapsToDevicePixels = true;
        UseLayoutRounding = true;
    }

    public OverlaySkin Skin
    {
        get => (OverlaySkin)GetValue(SkinProperty);
        set => SetValue(SkinProperty, value);
    }

    internal static bool Supports(OverlaySkinRenderKind renderKind)
    {
        if (renderKind is OverlaySkinRenderKind.Default or OverlaySkinRenderKind.LagrangeWeave)
        {
            return true;
        }

        return false;
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        if (ActualWidth < 24 || ActualHeight < 16)
        {
            return;
        }

        var profile = OverlaySkinCatalog.Get(Skin);
        var bounds = new Rect(0, 0, ActualWidth, ActualHeight);
        drawingContext.PushClip(new RectangleGeometry(bounds));
        drawingContext.DrawRectangle(
            Brush("#070B10"),
            Pen("#314552", 1),
            bounds);

        var scaleX = ActualWidth / 400d;
        var scaleY = ActualHeight / 180d;
        drawingContext.PushTransform(new ScaleTransform(scaleX, scaleY));
        switch (profile.RenderKind)
        {
            case OverlaySkinRenderKind.LagrangeWeave:
                DrawLagrangeScene(drawingContext);
                break;
            default:
                DrawFleetStandardScene(drawingContext);
                break;
        }

        drawingContext.Pop();
        drawingContext.Pop();
    }

    private void DrawFleetStandardScene(DrawingContext dc)
    {
        dc.DrawRectangle(Brush("#07131C"), null, new Rect(0, 0, 400, 180));
        DrawGrid(dc, "#173446", 20, 0.32);
        DrawCalibrationCorners(dc, "#4C8AA8");

        DrawStandardPanel(
            dc,
            new Rect(12, 43, 146, 42),
            "SQUAD STATUS",
            ["FLEET  04 / 04", "SERVER  LIVE"],
            emphasizeFirstRow: true);
        DrawStandardPanel(
            dc,
            new Rect(12, 85, 146, 48),
            "MEMBER STATUS",
            ["TEST ALPHA    ONLINE", "DOMINO_CN     BAJINI"],
            emphasizeFirstRow: false);
        DrawStandardPanel(
            dc,
            new Rect(12, 133, 146, 35),
            "COMMS",
            ["RELAY  CONNECTED"],
            emphasizeFirstRow: true);

        DrawStandardPanel(
            dc,
            new Rect(174, 13, 213, 38),
            "FLEET NOTICE",
            ["BRIDGE CHANNEL SYNCHRONIZED"],
            emphasizeFirstRow: true);

        DrawStandardEvent(dc, new Rect(280, 67, 108, 31), "NAV UPDATE", "BAJINI POINT");
        DrawStandardEvent(dc, new Rect(280, 104, 108, 31), "MEMBER ONLINE", "TEST ALPHA");
        DrawCrosshair(dc, new Point(219, 108), "#DCE4E9", false);

        DrawText(dc, "SC-FC // STANDARD LINK", new Point(175, 161), 6.4, "#7193A7", DataTypeface);
        DrawText(dc, "120 FPS", new Point(351, 161), 6.2, "#29AFFF", DataTypeface);
    }


    private void DrawLagrangeScene(DrawingContext dc)
    {
        dc.DrawRectangle(Brush("#061114"), null, new Rect(0, 0, 400, 180));
        DrawGrid(dc, "#15343A", 20, 0.28);
        DrawCalibrationCorners(dc, "#4B837F");

        DrawLagrangePanel(dc, new Rect(12, 42, 150, 43), "SQUAD FIELD", ["EQUILIBRIUM  0.97"]);
        DrawLagrangePanel(dc, new Rect(12, 85, 150, 49), "MEMBER FIELD", ["NODES  06 / 06"]);
        DrawLagrangePanel(dc, new Rect(12, 134, 150, 34), "COMMS FIELD", ["MESH  STABLE"]);
        DrawLagrangePanel(dc, new Rect(175, 13, 212, 39), "FIELD NOTICE", ["ANCHOR NETWORK SYNCHRONIZED"]);
        DrawLagrangePanel(dc, new Rect(278, 67, 110, 31), "EVENT VECTOR", ["L2  CAPTURED"]);
        DrawLagrangePanel(dc, new Rect(278, 104, 110, 31), "EVENT VECTOR", ["L4  STABLE"]);

        DrawLagrangeField(dc, new Point(219, 108));
        DrawText(dc, "LG-W // EQUILIBRIUM MAP", new Point(175, 161), 6.4, "#78979A", DataTypeface);
    }


    private void DrawStandardPanel(
        DrawingContext dc,
        Rect rect,
        string title,
        IReadOnlyList<string> rows,
        bool emphasizeFirstRow)
    {
        dc.DrawRectangle(Brush("#C9081722"), Pen("#657A91A0", 0.85), rect);
        dc.DrawLine(Pen("#29AFFF", 1.35), new Point(rect.Left, rect.Top), new Point(rect.Left + 7, rect.Top));
        dc.DrawLine(Pen("#29AFFF", 1.35), new Point(rect.Left, rect.Top), new Point(rect.Left, rect.Bottom));
        dc.DrawLine(
            Pen("#69CCFF", 0.8),
            new Point(rect.Left + 7, rect.Top + 15),
            new Point(rect.Right - 7, rect.Top + 15));
        DrawBracketCorners(dc, rect, "#80AFC5", 6);

        DrawText(dc, title, new Point(rect.Left + 9, rect.Top + 4), 6.8, "#DCE9F0", DisplayTypeface);
        for (var index = 0; index < rows.Count; index++)
        {
            DrawText(
                dc,
                rows[index],
                new Point(rect.Left + 9, rect.Top + 20 + index * 10),
                5.9,
                emphasizeFirstRow && index == 0 ? "#69CCFF" : "#9FB4C0",
                DataTypeface);
        }
    }

    private void DrawStandardEvent(DrawingContext dc, Rect rect, string title, string detail)
    {
        dc.DrawRectangle(Brush("#DB081722"), Pen("#5B7890A0", 0.8), rect);
        dc.DrawLine(Pen("#29AFFF", 1.2), new Point(rect.Right, rect.Top), new Point(rect.Right, rect.Bottom));
        dc.DrawLine(
            Pen("#3D90B6", 0.75),
            new Point(rect.Left + 6, rect.Top + 14),
            new Point(rect.Right - 6, rect.Top + 14));
        DrawText(dc, title, new Point(rect.Left + 7, rect.Top + 4), 6.3, "#DDE8ED", DisplayTypeface);
        DrawText(dc, detail, new Point(rect.Left + 7, rect.Top + 18), 5.7, "#83A1B1", DataTypeface);
    }


    private void DrawLagrangePanel(
        DrawingContext dc,
        Rect rect,
        string title,
        IReadOnlyList<string> rows)
    {
        var outline = new StreamGeometry();
        using (var context = outline.Open())
        {
            context.BeginFigure(new Point(rect.Left + 8, rect.Top), true, true);
            context.BezierTo(
                new Point(rect.Left + rect.Width * 0.28, rect.Top - 3),
                new Point(rect.Right - rect.Width * 0.28, rect.Top + 3),
                new Point(rect.Right - 8, rect.Top),
                true,
                false);
            context.BezierTo(
                new Point(rect.Right + 3, rect.Top + rect.Height * 0.28),
                new Point(rect.Right - 3, rect.Bottom - rect.Height * 0.28),
                new Point(rect.Right - 8, rect.Bottom),
                true,
                false);
            context.BezierTo(
                new Point(rect.Right - rect.Width * 0.28, rect.Bottom + 3),
                new Point(rect.Left + rect.Width * 0.28, rect.Bottom - 3),
                new Point(rect.Left + 8, rect.Bottom),
                true,
                false);
            context.BezierTo(
                new Point(rect.Left - 3, rect.Bottom - rect.Height * 0.28),
                new Point(rect.Left + 3, rect.Top + rect.Height * 0.28),
                new Point(rect.Left + 8, rect.Top),
                true,
                false);
        }

        outline.Freeze();
        dc.DrawGeometry(Brush("#D8071518"), Pen("#8FC8D2CD", 0.75), outline);
        dc.DrawLine(
            Pen("#B7FF58", 1.0),
            new Point(rect.Left + 12, rect.Top + 15),
            new Point(rect.Right - 12, rect.Top + 15));
        DrawText(dc, title, new Point(rect.Left + 13, rect.Top + 4), 6.5, "#E0ECE8", DisplayTypeface);
        if (rows.Count > 0)
        {
            DrawText(dc, rows[0], new Point(rect.Left + 13, rect.Top + 20), 5.7, "#8FBDB7", DataTypeface);
        }
    }

    private void DrawLagrangeField(DrawingContext dc, Point anchor)
    {
        for (var offset = -20; offset <= 20; offset += 10)
        {
            var geometry = new StreamGeometry();
            using var context = geometry.Open();
            context.BeginFigure(new Point(165, anchor.Y + offset), false, false);
            context.BezierTo(
                new Point(184, anchor.Y + offset * 0.72),
                new Point(198, anchor.Y + offset * 0.18),
                anchor,
                true,
                false);
            context.BezierTo(
                new Point(239, anchor.Y - offset * 0.18),
                new Point(255, anchor.Y - offset * 0.72),
                new Point(274, anchor.Y - offset),
                true,
                false);
            geometry.Freeze();
            dc.DrawGeometry(null, Pen(offset == 0 ? "#B7FF58" : "#3648D8C8", offset == 0 ? 1 : 0.55), geometry);
        }

        dc.DrawEllipse(Brush("#33B7FF58"), null, anchor, 10, 10);
        dc.DrawEllipse(Brush("#B7FF58"), null, anchor, 2.4, 2.4);
        dc.DrawEllipse(Brush("#F7FFF0"), null, anchor, 0.8, 0.8);
    }

    private static StreamGeometry CutCornerGeometry(
        Rect rect,
        double cut,
        bool cutTopRight,
        bool cutBottomLeft)
    {
        var topRight = cutTopRight ? cut : 0;
        var bottomLeft = cutBottomLeft ? cut : 0;
        var geometry = new StreamGeometry();
        using (var context = geometry.Open())
        {
            context.BeginFigure(new Point(rect.Left, rect.Top), true, true);
            context.LineTo(new Point(rect.Right - topRight, rect.Top), true, false);
            context.LineTo(new Point(rect.Right, rect.Top + topRight), true, false);
            context.LineTo(new Point(rect.Right, rect.Bottom), true, false);
            context.LineTo(new Point(rect.Left + bottomLeft, rect.Bottom), true, false);
            context.LineTo(new Point(rect.Left, rect.Bottom - bottomLeft), true, false);
        }

        geometry.Freeze();
        return geometry;
    }

    private static void DrawGrid(DrawingContext dc, string color, int spacing, double opacity)
    {
        var pen = Pen(color, 0.5, opacity);
        for (var x = spacing; x < 400; x += spacing)
        {
            dc.DrawLine(pen, new Point(x, 0), new Point(x, 180));
        }

        for (var y = spacing; y < 180; y += spacing)
        {
            dc.DrawLine(pen, new Point(0, y), new Point(400, y));
        }
    }

    private static void DrawCalibrationCorners(DrawingContext dc, string color)
    {
        var pen = Pen(color, 0.8, 0.7);
        const double length = 9;
        dc.DrawLine(pen, new Point(5, 5), new Point(5 + length, 5));
        dc.DrawLine(pen, new Point(5, 5), new Point(5, 5 + length));
        dc.DrawLine(pen, new Point(395, 5), new Point(395 - length, 5));
        dc.DrawLine(pen, new Point(395, 5), new Point(395, 5 + length));
        dc.DrawLine(pen, new Point(5, 175), new Point(5 + length, 175));
        dc.DrawLine(pen, new Point(5, 175), new Point(5, 175 - length));
        dc.DrawLine(pen, new Point(395, 175), new Point(395 - length, 175));
        dc.DrawLine(pen, new Point(395, 175), new Point(395, 175 - length));
    }

    private static void DrawBracketCorners(DrawingContext dc, Rect rect, string color, double length)
    {
        var pen = Pen(color, 0.75, 0.8);
        dc.DrawLine(pen, rect.TopLeft, new Point(rect.Left + length, rect.Top));
        dc.DrawLine(pen, rect.TopLeft, new Point(rect.Left, rect.Top + length));
        dc.DrawLine(pen, rect.TopRight, new Point(rect.Right - length, rect.Top));
        dc.DrawLine(pen, rect.TopRight, new Point(rect.Right, rect.Top + length));
        dc.DrawLine(pen, rect.BottomRight, new Point(rect.Right - length, rect.Bottom));
        dc.DrawLine(pen, rect.BottomRight, new Point(rect.Right, rect.Bottom - length));
    }

    private static void DrawCrosshair(DrawingContext dc, Point center, string color, bool nightShadow)
    {
        var pen = Pen(color, nightShadow ? 0.75 : 0.65, 0.82);
        dc.DrawEllipse(null, pen, center, 6, 6);
        dc.DrawLine(pen, new Point(center.X - 11, center.Y), new Point(center.X - 4, center.Y));
        dc.DrawLine(pen, new Point(center.X + 4, center.Y), new Point(center.X + 11, center.Y));
        dc.DrawLine(pen, new Point(center.X, center.Y - 11), new Point(center.X, center.Y - 4));
        dc.DrawLine(pen, new Point(center.X, center.Y + 4), new Point(center.X, center.Y + 11));
        dc.DrawEllipse(Brush(color), null, center, 0.9, 0.9);
    }

    private static void DrawGlowLine(
        DrawingContext dc,
        Point start,
        Point end,
        string color)
    {
        dc.DrawLine(Pen(color, 8, 0.06), start, end);
        dc.DrawLine(Pen(color, 4, 0.14), start, end);
        dc.DrawLine(Pen(color, 1.3, 0.94), start, end);
        dc.DrawLine(Pen("#FFF5F6", 0.45, 0.92), start, end);
    }

    private void DrawText(
        DrawingContext dc,
        string text,
        Point origin,
        double size,
        string color,
        Typeface typeface)
    {
        var formatted = new FormattedText(
            text,
            CultureInfo.InvariantCulture,
            System.Windows.FlowDirection.LeftToRight,
            typeface,
            size,
            Brush(color),
            VisualTreeHelper.GetDpi(this).PixelsPerDip);
        dc.DrawText(formatted, origin);
    }

    private static SolidColorBrush Brush(string color)
    {
        var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
        brush.Freeze();
        return brush;
    }

    private static Pen Pen(string color, double thickness, double opacity = 1)
    {
        var penBrush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color))
        {
            Opacity = opacity
        };
        penBrush.Freeze();
        var pen = new Pen(penBrush, thickness)
        {
            DashCap = PenLineCap.Flat
        };
        pen.Freeze();
        return pen;
    }
}
