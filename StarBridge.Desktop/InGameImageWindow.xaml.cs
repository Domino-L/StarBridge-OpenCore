using Microsoft.Win32;
using System.ComponentModel;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace StarBridge.Desktop;

public partial class InGameImageWindow : Window, IInGameScreenshotVisibilityGuard
{
    private enum ImageRegionAction
    {
        None,
        Crop,
        Zoom
    }

    private BitmapSource? _image;
    private BitmapSource? _originalImage;
    private bool _fitToWindow;
    private bool _updatingZoom;
    private bool _updatingViewportMode;
    private bool _compactSettingsExpanded;
    private string _language = "zh";
    private bool _allowPermanentClose;
    private bool _isPinnedToOverlay;
    private bool _isPureImageMode;
    private bool _isToolbarDockedToBottom;
    private bool _surfaceDragPending;
    private System.Windows.Point _surfaceDragStart;
    private readonly InGameImageViewportPanSession _viewportPan = new();
    private ImageRegionAction _imageRegionAction;
    private bool _isSelectingImageRegion;
    private System.Windows.Point _imageRegionStart;
    private Rect _editingBounds;
    private double _editingMinWidth;
    private double _editingMinHeight;
    private bool _menuSessionActive;
    private bool _screenshotVisibilitySuppressed;
    private InGameMenuSettings _settings = InGameMenuSettings.Default;
    private readonly Dictionary<string, ImageAdjustmentState> _adjustmentsByPath =
        new(StringComparer.OrdinalIgnoreCase);
    private string _currentImagePath = "";
    private readonly System.Windows.Media.Brush? _editingFrameBackground;
    private readonly System.Windows.Media.Brush? _editingSurfaceBackground;
    private readonly DispatcherTimer _foregroundVisibilityTimer = new()
    {
        Interval = TimeSpan.FromMilliseconds(250)
    };
    private readonly DispatcherTimer _modeNotificationTimer = new()
    {
        Interval = TimeSpan.FromSeconds(2.6)
    };

    internal event EventHandler? MenuCloseRequested;
    internal event EventHandler? ToolDeactivated;
    internal event EventHandler? ToolHidden;

    internal bool IsChoosingImage { get; private set; }
    internal bool HasImage => _image is not null;

    internal InGameImageWindow()
    {
        InitializeComponent();
        _editingFrameBackground = ImageWindowFrame.Background;
        _editingSurfaceBackground = ImageSurface.Background;
        ApplyLanguage(_language);
        ApplyImageToolbarDock();
        RefreshPinButtonPresentation();
        InGameToolWindowBehavior.PreventSnapMaximize(this);
        _foregroundVisibilityTimer.Tick += (_, _) => RefreshPinnedVisibility();
        _modeNotificationTimer.Tick += (_, _) =>
        {
            _modeNotificationTimer.Stop();
            ImageModeToast.Visibility = Visibility.Collapsed;
        };
        _foregroundVisibilityTimer.Start();
    }

    internal void ShowForMenu()
    {
        _menuSessionActive = true;
        ApplyEditingPresentation();
        if (WindowState == WindowState.Minimized)
        {
            WindowState = WindowState.Normal;
        }

        Show();
        Activate();
    }

    internal void ApplySettings(InGameMenuSettings settings)
    {
        var rememberAdjustments = settings.RememberImageAdjustments;
        _settings = settings.Normalize();
        if (!rememberAdjustments)
        {
            _adjustmentsByPath.Clear();
        }

        if (_image is null)
        {
            SetFitToWindowState(
                _settings.ImageScaleMode != InGameMenuImageScaleMode.ActualSize);
            ImageOpacitySlider.Value = _settings.ImageDefaultOpacity;
            _isPinnedToOverlay = _settings.ImageDefaultPinned;
            RefreshPinButtonPresentation();
        }
    }

    internal void ApplyLanguage(string? language)
    {
        _language = language?.Trim().StartsWith(
            "zh",
            StringComparison.OrdinalIgnoreCase) == true
            ? "zh"
            : "en";
        RefreshViewportModeOptions();
        RefreshCompactSettingsToggleText();
    }

    internal void HideForMenu()
    {
        SaveCurrentImageAdjustments();
        _menuSessionActive = false;
        if (_isPinnedToOverlay && _image is not null)
        {
            ApplyPinnedPresentation();
            RefreshPinnedVisibility();
            return;
        }

        if (IsVisible)
        {
            Hide();
        }
    }

    internal void CloseForApplication()
    {
        ClosePermanently();
    }

    void IInGameScreenshotVisibilityGuard.BeginScreenshotVisibilitySuppression() =>
        _screenshotVisibilitySuppressed = true;

    void IInGameScreenshotVisibilityGuard.EndScreenshotVisibilitySuppression() =>
        _screenshotVisibilitySuppressed = false;

