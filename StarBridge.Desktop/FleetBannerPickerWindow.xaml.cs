using Microsoft.Win32;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace StarBridge.Desktop;

public partial class FleetBannerPickerWindow : Window
{
    private const double RecommendedRatio = 4.0;
    private readonly string? _currentBannerPath;
    private readonly System.Windows.Media.Brush _dropZoneDefaultBackground;
    private readonly System.Windows.Media.Brush _dropZoneDefaultBorder;
    private BitmapImage? _selectedImage;

    public string? SelectedImagePath { get; private set; }
    public bool RemoveRequested { get; private set; }

    public FleetBannerPickerWindow(string? currentBannerPath)
    {
        InitializeComponent();

        _currentBannerPath = currentBannerPath;
        _dropZoneDefaultBackground = BannerDropZone.Background;
        _dropZoneDefaultBorder = BannerDropZone.BorderBrush;
        RestoreDefaultButton.IsEnabled = !string.IsNullOrWhiteSpace(currentBannerPath);
        RestoreDefaultButton.Opacity = RestoreDefaultButton.IsEnabled ? 1 : 0.62;

        if (TryLoadBitmapImage(currentBannerPath, out var currentImage) && currentImage is not null)
        {
            _selectedImage = currentImage;
            SelectedImagePath = currentBannerPath;
            ApplyImagePreview(currentImage, currentBannerPath, isCurrent: true);
            ApplyButton.IsEnabled = false;
            StatusText.Text = "当前正在使用的舰队横幅。选择新图片后可预览并应用。";
        }
    }

