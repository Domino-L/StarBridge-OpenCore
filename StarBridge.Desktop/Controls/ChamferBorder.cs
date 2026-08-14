using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using MediaPen = System.Windows.Media.Pen;
using WpfPoint = System.Windows.Point;

namespace StarBridge.Desktop.Controls;

[Flags]
public enum ChamferCorners
{
    None = 0,
    TopLeft = 1,
    TopRight = 2,
    BottomRight = 4,
    BottomLeft = 8,
    /// <summary>The Bridge signature: cut the top-left and bottom-right.</summary>
    Signature = TopLeft | BottomRight,
    All = TopLeft | TopRight | BottomRight | BottomLeft
}

/// <summary>
/// A <see cref="Border"/> whose corners are cut straight instead of rounded.
///
/// WPF has no clip-path, and clipping a Border with a Geometry removes its stroke
/// along with its corners. Drawing fill and stroke together in OnRender avoids both
/// problems: one element, one geometry, a crisp stroke that follows the cut.
///
/// Layout, Padding and Child handling are inherited from Border unchanged.
/// BorderThickness still drives the layout inset; it is also the stroke width.
/// </summary>
public class ChamferBorder : Border
{
    public static readonly DependencyProperty ChamferProperty =
        DependencyProperty.Register(
            nameof(Chamfer), typeof(double), typeof(ChamferBorder),
            new FrameworkPropertyMetadata(14.0, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty CornersProperty =
        DependencyProperty.Register(
            nameof(Corners), typeof(ChamferCorners), typeof(ChamferBorder),
            new FrameworkPropertyMetadata(ChamferCorners.Signature, FrameworkPropertyMetadataOptions.AffectsRender));

    public double Chamfer
    {
        get => (double)GetValue(ChamferProperty);
        set => SetValue(ChamferProperty, value);
    }

    public ChamferCorners Corners
    {
        get => (ChamferCorners)GetValue(CornersProperty);
        set => SetValue(CornersProperty, value);
    }

    static ChamferBorder()
    {
        // CornerRadius belongs to rounded borders; make it inert here so nobody
        // sets both and wonders which one wins.
        CornerRadiusProperty.OverrideMetadata(
            typeof(ChamferBorder),
            new FrameworkPropertyMetadata(default(CornerRadius)));
    }

    public ChamferBorder()
    {
        SnapsToDevicePixels = true;
        UseLayoutRounding = true;
    }

    protected override void OnRender(DrawingContext dc)
    {
        // Deliberately does not call base: Border would paint a rectangle underneath.
        double w = ActualWidth, h = ActualHeight;
        if (w <= 0 || h <= 0) return;

        double t = BorderThickness.Left;
        bool stroked = t > 0 && BorderBrush != null;
        double inset = stroked ? t / 2.0 : 0;

        var rect = new Rect(inset, inset, Math.Max(0, w - inset * 2), Math.Max(0, h - inset * 2));
        if (rect.Width <= 0 || rect.Height <= 0) return;

        double max = Math.Min(rect.Width, rect.Height) / 2.0;
        double c = Math.Max(0, Math.Min(Chamfer, max));

        Geometry geo = BuildGeometry(rect, c, Corners);

        MediaPen? pen = null;
        if (stroked)
        {
            pen = new MediaPen(BorderBrush, t);
            // A pen containing a data-bound brush cannot be frozen. Freezing is
            // only an optimization, so always check first.
            if (pen.CanFreeze) pen.Freeze();
        }

        dc.DrawGeometry(Background, pen, geo);
    }

    private static Geometry BuildGeometry(Rect r, double c, ChamferCorners corners)
    {
        double tl = corners.HasFlag(ChamferCorners.TopLeft) ? c : 0;
        double tr = corners.HasFlag(ChamferCorners.TopRight) ? c : 0;
        double br = corners.HasFlag(ChamferCorners.BottomRight) ? c : 0;
        double bl = corners.HasFlag(ChamferCorners.BottomLeft) ? c : 0;

        double l = r.Left, t = r.Top, right = r.Right, bottom = r.Bottom;

        var geometry = new StreamGeometry { FillRule = FillRule.Nonzero };
        using (StreamGeometryContext context = geometry.Open())
        {
            context.BeginFigure(new WpfPoint(l + tl, t), isFilled: true, isClosed: true);
            context.LineTo(new WpfPoint(right - tr, t), true, false);
            if (tr > 0) context.LineTo(new WpfPoint(right, t + tr), true, false);
            context.LineTo(new WpfPoint(right, bottom - br), true, false);
            if (br > 0) context.LineTo(new WpfPoint(right - br, bottom), true, false);
            context.LineTo(new WpfPoint(l + bl, bottom), true, false);
            if (bl > 0) context.LineTo(new WpfPoint(l, bottom - bl), true, false);
            context.LineTo(new WpfPoint(l, t + tl), true, false);
        }

        geometry.Freeze();
        return geometry;
    }
}
