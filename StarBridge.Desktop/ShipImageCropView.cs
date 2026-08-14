using StarBridge.Core.ShipMedia;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace StarBridge.Desktop;

public readonly record struct ShipImageCropBounds(
    double Left,
    double Top,
    double Width,
    double Height,
    double OverflowX,
    double OverflowY);

public static class ShipImageCropGeometry
{
    public static ShipImageCropBounds Calculate(
        double sourceWidth,
        double sourceHeight,
        double viewportWidth,
        double viewportHeight,
        ShipImageCropFrame frame)
    {
        if (sourceWidth <= 0 || sourceHeight <= 0 || viewportWidth <= 0 || viewportHeight <= 0)
        {
            return default;
        }

        var normalized = ShipImageCropFrame.Normalize(frame.FocusX, frame.FocusY, frame.Zoom);
        var baseScale = Math.Max(viewportWidth / sourceWidth, viewportHeight / sourceHeight);
        var scale = baseScale * normalized.Zoom;
        var width = sourceWidth * scale;
        var height = sourceHeight * scale;
        var overflowX = Math.Max(0, width - viewportWidth);
        var overflowY = Math.Max(0, height - viewportHeight);
        return new ShipImageCropBounds(
            -overflowX * normalized.FocusX,
            -overflowY * normalized.FocusY,
            width,
            height,
            overflowX,
            overflowY);
    }
}

public sealed class ShipImageCropView : Canvas
{
    public static readonly DependencyProperty SourceProperty = DependencyProperty.Register(
        nameof(Source),
        typeof(ImageSource),
        typeof(ShipImageCropView),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender, OnViewportPropertyChanged));

    public static readonly DependencyProperty FocusXProperty = DependencyProperty.Register(
        nameof(FocusX),
        typeof(double),
        typeof(ShipImageCropView),
        new FrameworkPropertyMetadata(0.5, FrameworkPropertyMetadataOptions.AffectsRender, OnViewportPropertyChanged));

    public static readonly DependencyProperty FocusYProperty = DependencyProperty.Register(
        nameof(FocusY),
        typeof(double),
        typeof(ShipImageCropView),
        new FrameworkPropertyMetadata(0.5, FrameworkPropertyMetadataOptions.AffectsRender, OnViewportPropertyChanged));

    public static readonly DependencyProperty ZoomProperty = DependencyProperty.Register(
        nameof(Zoom),
        typeof(double),
        typeof(ShipImageCropView),
        new FrameworkPropertyMetadata(1.0, FrameworkPropertyMetadataOptions.AffectsRender, OnViewportPropertyChanged));

    private readonly System.Windows.Controls.Image _image;
    private ShipImageCropBounds _bounds;

    public ShipImageCropView()
    {
        ClipToBounds = true;
        SnapsToDevicePixels = true;
        _image = new System.Windows.Controls.Image
        {
            Stretch = Stretch.Fill,
            IsHitTestVisible = false
        };
        RenderOptions.SetBitmapScalingMode(_image, BitmapScalingMode.HighQuality);
        Children.Add(_image);
        SizeChanged += (_, _) => UpdateViewport();
        Loaded += (_, _) => UpdateViewport();
    }

    public ImageSource? Source
    {
        get => (ImageSource?)GetValue(SourceProperty);
        set => SetValue(SourceProperty, value);
    }

    public double FocusX
    {
        get => (double)GetValue(FocusXProperty);
        set => SetValue(FocusXProperty, value);
    }

    public double FocusY
    {
        get => (double)GetValue(FocusYProperty);
        set => SetValue(FocusYProperty, value);
    }

    public double Zoom
    {
        get => (double)GetValue(ZoomProperty);
        set => SetValue(ZoomProperty, value);
    }

    public ShipImageCropFrame CropFrame => ShipImageCropFrame.Normalize(FocusX, FocusY, Zoom);

    public void ResetCropFrame()
    {
        FocusX = 0.5;
        FocusY = 0.5;
        Zoom = 1.0;
    }

    public void PanByPixels(double deltaX, double deltaY)
    {
        var frame = CropFrame;
        if (_bounds.OverflowX > 0.01)
        {
            FocusX = Math.Clamp(frame.FocusX - (deltaX / _bounds.OverflowX), 0.0, 1.0);
        }

        if (_bounds.OverflowY > 0.01)
        {
            FocusY = Math.Clamp(frame.FocusY - (deltaY / _bounds.OverflowY), 0.0, 1.0);
        }
    }

    private static void OnViewportPropertyChanged(DependencyObject sender, DependencyPropertyChangedEventArgs e)
    {
        if (sender is ShipImageCropView view)
        {
            view.UpdateViewport();
        }
    }

    private void UpdateViewport()
    {
        _image.Source = Source;
        if (Source is null || ActualWidth <= 0 || ActualHeight <= 0 || Source.Width <= 0 || Source.Height <= 0)
        {
            _bounds = default;
            return;
        }

        _bounds = ShipImageCropGeometry.Calculate(
            Source.Width,
            Source.Height,
            ActualWidth,
            ActualHeight,
            CropFrame);
        _image.Width = _bounds.Width;
        _image.Height = _bounds.Height;
        Canvas.SetLeft(_image, _bounds.Left);
        Canvas.SetTop(_image, _bounds.Top);
    }
}
