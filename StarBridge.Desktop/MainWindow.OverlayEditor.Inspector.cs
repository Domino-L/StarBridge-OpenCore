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
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
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
    private string _overlayInspectorModulePickerSignature = "";

    private void RefreshOverlayInspector()
    {
        if (OverlayInspectorTitleText is null ||
            OverlayInspectorKeyText is null ||
            OverlayInspectorXBox is null ||
            OverlayInspectorYBox is null ||
            OverlayInspectorWidthBox is null ||
            OverlayInspectorHeightBox is null ||
            OverlayInspectorHorizontalAnchorBox is null ||
            OverlayInspectorVerticalAnchorBox is null ||
            OverlayInspectorGeometryPanel is null ||
            OverlayEventInspectorPanel is null ||
            OverlayInspectorResetButton is null ||
            OverlayInspectorHideButton is null)
        {
            return;
        }

        RefreshOverlayInspectorModulePicker();

        if (_isOverlayEventNotificationSelected && _overlaySettings.ShowEventNotifications)
        {
            const double previewHeight = 92;
            var previewWidth = ResolveOverlayEditorEventNotificationWidth();
            var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
            var side = _overlaySettings.EventNotificationSide == OverlayEventNotificationSide.Left
                ? zh ? "左侧吸附" : "Left snap"
                : zh ? "右侧吸附" : "Right snap";
            OverlayInspectorTitleText.Text = zh ? "事件通知" : "Event notifications";
            OverlayInspectorKeyText.Text = zh ? "侧向事件通知" : "Side event notification";
            if (OverlayInspectorStatusText is not null)
            {
                OverlayInspectorStatusText.Text = zh
                    ? $"{side} / 永远置顶 / {_overlaySettings.EventNotificationDurationSeconds:0.#} 秒"
                    : $"{side} / Always on top / {_overlaySettings.EventNotificationDurationSeconds:0.#}s";
            }

            OverlayInspectorXBox.Text = side;
            OverlayInspectorYBox.Text = Math.Round(ResolveOverlayEditorEventNotificationTop(previewHeight)).ToString(CultureInfo.InvariantCulture);
            OverlayInspectorWidthBox.Text = $"{previewWidth:0} / 自动贴边";
            OverlayInspectorHeightBox.Text = $"{_overlaySettings.EventNotificationDurationSeconds:0.#} 秒";
            OverlayInspectorGeometryPanel.Visibility = Visibility.Collapsed;
            OverlayInspectorGeometryExpander.Visibility = Visibility.Collapsed;
            SyncOverlayModuleStyleControls(null);
            SyncOverlayInspectorModuleControls(null, true);
            SetOverlayInspectorInputsEnabled(false);
            SyncOverlayInspectorAnchorControls(null);
            OverlayInspectorResetButton.IsEnabled = false;
            OverlayInspectorHideButton.IsEnabled = true;
            if (OverlayInspectorAccentSwatch is not null)
            {
                OverlayInspectorAccentSwatch.Background = GetOverlayEventNotificationPreviewBrush();
            }

            RefreshOverlayHiddenModuleLibrary();
            RefreshOverlayFullScreenToolsInspector();
            return;
        }

        if (_isOverlayCrosshairSelected && _overlaySettings.ShowCrosshair)
        {
            var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
            var mode = FormatOverlayCrosshairMode(_overlaySettings.CrosshairMode, zh);
            OverlayInspectorTitleText.Text = zh ? "虚拟准星" : "Virtual crosshair";
            OverlayInspectorKeyText.Text = zh ? "中心准星 / 固定在屏幕中心" : "Center reticle / Fixed to screen center";
            if (OverlayInspectorStatusText is not null)
            {
                OverlayInspectorStatusText.Text = zh
                    ? $"{mode} / {OverlayDisplaySettings.NormalizeCrosshairSize(_overlaySettings.CrosshairSize):0}px / 点击参数即可微调"
                    : $"{mode} / {OverlayDisplaySettings.NormalizeCrosshairSize(_overlaySettings.CrosshairSize):0}px / Tune values below";
            }

            OverlayInspectorXBox.Text = "";
            OverlayInspectorYBox.Text = "";
            OverlayInspectorWidthBox.Text = "";
            OverlayInspectorHeightBox.Text = "";
            OverlayInspectorGeometryPanel.Visibility = Visibility.Collapsed;
            OverlayInspectorGeometryExpander.Visibility = Visibility.Collapsed;
            SyncOverlayModuleStyleControls(null);
            SetOverlayInspectorModulePanelVisibility("Crosshair");
            SyncOverlayInspectorCrosshairControls();
            SetOverlayInspectorInputsEnabled(false);
            SyncOverlayInspectorAnchorControls(null);
            OverlayInspectorResetButton.IsEnabled = true;
            OverlayInspectorHideButton.IsEnabled = true;
            if (OverlayInspectorAccentSwatch is not null)
            {
                OverlayInspectorAccentSwatch.Background = GetCrosshairPreviewBrush(GetEffectiveOverlaySettings());
            }

            RefreshOverlayHiddenModuleLibrary();
            RefreshOverlayFullScreenToolsInspector();
            return;
        }

        var item = _selectedOverlayInspectorItem;
        if (item is null ||
            !_overlayLayout.Contains(item) ||
            !IsOverlayEditorItemVisible(item))
        {
            SetOverlayInspectorOpen(false);
            _isOverlayEventNotificationSelected = false;
            _isOverlayCrosshairSelected = false;
            var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
            OverlayInspectorTitleText.Text = zh ? "未选中模块" : "No module selected";
            OverlayInspectorKeyText.Text = zh ? "从模块列表选择" : "Choose from the module list";
            if (OverlayInspectorStatusText is not null)
            {
                OverlayInspectorStatusText.Text = zh
                    ? "等待 / 可从模块库恢复隐藏模块"
                    : "Waiting / Restore hidden modules from the library";
            }

            OverlayInspectorXBox.Text = "";
            OverlayInspectorYBox.Text = "";
            OverlayInspectorWidthBox.Text = "";
            OverlayInspectorHeightBox.Text = "";
            OverlayInspectorGeometryPanel.Visibility = Visibility.Visible;
            OverlayInspectorGeometryExpander.Visibility = Visibility.Collapsed;
            SyncOverlayModuleStyleControls(null);
            SyncOverlayInspectorModuleControls(null, false);
            SetOverlayInspectorInputsEnabled(false);
            SyncOverlayInspectorAnchorControls(null);
            OverlayInspectorResetButton.IsEnabled = false;
            OverlayInspectorHideButton.IsEnabled = false;
            if (OverlayInspectorAccentSwatch is not null)
            {
                OverlayInspectorAccentSwatch.Background = GetOverlayThemeAccent(GetEffectiveOverlaySettings().Theme);
            }

            RefreshOverlayHiddenModuleLibrary();
            RefreshOverlayFullScreenToolsInspector();
            return;
        }

        var canvasWidth = OverlayEditorCanvas.Width;
        var canvasHeight = OverlayEditorCanvas.Height;
        OverlayInspectorTitleText.Text = ResolveOverlayEditorPanelTitle(item);
        OverlayInspectorKeyText.Text = GetOverlayInspectorSubtitle(item);
        var rect = ResolveOverlayEditorItemDisplayRect(item);
        if (OverlayInspectorStatusText is not null)
        {
            OverlayInspectorStatusText.Text =
                _language.Equals("zh", StringComparison.OrdinalIgnoreCase)
                    ? $"{Math.Round(rect.Width)} x {Math.Round(rect.Height)} / {GetOverlayAnchorDisplayName(item, false)} / 已启用"
                    : $"{Math.Round(rect.Width)} x {Math.Round(rect.Height)} / {GetOverlayAnchorDisplayName(item, false)} / Enabled";
        }

        OverlayInspectorXBox.Text = Math.Round(rect.Left).ToString(CultureInfo.InvariantCulture);
        OverlayInspectorYBox.Text = Math.Round(rect.Top).ToString(CultureInfo.InvariantCulture);
        OverlayInspectorWidthBox.Text = Math.Round(rect.Width).ToString(CultureInfo.InvariantCulture);
        OverlayInspectorHeightBox.Text = Math.Round(rect.Height).ToString(CultureInfo.InvariantCulture);
        OverlayInspectorGeometryPanel.Visibility = Visibility.Visible;
        OverlayInspectorGeometryExpander.Visibility = Visibility.Visible;
        OverlayInspectorGeometryExpander.IsEnabled = !item.IsLocked && !_isOverlayLayoutLocked && !IsOverlayChatBarrage(item);
        SyncOverlayModuleStyleControls(item);
        SyncOverlayInspectorModuleControls(item, false);
        SetOverlayInspectorInputsEnabled(!item.IsLocked && !_isOverlayLayoutLocked && !IsOverlayChatBarrage(item));
        SyncOverlayInspectorAnchorControls(item);
        OverlayInspectorResetButton.IsEnabled = true;
        OverlayInspectorHideButton.IsEnabled = true;
        if (OverlayInspectorAccentSwatch is not null)
        {
            OverlayInspectorAccentSwatch.Background = item.Brush;
        }

        RefreshOverlayHiddenModuleLibrary();
        RefreshOverlayFullScreenToolsInspector();
    }

    private void RefreshOverlayInspectorModulePicker()
    {
        if (OverlayInspectorModulePickerPanel is null)
        {
            return;
        }

        var visibleItems = _overlayLayout
            .Where(IsOverlayEditorItemVisible)
            .OrderBy(item => GetOverlayInspectorModulePickerOrder(item.Key))
            .ThenBy(item => item.Key, StringComparer.OrdinalIgnoreCase)
            .ToList();
        var sceneKind = ResolveCurrentOverlayScene().Context.Kind;
        var selectedKey = _isOverlayEventNotificationSelected
            ? "EventNotifications"
            : _isOverlayCrosshairSelected
                ? "Crosshair"
                : _selectedOverlayInspectorItem?.Key ?? "";
        var signature = string.Join(
            "|",
            _language,
            sceneKind,
            selectedKey,
            _overlaySettings.Theme,
            _overlaySettings.CrosshairColor,
            _overlaySettings.ShowEventNotifications,
            _overlaySettings.ShowCrosshair,
            string.Join(",", visibleItems.Select(item => $"{item.Key}:{item.IsLocked}")));
        if (signature.Equals(_overlayInspectorModulePickerSignature, StringComparison.Ordinal))
        {
            return;
        }

        _overlayInspectorModulePickerSignature = signature;
        OverlayInspectorModulePickerPanel.Children.Clear();

        foreach (var item in visibleItems)
        {
            OverlayInspectorModulePickerPanel.Children.Add(
                CreateOverlayInspectorModulePickerEntry(
                    item.Key,
                    ResolveOverlayEditorPanelTitle(item),
                    item.Brush,
                    item.Key.Equals(selectedKey, StringComparison.OrdinalIgnoreCase),
                    item.IsLocked));
        }

        if (_overlaySettings.ShowEventNotifications)
        {
            OverlayInspectorModulePickerPanel.Children.Add(
                CreateOverlayInspectorModulePickerEntry(
                    "EventNotifications",
                    _language.Equals("zh", StringComparison.OrdinalIgnoreCase) ? "事件通知" : "Event notifications",
                    GetOverlayEventNotificationPreviewBrush(),
                    selectedKey.Equals("EventNotifications", StringComparison.OrdinalIgnoreCase),
                    false));
        }

        if (_overlaySettings.ShowCrosshair)
        {
            OverlayInspectorModulePickerPanel.Children.Add(
                CreateOverlayInspectorModulePickerEntry(
                    "Crosshair",
                    _language.Equals("zh", StringComparison.OrdinalIgnoreCase) ? "虚拟准星" : "Crosshair",
                    GetCrosshairPreviewBrush(GetEffectiveOverlaySettings()),
                    selectedKey.Equals("Crosshair", StringComparison.OrdinalIgnoreCase),
                    true));
        }
    }

    private static int GetOverlayInspectorModulePickerOrder(string key)
    {
        return key switch
        {
            "Notice" => 0,
            "Squads" => 1,
            "Members" => 2,
            "Chat" => 3,
            _ => 100
        };
    }

    private Border CreateOverlayInspectorModulePickerEntry(
        string key,
        string title,
        System.Windows.Media.Brush accent,
        bool selected,
        bool locked)
    {
        var routeLight = new Border
        {
            Width = 3,
            Margin = new Thickness(0, 4, 0, 4),
            Background = selected
                ? FindBrush("OverlaySettingsNavigationRouteLightBrush", accent)
                : Brushes.Transparent,
            CornerRadius = new CornerRadius(2),
            Effect = selected
                ? new DropShadowEffect
                {
                    Color = Color.FromRgb(105, 204, 255),
                    BlurRadius = 8,
                    ShadowDepth = 0,
                    Opacity = 0.45
                }
                : null
        };

        var accentSwatch = new Border
        {
            Width = 8,
            Height = 8,
            Margin = new Thickness(9, 0, 8, 0),
            VerticalAlignment = VerticalAlignment.Center,
            Background = accent,
            BorderBrush = new SolidColorBrush(Color.FromArgb(120, 225, 246, 255)),
            BorderThickness = new Thickness(1)
        };

        var titleText = new TextBlock
        {
            Text = title,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = selected
                ? FindBrush("TextPrimaryBrush", Brushes.AliceBlue)
                : FindBrush("TextSecondaryBrush", Brushes.LightSteelBlue),
            FontSize = 11.5,
            FontWeight = selected ? FontWeights.SemiBold : FontWeights.Normal,
            TextTrimming = TextTrimming.CharacterEllipsis
        };

        var stateText = new TextBlock
        {
            Text = selected
                ? (_language.Equals("zh", StringComparison.OrdinalIgnoreCase) ? "当前" : "Current")
                : locked
                    ? (_language.Equals("zh", StringComparison.OrdinalIgnoreCase) ? "已锁定" : "Locked")
                    : "",
            Margin = new Thickness(6, 0, 8, 0),
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = selected
                ? FindBrush("AccentBrush", Brushes.DeepSkyBlue)
                : FindBrush("MutedTextBrush", Brushes.LightSlateGray),
            FontSize = 9.5,
            FontWeight = FontWeights.SemiBold
        };

        var content = new Grid();
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        content.Children.Add(routeLight);
        Grid.SetColumn(accentSwatch, 1);
        content.Children.Add(accentSwatch);
        Grid.SetColumn(titleText, 2);
        content.Children.Add(titleText);
        Grid.SetColumn(stateText, 3);
        content.Children.Add(stateText);

        var entry = new Border
        {
            Tag = key,
            Height = 40,
            Margin = new Thickness(0, 0, 6, 6),
            Background = new SolidColorBrush(selected
                ? Color.FromArgb(220, 17, 47, 66)
                : Color.FromArgb(150, 6, 22, 32)),
            BorderBrush = new SolidColorBrush(selected
                ? Color.FromArgb(235, 78, 175, 224)
                : Color.FromArgb(115, 54, 86, 109)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(3),
            Cursor = Cursors.Hand,
            Focusable = true,
            ToolTip = _language.Equals("zh", StringComparison.OrdinalIgnoreCase)
                ? $"切换到{title}"
                : $"Switch to {title}",
            Child = content
        };
        AutomationProperties.SetName(entry, title);
        entry.MouseLeftButtonDown += OverlayInspectorModulePickerEntry_MouseLeftButtonDown;
        entry.KeyDown += OverlayInspectorModulePickerEntry_KeyDown;
        return entry;
    }

    private void OverlayInspectorModulePickerEntry_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: string key } entry)
        {
            return;
        }

        entry.Focus();
        ActivateOverlayInspectorModulePickerEntry(key);
        e.Handled = true;
    }

    private void OverlayInspectorModulePickerEntry_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: string key } ||
            e.Key is not (Key.Enter or Key.Space))
        {
            return;
        }

        ActivateOverlayInspectorModulePickerEntry(key);
        e.Handled = true;
    }

    private void ActivateOverlayInspectorModulePickerEntry(string key)
    {
        SelectOverlayLayerEntry(key);
        SetOverlayInspectorOpen(true);
        RefreshOverlayInspector();
        OverlayInspectorModulePickerExpander.IsExpanded = false;
        SmoothWheelScrollBehavior.CancelPendingMotion(OverlayInspectorScrollViewer);
        OverlayInspectorScrollViewer.ScrollToTop();
    }

    private void OpenOverlayModuleWorkbench_Click(object sender, RoutedEventArgs e)
    {
        var selectedKey = ResolveSelectedOverlayInspectorModuleKey();
        if (string.IsNullOrWhiteSpace(selectedKey))
        {
            selectedKey = ResolveFirstAvailableOverlayInspectorModuleKey();
        }

        if (string.IsNullOrWhiteSpace(selectedKey))
        {
            StarBridgeMessageBox.Show(
                this,
                _language.Equals("zh", StringComparison.OrdinalIgnoreCase)
                    ? "当前没有可调整的模块。请先在下方“模块开关”中启用至少一个模块。"
                    : "There are no modules available to adjust. Enable at least one module under Module toggles first.",
                _language.Equals("zh", StringComparison.OrdinalIgnoreCase)
                    ? "模块工作台"
                    : "Module workbench",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            return;
        }

        SelectOverlayLayerEntry(selectedKey);
        SetOverlayInspectorOpen(true);
        RefreshOverlayInspector();
        OverlayInspectorModulePickerExpander.IsExpanded = true;
        SmoothWheelScrollBehavior.CancelPendingMotion(OverlayInspectorScrollViewer);
        OverlayInspectorScrollViewer.ScrollToTop();
        NotifyOverlaySettingsGuideTarget(OverlayOpenModuleWorkbenchButton);
    }

    private string? ResolveSelectedOverlayInspectorModuleKey()
    {
        if (_isOverlayEventNotificationSelected && _overlaySettings.ShowEventNotifications)
        {
            return "EventNotifications";
        }

        if (_isOverlayCrosshairSelected && _overlaySettings.ShowCrosshair)
        {
            return "Crosshair";
        }

        return _selectedOverlayInspectorItem is not null &&
               _overlayLayout.Contains(_selectedOverlayInspectorItem) &&
               IsOverlayEditorItemVisible(_selectedOverlayInspectorItem)
            ? _selectedOverlayInspectorItem.Key
            : null;
    }

    private string? ResolveFirstAvailableOverlayInspectorModuleKey()
    {
        var itemKey = _overlayLayout
            .Where(IsOverlayEditorItemVisible)
            .OrderBy(item => GetOverlayInspectorModulePickerOrder(item.Key))
            .ThenBy(item => item.Key, StringComparer.OrdinalIgnoreCase)
            .Select(item => item.Key)
            .FirstOrDefault();
        if (!string.IsNullOrWhiteSpace(itemKey))
        {
            return itemKey;
        }

        if (_overlaySettings.ShowEventNotifications)
        {
            return "EventNotifications";
        }

        return _overlaySettings.ShowCrosshair ? "Crosshair" : null;
    }

    private void RefreshOverlayFullScreenToolsInspector()
    {
        if (OverlayFullScreenInspectorTitleText is null ||
            OverlayFullScreenInspectorStatusText is null ||
            OverlayFullScreenInspectorXBox is null ||
            OverlayFullScreenInspectorYBox is null ||
            OverlayFullScreenInspectorWidthBox is null ||
            OverlayFullScreenInspectorHeightBox is null ||
            OverlayFullScreenInspectorResetButton is null ||
            OverlayFullScreenInspectorHideButton is null)
        {
            return;
        }

        if (_isOverlayEventNotificationSelected && _overlaySettings.ShowEventNotifications)
        {
            var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
            var side = _overlaySettings.EventNotificationSide == OverlayEventNotificationSide.Left
                ? zh ? "左侧吸附" : "Left snap"
                : zh ? "右侧吸附" : "Right snap";
            OverlayFullScreenInspectorTitleText.Text = zh ? "事件通知" : "Event notifications";
            OverlayFullScreenInspectorStatusText.Text = zh
                ? $"{side} / 永远置顶 / {_overlaySettings.EventNotificationDurationSeconds:0.#} 秒"
                : $"{side} / Always on top / {_overlaySettings.EventNotificationDurationSeconds:0.#}s";
            OverlayFullScreenInspectorXBox.Text = side;
            OverlayFullScreenInspectorYBox.Text = Math.Round(ResolveOverlayEditorEventNotificationTop(92)).ToString(CultureInfo.InvariantCulture);
            OverlayFullScreenInspectorWidthBox.Text = $"{ResolveOverlayEditorEventNotificationWidth():0} / 自动贴边";
            OverlayFullScreenInspectorHeightBox.Text = $"{_overlaySettings.EventNotificationDurationSeconds:0.#} 秒";
            SetOverlayFullScreenGeometryPanelVisibility(Visibility.Visible);
            SyncOverlayModuleStyleControls(null);
            SetOverlayFullScreenInspectorInputsEnabled(false);
            SyncOverlayFullScreenAnchorControls(null);
            SyncOverlayFullScreenModuleControls(null, true);
            OverlayFullScreenInspectorResetButton.IsEnabled = false;
            OverlayFullScreenInspectorHideButton.IsEnabled = true;
            if (OverlayFullScreenInspectorAccentSwatch is not null)
            {
                OverlayFullScreenInspectorAccentSwatch.Background = GetOverlayEventNotificationPreviewBrush();
            }

            return;
        }

        if (_isOverlayCrosshairSelected && _overlaySettings.ShowCrosshair)
        {
            var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
            var mode = FormatOverlayCrosshairMode(_overlaySettings.CrosshairMode, zh);
            OverlayFullScreenInspectorTitleText.Text = zh ? "虚拟准星" : "Virtual crosshair";
            OverlayFullScreenInspectorStatusText.Text = zh
                ? $"{mode} / {OverlayDisplaySettings.NormalizeCrosshairSize(_overlaySettings.CrosshairSize):0}px / 固定屏幕中心"
                : $"{mode} / {OverlayDisplaySettings.NormalizeCrosshairSize(_overlaySettings.CrosshairSize):0}px / Fixed center";
            OverlayFullScreenInspectorXBox.Text = "";
            OverlayFullScreenInspectorYBox.Text = "";
            OverlayFullScreenInspectorWidthBox.Text = "";
            OverlayFullScreenInspectorHeightBox.Text = "";
            SetOverlayFullScreenGeometryPanelVisibility(Visibility.Collapsed);
            SyncOverlayModuleStyleControls(null);
            SetOverlayFullScreenInspectorInputsEnabled(false);
            SyncOverlayFullScreenAnchorControls(null);
            SetOverlayFullScreenModulePanelVisibility("Crosshair");
            SyncOverlayFullScreenCrosshairControls();
            OverlayFullScreenInspectorResetButton.IsEnabled = true;
            OverlayFullScreenInspectorHideButton.IsEnabled = true;
            if (OverlayFullScreenInspectorAccentSwatch is not null)
            {
                OverlayFullScreenInspectorAccentSwatch.Background = GetCrosshairPreviewBrush(GetEffectiveOverlaySettings());
            }

            return;
        }

        var item = _selectedOverlayInspectorItem;
        if (item is null ||
            !_overlayLayout.Contains(item) ||
            !IsOverlayEditorItemVisible(item) ||
            OverlayEditorCanvas is null)
        {
            var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
            OverlayFullScreenInspectorTitleText.Text = zh ? "未选中模块" : "No module selected";
            OverlayFullScreenInspectorStatusText.Text = zh
                ? "在画布上选择模块以编辑"
                : "Select a module on the canvas to edit";
            OverlayFullScreenInspectorXBox.Text = "";
            OverlayFullScreenInspectorYBox.Text = "";
            OverlayFullScreenInspectorWidthBox.Text = "";
            OverlayFullScreenInspectorHeightBox.Text = "";
            SetOverlayFullScreenGeometryPanelVisibility(Visibility.Collapsed);
            SyncOverlayModuleStyleControls(null);
            SetOverlayFullScreenInspectorInputsEnabled(false);
            SyncOverlayFullScreenAnchorControls(null);
            SyncOverlayFullScreenModuleControls(null, false);
            OverlayFullScreenInspectorResetButton.IsEnabled = false;
            OverlayFullScreenInspectorHideButton.IsEnabled = false;
            if (OverlayFullScreenInspectorAccentSwatch is not null)
            {
                OverlayFullScreenInspectorAccentSwatch.Background = GetOverlayThemeAccent(GetEffectiveOverlaySettings().Theme);
            }

            return;
        }

        var rect = ResolveOverlayEditorItemDisplayRect(item);
        OverlayFullScreenInspectorTitleText.Text = ResolveOverlayEditorPanelTitle(item);
        OverlayFullScreenInspectorStatusText.Text = _language.Equals("zh", StringComparison.OrdinalIgnoreCase)
            ? $"{Math.Round(rect.Width)} x {Math.Round(rect.Height)} / {GetOverlayAnchorDisplayName(item, false)} / 已启用"
            : $"{Math.Round(rect.Width)} x {Math.Round(rect.Height)} / {GetOverlayAnchorDisplayName(item, false)} / Enabled";
        OverlayFullScreenInspectorXBox.Text = Math.Round(rect.Left).ToString(CultureInfo.InvariantCulture);
        OverlayFullScreenInspectorYBox.Text = Math.Round(rect.Top).ToString(CultureInfo.InvariantCulture);
        OverlayFullScreenInspectorWidthBox.Text = Math.Round(rect.Width).ToString(CultureInfo.InvariantCulture);
        OverlayFullScreenInspectorHeightBox.Text = Math.Round(rect.Height).ToString(CultureInfo.InvariantCulture);
        SetOverlayFullScreenGeometryPanelVisibility(Visibility.Visible);
        SyncOverlayModuleStyleControls(item);
        SetOverlayFullScreenInspectorInputsEnabled(!item.IsLocked && !_isOverlayLayoutLocked && !IsOverlayChatBarrage(item));
        SyncOverlayFullScreenAnchorControls(item);
        SyncOverlayFullScreenModuleControls(item, false);
        OverlayFullScreenInspectorResetButton.IsEnabled = true;
        OverlayFullScreenInspectorHideButton.IsEnabled = true;
        if (OverlayFullScreenInspectorAccentSwatch is not null)
        {
            OverlayFullScreenInspectorAccentSwatch.Background = item.Brush;
        }
    }

    private void SetOverlayFullScreenInspectorInputsEnabled(bool isEnabled)
    {
        if (OverlayFullScreenInspectorXBox is not null)
        {
            OverlayFullScreenInspectorXBox.IsEnabled = isEnabled;
        }

        if (OverlayFullScreenInspectorYBox is not null)
        {
            OverlayFullScreenInspectorYBox.IsEnabled = isEnabled;
        }

        if (OverlayFullScreenInspectorWidthBox is not null)
        {
            OverlayFullScreenInspectorWidthBox.IsEnabled = isEnabled;
        }

        if (OverlayFullScreenInspectorHeightBox is not null)
        {
            OverlayFullScreenInspectorHeightBox.IsEnabled = isEnabled;
        }
    }

    private void SetOverlayFullScreenGeometryPanelVisibility(Visibility visibility)
    {
        if (OverlayFullScreenInspectorAnchorPanel is not null)
        {
            OverlayFullScreenInspectorAnchorPanel.Visibility = visibility;
        }

        if (OverlayFullScreenInspectorGeometryPanel is not null)
        {
            OverlayFullScreenInspectorGeometryPanel.Visibility = visibility;
        }
    }

    private void SyncOverlayFullScreenAnchorControls(OverlayLayoutItem? item)
    {
        _isSyncingOverlayInspectorAnchorControls = true;
        try
        {
            if (OverlayFullScreenHorizontalAnchorBox is not null)
            {
                OverlayFullScreenHorizontalAnchorBox.IsEnabled = item is not null && !item.IsLocked && !_isOverlayLayoutLocked && !IsOverlayChatBarrage(item);
                OverlayFullScreenHorizontalAnchorBox.SelectedIndex = item is null
                    ? -1
                    : GetComboBoxItemIndexByTag(OverlayFullScreenHorizontalAnchorBox, item.HorizontalAnchor.ToString());
            }

            if (OverlayFullScreenVerticalAnchorBox is not null)
            {
                OverlayFullScreenVerticalAnchorBox.IsEnabled = item is not null && !item.IsLocked && !_isOverlayLayoutLocked && !IsOverlayChatBarrage(item);
                OverlayFullScreenVerticalAnchorBox.SelectedIndex = item is null
                    ? -1
                    : GetComboBoxItemIndexByTag(OverlayFullScreenVerticalAnchorBox, item.VerticalAnchor.ToString());
            }
        }
        finally
        {
            _isSyncingOverlayInspectorAnchorControls = false;
        }
    }

    private void SyncOverlayFullScreenModuleControls(OverlayLayoutItem? item, bool eventNotificationSelected)
    {
        _isSyncingOverlayInspectorModuleControls = true;
        try
        {
            SetOverlayFullScreenModulePanelVisibility(null);

            if (eventNotificationSelected)
            {
                SetOverlayFullScreenModulePanelVisibility("EventNotifications");
                SyncOverlayFullScreenEventControls();
                return;
            }

            if (item is null)
            {
                return;
            }

            SetOverlayFullScreenModulePanelVisibility(item.Key);
            switch (item.Key)
            {
                case "Notice":
                    SyncOverlayFullScreenNoticeControls();
                    break;
                case "Squads":
                    SyncOverlayFullScreenSquadControls();
                    break;
                case "Members":
                    SyncOverlayFullScreenMemberControls();
                    break;
                case "Chat":
                    SyncOverlayFullScreenChatControls();
                    break;
            }
        }
        finally
        {
            _isSyncingOverlayInspectorModuleControls = false;
        }
    }

    private void SetOverlayFullScreenModulePanelVisibility(string? key)
    {
        if (OverlayFullScreenModuleSettingsPanel is not null)
        {
            OverlayFullScreenModuleSettingsPanel.Visibility = string.IsNullOrWhiteSpace(key)
                ? Visibility.Collapsed
                : Visibility.Visible;
        }

        if (OverlayFullScreenEventSettingsPanel is not null)
        {
            OverlayFullScreenEventSettingsPanel.Visibility = string.Equals(key, "EventNotifications", StringComparison.OrdinalIgnoreCase)
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (OverlayFullScreenCrosshairSettingsPanel is not null)
        {
            OverlayFullScreenCrosshairSettingsPanel.Visibility = string.Equals(key, "Crosshair", StringComparison.OrdinalIgnoreCase)
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (OverlayFullScreenNoticeSettingsPanel is not null)
        {
            OverlayFullScreenNoticeSettingsPanel.Visibility = string.Equals(key, "Notice", StringComparison.OrdinalIgnoreCase)
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (OverlayFullScreenSquadsSettingsPanel is not null)
        {
            OverlayFullScreenSquadsSettingsPanel.Visibility = string.Equals(key, "Squads", StringComparison.OrdinalIgnoreCase)
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (OverlayFullScreenMembersSettingsPanel is not null)
        {
            OverlayFullScreenMembersSettingsPanel.Visibility = string.Equals(key, "Members", StringComparison.OrdinalIgnoreCase)
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (OverlayFullScreenChatSettingsPanel is not null)
        {
            OverlayFullScreenChatSettingsPanel.Visibility = string.Equals(key, "Chat", StringComparison.OrdinalIgnoreCase)
                ? Visibility.Visible
                : Visibility.Collapsed;
        }
    }

    private void SyncOverlayFullScreenEventControls()
    {
        var previousSyncing = _isSyncingOverlayInspectorModuleControls;
        _isSyncingOverlayInspectorModuleControls = true;
        try
        {
            var enabled = _overlaySettings.ShowEventNotifications;
            if (OverlayFullScreenEventSideBox is not null)
            {
                OverlayFullScreenEventSideBox.SelectedIndex = _overlaySettings.EventNotificationSide == OverlayEventNotificationSide.Left ? 0 : 1;
                SetOverlayInspectorModuleControlEnabled(OverlayFullScreenEventSideBox, enabled);
            }

            if (OverlayFullScreenEventDurationBox is not null)
            {
                if (!OverlayFullScreenEventDurationBox.IsKeyboardFocusWithin)
                {
                    OverlayFullScreenEventDurationBox.Text = _overlaySettings.EventNotificationDurationSeconds.ToString("0.#", CultureInfo.InvariantCulture);
                }

                OverlayFullScreenEventDurationBox.IsEnabled = enabled;
                OverlayFullScreenEventDurationBox.Opacity = enabled ? 1.0 : 0.52;
            }

        }
        finally
        {
            _isSyncingOverlayInspectorModuleControls = previousSyncing;
        }
    }

    private void SyncOverlayFullScreenNoticeControls()
    {
        var previousSyncing = _isSyncingOverlayInspectorModuleControls;
        _isSyncingOverlayInspectorModuleControls = true;
        try
        {
            if (OverlayFullScreenNoticeHintText is not null)
            {
                OverlayFullScreenNoticeHintText.Text = _language.Equals("zh", StringComparison.OrdinalIgnoreCase)
                    ? "无事件时自动隐藏；位置仅可贴合画布顶部或底部。"
                    : "Hidden while idle. This module can only dock to the top or bottom edge.";
            }

            if (OverlayFullScreenCommunicationFriendEventsCheck is not null)
            {
                OverlayFullScreenCommunicationFriendEventsCheck.IsChecked = _overlaySettings.CommunicationFriendEvents;
                SetOverlayInspectorModuleControlEnabled(OverlayFullScreenCommunicationFriendEventsCheck, _overlaySettings.ShowNotice);
            }

            if (OverlayFullScreenCommunicationMessagePreviewCheck is not null)
            {
                OverlayFullScreenCommunicationMessagePreviewCheck.IsChecked = _overlaySettings.CommunicationMessagePreview;
                SetOverlayInspectorModuleControlEnabled(
                    OverlayFullScreenCommunicationMessagePreviewCheck,
                    _overlaySettings.ShowNotice && _overlaySettings.CommunicationFriendEvents);
            }

            SyncCommunicationDockBox(OverlayFullScreenCommunicationDockBox);
            if (OverlayFullScreenCommunicationDurationSlider is not null)
            {
                OverlayFullScreenCommunicationDurationSlider.Value =
                    OverlayDisplaySettings.NormalizeCommunicationEventDuration(_overlaySettings.CommunicationEventDurationSeconds);
                SetOverlayInspectorModuleControlEnabled(OverlayFullScreenCommunicationDurationSlider, _overlaySettings.ShowNotice);
            }

            if (OverlayFullScreenCommunicationDurationValueText is not null)
            {
                OverlayFullScreenCommunicationDurationValueText.Text = $"{_overlaySettings.CommunicationEventDurationSeconds:0.#}s";
            }
        }
        finally
        {
            _isSyncingOverlayInspectorModuleControls = previousSyncing;
        }
    }

    private void SyncOverlayFullScreenSquadControls()
    {
        var enabled = _overlaySettings.ShowSquads;
        if (OverlayFullScreenSquadStatusModeBox is not null)
        {
            OverlayFullScreenSquadStatusModeBox.SelectedIndex = _overlaySettings.SquadStatusDisplayMode switch
            {
                OverlaySquadStatusDisplayMode.Compact => 1,
                OverlaySquadStatusDisplayMode.Detailed => 2,
                _ => 0
            };
            SetOverlayInspectorModuleControlEnabled(OverlayFullScreenSquadStatusModeBox, enabled);
        }

        if (OverlayFullScreenHideSquadIconsCheck is not null)
        {
            OverlayFullScreenHideSquadIconsCheck.IsChecked = _overlaySettings.HideSquadIcons;
            SetOverlayInspectorModuleControlEnabled(OverlayFullScreenHideSquadIconsCheck, enabled);
        }
    }

    private void SyncOverlayFullScreenMemberControls()
    {
        var membersEnabled = _overlaySettings.ShowMembers;
        var roomScene = ResolveCurrentOverlayScene().Context.Kind == OverlaySceneKind.PartyRoom;
        if (OverlayFullScreenMemberScopeBox is not null)
        {
            OverlayFullScreenMemberScopeBox.SelectedIndex = _overlaySettings.MemberScopeMode switch
            {
                OverlayMemberScopeMode.AllFleet => 1,
                OverlayMemberScopeMode.OtherSquads => 2,
                _ => 0
            };
            SetOverlayInspectorModuleControlEnabled(OverlayFullScreenMemberScopeBox, membersEnabled && !roomScene);
            OverlayFullScreenMemberScopeBox.ToolTip = roomScene
                ? "房间场景固定显示当前房间成员"
                : null;
        }

        if (OverlayFullScreenHideOfflineMembersCheck is not null)
        {
            OverlayFullScreenHideOfflineMembersCheck.IsChecked = _overlaySettings.HideOfflineMembers;
            SetOverlayInspectorModuleControlEnabled(OverlayFullScreenHideOfflineMembersCheck, membersEnabled);
        }

        if (OverlayFullScreenHideMemberOnlineStatusCheck is not null)
        {
            OverlayFullScreenHideMemberOnlineStatusCheck.IsChecked = _overlaySettings.EffectiveHideMemberOnlineStatus;
            SetOverlayInspectorModuleControlEnabled(
                OverlayFullScreenHideMemberOnlineStatusCheck,
                membersEnabled && _overlaySettings.HideOfflineMembers);
        }

        if (OverlayFullScreenHideSelfMemberCheck is not null)
        {
            OverlayFullScreenHideSelfMemberCheck.IsChecked = _overlaySettings.HideSelfMember;
            SetOverlayInspectorModuleControlEnabled(OverlayFullScreenHideSelfMemberCheck, membersEnabled);
        }

        if (OverlayFullScreenMemberPriorityBox is not null)
        {
            OverlayFullScreenMemberPriorityBox.SelectedIndex = _overlaySettings.MemberPriorityMode switch
            {
                OverlayMemberPriorityMode.Self => 1,
                OverlayMemberPriorityMode.SquadCommander => 2,
                _ => 0
            };
            SetOverlayInspectorModuleControlEnabled(OverlayFullScreenMemberPriorityBox, membersEnabled);
        }

        if (OverlayFullScreenMemberNameModeBox is not null)
        {
            OverlayFullScreenMemberNameModeBox.SelectedIndex = _overlaySettings.MemberNameMode switch
            {
                OverlayMemberNameMode.CallsignOnly => 1,
                OverlayMemberNameMode.GameNameOnly => 2,
                _ => 0
            };
            SetOverlayInspectorModuleControlEnabled(OverlayFullScreenMemberNameModeBox, membersEnabled);
        }

        if (OverlayFullScreenMemberColumnRatioText is not null)
        {
            var namePercent = Math.Round(OverlayDisplaySettings.NormalizeMemberNameColumnRatio(_overlaySettings.MemberNameColumnRatio) * 100);
            var locationPercent = 100 - namePercent;
            OverlayFullScreenMemberColumnRatioText.Text = _language.Equals("zh", StringComparison.OrdinalIgnoreCase)
                ? $"字段宽度：名字 {namePercent:0}% / 地点 {locationPercent:0}%，拖动成员行分隔线调整"
                : $"Field width: Name {namePercent:0}% / Location {locationPercent:0}%. Drag the member-row divider to adjust.";
            OverlayFullScreenMemberColumnRatioText.Opacity = membersEnabled ? 1.0 : 0.52;
        }
    }

    private void SyncOverlayFullScreenChatControls()
    {
        SyncOverlayFleetChatScopeControls(
            OverlayFullScreenFleetChatScopeRow,
            OverlayFullScreenFleetChatScopeBox);
        SyncOverlayChatControls(
            OverlayFullScreenChatModeBox,
            OverlayFullScreenChatSideBox,
            OverlayFullScreenChatDurationBox,
            OverlayFullScreenChatFontSizeBox,
            OverlayFullScreenChatRegionBox,
            OverlayFullScreenChatDensityBox,
            OverlayFullScreenChatEdgeStrengthBox,
            OverlayFullScreenChatAvoidCenterCheck,
            OverlayFullScreenChatBarrageSettingsPanel,
            OverlayFullScreenChatShowSenderCheck,
            OverlayFullScreenChatShowTimestampCheck,
            OverlayFullScreenChatShowSystemCheck,
            OverlayFullScreenChatHideSelfCheck);
    }

    private string GetOverlayInspectorSubtitle(OverlayLayoutItem item)
    {
        var anchorText = GetOverlayAnchorDisplayName(item, false);
        if (_language != "zh")
        {
            var moduleText = item.Key switch
            {
                "Notice" => "Communication alerts module",
                "Squads" => "Team overview module",
                "Members" => "Member information module",
                "Chat" => "Scene communication module",
                _ => item.Key
            };
            return $"{moduleText} / Anchor {anchorText}";
        }

        var zhModuleText = item.Key switch
        {
            "Notice" => "通讯提醒模块",
            "Squads" => "队伍概况模块",
            "Members" => "成员信息模块",
            "Chat" => "场景通讯模块",
            _ => item.Title
        };
        return $"{zhModuleText} / 锚点 {anchorText}";
    }

    private string GetOverlayAnchorDisplayName(OverlayLayoutItem item, bool compact)
    {
        var horizontal = item.HorizontalAnchor switch
        {
            OverlayHorizontalAnchor.Left => _language == "zh" ? "左" : "L",
            OverlayHorizontalAnchor.Right => _language == "zh" ? "右" : "R",
            _ => _language == "zh" ? "居中" : "C"
        };
        var vertical = item.VerticalAnchor switch
        {
            OverlayVerticalAnchor.Top => _language == "zh" ? "上" : "T",
            OverlayVerticalAnchor.Bottom => _language == "zh" ? "下" : "B",
            _ => _language == "zh" ? "中" : "M"
        };

        return compact
            ? $"{horizontal}{vertical}"
            : $"{horizontal} / {vertical}";
    }

    private void SetOverlayInspectorInputsEnabled(bool isEnabled)
    {
        if (OverlayInspectorXBox is not null)
        {
            OverlayInspectorXBox.IsEnabled = isEnabled;
        }

        if (OverlayInspectorYBox is not null)
        {
            OverlayInspectorYBox.IsEnabled = isEnabled;
        }

        if (OverlayInspectorWidthBox is not null)
        {
            OverlayInspectorWidthBox.IsEnabled = isEnabled;
        }

        if (OverlayInspectorHeightBox is not null)
        {
            OverlayInspectorHeightBox.IsEnabled = isEnabled;
        }
    }

    private void SyncOverlayInspectorAnchorControls(OverlayLayoutItem? item)
    {
        _isSyncingOverlayInspectorAnchorControls = true;
        try
        {
            if (OverlayInspectorHorizontalAnchorBox is not null)
            {
                OverlayInspectorHorizontalAnchorBox.IsEnabled = item is not null && !item.IsLocked && !_isOverlayLayoutLocked && !IsOverlayChatBarrage(item);
                OverlayInspectorHorizontalAnchorBox.SelectedIndex = item is null
                    ? -1
                    : GetComboBoxItemIndexByTag(OverlayInspectorHorizontalAnchorBox, item.HorizontalAnchor.ToString());
            }

            if (OverlayInspectorVerticalAnchorBox is not null)
            {
                OverlayInspectorVerticalAnchorBox.IsEnabled = item is not null && !item.IsLocked && !_isOverlayLayoutLocked && !IsOverlayChatBarrage(item);
                OverlayInspectorVerticalAnchorBox.SelectedIndex = item is null
                    ? -1
                    : GetComboBoxItemIndexByTag(OverlayInspectorVerticalAnchorBox, item.VerticalAnchor.ToString());
            }
        }
        finally
        {
            _isSyncingOverlayInspectorAnchorControls = false;
        }
    }

    private void SyncOverlayInspectorModuleControls(OverlayLayoutItem? item, bool eventNotificationSelected)
    {
        _isSyncingOverlayInspectorModuleControls = true;
        try
        {
            SetOverlayInspectorModulePanelVisibility(null);

            if (eventNotificationSelected)
            {
                SetOverlayInspectorModulePanelVisibility("EventNotifications");
                RefreshOverlayEventNotificationControls();
                return;
            }

            if (item is null)
            {
                return;
            }

            SetOverlayInspectorModulePanelVisibility(item.Key);
            switch (item.Key)
            {
                case "Notice":
                    SyncOverlayInspectorNoticeControls();
                    break;
                case "Squads":
                    SyncOverlayInspectorSquadControls();
                    break;
                case "Members":
                    SyncOverlayInspectorMemberControls();
                    break;
                case "Chat":
                    SyncOverlayInspectorChatControls();
                    break;
            }
        }
        finally
        {
            _isSyncingOverlayInspectorModuleControls = false;
        }
    }

    private void SetOverlayInspectorModulePanelVisibility(string? key)
    {
        if (OverlayEventInspectorPanel is not null)
        {
            OverlayEventInspectorPanel.Visibility = string.Equals(key, "EventNotifications", StringComparison.OrdinalIgnoreCase)
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (OverlayInspectorCrosshairPanel is not null)
        {
            OverlayInspectorCrosshairPanel.Visibility = string.Equals(key, "Crosshair", StringComparison.OrdinalIgnoreCase)
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (OverlayNoticeInspectorPanel is not null)
        {
            OverlayNoticeInspectorPanel.Visibility = string.Equals(key, "Notice", StringComparison.OrdinalIgnoreCase)
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (OverlaySquadsInspectorPanel is not null)
        {
            OverlaySquadsInspectorPanel.Visibility = string.Equals(key, "Squads", StringComparison.OrdinalIgnoreCase)
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (OverlayMembersInspectorPanel is not null)
        {
            OverlayMembersInspectorPanel.Visibility = string.Equals(key, "Members", StringComparison.OrdinalIgnoreCase)
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (OverlayChatInspectorPanel is not null)
        {
            OverlayChatInspectorPanel.Visibility = string.Equals(key, "Chat", StringComparison.OrdinalIgnoreCase)
                ? Visibility.Visible
                : Visibility.Collapsed;
        }
    }

    private void RefreshOverlayHiddenModuleLibrary()
    {
        var hiddenModules = GetOverlayHiddenModuleEntries().ToArray();
        RefreshOverlayHiddenModuleLibraryPanel(
            OverlayHiddenModuleLibraryPanel,
            OverlayHiddenModuleButtonsPanel,
            OverlayHiddenModuleCountText,
            hiddenModules);
        RefreshOverlayHiddenModuleLibraryPanel(
            OverlayModuleLibraryPanel,
            OverlayModuleLibraryButtonsPanel,
            OverlayModuleLibraryCountText,
            hiddenModules);
        RefreshOverlayHiddenModuleLibraryPanel(
            OverlayFullScreenModuleLibraryPanel,
            OverlayFullScreenModuleLibraryButtonsPanel,
            OverlayFullScreenModuleLibraryCountText,
            hiddenModules);
        RefreshOverlayModuleSummary(hiddenModules.Length);
    }

    private void RefreshOverlayHiddenModuleLibraryPanel(
        FrameworkElement? panel,
        System.Windows.Controls.Panel? buttonsPanel,
        TextBlock? countText,
        IReadOnlyCollection<(string Key, string Title)> hiddenModules)
    {
        if (panel is null ||
            buttonsPanel is null ||
            countText is null)
        {
            return;
        }

        buttonsPanel.Children.Clear();
        panel.Visibility = hiddenModules.Count > 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        countText.Text = hiddenModules.Count.ToString(CultureInfo.InvariantCulture);
        foreach (var module in hiddenModules)
        {
            buttonsPanel.Children.Add(CreateOverlayHiddenModuleRestoreButton(module.Key, module.Title));
        }
    }

    private System.Windows.Controls.Button CreateOverlayHiddenModuleRestoreButton(string key, string title)
    {
        var button = new System.Windows.Controls.Button
        {
            Content = title,
            Tag = key,
            Height = 30,
            MinWidth = 82,
            Padding = new Thickness(10, 0, 10, 0),
            Margin = new Thickness(0, 0, 8, 8),
            Style = TryFindResource("SecondaryButton") as Style,
            ToolTip = _language.Equals("zh", StringComparison.OrdinalIgnoreCase)
                ? $"恢复 {title}"
                : $"Restore {title}"
        };
        button.Click += RestoreOverlayModuleFromLibrary_Click;
        return button;
    }

    private void RefreshOverlayModuleSummary(int hiddenModuleCount)
    {
        if (OverlayModuleSummaryText is null)
        {
            return;
        }

        var enabledModuleCount = CountEnabledOverlayModules();
        var totalModuleCount = CountAvailableOverlayModules();
        OverlayModuleSummaryText.Text = _language.Equals("zh", StringComparison.OrdinalIgnoreCase)
            ? $"已启用 {enabledModuleCount} / {totalModuleCount}，隐藏 {hiddenModuleCount}"
            : $"Enabled modules {enabledModuleCount} / {totalModuleCount}, hidden {hiddenModuleCount}";
    }

    private int CountAvailableOverlayModules()
    {
        return 5;
    }

    private int CountEnabledOverlayModules()
    {
        var count = 0;
        if (_overlaySettings.ShowNotice)
        {
            count++;
        }

        if (_overlaySettings.ShowSquads)
        {
            count++;
        }

        if (_overlaySettings.ShowMembers)
        {
            count++;
        }

        if (_overlaySettings.ShowChat)
        {
            count++;
        }

        if (_overlaySettings.ShowEventNotifications)
        {
            count++;
        }

        return count;
    }

    private IEnumerable<(string Key, string Title)> GetOverlayHiddenModuleEntries()
    {
        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        if (!_overlaySettings.ShowNotice)
        {
            yield return ("Notice", zh ? "通讯提醒" : "Communication alerts");
        }

        if (!_overlaySettings.ShowSquads)
        {
            yield return ("Squads", zh ? "队伍概况" : "Team overview");
        }

        if (!_overlaySettings.ShowMembers)
        {
            yield return ("Members", zh ? "成员信息" : "Member information");
        }

        if (!_overlaySettings.ShowChat)
        {
            yield return ("Chat", zh ? "场景通讯" : "Scene communication");
        }

        if (!_overlaySettings.ShowEventNotifications)
        {
            yield return ("EventNotifications", zh ? "事件通知" : "Event notifications");
        }
    }

    private void RestoreOverlayModuleFromLibrary_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.Button { Tag: string key })
        {
            return;
        }

        PushOverlayEditorUndoState();
        var wasLoadingSettings = _isLoadingSettings;
        _isLoadingSettings = true;
        try
        {
            switch (key)
            {
                case "Notice":
                    ShowNoticePanelCheck.IsChecked = true;
                    SelectOverlayLayoutItemByKey("Notice");
                    break;
                case "Squads":
                    ShowSquadsPanelCheck.IsChecked = true;
                    SelectOverlayLayoutItemByKey("Squads");
                    break;
                case "Members":
                    ShowMembersPanelCheck.IsChecked = true;
                    SelectOverlayLayoutItemByKey("Members");
                    break;
                case "Chat":
                    ShowChatPanelCheck.IsChecked = true;
                    SelectOverlayLayoutItemByKey("Chat");
                    break;
                case "EventNotifications":
                    ShowEventNotificationsCheck.IsChecked = true;
                    _selectedOverlayInspectorItem = null;
                    _isOverlayEventNotificationSelected = true;
                    _isOverlayCrosshairSelected = false;
                    break;
                case "Crosshair":
                    ShowCrosshairCheck.IsChecked = true;
                    _selectedOverlayInspectorItem = null;
                    _isOverlayEventNotificationSelected = false;
                    _isOverlayCrosshairSelected = true;
                    break;
            }
        }
        finally
        {
            _isLoadingSettings = wasLoadingSettings;
        }

        OverlaySetting_Changed(sender, e);
        RenderOverlayEditor();
        RefreshOverlayHiddenModuleLibrary();
    }

    private void SelectOverlayLayoutItemByKey(string key)
    {
        var item = _overlayLayout.FirstOrDefault(candidate =>
            candidate.Key.Equals(key, StringComparison.OrdinalIgnoreCase));
        if (item is null)
        {
            return;
        }

        _isOverlayEventNotificationSelected = false;
        _isOverlayCrosshairSelected = false;
        _selectedOverlayInspectorItem = item;
    }

    private void SyncOverlayInspectorNoticeControls()
    {
        var previousSyncing = _isSyncingOverlayInspectorModuleControls;
        _isSyncingOverlayInspectorModuleControls = true;
        try
        {
            if (OverlayNoticeInspectorEmptyText is not null)
            {
                OverlayNoticeInspectorEmptyText.Text = _language.Equals("zh", StringComparison.OrdinalIgnoreCase)
                    ? "无事件时自动隐藏；位置仅可贴合画布顶部或底部。"
                    : "Hidden while idle. This module can only dock to the top or bottom edge.";
            }

            if (OverlayInspectorCommunicationFriendEventsCheck is not null)
            {
                OverlayInspectorCommunicationFriendEventsCheck.IsChecked = _overlaySettings.CommunicationFriendEvents;
                SetOverlayInspectorModuleControlEnabled(OverlayInspectorCommunicationFriendEventsCheck, _overlaySettings.ShowNotice);
            }

            if (OverlayInspectorCommunicationMessagePreviewCheck is not null)
            {
                OverlayInspectorCommunicationMessagePreviewCheck.IsChecked = _overlaySettings.CommunicationMessagePreview;
                SetOverlayInspectorModuleControlEnabled(
                    OverlayInspectorCommunicationMessagePreviewCheck,
                    _overlaySettings.ShowNotice && _overlaySettings.CommunicationFriendEvents);
            }

            SyncCommunicationDockBox(OverlayInspectorCommunicationDockBox);
            if (OverlayInspectorCommunicationDurationSlider is not null)
            {
                OverlayInspectorCommunicationDurationSlider.Value =
                    OverlayDisplaySettings.NormalizeCommunicationEventDuration(_overlaySettings.CommunicationEventDurationSeconds);
                SetOverlayInspectorModuleControlEnabled(OverlayInspectorCommunicationDurationSlider, _overlaySettings.ShowNotice);
            }

            if (OverlayInspectorCommunicationDurationValueText is not null)
            {
                OverlayInspectorCommunicationDurationValueText.Text = $"{_overlaySettings.CommunicationEventDurationSeconds:0.#}s";
            }
        }
        finally
        {
            _isSyncingOverlayInspectorModuleControls = previousSyncing;
        }
    }

    private void SyncCommunicationDockBox(System.Windows.Controls.ComboBox? comboBox)
    {
        if (comboBox is null || !TryGetSelectedOverlayInspectorItem(out var item))
        {
            return;
        }

        comboBox.SelectedIndex = item.VerticalAnchor == OverlayVerticalAnchor.Bottom ? 1 : 0;
        SetOverlayInspectorModuleControlEnabled(comboBox, _overlaySettings.ShowNotice && !item.IsLocked && !_isOverlayLayoutLocked);
    }

    private void SyncOverlayInspectorEventControls()
    {
        var previousSyncing = _isSyncingOverlayInspectorModuleControls;
        _isSyncingOverlayInspectorModuleControls = true;
        try
        {
            var enabled = _overlaySettings.ShowEventNotifications;
            if (OverlayEventNotificationSideBox is not null)
            {
                OverlayEventNotificationSideBox.SelectedIndex = _overlaySettings.EventNotificationSide == OverlayEventNotificationSide.Left ? 0 : 1;
                SetOverlayInspectorModuleControlEnabled(OverlayEventNotificationSideBox, enabled);
            }

            if (OverlayEventNotificationDurationSlider is not null)
            {
                OverlayEventNotificationDurationSlider.Value = Math.Clamp(_overlaySettings.EventNotificationDurationSeconds, 1, 12);
                SetOverlayInspectorModuleControlEnabled(OverlayEventNotificationDurationSlider, enabled);
            }

            if (OverlayEventNotificationDurationValueText is not null)
            {
                OverlayEventNotificationDurationValueText.Text = $"{_overlaySettings.EventNotificationDurationSeconds:0.#}s";
            }
        }
        finally
        {
            _isSyncingOverlayInspectorModuleControls = previousSyncing;
        }
    }

    private void SyncOverlayInspectorSquadControls()
    {
        if (OverlayInspectorSquadStatusModeBox is not null)
        {
            OverlayInspectorSquadStatusModeBox.SelectedIndex = _overlaySettings.SquadStatusDisplayMode switch
            {
                OverlaySquadStatusDisplayMode.Compact => 1,
                OverlaySquadStatusDisplayMode.Detailed => 2,
                _ => 0
            };
            OverlayInspectorSquadStatusModeBox.IsEnabled = _overlaySettings.ShowSquads;
            OverlayInspectorSquadStatusModeBox.Opacity = _overlaySettings.ShowSquads ? 1.0 : 0.52;
        }

        if (OverlayInspectorHideSquadIconsCheck is not null)
        {
            OverlayInspectorHideSquadIconsCheck.IsChecked = _overlaySettings.HideSquadIcons;
            OverlayInspectorHideSquadIconsCheck.IsEnabled = _overlaySettings.ShowSquads;
            OverlayInspectorHideSquadIconsCheck.Opacity = _overlaySettings.ShowSquads ? 1.0 : 0.52;
        }
    }

    private void SyncOverlayInspectorMemberControls()
    {
        var membersEnabled = _overlaySettings.ShowMembers;
        var roomScene = ResolveCurrentOverlayScene().Context.Kind == OverlaySceneKind.PartyRoom;
        if (OverlayInspectorMemberScopeBox is not null)
        {
            OverlayInspectorMemberScopeBox.SelectedIndex = _overlaySettings.MemberScopeMode switch
            {
                OverlayMemberScopeMode.AllFleet => 1,
                OverlayMemberScopeMode.OtherSquads => 2,
                _ => 0
            };
            SetOverlayInspectorModuleControlEnabled(OverlayInspectorMemberScopeBox, membersEnabled && !roomScene);
            OverlayInspectorMemberScopeBox.ToolTip = roomScene
                ? "房间场景固定显示当前房间成员"
                : null;
        }

        if (OverlayInspectorHideOfflineMembersCheck is not null)
        {
            OverlayInspectorHideOfflineMembersCheck.IsChecked = _overlaySettings.HideOfflineMembers;
            SetOverlayInspectorModuleControlEnabled(OverlayInspectorHideOfflineMembersCheck, membersEnabled);
        }

        if (OverlayInspectorHideMemberOnlineStatusCheck is not null)
        {
            OverlayInspectorHideMemberOnlineStatusCheck.IsChecked = _overlaySettings.EffectiveHideMemberOnlineStatus;
            SetOverlayInspectorModuleControlEnabled(
                OverlayInspectorHideMemberOnlineStatusCheck,
                membersEnabled && _overlaySettings.HideOfflineMembers);
        }

        if (OverlayInspectorHideSelfMemberCheck is not null)
        {
            OverlayInspectorHideSelfMemberCheck.IsChecked = _overlaySettings.HideSelfMember;
            SetOverlayInspectorModuleControlEnabled(OverlayInspectorHideSelfMemberCheck, membersEnabled);
        }

        if (OverlayInspectorMemberPriorityBox is not null)
        {
            OverlayInspectorMemberPriorityBox.SelectedIndex = _overlaySettings.MemberPriorityMode switch
            {
                OverlayMemberPriorityMode.Self => 1,
                OverlayMemberPriorityMode.SquadCommander => 2,
                _ => 0
            };
            SetOverlayInspectorModuleControlEnabled(OverlayInspectorMemberPriorityBox, membersEnabled);
        }

        if (OverlayInspectorMemberNameModeBox is not null)
        {
            OverlayInspectorMemberNameModeBox.SelectedIndex = _overlaySettings.MemberNameMode switch
            {
                OverlayMemberNameMode.CallsignOnly => 1,
                OverlayMemberNameMode.GameNameOnly => 2,
                _ => 0
            };
            SetOverlayInspectorModuleControlEnabled(OverlayInspectorMemberNameModeBox, membersEnabled);
        }

        if (OverlayInspectorMemberColumnRatioText is not null)
        {
            var namePercent = Math.Round(OverlayDisplaySettings.NormalizeMemberNameColumnRatio(_overlaySettings.MemberNameColumnRatio) * 100);
            var locationPercent = 100 - namePercent;
            OverlayInspectorMemberColumnRatioText.Text = _language.Equals("zh", StringComparison.OrdinalIgnoreCase)
                ? $"{namePercent:0}% · 地点 {locationPercent:0}%"
                : $"{namePercent:0}% · Location {locationPercent:0}%";
            OverlayInspectorMemberColumnRatioText.Opacity = membersEnabled ? 1.0 : 0.52;
        }

        if (OverlayInspectorMemberColumnRatioSlider is not null)
        {
            OverlayInspectorMemberColumnRatioSlider.Value =
                OverlayDisplaySettings.NormalizeMemberNameColumnRatio(_overlaySettings.MemberNameColumnRatio) * 100;
            SetOverlayInspectorModuleControlEnabled(OverlayInspectorMemberColumnRatioSlider, membersEnabled);
        }
    }

    private void SyncOverlayInspectorChatControls()
    {
        SyncOverlayFleetChatScopeControls(
            OverlayInspectorFleetChatScopeRow,
            OverlayInspectorFleetChatScopeBox);
        SyncOverlayChatControls(
            OverlayInspectorChatModeBox,
            OverlayInspectorChatSideBox,
            OverlayInspectorChatDurationBox,
            OverlayInspectorChatFontSizeBox,
            OverlayInspectorChatRegionBox,
            OverlayInspectorChatDensityBox,
            OverlayInspectorChatEdgeStrengthBox,
            OverlayInspectorChatAvoidCenterCheck,
            OverlayInspectorChatBarrageSettingsPanel,
            OverlayInspectorChatShowSenderCheck,
            OverlayInspectorChatShowTimestampCheck,
            OverlayInspectorChatShowSystemCheck,
            OverlayInspectorChatHideSelfCheck);
    }

    private void SyncOverlayChatControls(
        System.Windows.Controls.ComboBox? modeBox,
        System.Windows.Controls.ComboBox? sideBox,
        System.Windows.Controls.ComboBox? durationBox,
        System.Windows.Controls.ComboBox? fontSizeBox,
        System.Windows.Controls.ComboBox? regionBox,
        System.Windows.Controls.ComboBox? densityBox,
        System.Windows.Controls.ComboBox? edgeStrengthBox,
        System.Windows.Controls.CheckBox? avoidCenterCheck,
        FrameworkElement? barrageSettingsPanel,
        System.Windows.Controls.CheckBox? showSenderCheck,
        System.Windows.Controls.CheckBox? showTimestampCheck,
        System.Windows.Controls.CheckBox? showSystemCheck,
        System.Windows.Controls.CheckBox? hideSelfCheck)
    {
        var enabled = _overlaySettings.ShowChat;
        var barrageEnabled = enabled &&
                             OverlayDisplaySettings.NormalizeChatDisplayMode(_overlaySettings.ChatDisplayMode) ==
                             OverlayChatDisplayMode.FullScreenBarrage;
        if (barrageSettingsPanel is not null)
        {
            barrageSettingsPanel.Visibility = barrageEnabled ? Visibility.Visible : Visibility.Collapsed;
        }

        if (modeBox is not null)
        {
            SetComboBoxSelectedTag(modeBox, OverlayDisplaySettings.NormalizeChatDisplayMode(_overlaySettings.ChatDisplayMode).ToString());
            SetOverlayInspectorModuleControlEnabled(modeBox, enabled);
        }

        if (sideBox is not null)
        {
            SetComboBoxSelectedTag(sideBox, _overlaySettings.ChatSide.ToString());
            SetOverlayInspectorModuleControlEnabled(sideBox, false);
        }

        if (durationBox is not null)
        {
            SetComboBoxSelectedTag(durationBox, Math.Round(OverlayDisplaySettings.NormalizeChatDuration(_overlaySettings.ChatDurationSeconds)).ToString(CultureInfo.InvariantCulture));
            SetOverlayInspectorModuleControlEnabled(durationBox, barrageEnabled);
        }

        if (fontSizeBox is not null)
        {
            SetComboBoxSelectedTag(fontSizeBox, Math.Round(OverlayDisplaySettings.NormalizeChatBarrageFontSize(_overlaySettings.ChatBarrageFontSize)).ToString(CultureInfo.InvariantCulture));
            SetOverlayInspectorModuleControlEnabled(fontSizeBox, barrageEnabled);
        }

        if (regionBox is not null)
        {
            SetComboBoxSelectedTag(regionBox, OverlayDisplaySettings.NormalizeChatBarrageRegion(_overlaySettings.ChatBarrageRegion).ToString());
            SetOverlayInspectorModuleControlEnabled(regionBox, barrageEnabled);
        }

        if (densityBox is not null)
        {
            SetComboBoxSelectedTag(densityBox, OverlayDisplaySettings.NormalizeChatBarrageDensity(_overlaySettings.ChatBarrageDensity).ToString());
            SetOverlayInspectorModuleControlEnabled(densityBox, barrageEnabled);
        }

        if (edgeStrengthBox is not null)
        {
            SetComboBoxSelectedTag(edgeStrengthBox, OverlayDisplaySettings.NormalizeChatTextEdgeStrength(_overlaySettings.ChatTextEdgeStrength).ToString());
            SetOverlayInspectorModuleControlEnabled(edgeStrengthBox, barrageEnabled);
        }

        foreach (var check in new[] { avoidCenterCheck, showSenderCheck, showTimestampCheck, showSystemCheck, hideSelfCheck })
        {
            if (check is not null)
            {
                SetOverlayInspectorModuleControlEnabled(check, check == avoidCenterCheck ? barrageEnabled : enabled);
            }
        }

        if (avoidCenterCheck is not null) avoidCenterCheck.IsChecked = _overlaySettings.ChatBarrageAvoidCenter;
        if (showSenderCheck is not null) showSenderCheck.IsChecked = _overlaySettings.ChatShowSender;
        if (showTimestampCheck is not null) showTimestampCheck.IsChecked = _overlaySettings.ChatShowTimestamp;
        if (showSystemCheck is not null) showSystemCheck.IsChecked = _overlaySettings.ChatShowSystemMessages;
        if (hideSelfCheck is not null) hideSelfCheck.IsChecked = _overlaySettings.ChatHideSelfMessages;
    }

    private void SyncOverlayFleetChatScopeControls(
        FrameworkElement? scopeRow,
        System.Windows.Controls.ComboBox? scopeBox)
    {
        var fleetScene = ResolveCurrentOverlayScene().Context.Kind == OverlaySceneKind.Fleet;
        if (scopeRow is not null)
        {
            scopeRow.Visibility = fleetScene ? Visibility.Visible : Visibility.Collapsed;
        }

        if (scopeBox is not null)
        {
            SetComboBoxSelectedTag(
                scopeBox,
                OverlayDisplaySettings.NormalizeFleetChatScope(_overlaySettings.FleetChatScope).ToString());
            SetOverlayInspectorModuleControlEnabled(scopeBox, fleetScene && _overlaySettings.ShowChat);
        }
    }

    private static void SetOverlayInspectorModuleControlEnabled(System.Windows.Controls.Control control, bool enabled)
    {
        control.IsEnabled = enabled;
        control.Opacity = enabled ? 1.0 : 0.52;
    }

    private void SyncOverlayInspectorCrosshairControls()
    {
        SyncOverlayCrosshairInspectorControls(
            OverlayInspectorCrosshairModeBox,
            OverlayInspectorCrosshairThemeColorCheck,
            OverlayInspectorCrosshairSizeSlider,
            OverlayInspectorCrosshairSizeValueText,
            OverlayInspectorCrosshairThicknessSlider,
            OverlayInspectorCrosshairThicknessValueText,
            OverlayInspectorCrosshairGapSlider,
            OverlayInspectorCrosshairGapValueText,
            OverlayInspectorCrosshairCenterMarkCheck,
            OverlayInspectorCrosshairCenterSizeSlider,
            OverlayInspectorCrosshairCenterSizeValueText,
            OverlayInspectorCrosshairOpacitySlider,
            OverlayInspectorCrosshairOpacityValueText,
            OverlayInspectorCrosshairOutlineSlider,
            OverlayInspectorCrosshairOutlineValueText,
            OverlayInspectorCrosshairColorBox,
            OverlayInspectorCrosshairColorPreview);
    }

    private void SyncOverlayFullScreenCrosshairControls()
    {
        SyncOverlayCrosshairInspectorControls(
            OverlayFullScreenCrosshairModeBox,
            OverlayFullScreenCrosshairThemeColorCheck,
            OverlayFullScreenCrosshairSizeSlider,
            OverlayFullScreenCrosshairSizeValueText,
            OverlayFullScreenCrosshairThicknessSlider,
            OverlayFullScreenCrosshairThicknessValueText,
            OverlayFullScreenCrosshairGapSlider,
            OverlayFullScreenCrosshairGapValueText,
            OverlayFullScreenCrosshairCenterMarkCheck,
            OverlayFullScreenCrosshairCenterSizeSlider,
            OverlayFullScreenCrosshairCenterSizeValueText,
            OverlayFullScreenCrosshairOpacitySlider,
            OverlayFullScreenCrosshairOpacityValueText,
            OverlayFullScreenCrosshairOutlineSlider,
            OverlayFullScreenCrosshairOutlineValueText,
            OverlayFullScreenCrosshairColorBox,
            OverlayFullScreenCrosshairColorPreview);
    }

    private void SyncOverlayCrosshairInspectorControls(
        System.Windows.Controls.ComboBox? modeBox,
        System.Windows.Controls.CheckBox? themeColorCheck,
        System.Windows.Controls.Slider? sizeSlider,
        TextBlock? sizeValue,
        System.Windows.Controls.Slider? thicknessSlider,
        TextBlock? thicknessValue,
        System.Windows.Controls.Slider? gapSlider,
        TextBlock? gapValue,
        System.Windows.Controls.CheckBox? centerMarkCheck,
        System.Windows.Controls.Slider? centerSizeSlider,
        TextBlock? centerSizeValue,
        System.Windows.Controls.Slider? opacitySlider,
        TextBlock? opacityValue,
        System.Windows.Controls.Slider? outlineSlider,
        TextBlock? outlineValue,
        System.Windows.Controls.TextBox? colorBox,
        Border? colorPreview)
    {
        var previousSyncing = _isSyncingOverlayInspectorCrosshairControls;
        _isSyncingOverlayInspectorCrosshairControls = true;
        try
        {
            var enabled = _overlaySettings.ShowCrosshair;
            var centerMarkEnabled = enabled && _overlaySettings.CrosshairShowCenterMark;
            var useThemeColor = _overlaySettings.CrosshairUseThemeColor;
            if (modeBox is not null)
            {
                SetComboBoxSelectedTag(
                    modeBox,
                    OverlayDisplaySettings.NormalizeCrosshairMode(_overlaySettings.CrosshairMode).ToString());
                SetOverlayInspectorModuleControlEnabled(modeBox, enabled);
            }

            if (themeColorCheck is not null)
            {
                themeColorCheck.IsChecked = useThemeColor;
                SetOverlayInspectorModuleControlEnabled(themeColorCheck, enabled);
            }

            if (sizeSlider is not null)
            {
                sizeSlider.Value = OverlayDisplaySettings.NormalizeCrosshairSize(_overlaySettings.CrosshairSize);
                SetOverlayInspectorModuleControlEnabled(sizeSlider, enabled);
            }

            if (thicknessSlider is not null)
            {
                thicknessSlider.Value = Math.Clamp(_overlaySettings.CrosshairThickness, 1, 8);
                SetOverlayInspectorModuleControlEnabled(thicknessSlider, enabled);
            }

            if (gapSlider is not null)
            {
                gapSlider.Value = OverlayDisplaySettings.NormalizeCrosshairGap(_overlaySettings.CrosshairGap);
                SetOverlayInspectorModuleControlEnabled(gapSlider, enabled);
            }

            if (centerMarkCheck is not null)
            {
                centerMarkCheck.IsChecked = _overlaySettings.CrosshairShowCenterMark;
                SetOverlayInspectorModuleControlEnabled(centerMarkCheck, enabled);
            }

            if (centerSizeSlider is not null)
            {
                centerSizeSlider.Value = OverlayDisplaySettings.NormalizeCrosshairCenterMarkSize(_overlaySettings.CrosshairCenterMarkSize);
                SetOverlayInspectorModuleControlEnabled(centerSizeSlider, centerMarkEnabled);
            }

            if (opacitySlider is not null)
            {
                opacitySlider.Value = Math.Clamp(_overlaySettings.CrosshairOpacity, 0.2, 1.0) * 100.0;
                SetOverlayInspectorModuleControlEnabled(opacitySlider, enabled);
            }

            if (outlineSlider is not null)
            {
                outlineSlider.Value = OverlayDisplaySettings.NormalizeCrosshairOutlineOpacity(_overlaySettings.CrosshairOutlineOpacity) * 100.0;
                SetOverlayInspectorModuleControlEnabled(outlineSlider, enabled);
            }

            if (colorBox is not null)
            {
                if (!colorBox.IsKeyboardFocusWithin)
                {
                    colorBox.Text = OverlayDisplaySettings.NormalizeCrosshairColor(_overlaySettings.CrosshairColor);
                }

                colorBox.IsEnabled = enabled && !useThemeColor;
                colorBox.Opacity = colorBox.IsEnabled ? 1.0 : 0.52;
            }

            if (colorPreview is not null)
            {
                colorPreview.Background = GetCrosshairPreviewBrush(GetEffectiveOverlaySettings());
                colorPreview.Opacity = enabled ? 1.0 : 0.52;
            }

            UpdateOverlayCrosshairInspectorValueTexts(
                sizeSlider,
                sizeValue,
                thicknessSlider,
                thicknessValue,
                gapSlider,
                gapValue,
                centerMarkCheck,
                centerSizeSlider,
                centerSizeValue,
                opacitySlider,
                opacityValue,
                outlineSlider,
                outlineValue);
            RefreshOverlayInspectorCrosshairModeAvailability(
                OverlayDisplaySettings.NormalizeCrosshairMode(_overlaySettings.CrosshairMode),
                enabled);
        }
        finally
        {
            _isSyncingOverlayInspectorCrosshairControls = previousSyncing;
        }
    }

    private void UpdateOverlayCrosshairInspectorValueTexts(
        System.Windows.Controls.Slider? sizeSlider,
        TextBlock? sizeValue,
        System.Windows.Controls.Slider? thicknessSlider,
        TextBlock? thicknessValue,
        System.Windows.Controls.Slider? gapSlider,
        TextBlock? gapValue,
        System.Windows.Controls.CheckBox? centerMarkCheck,
        System.Windows.Controls.Slider? centerSizeSlider,
        TextBlock? centerSizeValue,
        System.Windows.Controls.Slider? opacitySlider,
        TextBlock? opacityValue,
        System.Windows.Controls.Slider? outlineSlider,
        TextBlock? outlineValue)
    {
        if (sizeSlider is not null && sizeValue is not null)
        {
            sizeValue.Text = $"{Math.Round(sizeSlider.Value)}px";
        }

        if (thicknessSlider is not null && thicknessValue is not null)
        {
            thicknessValue.Text = $"{thicknessSlider.Value:0.##}px";
        }

        if (gapSlider is not null && gapValue is not null)
        {
            gapValue.Text = $"{Math.Round(gapSlider.Value)}px";
        }

        if (centerMarkCheck is not null && centerSizeSlider is not null && centerSizeValue is not null)
        {
            centerSizeValue.Text = centerMarkCheck.IsChecked == true
                ? $"{Math.Round(centerSizeSlider.Value)}px"
                : _language.Equals("zh", StringComparison.OrdinalIgnoreCase) ? "关闭" : "Off";
        }

        if (opacitySlider is not null && opacityValue is not null)
        {
            opacityValue.Text = $"{Math.Round(opacitySlider.Value)}%";
        }

        if (outlineSlider is not null && outlineValue is not null)
        {
            outlineValue.Text = $"{Math.Round(outlineSlider.Value)}%";
        }
    }

    private void RefreshOverlayInspectorCrosshairModeAvailability(OverlayCrosshairMode mode, bool enabled)
    {
        mode = OverlayDisplaySettings.NormalizeCrosshairMode(mode);
        var isDot = mode == OverlayCrosshairMode.Dot;
        var usesGap = mode is OverlayCrosshairMode.Cross or OverlayCrosshairMode.TShape;
        var centerSizeEnabled = enabled && (isDot || _overlaySettings.CrosshairShowCenterMark);

        SetCrosshairControlState(OverlayInspectorCrosshairModeBox, enabled);
        SetCrosshairControlState(OverlayInspectorCrosshairSizeSlider, enabled && !isDot);
        SetCrosshairControlState(OverlayInspectorCrosshairThicknessSlider, enabled && !isDot);
        SetCrosshairControlState(OverlayInspectorCrosshairGapSlider, enabled && usesGap);
        SetCrosshairControlState(OverlayInspectorCrosshairCenterMarkCheck, enabled && !isDot);
        SetCrosshairControlState(OverlayInspectorCrosshairCenterSizeSlider, centerSizeEnabled);

        SetCrosshairControlState(OverlayFullScreenCrosshairModeBox, enabled);
        SetCrosshairControlState(OverlayFullScreenCrosshairSizeSlider, enabled && !isDot);
        SetCrosshairControlState(OverlayFullScreenCrosshairThicknessSlider, enabled && !isDot);
        SetCrosshairControlState(OverlayFullScreenCrosshairGapSlider, enabled && usesGap);
        SetCrosshairControlState(OverlayFullScreenCrosshairCenterMarkCheck, enabled && !isDot);
        SetCrosshairControlState(OverlayFullScreenCrosshairCenterSizeSlider, centerSizeEnabled);

        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var sizeLabel = mode == OverlayCrosshairMode.Circle
            ? zh ? "圆环直径" : "RING DIAMETER"
            : zh ? "整体大小" : "OVERALL SIZE";
        var centerSizeLabel = isDot
            ? zh ? "点大小" : "DOT SIZE"
            : zh ? "中心点大小" : "CENTER DOT SIZE";
        OverlayInspectorCrosshairSizeLabel.Text = sizeLabel;
        OverlayFullScreenCrosshairSizeLabel.Text = sizeLabel;
        OverlayInspectorCrosshairCenterMarkCheck.Content = zh ? "显示中心点" : "Show center dot";
        OverlayFullScreenCrosshairCenterMarkCheck.Content = zh ? "显示中心点" : "Show center dot";
        OverlayInspectorCrosshairCenterSizeLabel.Text = centerSizeLabel;
        OverlayFullScreenCrosshairCenterSizeLabel.Text = centerSizeLabel;
    }

    private void SyncOverlayModuleStyleControls(OverlayLayoutItem? item)
    {
        _isSyncingOverlayModuleStyleControls = true;
        try
        {
            var hasItem = item is not null;
            var eventNotificationSelected = _isOverlayEventNotificationSelected && _overlaySettings.ShowEventNotifications;
            var hasAppearance = hasItem || eventNotificationSelected;
            var textPercent = eventNotificationSelected
                ? Math.Round(OverlayLayoutItem.NormalizeTextOpacity(_overlaySettings.EventNotificationTextOpacity) * 100.0)
                : hasItem
                    ? Math.Round(OverlayLayoutItem.NormalizeTextOpacity(item!.TextOpacity) * 100.0)
                    : 100.0;
            var backgroundPercent = eventNotificationSelected
                ? Math.Round(OverlayLayoutItem.NormalizeBackgroundOpacity(_overlaySettings.EventNotificationBackgroundOpacity) * 100.0)
                : hasItem
                    ? Math.Round(OverlayLayoutItem.NormalizeBackgroundOpacity(item!.BackgroundOpacity) * 100.0)
                    : 100.0;

            if (OverlayInspectorModuleAppearancePanel is not null)
            {
                OverlayInspectorModuleAppearancePanel.Visibility = hasAppearance ? Visibility.Visible : Visibility.Collapsed;
            }

            if (OverlayFullScreenModuleAppearancePanel is not null)
            {
                OverlayFullScreenModuleAppearancePanel.Visibility = hasAppearance ? Visibility.Visible : Visibility.Collapsed;
            }

            SyncOverlayModuleStyleControlSet(
                OverlayInspectorModuleLockCheck,
                OverlayInspectorTextOpacitySlider,
                OverlayInspectorTextOpacityValueText,
                OverlayInspectorBackgroundOpacitySlider,
                OverlayInspectorBackgroundOpacityValueText);
            SyncOverlayModuleStyleControlSet(
                OverlayFullScreenModuleLockCheck,
                OverlayFullScreenTextOpacitySlider,
                OverlayFullScreenTextOpacityValueText,
                OverlayFullScreenBackgroundOpacitySlider,
                OverlayFullScreenBackgroundOpacityValueText);

            void SyncOverlayModuleStyleControlSet(
                System.Windows.Controls.CheckBox? lockCheck,
                System.Windows.Controls.Slider? textSlider,
                TextBlock? textValue,
                System.Windows.Controls.Slider? backgroundSlider,
                TextBlock? backgroundValue)
            {
                if (lockCheck is not null)
                {
                    lockCheck.IsChecked = item?.IsLocked == true;
                    lockCheck.IsEnabled = hasItem;
                    lockCheck.Opacity = hasItem ? 1.0 : 0.52;
                    lockCheck.Visibility = hasItem ? Visibility.Visible : Visibility.Collapsed;
                }

                if (textSlider is not null)
                {
                    textSlider.IsEnabled = hasAppearance;
                    textSlider.Opacity = hasAppearance ? 1.0 : 0.52;
                    textSlider.Value = textPercent;
                }

                if (textValue is not null)
                {
                    textValue.Text = $"{textPercent:0}%";
                    textValue.Opacity = hasAppearance ? 1.0 : 0.52;
                }

                if (backgroundSlider is not null)
                {
                    backgroundSlider.IsEnabled = hasAppearance;
                    backgroundSlider.Opacity = hasAppearance ? 1.0 : 0.52;
                    backgroundSlider.Value = backgroundPercent;
                }

                if (backgroundValue is not null)
                {
                    backgroundValue.Text = $"{backgroundPercent:0}%";
                    backgroundValue.Opacity = hasAppearance ? 1.0 : 0.52;
                }
            }
        }
        finally
        {
            _isSyncingOverlayModuleStyleControls = false;
        }
    }

    private void OverlayInspectorModuleStyleSetting_Changed(object sender, RoutedEventArgs e)
    {
        ApplyOverlayModuleStyleControlChanges(useFullScreenControls: false);
    }

    private void OverlayFullScreenModuleStyleSetting_Changed(object sender, RoutedEventArgs e)
    {
        ApplyOverlayModuleStyleControlChanges(useFullScreenControls: true);
    }

    private void OverlayInspectorModuleOpacitySlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        ApplyOverlayModuleStyleControlChanges(useFullScreenControls: false);
    }

    private void OverlayFullScreenModuleOpacitySlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        ApplyOverlayModuleStyleControlChanges(useFullScreenControls: true);
    }

    private void ApplyOverlayModuleStyleControlChanges(bool useFullScreenControls)
    {
        if (_isLoadingSettings || _isSyncingOverlayModuleStyleControls)
        {
            return;
        }

        var eventNotificationSelected = _isOverlayEventNotificationSelected && _overlaySettings.ShowEventNotifications;
        OverlayLayoutItem? item = null;
        if (!eventNotificationSelected && !TryGetSelectedOverlayInspectorItem(out item))
        {
            return;
        }

        var lockCheck = useFullScreenControls ? OverlayFullScreenModuleLockCheck : OverlayInspectorModuleLockCheck;
        var textSlider = useFullScreenControls ? OverlayFullScreenTextOpacitySlider : OverlayInspectorTextOpacitySlider;
        var backgroundSlider = useFullScreenControls ? OverlayFullScreenBackgroundOpacitySlider : OverlayInspectorBackgroundOpacitySlider;
        var historyState = CreateOverlayEditorHistoryState();

        if (eventNotificationSelected)
        {
            _overlaySettings = _overlaySettings with
            {
                EventNotificationTextOpacity = OverlayLayoutItem.NormalizeTextOpacity((textSlider?.Value ?? 100) / 100.0),
                EventNotificationBackgroundOpacity = OverlayLayoutItem.NormalizeBackgroundOpacity((backgroundSlider?.Value ?? 100) / 100.0)
            };
        }
        else if (lockCheck is not null && item is not null)
        {
            item.IsLocked = lockCheck.IsChecked == true;
        }

        if (!eventNotificationSelected && textSlider is not null && item is not null)
        {
            item.TextOpacity = OverlayLayoutItem.NormalizeTextOpacity(textSlider.Value / 100.0);
        }

        if (!eventNotificationSelected && backgroundSlider is not null && item is not null)
        {
            item.BackgroundOpacity = OverlayLayoutItem.NormalizeBackgroundOpacity(backgroundSlider.Value / 100.0);
        }

        if (historyState.Equals(CreateOverlayEditorHistoryState()))
        {
            SyncOverlayModuleStyleControls(item);
            return;
        }

        PushOverlayEditorUndoState(historyState);
        MarkOverlayEditorLayoutDirty();
        RenderOverlayEditor();
        SaveCurrentConfig();
        RefreshOverlayWindow();
    }

    private Border CreateOverlayLayerRow(OverlayEditorLayerRow row)
    {
        var accent = row.Brush;
        var border = new Border
        {
            Tag = row.Key,
            BorderBrush = row.IsSelected ? Brushes.WhiteSmoke : new SolidColorBrush(Color.FromArgb(120, 79, 159, 194)),
            BorderThickness = new Thickness(row.IsSelected ? 2 : 1),
            Background = new SolidColorBrush(row.IsSelected ? Color.FromArgb(156, 8, 34, 50) : Color.FromArgb(92, 5, 18, 28)),
            Padding = new Thickness(8),
            Margin = new Thickness(0, 0, 0, 8),
            Cursor = Cursors.Hand
        };
        border.MouseLeftButtonDown += OverlayLayerRow_MouseLeftButtonDown;

        var stack = new StackPanel();
        var header = new Grid();
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        header.Children.Add(new Border
        {
            Width = 8,
            Height = 8,
            Background = accent,
            BorderBrush = Brushes.WhiteSmoke,
            BorderThickness = new Thickness(row.IsSelected ? 1 : 0),
            Margin = new Thickness(0, 4, 8, 0)
        });
        var title = new TextBlock
        {
            Text = row.Title,
            Foreground = row.IsSelected ? Brushes.WhiteSmoke : FindBrush("PrimaryTextBrush", Brushes.AliceBlue),
            FontSize = 12,
            FontWeight = FontWeights.SemiBold,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        Grid.SetColumn(title, 1);
        header.Children.Add(title);
        var status = new TextBlock
        {
            Text = row.IsEventRail
                ? (_language.Equals("zh", StringComparison.OrdinalIgnoreCase) ? "置顶" : "Top")
                : row.IsLocked
                    ? (_language.Equals("zh", StringComparison.OrdinalIgnoreCase) ? "锁定" : "Locked")
                    : "",
            Foreground = row.IsEventRail ? FindBrush("StatusWarningBrush", Brushes.Gold) : FindBrush("MutedTextBrush", Brushes.LightSlateGray),
            FontSize = 10,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(8, 0, 0, 0)
        };
        Grid.SetColumn(status, 2);
        header.Children.Add(status);
        stack.Children.Add(header);

        var actions = new System.Windows.Controls.Primitives.UniformGrid
        {
            Columns = 5,
            Margin = new Thickness(0, 8, 0, 0)
        };
        var canMove = !row.IsEventRail && !row.IsLocked && !_isOverlayLayoutLocked;
        var canLock = !row.IsEventRail;
        actions.Children.Add(CreateOverlayLayerActionButton(row.Key, "Top", _language == "zh" ? "顶" : "Top", canMove && row.LayoutIndex < _overlayLayout.Count - 1));
        actions.Children.Add(CreateOverlayLayerActionButton(row.Key, "Up", _language == "zh" ? "上" : "Up", canMove && row.LayoutIndex < _overlayLayout.Count - 1));
        actions.Children.Add(CreateOverlayLayerActionButton(row.Key, "Down", _language == "zh" ? "下" : "Down", canMove && row.LayoutIndex > 0));
        actions.Children.Add(CreateOverlayLayerActionButton(row.Key, "Bottom", _language == "zh" ? "底" : "Bot", canMove && row.LayoutIndex > 0));
        actions.Children.Add(CreateOverlayLayerActionButton(
            row.Key,
            "Lock",
            row.IsLocked
                ? (_language == "zh" ? "解" : "Unlock")
                : (_language == "zh" ? "锁" : "Lock"),
            canLock));
        stack.Children.Add(actions);

        border.Child = stack;
        return border;
    }

    private System.Windows.Controls.Button CreateOverlayLayerActionButton(string key, string action, string label, bool enabled)
    {
        var button = new System.Windows.Controls.Button
        {
            Content = label,
            Tag = $"{key}|{action}",
            Height = 26,
            Margin = new Thickness(2, 0, 2, 0),
            Padding = new Thickness(0),
            FontSize = 10,
            IsEnabled = enabled,
            Opacity = enabled ? 1.0 : 0.42,
            Style = TryFindResource("SecondaryButton") as Style
        };
        button.Click += OverlayLayerAction_Click;
        return button;
    }

    private void OverlayLayerRow_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: string key })
        {
            return;
        }

        SelectOverlayLayerEntry(key);
        e.Handled = true;
    }

    private void OverlayLayerAction_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.Button { Tag: string tag })
        {
            return;
        }

        var parts = tag.Split('|', 2);
        if (parts.Length != 2)
        {
            return;
        }

        var key = parts[0];
        var action = parts[1];
        if (action.Equals("Lock", StringComparison.OrdinalIgnoreCase))
        {
            ToggleOverlayLayerLock(key);
        }
        else
        {
            MoveOverlayLayer(key, action);
        }

        e.Handled = true;
    }

    private void SelectOverlayLayerEntry(string key)
    {
        if (key.Equals("EventNotifications", StringComparison.OrdinalIgnoreCase))
        {
            _selectedOverlayInspectorItem = null;
            _isOverlayEventNotificationSelected = _overlaySettings.ShowEventNotifications;
            _isOverlayCrosshairSelected = false;
        }
        else if (key.Equals("Crosshair", StringComparison.OrdinalIgnoreCase))
        {
            _selectedOverlayInspectorItem = null;
            _isOverlayEventNotificationSelected = false;
            _isOverlayCrosshairSelected = _overlaySettings.ShowCrosshair;
        }
        else
        {
            var item = _overlayLayout.FirstOrDefault(candidate =>
                candidate.Key.Equals(key, StringComparison.OrdinalIgnoreCase) &&
                IsOverlayEditorItemVisible(candidate));
            if (item is null)
            {
                return;
            }

            _isOverlayEventNotificationSelected = false;
            _isOverlayCrosshairSelected = false;
            _selectedOverlayInspectorItem = item;
        }

        RenderOverlayEditor();
    }

    private void ToggleOverlayLayerLock(string key)
    {
        var item = _overlayLayout.FirstOrDefault(candidate =>
            candidate.Key.Equals(key, StringComparison.OrdinalIgnoreCase));
        if (item is null)
        {
            return;
        }

        var historyState = CreateOverlayEditorHistoryState();
        item.IsLocked = !item.IsLocked;
        if (historyState.Equals(CreateOverlayEditorHistoryState()))
        {
            return;
        }

        PushOverlayEditorUndoState(historyState);
        MarkOverlayEditorLayoutDirty();
        RenderOverlayEditor();
        SaveCurrentConfig();
        RefreshOverlayWindow();
    }

    private void MoveOverlayLayer(string key, string action)
    {
        var item = _overlayLayout.FirstOrDefault(candidate =>
            candidate.Key.Equals(key, StringComparison.OrdinalIgnoreCase));
        if (item is null ||
            item.IsLocked ||
            _isOverlayLayoutLocked)
        {
            return;
        }

        var oldIndex = _overlayLayout.IndexOf(item);
        var newIndex = action switch
        {
            "Top" => _overlayLayout.Count - 1,
            "Up" => Math.Min(_overlayLayout.Count - 1, oldIndex + 1),
            "Down" => Math.Max(0, oldIndex - 1),
            "Bottom" => 0,
            _ => oldIndex
        };
        if (newIndex == oldIndex)
        {
            return;
        }

        var historyState = CreateOverlayEditorHistoryState();
        _overlayLayout.RemoveAt(oldIndex);
        _overlayLayout.Insert(newIndex, item);
        PushOverlayEditorUndoState(historyState);
        MarkOverlayEditorLayoutDirty();
        RenderOverlayEditor();
        SaveCurrentConfig();
        RefreshOverlayWindow();
    }

    private sealed record OverlayEditorLayerRow(
        string Key,
        string Title,
        System.Windows.Media.Brush Brush,
        bool IsEventRail,
        bool IsSelected,
        bool IsLocked,
        int LayoutIndex);

    private static int GetComboBoxItemIndexByTag(System.Windows.Controls.ComboBox comboBox, string tag)
    {
        for (var index = 0; index < comboBox.Items.Count; index++)
        {
            if (comboBox.Items[index] is ComboBoxItem item &&
                string.Equals(item.Tag?.ToString(), tag, StringComparison.OrdinalIgnoreCase))
            {
                return index;
            }
        }

        return -1;
    }

    private static void SetComboBoxSelectedTag(System.Windows.Controls.ComboBox comboBox, string tag)
    {
        var index = GetComboBoxItemIndexByTag(comboBox, tag);
        if (index >= 0)
        {
            comboBox.SelectedIndex = index;
        }
    }

    private void OverlayInspectorAnchorBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isSyncingOverlayInspectorAnchorControls ||
            !TryGetSelectedOverlayInspectorItem(out var item) ||
            item.IsLocked ||
            _isOverlayLayoutLocked ||
            OverlayEditorCanvas is null)
        {
            return;
        }

        var currentRect = ResolveOverlayEditorItemDisplayRect(item);
        var historyState = CreateOverlayEditorHistoryState();
        var changed = false;
        var horizontalBox = sender == OverlayInspectorHorizontalAnchorBox
            ? OverlayInspectorHorizontalAnchorBox
            : sender == OverlayFullScreenHorizontalAnchorBox
                ? OverlayFullScreenHorizontalAnchorBox
                : null;
        var verticalBox = sender == OverlayInspectorVerticalAnchorBox
            ? OverlayInspectorVerticalAnchorBox
            : sender == OverlayFullScreenVerticalAnchorBox
                ? OverlayFullScreenVerticalAnchorBox
                : null;

        if (horizontalBox?.SelectedItem is ComboBoxItem horizontalItem &&
            Enum.TryParse<OverlayHorizontalAnchor>(horizontalItem.Tag?.ToString(), out var horizontalAnchor) &&
            item.HorizontalAnchor != horizontalAnchor)
        {
            item.HorizontalAnchor = horizontalAnchor;
            changed = true;
        }
        else if (verticalBox?.SelectedItem is ComboBoxItem verticalItem &&
                 Enum.TryParse<OverlayVerticalAnchor>(verticalItem.Tag?.ToString(), out var verticalAnchor) &&
                 item.VerticalAnchor != verticalAnchor)
        {
            if (IsCommunicationEventModule(item) && verticalAnchor == OverlayVerticalAnchor.Middle)
            {
                RefreshOverlayInspector();
                return;
            }

            item.VerticalAnchor = verticalAnchor;
            if (IsCommunicationEventModule(item))
            {
                currentRect = new Rect(
                    currentRect.Left,
                    verticalAnchor == OverlayVerticalAnchor.Bottom
                        ? Math.Max(0, OverlayEditorCanvas.Height - currentRect.Height)
                        : 0,
                    currentRect.Width,
                    currentRect.Height);
            }
            changed = true;
        }

        if (!changed)
        {
            return;
        }

        OverlaySurfaceLayout.ApplyRectToItem(item, currentRect, OverlayEditorCanvas.Width, OverlayEditorCanvas.Height);
        if (!historyState.Equals(CreateOverlayEditorHistoryState()))
        {
            PushOverlayEditorUndoState(historyState);
            MarkOverlayEditorLayoutDirty();
        }

        RenderOverlayEditor();
        SaveCurrentConfig();
        RefreshOverlayWindow();
    }

    private void OverlayInspectorModuleSetting_Changed(object sender, RoutedEventArgs e)
    {
        if (_isLoadingSettings || _isSyncingOverlayInspectorModuleControls)
        {
            return;
        }

        ApplyOverlayInspectorModuleControlChanges(sender, e);
    }

    private void OverlayInspectorModuleSelection_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_isLoadingSettings || _isSyncingOverlayInspectorModuleControls)
        {
            return;
        }

        ApplyOverlayInspectorModuleControlChanges(sender, e);
    }

    private void OverlayFullScreenModuleSetting_Changed(object sender, RoutedEventArgs e)
    {
        if (_isLoadingSettings || _isSyncingOverlayInspectorModuleControls)
        {
            return;
        }

        ApplyOverlayFullScreenModuleControlChanges(sender, e);
    }

    private void OverlayFullScreenModuleSelection_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_isLoadingSettings || _isSyncingOverlayInspectorModuleControls)
        {
            return;
        }

        ApplyOverlayFullScreenModuleControlChanges(sender, e);
    }

    private void OverlayCommunicationDockBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isLoadingSettings ||
            _isSyncingOverlayInspectorModuleControls ||
            sender is not System.Windows.Controls.ComboBox { SelectedItem: ComboBoxItem selectedItem } ||
            !Enum.TryParse<OverlayVerticalAnchor>(selectedItem.Tag?.ToString(), out var verticalAnchor) ||
            verticalAnchor == OverlayVerticalAnchor.Middle ||
            !TryGetSelectedOverlayInspectorItem(out var item) ||
            !IsCommunicationEventModule(item) ||
            item.IsLocked ||
            _isOverlayLayoutLocked ||
            OverlayEditorCanvas is null)
        {
            return;
        }

        var currentRect = ResolveOverlayEditorItemDisplayRect(item);
        var nextRect = new Rect(
            currentRect.Left,
            verticalAnchor == OverlayVerticalAnchor.Bottom
                ? Math.Max(0, OverlayEditorCanvas.Height - currentRect.Height)
                : 0,
            currentRect.Width,
            currentRect.Height);
        if (item.VerticalAnchor == verticalAnchor && Math.Abs(currentRect.Top - nextRect.Top) < 0.5)
        {
            return;
        }

        var historyState = CreateOverlayEditorHistoryState();
        item.VerticalAnchor = verticalAnchor;
        OverlaySurfaceLayout.ApplyRectToItem(item, nextRect, OverlayEditorCanvas.Width, OverlayEditorCanvas.Height);
        if (!historyState.Equals(CreateOverlayEditorHistoryState()))
        {
            PushOverlayEditorUndoState(historyState);
            MarkOverlayEditorLayoutDirty();
        }

        RenderOverlayEditor();
        SaveCurrentConfig();
        RefreshOverlayWindow();
    }

    private void OverlayInspectorCommunicationDurationSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (OverlayInspectorCommunicationDurationValueText is not null)
        {
            OverlayInspectorCommunicationDurationValueText.Text = $"{e.NewValue:0.#}s";
        }

        if (_isLoadingSettings || _isSyncingOverlayInspectorModuleControls)
        {
            return;
        }

        ApplyOverlayInspectorModuleControlChanges(sender, new RoutedEventArgs());
    }

    private void OverlayInspectorMemberColumnRatioSlider_ValueChanged(
        object sender,
        RoutedPropertyChangedEventArgs<double> e)
    {
        var namePercent = Math.Round(Math.Clamp(e.NewValue, 18, 82));
        if (OverlayInspectorMemberColumnRatioText is not null)
        {
            OverlayInspectorMemberColumnRatioText.Text = _language.Equals("zh", StringComparison.OrdinalIgnoreCase)
                ? $"{namePercent:0}% · 地点 {100 - namePercent:0}%"
                : $"{namePercent:0}% · Location {100 - namePercent:0}%";
        }

        if (_isLoadingSettings || _isSyncingOverlayInspectorModuleControls)
        {
            return;
        }

        ApplyOverlayInspectorModuleControlChanges(sender, new RoutedEventArgs());
    }

    private void OverlayFullScreenCommunicationDurationSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (OverlayFullScreenCommunicationDurationValueText is not null)
        {
            OverlayFullScreenCommunicationDurationValueText.Text = $"{e.NewValue:0.#}s";
        }

        if (_isLoadingSettings || _isSyncingOverlayInspectorModuleControls)
        {
            return;
        }

        ApplyOverlayFullScreenModuleControlChanges(sender, new RoutedEventArgs());
    }

    private void OverlayFullScreenEventDurationBox_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key != Key.Enter)
        {
            return;
        }

        ApplyOverlayFullScreenModuleControlChanges(sender, new RoutedEventArgs());
        e.Handled = true;
    }

    private void OverlayFullScreenEventDurationBox_LostFocus(object sender, RoutedEventArgs e)
    {
        ApplyOverlayFullScreenModuleControlChanges(sender, e);
    }

    private void OverlayInspectorCrosshairSetting_Changed(object sender, RoutedEventArgs e)
    {
        ApplyOverlayInspectorCrosshairControlChanges(useFullScreenControls: false, sender, e);
    }

    private void OverlayInspectorCrosshairSelection_Changed(object sender, SelectionChangedEventArgs e)
    {
        ApplyOverlayInspectorCrosshairControlChanges(useFullScreenControls: false, sender, e);
    }

    private void OverlayInspectorCrosshairSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        UpdateOverlayCrosshairInspectorValueTexts(
            OverlayInspectorCrosshairSizeSlider,
            OverlayInspectorCrosshairSizeValueText,
            OverlayInspectorCrosshairThicknessSlider,
            OverlayInspectorCrosshairThicknessValueText,
            OverlayInspectorCrosshairGapSlider,
            OverlayInspectorCrosshairGapValueText,
            OverlayInspectorCrosshairCenterMarkCheck,
            OverlayInspectorCrosshairCenterSizeSlider,
            OverlayInspectorCrosshairCenterSizeValueText,
            OverlayInspectorCrosshairOpacitySlider,
            OverlayInspectorCrosshairOpacityValueText,
            OverlayInspectorCrosshairOutlineSlider,
            OverlayInspectorCrosshairOutlineValueText);
        ApplyOverlayInspectorCrosshairControlChanges(useFullScreenControls: false, sender, new RoutedEventArgs());
    }

    private void OverlayInspectorCrosshairColorBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        ApplyOverlayInspectorCrosshairControlChanges(useFullScreenControls: false, sender, new RoutedEventArgs());
    }

    private void OverlayFullScreenCrosshairSetting_Changed(object sender, RoutedEventArgs e)
    {
        ApplyOverlayInspectorCrosshairControlChanges(useFullScreenControls: true, sender, e);
    }

    private void OverlayFullScreenCrosshairSelection_Changed(object sender, SelectionChangedEventArgs e)
    {
        ApplyOverlayInspectorCrosshairControlChanges(useFullScreenControls: true, sender, e);
    }

    private void OverlayFullScreenCrosshairSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        UpdateOverlayCrosshairInspectorValueTexts(
            OverlayFullScreenCrosshairSizeSlider,
            OverlayFullScreenCrosshairSizeValueText,
            OverlayFullScreenCrosshairThicknessSlider,
            OverlayFullScreenCrosshairThicknessValueText,
            OverlayFullScreenCrosshairGapSlider,
            OverlayFullScreenCrosshairGapValueText,
            OverlayFullScreenCrosshairCenterMarkCheck,
            OverlayFullScreenCrosshairCenterSizeSlider,
            OverlayFullScreenCrosshairCenterSizeValueText,
            OverlayFullScreenCrosshairOpacitySlider,
            OverlayFullScreenCrosshairOpacityValueText,
            OverlayFullScreenCrosshairOutlineSlider,
            OverlayFullScreenCrosshairOutlineValueText);
        ApplyOverlayInspectorCrosshairControlChanges(useFullScreenControls: true, sender, new RoutedEventArgs());
    }

    private void OverlayFullScreenCrosshairColorBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        ApplyOverlayInspectorCrosshairControlChanges(useFullScreenControls: true, sender, new RoutedEventArgs());
    }

    private void ApplyOverlayInspectorCrosshairControlChanges(bool useFullScreenControls, object sender, RoutedEventArgs e)
    {
        if (_isLoadingSettings ||
            _isSyncingOverlayInspectorCrosshairControls ||
            !_isOverlayCrosshairSelected ||
            !(_overlaySettings.ShowCrosshair || ShowCrosshairCheck?.IsChecked == true))
        {
            return;
        }

        var modeBox = useFullScreenControls ? OverlayFullScreenCrosshairModeBox : OverlayInspectorCrosshairModeBox;
        var themeColorCheck = useFullScreenControls ? OverlayFullScreenCrosshairThemeColorCheck : OverlayInspectorCrosshairThemeColorCheck;
        var sizeSlider = useFullScreenControls ? OverlayFullScreenCrosshairSizeSlider : OverlayInspectorCrosshairSizeSlider;
        var thicknessSlider = useFullScreenControls ? OverlayFullScreenCrosshairThicknessSlider : OverlayInspectorCrosshairThicknessSlider;
        var gapSlider = useFullScreenControls ? OverlayFullScreenCrosshairGapSlider : OverlayInspectorCrosshairGapSlider;
        var centerMarkCheck = useFullScreenControls ? OverlayFullScreenCrosshairCenterMarkCheck : OverlayInspectorCrosshairCenterMarkCheck;
        var centerSizeSlider = useFullScreenControls ? OverlayFullScreenCrosshairCenterSizeSlider : OverlayInspectorCrosshairCenterSizeSlider;
        var opacitySlider = useFullScreenControls ? OverlayFullScreenCrosshairOpacitySlider : OverlayInspectorCrosshairOpacitySlider;
        var outlineSlider = useFullScreenControls ? OverlayFullScreenCrosshairOutlineSlider : OverlayInspectorCrosshairOutlineSlider;
        var colorBox = useFullScreenControls ? OverlayFullScreenCrosshairColorBox : OverlayInspectorCrosshairColorBox;
        if (ShowCrosshairCheck is null ||
            CrosshairModeBox is null ||
            CrosshairThemeColorCheck is null ||
            CrosshairSizeSlider is null ||
            CrosshairThicknessSlider is null ||
            CrosshairGapSlider is null ||
            CrosshairCenterMarkCheck is null ||
            CrosshairCenterSizeSlider is null ||
            CrosshairOpacitySlider is null ||
            CrosshairOutlineOpacitySlider is null ||
            CrosshairColorBox is null)
        {
            return;
        }

        var historyState = CreateOverlayEditorHistoryState();
        var wasLoadingSettings = _isLoadingSettings;
        _isLoadingSettings = true;
        try
        {
            ShowCrosshairCheck.IsChecked = true;
            SetComboBoxSelectedTag(
                CrosshairModeBox,
                GetOverlayCrosshairModeFromComboBox(modeBox).ToString());

            if (themeColorCheck is not null)
            {
                CrosshairThemeColorCheck.IsChecked = themeColorCheck.IsChecked == true;
            }

            if (sizeSlider is not null)
            {
                CrosshairSizeSlider.Value = OverlayDisplaySettings.NormalizeCrosshairSize(sizeSlider.Value);
            }

            if (thicknessSlider is not null)
            {
                CrosshairThicknessSlider.Value = Math.Clamp(thicknessSlider.Value, 1, 8);
            }

            if (gapSlider is not null)
            {
                CrosshairGapSlider.Value = OverlayDisplaySettings.NormalizeCrosshairGap(gapSlider.Value);
            }

            if (centerMarkCheck is not null)
            {
                CrosshairCenterMarkCheck.IsChecked = centerMarkCheck.IsChecked == true;
            }

            if (centerSizeSlider is not null)
            {
                CrosshairCenterSizeSlider.Value = OverlayDisplaySettings.NormalizeCrosshairCenterMarkSize(centerSizeSlider.Value);
            }

            if (opacitySlider is not null)
            {
                CrosshairOpacitySlider.Value = Math.Clamp(opacitySlider.Value, 20, 100);
            }

            if (outlineSlider is not null)
            {
                CrosshairOutlineOpacitySlider.Value = Math.Clamp(outlineSlider.Value, 0, 80);
            }

            if (colorBox is not null)
            {
                CrosshairColorBox.Text = OverlayDisplaySettings.NormalizeCrosshairColor(colorBox.Text);
            }
        }
        finally
        {
            _isLoadingSettings = wasLoadingSettings;
        }

        OverlaySetting_Changed(sender, e);
        if (!historyState.Equals(CreateOverlayEditorHistoryState()))
        {
            PushOverlayEditorUndoState(historyState);
        }

        SyncOverlayInspectorCrosshairControls();
        SyncOverlayFullScreenCrosshairControls();
    }

    private void ApplyOverlayFullScreenModuleControlChanges(object sender, RoutedEventArgs e)
    {
        var activeKey = _isOverlayEventNotificationSelected
            ? "EventNotifications"
            : _selectedOverlayInspectorItem?.Key;
        if (string.IsNullOrWhiteSpace(activeKey))
        {
            return;
        }

        CommitOverlayModuleSettings(BuildOverlayModuleSettingsFromControls(activeKey, useFullScreenControls: true));
    }

    private OverlayDisplaySettings BuildOverlayModuleSettingsFromControls(string activeKey, bool useFullScreenControls)
    {
        switch (activeKey)
        {
            case "Notice":
            {
                var friendEventsCheck = useFullScreenControls
                    ? OverlayFullScreenCommunicationFriendEventsCheck
                    : OverlayInspectorCommunicationFriendEventsCheck;
                var messagePreviewCheck = useFullScreenControls
                    ? OverlayFullScreenCommunicationMessagePreviewCheck
                    : OverlayInspectorCommunicationMessagePreviewCheck;
                var durationSlider = useFullScreenControls
                    ? OverlayFullScreenCommunicationDurationSlider
                    : OverlayInspectorCommunicationDurationSlider;
                var durationSeconds = durationSlider is not null
                    ? OverlayDisplaySettings.NormalizeCommunicationEventDuration(durationSlider.Value)
                    : _overlaySettings.CommunicationEventDurationSeconds;
                return _overlaySettings with
                {
                    CommunicationFriendEvents = friendEventsCheck?.IsChecked == true,
                    CommunicationMessagePreview = messagePreviewCheck?.IsChecked == true,
                    CommunicationEventDurationSeconds = durationSeconds
                };
            }
            case "EventNotifications":
            {
                var sideBox = useFullScreenControls ? OverlayFullScreenEventSideBox : OverlayEventNotificationSideBox;
                var durationSeconds = _overlaySettings.EventNotificationDurationSeconds;
                if (useFullScreenControls &&
                    OverlayFullScreenEventDurationBox is not null &&
                    TryParseOverlayInspectorNumber(OverlayFullScreenEventDurationBox.Text, out var parsedDuration))
                {
                    durationSeconds = parsedDuration;
                }
                else if (!useFullScreenControls && OverlayEventNotificationDurationSlider is not null)
                {
                    durationSeconds = OverlayEventNotificationDurationSlider.Value;
                }

                return _overlaySettings with
                {
                    EventNotificationSide = sideBox?.SelectedIndex == 0
                        ? OverlayEventNotificationSide.Left
                        : OverlayEventNotificationSide.Right,
                    EventNotificationDurationSeconds = Math.Clamp(durationSeconds, 1, 12)
                };
            }
            case "Squads":
            {
                var modeBox = useFullScreenControls ? OverlayFullScreenSquadStatusModeBox : OverlayInspectorSquadStatusModeBox;
                var hideIconsCheck = useFullScreenControls ? OverlayFullScreenHideSquadIconsCheck : OverlayInspectorHideSquadIconsCheck;
                return _overlaySettings with
                {
                    SquadStatusDisplayMode = modeBox?.SelectedIndex switch
                    {
                        1 => OverlaySquadStatusDisplayMode.Compact,
                        2 => OverlaySquadStatusDisplayMode.Detailed,
                        _ => OverlaySquadStatusDisplayMode.Auto
                    },
                    HideSquadIcons = hideIconsCheck?.IsChecked == true
                };
            }
            case "Members":
            {
                var scopeBox = useFullScreenControls ? OverlayFullScreenMemberScopeBox : OverlayInspectorMemberScopeBox;
                var priorityBox = useFullScreenControls ? OverlayFullScreenMemberPriorityBox : OverlayInspectorMemberPriorityBox;
                var nameModeBox = useFullScreenControls ? OverlayFullScreenMemberNameModeBox : OverlayInspectorMemberNameModeBox;
                var memberNameColumnRatio = !useFullScreenControls && OverlayInspectorMemberColumnRatioSlider is not null
                    ? OverlayDisplaySettings.NormalizeMemberNameColumnRatio(OverlayInspectorMemberColumnRatioSlider.Value / 100)
                    : _overlaySettings.MemberNameColumnRatio;
                var hideOfflineCheck = useFullScreenControls ? OverlayFullScreenHideOfflineMembersCheck : OverlayInspectorHideOfflineMembersCheck;
                var hideOnlineStatusCheck = useFullScreenControls ? OverlayFullScreenHideMemberOnlineStatusCheck : OverlayInspectorHideMemberOnlineStatusCheck;
                var hideSelfCheck = useFullScreenControls ? OverlayFullScreenHideSelfMemberCheck : OverlayInspectorHideSelfMemberCheck;
                var hideOffline = hideOfflineCheck?.IsChecked == true;
                return _overlaySettings with
                {
                    MemberScopeMode = scopeBox?.SelectedIndex switch
                    {
                        1 => OverlayMemberScopeMode.AllFleet,
                        2 => OverlayMemberScopeMode.OtherSquads,
                        _ => OverlayMemberScopeMode.CurrentSquad
                    },
                    MemberPriorityMode = priorityBox?.SelectedIndex switch
                    {
                        1 => OverlayMemberPriorityMode.Self,
                        2 => OverlayMemberPriorityMode.SquadCommander,
                        _ => OverlayMemberPriorityMode.Default
                    },
                    MemberNameMode = nameModeBox?.SelectedIndex switch
                    {
                        1 => OverlayMemberNameMode.CallsignOnly,
                        2 => OverlayMemberNameMode.GameNameOnly,
                        _ => OverlayMemberNameMode.CallsignAndGameName
                    },
                    MemberNameColumnRatio = memberNameColumnRatio,
                    HideOfflineMembers = hideOffline,
                    HideMemberOnlineStatus = hideOffline && hideOnlineStatusCheck?.IsChecked == true,
                    HideSelfMember = hideSelfCheck?.IsChecked == true
                };
            }
            case "Chat":
            {
                var modeBox = useFullScreenControls ? OverlayFullScreenChatModeBox : OverlayInspectorChatModeBox;
                var fleetScopeBox = useFullScreenControls ? OverlayFullScreenFleetChatScopeBox : OverlayInspectorFleetChatScopeBox;
                var durationBox = useFullScreenControls ? OverlayFullScreenChatDurationBox : OverlayInspectorChatDurationBox;
                var fontSizeBox = useFullScreenControls ? OverlayFullScreenChatFontSizeBox : OverlayInspectorChatFontSizeBox;
                var regionBox = useFullScreenControls ? OverlayFullScreenChatRegionBox : OverlayInspectorChatRegionBox;
                var densityBox = useFullScreenControls ? OverlayFullScreenChatDensityBox : OverlayInspectorChatDensityBox;
                var edgeStrengthBox = useFullScreenControls ? OverlayFullScreenChatEdgeStrengthBox : OverlayInspectorChatEdgeStrengthBox;
                var avoidCenterCheck = useFullScreenControls ? OverlayFullScreenChatAvoidCenterCheck : OverlayInspectorChatAvoidCenterCheck;
                var showSenderCheck = useFullScreenControls ? OverlayFullScreenChatShowSenderCheck : OverlayInspectorChatShowSenderCheck;
                var showTimestampCheck = useFullScreenControls ? OverlayFullScreenChatShowTimestampCheck : OverlayInspectorChatShowTimestampCheck;
                var showSystemCheck = useFullScreenControls ? OverlayFullScreenChatShowSystemCheck : OverlayInspectorChatShowSystemCheck;
                var hideSelfCheck = useFullScreenControls ? OverlayFullScreenChatHideSelfCheck : OverlayInspectorChatHideSelfCheck;
                var selectedDuration = TryGetComboBoxTagNumber(durationBox, out var parsedDuration)
                    ? parsedDuration
                    : _overlaySettings.ChatDurationSeconds;
                var nextDisplayMode = modeBox?.SelectedIndex == 1
                    ? OverlayChatDisplayMode.FullScreenBarrage
                    : OverlayChatDisplayMode.MessageList;
                var duration = OverlayDisplaySettings.ResolveChatDurationForDisplayModeChange(
                    _overlaySettings.ChatDisplayMode,
                    nextDisplayMode,
                    selectedDuration);
                var fontSize = TryGetComboBoxTagNumber(fontSizeBox, out var parsedFontSize)
                    ? OverlayDisplaySettings.NormalizeChatBarrageFontSize(parsedFontSize)
                    : _overlaySettings.ChatBarrageFontSize;
                var region = GetComboBoxTagEnum(regionBox, _overlaySettings.ChatBarrageRegion);
                var density = GetComboBoxTagEnum(densityBox, _overlaySettings.ChatBarrageDensity);
                var edgeStrength = GetComboBoxTagEnum(edgeStrengthBox, _overlaySettings.ChatTextEdgeStrength);
                var fleetChatScope = GetComboBoxTagEnum(fleetScopeBox, _overlaySettings.FleetChatScope);
                return _overlaySettings with
                {
                    ChatDisplayMode = nextDisplayMode,
                    ChatSide = _overlaySettings.ChatSide,
                    ChatMaxVisibleCount = _overlaySettings.ChatMaxVisibleCount,
                    ChatDurationSeconds = duration,
                    ChatShowSender = showSenderCheck?.IsChecked == true,
                    ChatShowTimestamp = showTimestampCheck?.IsChecked == true,
                    ChatShowSystemMessages = showSystemCheck?.IsChecked == true,
                    ChatHideSelfMessages = hideSelfCheck?.IsChecked == true,
                    ChatBarrageFontSize = fontSize,
                    ChatBarrageRegion = OverlayDisplaySettings.NormalizeChatBarrageRegion(region),
                    ChatBarrageDensity = OverlayDisplaySettings.NormalizeChatBarrageDensity(density),
                    ChatBarrageAvoidCenter = avoidCenterCheck?.IsChecked == true,
                    ChatTextEdgeStrength = OverlayDisplaySettings.NormalizeChatTextEdgeStrength(edgeStrength),
                    FleetChatScope = OverlayDisplaySettings.NormalizeFleetChatScope(fleetChatScope)
                };
            }
        }

        return _overlaySettings;
    }

    private static bool TryGetComboBoxTagNumber(System.Windows.Controls.ComboBox? comboBox, out double value)
    {
        value = 0;
        return comboBox?.SelectedItem is ComboBoxItem item &&
               double.TryParse(item.Tag?.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out value);
    }

    private static TEnum GetComboBoxTagEnum<TEnum>(
        System.Windows.Controls.ComboBox? comboBox,
        TEnum fallback)
        where TEnum : struct, Enum
    {
        return comboBox?.SelectedItem is ComboBoxItem item &&
               Enum.TryParse<TEnum>(item.Tag?.ToString(), out var parsed)
            ? parsed
            : fallback;
    }

    private void ApplyOverlayInspectorModuleControlChanges(object sender, RoutedEventArgs e)
    {
        var activeKey = _isOverlayEventNotificationSelected
            ? "EventNotifications"
            : _selectedOverlayInspectorItem?.Key;
        if (string.IsNullOrWhiteSpace(activeKey))
        {
            return;
        }

        CommitOverlayModuleSettings(BuildOverlayModuleSettingsFromControls(activeKey, useFullScreenControls: false));
    }

    private void CommitOverlayModuleSettings(OverlayDisplaySettings nextSettings)
    {
        if (_isLoadingSettings || _isSyncingOverlayInspectorModuleControls)
        {
            return;
        }

        nextSettings = ApplyOverlayFeatureLocks(nextSettings);
        if (nextSettings == _overlaySettings)
        {
            RefreshOverlayInspector();
            return;
        }

        var historyState = CreateOverlayEditorHistoryState();
        if (nextSettings.FleetChatScope != _overlaySettings.FleetChatScope)
        {
            ResetFleetOverlayChatProjection();
        }
        _overlaySettings = nextSettings;
        PushOverlayEditorUndoState(historyState);
        MarkOverlayEditorLayoutDirty();
        SaveCurrentConfig();
        RenderOverlayEditor();
        RefreshOverlayWindow();
        RefreshOverlayInspector();
    }

    private void OverlayInspectorNudge_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.Button { Tag: string tag })
        {
            return;
        }

        var parts = tag.Split(':', 2);
        if (parts.Length != 2 ||
            !double.TryParse(parts[1], NumberStyles.Float, CultureInfo.InvariantCulture, out var direction))
        {
            return;
        }

        var step = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift) ? 10 : _overlayEditorNudgeStep;
        ApplyOverlayInspectorPixelDelta(parts[0], direction * step);
    }

    private void OverlayInspectorNudgeStepBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (OverlayInspectorNudgeStepBox?.SelectedItem is ComboBoxItem item &&
            double.TryParse(item.Tag?.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var step))
        {
            _overlayEditorNudgeStep = Math.Clamp(step, 1, 20);
        }
        else
        {
            _overlayEditorNudgeStep = 1;
        }
    }

    private void OverlayInspectorValueBox_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key != Key.Enter)
        {
            return;
        }

        CommitOverlayInspectorValue(sender as System.Windows.Controls.TextBox);
        e.Handled = true;
    }

    private void OverlayInspectorValueBox_LostFocus(object sender, RoutedEventArgs e)
    {
        CommitOverlayInspectorValue(sender as System.Windows.Controls.TextBox);
    }

    private void CommitOverlayInspectorValue(System.Windows.Controls.TextBox? textBox)
    {
        if (textBox?.Tag is not string property ||
            !TryGetSelectedOverlayInspectorItem(out _) ||
            !TryParseOverlayInspectorNumber(textBox.Text, out var value))
        {
            RefreshOverlayInspector();
            return;
        }

        ApplyOverlayInspectorPixelValue(property, value);
    }

    private void ApplyOverlayInspectorPixelDelta(string property, double delta)
    {
        if (!TryGetSelectedOverlayInspectorItem(out var item) ||
            item.IsLocked ||
            _isOverlayLayoutLocked)
        {
            return;
        }

        var rect = ResolveOverlayEditorItemDisplayRect(item);
        var currentValue = property switch
        {
            "X" => rect.Left,
            "Y" => rect.Top,
            "Width" => rect.Width,
            "Height" => rect.Height,
            _ => double.NaN
        };

        if (double.IsNaN(currentValue))
        {
            return;
        }

        ApplyOverlayInspectorPixelValue(property, currentValue + delta);
    }

    private void ApplyOverlayInspectorPixelValue(string property, double pixelValue)
    {
        if (!TryGetSelectedOverlayInspectorItem(out var item) ||
            item.IsLocked ||
            _isOverlayLayoutLocked)
        {
            RefreshOverlayInspector();
            return;
        }

        var canvasWidth = OverlayEditorCanvas.Width;
        var canvasHeight = OverlayEditorCanvas.Height;
        var historyState = CreateOverlayEditorHistoryState();
        var currentRect = ResolveOverlayEditorItemDisplayRect(
            item,
            canvasWidth,
            canvasHeight);
        var nextRect = currentRect;
        switch (property)
        {
            case "X":
                nextRect = new Rect(pixelValue, currentRect.Top, currentRect.Width, currentRect.Height);
                break;
            case "Y":
                nextRect = new Rect(currentRect.Left, pixelValue, currentRect.Width, currentRect.Height);
                break;
            case "Width":
                nextRect = new Rect(currentRect.Left, currentRect.Top, pixelValue, currentRect.Height);
                break;
            case "Height":
                nextRect = new Rect(currentRect.Left, currentRect.Top, currentRect.Width, pixelValue);
                break;
            default:
                RefreshOverlayInspector();
                return;
        }

        nextRect = ConstrainCommunicationEventRect(item, nextRect);
        OverlaySurfaceLayout.ApplyRectToItem(item, nextRect, canvasWidth, canvasHeight);
        if (IsCommunicationEventModule(item))
        {
            item.VerticalAnchor = nextRect.Top <= 0.5
                ? OverlayVerticalAnchor.Top
                : OverlayVerticalAnchor.Bottom;
        }
        var changed = !historyState.Equals(CreateOverlayEditorHistoryState());
        if (changed)
        {
            PushOverlayEditorUndoState(historyState);
        }
        if (changed)
        {
            MarkOverlayEditorLayoutDirty();
        }

        RenderOverlayEditor();
        SaveCurrentConfig();
        RefreshOverlayWindow();
    }

    private bool TryGetSelectedOverlayInspectorItem([NotNullWhen(true)] out OverlayLayoutItem? item)
    {
        item = _selectedOverlayInspectorItem;
        return item is not null &&
               _overlayLayout.Contains(item) &&
               IsOverlayEditorItemVisible(item) &&
               OverlayEditorCanvas is not null;
    }

    private static bool TryParseOverlayInspectorNumber(string text, out double value)
    {
        var normalized = text
            .Trim()
            .Replace("px", "", StringComparison.OrdinalIgnoreCase)
            .Trim();
        var parsed = double.TryParse(normalized, NumberStyles.Float, CultureInfo.CurrentCulture, out value) ||
                     double.TryParse(normalized, NumberStyles.Float, CultureInfo.InvariantCulture, out value);
        return parsed && double.IsFinite(value);
    }

    private void ResetSelectedOverlayModule_Click(object sender, RoutedEventArgs e)
    {
        if (_isOverlayCrosshairSelected && _overlaySettings.ShowCrosshair)
        {
            PushOverlayEditorUndoState();
            var defaults = OverlayDisplaySettings.Default;
            var wasLoadingSettings = _isLoadingSettings;
            _isLoadingSettings = true;
            try
            {
                ShowCrosshairCheck.IsChecked = true;
                SetComboBoxSelectedTag(
                    CrosshairModeBox,
                    OverlayDisplaySettings.NormalizeCrosshairMode(defaults.CrosshairMode).ToString());
                CrosshairThemeColorCheck.IsChecked = defaults.CrosshairUseThemeColor;
                CrosshairSizeSlider.Value = OverlayDisplaySettings.NormalizeCrosshairSize(defaults.CrosshairSize);
                CrosshairThicknessSlider.Value = Math.Clamp(defaults.CrosshairThickness, 1, 8);
                CrosshairGapSlider.Value = OverlayDisplaySettings.NormalizeCrosshairGap(defaults.CrosshairGap);
                CrosshairCenterMarkCheck.IsChecked = defaults.CrosshairShowCenterMark;
                CrosshairCenterSizeSlider.Value = OverlayDisplaySettings.NormalizeCrosshairCenterMarkSize(defaults.CrosshairCenterMarkSize);
                CrosshairOpacitySlider.Value = Math.Clamp(defaults.CrosshairOpacity, 0.2, 1.0) * 100.0;
                CrosshairOutlineOpacitySlider.Value = OverlayDisplaySettings.NormalizeCrosshairOutlineOpacity(defaults.CrosshairOutlineOpacity) * 100.0;
                CrosshairColorBox.Text = OverlayDisplaySettings.NormalizeCrosshairColor(defaults.CrosshairColor);
            }
            finally
            {
                _isLoadingSettings = wasLoadingSettings;
            }

            OverlaySetting_Changed(sender, e);
            RefreshOverlayInspector();
            AppendOutput("Overlay crosshair reset.");
            return;
        }

        var item = _selectedOverlayInspectorItem;
        if (item is null)
        {
            return;
        }

        var defaultItem = CreateDefaultOverlayLayout(_activeOverlayPreset)
            .FirstOrDefault(candidate => candidate.Key.Equals(item.Key, StringComparison.OrdinalIgnoreCase));
        if (defaultItem is null)
        {
            return;
        }

        PushOverlayEditorUndoState();
        item.X = defaultItem.X;
        item.Y = defaultItem.Y;
        item.Width = defaultItem.Width;
        item.Height = defaultItem.Height;
        RenderOverlayEditor();
        MarkOverlayEditorLayoutDirty();
        SaveCurrentConfig();
        RefreshOverlayWindow();
        RefreshOverlayInspector();
        AppendOutput($"Overlay module reset: {item.Key}.");
    }

    private void HideSelectedOverlayModule_Click(object sender, RoutedEventArgs e)
    {
        if (_isOverlayEventNotificationSelected && _overlaySettings.ShowEventNotifications)
        {
            PushOverlayEditorUndoState();
            var wasLoadingSettings = _isLoadingSettings;
            _isLoadingSettings = true;
            try
            {
                ShowEventNotificationsCheck.IsChecked = false;
                _isOverlayEventNotificationSelected = false;
                _isOverlayCrosshairSelected = false;
            }
            finally
            {
                _isLoadingSettings = wasLoadingSettings;
            }

            OverlaySetting_Changed(sender, e);
            RefreshOverlayInspector();
            return;
        }

        if (_isOverlayCrosshairSelected && _overlaySettings.ShowCrosshair)
        {
            PushOverlayEditorUndoState();
            var wasLoadingSettings = _isLoadingSettings;
            _isLoadingSettings = true;
            try
            {
                ShowCrosshairCheck.IsChecked = false;
                _isOverlayCrosshairSelected = false;
            }
            finally
            {
                _isLoadingSettings = wasLoadingSettings;
            }

            OverlaySetting_Changed(sender, e);
            RefreshOverlayInspector();
            return;
        }

        var item = _selectedOverlayInspectorItem;
        if (item is null)
        {
            return;
        }

        PushOverlayEditorUndoState();
        var wasLoading = _isLoadingSettings;
        _isLoadingSettings = true;
        try
        {
            switch (item.Key)
            {
                case "Notice":
                    ShowNoticePanelCheck.IsChecked = false;
                    break;
                case "Squads":
                    ShowSquadsPanelCheck.IsChecked = false;
                    break;
                case "Members":
                    ShowMembersPanelCheck.IsChecked = false;
                    break;
                case "Chat":
                    ShowChatPanelCheck.IsChecked = false;
                    break;
            }
        }
        finally
        {
            _isLoadingSettings = wasLoading;
        }

        _selectedOverlayInspectorItem = null;
        _isOverlayCrosshairSelected = false;
        OverlaySetting_Changed(sender, e);
        RefreshOverlayInspector();
    }
}
