using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using StarBridge.Core.ShipMedia;

namespace StarBridge.Desktop;

public sealed record ShipImageEditResult(
    byte[] EncodedBytes,
    int SourceWidth,
    int SourceHeight,
    int OutputWidth,
    int OutputHeight,
    string OutputFormat,
    ShipImageCropFrame CropFrame);

public partial class ShipImageEditorView : System.Windows.Controls.UserControl
{
    private sealed record QualityOption(string Label, int MaxWidth, int MaxHeight)
    {
        public override string ToString() => Label;
    }

    private readonly string _imagePath;
    private readonly Action<ShipImageEditResult?> _complete;
    private PreparedShipImageUpload? _prepared;
    private int _quarterTurns;
    private int _renderVersion;
    private bool _initialized;
    private bool _isDraggingSquareCrop;
    private System.Windows.Point _lastSquareCropPoint;

    public ShipImageEditorView(
        string imagePath,
        string shipName,
        Action<ShipImageEditResult?> complete)
    {
        InitializeComponent();
        _imagePath = imagePath;
        _complete = complete;
        QualityComboBox.ItemsSource = new[]
        {
            new QualityOption("高清（推荐） · 最大 1600 × 900", 1600, 900),
            new QualityOption("均衡 · 最大 1280 × 720", 1280, 720),
            new QualityOption("节省流量 · 最大 960 × 540", 960, 540)
        };
        QualityComboBox.SelectedIndex = 0;
        ToolTip = $"为 {shipName} 调整专属图片";
        Loaded += ShipImageEditorView_Loaded;
    }

    private async void ShipImageEditorView_Loaded(object sender, RoutedEventArgs e)
    {
        if (_initialized)
        {
            return;
        }

        _initialized = true;
        await RenderPreviewAsync();
    }

    private async Task RenderPreviewAsync()
    {
        if (QualityComboBox.SelectedItem is not QualityOption quality)
        {
            return;
        }

        var version = ++_renderVersion;
        SetProcessingState(true);
        ErrorText.Visibility = Visibility.Collapsed;
        try
        {
            var prepared = await Task.Run(() => ShipImageUploadProcessor.Prepare(
                _imagePath,
                _quarterTurns,
                quality.MaxWidth,
                quality.MaxHeight));
            if (version != _renderVersion)
            {
                return;
            }

            var preview = CreateBitmapSource(prepared.EncodedBytes);
            _prepared = prepared;
            MainPreviewImage.Source = preview;
            SquarePreviewImage.Source = preview;
            PreviewPlaceholderText.Visibility = Visibility.Collapsed;
            SourceInfoText.Text = $"原图：{prepared.SourceFormat} · {prepared.SourceWidth} × {prepared.SourceHeight}";
            OutputInfoText.Text = $"上传：{prepared.OutputFormat} · {prepared.OutputWidth} × {prepared.OutputHeight} · {FormatBytes(prepared.EncodedBytes.Length)}";
            StatusText.Text = "图片已准备好。机库保留完整画面，方形位置会使用右侧取景。";
            ConfirmButton.IsEnabled = true;
        }
        catch (Exception ex)
        {
            if (version != _renderVersion)
            {
                return;
            }

            _prepared = null;
            MainPreviewImage.Source = null;
            SquarePreviewImage.Source = null;
            PreviewPlaceholderText.Text = "图片暂时无法预览";
            PreviewPlaceholderText.Visibility = Visibility.Visible;
            ErrorText.Text = ex is InvalidDataException
                ? ex.Message
                : "暂时无法读取这张图片。请尝试导出为 PNG、JPG 或 WebP 后重试。";
            ErrorText.Visibility = Visibility.Visible;
            StatusText.Text = "这张图片尚未准备好。";
            ConfirmButton.IsEnabled = false;
        }
        finally
        {
            if (version == _renderVersion)
            {
                SetProcessingState(false);
            }
        }
    }

    private void SetProcessingState(bool processing)
    {
        RotateLeftButton.IsEnabled = !processing;
        RotateRightButton.IsEnabled = !processing;
        QualityComboBox.IsEnabled = !processing;
        if (processing)
        {
            StatusText.Text = "正在优化图片…";
            ConfirmButton.IsEnabled = false;
        }
    }

    private async void RotateLeftButton_Click(object sender, RoutedEventArgs e)
    {
        _quarterTurns = (_quarterTurns + 3) % 4;
        ResetSquareCrop();
        await RenderPreviewAsync();
    }

    private async void RotateRightButton_Click(object sender, RoutedEventArgs e)
    {
        _quarterTurns = (_quarterTurns + 1) % 4;
        ResetSquareCrop();
        await RenderPreviewAsync();
    }

    private void SquareCropViewport_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        _isDraggingSquareCrop = true;
        _lastSquareCropPoint = e.GetPosition(SquareCropViewport);
        SquareCropViewport.CaptureMouse();
        e.Handled = true;
    }

    private void SquareCropViewport_MouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (!_isDraggingSquareCrop || e.LeftButton != MouseButtonState.Pressed)
        {
            return;
        }

        var current = e.GetPosition(SquareCropViewport);
        SquarePreviewImage.PanByPixels(
            current.X - _lastSquareCropPoint.X,
            current.Y - _lastSquareCropPoint.Y);
        _lastSquareCropPoint = current;
        StatusText.Text = "方形取景已调整；机库中的完整原图不会改变。";
        e.Handled = true;
    }

    private void SquareCropViewport_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        EndSquareCropDrag();
        e.Handled = true;
    }

    private void SquareCropViewport_LostMouseCapture(object sender, System.Windows.Input.MouseEventArgs e) =>
        _isDraggingSquareCrop = false;

    private void EndSquareCropDrag()
    {
        _isDraggingSquareCrop = false;
        if (SquareCropViewport.IsMouseCaptured)
        {
            SquareCropViewport.ReleaseMouseCapture();
        }
    }

    private void CropZoomSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (SquarePreviewImage is null)
        {
            return;
        }

        SquarePreviewImage.Zoom = e.NewValue;
        if (_initialized)
        {
            StatusText.Text = "方形缩放已调整；机库中的完整原图不会改变。";
        }
    }

    private void ResetSquareCropButton_Click(object sender, RoutedEventArgs e) => ResetSquareCrop();

    private void ResetSquareCrop()
    {
        if (SquarePreviewImage is null || CropZoomSlider is null)
        {
            return;
        }

        SquarePreviewImage.ResetCropFrame();
        CropZoomSlider.Value = 1;
        if (_initialized)
        {
            StatusText.Text = "方形取景已恢复居中。";
        }
    }

    private async void QualityComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_initialized)
        {
            await RenderPreviewAsync();
        }
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e) => _complete(null);

    private void ConfirmButton_Click(object sender, RoutedEventArgs e)
    {
        if (_prepared is null)
        {
            return;
        }

        _complete(new ShipImageEditResult(
            _prepared.EncodedBytes,
            _prepared.SourceWidth,
            _prepared.SourceHeight,
            _prepared.OutputWidth,
            _prepared.OutputHeight,
            _prepared.OutputFormat,
            SquarePreviewImage.CropFrame));
    }

    private static BitmapImage CreateBitmapSource(byte[] bytes)
    {
        using var stream = new MemoryStream(bytes, writable: false);
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.StreamSource = stream;
        image.EndInit();
        image.Freeze();
        return image;
    }

    private static string FormatBytes(int bytes) =>
        bytes >= 1024 * 1024
            ? $"{bytes / 1024d / 1024d:0.00} MB"
            : $"{Math.Max(1, bytes / 1024d):0} KB";
}