    private void ChooseImage_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Title = "选择舰队横幅",
            Filter = "图片文件 (*.png;*.jpg;*.jpeg;*.bmp;*.webp)|*.png;*.jpg;*.jpeg;*.bmp;*.webp|所有文件 (*.*)|*.*",
            CheckFileExists = true
        };

        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        LoadCandidateImage(dialog.FileName);
    }

    private void BannerDropZone_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (e.OriginalSource is System.Windows.Controls.Button)
        {
            return;
        }

        ChooseImage_Click(sender, new RoutedEventArgs());
    }

    private void BannerDropZone_DragEnter(object sender, System.Windows.DragEventArgs e)
    {
        if (GetFirstDroppedImagePath(e) is null)
        {
            e.Effects = System.Windows.DragDropEffects.None;
            return;
        }

        e.Effects = System.Windows.DragDropEffects.Copy;
        SetDropZoneActive(true);
        e.Handled = true;
    }

    private void BannerDropZone_DragLeave(object sender, System.Windows.DragEventArgs e)
    {
        SetDropZoneActive(false);
    }

    private void BannerDropZone_Drop(object sender, System.Windows.DragEventArgs e)
    {
        SetDropZoneActive(false);

        var path = GetFirstDroppedImagePath(e);
        if (path is null)
        {
            StatusText.Text = "请拖入 PNG、JPG、BMP 或 WebP 图片文件。";
            StatusText.Foreground = FindBrush("StatusWarningBrush", System.Windows.Media.Brushes.Goldenrod);
            return;
        }

        LoadCandidateImage(path);
        e.Handled = true;
    }

    private void LoadCandidateImage(string path)
    {
        if (!TryLoadBitmapImage(path, out var image) || image is null)
        {
            SelectedImagePath = null;
            _selectedImage = null;
            ApplyButton.IsEnabled = false;
            StatusText.Text = "无法读取这张图片。请换用 PNG、JPG、BMP，或确认系统支持该 WebP 文件。";
            StatusText.Foreground = FindBrush("StatusWarningBrush", System.Windows.Media.Brushes.Goldenrod);
            SelectedFileNameText.Text = Path.GetFileName(path);
            SelectedFileStateText.Text = "读取失败，请选择其他图片。";
            SelectedFileStateText.Foreground = FindBrush("StatusWarningBrush", System.Windows.Media.Brushes.Goldenrod);
            PathText.Text = path;
            return;
        }

        SelectedImagePath = path;
        _selectedImage = image;
        RemoveRequested = false;
        ApplyButton.IsEnabled = true;
        ApplyImagePreview(image, path, isCurrent: false);
    }

    private void ApplyImagePreview(BitmapImage image, string? path, bool isCurrent)
    {
        PreviewBannerImage.Source = image;
        PreviewBannerImage.Visibility = Visibility.Visible;
        PreviewScrim.Visibility = Visibility.Visible;
        PreviewPlaceholder.Visibility = Visibility.Collapsed;

        var width = Math.Max(1, image.PixelWidth);
        var height = Math.Max(1, image.PixelHeight);
        var ratio = width / (double)height;
        var ratioDelta = Math.Abs(ratio - RecommendedRatio);
        var fileText = FormatFileSize(path);

        ImageSizeText.Text = $"{width.ToString(CultureInfo.InvariantCulture)} × {height.ToString(CultureInfo.InvariantCulture)}";
        RatioAndFileText.Text = $"{ratio:0.00}:1 / {fileText}";
        PathText.Text = string.IsNullOrWhiteSpace(path) ? "未选择图片" : path;
        SelectedFileNameText.Text = string.IsNullOrWhiteSpace(path) ? "未选择图片" : Path.GetFileName(path);
        SelectedFileStateText.Text = isCurrent ? "当前正在使用的横幅。" : "新横幅已载入，等待应用。";
        SelectedFileStateText.Foreground = isCurrent
            ? FindBrush("MutedTextBrush", System.Windows.Media.Brushes.LightSlateGray)
            : FindBrush("StatusSuccessBrush", System.Windows.Media.Brushes.LightGreen);

        if (width >= 1920 && height >= 480 && ratioDelta <= 0.25)
        {
            FitHintText.Text = "尺寸和比例接近推荐值，可直接作为顶部横幅使用。";
            FitHintText.Foreground = FindBrush("StatusSuccessBrush", System.Windows.Media.Brushes.LightGreen);
        }
        else if (ratioDelta <= 0.65)
        {
            FitHintText.Text = "比例可用，但可能会在顶部栏两侧或上下被裁切。推荐 1920×480。";
            FitHintText.Foreground = FindBrush("StatusWarningBrush", System.Windows.Media.Brushes.Goldenrod);
        }
        else
        {
            FitHintText.Text = "这张图片不是宽幅比例，应用后裁切会比较明显。建议换用约 4:1 的横幅图。";
            FitHintText.Foreground = FindBrush("StatusWarningBrush", System.Windows.Media.Brushes.Goldenrod);
        }

        StatusText.Text = isCurrent
            ? "已载入当前横幅。你可以选择新图片，或恢复默认背景。"
            : "已载入新图片。确认预览效果后点击“应用横幅”。";
        StatusText.Foreground = FindBrush("MutedTextBrush", System.Windows.Media.Brushes.LightSlateGray);
    }

    private static string? GetFirstDroppedImagePath(System.Windows.DragEventArgs e)
    {
        if (!e.Data.GetDataPresent(System.Windows.DataFormats.FileDrop))
        {
            return null;
        }

        if (e.Data.GetData(System.Windows.DataFormats.FileDrop) is not string[] files)
        {
            return null;
        }

        return files.FirstOrDefault(IsSupportedImagePath);
    }

    private static bool IsSupportedImagePath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
        {
            return false;
        }

        var extension = Path.GetExtension(path).ToLowerInvariant();
        return extension is ".png" or ".jpg" or ".jpeg" or ".bmp" or ".webp";
    }

    private void SetDropZoneActive(bool active)
    {
        BannerDropZone.Background = active
            ? FindBrush("AccentPanelBackgroundBrush", new SolidColorBrush(System.Windows.Media.Color.FromRgb(12, 39, 54)))
            : _dropZoneDefaultBackground;
        BannerDropZone.BorderBrush = active
            ? FindBrush("AccentBrush", System.Windows.Media.Brushes.DeepSkyBlue)
            : _dropZoneDefaultBorder;
    }

    private static string FormatFileSize(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
        {
            return "未知大小";
        }

        var length = new FileInfo(path).Length;
        if (length >= 1024 * 1024)
        {
            return $"{length / 1024d / 1024d:0.0} MB";
        }

        return $"{Math.Max(1, length / 1024).ToString(CultureInfo.InvariantCulture)} KB";
    }

    private void RestoreDefault_Click(object sender, RoutedEventArgs e)
    {
        RemoveRequested = true;
        SelectedImagePath = null;
        DialogResult = true;
        Close();
    }

    private void Apply_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(SelectedImagePath) || _selectedImage is null)
        {
            return;
        }

        RemoveRequested = false;
        DialogResult = true;
        Close();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }

    private static bool TryLoadBitmapImage(string? path, out BitmapImage? image)
    {
        image = null;
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
        {
            return false;
        }

        try
        {
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.UriSource = new Uri(path);
            bitmap.EndInit();
            bitmap.Freeze();
            image = bitmap;
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static System.Windows.Media.Brush FindBrush(string resourceKey, System.Windows.Media.Brush fallback)
    {
        return System.Windows.Application.Current.TryFindResource(resourceKey) as System.Windows.Media.Brush ?? fallback;
    }
}
