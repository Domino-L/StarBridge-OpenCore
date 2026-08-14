using System.Windows;

namespace StarBridge.Desktop;

public partial class ShipImagePreviewView : System.Windows.Controls.UserControl
{
    private readonly Func<Task>? _reportImage;

    public ShipImagePreviewView(
        string? imagePath,
        string shipName,
        Func<Task>? reportImage = null)
    {
        InitializeComponent();
        _reportImage = reportImage;
        ReportImageButton.Visibility = reportImage is null
            ? Visibility.Collapsed
            : Visibility.Visible;

        if (string.IsNullOrWhiteSpace(imagePath))
        {
            ImageInfoText.Text = $"暂时无法读取 {shipName} 的图片，请稍后重试。";
            return;
        }

        var image = ImageDecodeCache.Load(imagePath, 4096);
        if (image is null)
        {
            ImageInfoText.Text = $"暂时无法读取 {shipName} 的图片，请确认文件完整后重试。";
            return;
        }

        PreviewImage.Source = image;
        EmptyText.Visibility = Visibility.Collapsed;
        ImageInfoText.Text = $"{image.PixelWidth} × {image.PixelHeight} · 完整图片（未裁切）";
    }

    private async void ReportImageButton_Click(object sender, RoutedEventArgs e)
    {
        if (_reportImage is null)
        {
            return;
        }

        ReportImageButton.IsEnabled = false;
        try
        {
            await _reportImage();
        }
        finally
        {
            ReportImageButton.IsEnabled = true;
        }
    }
}