    private void ChooseImageButton_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Title = "选择参考图",
            Filter = "图片文件|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff|所有文件|*.*",
            CheckFileExists = true,
            Multiselect = false
        };

        IsChoosingImage = true;
        try
        {
            if (dialog.ShowDialog(this) != true)
            {
                return;
            }

            LoadImage(dialog.FileName);
        }
        finally
        {
            IsChoosingImage = false;
            Activate();
        }
    }

    internal void LoadImage(string path)
    {
        if (!InGameImageFilePolicy.IsSupported(path))
        {
            ImageStatusText.Text = "请选择 PNG、JPG、BMP、GIF 或 TIFF 图片";
            return;
        }

        var image = ImageDecodeCache.Load(path, 4096);
        if (image is null)
        {
            ImageStatusText.Text = "图片无法打开，请检查文件是否完整";
            return;
        }

        SaveCurrentImageAdjustments();
        CancelImageRegionSelection();
        _originalImage = image;
        _currentImagePath = Path.GetFullPath(path);
        ImageNameText.Text = Path.GetFileName(path);
        ImageNameText.ToolTip = path;
        EmptyState.Visibility = Visibility.Collapsed;
        ImageStatusText.Text = $"{image.PixelWidth} × {image.PixelHeight} · 仅本机可见";

        if (_settings.RememberImageAdjustments &&
            _adjustmentsByPath.TryGetValue(
                _currentImagePath,
                out var saved))
        {
            _image = saved.EditedImage;
            DisplayedImage.Source = saved.EditedImage;
            ResetImageEditsButton.IsEnabled = saved.IsEdited;
            ImageOpacitySlider.Value = saved.OpacityPercent;
            _isPinnedToOverlay = saved.IsPinned;
            _isToolbarDockedToBottom = saved.ToolbarDockedToBottom;
            SetFitToWindowState(saved.FitToWindow);
            ApplyImageToolbarDock();
            RefreshPinButtonPresentation();
            if (saved.FitToWindow)
            {
                FitImageToViewport();
            }
            else
            {
                SetZoom(saved.ZoomPercent);
            }

            _isPureImageMode = saved.PureImageMode;
            if (_isPureImageMode)
            {
                ApplyBorderlessPresentation(
                    resizeToImage: true,
                    clickThrough: false);
            }
            else
            {
                ApplyEditingPresentation();
            }

            ImageStatusText.Text =
                $"{image.PixelWidth} × {image.PixelHeight} · 已恢复本次运行中的图片调整";
            return;
        }

        _image = image;
        DisplayedImage.Source = image;
        ResetImageEditsButton.IsEnabled = false;
        ImageOpacitySlider.Value = _settings.ImageDefaultOpacity;
        _isPinnedToOverlay = _settings.ImageDefaultPinned;
        RefreshPinButtonPresentation();
        if (_settings.ImageScaleMode == InGameMenuImageScaleMode.ActualSize)
        {
            SetFitToWindowState(false);
            SetZoom(100);
        }
        else
        {
            FitImageToViewport();
        }

        if (_settings.ImageOpenMode == InGameMenuImageOpenMode.ImageOnly &&
            !_isPureImageMode)
        {
            TogglePureImageMode();
        }
    }

    private void SaveCurrentImageAdjustments()
    {
        if (!_settings.RememberImageAdjustments ||
            _image is null ||
            string.IsNullOrWhiteSpace(_currentImagePath))
        {
            return;
        }

        _adjustmentsByPath[_currentImagePath] = new ImageAdjustmentState(
            _image,
            ZoomSlider.Value,
            ImageOpacitySlider.Value,
            _fitToWindow,
            _isPinnedToOverlay,
            _isPureImageMode,
            _isToolbarDockedToBottom,
            ResetImageEditsButton.IsEnabled);
    }

    private void FitButton_Click(object sender, RoutedEventArgs e)
    {
        CancelImageRegionSelection();
        FitImageToViewport();
    }

    private void ActualSizeButton_Click(object sender, RoutedEventArgs e)
    {
        CancelImageRegionSelection();
        SetFitToWindowState(false);
        SetZoom(100);
    }

    private void ImageViewportModeComboBox_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e)
    {
        if (_updatingViewportMode ||
            ImageViewportModeComboBox.SelectedItem is not
                InGameImageViewportModeOption option)
        {
            return;
        }

        CancelImageRegionSelection();
        if (option.Value == InGameImageViewportMode.FullImage)
        {
            FitImageToViewport();
            return;
        }

        SetFitToWindowState(false);
        SetZoom(100);
    }

    private void CropImageButton_Click(object sender, RoutedEventArgs e) =>
        BeginImageRegionSelection(ImageRegionAction.Crop);

    private void ZoomRegionButton_Click(object sender, RoutedEventArgs e) =>
        BeginImageRegionSelection(ImageRegionAction.Zoom);

    private void ResetImageEditsButton_Click(object sender, RoutedEventArgs e)
    {
        if (_originalImage is null)
        {
            return;
        }

        CancelImageRegionSelection();
        _image = _originalImage;
        DisplayedImage.Source = _originalImage;
        ResetImageEditsButton.IsEnabled = false;
        FitImageToViewport();
        ImageStatusText.Text =
            $"{_originalImage.PixelWidth} × {_originalImage.PixelHeight} · 已恢复完整原图";
    }

    private void BeginImageRegionSelection(ImageRegionAction action)
    {
        if (_image is null)
        {
            ImageStatusText.Text = "请先选择图片";
            return;
        }

        if (_isPureImageMode)
        {
            ImageStatusText.Text = "请先双击图片返回编辑模式";
            return;
        }

        if (_imageRegionAction == action)
        {
            CancelImageRegionSelection();
            ImageStatusText.Text = "已取消框选";
            return;
        }

        CancelImageRegionSelection();
        _imageRegionAction = action;
        ImageSurface.Cursor = System.Windows.Input.Cursors.Cross;
        CropImageButton.Content = action == ImageRegionAction.Crop ? "拖动裁剪" : "裁剪";
        ZoomRegionButton.Content = action == ImageRegionAction.Zoom ? "拖动放大" : "局部放大";
        ImageStatusText.Text = action == ImageRegionAction.Crop
            ? "在图片上拖动框选要保留的区域；松开鼠标后立即裁剪，按 ESC 可取消"
            : "在图片上拖动框选要查看的区域；松开鼠标后放大到视口，按 ESC 可取消";
    }

    private void CancelImageRegionSelection()
    {
        _imageRegionAction = ImageRegionAction.None;
        _isSelectingImageRegion = false;
        ImageSurface.ReleaseMouseCapture();
        ImageSurface.Cursor = System.Windows.Input.Cursors.Arrow;
        ImageSelectionRectangle.Visibility = Visibility.Collapsed;
        CropImageButton.Content = "裁剪";
        ZoomRegionButton.Content = "局部放大";
    }

    private bool TryGetImageRegionPoint(
        System.Windows.Input.MouseEventArgs e,
        out System.Windows.Point point)
    {
        point = e.GetPosition(DisplayedImageLayer);
        var width = DisplayedImageLayer.ActualWidth;
        var height = DisplayedImageLayer.ActualHeight;
        return width > 0 &&
               height > 0 &&
               point.X >= 0 &&
               point.Y >= 0 &&
               point.X <= width &&
               point.Y <= height;
    }

    private System.Windows.Point ClampImageRegionPoint(
        System.Windows.Input.MouseEventArgs e)
    {
        var point = e.GetPosition(DisplayedImageLayer);
        return new System.Windows.Point(
            Math.Clamp(point.X, 0, Math.Max(0, DisplayedImageLayer.ActualWidth)),
            Math.Clamp(point.Y, 0, Math.Max(0, DisplayedImageLayer.ActualHeight)));
    }

    private Rect UpdateImageRegionSelection(System.Windows.Point current)
    {
        var left = Math.Min(_imageRegionStart.X, current.X);
        var top = Math.Min(_imageRegionStart.Y, current.Y);
        var selection = new Rect(
            left,
            top,
            Math.Abs(current.X - _imageRegionStart.X),
            Math.Abs(current.Y - _imageRegionStart.Y));
        Canvas.SetLeft(ImageSelectionRectangle, selection.Left);
        Canvas.SetTop(ImageSelectionRectangle, selection.Top);
        ImageSelectionRectangle.Width = selection.Width;
        ImageSelectionRectangle.Height = selection.Height;
        ImageSelectionRectangle.Visibility = Visibility.Visible;
        return selection;
    }

    private void CompleteImageRegionSelection(Rect selection, ImageRegionAction action)
    {
        CancelImageRegionSelection();
        if (selection.Width < 8 || selection.Height < 8)
        {
            ImageStatusText.Text = "框选范围太小，请重新拖动选择";
            return;
        }

        if (action == ImageRegionAction.Crop)
        {
            ApplyImageCrop(selection);
            return;
        }

        ZoomToImageRegion(selection);
    }

    private void ApplyImageCrop(Rect selection)
    {
        if (_image is null ||
            DisplayedImageLayer.ActualWidth <= 0 ||
            DisplayedImageLayer.ActualHeight <= 0)
        {
            return;
        }

        var left = Math.Clamp(
            (int)Math.Floor(selection.Left / DisplayedImageLayer.ActualWidth * _image.PixelWidth),
            0,
            Math.Max(0, _image.PixelWidth - 1));
        var top = Math.Clamp(
            (int)Math.Floor(selection.Top / DisplayedImageLayer.ActualHeight * _image.PixelHeight),
            0,
            Math.Max(0, _image.PixelHeight - 1));
        var right = Math.Clamp(
            (int)Math.Ceiling(selection.Right / DisplayedImageLayer.ActualWidth * _image.PixelWidth),
            left + 1,
            _image.PixelWidth);
        var bottom = Math.Clamp(
            (int)Math.Ceiling(selection.Bottom / DisplayedImageLayer.ActualHeight * _image.PixelHeight),
            top + 1,
            _image.PixelHeight);
        var cropBounds = new Int32Rect(left, top, right - left, bottom - top);
        var croppedImage = new CroppedBitmap(_image, cropBounds);
        if (croppedImage.CanFreeze)
        {
            croppedImage.Freeze();
        }

        _image = croppedImage;
        DisplayedImage.Source = croppedImage;
        ResetImageEditsButton.IsEnabled = true;
        FitImageToViewport();
        ImageStatusText.Text =
            $"已裁剪为 {croppedImage.PixelWidth} × {croppedImage.PixelHeight} · 可点击“重置裁剪”恢复完整原图";
    }

    private void ZoomToImageRegion(Rect selection)
    {
        if (_image is null ||
            DisplayedImageLayer.ActualWidth <= 0 ||
            DisplayedImageLayer.ActualHeight <= 0)
        {
            return;
        }

        var sourceCenterX =
            (selection.Left + selection.Width / 2) / DisplayedImageLayer.ActualWidth;
        var sourceCenterY =
            (selection.Top + selection.Height / 2) / DisplayedImageLayer.ActualHeight;
        var sourceWidth =
            selection.Width / DisplayedImageLayer.ActualWidth * _image.Width;
        var sourceHeight =
            selection.Height / DisplayedImageLayer.ActualHeight * _image.Height;
        var availableWidth = Math.Max(1, ImageScrollViewer.ViewportWidth - 24);
        var availableHeight = Math.Max(1, ImageScrollViewer.ViewportHeight - 24);
        var zoom = Math.Min(
            availableWidth / Math.Max(1, sourceWidth),
            availableHeight / Math.Max(1, sourceHeight)) * 100;

        SetFitToWindowState(false);
        SetZoom(Math.Clamp(zoom, ZoomSlider.Minimum, ZoomSlider.Maximum));
        Dispatcher.BeginInvoke(
            () =>
            {
                var imageWidth = DisplayedImage.ActualWidth;
                var imageHeight = DisplayedImage.ActualHeight;
                var contentLeft = Math.Max(0, (ImageScrollContent.ActualWidth - imageWidth) / 2);
                var contentTop = Math.Max(0, (ImageScrollContent.ActualHeight - imageHeight) / 2);
                ImageScrollViewer.ScrollToHorizontalOffset(
                    contentLeft + sourceCenterX * imageWidth - ImageScrollViewer.ViewportWidth / 2);
                ImageScrollViewer.ScrollToVerticalOffset(
                    contentTop + sourceCenterY * imageHeight - ImageScrollViewer.ViewportHeight / 2);
            },
            DispatcherPriority.Loaded);
        ImageStatusText.Text = $"已放大所选区域 · 当前缩放 {Math.Round(ZoomSlider.Value):0}%";
    }

    private void FitImageToViewport()
    {
        if (_image is null)
        {
            return;
        }

        var availableWidth = Math.Max(1, ImageScrollViewer.ViewportWidth - 24);
        var availableHeight = Math.Max(1, ImageScrollViewer.ViewportHeight - 24);
        var ratio = Math.Min(
            availableWidth / _image.Width,
            availableHeight / _image.Height);
        SetFitToWindowState(true);
        SetZoom(Math.Clamp(ratio * 100, ZoomSlider.Minimum, ZoomSlider.Maximum));
    }

    private void SetFitToWindowState(bool fitToWindow)
    {
        _fitToWindow = fitToWindow;
        RefreshViewportModeSelection();
    }

    private void RefreshViewportModeOptions()
    {
        if (ImageViewportModeComboBox is null)
        {
            return;
        }

        _updatingViewportMode = true;
        var options = InGameImageViewportModePresentation.Options(_language);
        ImageViewportModeComboBox.ItemsSource = options;
        ImageViewportModeComboBox.ToolTip = _language == "zh"
            ? "选择只查看窗口框内区域，或自动显示完整图片"
            : "Choose the framed area or fit the full image";
        System.Windows.Automation.AutomationProperties.SetName(
            ImageViewportModeComboBox,
            _language == "zh" ? "图片显示范围" : "Image display area");
        ImageViewportModeComboBox.SelectedItem = options.First(option =>
            option.Value == (_fitToWindow
                ? InGameImageViewportMode.FullImage
                : InGameImageViewportMode.FramedArea));
        _updatingViewportMode = false;
    }

    private void RefreshViewportModeSelection()
    {
        if (ImageViewportModeComboBox?.ItemsSource is not
            IEnumerable<InGameImageViewportModeOption> options)
        {
            return;
        }

        _updatingViewportMode = true;
        ImageViewportModeComboBox.SelectedItem = options.First(option =>
            option.Value == (_fitToWindow
                ? InGameImageViewportMode.FullImage
                : InGameImageViewportMode.FramedArea));
        _updatingViewportMode = false;
    }

    private void SetZoom(double value)
    {
        if (_image is null)
        {
            return;
        }

        _updatingZoom = true;
        ZoomSlider.Value = value;
        ApplyZoom(value);
        _updatingZoom = false;
    }

    private void ZoomSlider_ValueChanged(
        object sender,
        RoutedPropertyChangedEventArgs<double> e)
    {
        if (!IsInitialized)
        {
            return;
        }

        if (!_updatingZoom)
        {
            SetFitToWindowState(false);
        }

        ApplyZoom(e.NewValue);
    }

    private void ApplyZoom(double percent)
    {
        if (ZoomValueText is null || DisplayedImage is null)
        {
            return;
        }

        ZoomValueText.Text = $"{Math.Round(percent):0}%";
        if (_image is null)
        {
            return;
        }

        var scale = percent / 100d;
        DisplayedImage.Width = Math.Max(1, _image.Width * scale);
        DisplayedImage.Height = Math.Max(1, _image.Height * scale);
    }

    private void ImageOpacitySlider_ValueChanged(
        object sender,
        RoutedPropertyChangedEventArgs<double> e)
    {
        if (!IsInitialized)
        {
            return;
        }

        ImageOpacityValueText.Text = $"{Math.Round(e.NewValue):0}%";
        DisplayedImage.Opacity = Math.Clamp(e.NewValue / 100d, 0.2, 1);
    }

    private void ImageScrollViewer_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (_fitToWindow)
        {
            FitImageToViewport();
        }
    }

    private void ImageToolbar_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (ImageStatusBar is null)
        {
            return;
        }

        ApplyImageToolbarDock();
    }

    private void CompactSettingsToggleButton_Click(object sender, RoutedEventArgs e)
    {
        _compactSettingsExpanded = !_compactSettingsExpanded;
        ApplyImageToolbarDock();
    }

    private void CompactSettingsPopup_Closed(object? sender, EventArgs e)
    {
        _compactSettingsExpanded = false;
        RefreshCompactSettingsToggleText();
    }

    private void CompactSettingsPopup_Opened(object? sender, EventArgs e)
    {
        InGameToolWindowBehavior.SetClickThrough(this, false);
        _ = InGameToolWindowBehavior.TakeForegroundInput(this);
    }

    private void Window_PreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key == Key.Escape && _imageRegionAction != ImageRegionAction.None)
        {
            CancelImageRegionSelection();
            ImageStatusText.Text = "已取消框选";
            e.Handled = true;
            return;
        }

        if (key != Key.Escape)
        {
            return;
        }

        e.Handled = true;
        MenuCloseRequested?.Invoke(this, EventArgs.Empty);
    }

    private void Window_Deactivated(object? sender, EventArgs e) =>
        ToolDeactivated?.Invoke(this, EventArgs.Empty);

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!_allowPermanentClose)
        {
            e.Cancel = true;
            HideForMenu();
            ToolHidden?.Invoke(this, EventArgs.Empty);
            return;
        }

        base.OnClosing(e);
    }

    protected override void OnClosed(EventArgs e)
    {
        SaveCurrentImageAdjustments();
        _foregroundVisibilityTimer.Stop();
        _modeNotificationTimer.Stop();
        base.OnClosed(e);
    }

    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void ImageSurface_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (_image is null || e.ChangedButton != MouseButton.Left)
        {
            return;
        }

        if (_imageRegionAction != ImageRegionAction.None && !_isPureImageMode)
        {
            if (!TryGetImageRegionPoint(e, out var point))
            {
                ImageStatusText.Text = "请从图片内部开始拖动框选";
                e.Handled = true;
                return;
            }

            _imageRegionStart = point;
            _isSelectingImageRegion = true;
            ImageSurface.CaptureMouse();
            UpdateImageRegionSelection(point);
            e.Handled = true;
            return;
        }

        if (e.ClickCount == 2)
        {
            _surfaceDragPending = false;
            EndImageViewportPan();
            e.Handled = true;
            TogglePureImageMode();
            return;
        }

        if (_isPureImageMode)
        {
            EndImageViewportPan();
            _surfaceDragStart = e.GetPosition(this);
            _surfaceDragPending = true;
            e.Handled = true;
            return;
        }

        if (TryGetImageRegionPoint(e, out _) &&
            _viewportPan.TryBegin(
                ImageScrollViewer,
                e.GetPosition(ImageScrollViewer)))
        {
            _surfaceDragPending = false;
            ImageSurface.CaptureMouse();
            ImageSurface.Cursor = System.Windows.Input.Cursors.SizeAll;
            e.Handled = true;
            return;
        }
    }

    private void ImageSurface_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (_isSelectingImageRegion)
        {
            var action = _imageRegionAction;
            var selection = UpdateImageRegionSelection(ClampImageRegionPoint(e));
            CompleteImageRegionSelection(selection, action);
            e.Handled = true;
            return;
        }

        if (_viewportPan.IsActive)
        {
            EndImageViewportPan();
            e.Handled = true;
            return;
        }

        _surfaceDragPending = false;
    }

    private void ImageSurface_MouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (_isSelectingImageRegion && e.LeftButton == MouseButtonState.Pressed)
        {
            UpdateImageRegionSelection(ClampImageRegionPoint(e));
            e.Handled = true;
            return;
        }

        if (_viewportPan.IsActive)
        {
            if (e.LeftButton == MouseButtonState.Pressed)
            {
                _viewportPan.Update(
                    ImageScrollViewer,
                    e.GetPosition(ImageScrollViewer));
            }
            else
            {
                EndImageViewportPan();
            }

            e.Handled = true;
            return;
        }

        if (!_surfaceDragPending ||
            !_isPureImageMode ||
            e.LeftButton != MouseButtonState.Pressed)
        {
            return;
        }

        var current = e.GetPosition(this);
        if (Math.Abs(current.X - _surfaceDragStart.X) < SystemParameters.MinimumHorizontalDragDistance &&
            Math.Abs(current.Y - _surfaceDragStart.Y) < SystemParameters.MinimumVerticalDragDistance)
        {
            return;
        }

        _surfaceDragPending = false;
        try
        {
            DragMove();
        }
        catch (InvalidOperationException)
        {
            // The mouse button may be released while Windows begins the move loop.
        }
    }

    private void ImageSurface_PreviewMouseWheel(
        object sender,
        MouseWheelEventArgs e)
    {
        if (_image is null || e.Delta == 0)
        {
            return;
        }

        // The image surface owns the wheel gesture. Never let ScrollViewer turn
        // it into movement; movement is deliberately reserved for mouse drag.
        e.Handled = true;
        if (_isSelectingImageRegion)
        {
            return;
        }

        var pointerInImage = e.GetPosition(DisplayedImageLayer);
        var pointerInViewport = e.GetPosition(ImageScrollViewer);
        var plan = InGameImageWheelZoom.Project(
            ZoomSlider.Value,
            e.Delta,
            ZoomSlider.Minimum,
            ZoomSlider.Maximum,
            pointerInImage,
            new System.Windows.Size(
                DisplayedImageLayer.ActualWidth,
                DisplayedImageLayer.ActualHeight));
        SetFitToWindowState(false);
        SetZoom(plan.TargetZoom);
        Dispatcher.BeginInvoke(
            () => InGameImageWheelZoom.RestorePointerAnchor(
                ImageScrollViewer,
                ImageScrollContent,
                DisplayedImage,
                pointerInViewport,
                plan),
            DispatcherPriority.Loaded);
    }

    private void EndImageViewportPan()
    {
        _viewportPan.End();
        if (Mouse.Captured == ImageSurface)
        {
            ImageSurface.ReleaseMouseCapture();
        }

        ImageSurface.Cursor = _imageRegionAction == ImageRegionAction.None
            ? System.Windows.Input.Cursors.Arrow
            : System.Windows.Input.Cursors.Cross;
    }

    private void ImageSurface_LostMouseCapture(
        object sender,
        System.Windows.Input.MouseEventArgs e)
    {
        if (!_viewportPan.IsActive)
        {
            return;
        }

        _viewportPan.End();
        ImageSurface.Cursor = _imageRegionAction == ImageRegionAction.None
            ? System.Windows.Input.Cursors.Arrow
            : System.Windows.Input.Cursors.Cross;
    }

    private void ImageSettingsToggleButton_Click(object sender, RoutedEventArgs e)
    {
        _isToolbarDockedToBottom = !_isToolbarDockedToBottom;
        ApplyImageToolbarDock();
    }

    private void PinToOverlayButton_Click(object sender, RoutedEventArgs e)
    {
        if (_image is null)
        {
            ImageStatusText.Text = "请先选择图片，再固定到游戏画面";
            return;
        }

        _isPinnedToOverlay = !_isPinnedToOverlay;
        RefreshPinButtonPresentation();
        ImageStatusText.Text = _isPinnedToOverlay
            ? "固定后仅在 Star Citizen 位于前台时显示；再次打开菜单可调整"
            : "已取消固定；返回游戏后图片窗口会隐藏";
    }

    private void TogglePureImageMode()
    {
        if (_image is null)
        {
            ImageStatusText.Text = "请先选择图片";
            return;
        }

        CancelImageRegionSelection();
        _isPureImageMode = !_isPureImageMode;
        if (_isPureImageMode)
        {
            _isPinnedToOverlay = true;
            RefreshPinButtonPresentation();
            ApplyBorderlessPresentation(resizeToImage: true, clickThrough: false);
            ShowModeNotification("已进入纯图片模式", "双击图片返回编辑");
            return;
        }

        ApplyEditingPresentation();
        ImageStatusText.Text = "已返回编辑模式，可继续调整图片大小、透明度和固定状态";
        ShowModeNotification("已返回编辑模式", "双击图片进入纯图片模式");
    }

    private void ShowModeNotification(string title, string detail)
    {
        ImageModeToastText.Text = $"{title}  ·  {detail}";
        ImageModeToast.Visibility = Visibility.Visible;
        _modeNotificationTimer.Stop();
        _modeNotificationTimer.Start();
    }

    private void ApplyPinnedPresentation()
    {
        if (_image is null)
        {
            Hide();
            return;
        }

        var resizeToImage = ImageWindowChrome.Visibility == Visibility.Visible;
        ApplyBorderlessPresentation(
            resizeToImage,
            clickThrough: !_isPureImageMode);
    }

    private void ApplyBorderlessPresentation(bool resizeToImage, bool clickThrough)
    {
        if (_image is null)
        {
            return;
        }

        var framedArea = CaptureFramedAreaPresentation();
        if (ImageWindowChrome.Visibility == Visibility.Visible)
        {
            _editingBounds = new Rect(Left, Top, ActualWidth, ActualHeight);
            _editingMinWidth = MinWidth;
            _editingMinHeight = MinHeight;
        }

        ImageWindowChrome.Visibility = Visibility.Collapsed;
        ImageToolbar.Visibility = Visibility.Collapsed;
        ImageStatusBar.Visibility = Visibility.Collapsed;
        ImageEditorChrome.Visibility = Visibility.Collapsed;
        ImageTopDockRow.Height = new GridLength(0);
        ImageToolbarTopRow.Height = new GridLength(0);
        ImageStatusTopRow.Height = new GridLength(0);
        ImageStatusBottomRow.Height = new GridLength(0);
        ImageToolbarBottomRow.Height = new GridLength(0);
        ImageBottomDockRow.Height = new GridLength(0);
        ImageWindowFrame.BorderThickness = new Thickness(0);
        ImageAccentLine.Visibility = Visibility.Collapsed;
        // Borderless presentations must hide the editor chrome without disabling
        // scrolling. Disabled resets the viewport offsets to zero and exposes the
        // top-left of the full source image instead of the user's framed area.
        ImageScrollViewer.HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden;
        ImageScrollViewer.VerticalScrollBarVisibility = ScrollBarVisibility.Hidden;
        ImageWindowShellChrome.ResizeBorderThickness = new Thickness(0);
        ResizeMode = ResizeMode.NoResize;
        MinWidth = 1;
        MinHeight = 1;
        ApplyTransparentImageSurface();

        if (framedArea is not null)
        {
            ApplyFramedAreaPresentation(framedArea);
        }
        else if (resizeToImage)
        {
            ResizeAroundCurrentCenter();
        }

        InGameToolWindowBehavior.SetClickThrough(
            this,
            clickThrough,
            preventActivation: _isPureImageMode && !_menuSessionActive);
    }

    private FramedAreaPresentation? CaptureFramedAreaPresentation()
    {
        if (_fitToWindow ||
            _image is null ||
            DisplayedImage.ActualWidth <= 0 ||
            DisplayedImage.ActualHeight <= 0 ||
            ImageScrollViewer.ViewportWidth <= 0 ||
            ImageScrollViewer.ViewportHeight <= 0)
        {
            return null;
        }

        var contentLeft = Math.Max(
            0,
            (ImageScrollContent.ActualWidth - DisplayedImage.ActualWidth) / 2);
        var contentTop = Math.Max(
            0,
            (ImageScrollContent.ActualHeight - DisplayedImage.ActualHeight) / 2);
        var sourceRect = new Rect(
            Math.Clamp(
                (ImageScrollViewer.HorizontalOffset - contentLeft) /
                DisplayedImage.ActualWidth,
                0,
                1),
            Math.Clamp(
                (ImageScrollViewer.VerticalOffset - contentTop) /
                DisplayedImage.ActualHeight,
                0,
                1),
            Math.Clamp(
                ImageScrollViewer.ViewportWidth / DisplayedImage.ActualWidth,
                0,
                1),
            Math.Clamp(
                ImageScrollViewer.ViewportHeight / DisplayedImage.ActualHeight,
                0,
                1));
        var viewportOrigin = ImageScrollViewer.TranslatePoint(
            new System.Windows.Point(),
            this);
        return new FramedAreaPresentation(
            sourceRect,
            new Rect(
                Left + viewportOrigin.X,
                Top + viewportOrigin.Y,
                ImageScrollViewer.ViewportWidth,
                ImageScrollViewer.ViewportHeight));
    }

    private void ApplyFramedAreaPresentation(FramedAreaPresentation presentation)
    {
        Width = Math.Max(1, presentation.WindowBounds.Width);
        Height = Math.Max(1, presentation.WindowBounds.Height);
        Left = presentation.WindowBounds.Left;
        Top = presentation.WindowBounds.Top;
        UpdateLayout();
        RestoreFramedSourceRect(presentation.SourceRect);
        Dispatcher.BeginInvoke(
            () => RestoreFramedSourceRect(presentation.SourceRect),
            DispatcherPriority.Loaded);
    }

    private void RestoreFramedSourceRect(Rect sourceRect)
    {
        if (DisplayedImage.ActualWidth <= 0 || DisplayedImage.ActualHeight <= 0)
        {
            return;
        }

        var contentLeft = Math.Max(
            0,
            (ImageScrollContent.ActualWidth - DisplayedImage.ActualWidth) / 2);
        var contentTop = Math.Max(
            0,
            (ImageScrollContent.ActualHeight - DisplayedImage.ActualHeight) / 2);
        ImageScrollViewer.ScrollToHorizontalOffset(
            contentLeft + sourceRect.X * DisplayedImage.ActualWidth);
        ImageScrollViewer.ScrollToVerticalOffset(
            contentTop + sourceRect.Y * DisplayedImage.ActualHeight);
    }

    private void ApplyTransparentImageSurface()
    {
        ImageWindowFrame.Background = System.Windows.Media.Brushes.Transparent;
        ImageSurface.Background = System.Windows.Media.Brushes.Transparent;
    }

    private void RestoreEditingImageSurface()
    {
        ImageWindowFrame.Background = _editingFrameBackground;
        ImageSurface.Background = _editingSurfaceBackground;
    }

    private void ResizeAroundCurrentCenter()
    {
        var virtualLeft = SystemParameters.VirtualScreenLeft;
        var virtualTop = SystemParameters.VirtualScreenTop;
        var virtualWidth = SystemParameters.VirtualScreenWidth;
        var virtualHeight = SystemParameters.VirtualScreenHeight;
        var width = Math.Clamp(DisplayedImage.Width, 64, virtualWidth);
        var height = Math.Clamp(DisplayedImage.Height, 64, virtualHeight);
        var sourceBounds = _editingBounds.Width > 0 && _editingBounds.Height > 0
            ? _editingBounds
            : new Rect(Left, Top, ActualWidth, ActualHeight);
        var centerX = sourceBounds.Left + sourceBounds.Width / 2;
        var centerY = sourceBounds.Top + sourceBounds.Height / 2;
        Width = width;
        Height = height;
        Left = Math.Clamp(
            centerX - width / 2,
            virtualLeft,
            virtualLeft + virtualWidth - width);
        Top = Math.Clamp(
            centerY - height / 2,
            virtualTop,
            virtualTop + virtualHeight - height);
    }

    private void RefreshPinnedVisibility()
    {
        if (_screenshotVisibilitySuppressed)
        {
            if (IsVisible)
            {
                Hide();
            }

            return;
        }

        if (!_isPinnedToOverlay && !_menuSessionActive)
        {
            if (IsVisible)
            {
                Hide();
            }

            return;
        }

        var shouldShow = InGameGuideImageVisibilityPolicy.ShouldShow(
            _menuSessionActive,
            _isPinnedToOverlay && _image is not null,
            StarCitizenProcessProbe.IsForeground());
        if (shouldShow)
        {
            if (!IsVisible)
            {
                Show();
            }

            return;
        }

        if (IsVisible)
        {
            Hide();
        }
    }

    private void ApplyEditingPresentation()
    {
        InGameToolWindowBehavior.SetClickThrough(this, false);
        if (_isPureImageMode && _image is not null)
        {
            ApplyBorderlessPresentation(resizeToImage: false, clickThrough: false);
            return;
        }

        ImageWindowChrome.Visibility = Visibility.Visible;
        ImageStatusBar.Visibility = Visibility.Visible;
        ImageEditorChrome.Visibility = Visibility.Visible;
        ApplyImageToolbarDock();
        ImageWindowFrame.BorderThickness = new Thickness(1);
        ImageAccentLine.Visibility = Visibility.Visible;
        ImageScrollViewer.HorizontalScrollBarVisibility = ScrollBarVisibility.Auto;
        ImageScrollViewer.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        ImageWindowShellChrome.ResizeBorderThickness = new Thickness(7);
        ResizeMode = ResizeMode.CanResize;
        RestoreEditingImageSurface();
        ApplyZoom(ZoomSlider.Value);

        if (_editingBounds.Width > 0 && _editingBounds.Height > 0)
        {
            MinWidth = _editingMinWidth;
            MinHeight = _editingMinHeight;
            Left = _editingBounds.Left;
            Top = _editingBounds.Top;
            Width = _editingBounds.Width;
            Height = _editingBounds.Height;
        }
    }

    private void ApplyImageToolbarDock()
    {
        var availableToolbarWidth = ImageToolbar.ActualWidth > 0
            ? ImageToolbar.ActualWidth
            : Math.Max(0, Width - 2);
        var layout = InGameImageToolbarLayoutPolicy.Resolve(
            availableToolbarWidth,
            _compactSettingsExpanded);

        ImageEditorChrome.Visibility = Visibility.Visible;
        ImageWindowChrome.Visibility = Visibility.Visible;
        ImageToolbar.Visibility = Visibility.Visible;
        ImageStatusBar.Visibility = layout.StatusHeight > 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        ImageSettingsPanel.Visibility = layout.UseCompactSettings
            ? Visibility.Collapsed
            : Visibility.Visible;
        CompactImageSettingsPanel.Visibility = layout.UseCompactSettings
            ? Visibility.Visible
            : Visibility.Collapsed;
        CompactSettingsPopup.Placement = _isToolbarDockedToBottom
            ? PlacementMode.Top
            : PlacementMode.Bottom;
        CompactSettingsPopup.IsOpen = layout.ShowExpandedSettings;
        RefreshCompactSettingsToggleText();
        Grid.SetRow(ImageEditorChrome, _isToolbarDockedToBottom ? 4 : 0);
        Grid.SetRowSpan(ImageEditorChrome, 3);
        Grid.SetRow(ImageWindowChrome, _isToolbarDockedToBottom ? 6 : 0);
        Grid.SetRow(ImageToolbar, _isToolbarDockedToBottom ? 5 : 1);
        Grid.SetRow(ImageStatusBar, _isToolbarDockedToBottom ? 4 : 2);
        ImageTopDockRow.Height = _isToolbarDockedToBottom
            ? new GridLength(0)
            : new GridLength(52);
        ImageToolbarTopRow.Height = _isToolbarDockedToBottom
            ? new GridLength(0)
            : new GridLength(layout.ToolbarHeight);
        ImageStatusTopRow.Height = _isToolbarDockedToBottom
            ? new GridLength(0)
            : new GridLength(layout.StatusHeight);
        ImageStatusBottomRow.Height = _isToolbarDockedToBottom
            ? new GridLength(layout.StatusHeight)
            : new GridLength(0);
        ImageToolbarBottomRow.Height = _isToolbarDockedToBottom
            ? new GridLength(layout.ToolbarHeight)
            : new GridLength(0);
        ImageBottomDockRow.Height = _isToolbarDockedToBottom
            ? new GridLength(52)
            : new GridLength(0);
        ImageWindowChrome.BorderThickness = _isToolbarDockedToBottom
            ? new Thickness(0, 1, 0, 0)
            : new Thickness(0, 0, 0, 1);
        ImageToolbar.BorderThickness = _isToolbarDockedToBottom
            ? new Thickness(0, 1, 0, 1)
            : new Thickness(0, 0, 0, 1);
        ImageStatusBar.BorderThickness = _isToolbarDockedToBottom
            ? new Thickness(0, 1, 0, 0)
            : new Thickness(0, 0, 0, 1);
        ImageSettingsChevronPath.Data = System.Windows.Media.Geometry.Parse(
            _isToolbarDockedToBottom
                ? "M 3,10 L 8,5 L 13,10"
                : "M 3,6 L 8,11 L 13,6");
        ImageSettingsToggleButton.ToolTip = _isToolbarDockedToBottom
            ? "将编辑栏移到顶部"
            : "将编辑栏移到底部";
    }

    private void RefreshCompactSettingsToggleText()
    {
        if (CompactSettingsToggleButton is null)
        {
            return;
        }

        CompactSettingsToggleButton.Content = _language == "zh"
            ? (_compactSettingsExpanded ? "收起设置" : "展开设置")
            : (_compactSettingsExpanded ? "Hide settings" : "Show settings");
    }

    private void RefreshPinButtonPresentation()
    {
        PinToOverlayButton.ToolTip = _isPinnedToOverlay
            ? "取消固定"
            : "固定到浮层";
        PinGlyphPath.Fill = _isPinnedToOverlay
            ? (System.Windows.Media.Brush)FindResource("AccentBrush")
            : System.Windows.Media.Brushes.White;
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        _isPinnedToOverlay = false;
        RefreshPinButtonPresentation();
        ClosePermanently();
    }

    private void ClosePermanently()
    {
        _allowPermanentClose = true;
        Close();
    }

    private sealed record ImageAdjustmentState(
        BitmapSource EditedImage,
        double ZoomPercent,
        double OpacityPercent,
        bool FitToWindow,
        bool IsPinned,
        bool PureImageMode,
        bool ToolbarDockedToBottom,
        bool IsEdited);

    private sealed record FramedAreaPresentation(
        Rect SourceRect,
        Rect WindowBounds);
}
