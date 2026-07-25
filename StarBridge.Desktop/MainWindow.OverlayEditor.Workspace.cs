using Microsoft.Win32;
using StarBridge.Core.Events;
using StarBridge.Core.State;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using Cursors = System.Windows.Input.Cursors;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using OpenFileDialog = Microsoft.Win32.OpenFileDialog;
using Pen = System.Windows.Media.Pen;
using Point = System.Windows.Point;
using SaveFileDialog = Microsoft.Win32.SaveFileDialog;
using WinForms = System.Windows.Forms;
using ControlsImage = System.Windows.Controls.Image;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void ToggleOverlayEditorGrid_Click(object sender, RoutedEventArgs e)
    {
        _isOverlayEditorGridVisible = !_isOverlayEditorGridVisible;
        ApplyOverlayEditorChromeState();
    }

    private void OverlaySettingsShowGridCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isSyncingOverlayEditorPlacementControls ||
            OverlaySettingsShowGridCheck is null)
        {
            return;
        }

        _isOverlayEditorGridVisible = OverlaySettingsShowGridCheck.IsChecked == true;
        ApplyOverlayEditorChromeState();
    }

    private void ToggleOverlayEditorLivePreview_Click(object sender, RoutedEventArgs e)
    {
        if (!_isOverlayEditorFullScreen)
        {
            SetOverlayEditorLivePreviewEnabled(false);
            ApplyOverlayEditorChromeState();
            RenderOverlayEditor();
            return;
        }

        SetOverlayEditorLivePreviewEnabled(!_isOverlayEditorLivePreviewEnabled);
        ApplyOverlayEditorChromeState();
        RenderOverlayEditor();
        if (sender is FrameworkElement element)
        {
            NotifyOverlaySettingsGuideTarget(element);
        }
    }

    private void ToggleOverlayFullScreenTools_Click(object sender, RoutedEventArgs e)
    {
        if (!_isOverlayEditorFullScreen)
        {
            _isOverlayFullScreenToolsOpen = false;
            ApplyOverlayEditorChromeState();
            return;
        }

        _isOverlayFullScreenToolsOpen = !_isOverlayFullScreenToolsOpen;
        ApplyOverlayEditorChromeState();
    }

    private void OverlayFullScreenToolsDragHandle_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (!_isOverlayEditorFullScreen ||
            OverlayFullScreenToolsPanelTransform is null ||
            OverlayEditorPreviewGrid is null)
        {
            return;
        }

        _isOverlayFullScreenToolsDragging = true;
        _overlayFullScreenToolsDragStartPoint = e.GetPosition(OverlayEditorPreviewGrid);
        _overlayFullScreenToolsDragStartX = OverlayFullScreenToolsPanelTransform.X;
        _overlayFullScreenToolsDragStartY = OverlayFullScreenToolsPanelTransform.Y;
        if (sender is UIElement element)
        {
            element.CaptureMouse();
        }

        e.Handled = true;
    }

    private void OverlayFullScreenToolsPanel_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (IsOverlayFullScreenToolsInteractiveSource(e.OriginalSource as DependencyObject))
        {
            return;
        }

        OverlayFullScreenToolsDragHandle_MouseLeftButtonDown(sender, e);
    }

    private static bool IsOverlayFullScreenToolsInteractiveSource(DependencyObject? source)
    {
        return FindVisualParent<System.Windows.Controls.Primitives.ButtonBase>(source) is not null ||
               FindVisualParent<System.Windows.Controls.Slider>(source) is not null ||
               FindVisualParent<System.Windows.Controls.TextBox>(source) is not null ||
               FindVisualParent<System.Windows.Controls.ComboBox>(source) is not null ||
               FindVisualParent<System.Windows.Controls.Primitives.ScrollBar>(source) is not null;
    }

    private void OverlayFullScreenToolsDragHandle_MouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (!_isOverlayFullScreenToolsDragging ||
            OverlayFullScreenToolsPanelTransform is null ||
            OverlayFullScreenToolsPanel is null ||
            OverlayEditorPreviewGrid is null)
        {
            return;
        }

        var point = e.GetPosition(OverlayEditorPreviewGrid);
        var nextX = _overlayFullScreenToolsDragStartX + point.X - _overlayFullScreenToolsDragStartPoint.X;
        var nextY = _overlayFullScreenToolsDragStartY + point.Y - _overlayFullScreenToolsDragStartPoint.Y;

        var topLeft = OverlayFullScreenToolsPanel.TransformToAncestor(OverlayEditorPreviewGrid).Transform(new System.Windows.Point(0, 0));
        var baseLeft = topLeft.X - OverlayFullScreenToolsPanelTransform.X;
        var baseTop = topLeft.Y - OverlayFullScreenToolsPanelTransform.Y;
        var maxX = OverlayEditorPreviewGrid.ActualWidth - baseLeft - OverlayFullScreenToolsPanel.ActualWidth - 8;
        var maxY = OverlayEditorPreviewGrid.ActualHeight - baseTop - OverlayFullScreenToolsPanel.ActualHeight - 8;
        OverlayFullScreenToolsPanelTransform.X = Math.Clamp(nextX, -baseLeft + 8, Math.Max(-baseLeft + 8, maxX));
        OverlayFullScreenToolsPanelTransform.Y = Math.Clamp(nextY, -baseTop + 8, Math.Max(-baseTop + 8, maxY));
        e.Handled = true;
    }

    private void OverlayFullScreenToolsDragHandle_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (!_isOverlayFullScreenToolsDragging)
        {
            return;
        }

        _isOverlayFullScreenToolsDragging = false;
        if (sender is UIElement element && element.IsMouseCaptured)
        {
            element.ReleaseMouseCapture();
        }

        e.Handled = true;
    }

    private void ToggleOverlayEditorFullScreen_Click(object sender, RoutedEventArgs e)
    {
        var enteredFullScreen = false;
        if (_isOverlayEditorFullScreen)
        {
            if (!TryExitOverlayEditorFullScreen())
            {
                return;
            }
        }
        else
        {
            EnterOverlayEditorFullScreen();
            enteredFullScreen = true;
        }

        ApplyOverlayEditorChromeState();
        RenderOverlayEditor();
        if (enteredFullScreen)
        {
            NotifyOverlaySettingsGuideTarget(OverlayEditorFullScreenButton);
        }
    }

    private void MainWindow_Activated(object? sender, EventArgs e)
    {
        if (_isOverlayEditorFullScreen)
        {
            ScheduleOverlayEditorFullScreenTaskbarState();
        }
    }

    private void MainWindow_Deactivated(object? sender, EventArgs e)
    {
        if (_isOverlayEditorFullScreen)
        {
            WindowsFullscreenTaskbar.SetFullscreen(this, false);
        }
    }

    private void OverlaySnapModeBox_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if (_isSyncingOverlayEditorPlacementControls)
        {
            return;
        }

        _overlayEditorSnapSize = TryReadOverlaySnapSize(sender as System.Windows.Controls.ComboBox, out var snapSize)
            ? snapSize
            : 0;

        ApplyOverlayEditorChromeState();
    }

    private void OverlayFullScreenSnapModeBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isSyncingOverlayEditorPlacementControls)
        {
            return;
        }

        _overlayEditorSnapSize = TryReadOverlaySnapSize(sender as System.Windows.Controls.ComboBox, out var snapSize)
            ? snapSize
            : 0;

        ApplyOverlayEditorChromeState();
    }

    private static bool TryReadOverlaySnapSize(System.Windows.Controls.ComboBox? comboBox, out double snapSize)
    {
        snapSize = 0;
        if (comboBox?.SelectedItem is not ComboBoxItem item ||
            !double.TryParse(item.Tag?.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed))
        {
            return false;
        }

        snapSize = Math.Max(0, parsed);
        return true;
    }

    private static int GetOverlaySnapModeSelectedIndex(double snapSize)
    {
        if (snapSize <= 0)
        {
            return 0;
        }

        if (snapSize <= 16)
        {
            return 1;
        }

        if (snapSize <= 32)
        {
            return 2;
        }

        return 3;
    }

    private void OverlaySettingsSnapEdgeCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isSyncingOverlayEditorPlacementControls ||
            OverlaySettingsSnapEdgeCheck is null)
        {
            return;
        }

        _isOverlayEditorEdgeSnapEnabled = OverlaySettingsSnapEdgeCheck.IsChecked == true;
        ApplyOverlayEditorChromeState();
    }

    private void OverlayFullScreenShowGridCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isSyncingOverlayEditorPlacementControls ||
            OverlayFullScreenShowGridCheck is null)
        {
            return;
        }

        _isOverlayEditorGridVisible = OverlayFullScreenShowGridCheck.IsChecked == true;
        ApplyOverlayEditorChromeState();
    }

    private void OverlayFullScreenSnapGridCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isSyncingOverlayEditorPlacementControls ||
            OverlayFullScreenSnapGridCheck is null)
        {
            return;
        }

        _overlayEditorSnapSize = OverlayFullScreenSnapGridCheck.IsChecked == true ? 64 : 0;
        ApplyOverlayEditorChromeState();
    }

    private void OverlayFullScreenSnapEdgeCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isSyncingOverlayEditorPlacementControls ||
            OverlayFullScreenSnapEdgeCheck is null)
        {
            return;
        }

        _isOverlayEditorEdgeSnapEnabled = OverlayFullScreenSnapEdgeCheck.IsChecked == true;
        ApplyOverlayEditorChromeState();
    }

    private void OverlayFullScreenLockLayoutCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isSyncingOverlayEditorPlacementControls ||
            OverlayFullScreenLockLayoutCheck is null)
        {
            return;
        }

        SetOverlayLayoutLocked(OverlayFullScreenLockLayoutCheck.IsChecked == true);
    }

    private void OverlayFullScreenLivePreviewCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isSyncingOverlayEditorPlacementControls ||
            OverlayFullScreenLivePreviewCheck is null)
        {
            return;
        }

        SetOverlayEditorLivePreviewEnabled(OverlayFullScreenLivePreviewCheck.IsChecked == true);
        ApplyOverlayEditorChromeState();
        RenderOverlayEditor();
    }

    private void OverlaySettingsSnapGridCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isSyncingOverlayEditorPlacementControls ||
            OverlaySettingsSnapGridCheck is null)
        {
            return;
        }

        _overlayEditorSnapSize = OverlaySettingsSnapGridCheck.IsChecked == true ? 64 : 0;
        ApplyOverlayEditorChromeState();
    }

    private void ToggleOverlayLayoutLock_Click(object sender, RoutedEventArgs e)
    {
        SetOverlayLayoutLocked(!_isOverlayLayoutLocked);
    }

    private void OverlaySettingsLockLayoutCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isSyncingOverlayEditorPlacementControls ||
            OverlaySettingsLockLayoutCheck is null)
        {
            return;
        }

        SetOverlayLayoutLocked(OverlaySettingsLockLayoutCheck.IsChecked == true);
    }

    private void SetOverlayLayoutLocked(bool isLocked)
    {
        if (_isOverlayLayoutLocked == isLocked)
        {
            ApplyOverlayEditorChromeState();
            return;
        }

        _isOverlayLayoutLocked = isLocked;
        _activeOverlayEditorElement?.ReleaseMouseCapture();
        _activeOverlayEventNotificationPreview?.ReleaseMouseCapture();
        _activeOverlayItem = null;
        _activeOverlayEditorElement = null;
        _isOverlayResize = false;
        _isOverlayEventNotificationDrag = false;
        _isOverlayFullScreenToolsDragging = false;
        CancelOverlayMemberColumnSplitDrag();
        _activeOverlayEventNotificationPreview = null;
        ApplyOverlayEditorChromeState();
        RenderOverlayEditor();
    }

    private void ApplyOverlayEditorChromeState()
    {
        ApplyOverlayEditorFullScreenState();
        ApplyOverlayEditorCanvasScaleState();
        var gridSize = _overlayEditorSnapSize > 0 ? _overlayEditorSnapSize : 64;
        if (OverlayEditorGridLayer is not null)
        {
            OverlayEditorGridLayer.Visibility = _isOverlayEditorGridVisible ? Visibility.Visible : Visibility.Collapsed;
            RefreshOverlayEditorGridLayerMetrics();
        }

        if (OverlayEditorGridButton is not null)
        {
            OverlayEditorGridButton.Opacity = _isOverlayEditorGridVisible ? 1.0 : 0.62;
        }

        if (OverlayEditorLivePreviewButton is not null)
        {
            OverlayEditorLivePreviewButton.Visibility = _isOverlayEditorFullScreen ? Visibility.Visible : Visibility.Collapsed;
            OverlayEditorLivePreviewButton.IsEnabled = _isOverlayEditorFullScreen;
            OverlayEditorLivePreviewButton.Content = _isOverlayEditorLivePreviewEnabled ? "关闭模拟" : "模拟信息";
            OverlayEditorLivePreviewButton.Opacity = _isOverlayEditorLivePreviewEnabled ? 1.0 : 0.68;
        }

        if (OverlayFullScreenToolsToggleButton is not null)
        {
            OverlayFullScreenToolsToggleButton.Visibility = _isOverlayEditorFullScreen && !_isOverlayFullScreenToolsOpen
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (OverlayFullScreenToolsPanel is not null)
        {
            OverlayFullScreenToolsPanel.Visibility = _isOverlayEditorFullScreen && _isOverlayFullScreenToolsOpen
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (OverlayEditorFullScreenButton is not null)
        {
            OverlayEditorFullScreenButton.Content = _isOverlayEditorFullScreen ? "退出全屏" : "全屏预览";
            OverlayEditorFullScreenButton.Opacity = _isOverlayEditorFullScreen ? 1.0 : 0.86;
        }

        if (OverlayEditorGridSummaryText is not null)
        {
            var gridText = gridSize.ToString(CultureInfo.InvariantCulture);
            var snapText = _overlayEditorSnapSize > 0
                ? $"{_overlayEditorSnapSize.ToString(CultureInfo.InvariantCulture)}px"
                : "关闭";
            var modeText = _isOverlayEditorFullScreen
                ? _isOverlayEditorLivePreviewEnabled ? "全屏 / 模拟信息" : "全屏 / 布局编辑"
                : "普通编辑";
            var (canvasWidth, canvasHeight) = GetOverlayEditorCanvasDisplaySize();
            var scaleText = _isOverlayEditorFullScreen ? " / 1:1" : " / 适配缩放";
            OverlayEditorGridSummaryText.Text = $"画布 / {canvasWidth} x {canvasHeight}{scaleText} / 网格 {gridText}px / 吸附 {snapText} / {modeText}";
            if (OverlayPreviewFooterText is not null)
            {
                OverlayPreviewFooterText.Text = $"画布：{canvasWidth} x {canvasHeight}    选中模块后可在检查器中查看位置";
            }
        }

        if (OverlayLayoutLockButton is not null)
        {
            OverlayLayoutLockButton.Content = _isOverlayLayoutLocked ? "解锁布局" : "锁定布局";
        }

        RefreshOverlayEditorHistoryButtons();
        SyncOverlayEditorPlacementControls();
        RefreshOverlayFullScreenToolsInspector();
        RefreshOverlayOverviewSummary();

        if (OverlayEditHintText is not null)
        {
            OverlayEditHintText.Text = _isOverlayEditorFullScreen
            ? "全屏编辑按 1:1 对齐真实浮层位置，可直接拖拽调整。"
            : "拖动模块调整位置，拖拽右下角缩放；进入全屏编辑可按 1:1 对齐浮层。";
        }
    }

    private void SyncOverlayEditorPlacementControls()
    {
        _isSyncingOverlayEditorPlacementControls = true;
        try
        {
            if (OverlaySettingsShowGridCheck is not null)
            {
                OverlaySettingsShowGridCheck.IsChecked = _isOverlayEditorGridVisible;
            }

            if (OverlayFullScreenShowGridCheck is not null)
            {
                OverlayFullScreenShowGridCheck.IsChecked = _isOverlayEditorGridVisible;
            }

            if (OverlaySettingsSnapGridCheck is not null)
            {
                OverlaySettingsSnapGridCheck.IsChecked = _overlayEditorSnapSize > 0;
            }

            if (OverlayFullScreenSnapGridCheck is not null)
            {
                OverlayFullScreenSnapGridCheck.IsChecked = _overlayEditorSnapSize > 0;
            }

            var snapModeIndex = GetOverlaySnapModeSelectedIndex(_overlayEditorSnapSize);
            if (OverlaySnapModeBox is not null)
            {
                OverlaySnapModeBox.SelectedIndex = snapModeIndex;
            }

            if (OverlayFullScreenSnapModeBox is not null)
            {
                OverlayFullScreenSnapModeBox.SelectedIndex = snapModeIndex;
            }

            if (OverlaySettingsSnapEdgeCheck is not null)
            {
                OverlaySettingsSnapEdgeCheck.IsChecked = _isOverlayEditorEdgeSnapEnabled;
            }

            if (OverlayFullScreenSnapEdgeCheck is not null)
            {
                OverlayFullScreenSnapEdgeCheck.IsChecked = _isOverlayEditorEdgeSnapEnabled;
            }

            if (OverlaySettingsLockLayoutCheck is not null)
            {
                OverlaySettingsLockLayoutCheck.IsChecked = _isOverlayLayoutLocked;
            }

            if (OverlayFullScreenLockLayoutCheck is not null)
            {
                OverlayFullScreenLockLayoutCheck.IsChecked = _isOverlayLayoutLocked;
            }

            if (OverlayFullScreenLivePreviewCheck is not null)
            {
                OverlayFullScreenLivePreviewCheck.IsChecked = _isOverlayEditorFullScreen && _isOverlayEditorLivePreviewEnabled;
                OverlayFullScreenLivePreviewCheck.IsEnabled = _isOverlayEditorFullScreen;
                OverlayFullScreenLivePreviewCheck.Opacity = _isOverlayEditorFullScreen ? 1.0 : 0.52;
            }
        }
        finally
        {
            _isSyncingOverlayEditorPlacementControls = false;
        }
    }

    private void RefreshOverlayOverviewSummary()
    {
        RefreshOverlayRuntimeStatus();

        if (OverlayOverviewPresetText is not null)
        {
            OverlayOverviewPresetText.Text = GetOverlayPresetDisplayName(_activeOverlayPreset);
        }

        if (OverlayOverviewModuleCountText is not null)
        {
            var enabledModules = 0;
            enabledModules += _overlaySettings.ShowNotice ? 1 : 0;
            enabledModules += _overlaySettings.ShowSquads ? 1 : 0;
            enabledModules += _overlaySettings.ShowMembers ? 1 : 0;
            enabledModules += _overlaySettings.ShowChat ? 1 : 0;
            enabledModules += _overlaySettings.ShowEventNotifications ? 1 : 0;
            OverlayOverviewModuleCountText.Text = _language.Equals("zh", StringComparison.OrdinalIgnoreCase)
                ? $"{enabledModules} 个启用"
                : $"{enabledModules} enabled";
        }

        if (OverlayOverviewLayoutText is not null)
        {
            var (canvasWidth, canvasHeight) = GetOverlayEditorCanvasDisplaySize();
            OverlayOverviewLayoutText.Text = $"{canvasWidth} × {canvasHeight}";
        }

        if (OverlayOverviewSavedText is not null)
        {
            OverlayOverviewSavedText.Text = _overlayEditorLastSavedAt is { } savedAt
                ? savedAt.ToLocalTime().ToString("HH:mm:ss", CultureInfo.CurrentCulture)
                : _language.Equals("zh", StringComparison.OrdinalIgnoreCase) ? "尚无记录" : "No save yet";
        }

        if (OverlayHeaderLastSavedText is not null)
        {
            var savedText = _overlayEditorLastSavedAt is { } savedAt
                ? savedAt.ToLocalTime().ToString("HH:mm:ss", CultureInfo.CurrentCulture)
                : _language.Equals("zh", StringComparison.OrdinalIgnoreCase) ? "尚无本次记录" : "No save this session";
            OverlayHeaderLastSavedText.Text = _language.Equals("zh", StringComparison.OrdinalIgnoreCase)
                ? $"最后保存：{savedText}"
                : $"Last saved: {savedText}";
        }

        if (OverlayOverviewDirtyText is not null)
        {
            var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
            OverlayOverviewDirtyText.Text = _isOverlayEditorLayoutDirty
                ? zh ? "未保存" : "Unsaved"
                : zh ? "无" : "None";
            OverlayOverviewDirtyText.Foreground = _isOverlayEditorLayoutDirty
                ? FindBrush("StatusWarningBrush", Brushes.Orange)
                : FindBrush("MutedTextBrush", Brushes.LightSlateGray);
        }

        if (OverlayPreviewDiscardButton is not null)
        {
            OverlayPreviewDiscardButton.IsEnabled = _isOverlayEditorLayoutDirty;
            OverlayPreviewDiscardButton.Opacity = _isOverlayEditorLayoutDirty ? 1.0 : 0.52;
        }

        if (OverlayFullScreenDiscardButton is not null)
        {
            OverlayFullScreenDiscardButton.IsEnabled = _isOverlayEditorLayoutDirty;
            OverlayFullScreenDiscardButton.Opacity = _isOverlayEditorLayoutDirty ? 1.0 : 0.52;
        }

        if (OverlayFullScreenSaveStateText is not null)
        {
            var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
            if (_isOverlayEditorLayoutDirty)
            {
                OverlayFullScreenSaveStateText.Text = zh ? "有未保存更改" : "Unsaved changes";
                OverlayFullScreenSaveStateText.Foreground = FindBrush("StatusWarningBrush", Brushes.Orange);
            }
            else if (_overlayEditorLastSavedAt is { } savedAt)
            {
                var savedTime = savedAt.ToLocalTime().ToString("HH:mm:ss", CultureInfo.CurrentCulture);
                OverlayFullScreenSaveStateText.Text = zh ? $"已保存 {savedTime}" : $"Saved {savedTime}";
                OverlayFullScreenSaveStateText.Foreground = FindBrush("MutedTextBrush", Brushes.LightSlateGray);
            }
            else
            {
                OverlayFullScreenSaveStateText.Text = zh ? "布局已保存" : "Layout saved";
                OverlayFullScreenSaveStateText.Foreground = FindBrush("MutedTextBrush", Brushes.LightSlateGray);
            }
        }
    }

    private string GetOverlayPresetDisplayName(string preset)
    {
        return _overlayPresetEntries.FirstOrDefault(entry =>
            entry.Id.Equals(preset, StringComparison.OrdinalIgnoreCase))?.Name ?? "预设1";
    }

    private void ApplyOverlayEditorFullScreenState()
    {
        if (OverlayEditorCategoryPanel is null ||
            OverlayEditorSettingsPanel is null ||
            OverlayInspectorPanel is null ||
            OverlayPreviewPanel is null ||
            OverlayEditorCategoryColumn is null ||
            OverlayEditorSettingsColumn is null ||
            OverlayEditorInspectorColumn is null ||
            OverlayEditorPreviewColumn is null)
        {
            return;
        }

        var focus = _isOverlayEditorFullScreen;
        OverlayEditorCategoryPanel.Visibility = focus ? Visibility.Collapsed : Visibility.Visible;
        OverlayEditorSettingsPanel.Visibility = focus ? Visibility.Collapsed : Visibility.Visible;
        OverlayInspectorPanel.Visibility = focus ? Visibility.Collapsed : Visibility.Visible;
        if (OverlayEditRootGrid is not null)
        {
            OverlayEditRootGrid.Margin = focus ? new Thickness(0) : new Thickness(0, 14, 0, 0);
        }

        if (OverlayEditorHeaderPanel is not null)
        {
            OverlayEditorHeaderPanel.Visibility = focus ? Visibility.Collapsed : Visibility.Visible;
        }

        if (OverlayEditorHeaderRow is not null)
        {
            OverlayEditorHeaderRow.Height = focus ? new GridLength(0) : GridLength.Auto;
        }

        OverlayEditorCategoryColumn.Width = focus ? new GridLength(0) : new GridLength(196);
        OverlayEditorSettingsColumn.Width = focus ? new GridLength(0) : new GridLength(360);
        OverlayEditorInspectorColumn.Width = focus ? new GridLength(0) : new GridLength(224);
        OverlayEditorPreviewColumn.Width = new GridLength(1, GridUnitType.Star);

        Grid.SetColumn(OverlayPreviewPanel, focus ? 0 : 3);
        Grid.SetColumnSpan(OverlayPreviewPanel, focus ? 4 : 1);

        OverlayPreviewPanel.Padding = focus ? new Thickness(0) : new Thickness(10);
        OverlayPreviewPanel.BorderThickness = focus ? new Thickness(0) : new Thickness(1);
        OverlayPreviewPanel.CornerRadius = focus ? new CornerRadius(0) : new CornerRadius(2);

        if (OverlayPreviewCanvasHost is not null)
        {
            Grid.SetRow(OverlayPreviewCanvasHost, focus ? 0 : 1);
            Grid.SetRowSpan(OverlayPreviewCanvasHost, focus ? 3 : 1);
            System.Windows.Controls.Panel.SetZIndex(OverlayPreviewCanvasHost, 0);
            OverlayPreviewCanvasHost.BorderThickness = focus ? new Thickness(0) : new Thickness(1);
        }

        if (OverlayPreviewToolbar is not null)
        {
            System.Windows.Controls.Panel.SetZIndex(OverlayPreviewToolbar, focus ? 10 : 0);
            OverlayPreviewToolbar.Margin = focus ? new Thickness(12) : new Thickness(0, 0, 0, 10);
            OverlayPreviewToolbar.Background = focus
                ? Brushes.Transparent
                : Brushes.Transparent;
        }

        if (OverlayPreviewFooterText is not null)
        {
            OverlayPreviewFooterText.Visibility = focus ? Visibility.Collapsed : Visibility.Visible;
        }
    }

    private bool ShouldShowOverlayEditorLivePreview()
    {
        return _isOverlayEditorFullScreen && _isOverlayEditorLivePreviewEnabled;
    }

    private void SetOverlayEditorLivePreviewEnabled(bool enabled)
    {
        var nextEnabled = _isOverlayEditorFullScreen && enabled;
        if (nextEnabled)
        {
            if (!_isOverlayEditorLivePreviewEnabled || _overlayEditorSimulationSample is null)
            {
                RollOverlayEditorSimulationSample();
            }

            _isOverlayEditorLivePreviewEnabled = true;
        }
        else
        {
            _isOverlayEditorLivePreviewEnabled = false;
            _overlayEditorSimulationSample = null;
        }
    }

    private OverlayEditorSimulationSample EnsureOverlayEditorSimulationSample()
    {
        return _overlayEditorSimulationSample ?? RollOverlayEditorSimulationSample();
    }

    private OverlayEditorSimulationSample RollOverlayEditorSimulationSample()
    {
        var currentSquadName = ResolveOverlayEditorSampleCurrentSquadName();
        var members = CreateOverlayEditorSampleMembers(currentSquadName);
        var missingShipCount = members.Count(member => string.IsNullOrWhiteSpace(member.ShipText));
        var missingLocationCount = members.Count(member => string.IsNullOrWhiteSpace(member.LocationText));
        var sampleShips = ResolveOverlayEditorSampleShips(missingShipCount);
        var sampleLocations = ResolveOverlayEditorSampleLocations(missingLocationCount);
        var sampleShipIndex = 0;
        var sampleLocationIndex = 0;
        var fixedMembers = members
            .Select(member =>
            {
                var ship = string.IsNullOrWhiteSpace(member.ShipText)
                    ? sampleShips[Math.Min(sampleShipIndex++, sampleShips.Length - 1)]
                    : member.ShipText;
                var location = string.IsNullOrWhiteSpace(member.LocationText)
                    ? sampleLocations[Math.Min(sampleLocationIndex++, sampleLocations.Length - 1)]
                    : member.LocationText;
                return member with
                {
                    ShipText = ship,
                    LocationText = location
                };
            })
            .ToArray();

        _overlayEditorSimulationSample = new OverlayEditorSimulationSample(
            currentSquadName,
            fixedMembers);
        return _overlayEditorSimulationSample;
    }

    private void EnterOverlayEditorFullScreen()
    {
        if (_isOverlayEditorFullScreen)
        {
            return;
        }

        _overlayEditorFullScreenSnapshot = CreateOverlayEditorFullScreenSnapshot();
        _isOverlayEditorFullScreen = true;
        SetOverlayEditorLivePreviewEnabled(true);
        _isOverlayFullScreenToolsOpen = true;
        ApplyOverlayEditorWindowFullScreenState();
        ApplyOverlayEditorFullScreenState();
        Activate();
        ScheduleOverlayEditorFullScreenTaskbarState();
    }

    private void ScheduleOverlayEditorFullScreenTaskbarState()
    {
        Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Loaded, new Action(() =>
        {
            WindowsFullscreenTaskbar.SetFullscreen(
                this,
                _isOverlayEditorFullScreen && IsActive);
        }));
    }

    private void ExitOverlayEditorFullScreen()
    {
        if (!_isOverlayEditorFullScreen)
        {
            return;
        }

        _isOverlayEditorFullScreen = false;
        WindowsFullscreenTaskbar.SetFullscreen(this, false);
        try
        {
            SetOverlayEditorLivePreviewEnabled(false);
            _isOverlayFullScreenToolsOpen = false;
            _isOverlayFullScreenToolsDragging = false;
            OverlayFullScreenToolsDragHandle?.ReleaseMouseCapture();
            ApplyOverlayEditorFullScreenState();
        }
        finally
        {
            RestoreOverlayEditorWindowState();
        }
    }

    private bool TryExitOverlayEditorFullScreen()
    {
        if (!_isOverlayEditorFullScreen)
        {
            return true;
        }

        ExitOverlayEditorFullScreen();
        return true;
    }

    private bool TryLeaveOverlayEditorTab()
    {
        if (MainTabs is null ||
            !ReferenceEquals(MainTabs.SelectedItem, OverlayEditTab))
        {
            return true;
        }

        if (!TryResolveOverlayEditorUnsavedChanges("离开游戏浮层设置"))
        {
            return false;
        }

        if (_isOverlayEditorFullScreen)
        {
            ExitOverlayEditorFullScreen();
        }

        return true;
    }

    private bool TryResolveOverlayEditorUnsavedChanges(string caption)
    {
        if (!_isOverlayEditorLayoutDirty)
        {
            return true;
        }

        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var result = StarBridgeMessageBox.Show(
            this,
            zh
                ? "当前浮层布局有未保存更改。\n\n是：保存并继续\n否：放弃更改并继续\n取消：留在浮层设置"
                : "The current Overlay layout has unsaved changes.\n\nYes: save and continue\nNo: discard changes and continue\nCancel: stay in Overlay settings",
            caption,
            MessageBoxButton.YesNoCancel,
            MessageBoxImage.Warning);

        if (result == MessageBoxResult.Cancel)
        {
            return false;
        }

        if (result == MessageBoxResult.Yes)
        {
            MarkOverlayEditorLayoutSaved();
            SaveCurrentConfig();
            RefreshOverlayWindow();
        }
        else if (result == MessageBoxResult.No)
        {
            DiscardOverlayEditorLayoutChanges();
        }

        return true;
    }

    private OverlayEditorFullScreenSnapshot CreateOverlayEditorFullScreenSnapshot()
    {
        var normalBounds = GetCurrentWindowNormalBounds();
        return new OverlayEditorFullScreenSnapshot(
            WindowState: WindowState,
            ResizeMode: ResizeMode,
            Topmost: Topmost,
            NormalBounds: normalBounds,
            MinWidth: MinWidth,
            MinHeight: MinHeight,
            FrameBorderThickness: MainWindowFrame?.BorderThickness ?? new Thickness(1),
            MainContentMargin: MainContentGrid?.Margin ?? new Thickness(18),
            OverlayEditRootMargin: OverlayEditRootGrid?.Margin ?? new Thickness(0, 14, 0, 0),
            OverlayEditorHeaderRowHeight: OverlayEditorHeaderRow?.Height ?? GridLength.Auto,
            OverlayEditorHeaderVisibility: OverlayEditorHeaderPanel?.Visibility ?? Visibility.Visible,
            WindowTitleRowHeight: WindowTitleRow?.Height ?? new GridLength(50),
            TopNavigationRowHeight: TopNavigationRow?.Height ?? new GridLength(88),
            TopBannerReserveRowHeight: TopBannerReserveRow?.Height ?? new GridLength(0),
            CustomTitleBarVisibility: CustomTitleBar?.Visibility ?? Visibility.Visible,
            TopFleetBannerVisibility: TopFleetBannerLayer?.Visibility ?? Visibility.Collapsed);
    }

    private Rect GetCurrentWindowNormalBounds()
    {
        var bounds = WindowState == WindowState.Normal
            ? new Rect(Left, Top, Width, Height)
            : RestoreBounds;
        if (bounds.Width <= 1 || bounds.Height <= 1)
        {
            bounds = new Rect(Left, Top, Math.Max(1, Width), Math.Max(1, Height));
        }

        return bounds;
    }

    private void ApplyOverlayEditorWindowFullScreenState()
    {
        WindowState = WindowState.Normal;
        ResizeMode = ResizeMode.NoResize;
        MinWidth = 0;
        MinHeight = 0;

        var bounds = ResolveOverlayTargetSurfaceBounds();
        Left = bounds.Left;
        Top = bounds.Top;
        Width = Math.Max(1, bounds.Width);
        Height = Math.Max(1, bounds.Height);
        Topmost = false;

        if (MainWindowFrame is not null)
        {
            MainWindowFrame.BorderThickness = new Thickness(0);
        }

        if (MainContentGrid is not null)
        {
            MainContentGrid.Margin = new Thickness(0);
        }

        if (WindowTitleRow is not null)
        {
            WindowTitleRow.Height = new GridLength(0);
        }

        if (CustomTitleBar is not null)
        {
            CustomTitleBar.Visibility = Visibility.Collapsed;
        }

        if (TopNavigationRow is not null)
        {
            TopNavigationRow.Height = new GridLength(0);
        }

        if (TopBannerReserveRow is not null)
        {
            TopBannerReserveRow.Height = new GridLength(0);
        }

        if (TopFleetBannerLayer is not null)
        {
            TopFleetBannerLayer.Visibility = Visibility.Collapsed;
        }

    }

    private void RestoreOverlayEditorWindowState()
    {
        WindowsFullscreenTaskbar.SetFullscreen(this, false);
        var snapshot = _overlayEditorFullScreenSnapshot;
        _overlayEditorFullScreenSnapshot = null;
        if (snapshot is null)
        {
            return;
        }

        Topmost = snapshot.Topmost;
        ResizeMode = snapshot.ResizeMode;
        MinWidth = snapshot.MinWidth;
        MinHeight = snapshot.MinHeight;
        WindowState = WindowState.Normal;
        Left = snapshot.NormalBounds.Left;
        Top = snapshot.NormalBounds.Top;
        Width = Math.Max(1, snapshot.NormalBounds.Width);
        Height = Math.Max(1, snapshot.NormalBounds.Height);

        if (MainWindowFrame is not null)
        {
            MainWindowFrame.BorderThickness = snapshot.FrameBorderThickness;
        }

        if (MainContentGrid is not null)
        {
            MainContentGrid.Margin = snapshot.MainContentMargin;
        }

        if (OverlayEditRootGrid is not null)
        {
            OverlayEditRootGrid.Margin = snapshot.OverlayEditRootMargin;
        }

        if (OverlayEditorHeaderRow is not null)
        {
            OverlayEditorHeaderRow.Height = snapshot.OverlayEditorHeaderRowHeight;
        }

        if (OverlayEditorHeaderPanel is not null)
        {
            OverlayEditorHeaderPanel.Visibility = snapshot.OverlayEditorHeaderVisibility;
        }

        if (WindowTitleRow is not null)
        {
            WindowTitleRow.Height = snapshot.WindowTitleRowHeight;
        }

        if (CustomTitleBar is not null)
        {
            CustomTitleBar.Visibility = snapshot.CustomTitleBarVisibility;
        }

        if (TopNavigationRow is not null)
        {
            TopNavigationRow.Height = snapshot.TopNavigationRowHeight;
        }

        if (TopBannerReserveRow is not null)
        {
            TopBannerReserveRow.Height = snapshot.TopBannerReserveRowHeight;
        }

        if (TopFleetBannerLayer is not null)
        {
            TopFleetBannerLayer.Visibility = snapshot.TopFleetBannerVisibility;
        }

        WindowState = snapshot.WindowState;
        UpdateMaximizeButtonText();
        ApplyFleetHeaderBannerImage(TopFleetBannerImage?.Source);
    }

    private Rect SnapOverlayEditorRectPosition(OverlayLayoutItem item, Rect rect)
    {
        if (OverlayEditorCanvas.Width <= 0 || OverlayEditorCanvas.Height <= 0)
        {
            return rect;
        }

        if (_overlayEditorSnapSize > 0)
        {
            rect = new Rect(
                Math.Round(rect.Left / _overlayEditorSnapSize, MidpointRounding.AwayFromZero) * _overlayEditorSnapSize,
                Math.Round(rect.Top / _overlayEditorSnapSize, MidpointRounding.AwayFromZero) * _overlayEditorSnapSize,
                rect.Width,
                rect.Height);
        }

        if (_isOverlayEditorEdgeSnapEnabled)
        {
            rect = SnapOverlayEditorRectPositionAxis(item, rect, horizontal: true);
            rect = SnapOverlayEditorRectPositionAxis(item, rect, horizontal: false);
        }

        return ConstrainCommunicationEventRect(item, ClampOverlayEditorRect(rect));
    }

    private Rect SnapOverlayEditorRectSize(OverlayLayoutItem item, Rect rect)
    {
        if (OverlayEditorCanvas.Width <= 0 || OverlayEditorCanvas.Height <= 0)
        {
            return rect;
        }

        var width = Math.Clamp(rect.Width, 80, Math.Max(80, OverlayEditorCanvas.Width - rect.Left));
        var height = Math.Clamp(rect.Height, 58, Math.Max(58, OverlayEditorCanvas.Height - rect.Top));
        if (_overlayEditorSnapSize > 0)
        {
            width = Math.Round(width / _overlayEditorSnapSize, MidpointRounding.AwayFromZero) * _overlayEditorSnapSize;
            height = Math.Round(height / _overlayEditorSnapSize, MidpointRounding.AwayFromZero) * _overlayEditorSnapSize;
        }

        if (_isOverlayEditorEdgeSnapEnabled)
        {
            if (Math.Abs(OverlayEditorCanvas.Width - (rect.Left + width)) <= OverlayEditorSmartSnapThreshold)
            {
                width = OverlayEditorCanvas.Width - rect.Left;
            }

            if (Math.Abs(OverlayEditorCanvas.Height - (rect.Top + height)) <= OverlayEditorSmartSnapThreshold)
            {
                height = OverlayEditorCanvas.Height - rect.Top;
            }

            var resizedRect = new Rect(rect.Left, rect.Top, width, height);
            width = SnapOverlayEditorResizeEdgeToModules(item, resizedRect, horizontal: true) - rect.Left;
            height = SnapOverlayEditorResizeEdgeToModules(item, resizedRect, horizontal: false) - rect.Top;
            width = Math.Clamp(width, 80, Math.Max(80, OverlayEditorCanvas.Width - rect.Left));
            height = Math.Clamp(height, 58, Math.Max(58, OverlayEditorCanvas.Height - rect.Top));
        }

        return ConstrainCommunicationEventRect(
            item,
            ClampOverlayEditorRect(new Rect(rect.Left, rect.Top, width, height)));
    }

    private Rect SnapOverlayEditorRectPositionAxis(OverlayLayoutItem item, Rect rect, bool horizontal)
    {
        var extent = horizontal ? OverlayEditorCanvas.Width : OverlayEditorCanvas.Height;
        var moduleSnapThreshold = GetOverlayEditorModuleSnapThreshold(horizontal);
        var start = horizontal ? rect.Left : rect.Top;
        var size = horizontal ? rect.Width : rect.Height;
        var anchor = horizontal
            ? GetOverlayEditorHorizontalAnchorPoint(item, rect)
            : GetOverlayEditorVerticalAnchorPoint(item, rect);
        var bestDelta = 0.0;
        var bestDistance = double.MaxValue;

        void Consider(double current, double target)
        {
            var distance = Math.Abs(target - current);
            if (distance <= OverlayEditorSmartSnapThreshold && distance < bestDistance)
            {
                bestDistance = distance;
                bestDelta = target - current;
            }
        }

        Consider(start, 0);
        Consider(start + size, extent);
        Consider(anchor, extent / 2);
        foreach (var target in GetOverlayEditorModuleSnapTargets(item, horizontal))
        {
            ConsiderModule(start, target.Start);
            ConsiderModule(start + size, target.End);
            ConsiderModule(start, target.End);
            ConsiderModule(start + size, target.Start);
            ConsiderModule(anchor, target.Center);
        }

        if (bestDistance == double.MaxValue)
        {
            return rect;
        }

        return horizontal
            ? new Rect(rect.Left + bestDelta, rect.Top, rect.Width, rect.Height)
            : new Rect(rect.Left, rect.Top + bestDelta, rect.Width, rect.Height);

        void ConsiderModule(double current, double target)
        {
            var distance = Math.Abs(target - current);
            if (distance <= moduleSnapThreshold && distance < bestDistance)
            {
                bestDistance = distance;
                bestDelta = target - current;
            }
        }
    }

    private double SnapOverlayEditorResizeEdgeToModules(OverlayLayoutItem item, Rect rect, bool horizontal)
    {
        var edge = horizontal ? rect.Right : rect.Bottom;
        var moduleSnapThreshold = GetOverlayEditorModuleSnapThreshold(horizontal);
        var bestTarget = edge;
        var bestDistance = double.MaxValue;
        foreach (var target in GetOverlayEditorModuleSnapTargets(item, horizontal))
        {
            Consider(target.Start);
            Consider(target.Center);
            Consider(target.End);
        }

        return bestDistance == double.MaxValue ? edge : bestTarget;

        void Consider(double target)
        {
            var distance = Math.Abs(edge - target);
            if (distance <= moduleSnapThreshold && distance < bestDistance)
            {
                bestDistance = distance;
                bestTarget = target;
            }
        }
    }

    private static double GetOverlayEditorModuleSnapThreshold(bool horizontal)
    {
        return horizontal ? OverlayEditorModuleSnapThreshold : OverlayEditorVerticalModuleSnapThreshold;
    }

    private IEnumerable<(double Start, double Center, double End)> GetOverlayEditorModuleSnapTargets(OverlayLayoutItem activeItem, bool horizontal)
    {
        foreach (var item in _overlayLayout.Where(ShouldRenderOverlayEditorItem))
        {
            if (ReferenceEquals(item, activeItem))
            {
                continue;
            }

            var rect = ResolveOverlayEditorItemDisplayRect(item);
            yield return horizontal
                ? (rect.Left, rect.Left + rect.Width / 2, rect.Right)
                : (rect.Top, rect.Top + rect.Height / 2, rect.Bottom);
        }
    }

    private Rect ClampOverlayEditorRect(Rect rect)
    {
        var width = Math.Clamp(rect.Width, 1, Math.Max(1, OverlayEditorCanvas.Width));
        var height = Math.Clamp(rect.Height, 1, Math.Max(1, OverlayEditorCanvas.Height));
        var left = Math.Clamp(rect.Left, 0, Math.Max(0, OverlayEditorCanvas.Width - width));
        var top = Math.Clamp(rect.Top, 0, Math.Max(0, OverlayEditorCanvas.Height - height));
        return new Rect(left, top, width, height);
    }

    private static double GetOverlayEditorHorizontalAnchorPoint(OverlayLayoutItem item, Rect rect)
    {
        return item.HorizontalAnchor switch
        {
            OverlayHorizontalAnchor.Left => rect.Left,
            OverlayHorizontalAnchor.Right => rect.Right,
            _ => rect.Left + rect.Width / 2
        };
    }

    private static double GetOverlayEditorVerticalAnchorPoint(OverlayLayoutItem item, Rect rect)
    {
        return item.VerticalAnchor switch
        {
            OverlayVerticalAnchor.Top => rect.Top,
            OverlayVerticalAnchor.Bottom => rect.Bottom,
            _ => rect.Top + rect.Height / 2
        };
    }

    private void RefreshOverlayEditorAlignmentGuides(OverlayLayoutItem? item)
    {
        if (OverlayEditorCanvas is null)
        {
            return;
        }

        ClearOverlayEditorAlignmentGuides();
        if (item is null ||
            !_overlayLayout.Contains(item) ||
            !ShouldRenderOverlayEditorItem(item) ||
            OverlayEditorCanvas.Width <= 1 ||
            OverlayEditorCanvas.Height <= 1)
        {
            return;
        }

        var rect = ResolveOverlayEditorItemDisplayRect(item);
        var anchorX = GetOverlayEditorHorizontalAnchorPoint(item, rect);
        var anchorY = GetOverlayEditorVerticalAnchorPoint(item, rect);
        AddOverlayEditorGuideLine(OverlayEditorCanvas.Width / 2, true, Brushes.DeepSkyBlue, 0.28, 1);
        AddOverlayEditorGuideLine(OverlayEditorCanvas.Height / 2, false, Brushes.DeepSkyBlue, 0.22, 1);
        AddOverlayEditorGuideLine(anchorX, true, item.Brush, 0.56, 2);
        AddOverlayEditorGuideLine(anchorY, false, item.Brush, 0.46, 2);
        AddOverlayEditorAnchorPoint(anchorX, anchorY, item.Brush);
    }

    private void ClearOverlayEditorAlignmentGuides()
    {
        if (OverlayEditorCanvas is null)
        {
            return;
        }

        var guides = OverlayEditorCanvas.Children
            .OfType<FrameworkElement>()
            .Where(element => Equals(element.Tag, OverlayEditorAlignmentGuideTag))
            .ToArray();
        foreach (var guide in guides)
        {
            OverlayEditorCanvas.Children.Remove(guide);
        }
    }

    private void AddOverlayEditorGuideLine(double position, bool vertical, System.Windows.Media.Brush brush, double opacity, double thickness)
    {
        var line = new Border
        {
            Tag = OverlayEditorAlignmentGuideTag,
            Width = vertical ? thickness : OverlayEditorCanvas.Width,
            Height = vertical ? OverlayEditorCanvas.Height : thickness,
            Background = brush,
            Opacity = opacity,
            IsHitTestVisible = false
        };
        Canvas.SetLeft(line, vertical ? Math.Round(position) - thickness / 2 : 0);
        Canvas.SetTop(line, vertical ? 0 : Math.Round(position) - thickness / 2);
        System.Windows.Controls.Panel.SetZIndex(line, 1800);
        OverlayEditorCanvas.Children.Add(line);
    }

    private void AddOverlayEditorAnchorPoint(double x, double y, System.Windows.Media.Brush brush)
    {
        const double size = 12;
        var point = new Border
        {
            Tag = OverlayEditorAlignmentGuideTag,
            Width = size,
            Height = size,
            Background = new SolidColorBrush(Color.FromArgb(230, 4, 18, 28)),
            BorderBrush = brush,
            BorderThickness = new Thickness(2),
            IsHitTestVisible = false
        };
        Canvas.SetLeft(point, x - size / 2);
        Canvas.SetTop(point, y - size / 2);
        System.Windows.Controls.Panel.SetZIndex(point, 1810);
        OverlayEditorCanvas.Children.Add(point);
    }

    private static SolidColorBrush CreateOverlayEditorPanelBackground(bool isSelected, double backgroundOpacity)
    {
        var baseAlpha = isSelected ? 222 : 204;
        var alpha = (byte)Math.Round(baseAlpha * OverlayLayoutItem.NormalizeBackgroundOpacity(backgroundOpacity));
        return new SolidColorBrush(Color.FromArgb(alpha, 5, 18, 28));
    }

    private FrameworkElement CreateOverlayEditorPanel(OverlayLayoutItem item)
    {
        var isSelected = !_isOverlayEventNotificationSelected &&
            _selectedOverlayInspectorItem?.Key.Equals(item.Key, StringComparison.OrdinalIgnoreCase) == true;
        var selectedBrush = Brushes.WhiteSmoke;
        var effectiveSettings = GetEffectiveOverlaySettings();
        var isLagrangeWeave = effectiveSettings.Skin == OverlaySkin.LagrangeWeave;
        var isVerdict = effectiveSettings.Skin == OverlaySkin.Verdict;
        const bool previewsVerdictAppearance = false;
        var usesCustomChrome = isLagrangeWeave || previewsVerdictAppearance;
        var isPositionLocked = _isOverlayLayoutLocked || item.IsLocked;
        var isFullScreenChatBarrage = IsOverlayChatBarrage(item);
        isPositionLocked |= isFullScreenChatBarrage;
        var border = new Border
        {
            Tag = item,
            Background = usesCustomChrome
                ? Brushes.Transparent
                : CreateOverlayEditorPanelBackground(isSelected, item.BackgroundOpacity),
            BorderBrush = isSelected
                ? selectedBrush
                : usesCustomChrome
                    ? Brushes.Transparent
                    : item.Brush,
            BorderThickness = new Thickness(isSelected ? 2 : usesCustomChrome ? 0 : 1),
            Padding = new Thickness(0),
            Cursor = isPositionLocked ? Cursors.Arrow : Cursors.SizeAll,
            MinWidth = 80,
            MinHeight = 58,
            ClipToBounds = true
        };

        var showLivePreview = ShouldShowOverlayEditorLivePreview();
        var livePreviewPalette = ResolveOverlayEditorPreviewPalette(effectiveSettings.Theme);
        var contentAccent = isLagrangeWeave
            ? livePreviewPalette.Alert
            : previewsVerdictAppearance
                ? livePreviewPalette.Title
                : item.Brush;
        var shell = new Grid
        {
            Margin = isLagrangeWeave
                ? new Thickness(18, 16, 28, 14)
                : previewsVerdictAppearance
                    ? new Thickness(18, 8, 28, 22)
                    : new Thickness(12),
            ClipToBounds = true
        };
        if (showLivePreview)
        {
            shell.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        }
        else
        {
            shell.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(4) });
            shell.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
            shell.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            shell.Children.Add(new Border
            {
                Background = contentAccent,
                Opacity = 0.9
            });
        }

        var title = new TextBlock
        {
            Text = ResolveOverlayEditorPanelTitle(item),
            Foreground = showLivePreview ? livePreviewPalette.Title : contentAccent,
            FontWeight = FontWeights.SemiBold,
            FontSize = 15,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Margin = previewsVerdictAppearance ? new Thickness(52, 0, 0, 18) : new Thickness(0)
        };
        var hint = new TextBlock
        {
            Text = isFullScreenChatBarrage
                ? _language == "zh"
                    ? "全屏轨道 / 随机位置 / 无需布局"
                    : "Full-screen lanes / random position / no layout"
                : _language == "zh"
                    ? $"拖动调整 / 右下缩放 / {GetOverlayAnchorDisplayName(item, true)}"
                    : $"Drag to move / resize corner / {GetOverlayAnchorDisplayName(item, true)}",
            Foreground = Brushes.LightSlateGray,
            FontSize = 11,
            Margin = new Thickness(0, 4, 0, 6),
            TextTrimming = TextTrimming.CharacterEllipsis
        };

        var content = new StackPanel
        {
            ClipToBounds = true,
            Opacity = OverlayLayoutItem.NormalizeTextOpacity(item.TextOpacity)
        };
        Grid.SetColumn(content, showLivePreview ? 0 : 2);
        content.Children.Add(title);
        if (showLivePreview)
        {
            foreach (var element in CreateOverlayEditorLivePreviewLines(item))
            {
                content.Children.Add(element);
            }
        }
        else
        {
            if (isSelected)
            {
                content.Children.Add(hint);
            }

            content.Children.Add(CreateOverlayEditorSkeletonLine(0.72, contentAccent));
            content.Children.Add(CreateOverlayEditorSkeletonLine(0.58, contentAccent));
            content.Children.Add(CreateOverlayEditorSkeletonLine(0.44, contentAccent));
        }
        shell.Children.Add(content);

        var handle = new Border
        {
            Width = 18,
            Height = 18,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Bottom,
            Background = contentAccent,
            Cursor = isPositionLocked ? Cursors.Arrow : Cursors.SizeNWSE,
            Opacity = isPositionLocked ? 0.26 : 0.82,
            Margin = new Thickness(0, 0, 5, 5)
        };
        handle.MouseLeftButtonDown += OverlayResize_MouseLeftButtonDown;

        var anchorBadge = new Border
        {
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, 7, 7, 0),
            Padding = new Thickness(7, 3, 7, 3),
            Background = new SolidColorBrush(Color.FromArgb(178, 7, 27, 42)),
            BorderBrush = selectedBrush,
            BorderThickness = new Thickness(1),
            IsHitTestVisible = false,
            Child = new TextBlock
            {
                Text = GetOverlayAnchorDisplayName(item, true),
                Foreground = selectedBrush,
                FontSize = 10,
                FontWeight = FontWeights.SemiBold
            }
        };

        var wrapper = new Grid { ClipToBounds = true };
        if (isLagrangeWeave)
        {
            var join = ResolveLagrangeEditorPanelJoin(item);
            if (effectiveSettings.NightShadowBloom != OverlayNightShadowBloom.Off)
            {
                wrapper.Children.Add(new LagrangeWeaveEditorChrome(
                    item.Key,
                    join,
                    item.BackgroundOpacity,
                    glowOnly: true)
                {
                    Effect = new System.Windows.Media.Effects.BlurEffect
                    {
                        Radius = effectiveSettings.NightShadowBloom == OverlayNightShadowBloom.Strong ? 8 : 5
                    },
                    Opacity = effectiveSettings.NightShadowBloom == OverlayNightShadowBloom.Strong ? 0.82 : 0.62
                });
            }

            wrapper.Children.Add(new LagrangeWeaveEditorChrome(
                item.Key,
                join,
                item.BackgroundOpacity));
        }

        wrapper.Children.Add(shell);

        if (isSelected)
        {
            wrapper.Children.Add(anchorBadge);
            wrapper.Children.Add(CreateOverlayEditorSelectedModuleBadge(selectedBrush));

            if (item.Key.Equals("Members", StringComparison.OrdinalIgnoreCase))
            {
                wrapper.Children.Add(CreateOverlayEditorMemberColumnHint());
            }

            if (!isFullScreenChatBarrage)
            {
                wrapper.Children.Add(handle);
            }
        }

        border.Child = wrapper;

        border.MouseLeftButtonDown += OverlayPanel_MouseLeftButtonDown;
        border.MouseMove += OverlayPanel_MouseMove;
        border.MouseLeftButtonUp += OverlayPanel_MouseLeftButtonUp;
        return border;
    }

    private LagrangePanelJoin ResolveLagrangeEditorPanelJoin(OverlayLayoutItem item)
    {
        if (!IsLagrangeJoinableModule(item.Key) ||
            OverlayEditorCanvas is null ||
            OverlayEditorCanvas.Width <= 1 ||
            OverlayEditorCanvas.Height <= 1)
        {
            return LagrangePanelJoin.None;
        }

        var current = ResolveOverlayEditorItemDisplayRect(item);
        var join = LagrangePanelJoin.None;
        foreach (var neighbor in _overlayLayout.Where(ShouldRenderOverlayEditorItem))
        {
            if (ReferenceEquals(item, neighbor) || !IsLagrangeJoinableModule(neighbor.Key))
            {
                continue;
            }

            var neighborRect = ResolveOverlayEditorItemDisplayRect(neighbor);
            if (OverlayCompositionHudWindow.AreLagrangePanelsVerticallyJoined(neighborRect, current))
            {
                join |= LagrangePanelJoin.Top;
            }
            else if (OverlayCompositionHudWindow.AreLagrangePanelsVerticallyJoined(current, neighborRect))
            {
                join |= LagrangePanelJoin.Bottom;
            }
        }

        return join;
    }

    private static bool IsLagrangeJoinableModule(string key) =>
        key.Equals("Squads", StringComparison.OrdinalIgnoreCase) ||
        key.Equals("Members", StringComparison.OrdinalIgnoreCase) ||
        key.Equals("Chat", StringComparison.OrdinalIgnoreCase);


    private sealed class LagrangeWeaveEditorChrome : FrameworkElement
    {
        private readonly SolidColorBrush _panelBrush = new(Color.FromRgb(3, 5, 10));
        private readonly SolidColorBrush _fieldBrush = new(Color.FromRgb(240, 167, 107));
        private readonly SolidColorBrush _coreBrush = new(Color.FromRgb(255, 240, 207));
        private readonly string _moduleKey;
        private readonly LagrangePanelJoin _join;
        private readonly double _backgroundOpacity;
        private readonly bool _glowOnly;
        private readonly bool _showEventRail;

        public LagrangeWeaveEditorChrome(
            string moduleKey,
            LagrangePanelJoin join,
            double backgroundOpacity,
            bool glowOnly = false,
            bool mirror = false,
            bool showEventRail = false)
        {
            _moduleKey = moduleKey;
            _join = join;
            _backgroundOpacity = OverlayLayoutItem.NormalizeBackgroundOpacity(backgroundOpacity);
            _glowOnly = glowOnly;
            _showEventRail = showEventRail;
            IsHitTestVisible = false;
            SnapsToDevicePixels = true;
            if (mirror)
            {
                RenderTransformOrigin = new Point(0.5, 0.5);
                RenderTransform = new ScaleTransform(-1, 1);
            }
        }

        protected override void OnRender(DrawingContext drawingContext)
        {
            base.OnRender(drawingContext);
            var width = Math.Max(4, ActualWidth);
            var height = Math.Max(4, ActualHeight);
            var plan = LagrangeWeaveGeometry.BuildPanel(
                _moduleKey,
                (float)width,
                (float)height,
                _join);

            if (_glowOnly)
            {
                DrawCurves(
                    drawingContext,
                    plan.FieldCurves,
                    Color.FromRgb(240, 167, 107),
                    1.65,
                    0.58);
                var glowAnchor = ToPoint(plan.Anchor);
                drawingContext.DrawEllipse(_fieldBrush, null, glowAnchor, 6.2, 6.2);
                if (_showEventRail)
                {
                    drawingContext.DrawLine(
                        new Pen(CreateOpacityBrush(Color.FromRgb(240, 167, 107), 0.52), 1.25),
                        new Point(width - 8, 2),
                        new Point(width - 8, height - 2));
                }

                return;
            }

            var fillGeometry = BuildClosedGeometry(plan.FillOutline);
            drawingContext.PushOpacity(_backgroundOpacity);
            drawingContext.DrawGeometry(_panelBrush, null, fillGeometry);
            drawingContext.Pop();

            DrawCurves(
                drawingContext,
                plan.FieldCurves,
                Color.FromRgb(240, 167, 107),
                0.72,
                0.24);
            DrawCurves(
                drawingContext,
                plan.ShellCurves,
                Color.FromRgb(174, 186, 201),
                1.18,
                0.90);
            drawingContext.DrawLine(
                new Pen(_fieldBrush, 1.05),
                ToPoint(plan.TitleTickStart),
                ToPoint(plan.TitleTickEnd));

            var anchor = ToPoint(plan.Anchor);
            drawingContext.DrawEllipse(null, new Pen(CreateOpacityBrush(Color.FromRgb(240, 167, 107), 0.32), 0.72), anchor, 8.2, 8.2);
            drawingContext.DrawEllipse(_panelBrush, new Pen(_fieldBrush, 1.08), anchor, 5.8, 5.8);
            drawingContext.DrawEllipse(_fieldBrush, null, anchor, 2.8, 2.8);
            drawingContext.DrawEllipse(_coreBrush, null, anchor, 1.1, 1.1);
            if (_showEventRail)
            {
                var railPen = new Pen(CreateOpacityBrush(Color.FromRgb(174, 186, 201), 0.58), 0.9);
                drawingContext.DrawLine(railPen, new Point(width - 8, 2), new Point(width - 8, height - 2));
                drawingContext.DrawLine(
                    new Pen(CreateOpacityBrush(Color.FromRgb(240, 167, 107), 0.72), 0.9),
                    new Point(width - 18, 10),
                    new Point(width - 8, 10));
            }
        }

        private static void DrawCurves(
            DrawingContext drawingContext,
            IReadOnlyList<LagrangeCubicCurve> curves,
            Color color,
            double thickness,
            double opacity)
        {
            var pen = new Pen(CreateOpacityBrush(color, opacity), thickness);
            pen.Freeze();
            var geometry = new StreamGeometry();
            using (var context = geometry.Open())
            {
                foreach (var curve in curves)
                {
                    context.BeginFigure(ToPoint(curve.Start), false, false);
                    context.BezierTo(
                        ToPoint(curve.Control1),
                        ToPoint(curve.Control2),
                        ToPoint(curve.End),
                        true,
                        false);
                }
            }

            geometry.Freeze();
            drawingContext.DrawGeometry(null, pen, geometry);
        }

        private static StreamGeometry BuildClosedGeometry(IReadOnlyList<System.Numerics.Vector2> points)
        {
            var geometry = new StreamGeometry();
            using (var context = geometry.Open())
            {
                if (points.Count > 0)
                {
                    context.BeginFigure(ToPoint(points[0]), true, true);
                    for (var index = 1; index < points.Count; index++)
                    {
                        context.LineTo(ToPoint(points[index]), true, false);
                    }
                }
            }

            geometry.Freeze();
            return geometry;
        }

        private static Point ToPoint(System.Numerics.Vector2 point) =>
            new(point.X, point.Y);

        private static SolidColorBrush CreateOpacityBrush(Color color, double opacity)
        {
            var brush = new SolidColorBrush(color)
            {
                Opacity = Math.Clamp(opacity, 0, 1)
            };
            brush.Freeze();
            return brush;
        }
    }

    private Border CreateOverlayEditorSelectedModuleBadge(System.Windows.Media.Brush brush)
    {
        return new Border
        {
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(7, 7, 0, 0),
            Padding = new Thickness(7, 3, 7, 3),
            Background = new SolidColorBrush(Color.FromArgb(212, 2, 16, 26)),
            BorderBrush = brush,
            BorderThickness = new Thickness(1),
            IsHitTestVisible = false,
            Child = new TextBlock
            {
                Text = _language == "zh" ? "校准中" : "Calibrating",
                Foreground = brush,
                FontSize = 10,
                FontWeight = FontWeights.SemiBold
            }
        };
    }

    private Border CreateOverlayEditorMemberColumnHint()
    {
        return new Border
        {
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(12, 0, 0, 7),
            Padding = new Thickness(8, 3, 8, 3),
            Background = new SolidColorBrush(Color.FromArgb(214, 2, 16, 26)),
            BorderBrush = new SolidColorBrush(Color.FromRgb(41, 175, 255)),
            BorderThickness = new Thickness(1),
            IsHitTestVisible = false,
            Child = new TextBlock
            {
                Text = _language == "zh" ? "拖动分隔线：名字 / 地点" : "Drag divider: name / location",
                Foreground = new SolidColorBrush(Color.FromRgb(176, 226, 255)),
                FontSize = 10,
                FontWeight = FontWeights.SemiBold
            }
        };
    }

    private sealed record OverlayEditorPreviewPalette(
        System.Windows.Media.Brush Title,
        System.Windows.Media.Brush Text,
        System.Windows.Media.Brush Muted,
        System.Windows.Media.Brush Alert,
        System.Windows.Media.Brush Online,
        System.Windows.Media.Brush Offline);

    private sealed record OverlayEditorPreviewLine(
        string Text,
        System.Windows.Media.Brush Brush,
        double Size,
        FontWeight Weight);

    private sealed record OverlayEditorSquadPreviewRow(
        string Name,
        string Icon,
        string Detail,
        string Summary,
        System.Windows.Media.Brush StatusBrush,
        string? EmblemPath = null,
        bool IsPartyRoomIcon = false);

    private sealed record OverlayEditorMemberPreviewRow(
        string DisplayName,
        string Status,
        string Location,
        string Ship,
        System.Windows.Media.Brush StatusBrush);

    private sealed record OverlayEditorSampleMember(
        string Callsign,
        string GameName,
        string SquadName,
        bool Online,
        bool IsSelf,
        bool IsSquadCommander,
        string? ShipText = null,
        string? LocationText = null,
        string? ServerShard = null);

    private IEnumerable<UIElement> CreateOverlayEditorLivePreviewLines(OverlayLayoutItem item)
    {
        var palette = ResolveOverlayEditorPreviewPalette(GetEffectiveOverlaySettings().Theme);
        var elements = item.Key switch
        {
            "Notice" => BuildOverlayEditorNoticePreview(palette),
            "Squads" => BuildOverlayEditorSquadPreview(item, palette),
            "Members" => BuildOverlayEditorMemberPreview(item, palette),
            "Chat" => BuildOverlayEditorChatPreview(item, palette),
            _ => Enumerable.Empty<UIElement>()
        };

        foreach (var element in elements)
        {
            yield return element;
        }
    }

    private string ResolveOverlayEditorPanelTitle(OverlayLayoutItem item)
    {
        var roomScene = ResolveCurrentOverlayScene().Context.Kind == OverlaySceneKind.PartyRoom;
        return item.Key switch
        {
            "Notice" => ResolveOverlayEditorNoticeTitle(),
            "Squads" => roomScene ? "房间概况" : "小队态势",
            "Members" => roomScene ? "房间成员" : "成员状态",
            "Chat" => roomScene ? "房间通讯" : ResolveFleetOverlayChatTitle(),
            _ => item.Title
        };
    }

    private bool ShouldRenderOverlayEditorItem(OverlayLayoutItem item) =>
        IsOverlayEditorItemVisible(item) && !IsOverlayChatBarrage(item);

    private bool IsOverlayChatBarrage(OverlayLayoutItem? item)
    {
        return item?.Key.Equals("Chat", StringComparison.OrdinalIgnoreCase) == true &&
               _overlaySettings.ChatDisplayMode == OverlayChatDisplayMode.FullScreenBarrage;
    }

    private Rect ResolveOverlayEditorItemDisplayRect(OverlayLayoutItem item)
    {
        return ResolveOverlayEditorItemDisplayRect(
            item,
            OverlayEditorCanvas.Width,
            OverlayEditorCanvas.Height);
    }

    private Rect ResolveOverlayEditorItemDisplayRect(
        OverlayLayoutItem item,
        double canvasWidth,
        double canvasHeight)
    {
        var resolvedItems = OverlaySurfaceLayout.ResolveItems(
            _overlayLayout,
            canvasWidth,
            canvasHeight);
        return resolvedItems.TryGetValue(item.Key, out var rect)
            ? rect
            : OverlaySurfaceLayout.ResolveItemRect(item, canvasWidth, canvasHeight);
    }

    private string ResolveOverlayEditorNoticeTitle()
    {
        return _language.Equals("zh", StringComparison.OrdinalIgnoreCase)
            ? "通讯事件"
            : "COMMUNICATION EVENT";
    }

    private IEnumerable<UIElement> BuildOverlayEditorNoticePreview(OverlayEditorPreviewPalette palette)
    {
        var scene = ResolveCurrentOverlayScene();
        var noticeText = scene.Context.Kind == OverlaySceneKind.PartyRoom
            ? $"已接入 {scene.Context.RoomTitle ?? "当前房间"} · {scene.Context.RoomMemberCount}/{Math.Max(scene.Context.RoomCapacity, scene.Context.RoomMemberCount)} 人"
            : "已接入舰队频道，等待指挥同步";

        var grid = new Grid
        {
            Margin = new Thickness(0, 6, 0, 0),
            ClipToBounds = true
        };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(58) });
        grid.Children.Add(CreateOverlayEditorPreviewText(
            CompactOverlayEditorText(noticeText, 58),
            palette.Text,
            11.2,
            TextAlignment.Left,
            HorizontalAlignment.Stretch));
        var timer = CreateOverlayEditorPreviewText(
            $"{OverlayDisplaySettings.NormalizeCommunicationEventDuration(_overlaySettings.CommunicationEventDurationSeconds):0.#}s",
            palette.Alert,
            11,
            TextAlignment.Right,
            HorizontalAlignment.Right,
            FontWeights.SemiBold);
        Grid.SetColumn(timer, 1);
        grid.Children.Add(timer);
        yield return grid;
    }

    private IEnumerable<UIElement> BuildOverlayEditorSquadPreview(
        OverlayLayoutItem item,
        OverlayEditorPreviewPalette palette)
    {
        var scene = ResolveCurrentOverlayScene();
        if (scene.Context.Kind == OverlaySceneKind.PartyRoom)
        {
            foreach (var element in BuildOverlayEditorPartyRoomPreview(item, palette, scene.Context))
            {
                yield return element;
            }
            yield break;
        }

        var sampleMembers = ResolveOverlayEditorSampleMembers();
        var currentSquadName = ResolveOverlayEditorPreviewCurrentSquadName();
        var currentSquadMembers = sampleMembers
            .Where(member => member.SquadName.Equals(currentSquadName, StringComparison.OrdinalIgnoreCase))
            .ToArray();
        var fleetOnline = sampleMembers.Count(member => member.Online);
        var currentOnline = currentSquadMembers.Count(member => member.Online);
        var localShard = ResolveOverlayEditorLocalSampleShard();
        var sameShard = currentSquadMembers.Count(member =>
            member.Online &&
            !member.IsSelf &&
            !string.IsNullOrWhiteSpace(localShard) &&
            string.Equals(member.ServerShard, localShard, StringComparison.OrdinalIgnoreCase));
        var primaryName = "舰队总览";
        var summary = $"在线 {fleetOnline.ToString(CultureInfo.InvariantCulture)} / {sampleMembers.Length.ToString(CultureInfo.InvariantCulture)}";
        var serverSummary = "美服 · 5人";
        var focusLine = $"与你同服务器分线 {sameShard.ToString(CultureInfo.InvariantCulture)} 人";
        var statusBrush = ResolveOverlayEditorSampleFleetStatusBrush(sampleMembers, palette);
        var showSimulation = ShouldShowOverlayEditorLivePreview();
        var currentEmblemPath = showSimulation
            ? null
            : _squads.FirstOrDefault(squad =>
                squad.Name.Equals(currentSquadName, StringComparison.OrdinalIgnoreCase))?.EmblemPath;
        var currentSquadRow = new OverlayEditorSquadPreviewRow(
            currentSquadName,
            "A",
            "当前小队",
            $"在线 {currentOnline.ToString(CultureInfo.InvariantCulture)} / {currentSquadMembers.Length.ToString(CultureInfo.InvariantCulture)}",
            currentOnline > 0 ? palette.Title : palette.Muted,
            currentEmblemPath);
        var squadRows = ResolveOverlayEditorSampleSquadRows(palette, currentSquadName, currentOnline, currentSquadMembers.Length);
        if (!showSimulation)
        {
            squadRows = squadRows
                .Select(row => row with
                {
                    EmblemPath = _squads.FirstOrDefault(squad =>
                        squad.Name.Equals(row.Name, StringComparison.OrdinalIgnoreCase))?.EmblemPath
                })
                .ToArray();
        }

        var detailed = UsesDetailedSquadStatusPreview(item);
        yield return CreateOverlayEditorThreeColumnRow(
            primaryName,
            summary,
            serverSummary,
            palette.Text,
            statusBrush,
            palette.Alert,
            13,
            12,
            11,
            new Thickness(0, detailed ? 10 : 9, 0, 0));
        yield return CreateOverlayEditorPreviewText(
            CompactOverlayEditorText(focusLine, 56),
            palette.Muted,
            10,
            TextAlignment.Left,
            HorizontalAlignment.Stretch,
            FontWeights.Normal,
            new Thickness(0, 5, 0, 0));

        if (!detailed)
        {
            yield return CreateOverlayEditorSquadPreviewRow(currentSquadRow, palette);
            yield break;
        }

        var projectedHeight = ResolveOverlayEditorItemDisplayRect(item).Height;
        var rowLimit = Math.Clamp((int)Math.Floor((projectedHeight - 86) / 28), 1, 7);
        foreach (var squad in squadRows.Take(rowLimit))
        {
            yield return CreateOverlayEditorSquadPreviewRow(squad, palette);
        }
    }

    private IEnumerable<UIElement> BuildOverlayEditorChatPreview(
        OverlayLayoutItem item,
        OverlayEditorPreviewPalette palette)
    {
        var sceneKind = ResolveCurrentOverlayScene().Context.Kind;
        var projectedHeight = ResolveOverlayEditorItemDisplayRect(item).Height;
        var rowLimit = Math.Clamp((int)Math.Floor((projectedHeight - 48) / 48), 1, 8);
        var roomSamples = sceneKind == OverlaySceneKind.PartyRoom && _partyRoomChatMessages.Count > 0
            ? _partyRoomChatMessages.TakeLast(rowLimit)
                .Select(message => (
                    SenderDisplay: message.SenderDisplay,
                    Text: message.Text,
                    TimeText: message.TimeText,
                    SenderColor: message.SenderColor))
                .ToArray()
            : [];
        var fleetSamples = sceneKind == OverlaySceneKind.Fleet && _fleetOverlayChatMessages.Count > 0
            ? _fleetOverlayChatMessages.TakeLast(rowLimit)
                .Select(message => (
                    SenderDisplay: ResolveOverlayEditorFleetChatSender(message),
                    Text: message.Text,
                    TimeText: CommunicationTimeFormatter.Format(message.CreatedAt),
                    SenderColor: message.SenderColor))
                .ToArray()
            : [];
        var samples = roomSamples.Length > 0
            ? roomSamples
            : fleetSamples.Length > 0
                ? fleetSamples
                : new[]
            {
                (SenderDisplay: "NightShadow", Text: "准备完成，正在前往集合点。", TimeText: "21:14", SenderColor: "#FF3045"),
                (SenderDisplay: "Black Division", Text: "收到，进入服务器后同步分线。", TimeText: "21:15", SenderColor: "#69CCFF")
            };

        foreach (var sample in samples)
        {
            var row = new StackPanel { Margin = new Thickness(0, 7, 0, 0) };
            var header = new Grid();
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var sender = CreateOverlayEditorPreviewText(
                _overlaySettings.ChatShowSender ? CompactOverlayEditorText(sample.SenderDisplay, 24) : "通讯消息",
                palette.Title,
                11,
                TextAlignment.Left,
                HorizontalAlignment.Stretch,
                FontWeights.SemiBold);
            header.Children.Add(sender);
            if (_overlaySettings.ChatShowTimestamp)
            {
                var time = CreateOverlayEditorPreviewText(sample.TimeText, palette.Muted, 9, TextAlignment.Right, HorizontalAlignment.Right);
                Grid.SetColumn(time, 1);
                header.Children.Add(time);
            }

            row.Children.Add(header);
            row.Children.Add(new TextBlock
            {
                Text = sample.Text,
                Foreground = palette.Text,
                FontSize = 10,
                TextWrapping = TextWrapping.Wrap,
                MaxHeight = 32,
                Margin = new Thickness(0, 3, 0, 0)
            });
            yield return row;
        }
    }

    private static string ResolveOverlayEditorFleetChatSender(OverlayChatMessage message)
    {
        var sender = string.IsNullOrWhiteSpace(message.SenderCallsign)
            ? message.SenderGameId
            : message.SenderCallsign;
        return string.IsNullOrWhiteSpace(message.SourceLabel)
            ? sender
            : $"{message.SourceLabel} · {sender}";
    }

    private IEnumerable<UIElement> BuildOverlayEditorPartyRoomPreview(
        OverlayLayoutItem item,
        OverlayEditorPreviewPalette palette,
        OverlaySceneContext scene)
    {
        var capacity = Math.Max(scene.RoomCapacity, scene.RoomMemberCount);
        var roomName = string.IsNullOrWhiteSpace(scene.RoomTitle) ? "当前房间" : scene.RoomTitle!;
        var online = Math.Max(1, scene.RoomMemberCount - 1);
        yield return CreateOverlayEditorThreeColumnRow(
            CompactOverlayEditorText(roomName, 22),
            $"在线 {online}/{capacity}",
            "房主在线",
            palette.Text,
            palette.Title,
            palette.Alert,
            13,
            12,
            11,
            new Thickness(0, 9, 0, 0));
        yield return CreateOverlayEditorPreviewText(
            "与你同服务器分线 2 人",
            palette.Muted,
            10,
            TextAlignment.Left,
            HorizontalAlignment.Stretch,
            FontWeights.Normal,
            new Thickness(0, 5, 0, 0));

        yield return CreateOverlayEditorSquadPreviewRow(
            new OverlayEditorSquadPreviewRow(
                roomName,
                "",
                CompactOverlayEditorText(scene.RoomGoal ?? "房间目标：协同游戏", 52),
                $"成员 {scene.RoomMemberCount}/{capacity}",
                palette.Title,
                IsPartyRoomIcon: true),
            palette);
    }

    private IEnumerable<UIElement> BuildOverlayEditorMemberPreview(
        OverlayLayoutItem item,
        OverlayEditorPreviewPalette palette)
    {
        var projectedHeight = ResolveOverlayEditorItemDisplayRect(item).Height;
        var rowLimit = Math.Clamp((int)Math.Floor((projectedHeight - 52) / 34), 1, 8);
        foreach (var player in ResolveOverlayEditorMemberPreviewRows(palette).Take(rowLimit))
        {
            yield return CreateOverlayEditorMemberPreviewRow(player, palette);
        }
    }

    private static OverlayEditorPreviewLine OverlayPreviewLine(
        string text,
        System.Windows.Media.Brush brush,
        double size,
        FontWeight? weight = null)
    {
        return new OverlayEditorPreviewLine(text, brush, size, weight ?? FontWeights.Normal);
    }

    private static Grid CreateOverlayEditorTwoColumnRow(
        string leftText,
        string rightText,
        System.Windows.Media.Brush leftBrush,
        System.Windows.Media.Brush rightBrush,
        double leftSize,
        double rightSize,
        Thickness margin)
    {
        var grid = new Grid
        {
            Margin = margin,
            ClipToBounds = true
        };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        grid.Children.Add(CreateOverlayEditorPreviewText(
            CompactOverlayEditorText(leftText, 28),
            leftBrush,
            leftSize,
            TextAlignment.Left,
            HorizontalAlignment.Stretch,
            FontWeights.SemiBold));
        var right = CreateOverlayEditorPreviewText(
            CompactOverlayEditorText(rightText, 22),
            rightBrush,
            rightSize,
            TextAlignment.Right,
            HorizontalAlignment.Right,
            FontWeights.SemiBold,
            new Thickness(10, 0, 0, 0));
        Grid.SetColumn(right, 1);
        grid.Children.Add(right);
        return grid;
    }

    private static Grid CreateOverlayEditorThreeColumnRow(
        string leftText,
        string middleText,
        string rightText,
        System.Windows.Media.Brush leftBrush,
        System.Windows.Media.Brush middleBrush,
        System.Windows.Media.Brush rightBrush,
        double leftSize,
        double middleSize,
        double rightSize,
        Thickness margin)
    {
        var grid = new Grid
        {
            Margin = margin,
            ClipToBounds = true
        };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        grid.Children.Add(CreateOverlayEditorPreviewText(
            CompactOverlayEditorText(leftText, 24),
            leftBrush,
            leftSize,
            TextAlignment.Left,
            HorizontalAlignment.Stretch,
            FontWeights.SemiBold));

        var middle = CreateOverlayEditorPreviewText(
            CompactOverlayEditorText(middleText, 18),
            middleBrush,
            middleSize,
            TextAlignment.Right,
            HorizontalAlignment.Right,
            FontWeights.SemiBold,
            new Thickness(10, 0, 0, 0));
        Grid.SetColumn(middle, 1);
        grid.Children.Add(middle);

        var right = CreateOverlayEditorPreviewText(
            CompactOverlayEditorText(rightText, 16),
            rightBrush,
            rightSize,
            TextAlignment.Right,
            HorizontalAlignment.Right,
            FontWeights.SemiBold,
            new Thickness(10, 1, 0, 0));
        Grid.SetColumn(right, 2);
        grid.Children.Add(right);
        return grid;
    }

    private UIElement CreateOverlayEditorSquadPreviewRow(
        OverlayEditorSquadPreviewRow squad,
        OverlayEditorPreviewPalette palette)
    {
        var grid = new Grid
        {
            Margin = new Thickness(0, 8, 0, 0),
            ClipToBounds = true
        };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(22) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        if (!_overlaySettings.HideSquadIcons)
        {
            UIElement icon;
            if (squad.IsPartyRoomIcon)
            {
                icon = CreateOverlayEditorPartyRoomNodeIcon(squad.StatusBrush);
            }
            else if (!string.IsNullOrWhiteSpace(squad.EmblemPath) &&
                     ImageDecodeCache.Load(squad.EmblemPath, 32) is { } emblem)
            {
                icon = new Border
                {
                    Width = 14,
                    Height = 14,
                    VerticalAlignment = VerticalAlignment.Top,
                    Child = new ControlsImage
                    {
                        Source = emblem,
                        Stretch = Stretch.UniformToFill
                    }
                };
            }
            else
            {
                icon = new Border
                {
                    Width = 14,
                    Height = 14,
                    Background = squad.StatusBrush,
                    Opacity = 0.92,
                    VerticalAlignment = VerticalAlignment.Top,
                    Child = new TextBlock
                    {
                        Text = string.IsNullOrWhiteSpace(squad.Icon) ? "?" : squad.Icon,
                        Foreground = new SolidColorBrush(Color.FromRgb(6, 16, 26)),
                        FontSize = 8,
                        FontWeight = FontWeights.SemiBold,
                        HorizontalAlignment = HorizontalAlignment.Center,
                        VerticalAlignment = VerticalAlignment.Center,
                        TextAlignment = TextAlignment.Center
                    }
                };
            }

            grid.Children.Add(icon);
        }

        var stack = new StackPanel { ClipToBounds = true };
        stack.Children.Add(CreateOverlayEditorPreviewText(
            CompactOverlayEditorText(squad.Name, 30),
            palette.Text,
            11,
            TextAlignment.Left,
            HorizontalAlignment.Stretch,
            FontWeights.SemiBold));
        stack.Children.Add(CreateOverlayEditorPreviewText(
            CompactOverlayEditorText(squad.Detail, 62),
            palette.Muted,
            9,
            TextAlignment.Left,
            HorizontalAlignment.Stretch,
            FontWeights.Normal,
            new Thickness(0, 2, 0, 0)));
        Grid.SetColumn(stack, 1);
        grid.Children.Add(stack);

        var summary = CreateOverlayEditorPreviewText(
            CompactOverlayEditorText(squad.Summary, 16),
            squad.StatusBrush,
            10,
            TextAlignment.Right,
            HorizontalAlignment.Right,
            FontWeights.SemiBold,
            new Thickness(8, 0, 0, 0));
        Grid.SetColumn(summary, 2);
        grid.Children.Add(summary);
        return grid;
    }

    private static UIElement CreateOverlayEditorPartyRoomNodeIcon(System.Windows.Media.Brush brush)
    {
        var canvas = new Canvas
        {
            Width = 14,
            Height = 14,
            VerticalAlignment = VerticalAlignment.Top,
            SnapsToDevicePixels = true
        };
        canvas.Children.Add(new System.Windows.Shapes.Path
        {
            Data = Geometry.Parse("M7,3 L3,11 M7,3 L11,11"),
            Stroke = brush,
            StrokeThickness = 1,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
            Opacity = 0.58
        });

        AddNode(5, 1, 4, 1);
        AddNode(1.5, 9.5, 3, 0.9);
        AddNode(9.5, 9.5, 3, 0.9);
        return canvas;

        void AddNode(double left, double top, double size, double opacity)
        {
            var node = new System.Windows.Shapes.Ellipse
            {
                Width = size,
                Height = size,
                Fill = brush,
                Opacity = opacity
            };
            Canvas.SetLeft(node, left);
            Canvas.SetTop(node, top);
            canvas.Children.Add(node);
        }
    }

    private UIElement CreateOverlayEditorMemberPreviewRow(
        OverlayEditorMemberPreviewRow player,
        OverlayEditorPreviewPalette palette)
    {
        var hideStatus = _overlaySettings.EffectiveHideMemberOnlineStatus;
        var grid = new Grid
        {
            Margin = new Thickness(0, 9, 0, 0),
            ClipToBounds = true,
            Tag = OverlayMemberPreviewRowTag
        };
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        ApplyOverlayEditorMemberPreviewColumnWidths(grid);

        grid.Children.Add(CreateOverlayEditorPreviewText(
            CompactOverlayEditorText(player.DisplayName, hideStatus ? 28 : 24),
            palette.Text,
            12,
            TextAlignment.Left,
            HorizontalAlignment.Stretch));

        var splitHandle = CreateOverlayEditorMemberColumnSplitHandle(palette);
        splitHandle.Tag = grid;
        Grid.SetColumn(splitHandle, 0);
        Grid.SetRowSpan(splitHandle, 2);
        System.Windows.Controls.Panel.SetZIndex(splitHandle, 5);
        grid.Children.Add(splitHandle);

        if (!hideStatus)
        {
            var status = CreateOverlayEditorPreviewText(
                CompactOverlayEditorText(player.Status, 12),
                player.StatusBrush,
                11,
                TextAlignment.Center,
                HorizontalAlignment.Center);
            Grid.SetColumn(status, 1);
            grid.Children.Add(status);
        }

        var location = CreateOverlayEditorPreviewText(
            CompactOverlayEditorText(player.Location, hideStatus ? 34 : 24),
            palette.Muted,
            10,
            TextAlignment.Right,
            HorizontalAlignment.Stretch);
        Grid.SetColumn(location, hideStatus ? 1 : 2);
        grid.Children.Add(location);

        var ship = CreateOverlayEditorPreviewText(
            CompactOverlayEditorText(player.Ship, 62),
            palette.Muted,
            10,
            TextAlignment.Left,
            HorizontalAlignment.Stretch,
            FontWeights.Normal,
            new Thickness(0, 2, 0, 0));
        Grid.SetRow(ship, 1);
        Grid.SetColumnSpan(ship, hideStatus ? 2 : 3);
        grid.Children.Add(ship);
        return grid;
    }

    private void ApplyOverlayEditorMemberPreviewColumnWidths(Grid grid)
    {
        var hideStatus = _overlaySettings.EffectiveHideMemberOnlineStatus;
        var memberNameRatio = OverlayDisplaySettings.NormalizeMemberNameColumnRatio(_overlaySettings.MemberNameColumnRatio);
        grid.ColumnDefinitions.Clear();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(memberNameRatio, GridUnitType.Star) });
        if (!hideStatus)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(OverlayDisplaySettings.MemberStatusColumnPixelWidth) });
        }

        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1 - memberNameRatio, GridUnitType.Star) });
    }

    private Border CreateOverlayEditorMemberColumnSplitHandle(OverlayEditorPreviewPalette palette)
    {
        var isMembersSelected = !_isOverlayEventNotificationSelected &&
            _selectedOverlayInspectorItem?.Key.Equals("Members", StringComparison.OrdinalIgnoreCase) == true;
        var line = new Border
        {
            Width = isMembersSelected ? 2 : 1,
            HorizontalAlignment = HorizontalAlignment.Center,
            Background = palette.Title,
            Opacity = isMembersSelected ? 0.95 : 0.72,
            IsHitTestVisible = false
        };

        var handle = new Border
        {
            Width = isMembersSelected ? OverlayMemberColumnSplitHandleWidth + 4 : OverlayMemberColumnSplitHandleWidth,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Stretch,
            Margin = new Thickness(0, 0, -(isMembersSelected ? OverlayMemberColumnSplitHandleWidth + 4 : OverlayMemberColumnSplitHandleWidth) / 2, 0),
            Background = Brushes.Transparent,
            Cursor = _isOverlayLayoutLocked ? Cursors.Arrow : Cursors.SizeWE,
            ToolTip = _language == "zh" ? "拖动调整名字与地点列宽" : "Drag to resize name and location columns",
            Child = line
        };
        handle.MouseLeftButtonDown += OverlayMemberColumnSplit_MouseLeftButtonDown;
        return handle;
    }

    private static TextBlock CreateOverlayEditorPreviewText(
        string text,
        System.Windows.Media.Brush brush,
        double fontSize,
        TextAlignment textAlignment,
        HorizontalAlignment horizontalAlignment,
        FontWeight? fontWeight = null,
        Thickness? margin = null)
    {
        return new TextBlock
        {
            Text = text,
            Foreground = brush,
            FontSize = fontSize,
            FontWeight = fontWeight ?? FontWeights.Normal,
            Margin = margin ?? new Thickness(0),
            TextAlignment = textAlignment,
            HorizontalAlignment = horizontalAlignment,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
    }

    private bool UsesDetailedSquadStatusPreview(OverlayLayoutItem item)
    {
        var rect = ResolveOverlayEditorItemDisplayRect(item);
        return _overlaySettings.SquadStatusDisplayMode switch
        {
            OverlaySquadStatusDisplayMode.Compact => false,
            OverlaySquadStatusDisplayMode.Detailed => true,
            _ => rect.Width >= 220 && rect.Height >= 168
        };
    }

    private static System.Windows.Media.Brush ResolveOverlayEditorFleetStatusBrush(
        IReadOnlyCollection<PlayerRow> players,
        OverlayEditorPreviewPalette palette)
    {
        var online = players.Count(IsOverlayGamePresence);
        if (players.Count == 0 || online == 0)
        {
            return palette.Muted;
        }

        return online == players.Count ? palette.Online : palette.Title;
    }

    private static System.Windows.Media.Brush ResolveOverlayEditorSquadStatusBrush(
        SquadRow squad,
        OverlayEditorPreviewPalette palette)
    {
        if (squad.MemberCount == 0 || squad.OnlineCount == 0)
        {
            return palette.Muted;
        }

        return squad.OnlineCount == squad.MemberCount ? palette.Online : palette.Title;
    }

    private IEnumerable<OverlayEditorMemberPreviewRow> ResolveOverlayEditorMemberPreviewRows(OverlayEditorPreviewPalette palette)
    {
        var roomScene = ResolveCurrentOverlayScene().Context.Kind == OverlaySceneKind.PartyRoom;
        var visibleMembers = ResolveOverlayEditorSampleMembers()
            .Where(member => roomScene || MemberMatchesOverlayEditorSampleScope(member))
            .Where(member => !_overlaySettings.HideOfflineMembers || member.Online)
            .Where(member => !_overlaySettings.HideSelfMember || !member.IsSelf)
            .ToArray();

        var selfMember = visibleMembers.FirstOrDefault(member => member.IsSelf);
        var otherMembers = visibleMembers
            .Where(member => !member.IsSelf)
            .OrderByDescending(member => member.Online)
            .ThenByDescending(member => ResolveOverlayEditorSampleMemberPriorityScore(member))
            .ThenBy(member => FormatOverlayEditorSampleMemberName(member), StringComparer.OrdinalIgnoreCase);
        var sampleMembers = selfMember is null
            ? otherMembers.ToArray()
            : new[] { selfMember }.Concat(otherMembers).ToArray();

        for (var index = 0; index < sampleMembers.Length; index++)
        {
            var member = sampleMembers[index];
            var ship = string.IsNullOrWhiteSpace(member.ShipText) ? "Unknown" : member.ShipText!;
            var location = string.IsNullOrWhiteSpace(member.LocationText) ? "Unknown" : member.LocationText!;
            yield return new OverlayEditorMemberPreviewRow(
                FormatOverlayEditorSampleMemberName(member),
                member.Online ? "在线" : "离线",
                FormatOverlayEditorPreviewLocationText(location),
                FormatOverlayEditorPreviewShipText(ship),
                member.Online ? palette.Online : palette.Offline);
        }
    }

    private string FormatOverlayEditorMemberName(PlayerRow player)
    {
        var callsign = string.IsNullOrWhiteSpace(player.Callsign) ? player.Name : player.Callsign!;
        return _overlaySettings.MemberNameMode switch
        {
            OverlayMemberNameMode.CallsignOnly => callsign,
            OverlayMemberNameMode.GameNameOnly => player.Name,
            _ => callsign.Equals(player.Name, StringComparison.OrdinalIgnoreCase)
                ? player.Name
                : $"{callsign} ({player.Name})"
        };
    }

    private string FormatOverlayEditorSampleMemberName(OverlayEditorSampleMember member)
    {
        return _overlaySettings.MemberNameMode switch
        {
            OverlayMemberNameMode.CallsignOnly => member.Callsign,
            OverlayMemberNameMode.GameNameOnly => member.GameName,
            _ => member.Callsign.Equals(member.GameName, StringComparison.OrdinalIgnoreCase)
                ? member.GameName
                : $"{member.Callsign} ({member.GameName})"
        };
    }

    private OverlayEditorSampleMember[] ResolveOverlayEditorSampleMembers()
    {
        var currentSquadName = ResolveOverlayEditorSampleCurrentSquadName();
        if (ShouldShowOverlayEditorLivePreview())
        {
            return EnsureOverlayEditorSimulationSample().Members;
        }

        return CreateOverlayEditorSampleMembers(currentSquadName);
    }

    private OverlayEditorSampleMember[] CreateOverlayEditorSampleMembers(string currentSquadName)
    {
        var localShard = ResolveOverlayEditorLocalSampleShard();
        return
        [
            ResolveOverlayEditorCurrentUserSampleMember(currentSquadName, localShard),
            new("L", "Li", currentSquadName, true, false, false, ServerShard: localShard),
            new("NOVA-7", "NovaSeven", currentSquadName, true, false, true, ServerShard: "pub_sc_alpha_4_1_0_usw_999999"),
            new("北辰", "Beichen", "Bravo", true, false, false, ServerShard: "pub_sc_alpha_4_1_0_eu_222222"),
            new("Kestrel_Long_Range_Commander", "KestrelLongRangeCommander0217", currentSquadName, true, false, false, ServerShard: "pub_sc_alpha_4_1_0_usw_555555"),
            new("ARGO-12", "ArgoTwelve", "Logistics Long Range", false, false, false, ServerShard: "pub_sc_alpha_4_1_0_ap_333333"),
            new("VEGA-DEEP-SPACE-RELAY", "VegaDeepSpaceRelayOperator", "Delta Recon", false, false, true, ServerShard: "pub_sc_alpha_4_1_0_usw_444444"),
            new("MIRAI", "Mirai", "Bravo", true, false, false, ServerShard: "pub_sc_alpha_4_1_0_aus_777777"),
            new("Echo", "Echo", "Delta Recon", false, false, false, ServerShard: "pub_sc_alpha_4_1_0_usw_888888")
        ];
    }

    private OverlayEditorSampleMember ResolveOverlayEditorCurrentUserSampleMember(string currentSquadName, string localShard)
    {
        var local = GetLocalPlayerRow();
        var gameName = FirstNonEmpty(local?.Name, _localPlayer, GetPersonalDisplayName());
        var callsign = FirstNonEmpty(local?.Callsign, _callsign, gameName);

        return new OverlayEditorSampleMember(
            callsign,
            gameName,
            currentSquadName,
            true,
            true,
            false,
            ServerShard: localShard);
    }

    private string ResolveOverlayEditorLocalSampleShard()
    {
        return IsGameServerRegionCurrent()
            ? _gameServerShard
            : "pub_sc_alpha_4_1_0_usw_123456";
    }

    private string ResolveOverlayEditorSampleCurrentSquadName()
    {
        var local = GetLocalPlayerRow();
        if (!IsOverlayEditorUnassignedSquadName(local?.SquadName))
        {
            return local!.SquadName;
        }

        if (!string.IsNullOrWhiteSpace(_joinedSquad?.Name))
        {
            return _joinedSquad.Name;
        }

        return "Alpha";
    }

    private string ResolveOverlayEditorPreviewCurrentSquadName()
    {
        return ShouldShowOverlayEditorLivePreview()
            ? EnsureOverlayEditorSimulationSample().CurrentSquadName
            : ResolveOverlayEditorSampleCurrentSquadName();
    }

    private bool MemberMatchesOverlayEditorSampleScope(OverlayEditorSampleMember member)
    {
        var currentSquadName = ResolveOverlayEditorPreviewCurrentSquadName();
        return _overlaySettings.MemberScopeMode switch
        {
            OverlayMemberScopeMode.AllFleet => true,
            OverlayMemberScopeMode.CurrentSquad when member.IsSelf => true,
            OverlayMemberScopeMode.OtherSquads => !member.SquadName.Equals(currentSquadName, StringComparison.OrdinalIgnoreCase),
            _ => member.SquadName.Equals(currentSquadName, StringComparison.OrdinalIgnoreCase)
        };
    }

    private static bool IsOverlayEditorUnassignedSquadName(string? squadName)
    {
        return string.IsNullOrWhiteSpace(squadName) ||
               squadName.Equals("Unassigned", StringComparison.OrdinalIgnoreCase) ||
               squadName.Equals("未分配", StringComparison.OrdinalIgnoreCase);
    }

    private static string FirstNonEmpty(params string?[] values)
    {
        foreach (var value in values)
        {
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value.Trim();
            }
        }

        return "Unknown";
    }

    private static string FormatOverlayEditorPreviewShipText(string value)
    {
        var text = StripOverlayEditorPreviewFieldPrefix(value, "飞船：", "飞船:", "Ship:");
        return string.IsNullOrWhiteSpace(text) ? "飞船：未知" : $"飞船：{text}";
    }

    private static string FormatOverlayEditorPreviewLocationText(string value)
    {
        var text = StripOverlayEditorPreviewFieldPrefix(value, "地点：", "地点:", "位置：", "位置:", "Location:");
        return string.IsNullOrWhiteSpace(text) ? "地点：未知星域" : $"地点：{text}";
    }

    private static string StripOverlayEditorPreviewFieldPrefix(string? value, params string[] prefixes)
    {
        var text = value?.Trim() ?? "";
        foreach (var prefix in prefixes)
        {
            if (text.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                return text[prefix.Length..].Trim();
            }
        }

        return text;
    }


    private int ResolveOverlayEditorSampleMemberPriorityScore(OverlayEditorSampleMember member)
    {
        return _overlaySettings.MemberPriorityMode switch
        {
            OverlayMemberPriorityMode.Self => member.IsSelf ? 1 : 0,
            OverlayMemberPriorityMode.SquadCommander => member.IsSquadCommander ? 1 : 0,
            _ => 0
        };
    }

    private static string FormatOverlayEditorSampleFleetOnlineSummary(IReadOnlyCollection<OverlayEditorSampleMember> members)
    {
        var online = members.Count(member => member.Online);
        return $"在线 {online.ToString(CultureInfo.InvariantCulture)}";
    }

    private static System.Windows.Media.Brush ResolveOverlayEditorSampleFleetStatusBrush(
        IReadOnlyCollection<OverlayEditorSampleMember> members,
        OverlayEditorPreviewPalette palette)
    {
        var online = members.Count(member => member.Online);
        if (members.Count == 0 || online == 0)
        {
            return palette.Muted;
        }

        return online == members.Count ? palette.Online : palette.Title;
    }

    private static OverlayEditorSquadPreviewRow[] ResolveOverlayEditorSampleSquadRows(
        OverlayEditorPreviewPalette palette,
        string currentSquadName,
        int currentOnline,
        int currentTotal)
    {
        return
        [
            new(
                currentSquadName,
                "A",
                "指挥官 NOVA-7 · 在线 · 与你在同服务器",
                $"在线 {currentOnline.ToString(CultureInfo.InvariantCulture)} / {currentTotal.ToString(CultureInfo.InvariantCulture)}",
                currentOnline > 0 ? palette.Title : palette.Muted),
            new("Bravo", "B", "指挥官 MIRAI · 在线", "在线 2 / 2", palette.Online),
            new("Delta Recon", "D", "指挥官 VEGA · 离线", "在线 1 / 3", palette.Title),
            new("Logistics Long Range", "L", "指挥官 ARGO-12 · 离线", "在线 0 / 2", palette.Muted)
        ];
    }

    private string[] ResolveOverlayEditorSampleShips(int count)
    {
        var catalogShips = ShipCatalog.Entries
            .Where(entry => !entry.HasHiddenTag("hide"))
            .Select(entry => entry.DisplayName(_language))
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var fallback =
            new[]
            {
                "RSI Polaris",
                "Anvil Carrack Expedition w/C8X",
                "Crusader C2 Hercules",
                "Drake Cutlass Black",
                "Aegis Redeemer",
                "RSI Aurora MR",
                "MISC Freelancer MAX",
                "Origin 315p"
            };
        return PickOverlayEditorSampleValues(catalogShips.Length > 0 ? catalogShips : fallback, count);
    }

    private static string[] ResolveOverlayEditorSampleLocations(int count)
    {
        var locations = PublishTaskLocationSuggestions
            .Concat(
            [
                "Everus Harbor / Stanton-040",
                "ARC-L1 空间站",
                "MicroTech - Shubin Mining Facility SM0-18",
                "Stanton Gateway / Pyro Jump Point",
                "Orison 云城",
                "Grim HEX 外环",
                "New Babbage Commons",
                "Baijini Point / Area18 轨道"
            ])
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        return PickOverlayEditorSampleValues(locations, count);
    }

    private static string[] PickOverlayEditorSampleValues(IReadOnlyList<string> source, int count)
    {
        if (count <= 0)
        {
            return [];
        }

        if (source.Count == 0)
        {
            return Enumerable.Repeat("未知", count).ToArray();
        }

        var pool = source
            .OrderBy(_ => Random.Shared.Next())
            .ToArray();
        var values = new string[count];
        for (var index = 0; index < count; index++)
        {
            values[index] = pool[index % pool.Length];
        }

        return values;
    }

    private SquadRow? ResolveOverlayEditorCurrentSquad(IReadOnlyCollection<PlayerRow> players)
    {
        var self = players.FirstOrDefault(player => player.IsSelf);
        var squadName = self?.SquadName;
        if (!string.IsNullOrWhiteSpace(squadName) &&
            !IsUnassignedSquad(squadName))
        {
            var matchedSquad = _squads.FirstOrDefault(squad =>
                squad.Name.Equals(squadName, StringComparison.OrdinalIgnoreCase));
            if (matchedSquad is not null)
            {
                return matchedSquad;
            }
        }

        return _joinedSquad ?? _squads.FirstOrDefault();
    }

    private static OverlayEditorPreviewPalette ResolveOverlayEditorPreviewPalette(OverlayVisualTheme theme)
    {
        return theme switch
        {
            OverlayVisualTheme.Anvil => OverlayPalette(
                Color.FromRgb(78, 255, 171),
                Color.FromRgb(229, 255, 242),
                Color.FromRgb(120, 221, 173),
                Color.FromRgb(208, 255, 0),
                Color.FromRgb(121, 255, 92),
                Color.FromRgb(255, 92, 76)),
            OverlayVisualTheme.Drake => OverlayPalette(
                Color.FromRgb(255, 178, 48),
                Color.FromRgb(255, 236, 196),
                Color.FromRgb(230, 151, 62),
                Color.FromRgb(255, 222, 89),
                Color.FromRgb(255, 190, 52),
                Color.FromRgb(196, 72, 48)),
            OverlayVisualTheme.Argo => OverlayPalette(
                Color.FromRgb(255, 132, 73),
                Color.FromRgb(255, 235, 211),
                Color.FromRgb(255, 167, 113),
                Color.FromRgb(142, 255, 116),
                Color.FromRgb(125, 255, 126),
                Color.FromRgb(255, 78, 61)),
            OverlayVisualTheme.Musashi => OverlayPalette(
                Color.FromRgb(255, 228, 128),
                Color.FromRgb(255, 246, 214),
                Color.FromRgb(131, 242, 221),
                Color.FromRgb(91, 255, 230),
                Color.FromRgb(94, 255, 225),
                Color.FromRgb(255, 111, 95)),
            OverlayVisualTheme.Mirai => OverlayPalette(
                Color.FromRgb(134, 225, 255),
                Color.FromRgb(235, 250, 255),
                Color.FromRgb(122, 191, 220),
                Color.FromRgb(255, 92, 72),
                Color.FromRgb(105, 255, 218),
                Color.FromRgb(255, 91, 74)),
            OverlayVisualTheme.Crusader => OverlayPalette(
                Color.FromRgb(110, 205, 255),
                Color.FromRgb(240, 250, 255),
                Color.FromRgb(146, 202, 255),
                Color.FromRgb(84, 255, 107),
                Color.FromRgb(97, 255, 126),
                Color.FromRgb(255, 104, 122)),
            OverlayVisualTheme.Aegis => OverlayPalette(
                Color.FromRgb(84, 245, 232),
                Color.FromRgb(224, 255, 250),
                Color.FromRgb(112, 201, 193),
                Color.FromRgb(255, 51, 41),
                Color.FromRgb(92, 255, 185),
                Color.FromRgb(255, 63, 55)),
            OverlayVisualTheme.Rsi => OverlayPalette(
                Color.FromRgb(214, 201, 255),
                Color.FromRgb(250, 246, 255),
                Color.FromRgb(187, 166, 220),
                Color.FromRgb(255, 151, 58),
                Color.FromRgb(116, 238, 210),
                Color.FromRgb(255, 112, 86)),
            OverlayVisualTheme.Origin => OverlayPalette(
                Color.FromRgb(176, 219, 255),
                Color.FromRgb(245, 250, 255),
                Color.FromRgb(132, 185, 232),
                Color.FromRgb(255, 96, 83),
                Color.FromRgb(135, 255, 180),
                Color.FromRgb(255, 104, 94)),
            OverlayVisualTheme.Aopoa => OverlayPalette(
                Color.FromRgb(126, 255, 237),
                Color.FromRgb(230, 255, 250),
                Color.FromRgb(116, 211, 198),
                Color.FromRgb(171, 255, 67),
                Color.FromRgb(156, 255, 77),
                Color.FromRgb(255, 72, 64)),
            OverlayVisualTheme.Esperia => OverlayPalette(
                Color.FromRgb(255, 92, 112),
                Color.FromRgb(255, 228, 236),
                Color.FromRgb(211, 125, 162),
                Color.FromRgb(168, 77, 255),
                Color.FromRgb(255, 108, 128),
                Color.FromRgb(152, 74, 255)),
            OverlayVisualTheme.Gatac => OverlayPalette(
                Color.FromRgb(255, 205, 230),
                Color.FromRgb(255, 238, 246),
                Color.FromRgb(203, 147, 221),
                Color.FromRgb(255, 122, 76),
                Color.FromRgb(255, 190, 230),
                Color.FromRgb(255, 117, 76)),
            OverlayVisualTheme.NightShadow => OverlayPalette(
                Color.FromRgb(232, 237, 242),
                Color.FromRgb(232, 237, 242),
                Color.FromRgb(135, 145, 156),
                Color.FromRgb(255, 54, 74),
                Color.FromRgb(255, 54, 74),
                Color.FromRgb(118, 124, 134)),
            OverlayVisualTheme.LagrangeWeave => OverlayPalette(
                Color.FromRgb(174, 186, 201),
                Color.FromRgb(229, 235, 241),
                Color.FromRgb(135, 147, 163),
                Color.FromRgb(240, 167, 107),
                Color.FromRgb(130, 197, 162),
                Color.FromRgb(135, 147, 163)),
            OverlayVisualTheme.Verdict => OverlayPalette(
                Color.FromRgb(247, 245, 240),
                Color.FromRgb(247, 245, 240),
                Color.FromRgb(174, 181, 189),
                Color.FromRgb(255, 25, 23),
                Color.FromRgb(247, 245, 240),
                Color.FromRgb(174, 181, 189)),
            _ => OverlayPalette(
                Color.FromRgb(83, 190, 255),
                Color.FromRgb(235, 247, 255),
                Color.FromRgb(142, 187, 220),
                Color.FromRgb(255, 240, 0),
                Color.FromRgb(121, 255, 158),
                Color.FromRgb(255, 105, 105))
        };
    }

    private static OverlayEditorPreviewPalette OverlayPalette(
        Color title,
        Color text,
        Color muted,
        Color alert,
        Color online,
        Color offline)
    {
        return new OverlayEditorPreviewPalette(
            OverlayEditorBrush(title),
            OverlayEditorBrush(text),
            OverlayEditorBrush(muted),
            OverlayEditorBrush(alert),
            OverlayEditorBrush(online),
            OverlayEditorBrush(offline));
    }

    private static SolidColorBrush OverlayEditorBrush(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    private static TextBlock CreateOverlayEditorLivePreviewText(
        string text,
        System.Windows.Media.Brush brush,
        double fontSize,
        FontWeight fontWeight)
    {
        return new TextBlock
        {
            Text = text,
            Foreground = brush,
            FontSize = fontSize,
            FontWeight = fontWeight,
            Margin = new Thickness(0, 4, 0, 0),
            TextTrimming = TextTrimming.CharacterEllipsis
        };
    }

    private static string NormalizeOverlayEditorIdleValue(string? value, string fallback)
    {
        if (string.IsNullOrWhiteSpace(value) ||
            value.Equals("Standby", StringComparison.OrdinalIgnoreCase) ||
            value.Equals("Use Global", StringComparison.OrdinalIgnoreCase) ||
            value.Equals("Unassigned", StringComparison.OrdinalIgnoreCase))
        {
            return fallback;
        }

        return value;
    }

    private static string NormalizeOverlayEditorUnknownValue(string? value, string fallback)
    {
        if (string.IsNullOrWhiteSpace(value) ||
            value.Equals("Unknown", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("未知", StringComparison.OrdinalIgnoreCase))
        {
            return fallback;
        }

        return value.Trim();
    }

    private static string CompactOverlayEditorText(string text, int maxLength)
    {
        var compact = string.IsNullOrWhiteSpace(text)
            ? ""
            : text.ReplaceLineEndings(" ").Trim();
        return compact.Length <= maxLength ? compact : $"{compact[..Math.Max(1, maxLength - 1)]}…";
    }

    private static Border CreateOverlayEditorSkeletonLine(double widthFactor, System.Windows.Media.Brush accent)
    {
        var brush = accent.Clone();
        brush.Opacity = 0.22;
        return new Border
        {
            Height = 7,
            Width = 180 * Math.Clamp(widthFactor, 0.2, 1.0),
            HorizontalAlignment = HorizontalAlignment.Left,
            Background = brush,
            Margin = new Thickness(0, 0, 0, 5)
        };
    }

    private void OverlayPanel_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (sender is not FrameworkElement element || element.Tag is not OverlayLayoutItem item)
        {
            return;
        }

        var wasSelected = !_isOverlayEventNotificationSelected &&
            _selectedOverlayInspectorItem?.Key.Equals(item.Key, StringComparison.OrdinalIgnoreCase) == true;
        _activeOverlayItem = item;
        SelectOverlayInspectorItem(item);
        if (!wasSelected)
        {
            RenderOverlayEditor();
            element = FindOverlayEditorPanel(item) ?? element;
        }

        if (_isOverlayLayoutLocked || item.IsLocked || IsOverlayChatBarrage(item))
        {
            _activeOverlayItem = null;
            _activeOverlayEditorElement = null;
            _isOverlayResize = false;
            e.Handled = true;
            return;
        }

        _activeOverlayEditorElement = element;
        _isOverlayResize = false;
        _overlayEditorDragStartPoint = e.GetPosition(OverlayEditorCanvas);
        _overlayEditorDragStartRect = ResolveOverlayEditorItemDisplayRect(item);
        _overlayEditorActiveDragHistoryState = CreateOverlayEditorHistoryState();
        element.CaptureMouse();
        e.Handled = true;
    }

    private FrameworkElement? FindOverlayEditorPanel(OverlayLayoutItem item)
    {
        if (OverlayEditorCanvas is null)
        {
            return null;
        }

        return OverlayEditorCanvas.Children
            .OfType<FrameworkElement>()
            .FirstOrDefault(element =>
                element.Tag is OverlayLayoutItem candidate &&
                candidate.Key.Equals(item.Key, StringComparison.OrdinalIgnoreCase));
    }

    private void OverlayResize_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (sender is not FrameworkElement handle ||
            FindParentEditorPanel(handle) is not FrameworkElement panel ||
            panel.Tag is not OverlayLayoutItem item)
        {
            return;
        }

        _activeOverlayItem = item;
        SelectOverlayInspectorItem(item);
        if (_isOverlayLayoutLocked || item.IsLocked || IsOverlayChatBarrage(item))
        {
            _activeOverlayItem = null;
            _activeOverlayEditorElement = null;
            _isOverlayResize = false;
            e.Handled = true;
            return;
        }

        _activeOverlayEditorElement = panel;
        _isOverlayResize = true;
        _overlayEditorDragStartPoint = e.GetPosition(OverlayEditorCanvas);
        _overlayEditorDragStartRect = ResolveOverlayEditorItemDisplayRect(item);
        _overlayEditorActiveDragHistoryState = CreateOverlayEditorHistoryState();
        panel.CaptureMouse();
        e.Handled = true;
    }

    private void OverlayPanel_MouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (_isOverlayLayoutLocked ||
            _activeOverlayItem is null ||
            _activeOverlayItem.IsLocked ||
            _activeOverlayEditorElement is null ||
            e.LeftButton != MouseButtonState.Pressed)
        {
            return;
        }

        var point = e.GetPosition(OverlayEditorCanvas);
        var dx = point.X - _overlayEditorDragStartPoint.X;
        var dy = point.Y - _overlayEditorDragStartPoint.Y;
        var nextRect = _overlayEditorDragStartRect;

        if (_isOverlayResize)
        {
            nextRect = new Rect(
                _overlayEditorDragStartRect.Left,
                _overlayEditorDragStartRect.Top,
                Math.Max(1, _overlayEditorDragStartRect.Width + dx),
                Math.Max(1, _overlayEditorDragStartRect.Height + dy));
            nextRect = SnapOverlayEditorRectSize(_activeOverlayItem, nextRect);
        }
        else
        {
            nextRect = new Rect(
                _overlayEditorDragStartRect.Left + dx,
                _overlayEditorDragStartRect.Top + dy,
                _overlayEditorDragStartRect.Width,
                _overlayEditorDragStartRect.Height);
            nextRect = SnapOverlayEditorRectPosition(_activeOverlayItem, nextRect);
        }

        OverlaySurfaceLayout.ApplyRectToItem(
            _activeOverlayItem,
            nextRect,
            OverlayEditorCanvas.Width,
            OverlayEditorCanvas.Height);
        if (IsCommunicationEventModule(_activeOverlayItem))
        {
            _activeOverlayItem.VerticalAnchor = nextRect.Top <= 0.5
                ? OverlayVerticalAnchor.Top
                : OverlayVerticalAnchor.Bottom;
        }
        var rect = ResolveOverlayEditorItemDisplayRect(_activeOverlayItem);
        Canvas.SetLeft(_activeOverlayEditorElement, rect.Left);
        Canvas.SetTop(_activeOverlayEditorElement, rect.Top);
        _activeOverlayEditorElement.Width = rect.Width;
        _activeOverlayEditorElement.Height = rect.Height;
        RefreshOverlayEditorAlignmentGuides(_activeOverlayItem);
        RefreshOverlayInspector();
        e.Handled = true;
    }

    private void OverlayPanel_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        var hadActiveEdit = _activeOverlayItem is not null && _activeOverlayEditorElement is not null;
        _activeOverlayEditorElement?.ReleaseMouseCapture();
        _activeOverlayItem = null;
        _activeOverlayEditorElement = null;
        _isOverlayResize = false;
        var historyState = _overlayEditorActiveDragHistoryState;
        _overlayEditorActiveDragHistoryState = null;
        if (!hadActiveEdit)
        {
            return;
        }

        var changed = false;
        if (historyState is not null && !historyState.Equals(CreateOverlayEditorHistoryState()))
        {
            PushOverlayEditorUndoState(historyState);
            changed = true;
        }

        if (changed)
        {
            MarkOverlayEditorLayoutDirty();
        }

        SaveCurrentConfig();
        RefreshOverlayWindow();
    }

    private static FrameworkElement? FindParentEditorPanel(DependencyObject element)
    {
        var current = VisualTreeHelper.GetParent(element);
        while (current is not null)
        {
            if (current is Border { Tag: OverlayLayoutItem } border)
            {
                return border;
            }

            current = VisualTreeHelper.GetParent(current);
        }

        return null;
    }
}
