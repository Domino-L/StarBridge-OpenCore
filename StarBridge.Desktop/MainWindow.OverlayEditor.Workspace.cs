using Microsoft.Win32;
using StarBridge.Core.Events;
using StarBridge.Core.State;
using StarBridge.Desktop.Theming;
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
    private void OverlayEditorWorkspaceGrid_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        ApplyOverlayEditorResponsiveState();
    }

    private void OverlayPreviewToolbar_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        ApplyOverlayEditorToolbarOverflowState();
    }

    private void OverlayEditorCompactNavigationButton_Click(object sender, RoutedEventArgs e)
    {
        SetOverlayEditorCompactDrawer(
            _overlayEditorCompactDrawer == OverlayEditorCompactDrawer.Categories
                ? OverlayEditorCompactDrawer.None
                : OverlayEditorCompactDrawer.Categories);
    }

    private void OverlayEditorCompactSettingsButton_Click(object sender, RoutedEventArgs e)
    {
        SetOverlayEditorCompactDrawer(
            _overlayEditorCompactDrawer == OverlayEditorCompactDrawer.Settings
                ? OverlayEditorCompactDrawer.None
                : OverlayEditorCompactDrawer.Settings);
    }

    private void OverlayToolbarOverflowButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.Button { ContextMenu: { } menu } button)
        {
            menu.PlacementTarget = button;
            menu.Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom;
            menu.IsOpen = true;
        }
    }

    private void OverlayToolbarSceneMenuItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not MenuItem { Tag: string mode } || OverlaySceneModeBox is null)
        {
            return;
        }

        OverlaySceneModeBox.SelectedIndex = mode switch
        {
            "Fleet" => 1,
            "PartyRoom" => 2,
            _ => 0
        };
    }

    private void OverlayToolbarSnapMenuItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not MenuItem { Tag: string value } ||
            !double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var snapSize))
        {
            return;
        }

        _overlayEditorSnapSize = snapSize;
        ApplyOverlayEditorChromeState();
    }

    private void SetOverlayEditorCompactDrawer(OverlayEditorCompactDrawer drawer)
    {
        _overlayEditorCompactDrawer = _isOverlayEditorCompact
            ? drawer
            : OverlayEditorCompactDrawer.None;
        ApplyOverlayEditorResponsiveState();
    }

    private void ApplyOverlayEditorToolbarOverflowState()
    {
        if (OverlayPreviewToolbar is null ||
            OverlayToolbarInlineAdvancedPanel is null ||
            OverlayToolbarOverflowButton is null ||
            OverlayEditorFullScreenButton is null ||
            OverlayToolbarFullScreenMenuItem is null)
        {
            return;
        }

        var layout = OverlayEditorResponsiveLayout.Resolve(
            OverlayEditorWorkspaceGrid?.ActualWidth ?? double.NaN,
            OverlayPreviewToolbar.ActualWidth,
            _isOverlayEditorFullScreen);
        OverlayToolbarInlineAdvancedPanel.Visibility = layout.UsesToolbarOverflow
            ? Visibility.Collapsed
            : Visibility.Visible;
        OverlayToolbarOverflowButton.Visibility = layout.UsesToolbarOverflow
            ? Visibility.Visible
            : Visibility.Collapsed;
        OverlayEditorFullScreenButton.Visibility = layout.ShowsFullScreenInline
            ? Visibility.Visible
            : Visibility.Collapsed;
        OverlayToolbarFullScreenMenuItem.Visibility = layout.ShowsFullScreenInline
            ? Visibility.Collapsed
            : Visibility.Visible;
    }

    private void ApplyOverlayEditorResponsiveState()
    {
        if (OverlayEditorWorkspaceGrid is null ||
            OverlayEditorCategoryPanel is null ||
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

        var layout = OverlayEditorResponsiveLayout.Resolve(
            OverlayEditorWorkspaceGrid.ActualWidth,
            OverlayPreviewToolbar?.ActualWidth ?? double.NaN,
            _isOverlayEditorFullScreen);
        _isOverlayEditorCompact = layout.UsesCompactSidebars && !_isOverlayEditorFullScreen;

        if (_isOverlayEditorFullScreen)
        {
            OverlayEditorCategoryPanel.Visibility = Visibility.Collapsed;
            OverlayEditorSettingsPanel.Visibility = Visibility.Collapsed;
            OverlayInspectorPanel.Visibility = Visibility.Collapsed;
            OverlayEditorCategoryColumn.Width = new GridLength(0);
            OverlayEditorSettingsColumn.Width = new GridLength(0);
            OverlayEditorInspectorColumn.Width = new GridLength(0);
            OverlayEditorPreviewColumn.Width = new GridLength(1, GridUnitType.Star);
            Grid.SetColumn(OverlayPreviewPanel, 0);
            Grid.SetColumnSpan(OverlayPreviewPanel, 4);
        }
        else if (_isOverlayEditorCompact)
        {
            OverlayEditorCategoryColumn.Width = new GridLength(0);
            OverlayEditorSettingsColumn.Width = new GridLength(0);
            OverlayEditorInspectorColumn.Width = new GridLength(0);
            OverlayEditorPreviewColumn.Width = new GridLength(1, GridUnitType.Star);
            Grid.SetColumn(OverlayPreviewPanel, 0);
            Grid.SetColumnSpan(OverlayPreviewPanel, 4);

            ConfigureOverlayEditorDrawer(OverlayEditorCategoryPanel, 300);
            ConfigureOverlayEditorDrawer(OverlayEditorSettingsPanel, OverlayEditorResponsiveLayout.SettingsWidth);
            ConfigureOverlayEditorDrawer(OverlayInspectorPanel, OverlayEditorResponsiveLayout.SettingsWidth);
            OverlayEditorCategoryPanel.Visibility = _overlayEditorCompactDrawer == OverlayEditorCompactDrawer.Categories
                ? Visibility.Visible
                : Visibility.Collapsed;
            OverlayEditorSettingsPanel.Visibility = _overlayEditorCompactDrawer == OverlayEditorCompactDrawer.Settings
                ? Visibility.Visible
                : Visibility.Collapsed;
            OverlayInspectorPanel.Visibility = _isOverlayEditorInspectorOpen &&
                                               _overlayEditorCompactDrawer == OverlayEditorCompactDrawer.Inspector
                ? Visibility.Visible
                : Visibility.Collapsed;
        }
        else
        {
            _overlayEditorCompactDrawer = OverlayEditorCompactDrawer.None;
            OverlayEditorCategoryColumn.Width = new GridLength(layout.CategoryColumnWidth);
            OverlayEditorSettingsColumn.Width = new GridLength(layout.SettingsColumnWidth);
            OverlayEditorInspectorColumn.Width = new GridLength(0);
            OverlayEditorPreviewColumn.Width = new GridLength(1, GridUnitType.Star);
            RestoreOverlayEditorRail(OverlayEditorCategoryPanel, 0);
            RestoreOverlayEditorRail(OverlayEditorSettingsPanel, 1);
            RestoreOverlayEditorRail(OverlayInspectorPanel, 1);
            OverlayEditorCategoryPanel.Visibility = Visibility.Visible;
            OverlayEditorSettingsPanel.Visibility = Visibility.Visible;
            OverlayInspectorPanel.Visibility = _isOverlayEditorInspectorOpen
                ? Visibility.Visible
                : Visibility.Collapsed;
            Grid.SetColumn(OverlayPreviewPanel, 3);
            Grid.SetColumnSpan(OverlayPreviewPanel, 1);
        }

        if (OverlayEditorCompactNavigationButton is not null)
        {
            OverlayEditorCompactNavigationButton.Visibility = _isOverlayEditorCompact
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (OverlayEditorCompactSettingsButton is not null)
        {
            OverlayEditorCompactSettingsButton.Visibility = _isOverlayEditorCompact
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        ApplyOverlayEditorToolbarOverflowState();
    }

    private static void ConfigureOverlayEditorDrawer(FrameworkElement panel, double width)
    {
        Grid.SetColumn(panel, 0);
        Grid.SetColumnSpan(panel, 4);
        panel.Width = width;
        panel.HorizontalAlignment = HorizontalAlignment.Left;
        panel.Margin = new Thickness(0, 0, 10, 0);
        System.Windows.Controls.Panel.SetZIndex(panel, 40);
    }

    private static void RestoreOverlayEditorRail(FrameworkElement panel, int column)
    {
        Grid.SetColumn(panel, column);
        Grid.SetColumnSpan(panel, 1);
        panel.Width = double.NaN;
        panel.HorizontalAlignment = HorizontalAlignment.Stretch;
        panel.Margin = new Thickness(0, 0, 10, 0);
        System.Windows.Controls.Panel.SetZIndex(panel, panel.Name == "OverlayInspectorPanel" ? 20 : 0);
    }

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
        CancelOverlayEditorLiveEdit();
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
            OverlayEditorFullScreenButton.Content = _isOverlayEditorFullScreen ? "退出全屏" : "全屏编辑";
            OverlayEditorFullScreenButton.Opacity = _isOverlayEditorFullScreen ? 1.0 : 0.86;
        }

        if (OverlayToolbarFullScreenMenuItem is not null)
        {
            OverlayToolbarFullScreenMenuItem.Header = _isOverlayEditorFullScreen ? "退出全屏" : "全屏编辑";
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

        ApplyOverlaySettingsWorkspacePresentation();
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
                ? BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.StatusWarn)
                : BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.Ink3);
        }

        if (OverlayHeaderDiscardButton is not null)
        {
            OverlayHeaderDiscardButton.IsEnabled = _isOverlayEditorLayoutDirty;
            OverlayHeaderDiscardButton.Opacity = _isOverlayEditorLayoutDirty ? 1.0 : 0.52;
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
                OverlayFullScreenSaveStateText.Foreground =
                    BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.StatusWarn);
            }
            else if (_overlayEditorLastSavedAt is { } savedAt)
            {
                var savedTime = savedAt.ToLocalTime().ToString("HH:mm:ss", CultureInfo.CurrentCulture);
                OverlayFullScreenSaveStateText.Text = zh ? $"已保存 {savedTime}" : $"Saved {savedTime}";
                OverlayFullScreenSaveStateText.Foreground =
                    BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.Ink3);
            }
            else
            {
                OverlayFullScreenSaveStateText.Text = zh ? "布局已保存" : "Layout saved";
                OverlayFullScreenSaveStateText.Foreground =
                    BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.Ink3);
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

        ApplyOverlayEditorResponsiveState();

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
        _isOverlayEditorLivePreviewEnabled = _isOverlayEditorFullScreen && enabled;
    }

    private void EnterOverlayEditorFullScreen()
    {
        if (_isOverlayEditorFullScreen)
        {
            return;
        }

        _overlayEditorFullScreenSnapshot = CreateOverlayEditorFullScreenSnapshot();
        _overlayInspectorWasOpenBeforeFullScreen = OverlayInspectorPanel?.Visibility == Visibility.Visible;
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
            if (_overlayInspectorWasOpenBeforeFullScreen)
            {
                SetOverlayInspectorOpen(true);
            }

            _overlayInspectorWasOpenBeforeFullScreen = false;
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

        SetBridgeShellFullScreenEditorState(isFullScreen: true);
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

        SetBridgeShellFullScreenEditorState(isFullScreen: false);

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
        if (ReferenceEquals(_overlayEditorSnapTargetOwner, activeItem))
        {
            return horizontal
                ? _overlayEditorHorizontalSnapTargets
                : _overlayEditorVerticalSnapTargets;
        }

        return ResolveOverlayEditorModuleSnapTargets(activeItem, horizontal);
    }

    private (double Start, double Center, double End)[] ResolveOverlayEditorModuleSnapTargets(
        OverlayLayoutItem activeItem,
        bool horizontal)
    {
        var resolvedItems = OverlaySurfaceLayout.ResolveItems(
            _overlayLayout,
            OverlayEditorCanvas.Width,
            OverlayEditorCanvas.Height);
        var targets = new List<(double Start, double Center, double End)>();
        foreach (var item in _overlayLayout.Where(ShouldRenderOverlayEditorItem))
        {
            if (ReferenceEquals(item, activeItem))
            {
                continue;
            }

            if (!resolvedItems.TryGetValue(item.Key, out var rect))
            {
                rect = OverlaySurfaceLayout.ResolveItemRect(
                    item,
                    OverlayEditorCanvas.Width,
                    OverlayEditorCanvas.Height);
            }

            targets.Add(horizontal
                ? (rect.Left, rect.Left + rect.Width / 2, rect.Right)
                : (rect.Top, rect.Top + rect.Height / 2, rect.Bottom));
        }

        return targets.ToArray();
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
        var sceneAccent = BridgeSceneContext.GetRequiredAccentBrush(this);
        AddOverlayEditorGuideLine(OverlayEditorCanvas.Width / 2, true, sceneAccent, 0.28, 1);
        AddOverlayEditorGuideLine(OverlayEditorCanvas.Height / 2, false, sceneAccent, 0.22, 1);
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

        _overlayEditorAlignmentGuides.Clear();
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
        _overlayEditorAlignmentGuides.Add(line);
    }

    private void AddOverlayEditorAnchorPoint(double x, double y, System.Windows.Media.Brush brush)
    {
        const double size = 12;
        var point = new Border
        {
            Tag = OverlayEditorAlignmentGuideTag,
            Width = size,
            Height = size,
            Background = BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.Panel),
            BorderBrush = brush,
            BorderThickness = new Thickness(2),
            IsHitTestVisible = false
        };
        Canvas.SetLeft(point, x - size / 2);
        Canvas.SetTop(point, y - size / 2);
        System.Windows.Controls.Panel.SetZIndex(point, 1810);
        OverlayEditorCanvas.Children.Add(point);
        _overlayEditorAlignmentGuides.Add(point);
    }

    private void UpdateOverlayEditorAlignmentGuides(OverlayLayoutItem item, Rect rect)
    {
        if (OverlayEditorCanvas is null)
        {
            return;
        }

        if (_overlayEditorAlignmentGuides.Count != 5 ||
            _overlayEditorAlignmentGuides.Any(guide => !OverlayEditorCanvas.Children.Contains(guide)))
        {
            RefreshOverlayEditorAlignmentGuides(item);
            return;
        }

        var anchorX = GetOverlayEditorHorizontalAnchorPoint(item, rect);
        var anchorY = GetOverlayEditorVerticalAnchorPoint(item, rect);
        var anchorVerticalGuide = _overlayEditorAlignmentGuides[2];
        var anchorHorizontalGuide = _overlayEditorAlignmentGuides[3];
        var anchorPoint = _overlayEditorAlignmentGuides[4];

        anchorVerticalGuide.Background = item.Brush;
        anchorHorizontalGuide.Background = item.Brush;
        anchorPoint.BorderBrush = item.Brush;
        var anchorVerticalTranslation = GetOverlayEditorGuideTranslation(anchorVerticalGuide);
        var anchorHorizontalTranslation = GetOverlayEditorGuideTranslation(anchorHorizontalGuide);
        var anchorPointTranslation = GetOverlayEditorGuideTranslation(anchorPoint);
        anchorVerticalTranslation.X =
            Math.Round(anchorX) - anchorVerticalGuide.Width / 2 - Canvas.GetLeft(anchorVerticalGuide);
        anchorHorizontalTranslation.Y =
            Math.Round(anchorY) - anchorHorizontalGuide.Height / 2 - Canvas.GetTop(anchorHorizontalGuide);
        anchorPointTranslation.X = anchorX - anchorPoint.Width / 2 - Canvas.GetLeft(anchorPoint);
        anchorPointTranslation.Y = anchorY - anchorPoint.Height / 2 - Canvas.GetTop(anchorPoint);
    }

    private static TranslateTransform GetOverlayEditorGuideTranslation(FrameworkElement guide)
    {
        if (guide.RenderTransform is TranslateTransform translation)
        {
            return translation;
        }

        translation = new TranslateTransform();
        guide.RenderTransform = translation;
        return translation;
    }

    private static SolidColorBrush CreateOverlayEditorPanelBackground(bool isSelected, double backgroundOpacity)
    {
        var baseAlpha = isSelected ? 222 : 204;
        var alpha = (byte)Math.Clamp(
            Math.Round(baseAlpha * Math.Max(0, backgroundOpacity)),
            byte.MinValue,
            byte.MaxValue);
        return new SolidColorBrush(Color.FromArgb(alpha, 5, 18, 28));
    }

    private FrameworkElement CreateOverlayEditorPanel(OverlayLayoutItem item)
    {
        var isSelected = !_isOverlayEventNotificationSelected &&
            _selectedOverlayInspectorItem?.Key.Equals(item.Key, StringComparison.OrdinalIgnoreCase) == true;
        var selectedBrush = BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.Ink);
        var effectiveSettings = GetEffectiveOverlaySettings();
        var isLagrangeWeave = effectiveSettings.Skin == OverlaySkin.LagrangeWeave;
        var isMinimal = effectiveSettings.Skin == OverlaySkin.Minimal;
        var isVerdict = effectiveSettings.Skin == OverlaySkin.Verdict;
        const bool previewsVerdictAppearance = false;
        var usesCustomChrome = isLagrangeWeave || isMinimal || previewsVerdictAppearance;
        var isPositionLocked = _isOverlayLayoutLocked || item.IsLocked;
        var isFullScreenChatBarrage = IsOverlayChatBarrage(item);
        isPositionLocked |= isFullScreenChatBarrage;
        var border = new Border
        {
            Tag = item,
            Background = usesCustomChrome
                ? Brushes.Transparent
                : CreateOverlayEditorPanelBackground(
                    isSelected,
                    item.BackgroundOpacity * effectiveSettings.BackgroundOpacity),
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
            : isMinimal
                ? livePreviewPalette.Title
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
            FontSize = isMinimal ? 16 : 15,
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
            Foreground = BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.Ink3),
            FontSize = 11,
            Margin = new Thickness(0, 4, 0, 6),
            TextTrimming = TextTrimming.CharacterEllipsis
        };

        var content = new StackPanel
        {
            ClipToBounds = true,
            Opacity = OverlayLayoutItem.NormalizeTextOpacity(item.TextOpacity * effectiveSettings.TextOpacity)
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
            Background = BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.PanelRaised),
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
        else if (isMinimal)
        {
            wrapper.Children.Add(new MinimalEditorChrome(
                item.BackgroundOpacity * effectiveSettings.BackgroundOpacity,
                showLeftRail: true));
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


    private sealed class MinimalEditorChrome : FrameworkElement
    {
        private readonly double _backgroundOpacity;
        private readonly bool _showLeftRail;

        public MinimalEditorChrome(double backgroundOpacity, bool showLeftRail = false)
        {
            _backgroundOpacity = Math.Max(0, double.IsFinite(backgroundOpacity) ? backgroundOpacity : 0);
            _showLeftRail = showLeftRail;
            IsHitTestVisible = false;
            SnapsToDevicePixels = true;
        }

        protected override void OnRender(DrawingContext drawingContext)
        {
            base.OnRender(drawingContext);
            var width = Math.Max(4, ActualWidth);
            var height = Math.Max(4, ActualHeight);
            var rect = new Rect(0.5, 0.5, Math.Max(1, width - 1), Math.Max(1, height - 1));
            var chamfer = Math.Clamp(Math.Min(rect.Width, rect.Height) * 0.04, 3, 8);
            var fillAlpha = (byte)Math.Clamp(
                Math.Round(204 * _backgroundOpacity),
                byte.MinValue,
                byte.MaxValue);
            var fill = new SolidColorBrush(Color.FromArgb(fillAlpha, 5, 18, 28));
            fill.Freeze();
            drawingContext.DrawGeometry(fill, null, CreateChamferedGeometry(rect, chamfer));

            var borderOpacity = Math.Clamp(_backgroundOpacity, 0, 1);
            var outline = new Pen(CreateOpacityBrush(Colors.White, borderOpacity), 1);
            outline.Freeze();
            var horizontalSpan = Math.Max(1, rect.Width - chamfer * 2);
            var verticalSpan = Math.Max(1, rect.Height - chamfer * 2);
            var horizontalGap = horizontalSpan * 0.60;
            var verticalGap = verticalSpan * 0.60;
            var horizontalStart = rect.Left + rect.Width * 0.5 - horizontalGap * 0.5;
            var horizontalEnd = horizontalStart + horizontalGap;
            var verticalStart = rect.Top + rect.Height * 0.5 - verticalGap * 0.5;
            var verticalEnd = verticalStart + verticalGap;

            DrawSegment(drawingContext, outline, rect.Left, rect.Top + chamfer, rect.Left + chamfer, rect.Top);
            DrawSegment(drawingContext, outline, rect.Right - chamfer, rect.Top, rect.Right, rect.Top + chamfer);
            DrawSegment(drawingContext, outline, rect.Right, rect.Bottom - chamfer, rect.Right - chamfer, rect.Bottom);
            DrawSegment(drawingContext, outline, rect.Left + chamfer, rect.Bottom, rect.Left, rect.Bottom - chamfer);
            DrawSegment(drawingContext, outline, rect.Left + chamfer, rect.Top, horizontalStart, rect.Top);
            DrawSegment(drawingContext, outline, horizontalEnd, rect.Top, rect.Right - chamfer, rect.Top);
            DrawSegment(drawingContext, outline, rect.Left + chamfer, rect.Bottom, horizontalStart, rect.Bottom);
            DrawSegment(drawingContext, outline, horizontalEnd, rect.Bottom, rect.Right - chamfer, rect.Bottom);
            DrawSegment(drawingContext, outline, rect.Left, rect.Top + chamfer, rect.Left, verticalStart);
            DrawSegment(drawingContext, outline, rect.Left, verticalEnd, rect.Left, rect.Bottom - chamfer);
            DrawSegment(drawingContext, outline, rect.Right, rect.Top + chamfer, rect.Right, verticalStart);
            DrawSegment(drawingContext, outline, rect.Right, verticalEnd, rect.Right, rect.Bottom - chamfer);

            if (_showLeftRail)
            {
                var rail = new Pen(CreateOpacityBrush(Colors.White, borderOpacity * 0.32), 1);
                rail.Freeze();
                var railStart = rect.Top + Math.Max(chamfer + 8, rect.Height * 0.20);
                var railEnd = rect.Top + Math.Min(rect.Height - chamfer - 8, rect.Height * 0.42);
                DrawSegment(drawingContext, rail, rect.Left + 5, railStart, rect.Left + 5, railEnd);
            }
        }

        private static StreamGeometry CreateChamferedGeometry(Rect rect, double chamfer)
        {
            var geometry = new StreamGeometry();
            using (var context = geometry.Open())
            {
                context.BeginFigure(new Point(rect.Left + chamfer, rect.Top), true, true);
                context.LineTo(new Point(rect.Right - chamfer, rect.Top), true, false);
                context.LineTo(new Point(rect.Right, rect.Top + chamfer), true, false);
                context.LineTo(new Point(rect.Right, rect.Bottom - chamfer), true, false);
                context.LineTo(new Point(rect.Right - chamfer, rect.Bottom), true, false);
                context.LineTo(new Point(rect.Left + chamfer, rect.Bottom), true, false);
                context.LineTo(new Point(rect.Left, rect.Bottom - chamfer), true, false);
                context.LineTo(new Point(rect.Left, rect.Top + chamfer), true, false);
            }

            geometry.Freeze();
            return geometry;
        }

        private static void DrawSegment(
            DrawingContext drawingContext,
            Pen pen,
            double x1,
            double y1,
            double x2,
            double y2) =>
            drawingContext.DrawLine(pen, new Point(x1, y1), new Point(x2, y2));

        private static SolidColorBrush CreateOpacityBrush(Color color, double opacity)
        {
            var brush = new SolidColorBrush(color) { Opacity = Math.Clamp(opacity, 0, 1) };
            brush.Freeze();
            return brush;
        }
    }


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
            Background = BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.Panel),
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
            Background = BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.Panel),
            BorderBrush = BridgeSceneContext.GetRequiredAccentBrush(this),
            BorderThickness = new Thickness(1),
            IsHitTestVisible = false,
            Child = new TextBlock
            {
                Text = _language == "zh" ? "拖动分隔线：名字 / 地点" : "Drag divider: name / location",
                Foreground = BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.Ink2),
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

    private sealed record OverlayEditorMemberPreviewRow(
        string DisplayName,
        string Status,
        string Location,
        string Ship,
        System.Windows.Media.Brush StatusBrush);

    private IEnumerable<UIElement> CreateOverlayEditorLivePreviewLines(OverlayLayoutItem item)
    {
        var palette = ResolveOverlayEditorPreviewPalette(GetEffectiveOverlaySettings().Theme);
        var elements = item.Key switch
        {
            "Notice" => BuildOverlayEditorNoticePreview(palette),
            // The persisted key remains "Squads" so existing layouts keep their slot.
            "Squads" => BuildOverlayEditorOverviewPreview(item, palette),
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
            "Squads" => roomScene ? "房间概况" : "舰队总览",
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

    private IEnumerable<UIElement> BuildOverlayEditorOverviewPreview(
        OverlayLayoutItem item,
        OverlayEditorPreviewPalette palette)
    {
        var scene = ResolveCurrentOverlayScene();
        var authorizedRoster = ResolveOverlayAuthorizedRoster(scene);
        var projection = OverlayOverviewProjection.Project(
            authorizedRoster.Members,
            scene.Context,
            scene.HasContent,
            _localPresence,
            ResolveOverlayEditorLocalShard(),
            _language);
        var displayRect = ResolveOverlayEditorItemDisplayRect(item);
        var statusLayout = OverlaySquadStatusRowLayout.Resolve(
            (float)Math.Max(1, displayRect.Width));

        yield return CreateOverlayEditorThreeColumnRow(
            projection.Primary,
            projection.Summary,
            projection.ServerSummary,
            projection.StatusBrush,
            palette.Text,
            palette.Alert,
            13,
            12,
            11,
            new Thickness(0, 9, 0, 0),
            statusLayout);

        if (scene.Context.Kind == OverlaySceneKind.Fleet)
        {
            if (!string.IsNullOrWhiteSpace(projection.Focus))
            {
                yield return CreateOverlayEditorPreviewText(
                    CompactOverlayEditorText(projection.Focus, 56),
                    palette.Muted,
                    10,
                    TextAlignment.Left,
                    HorizontalAlignment.Stretch,
                    FontWeights.Normal,
                    new Thickness(0, 5, 0, 0));
            }

            if (projection.TopLocations.Count > 0)
            {
                var locationLayout = OverlayOverviewLocationLayout.Resolve(
                    displayRect.Width,
                    displayRect.Height,
                    projection.TopLocations);
                if (locationLayout.Orientation == OverlayOverviewLocationOrientation.Horizontal)
                {
                    yield return CreateOverlayEditorOverviewLocationRow(
                        locationLayout.VisibleItems,
                        palette.Text,
                        palette.Muted);
                }
                else
                {
                    foreach (var location in locationLayout.VisibleItems)
                    {
                        yield return CreateOverlayEditorOverviewLocationRow(
                            [location],
                            palette.Text,
                            palette.Muted);
                    }
                }
            }
            else if (!string.IsNullOrWhiteSpace(projection.LocationPlaceholder))
            {
                yield return CreateOverlayEditorOverviewLocationRow(
                    [new OverlayOverviewLocationCount(
                        "placeholder",
                        projection.LocationPlaceholder,
                        0,
                        0,
                        projection.LocationPlaceholderMetric)],
                    palette.Text,
                    palette.Muted);
            }

            yield break;
        }

        // Party goals are not typed location aggregates. Keep their existing
        // projection copy rather than treating them as fleet geography.
        if (scene.Context.Kind == OverlaySceneKind.PartyRoom)
        {
            foreach (var detail in new[] { projection.Focus, projection.Secondary }
                         .Where(value => !string.IsNullOrWhiteSpace(value)))
            {
                yield return CreateOverlayEditorPreviewText(
                    CompactOverlayEditorText(detail, 56),
                    palette.Muted,
                    10,
                    TextAlignment.Left,
                    HorizontalAlignment.Stretch,
                    FontWeights.Normal,
                    new Thickness(0, 5, 0, 0));
            }
        }
    }

    private static Grid CreateOverlayEditorOverviewLocationRow(
        IReadOnlyList<OverlayOverviewLocationCount> locations,
        System.Windows.Media.Brush nameBrush,
        System.Windows.Media.Brush metricBrush)
    {
        var grid = new Grid
        {
            Margin = new Thickness(0, 5, 0, 0),
            ClipToBounds = true
        };
        for (var index = 0; index < locations.Count; index++)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = new GridLength(1, GridUnitType.Star)
            });
            var cell = new Grid
            {
                Margin = index == 0 ? new Thickness(0) : new Thickness(10, 0, 0, 0),
                ClipToBounds = true
            };
            cell.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = new GridLength(1, GridUnitType.Star)
            });
            cell.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = GridLength.Auto
            });

            var name = CreateOverlayEditorPreviewText(
                locations[index].DisplayName,
                nameBrush,
                10,
                TextAlignment.Left,
                HorizontalAlignment.Stretch,
                FontWeights.Normal,
                new Thickness(0));
            var metric = CreateOverlayEditorPreviewText(
                locations[index].DisplayMetricText,
                metricBrush,
                10,
                TextAlignment.Right,
                HorizontalAlignment.Stretch,
                FontWeights.Normal,
                new Thickness(8, 0, 0, 0));
            Grid.SetColumn(metric, 1);
            cell.Children.Add(name);
            cell.Children.Add(metric);
            Grid.SetColumn(cell, index);
            grid.Children.Add(cell);
        }

        return grid;
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
                (SenderDisplay: "Black Division", Text: "收到，进入服务器后同步服务器信息。", TimeText: "21:15", SenderColor: "#69CCFF")
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

    private IEnumerable<UIElement> BuildOverlayEditorMemberPreview(
        OverlayLayoutItem item,
        OverlayEditorPreviewPalette palette)
    {
        var scene = ResolveCurrentOverlayScene();
        var authorizedRoster = ResolveOverlayAuthorizedRoster(scene);
        if (_overlaySettings.HideSelfMember)
        {
            authorizedRoster = new OverlayAuthorizedRoster(
                authorizedRoster.Members.Where(player => !player.IsSelf));
        }

        var projectedHeight = ResolveOverlayEditorItemDisplayRect(item).Height;
        var projection = OverlayRosterPlanner.Project(
            authorizedRoster,
            GetOverlayRosterSelectionSettings(),
            new OverlayRosterViewport(
                projectedHeight,
                ResolveOverlayEditorLocalShard()));

        foreach (var player in authorizedRoster.Resolve(projection))
        {
            yield return CreateOverlayEditorMemberPreviewRow(
                ProjectOverlayEditorMemberPreviewRow(player, palette),
                palette);
        }

        if (projection.ShowOverflowSummary)
        {
            var hiddenTotal = projection.HiddenOnlineCount + projection.HiddenOfflineCount;
            var summary = projection.HiddenOfflineCount > 0
                ? _language == "zh"
                    ? $"另有 {hiddenTotal} 人（{projection.HiddenOnlineCount} 在线 / {projection.HiddenOfflineCount} 离线）"
                    : $"{hiddenTotal} more ({projection.HiddenOnlineCount} online / {projection.HiddenOfflineCount} offline)"
                : _language == "zh"
                    ? $"另有 {projection.HiddenOnlineCount} 人在线"
                    : $"{projection.HiddenOnlineCount} more online";
            yield return CreateOverlayEditorMemberPreviewRow(
                new OverlayEditorMemberPreviewRow(summary, "", "", "", palette.Muted),
                palette);
        }
        else if (projection.VisibleSourceIndices.Count == 0)
        {
            yield return CreateOverlayEditorMemberPreviewRow(
                new OverlayEditorMemberPreviewRow(
                    _language == "zh" ? "暂无可显示成员" : "No visible members",
                    "",
                    "",
                    "",
                    palette.Muted),
                palette);
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
        Thickness margin,
        OverlaySquadStatusRowLayout layout)
    {
        var grid = new Grid
        {
            Margin = margin,
            ClipToBounds = true
        };
        grid.ColumnDefinitions.Add(new ColumnDefinition
        {
            Width = new GridLength(layout.Primary.Width, GridUnitType.Star)
        });
        grid.ColumnDefinitions.Add(new ColumnDefinition
        {
            Width = new GridLength(layout.Summary.Width, GridUnitType.Star)
        });
        grid.ColumnDefinitions.Add(new ColumnDefinition
        {
            Width = new GridLength(layout.Server.Width, GridUnitType.Star)
        });

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

    private OverlayEditorMemberPreviewRow ProjectOverlayEditorMemberPreviewRow(
        PlayerRow player,
        OverlayEditorPreviewPalette palette)
    {
        var online = StarBridge.Core.Presence.PlayerPresence.IsOnline(player.SharedPresence);
        return new OverlayEditorMemberPreviewRow(
            FormatOverlayEditorMemberName(player),
            player.SharedPresenceText,
            FormatOverlayEditorPreviewLocationText(player.SharedLocationDisplayText),
            FormatOverlayEditorPreviewShipText(player.SharedShipDisplayText),
            online ? palette.Online : palette.Offline);
    }

    private string? ResolveOverlayEditorLocalShard() =>
        IsGameServerRegionCurrent() &&
        PlayerSessionStatePresentation.HasRecognizedValue(_gameServerShard)
            ? _gameServerShard.Trim()
            : null;

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
            OverlayVisualTheme.LagrangeWeave => OverlayPalette(
                Color.FromRgb(174, 186, 201),
                Color.FromRgb(229, 235, 241),
                Color.FromRgb(135, 147, 163),
                Color.FromRgb(240, 167, 107),
                Color.FromRgb(130, 197, 162),
                Color.FromRgb(135, 147, 163)),
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
        BeginOverlayEditorLiveEdit(item, element);
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
        BeginOverlayEditorLiveEdit(item, panel);
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

        nextRect = ClampOverlayEditorRect(nextRect);
        UpdateOverlayEditorLiveEdit(_activeOverlayItem, nextRect);
        e.Handled = true;
    }

    private void OverlayPanel_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        var activeItem = _activeOverlayItem;
        var activeElement = _activeOverlayEditorElement;
        var hadActiveEdit = activeItem is not null && activeElement is not null;
        activeElement?.ReleaseMouseCapture();
        if (activeItem is not null && activeElement is not null)
        {
            CommitOverlayEditorLiveEdit(activeItem, activeElement);
        }

        _activeOverlayItem = null;
        _activeOverlayEditorElement = null;
        _isOverlayResize = false;
        FlushDeferredOverlayEditorRender();
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

        RefreshOverlayInspector();
        SaveCurrentConfig();
        RefreshOverlayWindow();
    }

    private void BeginOverlayEditorLiveEdit(OverlayLayoutItem item, FrameworkElement element)
    {
        _overlayEditorLiveEditRect = _overlayEditorDragStartRect;
        _overlayEditorSnapTargetOwner = item;
        _overlayEditorHorizontalSnapTargets = ResolveOverlayEditorModuleSnapTargets(item, true);
        _overlayEditorVerticalSnapTargets = ResolveOverlayEditorModuleSnapTargets(item, false);
        _overlayEditorPreviousRenderTransform = element.RenderTransform;
        _overlayEditorPreviousCacheMode = element.CacheMode;
        element.CacheMode = new BitmapCache
        {
            EnableClearType = true,
            RenderAtScale = 1
        };
        _overlayEditorLiveScaleTransform = new ScaleTransform(1, 1);
        _overlayEditorLiveTranslateTransform = new TranslateTransform();
        var liveTransform = new TransformGroup();
        liveTransform.Children.Add(_overlayEditorLiveScaleTransform);
        liveTransform.Children.Add(_overlayEditorLiveTranslateTransform);
        element.RenderTransform = liveTransform;
    }

    private bool IsOverlayEditorLiveEditActive()
    {
        return _overlayEditorLiveEditRect is not null &&
            _activeOverlayItem is not null &&
            _activeOverlayEditorElement is not null;
    }

    private void FlushDeferredOverlayEditorRender()
    {
        if (!_overlayEditorRenderPendingAfterLiveEdit || IsOverlayEditorLiveEditActive())
        {
            return;
        }

        _overlayEditorRenderPendingAfterLiveEdit = false;
        RenderOverlayEditor();
    }

    private void UpdateOverlayEditorLiveEdit(OverlayLayoutItem item, Rect rect)
    {
        _overlayEditorLiveEditRect = rect;
        if (_overlayEditorLiveScaleTransform is null ||
            _overlayEditorLiveTranslateTransform is null)
        {
            return;
        }

        if (_isOverlayResize)
        {
            _overlayEditorLiveScaleTransform.ScaleX = rect.Width / Math.Max(1, _overlayEditorDragStartRect.Width);
            _overlayEditorLiveScaleTransform.ScaleY = rect.Height / Math.Max(1, _overlayEditorDragStartRect.Height);
            _overlayEditorLiveTranslateTransform.X = 0;
            _overlayEditorLiveTranslateTransform.Y = 0;
        }
        else
        {
            _overlayEditorLiveScaleTransform.ScaleX = 1;
            _overlayEditorLiveScaleTransform.ScaleY = 1;
            _overlayEditorLiveTranslateTransform.X = rect.Left - _overlayEditorDragStartRect.Left;
            _overlayEditorLiveTranslateTransform.Y = rect.Top - _overlayEditorDragStartRect.Top;
        }

        UpdateOverlayEditorAlignmentGuides(item, rect);
    }

    private void CommitOverlayEditorLiveEdit(OverlayLayoutItem item, FrameworkElement element)
    {
        var finalRect = _overlayEditorLiveEditRect ?? _overlayEditorDragStartRect;
        element.RenderTransform = _overlayEditorPreviousRenderTransform ?? Transform.Identity;
        element.CacheMode = _overlayEditorPreviousCacheMode;
        OverlaySurfaceLayout.ApplyRectToItem(
            item,
            finalRect,
            OverlayEditorCanvas.Width,
            OverlayEditorCanvas.Height);
        if (IsCommunicationEventModule(item))
        {
            item.VerticalAnchor = finalRect.Top <= 0.5
                ? OverlayVerticalAnchor.Top
                : OverlayVerticalAnchor.Bottom;
        }

        var committedRect = ResolveOverlayEditorItemDisplayRect(item);
        Canvas.SetLeft(element, committedRect.Left);
        Canvas.SetTop(element, committedRect.Top);
        element.Width = committedRect.Width;
        element.Height = committedRect.Height;
        UpdateOverlayEditorAlignmentGuides(item, committedRect);
        ClearOverlayEditorLiveEditState();
    }

    private void CancelOverlayEditorLiveEdit()
    {
        if (_activeOverlayEditorElement is not null)
        {
            _activeOverlayEditorElement.RenderTransform =
                _overlayEditorPreviousRenderTransform ?? Transform.Identity;
            _activeOverlayEditorElement.CacheMode = _overlayEditorPreviousCacheMode;
        }

        ClearOverlayEditorLiveEditState();
    }

    private void ClearOverlayEditorLiveEditState()
    {
        _overlayEditorLiveEditRect = null;
        _overlayEditorPreviousRenderTransform = null;
        _overlayEditorPreviousCacheMode = null;
        _overlayEditorLiveScaleTransform = null;
        _overlayEditorLiveTranslateTransform = null;
        _overlayEditorSnapTargetOwner = null;
        _overlayEditorHorizontalSnapTargets = [];
        _overlayEditorVerticalSnapTargets = [];
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
