using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Globalization;
using Point = System.Windows.Point;
using Rectangle = System.Windows.Shapes.Rectangle;

namespace StarBridge.Desktop;

public partial class SquadEmblemCropWindow : Window
{
    private readonly BitmapImage _source;
    private bool _dragging;
    private System.Windows.Point _dragOffset;

    public BitmapSource? CroppedImage { get; private set; }

    public SquadEmblemCropWindow(string imagePath)
    {
        InitializeComponent();

        _source = new BitmapImage();
        _source.BeginInit();
        _source.CacheOption = BitmapCacheOption.OnLoad;
        _source.UriSource = new Uri(imagePath);
        _source.EndInit();
        _source.Freeze();
        SourceImage.Source = _source;
    }

    private void CropCanvas_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        LayoutImage();
        ResetCropFrame();
    }

    private void LayoutImage()
    {
        var rect = GetImageDisplayRect();
        Canvas.SetLeft(SourceImage, rect.X);
        Canvas.SetTop(SourceImage, rect.Y);
        SourceImage.Width = rect.Width;
        SourceImage.Height = rect.Height;
    }

    private void ResetCropFrame()
    {
        var imageRect = GetImageDisplayRect();
        var size = SquareImageCropGeometry.ResolveFrameSize(imageRect, CropScaleSlider.Value);
        CropFrame.Width = size;
        CropFrame.Height = size;
        Canvas.SetLeft(CropFrame, imageRect.X + (imageRect.Width - size) / 2);
        Canvas.SetTop(CropFrame, imageRect.Y + (imageRect.Height - size) / 2);
        RefreshScaleText();
        UpdateShade();
    }

    private void CropScaleSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        RefreshScaleText();
        if (!IsLoaded || CropCanvas.ActualWidth <= 0 || CropCanvas.ActualHeight <= 0)
        {
            return;
        }

        var imageRect = GetImageDisplayRect();
        var current = GetCropRect();
        var centerX = double.IsNaN(current.X) ? imageRect.X + imageRect.Width / 2 : current.X + current.Width / 2;
        var centerY = double.IsNaN(current.Y) ? imageRect.Y + imageRect.Height / 2 : current.Y + current.Height / 2;
        var size = SquareImageCropGeometry.ResolveFrameSize(imageRect, e.NewValue);
        var x = Math.Clamp(centerX - size / 2, imageRect.Left, imageRect.Right - size);
        var y = Math.Clamp(centerY - size / 2, imageRect.Top, imageRect.Bottom - size);
        CropFrame.Width = size;
        CropFrame.Height = size;
        Canvas.SetLeft(CropFrame, x);
        Canvas.SetTop(CropFrame, y);
        UpdateShade();
    }

    private void RefreshScaleText()
    {
        if (CropScaleValueText is not null && CropScaleSlider is not null)
        {
            CropScaleValueText.Text = $"{Math.Round(CropScaleSlider.Value).ToString(CultureInfo.InvariantCulture)}%";
        }
    }

    private Rect GetImageDisplayRect()
    {
        var width = Math.Max(1, CropCanvas.ActualWidth);
        var height = Math.Max(1, CropCanvas.ActualHeight);
        var imageRatio = _source.PixelWidth / (double)_source.PixelHeight;
        var canvasRatio = width / height;

        if (imageRatio > canvasRatio)
        {
            var displayHeight = width / imageRatio;
            return new Rect(0, (height - displayHeight) / 2, width, displayHeight);
        }

        var displayWidth = height * imageRatio;
        return new Rect((width - displayWidth) / 2, 0, displayWidth, height);
    }

    private void CropCanvas_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        var point = e.GetPosition(CropCanvas);
        var crop = GetCropRect();
        if (!crop.Contains(point))
        {
            return;
        }

        _dragging = true;
        _dragOffset = new System.Windows.Point(point.X - crop.X, point.Y - crop.Y);
        CropCanvas.CaptureMouse();
    }

    private void CropCanvas_MouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (!_dragging)
        {
            return;
        }

        var point = e.GetPosition(CropCanvas);
        var imageRect = GetImageDisplayRect();
        var size = CropFrame.Width;
        var x = Math.Clamp(point.X - _dragOffset.X, imageRect.Left, imageRect.Right - size);
        var y = Math.Clamp(point.Y - _dragOffset.Y, imageRect.Top, imageRect.Bottom - size);
        Canvas.SetLeft(CropFrame, x);
        Canvas.SetTop(CropFrame, y);
        UpdateShade();
    }

    private void CropCanvas_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        _dragging = false;
        CropCanvas.ReleaseMouseCapture();
    }

    private void UpdateShade()
    {
        var crop = GetCropRect();
        SetRect(ShadeTop, 0, 0, CropCanvas.ActualWidth, crop.Top);
        SetRect(ShadeLeft, 0, crop.Top, crop.Left, crop.Height);
        SetRect(ShadeRight, crop.Right, crop.Top, CropCanvas.ActualWidth - crop.Right, crop.Height);
        SetRect(ShadeBottom, 0, crop.Bottom, CropCanvas.ActualWidth, CropCanvas.ActualHeight - crop.Bottom);
    }

    private Rect GetCropRect()
    {
        return new Rect(Canvas.GetLeft(CropFrame), Canvas.GetTop(CropFrame), CropFrame.Width, CropFrame.Height);
    }

    private static void SetRect(System.Windows.Shapes.Rectangle rectangle, double x, double y, double width, double height)
    {
        Canvas.SetLeft(rectangle, x);
        Canvas.SetTop(rectangle, y);
        rectangle.Width = Math.Max(0, width);
        rectangle.Height = Math.Max(0, height);
    }

    private void UseCrop_Click(object sender, RoutedEventArgs e)
    {
        var imageRect = GetImageDisplayRect();
        var crop = GetCropRect();
        var scaleX = _source.PixelWidth / imageRect.Width;
        var scaleY = _source.PixelHeight / imageRect.Height;
        var sourceRect = new Int32Rect(
            Math.Clamp((int)((crop.X - imageRect.X) * scaleX), 0, _source.PixelWidth - 1),
            Math.Clamp((int)((crop.Y - imageRect.Y) * scaleY), 0, _source.PixelHeight - 1),
            Math.Clamp((int)(crop.Width * scaleX), 1, _source.PixelWidth),
            Math.Clamp((int)(crop.Height * scaleY), 1, _source.PixelHeight));

        if (sourceRect.X + sourceRect.Width > _source.PixelWidth)
        {
            sourceRect.Width = _source.PixelWidth - sourceRect.X;
        }

        if (sourceRect.Y + sourceRect.Height > _source.PixelHeight)
        {
            sourceRect.Height = _source.PixelHeight - sourceRect.Y;
        }

        CroppedImage = new CroppedBitmap(_source, sourceRect);
        DialogResult = true;
        Close();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) => Cancel_Click(sender, e);

    private void Header_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left)
        {
            return;
        }

        try
        {
            DragMove();
        }
        catch (InvalidOperationException)
        {
            // Mouse capture can be released between the click and the native drag request.
        }
    }

    private void Window_PreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            e.Handled = true;
            DialogResult = false;
            Close();
        }
    }
}

internal static class SquareImageCropGeometry
{
    public static double ResolveFrameSize(Rect imageRect, double percentage)
    {
        var maximum = Math.Max(0, Math.Min(imageRect.Width, imageRect.Height));
        if (maximum <= 0)
        {
            return 0;
        }

        var normalized = Math.Clamp(percentage, 20, 100) / 100d;
        return maximum * normalized;
    }
}
