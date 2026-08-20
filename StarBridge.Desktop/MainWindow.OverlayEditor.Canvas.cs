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
using SaveFileDialog = Microsoft.Win32.SaveFileDialog;
using WinForms = System.Windows.Forms;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private OverlayEditorHistoryState CreateOverlayEditorHistoryState()
    {
        return new OverlayEditorHistoryState(
            SerializeOverlayLayout(),
            _overlaySettings,
            _selectedOverlayInspectorItem?.Key,
            _isOverlayEventNotificationSelected,
            _isOverlayCrosshairSelected);
    }

    private void PushOverlayEditorUndoState()
    {
        PushOverlayEditorUndoState(CreateOverlayEditorHistoryState());
    }

    private void PushOverlayEditorUndoState(OverlayEditorHistoryState state)
    {
        if (_isRestoringOverlayEditorHistory)
        {
            return;
        }

        if (_overlayEditorUndoHistory.Count > 0 && _overlayEditorUndoHistory[^1].Equals(state))
        {
            RefreshOverlayEditorHistoryButtons();
            return;
        }

        _overlayEditorUndoHistory.Add(state);
        if (_overlayEditorUndoHistory.Count > OverlayEditorHistoryLimit)
        {
            _overlayEditorUndoHistory.RemoveAt(0);
        }

        _overlayEditorRedoHistory.Clear();
        RefreshOverlayEditorHistoryButtons();
    }

    private void ClearOverlayEditorHistory()
    {
        _overlayEditorUndoHistory.Clear();
        _overlayEditorRedoHistory.Clear();
        _overlayEditorActiveDragHistoryState = null;
        RefreshOverlayEditorHistoryButtons();
    }

    private void RefreshOverlayEditorHistoryButtons()
    {
        if (OverlayEditorUndoButton is not null)
        {
            OverlayEditorUndoButton.IsEnabled = _overlayEditorUndoHistory.Count > 0;
            OverlayEditorUndoButton.Opacity = OverlayEditorUndoButton.IsEnabled ? 1.0 : 0.52;
        }

        if (OverlayFullScreenUndoButton is not null)
        {
            OverlayFullScreenUndoButton.IsEnabled = _overlayEditorUndoHistory.Count > 0;
            OverlayFullScreenUndoButton.Opacity = OverlayFullScreenUndoButton.IsEnabled ? 1.0 : 0.52;
        }

        if (OverlayEditorRedoButton is not null)
        {
            OverlayEditorRedoButton.IsEnabled = _overlayEditorRedoHistory.Count > 0;
            OverlayEditorRedoButton.Opacity = OverlayEditorRedoButton.IsEnabled ? 1.0 : 0.52;
        }

        if (OverlayFullScreenRedoButton is not null)
        {
            OverlayFullScreenRedoButton.IsEnabled = _overlayEditorRedoHistory.Count > 0;
            OverlayFullScreenRedoButton.Opacity = OverlayFullScreenRedoButton.IsEnabled ? 1.0 : 0.52;
        }
    }

    private void UndoOverlayEditor_Click(object sender, RoutedEventArgs e)
    {
        if (_overlayEditorUndoHistory.Count == 0)
        {
            return;
        }

        var current = CreateOverlayEditorHistoryState();
        var previous = _overlayEditorUndoHistory[^1];
        _overlayEditorUndoHistory.RemoveAt(_overlayEditorUndoHistory.Count - 1);
        _overlayEditorRedoHistory.Add(current);
        RestoreOverlayEditorHistoryState(previous);
    }

    private void RedoOverlayEditor_Click(object sender, RoutedEventArgs e)
    {
        if (_overlayEditorRedoHistory.Count == 0)
        {
            return;
        }

        var current = CreateOverlayEditorHistoryState();
        var next = _overlayEditorRedoHistory[^1];
        _overlayEditorRedoHistory.RemoveAt(_overlayEditorRedoHistory.Count - 1);
        _overlayEditorUndoHistory.Add(current);
        RestoreOverlayEditorHistoryState(next);
    }

    private void RestoreOverlayEditorHistoryState(OverlayEditorHistoryState state)
    {
        _isRestoringOverlayEditorHistory = true;
        try
        {
            _overlaySettings = ApplyOverlayFeatureLocks(state.Settings);
            LoadOverlayLayout(state.Layout);
            _isOverlayEventNotificationSelected = state.EventNotificationSelected &&
                _overlaySettings.ShowEventNotifications;
            _isOverlayCrosshairSelected = !_isOverlayEventNotificationSelected &&
                state.CrosshairSelected &&
                _overlaySettings.ShowCrosshair;
            _selectedOverlayInspectorItem = _isOverlayEventNotificationSelected || _isOverlayCrosshairSelected
                ? null
                : _overlayLayout.FirstOrDefault(item =>
                    !string.IsNullOrWhiteSpace(state.SelectedModuleKey) &&
                    item.Key.Equals(state.SelectedModuleKey, StringComparison.OrdinalIgnoreCase) &&
                    IsOverlayEditorItemVisible(item));

            _isLoadingSettings = true;
            ApplyOverlaySettingsToControls();
            _isLoadingSettings = false;
            RenderOverlayEditor();
            MarkOverlayEditorLayoutDirty();
            SaveCurrentConfig();
            RefreshOverlayWindow();
        }
        finally
        {
            _isRestoringOverlayEditorHistory = false;
            RefreshOverlayEditorHistoryButtons();
        }
    }

    private void RenderOverlayEditor()
    {
        if (OverlayEditorCanvas is null)
        {
            return;
        }

        if (IsOverlayEditorLiveEditActive())
        {
            _overlayEditorRenderPendingAfterLiveEdit = true;
            return;
        }

        _overlayEditorRenderPendingAfterLiveEdit = false;

        ApplyOverlayEditorCanvasScaleState();
        RefreshOverlaySceneChrome();

        if (!_overlaySettings.ShowEventNotifications)
        {
            _isOverlayEventNotificationSelected = false;
        }

        if (!_overlaySettings.ShowCrosshair)
        {
            _isOverlayCrosshairSelected = false;
        }

        OverlayEditorCanvas.Children.Clear();

        foreach (var item in _overlayLayout.Where(ShouldRenderOverlayEditorItem))
        {
            var panel = CreateOverlayEditorPanel(item);
            var rect = ResolveOverlayEditorItemDisplayRect(item);
            Canvas.SetLeft(panel, rect.Left);
            Canvas.SetTop(panel, rect.Top);
            panel.Width = rect.Width;
            panel.Height = rect.Height;
            OverlayEditorCanvas.Children.Add(panel);
        }

        AddOverlayEditorLagrangeFusionPreviews();
        AddOverlayEditorCrosshair();
        AddOverlayEditorEventNotificationPreview();
        RefreshOverlayEditorAlignmentGuides(_isOverlayEventNotificationSelected || _isOverlayCrosshairSelected ? null : _selectedOverlayInspectorItem);
        RefreshOverlayInspector();
        RefreshOverlayOverviewSummary();
    }

    private void ApplyOverlayEditorCanvasScaleState()
    {
        if (OverlayEditorCanvas is null)
        {
            return;
        }

        var (targetWidth, targetHeight) = GetOverlayEditorCanvasTargetSize();
        _isApplyingOverlayEditorCanvasScale = true;
        try
        {
            if (!AreClose(OverlayEditorCanvas.Width, targetWidth))
            {
                OverlayEditorCanvas.Width = targetWidth;
            }

            if (!AreClose(OverlayEditorCanvas.Height, targetHeight))
            {
                OverlayEditorCanvas.Height = targetHeight;
            }

            if (OverlayEditorCanvasViewbox is not null)
            {
                OverlayEditorCanvasViewbox.Stretch = _isOverlayEditorFullScreen ? Stretch.None : Stretch.Uniform;
                OverlayEditorCanvasViewbox.HorizontalAlignment = _isOverlayEditorFullScreen
                    ? HorizontalAlignment.Left
                    : HorizontalAlignment.Stretch;
                OverlayEditorCanvasViewbox.VerticalAlignment = _isOverlayEditorFullScreen
                    ? VerticalAlignment.Top
                    : VerticalAlignment.Stretch;
                OverlayEditorCanvasViewbox.Width = _isOverlayEditorFullScreen ? targetWidth : double.NaN;
                OverlayEditorCanvasViewbox.Height = _isOverlayEditorFullScreen ? targetHeight : double.NaN;
                OverlayEditorCanvasViewbox.Margin = new Thickness(0);
            }

            if (OverlayEditorGridLayer is not null)
            {
                RefreshOverlayEditorGridLayerMetrics(targetWidth, targetHeight);
            }
        }
        finally
        {
            _isApplyingOverlayEditorCanvasScale = false;
        }
    }

    private (double Width, double Height) GetOverlayEditorCanvasTargetSize()
    {
        var bounds = ResolveOverlayTargetSurfaceBounds();
        return (Math.Max(1, bounds.Width), Math.Max(1, bounds.Height));
    }

    private Rect GetOverlayEditorFullScreenCanvasBounds()
    {
        return ResolveOverlayTargetSurfaceBounds();
    }

    private Rect GetOverlayEditorFullScreenBounds()
    {
        return GetOverlayEditorFullScreenCanvasBounds();
    }

    private (int Width, int Height) GetOverlayEditorCanvasDisplaySize()
    {
        var (width, height) = GetOverlayEditorCanvasTargetSize();
        return ((int)Math.Round(width), (int)Math.Round(height));
    }

    private static bool AreClose(double left, double right)
    {
        return Math.Abs(left - right) < 0.5;
    }

    private void RefreshOverlayEditorGridLayerMetrics(double? targetWidth = null, double? targetHeight = null)
    {
        if (OverlayEditorGridLayer is null)
        {
            return;
        }

        var width = targetWidth ?? GetOverlayEditorCanvasTargetSize().Width;
        var height = targetHeight ?? GetOverlayEditorCanvasTargetSize().Height;
        var gridSize = _overlayEditorSnapSize > 0 ? _overlayEditorSnapSize : 64;

        if (_isOverlayEditorFullScreen)
        {
            OverlayEditorGridLayer.HorizontalAlignment = HorizontalAlignment.Left;
            OverlayEditorGridLayer.VerticalAlignment = VerticalAlignment.Top;
            OverlayEditorGridLayer.Width = width;
            OverlayEditorGridLayer.Height = height;
            OverlayEditorGridLayer.Margin = new Thickness(0);

            if (OverlayEditorGridLayer.Fill is DrawingBrush fullScreenGridBrush)
            {
                fullScreenGridBrush.Viewport = new Rect(0, 0, gridSize, gridSize);
            }

            return;
        }

        var hostWidth = OverlayPreviewCanvasHost?.ActualWidth ?? 0;
        var hostHeight = OverlayPreviewCanvasHost?.ActualHeight ?? 0;
        var scale = hostWidth > 1 && hostHeight > 1
            ? Math.Min(hostWidth / Math.Max(1, width), hostHeight / Math.Max(1, height))
            : 1;
        var displayWidth = Math.Max(1, width * scale);
        var displayHeight = Math.Max(1, height * scale);

        OverlayEditorGridLayer.HorizontalAlignment = HorizontalAlignment.Center;
        OverlayEditorGridLayer.VerticalAlignment = VerticalAlignment.Center;
        OverlayEditorGridLayer.Width = displayWidth;
        OverlayEditorGridLayer.Height = displayHeight;
        OverlayEditorGridLayer.Margin = new Thickness(0);

        if (OverlayEditorGridLayer.Fill is DrawingBrush gridBrush)
        {
            var scaledGridSize = Math.Max(1, gridSize * scale);
            gridBrush.Viewport = new Rect(0, 0, scaledGridSize, scaledGridSize);
        }
    }

    private void AddOverlayEditorEventNotificationPreview()
    {
        if (!_overlaySettings.ShowEventNotifications)
        {
            return;
        }

        var previewWidth = ResolveOverlayEditorEventNotificationWidth();
        const double previewHeight = 92;
        var left = ResolveOverlayEditorEventNotificationLeft(_overlaySettings.EventNotificationSide);
        var top = ResolveOverlayEditorEventNotificationTop(previewHeight);
        var accent = GetOverlayEventNotificationPreviewBrush();
        var isSelected = _isOverlayEventNotificationSelected;
        var effectiveSettings = GetEffectiveOverlaySettings();
        var skinProfile = OverlaySkinCatalog.Get(effectiveSettings.Skin);
        var isLagrangeWeave = effectiveSettings.Skin == OverlaySkin.LagrangeWeave;
        var isMinimal = effectiveSettings.Skin == OverlaySkin.Minimal;
        var isVerdict = effectiveSettings.Skin == OverlaySkin.Verdict;
        const bool previewsVerdictAppearance = false;
        var usesCustomChrome = isLagrangeWeave || isMinimal || previewsVerdictAppearance;
        var mirrorChrome = _overlaySettings.EventNotificationSide == OverlayEventNotificationSide.Left;
        var backgroundAlpha = (byte)Math.Round(
            204 * OverlayLayoutItem.NormalizeBackgroundOpacity(
                _overlaySettings.EventNotificationBackgroundOpacity * effectiveSettings.Opacity));
        var panel = new Border
        {
            Tag = "EventNotifications",
            Width = previewWidth,
            Height = previewHeight,
            Background = usesCustomChrome
                ? Brushes.Transparent
                : new SolidColorBrush(Color.FromArgb(backgroundAlpha, 5, 18, 28)),
            BorderBrush = isSelected
                ? BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.Ink)
                : usesCustomChrome
                    ? Brushes.Transparent
                    : accent,
            BorderThickness = new Thickness(isSelected ? 2 : usesCustomChrome ? 0 : 1),
            Padding = usesCustomChrome && !isMinimal ? new Thickness(0) : new Thickness(12),
            Cursor = _isOverlayLayoutLocked ? Cursors.Arrow : Cursors.SizeAll,
            IsHitTestVisible = true,
            ToolTip = _language == "zh" ? "上下拖动调整事件通知栏位置" : "Drag vertically to move the event rail"
        };
        panel.MouseLeftButtonDown += OverlayEventNotificationPreview_MouseLeftButtonDown;
        panel.MouseMove += OverlayEventNotificationPreview_MouseMove;
        panel.MouseLeftButtonUp += OverlayEventNotificationPreview_MouseLeftButtonUp;

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(4) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        if (isLagrangeWeave)
        {
            if (effectiveSettings.NightShadowBloom != OverlayNightShadowBloom.Off)
            {
                var glowChrome = new LagrangeWeaveEditorChrome(
                    "Event",
                    LagrangePanelJoin.None,
                    _overlaySettings.EventNotificationBackgroundOpacity * effectiveSettings.Opacity,
                    glowOnly: true,
                    mirror: mirrorChrome,
                    showEventRail: true)
                {
                    Effect = new System.Windows.Media.Effects.BlurEffect
                    {
                        Radius = effectiveSettings.NightShadowBloom == OverlayNightShadowBloom.Strong ? 8 : 5
                    },
                    Opacity = effectiveSettings.NightShadowBloom == OverlayNightShadowBloom.Strong ? 0.82 : 0.62
                };
                Grid.SetColumnSpan(glowChrome, 3);
                grid.Children.Add(glowChrome);
            }

            var chrome = new LagrangeWeaveEditorChrome(
                "Event",
                LagrangePanelJoin.None,
                _overlaySettings.EventNotificationBackgroundOpacity * effectiveSettings.Opacity,
                mirror: mirrorChrome,
                showEventRail: true);
            Grid.SetColumnSpan(chrome, 3);
            grid.Children.Add(chrome);
        }
        else if (isMinimal)
        {
            var chrome = new MinimalEditorChrome(
                _overlaySettings.EventNotificationBackgroundOpacity * effectiveSettings.Opacity,
                showLeftRail: true);
            Grid.SetColumnSpan(chrome, 3);
            grid.Children.Add(chrome);
        }
        else
        {
            var stripe = new Border { Background = accent, Opacity = 0.9 };
            grid.Children.Add(stripe);
        }

        var content = new StackPanel
        {
            Opacity = OverlayLayoutItem.NormalizeTextOpacity(
                _overlaySettings.EventNotificationTextOpacity * effectiveSettings.Opacity),
            Margin = isLagrangeWeave
                ? _overlaySettings.EventNotificationSide == OverlayEventNotificationSide.Right
                    ? new Thickness(18, 10, 38, 8)
                    : new Thickness(38, 10, 18, 8)
                : previewsVerdictAppearance
                    ? _overlaySettings.EventNotificationSide == OverlayEventNotificationSide.Right
                        ? new Thickness(18, 10, 36, 8)
                        : new Thickness(36, 10, 18, 8)
                    : new Thickness(0)
        };
        Grid.SetColumn(content, 2);
        content.Children.Add(new TextBlock
        {
            Text = _language == "zh" ? "事件通知栏预览" : "EVENT RAIL PREVIEW",
            Foreground = previewsVerdictAppearance ? Brushes.FloralWhite : accent,
            FontWeight = FontWeights.SemiBold,
            FontSize = skinProfile.EventTitleFontSize,
            Margin = previewsVerdictAppearance
                ? _overlaySettings.EventNotificationSide == OverlayEventNotificationSide.Right
                    ? new Thickness(52, 0, 0, 8)
                    : new Thickness(0, 0, 52, 8)
                : new Thickness(0)
        });
        content.Children.Add(new TextBlock
        {
            Text = _language == "zh" ? "成员上线 / 从吸附侧弹出" : "Member online / snaps from side",
            Foreground = Brushes.AliceBlue,
            FontSize = skinProfile.EventDetailFontSize,
            Margin = new Thickness(0, 6, 0, 0),
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        content.Children.Add(new TextBlock
        {
            Text = $"{_overlaySettings.EventNotificationDurationSeconds:0.#}s",
            Foreground = Brushes.LightSlateGray,
            FontSize = skinProfile.MutedFontSize,
            Margin = new Thickness(0, 4, 0, 0)
        });
        grid.Children.Add(content);

        if (isSelected)
        {
            var badge = CreateOverlayEditorSelectedModuleBadge(
                BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.Ink));
            badge.HorizontalAlignment = HorizontalAlignment.Right;
            badge.Margin = new Thickness(0, 7, 7, 0);
            Grid.SetColumnSpan(badge, 3);
            grid.Children.Add(badge);
        }

        panel.Child = grid;

        Canvas.SetLeft(panel, left);
        Canvas.SetTop(panel, top);
        System.Windows.Controls.Panel.SetZIndex(panel, 2000);
        OverlayEditorCanvas.Children.Add(panel);
    }

    private void AddOverlayEditorLagrangeFusionPreviews()
    {
        if (GetEffectiveOverlaySettings().Skin != OverlaySkin.LagrangeWeave ||
            OverlayEditorCanvas is null)
        {
            return;
        }

        var panels = _overlayLayout
            .Where(ShouldRenderOverlayEditorItem)
            .Where(item => IsLagrangeJoinableModule(item.Key))
            .Select(item => (Item: item, Rect: ResolveOverlayEditorItemDisplayRect(item)))
            .ToArray();
        for (var firstIndex = 0; firstIndex < panels.Length; firstIndex++)
        {
            for (var secondIndex = firstIndex + 1; secondIndex < panels.Length; secondIndex++)
            {
                var first = panels[firstIndex].Rect;
                var second = panels[secondIndex].Rect;
                Rect upper;
                Rect lower;
                if (OverlayCompositionHudWindow.AreLagrangePanelsVerticallyJoined(first, second))
                {
                    upper = first;
                    lower = second;
                }
                else if (OverlayCompositionHudWindow.AreLagrangePanelsVerticallyJoined(second, first))
                {
                    upper = second;
                    lower = first;
                }
                else
                {
                    continue;
                }

                AddOverlayEditorLagrangeFusionPreview(upper, lower);
            }
        }
    }


    private void AddOverlayEditorLagrangeFusionPreview(Rect upper, Rect lower)
    {
        var overlapLeft = Math.Max(upper.Left, lower.Left);
        var overlapRight = Math.Min(upper.Right, lower.Right);
        var saddleX = (overlapLeft + overlapRight) * 0.5;
        var saddleY = (upper.Bottom + lower.Top) * 0.5;
        var amber = new SolidColorBrush(Color.FromRgb(240, 167, 107));
        amber.Freeze();
        var shell = new SolidColorBrush(Color.FromRgb(174, 186, 201));
        shell.Freeze();

        AddOverlayEditorLagrangeFusionAdapter(upper.Left, lower.Left, saddleX, saddleY, amber);
        AddOverlayEditorLagrangeFusionAdapter(upper.Right, lower.Right, saddleX, saddleY, shell);

        var diamond = new System.Windows.Shapes.Polygon
        {
            Points =
            [
                new System.Windows.Point(saddleX, saddleY - 7),
                new System.Windows.Point(saddleX + 7, saddleY),
                new System.Windows.Point(saddleX, saddleY + 7),
                new System.Windows.Point(saddleX - 7, saddleY)
            ],
            Fill = new SolidColorBrush(Color.FromRgb(3, 5, 10)),
            Stroke = amber,
            StrokeThickness = 1.2,
            IsHitTestVisible = false
        };
        System.Windows.Controls.Panel.SetZIndex(diamond, 1901);
        OverlayEditorCanvas.Children.Add(diamond);

        var core = new System.Windows.Shapes.Ellipse
        {
            Width = 3.4,
            Height = 3.4,
            Fill = Brushes.FloralWhite,
            IsHitTestVisible = false
        };
        Canvas.SetLeft(core, saddleX - 1.7);
        Canvas.SetTop(core, saddleY - 1.7);
        System.Windows.Controls.Panel.SetZIndex(core, 1902);
        OverlayEditorCanvas.Children.Add(core);
    }

    private void AddOverlayEditorLagrangeFusionAdapter(
        double upperEdge,
        double lowerEdge,
        double saddleX,
        double saddleY,
        System.Windows.Media.Brush brush)
    {
        if (Math.Abs(upperEdge - lowerEdge) < 3)
        {
            return;
        }

        var geometry = new StreamGeometry();
        using (var context = geometry.Open())
        {
            context.BeginFigure(new System.Windows.Point(upperEdge, saddleY - 1), false, false);
            context.BezierTo(
                new System.Windows.Point((upperEdge + saddleX) * 0.5, saddleY - 6),
                new System.Windows.Point((lowerEdge + saddleX) * 0.5, saddleY + 6),
                new System.Windows.Point(lowerEdge, saddleY + 1),
                true,
                false);
        }

        geometry.Freeze();
        var path = new System.Windows.Shapes.Path
        {
            Data = geometry,
            Stroke = brush,
            StrokeThickness = 0.82,
            Opacity = 0.56,
            IsHitTestVisible = false
        };
        System.Windows.Controls.Panel.SetZIndex(path, 1900);
        OverlayEditorCanvas.Children.Add(path);
    }

    private double ResolveOverlayEditorEventNotificationTop(double previewHeight)
    {
        return OverlaySurfaceLayout.ResolveEventNotificationRect(
            OverlayEditorCanvas.Width,
            OverlayEditorCanvas.Height,
            _overlaySettings.EventNotificationSide,
            _overlaySettings.EventNotificationY,
            previewHeight,
            _overlayEditorSnapSize).Top;
    }

    private double ResolveOverlayEditorEventNotificationLeft(OverlayEventNotificationSide side)
    {
        return OverlaySurfaceLayout.ResolveEventNotificationRect(
            OverlayEditorCanvas.Width,
            OverlayEditorCanvas.Height,
            side,
            _overlaySettings.EventNotificationY,
            92,
            _overlayEditorSnapSize).Left;
    }

    private double ResolveOverlayEditorEventNotificationWidth()
    {
        return OverlaySurfaceLayout.ResolveEventNotificationWidth(OverlayEditorCanvas.Width);
    }

    private void OverlayEventNotificationPreview_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (sender is not FrameworkElement element)
        {
            e.Handled = true;
            return;
        }

        var wasSelected = _isOverlayEventNotificationSelected;
        _isOverlayEventNotificationSelected = true;
        _isOverlayCrosshairSelected = false;
        _selectedOverlayInspectorItem = null;
        ClearOverlayEditorAlignmentGuides();
        SetOverlayInspectorOpen(true);
        RefreshOverlayInspector();
        if (!wasSelected)
        {
            RenderOverlayEditor();
            element = FindOverlayEditorEventNotificationPreview() ?? element;
        }

        if (element is Border border)
        {
            border.BorderBrush = BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.Ink);
            border.BorderThickness = new Thickness(2);
        }

        if (_isOverlayLayoutLocked)
        {
            e.Handled = true;
            return;
        }

        _isOverlayEventNotificationDrag = true;
        _activeOverlayEventNotificationPreview = element;
        _overlayEventNotificationDragStartPoint = e.GetPosition(OverlayEditorCanvas);
        _overlayEventNotificationDragStartY = _overlaySettings.EventNotificationY;
        _overlayEditorActiveDragHistoryState = CreateOverlayEditorHistoryState();
        element.CaptureMouse();
        e.Handled = true;
    }

    private FrameworkElement? FindOverlayEditorEventNotificationPreview()
    {
        if (OverlayEditorCanvas is null)
        {
            return null;
        }

        return OverlayEditorCanvas.Children
            .OfType<FrameworkElement>()
            .FirstOrDefault(element =>
                element.Tag is string tag &&
                tag.Equals("EventNotifications", StringComparison.OrdinalIgnoreCase));
    }

    private void OverlayEventNotificationPreview_MouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (!_isOverlayEventNotificationDrag ||
            _activeOverlayEventNotificationPreview is null ||
            e.LeftButton != MouseButtonState.Pressed)
        {
            return;
        }

        var previewHeight = _activeOverlayEventNotificationPreview.Height > 0
            ? _activeOverlayEventNotificationPreview.Height
            : _activeOverlayEventNotificationPreview.ActualHeight;
        var minTop = OverlaySurfaceLayout.EventNotificationVerticalInset;
        var maxTop = Math.Max(minTop, OverlayEditorCanvas.Height - previewHeight - OverlaySurfaceLayout.EventNotificationVerticalInset);
        var available = Math.Max(1, maxTop - minTop);
        var point = e.GetPosition(OverlayEditorCanvas);
        var startTop = minTop + available * Math.Clamp(_overlayEventNotificationDragStartY, 0, 1);
        var top = Math.Clamp(startTop + point.Y - _overlayEventNotificationDragStartPoint.Y, minTop, maxTop);
        if (_overlayEditorSnapSize > 0)
        {
            top = Math.Round(top / _overlayEditorSnapSize, MidpointRounding.AwayFromZero) * _overlayEditorSnapSize;
            top = Math.Clamp(top, minTop, maxTop);
        }

        if (_isOverlayEditorEdgeSnapEnabled)
        {
            var threshold = OverlayEditorSmartSnapThreshold;
            var centeredTop = minTop + available / 2;
            if (Math.Abs(top - minTop) <= threshold)
            {
                top = minTop;
            }
            else if (Math.Abs(maxTop - top) <= threshold)
            {
                top = maxTop;
            }
            else if (Math.Abs(centeredTop - top) <= threshold)
            {
                top = centeredTop;
            }
        }

        var nextY = (top - minTop) / available;
        var nextSide = point.X < OverlayEditorCanvas.Width / 2
            ? OverlayEventNotificationSide.Left
            : OverlayEventNotificationSide.Right;
        _overlaySettings = _overlaySettings with
        {
            EventNotificationSide = nextSide,
            EventNotificationY = Math.Clamp(nextY, 0, 1)
        };
        Canvas.SetLeft(_activeOverlayEventNotificationPreview, ResolveOverlayEditorEventNotificationLeft(nextSide));
        Canvas.SetTop(_activeOverlayEventNotificationPreview, top);
        SyncOverlayEventNotificationSideBox();
        RefreshOverlayInspector();
        RefreshOverlayWindow();
        e.Handled = true;
    }

    private void OverlayEventNotificationPreview_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        _activeOverlayEventNotificationPreview?.ReleaseMouseCapture();
        if (!_isOverlayEventNotificationDrag)
        {
            return;
        }

        _isOverlayEventNotificationDrag = false;
        _activeOverlayEventNotificationPreview = null;
        if (_overlayEditorActiveDragHistoryState is not null &&
            !_overlayEditorActiveDragHistoryState.Equals(CreateOverlayEditorHistoryState()))
        {
            PushOverlayEditorUndoState(_overlayEditorActiveDragHistoryState);
        }
        _overlayEditorActiveDragHistoryState = null;
        SaveCurrentConfig();
        RefreshOverlayWindow();
        e.Handled = true;
    }

    private void OverlayMemberColumnSplit_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (_isOverlayLayoutLocked ||
            sender is not FrameworkElement { Tag: Grid row } ||
            OverlayEditorCanvas is null)
        {
            e.Handled = true;
            return;
        }

        _isOverlayMemberColumnSplitDrag = true;
        _activeOverlayMemberColumnSplitRow = row;
        _overlayEditorActiveDragHistoryState = CreateOverlayEditorHistoryState();
        OverlayEditorCanvas.MouseMove += OverlayMemberColumnSplitCanvas_MouseMove;
        OverlayEditorCanvas.MouseLeftButtonUp += OverlayMemberColumnSplitCanvas_MouseLeftButtonUp;
        OverlayEditorCanvas.CaptureMouse();
        UpdateOverlayMemberColumnSplitFromPoint(e.GetPosition(row), row);
        e.Handled = true;
    }

    private void OverlayMemberColumnSplitCanvas_MouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (!_isOverlayMemberColumnSplitDrag ||
            _activeOverlayMemberColumnSplitRow is null ||
            e.LeftButton != MouseButtonState.Pressed)
        {
            return;
        }

        UpdateOverlayMemberColumnSplitFromPoint(e.GetPosition(_activeOverlayMemberColumnSplitRow), _activeOverlayMemberColumnSplitRow);
        e.Handled = true;
    }

    private void OverlayMemberColumnSplitCanvas_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (_activeOverlayMemberColumnSplitRow is not null)
        {
            UpdateOverlayMemberColumnSplitFromPoint(e.GetPosition(_activeOverlayMemberColumnSplitRow), _activeOverlayMemberColumnSplitRow);
        }

        CancelOverlayMemberColumnSplitDrag();
        var changed = false;
        if (_overlayEditorActiveDragHistoryState is { } historyState &&
            !historyState.Equals(CreateOverlayEditorHistoryState()))
        {
            PushOverlayEditorUndoState(historyState);
            changed = true;
        }

        _overlayEditorActiveDragHistoryState = null;
        if (changed)
        {
            MarkOverlayEditorLayoutDirty();
        }

        SaveCurrentConfig();
        RenderOverlayEditor();
        RefreshOverlayWindow();
        e.Handled = true;
    }

    private void CancelOverlayMemberColumnSplitDrag()
    {
        if (OverlayEditorCanvas is not null)
        {
            OverlayEditorCanvas.MouseMove -= OverlayMemberColumnSplitCanvas_MouseMove;
            OverlayEditorCanvas.MouseLeftButtonUp -= OverlayMemberColumnSplitCanvas_MouseLeftButtonUp;
            if (OverlayEditorCanvas.IsMouseCaptured)
            {
                OverlayEditorCanvas.ReleaseMouseCapture();
            }
        }

        _isOverlayMemberColumnSplitDrag = false;
        _activeOverlayMemberColumnSplitRow = null;
    }

    private void UpdateOverlayMemberColumnSplitFromPoint(System.Windows.Point point, FrameworkElement row)
    {
        var rowWidth = row.ActualWidth > 1 ? row.ActualWidth : row.Width;
        if (rowWidth <= 1)
        {
            return;
        }

        var statusWidth = _overlaySettings.EffectiveHideMemberOnlineStatus ? 0 : OverlayDisplaySettings.MemberStatusColumnPixelWidth;
        var adjustableWidth = Math.Max(1, rowWidth - statusWidth);
        var nextRatio = OverlayDisplaySettings.NormalizeMemberNameColumnRatio(point.X / adjustableWidth);
        if (Math.Abs(nextRatio - _overlaySettings.MemberNameColumnRatio) < 0.002)
        {
            return;
        }

        _overlaySettings = _overlaySettings with { MemberNameColumnRatio = nextRatio };
        RefreshOverlayEditorMemberPreviewColumnWidths();
        RefreshOverlayWindow();
        RefreshOverlayInspector();
    }

    private void RefreshOverlayEditorMemberPreviewColumnWidths()
    {
        if (OverlayEditorCanvas is null)
        {
            return;
        }

        RefreshOverlayEditorMemberPreviewColumnWidths(OverlayEditorCanvas);
    }

    private void RefreshOverlayEditorMemberPreviewColumnWidths(DependencyObject parent)
    {
        var childCount = VisualTreeHelper.GetChildrenCount(parent);
        for (var index = 0; index < childCount; index++)
        {
            var child = VisualTreeHelper.GetChild(parent, index);
            if (child is Grid { Tag: string tag } grid &&
                tag.Equals(OverlayMemberPreviewRowTag, StringComparison.Ordinal))
            {
                ApplyOverlayEditorMemberPreviewColumnWidths(grid);
            }

            RefreshOverlayEditorMemberPreviewColumnWidths(child);
        }
    }

    private void SyncOverlayEventNotificationSideBox()
    {
        if (OverlayEventNotificationSideBox is null)
        {
            return;
        }

        _isLoadingSettings = true;
        OverlayEventNotificationSideBox.SelectedIndex = _overlaySettings.EventNotificationSide == OverlayEventNotificationSide.Left ? 0 : 1;
        _isLoadingSettings = false;
        RefreshOverlayEventNotificationControls();
    }

    private void AddOverlayEditorCrosshair()
    {
        if (!_overlaySettings.ShowCrosshair ||
            OverlayEditorCanvas.ActualWidth <= 0 ||
            OverlayEditorCanvas.ActualHeight <= 0)
        {
            return;
        }

        var previewSettings = GetEffectiveOverlaySettings();
        var accent = GetCrosshairPreviewBrush(previewSettings);
        var crosshair = CreateCrosshairPreview(accent, previewSettings);
        crosshair.Tag = "Crosshair";
        crosshair.Cursor = Cursors.Hand;
        crosshair.Background = Brushes.Transparent;
        crosshair.IsHitTestVisible = true;
        crosshair.MouseLeftButtonDown += OverlayEditorCrosshair_MouseLeftButtonDown;

        Canvas.SetLeft(crosshair, (OverlayEditorCanvas.ActualWidth - crosshair.Width) / 2.0);
        Canvas.SetTop(crosshair, (OverlayEditorCanvas.ActualHeight - crosshair.Height) / 2.0);
        System.Windows.Controls.Panel.SetZIndex(crosshair, 1500);
        OverlayEditorCanvas.Children.Add(crosshair);
    }

    private void OverlayEditorCrosshair_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (!_overlaySettings.ShowCrosshair)
        {
            e.Handled = true;
            return;
        }

        _isOverlayCrosshairSelected = true;
        _isOverlayEventNotificationSelected = false;
        _selectedOverlayInspectorItem = null;
        ClearOverlayEditorAlignmentGuides();
        SetOverlayInspectorOpen(true);
        RenderOverlayEditor();
        e.Handled = true;
    }

    private static Canvas CreateCrosshairPreview(System.Windows.Media.Brush brush, OverlayDisplaySettings settings)
    {
        var mode = OverlayDisplaySettings.NormalizeCrosshairMode(settings.CrosshairMode);
        var size = OverlayDisplaySettings.NormalizeCrosshairSize(settings.CrosshairSize);
        var thickness = Math.Clamp(settings.CrosshairThickness, 1, 8);
        var opacity = Math.Clamp(settings.CrosshairOpacity, 0.2, 1.0);
        var normalizedGap = OverlayDisplaySettings.NormalizeCrosshairGap(settings.CrosshairGap);
        var gap = Math.Min(size / 2.0 - 0.5, normalizedGap * size / 96.0);
        var center = size / 2.0;
        var arm = Math.Clamp((38 - normalizedGap) * size / 96.0, size * 0.12, size * 0.32);
        var outlineOpacity = OverlayDisplaySettings.NormalizeCrosshairOutlineOpacity(settings.CrosshairOutlineOpacity);
        var outline = CreateCrosshairOutlineBrush(outlineOpacity);

        var canvas = new Canvas
        {
            Width = size,
            Height = size,
            Opacity = Math.Clamp(opacity, 0.2, 1.0),
            Background = Brushes.Transparent,
            IsHitTestVisible = true
        };

        var centerMarkSize = OverlayDisplaySettings.NormalizeCrosshairCenterMarkSize(settings.CrosshairCenterMarkSize);
        if (mode == OverlayCrosshairMode.Dot)
        {
            AddCrosshairPreviewDot(canvas, center, centerMarkSize, brush, thickness, outline, outlineOpacity);
            return canvas;
        }

        if (mode == OverlayCrosshairMode.Circle)
        {
            var diameter = Math.Clamp(size * 0.62, 8, size - 4);
            if (outlineOpacity > 0)
            {
                var outlineRing = new System.Windows.Shapes.Ellipse
                {
                    Width = diameter,
                    Height = diameter,
                    Stroke = outline,
                    StrokeThickness = thickness + 2
                };
                Canvas.SetLeft(outlineRing, center - diameter / 2.0);
                Canvas.SetTop(outlineRing, center - diameter / 2.0);
                canvas.Children.Add(outlineRing);
            }

            var ring = new System.Windows.Shapes.Ellipse
            {
                Width = diameter,
                Height = diameter,
                Stroke = brush,
                StrokeThickness = thickness
            };
            Canvas.SetLeft(ring, center - diameter / 2.0);
            Canvas.SetTop(ring, center - diameter / 2.0);
            canvas.Children.Add(ring);

            if (settings.CrosshairShowCenterMark)
            {
                AddCrosshairPreviewDot(canvas, center, centerMarkSize, brush, thickness, outline, outlineOpacity);
            }

            return canvas;
        }

        if (mode != OverlayCrosshairMode.TShape)
        {
            AddCrosshairPreviewLine(canvas, center, center - gap - arm, center, center - gap, brush, thickness, outline, outlineOpacity);
        }

        AddCrosshairPreviewLine(canvas, center, center + gap, center, center + gap + arm, brush, thickness, outline, outlineOpacity);
        AddCrosshairPreviewLine(canvas, center - gap - arm, center, center - gap, center, brush, thickness, outline, outlineOpacity);
        AddCrosshairPreviewLine(canvas, center + gap, center, center + gap + arm, center, brush, thickness, outline, outlineOpacity);

        if (settings.CrosshairShowCenterMark)
        {
            AddCrosshairPreviewDot(canvas, center, centerMarkSize, brush, thickness, outline, outlineOpacity);
        }

        return canvas;
    }

    private static void AddCrosshairPreviewDot(
        Canvas canvas,
        double center,
        double dotSize,
        System.Windows.Media.Brush brush,
        double thickness,
        System.Windows.Media.Brush outline,
        double outlineOpacity)
    {
        if (outlineOpacity > 0)
        {
            var outlineDotSize = dotSize + Math.Max(2, thickness * 0.7);
            var outlineDot = new System.Windows.Shapes.Ellipse
            {
                Width = outlineDotSize,
                Height = outlineDotSize,
                Fill = outline
            };
            Canvas.SetLeft(outlineDot, center - outlineDotSize / 2.0);
            Canvas.SetTop(outlineDot, center - outlineDotSize / 2.0);
            canvas.Children.Add(outlineDot);
        }

        var dot = new System.Windows.Shapes.Ellipse
        {
            Width = dotSize,
            Height = dotSize,
            Fill = brush
        };
        Canvas.SetLeft(dot, center - dotSize / 2.0);
        Canvas.SetTop(dot, center - dotSize / 2.0);
        canvas.Children.Add(dot);
    }

    private static System.Windows.Media.Brush GetCrosshairPreviewBrush(OverlayDisplaySettings settings)
    {
        if (!settings.CrosshairUseThemeColor && TryParseHexColor(settings.CrosshairColor, out var customColor))
        {
            return new SolidColorBrush(customColor);
        }

        return GetOverlayThemeAccent(settings.Theme);
    }

    private System.Windows.Media.Brush GetOverlayEventNotificationPreviewBrush()
    {
        var settings = GetEffectiveOverlaySettings();
        var previewTheme =
            settings.Skin == OverlaySkin.NightShadow ? OverlayVisualTheme.Default : settings.Theme;
        return ResolveOverlayEditorPreviewPalette(settings with { Theme = previewTheme }).Title;
    }

    private static void AddLine(Canvas canvas, double x1, double y1, double x2, double y2, System.Windows.Media.Brush brush, double thickness)
    {
        canvas.Children.Add(new System.Windows.Shapes.Line
        {
            X1 = x1,
            Y1 = y1,
            X2 = x2,
            Y2 = y2,
            Stroke = brush,
            StrokeThickness = thickness,
            StrokeStartLineCap = PenLineCap.Square,
            StrokeEndLineCap = PenLineCap.Square
        });
    }

    private static void AddCrosshairPreviewLine(
        Canvas canvas,
        double x1,
        double y1,
        double x2,
        double y2,
        System.Windows.Media.Brush brush,
        double thickness,
        System.Windows.Media.Brush outline,
        double outlineOpacity)
    {
        if (outlineOpacity > 0)
        {
            AddLine(canvas, x1, y1, x2, y2, outline, thickness + 2.2);
        }

        AddLine(canvas, x1, y1, x2, y2, brush, thickness);
    }

    private static System.Windows.Media.Brush CreateCrosshairOutlineBrush(double opacity)
    {
        return new SolidColorBrush(Color.FromArgb(
            (byte)Math.Clamp(Math.Round(255 * opacity), 0, 255),
            2,
            7,
            12));
    }

    private static System.Windows.Media.Brush GetOverlayThemeAccent(OverlayVisualTheme theme)
    {
        return theme switch
        {
            OverlayVisualTheme.Anvil => new SolidColorBrush(Color.FromRgb(78, 255, 171)),
            OverlayVisualTheme.Drake => new SolidColorBrush(Color.FromRgb(255, 178, 48)),
            OverlayVisualTheme.Argo => new SolidColorBrush(Color.FromRgb(255, 132, 73)),
            OverlayVisualTheme.Musashi => new SolidColorBrush(Color.FromRgb(255, 228, 128)),
            OverlayVisualTheme.Mirai => new SolidColorBrush(Color.FromRgb(134, 225, 255)),
            OverlayVisualTheme.Crusader => new SolidColorBrush(Color.FromRgb(110, 205, 255)),
            OverlayVisualTheme.Aegis => new SolidColorBrush(Color.FromRgb(84, 245, 232)),
            OverlayVisualTheme.Rsi => new SolidColorBrush(Color.FromRgb(214, 201, 255)),
            OverlayVisualTheme.Origin => new SolidColorBrush(Color.FromRgb(176, 219, 255)),
            OverlayVisualTheme.Aopoa => new SolidColorBrush(Color.FromRgb(126, 255, 237)),
            OverlayVisualTheme.Esperia => new SolidColorBrush(Color.FromRgb(255, 92, 112)),
            OverlayVisualTheme.Gatac => new SolidColorBrush(Color.FromRgb(255, 205, 230)),
            OverlayVisualTheme.LagrangeWeave => new SolidColorBrush(Color.FromRgb(240, 167, 107)),
            _ => new SolidColorBrush(Color.FromRgb(83, 190, 255))
        };
    }

    private static bool TryParseHexColor(string? value, out Color color)
    {
        color = default;
        var text = value?.Trim();
        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }

        if (text.StartsWith('#'))
        {
            text = text[1..];
        }

        if (text.Length == 3)
        {
            text = string.Concat(text.Select(ch => $"{ch}{ch}"));
        }

        if (text.Length == 6 &&
            byte.TryParse(text[..2], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var red) &&
            byte.TryParse(text.Substring(2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var green) &&
            byte.TryParse(text.Substring(4, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var blue))
        {
            color = Color.FromRgb(red, green, blue);
            return true;
        }

        return false;
    }

    private sealed class DialogOwner(IntPtr handle) : WinForms.IWin32Window
    {
        public IntPtr Handle { get; } = handle;
    }

    private bool IsOverlayEditorItemVisible(OverlayLayoutItem item)
    {
        if (OverlayLayoutItem.IsRetiredModuleKey(item.Key))
        {
            return false;
        }

        return item.Key switch
        {
            "Notice" => _overlaySettings.ShowNotice,
            "Squads" => _overlaySettings.ShowSquads,
            "Members" => _overlaySettings.ShowMembers,
            "Chat" => _overlaySettings.ShowChat,
            _ => true
        };
    }

    private void SelectOverlayInspectorItem(OverlayLayoutItem item)
    {
        _isOverlayEventNotificationSelected = false;
        _isOverlayCrosshairSelected = false;
        _selectedOverlayInspectorItem = item;
        SetOverlayInspectorOpen(true);
        RefreshOverlayEditorAlignmentGuides(item);
        RefreshOverlayInspector();
    }

    private void SetOverlayInspectorOpen(bool open)
    {
        if (OverlayInspectorPanel is null)
        {
            return;
        }

        _isOverlayEditorInspectorOpen = open;
        if (open && !_isOverlayEditorFullScreen)
        {
            CaptureOverlayInspectorReturnState();
            if (_isOverlayEditorCompact)
            {
                _overlayEditorCompactDrawer = OverlayEditorCompactDrawer.Inspector;
                ApplyOverlayEditorResponsiveState();
            }
            else
            {
                OverlayInspectorPanel.Visibility = Visibility.Visible;
            }
            OverlayInspectorScrollViewer?.ScrollToTop();
            return;
        }

        OverlayInspectorPanel.Visibility = Visibility.Collapsed;
        if (!open && !_isOverlayEditorFullScreen)
        {
            RestoreOverlaySettingsAfterInspector();
            if (_isOverlayEditorCompact)
            {
                _overlayEditorCompactDrawer = OverlayEditorCompactDrawer.Settings;
                ApplyOverlayEditorResponsiveState();
            }
        }
    }

    private void CaptureOverlayInspectorReturnState()
    {
        if (_overlayInspectorReturnStateCaptured ||
            OverlaySettingsScrollViewer is null)
        {
            return;
        }

        CancelOverlaySettingsProgrammaticScroll();
        SmoothWheelScrollBehavior.CancelPendingMotion(OverlaySettingsScrollViewer);
        _overlayInspectorReturnScrollOffset = OverlaySettingsScrollViewer.VerticalOffset;
        _overlayInspectorReturnSectionKey = _overlaySettingsActiveKey;
        _overlayInspectorReturnStateCaptured = true;
    }

    private void RestoreOverlaySettingsAfterInspector()
    {
        if (!_overlayInspectorReturnStateCaptured)
        {
            return;
        }

        var returnOffset = _overlayInspectorReturnScrollOffset;
        var returnSectionKey = _overlayInspectorReturnSectionKey;
        _overlayInspectorReturnStateCaptured = false;
        _overlayInspectorReturnSectionKey = null;

        if (OverlaySettingsScrollViewer is null)
        {
            return;
        }

        CancelOverlaySettingsProgrammaticScroll();
        SmoothWheelScrollBehavior.CancelPendingMotion(OverlaySettingsScrollViewer);
        OverlaySettingsScrollViewer.ScrollToVerticalOffset(
            Math.Clamp(returnOffset, 0, OverlaySettingsScrollViewer.ScrollableHeight));
        if (!string.IsNullOrWhiteSpace(returnSectionKey))
        {
            SetActiveOverlaySettingsSection(returnSectionKey);
        }
    }

    private void CloseOverlayInspector_Click(object sender, RoutedEventArgs e)
    {
        SetOverlayInspectorOpen(false);
    }
}
