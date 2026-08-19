using Microsoft.Win32;
using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Color = System.Windows.Media.Color;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using OpenFileDialog = Microsoft.Win32.OpenFileDialog;
using SaveFileDialog = Microsoft.Win32.SaveFileDialog;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private bool _overlaySettingsWheelInterruptionAttached;

    private void OverlaySettingSwitch_PreviewMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (sender is not System.Windows.Controls.CheckBox checkBox)
        {
            return;
        }

        checkBox.ApplyTemplate();
        if (checkBox.Template.FindName("SwitchTrack", checkBox) is not FrameworkElement switchTrack ||
            !switchTrack.IsMouseOver)
        {
            e.Handled = true;
        }
    }

    private OverlayCommandState BuildOverlayCommandState()
    {
        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var noticeTitle = !string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle)
            ? zh ? "任务发布" : "Mission broadcast"
            : zh ? "舰队接入" : "Fleet link";
        var noticeText = !string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle)
            ? $"{_fleetCurrentTaskTitle} / {NormalizeOptionalField(_fleetCurrentTaskBrief)}{BuildInvisibleNoticeRevision()}"
            : zh ? "已接入舰队频道，等待指挥同步" : "Fleet channel linked. Awaiting command sync.";

        return new OverlayCommandState(
            noticeTitle,
            noticeText,
            _fleetCurrentTaskTitle,
            _fleetCurrentTaskBrief,
            _fleetCurrentTaskRally,
            _fleetCurrentTaskShip);
    }

    private string BuildInvisibleNoticeRevision()
    {
        if (_fleetCurrentTaskNoticeRevision <= 0)
        {
            return "";
        }

        return new string('\u200B', (_fleetCurrentTaskNoticeRevision % 2) + 1);
    }

    private void SaveOverlayLayout_Click(object sender, RoutedEventArgs e)
    {
        MarkOverlayEditorLayoutSaved();
        SaveCurrentConfig();
        RefreshOverlayWindow();
        RefreshOverlayOverviewSummary();
        AppendOutput($"Overlay preset saved: {_activeOverlayPreset}.");
    }

    private void ResetOverlayLayout_Click(object sender, RoutedEventArgs e)
    {
        PushOverlayEditorUndoState();
        _overlayLayout.Clear();
        _overlayLayout.AddRange(CreateDefaultOverlayLayout(_activeOverlayPreset));
        _overlaySettings = CreateDefaultOverlaySettings(_activeOverlayPreset);
        _selectedOverlayInspectorItem = null;
        _isOverlayEventNotificationSelected = false;
        _isOverlayCrosshairSelected = false;
        _isLoadingSettings = true;
        ApplyOverlaySettingsToControls();
        _isLoadingSettings = false;
        RenderOverlayEditor();
        MarkOverlayEditorLayoutDirty();
        SaveCurrentConfig();
        RefreshOverlayWindow();
        AppendOutput($"Overlay preset reset: {_activeOverlayPreset}.");
    }

    private void MarkOverlayEditorLayoutDirty()
    {
        _isOverlayEditorLayoutDirty = true;
        RefreshOverlayOverviewSummary();
    }

    private void MarkOverlayEditorLayoutSaved()
    {
        CaptureOverlayEditorSavedSnapshot();
        _isOverlayEditorLayoutDirty = false;
        _overlayEditorLastSavedAt = DateTimeOffset.Now;
        RefreshOverlayOverviewSummary();
    }

    private void CaptureOverlayEditorSavedSnapshot()
    {
        _overlaySettings = ApplyOverlayFeatureLocks(_overlaySettings);
        _savedOverlayPresetSnapshot = NormalizeOverlayPresetId(_activeOverlayPreset);
        _savedOverlaySettingsSnapshot = _overlaySettings.Serialize();
        _savedOverlayLayoutSnapshot = SerializeOverlayLayout();
    }

    private void DiscardOverlayEditorLayoutChanges()
    {
        if (string.IsNullOrWhiteSpace(_savedOverlaySettingsSnapshot) ||
            string.IsNullOrWhiteSpace(_savedOverlayLayoutSnapshot))
        {
            return;
        }

        _activeOverlayPreset = NormalizeOverlayPresetId(_savedOverlayPresetSnapshot);
        _overlaySettings = ApplyOverlayFeatureLocks(OverlayDisplaySettings.Parse(_savedOverlaySettingsSnapshot));
        LoadOverlayLayout(_savedOverlayLayoutSnapshot);
        _selectedOverlayInspectorItem = null;
        _isOverlayEventNotificationSelected = false;
        _isOverlayCrosshairSelected = false;
        ClearOverlayEditorHistory();

        var wasLoadingSettings = _isLoadingSettings;
        _isLoadingSettings = true;
        try
        {
            ApplyOverlaySettingsToControls();
        }
        finally
        {
            _isLoadingSettings = wasLoadingSettings;
        }

        _isOverlayEditorLayoutDirty = false;
        RenderOverlayEditor();
        SaveCurrentConfig();
        RefreshOverlayWindow();
        RefreshOverlayOverviewSummary();
        AppendOutput($"Overlay preset changes discarded: {_activeOverlayPreset}.");
    }

    private void DiscardOverlayLayoutChanges_Click(object sender, RoutedEventArgs e)
    {
        if (!_isOverlayEditorLayoutDirty)
        {
            return;
        }

        var result = StarBridgeMessageBox.Show(
            this,
            "放弃本轮未保存的浮层布局与模块设置，并恢复到上次保存的状态？",
            "放弃更改",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);
        if (result != MessageBoxResult.Yes)
        {
            return;
        }

        DiscardOverlayEditorLayoutChanges();
    }

    private void OverlayEditorCanvas_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (_isApplyingOverlayEditorCanvasScale)
        {
            return;
        }

        RenderOverlayEditor();
    }

    private void OverlayPreviewCanvasHost_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        ApplyOverlayEditorCanvasScaleState();
    }

    private void OverlayCategoryButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement element ||
            OverlaySettingsScrollViewer is null)
        {
            return;
        }

        var sectionKey = !string.IsNullOrWhiteSpace(element.Uid)
            ? element.Uid
            : element.Tag?.ToString();
        var target = ResolveOverlaySettingsSection(sectionKey);
        if (target is null)
        {
            return;
        }

        if (OverlayInspectorPanel?.Visibility == Visibility.Visible)
        {
            SetOverlayInspectorOpen(false);
        }

        _overlaySettingsProgrammaticTargetKey = sectionKey;
        SetActiveOverlaySettingsSection(sectionKey);
        NotifyOverlaySettingsGuideTarget(element);
        ScrollOverlaySettingsToSection(target);
        if (_isOverlayEditorCompact)
        {
            SetOverlayEditorCompactDrawer(OverlayEditorCompactDrawer.Settings);
        }
    }

    private void OverlaySettingsScrollViewer_Loaded(object sender, RoutedEventArgs e)
    {
        if (_overlaySettingsWheelInterruptionAttached ||
            sender is not ScrollViewer viewer)
        {
            return;
        }

        viewer.AddHandler(
            Mouse.PreviewMouseWheelEvent,
            new MouseWheelEventHandler(OverlaySettingsScrollViewer_PreviewMouseWheel),
            handledEventsToo: true);
        _overlaySettingsWheelInterruptionAttached = true;
    }

    private void OverlaySettingsScrollViewer_PreviewMouseWheel(
        object sender,
        MouseWheelEventArgs e)
    {
        CancelOverlaySettingsProgrammaticScroll();
    }

    private void CancelOverlaySettingsProgrammaticScroll()
    {
        if (_overlaySettingsSmoothScrollTimer?.IsEnabled != true &&
            string.IsNullOrWhiteSpace(_overlaySettingsProgrammaticTargetKey))
        {
            return;
        }

        _overlaySettingsSmoothScrollTimer?.Stop();
        _overlaySettingsProgrammaticTargetKey = null;
        if (OverlaySettingsScrollViewer is not null)
        {
            _overlaySettingsSmoothScrollTarget =
                OverlaySettingsScrollViewer.VerticalOffset;
        }
    }

    private void OverlaySettingsScrollViewer_ScrollChanged(object sender, ScrollChangedEventArgs e)
    {
        ScheduleGuidedTourLayout();

        if (!string.IsNullOrWhiteSpace(_overlaySettingsProgrammaticTargetKey))
        {
            return;
        }

        if (ConstrainOverlaySettingsGuideScroll())
        {
            return;
        }

        RefreshActiveOverlaySettingsSectionFromScroll();
    }

    private bool TryResolveOverlayGuideScrollRange(out OverlayGuideScrollRange range)
    {
        range = default;
        if (_guideMode != GuideMode.OverlaySettings || OverlaySettingsScrollViewer is null)
        {
            return false;
        }

        var scrollableHeight = OverlaySettingsScrollViewer.ScrollableHeight;
        if (!_overlayGuideShowingExplanation || _guidedTourTarget is null)
        {
            var lockedOffset = Math.Clamp(_overlayGuideLockedScrollOffset, 0, scrollableHeight);
            range = new OverlayGuideScrollRange(lockedOffset, lockedOffset);
            return true;
        }

        try
        {
            var relativeTop = _guidedTourTarget
                .TransformToAncestor(OverlaySettingsScrollViewer)
                .Transform(new System.Windows.Point(0, 0))
                .Y;
            var sectionTop = OverlaySettingsScrollViewer.VerticalOffset + relativeTop;
            range = OverlayGuideScrollRange.Resolve(
                sectionTop,
                _guidedTourTarget.ActualHeight,
                OverlaySettingsScrollViewer.ViewportHeight,
                scrollableHeight);
            return true;
        }
        catch (Exception exception) when (exception is InvalidOperationException or ArgumentException)
        {
            var lockedOffset = Math.Clamp(_overlayGuideLockedScrollOffset, 0, scrollableHeight);
            range = new OverlayGuideScrollRange(lockedOffset, lockedOffset);
            return true;
        }
    }

    private double ClampOverlaySettingsGuideOffset(double offset) =>
        TryResolveOverlayGuideScrollRange(out var range)
            ? range.Clamp(offset)
            : Math.Clamp(offset, 0, OverlaySettingsScrollViewer?.ScrollableHeight ?? 0);

    private void ApplyOverlayGuideScrollRange()
    {
        if (OverlaySettingsScrollViewer is not null &&
            TryResolveOverlayGuideScrollRange(out var range))
        {
            SmoothWheelScrollBehavior.SetVerticalBounds(
                OverlaySettingsScrollViewer,
                range.Minimum,
                range.Maximum);
        }
    }

    private void ReleaseOverlayGuideScrollRange()
    {
        if (OverlaySettingsScrollViewer is not null)
        {
            SmoothWheelScrollBehavior.ClearVerticalBounds(OverlaySettingsScrollViewer);
        }
    }

    private bool ConstrainOverlaySettingsGuideScroll()
    {
        if (OverlaySettingsScrollViewer is null ||
            !TryResolveOverlayGuideScrollRange(out var range))
        {
            return false;
        }

        var constrainedOffset = range.Clamp(OverlaySettingsScrollViewer.VerticalOffset);
        if (Math.Abs(constrainedOffset - OverlaySettingsScrollViewer.VerticalOffset) <= 0.3)
        {
            return false;
        }

        _overlaySettingsSmoothScrollTimer?.Stop();
        _overlaySettingsSmoothScrollTarget = constrainedOffset;
        OverlaySettingsScrollViewer.ScrollToVerticalOffset(constrainedOffset);
        return true;
    }

    private FrameworkElement? ResolveOverlaySettingsSection(string? sectionKey)
    {
        return sectionKey switch
        {
            "overview" => OverlaySettingsSectionOverview,
            "preset" => OverlaySettingsSectionPreset,
            "modules" => OverlaySettingsSectionModules,
            "placement" => OverlaySettingsSectionPlacement,
            // Older saved guide/navigation state may still request the former
            // standalone events page. Event notification settings now belong
            // to the module catalogue, so keep the legacy key harmless.
            "events" => OverlaySettingsSectionModules,
            "appearance" => OverlaySettingsSectionAppearance,
            "motion" => OverlaySettingsSectionMotion,
            "crosshair" => OverlaySettingsSectionCrosshair,
            "startup" => OverlaySettingsSectionStartup,
            "background" => OverlaySettingsSectionBackground,
            _ => null
        };
    }

    private IEnumerable<(string Key, FrameworkElement Section)> EnumerateOverlaySettingsSections()
    {
        var keys = new[] { "overview", "startup", "background", "modules", "placement", "crosshair", "appearance", "motion", "preset" };
        foreach (var key in keys)
        {
            var section = ResolveOverlaySettingsSection(key);
            if (section is not null)
            {
                yield return (key, section);
            }
        }
    }

    private void ScrollOverlaySettingsToSection(FrameworkElement target)
    {
        if (OverlaySettingsScrollViewer is null)
        {
            return;
        }

        try
        {
            var position = target.TransformToAncestor(OverlaySettingsScrollViewer).Transform(new System.Windows.Point(0, 0));
            var nextOffset = Math.Clamp(
                OverlaySettingsScrollViewer.VerticalOffset + position.Y - 10,
                0,
                OverlaySettingsScrollViewer.ScrollableHeight);
            StartOverlaySettingsSmoothScroll(nextOffset);
        }
        catch
        {
            target.BringIntoView();
            SetActiveOverlaySettingsSection(_overlaySettingsProgrammaticTargetKey);
            _overlaySettingsProgrammaticTargetKey = null;
        }
    }

    private void StartOverlaySettingsSmoothScroll(double targetOffset)
    {
        if (OverlaySettingsScrollViewer is null)
        {
            return;
        }

        SmoothWheelScrollBehavior.CancelPendingMotion(OverlaySettingsScrollViewer);
        _overlaySettingsSmoothScrollTarget = ClampOverlaySettingsGuideOffset(targetOffset);
        _overlaySettingsSmoothScrollTimer ??= new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(12) };
        _overlaySettingsSmoothScrollTimer.Tick -= OverlaySettingsSmoothScrollTimer_Tick;
        _overlaySettingsSmoothScrollTimer.Tick += OverlaySettingsSmoothScrollTimer_Tick;
        _overlaySettingsSmoothScrollTimer.Start();
    }

    private void OverlaySettingsSmoothScrollTimer_Tick(object? sender, EventArgs e)
    {
        if (OverlaySettingsScrollViewer is null ||
            _overlaySettingsSmoothScrollTimer is null)
        {
            return;
        }

        var currentOffset = OverlaySettingsScrollViewer.VerticalOffset;
        var delta = _overlaySettingsSmoothScrollTarget - currentOffset;
        if (Math.Abs(delta) < 0.5)
        {
            OverlaySettingsScrollViewer.ScrollToVerticalOffset(_overlaySettingsSmoothScrollTarget);
            _overlaySettingsSmoothScrollTimer.Stop();
            var lockedTargetKey = _overlaySettingsProgrammaticTargetKey;
            if (!string.IsNullOrWhiteSpace(lockedTargetKey))
            {
                SetActiveOverlaySettingsSection(lockedTargetKey);
                _overlaySettingsProgrammaticTargetKey = null;
            }
            else
            {
                RefreshActiveOverlaySettingsSectionFromScroll();
            }

            return;
        }

        OverlaySettingsScrollViewer.ScrollToVerticalOffset(currentOffset + delta * 0.28);
    }

    private void RefreshActiveOverlaySettingsSectionFromScroll()
    {
        if (OverlaySettingsScrollViewer is null)
        {
            return;
        }

        try
        {
            if (OverlaySettingsScrollViewer.ScrollableHeight > 0 &&
                OverlaySettingsScrollViewer.VerticalOffset >= OverlaySettingsScrollViewer.ScrollableHeight - 0.5)
            {
                SetActiveOverlaySettingsSection(
                    OverlaySettingsNavigationPolicy.ResolveBottomSectionKey(_overlaySettingsActiveKey));
                return;
            }

            const double activationLine = 32;
            string? activeKey = null;
            var closestAbove = double.NegativeInfinity;
            var closestDistance = double.PositiveInfinity;

            foreach (var (key, section) in EnumerateOverlaySettingsSections())
            {
                var y = section.TransformToAncestor(OverlaySettingsScrollViewer).Transform(new System.Windows.Point(0, 0)).Y;
                if (y <= activationLine && y > closestAbove)
                {
                    closestAbove = y;
                    activeKey = key;
                }

                if (activeKey is null)
                {
                    var distance = Math.Abs(y - activationLine);
                    if (distance < closestDistance)
                    {
                        closestDistance = distance;
                        activeKey = key;
                    }
                }
            }

            SetActiveOverlaySettingsSection(activeKey);
        }
        catch
        {
            SetActiveOverlaySettingsSection("overview");
        }
    }

    private void SetActiveOverlaySettingsSection(string? activeKey)
    {
        if (OverlayEditorCategoryPanel is null ||
            string.IsNullOrWhiteSpace(activeKey))
        {
            return;
        }

        var validKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "overview",
            "preset",
            "modules",
            "placement",
            "events",
            "appearance",
            "motion",
            "crosshair",
            "startup",
            "background"
        };

        System.Windows.Controls.Button? activeButton = null;
        foreach (var button in FindVisualChildren<System.Windows.Controls.Button>(OverlayEditorCategoryPanel))
        {
            if (!validKeys.Contains(button.Uid))
            {
                continue;
            }

            button.Tag = string.Equals(button.Uid, activeKey, StringComparison.OrdinalIgnoreCase)
                ? "Active"
                : button.Uid;
            if (string.Equals(button.Uid, activeKey, StringComparison.OrdinalIgnoreCase))
            {
                activeButton = button;
            }
        }

        if (activeButton is not null)
        {
            var shouldAnimate = _overlaySettingsActiveRailInitialized &&
                                !string.Equals(_overlaySettingsActiveKey, activeKey, StringComparison.OrdinalIgnoreCase);
            _overlaySettingsActiveKey = activeKey;
            activeButton.BringIntoView();
            MoveOverlaySettingsActiveRail(activeButton, shouldAnimate);
        }
    }

    private void MoveOverlaySettingsActiveRail(System.Windows.Controls.Button activeButton, bool animate)
    {
        if (OverlaySettingsNavigationContentGrid is null ||
            OverlaySettingsActiveRail is null ||
            OverlaySettingsActiveRailTransform is null)
        {
            return;
        }

        if (!OverlaySettingsNavigationContentGrid.IsLoaded || !activeButton.IsLoaded || activeButton.ActualHeight <= 0)
        {
            Dispatcher.BeginInvoke(
                () => MoveOverlaySettingsActiveRail(activeButton, animate: false),
                DispatcherPriority.Loaded);
            return;
        }

        try
        {
            var targetPosition = activeButton
                .TransformToAncestor(OverlaySettingsNavigationContentGrid)
                .Transform(new System.Windows.Point(0, 0));
            var targetY = targetPosition.Y + 2;
            OverlaySettingsActiveRail.Height = Math.Max(0, activeButton.ActualHeight - 4);
            OverlaySettingsActiveRail.Opacity = 1;

            var currentY = OverlaySettingsActiveRailTransform.Y;
            OverlaySettingsActiveRailTransform.BeginAnimation(TranslateTransform.YProperty, null);
            OverlaySettingsActiveRailTransform.Y = targetY;

            if (!animate || !UiMotion.IsEnabled || Math.Abs(targetY - currentY) < 0.5)
            {
                _overlaySettingsActiveRailInitialized = true;
                return;
            }

            var animation = new DoubleAnimationUsingKeyFrames
            {
                FillBehavior = FillBehavior.Stop
            };
            animation.KeyFrames.Add(new DiscreteDoubleKeyFrame(currentY, KeyTime.FromTimeSpan(TimeSpan.Zero)));
            animation.KeyFrames.Add(new SplineDoubleKeyFrame(
                targetY,
                KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(180)),
                new KeySpline(0.22, 1.0, 0.36, 1.0)));
            OverlaySettingsActiveRailTransform.BeginAnimation(
                TranslateTransform.YProperty,
                animation,
                HandoffBehavior.SnapshotAndReplace);
            _overlaySettingsActiveRailInitialized = true;
        }
        catch
        {
            OverlaySettingsActiveRailTransform.BeginAnimation(TranslateTransform.YProperty, null);
            _overlaySettingsActiveRailInitialized = true;
        }
    }

    private void OverlaySetting_Changed(object sender, RoutedEventArgs e)
    {
        if (_isLoadingSettings || _isApplyingLocalPlayReminderSettings)
        {
            return;
        }

        if (TrayModeCheck is null ||
            OverlayTextOpacitySlider is null ||
            OverlayBackgroundOpacitySlider is null ||
            ShowNoticePanelCheck is null ||
            ShowSquadsPanelCheck is null ||
            ShowMembersPanelCheck is null ||
            ShowChatPanelCheck is null ||
            ShowEventNotificationsCheck is null ||
            OverlayInspectorCommunicationFriendEventsCheck is null ||
            OverlayInspectorCommunicationMessagePreviewCheck is null ||
            OverlayInspectorCommunicationDurationSlider is null ||
            EventNotifyMemberPresenceCheck is null ||
            EventNotifyMemberServerCheck is null ||
            EventNotifySameServerCheck is null ||
            EventNotifyShipChangeCheck is null ||
            EventNotifyLocationChangeCheck is null ||
            EventNotifyOnlineSummaryCheck is null ||
            EventNotifyPrimaryServerCheck is null ||
            OverlayEventMaxCountBox is null ||
            OverlayEventPinImportantCheck is null ||
            OverlayEventAnimationSpeedBox is null ||
            OverlayEventNotificationSideBox is null ||
            OverlayEventNotificationDurationSlider is null ||
            AutoThemeByShipCheck is null ||
            ShowCrosshairCheck is null ||
            CrosshairModeBox is null ||
            CrosshairThemeColorCheck is null ||
            CrosshairSizeSlider is null ||
            CrosshairThicknessSlider is null ||
            CrosshairGapSlider is null ||
            CrosshairCenterMarkCheck is null ||
            CrosshairCenterSizeSlider is null ||
            CrosshairOpacitySlider is null ||
            CrosshairOutlineOpacitySlider is null ||
            CrosshairColorBox is null ||
            CrosshairColorPickerButton is null ||
            OverlaySkinBox is null ||
            OverlayThemeBox is null ||
            OverlayTransitionEnabledCheck is null ||
            OverlaySkipTransitionInGameCheck is null ||
            OverlayTransitionFrameRateBox is null ||
            OverlayNightShadowBloomBox is null ||
            OverlayAnimationFrameRateBox is null ||
            OverlayAutoFocusGameWindowCheck is null ||
            OverlayAutoOpenOnGameStartCheck is null ||
            OverlayAutoOpenOnGameForegroundCheck is null ||
            OverlayAutoCloseOnGameBackgroundCheck is null)
        {
            return;
        }

        var mode = _overlaySettings.MemberNameMode;
        var crosshairMode = GetOverlayCrosshairModeFromComboBox(CrosshairModeBox);
        var overlaySkin = GetSelectedOverlaySkin();
        var squadStatusDisplayMode = _overlaySettings.SquadStatusDisplayMode;
        var hideOfflineMembers = _overlaySettings.HideOfflineMembers;
        var hideMemberOnlineStatus = _overlaySettings.EffectiveHideMemberOnlineStatus;
        var memberPriorityMode = _overlaySettings.MemberPriorityMode;
        var memberScopeMode = _overlaySettings.MemberScopeMode;

        _overlaySettings = ApplyOverlayFeatureLocks(new OverlayDisplaySettings(
            false,
            mode,
            hideOfflineMembers,
            _overlaySettings.HideSquadIcons,
            TrayModeCheck.IsChecked == true,
            _overlaySettings.Opacity,
            ShowNoticePanelCheck.IsChecked == true,
            ShowSquadsPanelCheck.IsChecked == true,
            false,
            ShowMembersPanelCheck.IsChecked == true,
            overlaySkin,
            OverlayThemeBox.SelectedIndex switch
            {
                1 => OverlayVisualTheme.Anvil,
                2 => OverlayVisualTheme.Drake,
                3 => OverlayVisualTheme.Argo,
                4 => OverlayVisualTheme.Musashi,
                5 => OverlayVisualTheme.Mirai,
                6 => OverlayVisualTheme.Crusader,
                7 => OverlayVisualTheme.Aegis,
                8 => OverlayVisualTheme.Rsi,
                9 => OverlayVisualTheme.Origin,
                10 => OverlayVisualTheme.Aopoa,
                11 => OverlayVisualTheme.Esperia,
                12 => OverlayVisualTheme.Gatac,
                _ => OverlayVisualTheme.Default
            },
            AutoThemeByShipCheck.IsChecked == true,
            ShowCrosshairCheck.IsChecked == true,
            crosshairMode,
            CrosshairThemeColorCheck.IsChecked == true,
            OverlayDisplaySettings.NormalizeCrosshairColor(CrosshairColorBox.Text),
            OverlayDisplaySettings.NormalizeCrosshairSize(CrosshairSizeSlider.Value),
            Math.Clamp(CrosshairThicknessSlider.Value, 1, 8),
            Math.Clamp(CrosshairOpacitySlider.Value / 100.0, 0.2, 1.0),
            CrosshairCenterMarkCheck.IsChecked == true,
            OverlayDisplaySettings.NormalizeCrosshairCenterMarkSize(CrosshairCenterSizeSlider.Value),
            OverlayDisplaySettings.NormalizeCrosshairGap(CrosshairGapSlider.Value),
            OverlayDisplaySettings.NormalizeCrosshairOutlineOpacity(CrosshairOutlineOpacitySlider.Value / 100.0),
            OverlayTransitionEnabledCheck.IsChecked == true,
            OverlaySkinCatalog.Get(overlaySkin).StartupTransition,
            OverlayAutoFocusGameWindowCheck.IsChecked == true,
            true,
            OverlayTransitionFrameRateBox.SelectedIndex switch
            {
                1 => OverlayStartupTransitionFrameRate.Fps45,
                2 => OverlayStartupTransitionFrameRate.Fps60,
                3 => OverlayStartupTransitionFrameRate.Fps120,
                _ => OverlayStartupTransitionFrameRate.Fps30
            },
            OverlayAutoOpenOnGameStartCheck.IsChecked == true,
            OverlayAutoOpenOnGameForegroundCheck.IsChecked == true,
            OverlayAutoCloseOnGameBackgroundCheck.IsChecked == true,
            ShowEventNotificationsCheck.IsChecked == true,
            _overlaySettings.EventNotificationSide,
            Math.Clamp(_overlaySettings.EventNotificationDurationSeconds, 1, 12),
            Math.Clamp(_overlaySettings.EventNotificationY, 0, 1),
            hideMemberOnlineStatus,
            squadStatusDisplayMode,
            _overlaySettings.HideSelfMember,
            memberPriorityMode,
            memberScopeMode,
            OverlayDisplaySettings.NormalizeMemberNameColumnRatio(_overlaySettings.MemberNameColumnRatio),
            BuildOverlayEventNotificationTypesFromControls(),
            GetOverlayEventNotificationCountFromComboBox(OverlayEventMaxCountBox),
            OverlayEventPinImportantCheck.IsChecked == true,
            GetOverlayEventNotificationAnimationSpeedFromComboBox(OverlayEventAnimationSpeedBox),
            _overlaySettings.EventNotificationDurations,
            GetOverlayNightShadowBloomFromComboBox(OverlayNightShadowBloomBox),
            GetOverlayAnimationFrameRateFromComboBox(OverlayAnimationFrameRateBox),
            _overlaySettings.ScenePreference,
            ShowChatPanelCheck.IsChecked == true,
            _overlaySettings.ChatDisplayMode,
            _overlaySettings.ChatSide,
            _overlaySettings.ChatMaxVisibleCount,
            _overlaySettings.ChatDurationSeconds,
            _overlaySettings.ChatShowSender,
            _overlaySettings.ChatShowTimestamp,
            _overlaySettings.ChatShowSystemMessages,
            _overlaySettings.ChatHideSelfMessages,
            _overlaySettings.ChatBarrageFontSize,
            _overlaySettings.ChatBarrageRegion,
            _overlaySettings.ChatBarrageDensity,
            _overlaySettings.ChatBarrageAvoidCenter,
            _overlaySettings.ChatTextEdgeStrength,
            OverlayInspectorCommunicationFriendEventsCheck.IsChecked == true,
            OverlayInspectorCommunicationMessagePreviewCheck.IsChecked == true,
            OverlayDisplaySettings.NormalizeCommunicationEventDuration(OverlayInspectorCommunicationDurationSlider.Value),
            _overlaySettings.FleetChatScope,
            _overlaySettings.EventNotificationTextOpacity,
            _overlaySettings.EventNotificationBackgroundOpacity,
            OverlaySkipTransitionInGameCheck.IsChecked == true,
            overlaySkin,
            OverlayDisplaySettings.NormalizeTextOpacity(OverlayTextOpacitySlider.Value / 100.0),
            OverlayDisplaySettings.NormalizeBackgroundOpacity(OverlayBackgroundOpacitySlider.Value / 100.0)));

        RefreshCrosshairSettingLabels();
        RefreshOverlayTransitionControls();
        RefreshOverlaySkinControls();
        RefreshOverlayEventNotificationControls();
        RefreshOverlayCommunicationEventControls();
        RefreshOverlayHiddenModuleLibrary();
        MarkOverlayEditorLayoutDirty();
        SaveCurrentConfig();
        RenderOverlayEditor();
        RefreshOverlayWindow();
    }

    private void ApplyOverlayExperiencePreset_Click(object sender, RoutedEventArgs e)
    {
        if (_isLoadingSettings || sender is not FrameworkElement { Tag: string preset })
        {
            return;
        }

        var historyState = CreateOverlayEditorHistoryState();
        var nextSettings = preset switch
        {
            "Smooth" => _overlaySettings with
            {
                EnableStartupTransition = true,
                StartupTransitionFrameRate = OverlayStartupTransitionFrameRate.Fps120,
                AnimationFrameRate = OverlayAnimationFrameRate.Fps120
            },
            "ReducedMotion" => _overlaySettings with
            {
                EnableStartupTransition = false,
                StartupTransitionFrameRate = OverlayStartupTransitionFrameRate.Fps60,
                AnimationFrameRate = OverlayAnimationFrameRate.Fps60
            },
            _ => _overlaySettings with
            {
                EnableStartupTransition = true,
                StartupTransitionFrameRate = OverlayStartupTransitionFrameRate.Fps60,
                AnimationFrameRate = OverlayAnimationFrameRate.Fps60
            }
        };

        if (nextSettings == _overlaySettings)
        {
            RefreshOverlayExperiencePresetStatus();
            return;
        }

        _overlaySettings = ApplyOverlayFeatureLocks(nextSettings);
        PushOverlayEditorUndoState(historyState);
        var wasLoadingSettings = _isLoadingSettings;
        _isLoadingSettings = true;
        try
        {
            ApplyOverlaySettingsToControls();
        }
        finally
        {
            _isLoadingSettings = wasLoadingSettings;
        }

        MarkOverlayEditorLayoutDirty();
        SaveCurrentConfig();
        RenderOverlayEditor();
        RefreshOverlayWindow();
    }

    private void RefreshOverlayExperiencePresetStatus()
    {
        if (OverlayExperiencePresetStatusText is null)
        {
            return;
        }

        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var profile = !_overlaySettings.EnableStartupTransition
            ? zh ? "减少动画" : "Reduced motion"
            : _overlaySettings.StartupTransitionFrameRate == OverlayStartupTransitionFrameRate.Fps120 &&
              _overlaySettings.AnimationFrameRate == OverlayAnimationFrameRate.Fps120
                ? zh ? "流畅优先" : "Smooth"
                : _overlaySettings.StartupTransitionFrameRate == OverlayStartupTransitionFrameRate.Fps60 &&
                  _overlaySettings.AnimationFrameRate == OverlayAnimationFrameRate.Fps60
                    ? zh ? "均衡" : "Balanced"
                    : zh ? "自定义" : "Custom";
        OverlayExperiencePresetStatusText.Text = zh ? $"当前：{profile}" : $"Current: {profile}";
    }

    private static OverlayCrosshairMode GetOverlayCrosshairModeFromComboBox(System.Windows.Controls.ComboBox? comboBox)
    {
        return comboBox?.SelectedItem is ComboBoxItem { Tag: string tag } &&
               Enum.TryParse<OverlayCrosshairMode>(tag, out var parsed)
            ? OverlayDisplaySettings.NormalizeCrosshairMode(parsed)
            : OverlayCrosshairMode.Cross;
    }

    private static string FormatOverlayCrosshairMode(OverlayCrosshairMode mode, bool zh)
    {
        return OverlayDisplaySettings.NormalizeCrosshairMode(mode) switch
        {
            OverlayCrosshairMode.Dot => zh ? "中心点" : "Dot",
            OverlayCrosshairMode.Circle => zh ? "圆环" : "Circle",
            OverlayCrosshairMode.TShape => zh ? "T 型" : "T-shape",
            _ => zh ? "十字" : "Cross"
        };
    }

    private static void ApplyOverlayCrosshairModeLanguage(System.Windows.Controls.ComboBox? comboBox, bool zh)
    {
        if (comboBox is null)
        {
            return;
        }

        foreach (var item in comboBox.Items.OfType<ComboBoxItem>())
        {
            if (!Enum.TryParse<OverlayCrosshairMode>(item.Tag?.ToString(), out var mode))
            {
                continue;
            }

            item.Content = FormatOverlayCrosshairMode(mode, zh);
        }
    }

    private void RefreshCrosshairModeControlAvailability()
    {
        if (CrosshairModeBox is null)
        {
            return;
        }

        var mode = GetOverlayCrosshairModeFromComboBox(CrosshairModeBox);
        var enabled = ShowCrosshairCheck?.IsChecked == true;
        var isDot = mode == OverlayCrosshairMode.Dot;
        var usesGap = mode is OverlayCrosshairMode.Cross or OverlayCrosshairMode.TShape;
        SetCrosshairControlState(CrosshairModeBox, enabled);
        SetCrosshairControlState(CrosshairSizeSlider, enabled && !isDot);
        SetCrosshairControlState(CrosshairThicknessSlider, enabled && !isDot);
        SetCrosshairControlState(CrosshairGapSlider, enabled && usesGap);
        SetCrosshairControlState(CrosshairCenterMarkCheck, enabled && !isDot);
        SetCrosshairControlState(
            CrosshairCenterSizeSlider,
            enabled && (isDot || CrosshairCenterMarkCheck?.IsChecked == true));

        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        if (CrosshairSizeLabel is not null)
        {
            CrosshairSizeLabel.Text = mode == OverlayCrosshairMode.Circle
                ? zh ? "圆环直径" : "RING DIAMETER"
                : zh ? "整体大小" : "OVERALL SIZE";
        }

        if (CrosshairCenterMarkCheck is not null)
        {
            CrosshairCenterMarkCheck.Content = zh ? "显示中心点" : "Show center dot";
        }

        if (CrosshairCenterSizeLabel is not null)
        {
            CrosshairCenterSizeLabel.Text = isDot
                ? zh ? "点大小" : "DOT SIZE"
                : zh ? "中心点大小" : "CENTER DOT SIZE";
        }

        RefreshOverlayInspectorCrosshairModeAvailability(mode, enabled);
    }

    private static void SetCrosshairControlState(UIElement? control, bool enabled)
    {
        if (control is null)
        {
            return;
        }

        control.IsEnabled = enabled;
        control.Opacity = enabled ? 1.0 : 0.48;
    }

    private OverlayEventNotificationTypes BuildOverlayEventNotificationTypesFromControls()
    {
        var types = OverlayEventNotificationTypes.None;
        if (EventNotifyMemberPresenceCheck?.IsChecked == true)
        {
            types |= OverlayEventNotificationTypes.MemberPresence;
        }

        if (EventNotifyMemberServerCheck?.IsChecked == true)
        {
            types |= OverlayEventNotificationTypes.MemberServer;
        }

        if (EventNotifySameServerCheck?.IsChecked == true)
        {
            types |= OverlayEventNotificationTypes.SameServer;
        }

        if (EventNotifyShipChangeCheck?.IsChecked == true)
        {
            types |= OverlayEventNotificationTypes.ShipChange;
        }

        if (EventNotifyLocationChangeCheck?.IsChecked == true)
        {
            types |= OverlayEventNotificationTypes.LocationChange;
        }

        if (EventNotifyOnlineSummaryCheck?.IsChecked == true)
        {
            types |= OverlayEventNotificationTypes.OnlineSummary;
        }

        if (EventNotifyPrimaryServerCheck?.IsChecked == true)
        {
            types |= OverlayEventNotificationTypes.PrimaryServer;
        }

        if (EventNotifyDeathAndRespawnCheck?.IsChecked == true)
        {
            types |= OverlayEventNotificationTypes.DeathAndRespawn;
        }

        if (EventNotifyLocalPlayReminderCheck?.IsChecked == true)
        {
            types |= OverlayEventNotificationTypes.LocalPlayReminder;
        }

        return OverlayDisplaySettings.NormalizeEventNotificationTypes(types);
    }

    private static int GetOverlayEventNotificationCountFromComboBox(System.Windows.Controls.ComboBox comboBox)
    {
        if (comboBox.SelectedItem is ComboBoxItem item &&
            int.TryParse(item.Tag?.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var count))
        {
            return OverlayDisplaySettings.NormalizeEventNotificationMaxVisibleCount(count);
        }

        return OverlayDisplaySettings.Default.EventNotificationMaxVisibleCount;
    }

    private static OverlayEventNotificationAnimationSpeed GetOverlayEventNotificationAnimationSpeedFromComboBox(System.Windows.Controls.ComboBox comboBox)
    {
        return comboBox.SelectedItem is ComboBoxItem item &&
               Enum.TryParse<OverlayEventNotificationAnimationSpeed>(item.Tag?.ToString(), out var speed)
            ? speed
            : OverlayDisplaySettings.Default.EventNotificationAnimationSpeed;
    }

    private static OverlayNightShadowBloom GetOverlayNightShadowBloomFromComboBox(System.Windows.Controls.ComboBox comboBox)
    {
        return comboBox.SelectedItem is ComboBoxItem item &&
               Enum.TryParse<OverlayNightShadowBloom>(item.Tag?.ToString(), out var bloom)
            ? bloom
            : OverlayDisplaySettings.Default.NightShadowBloom;
    }

    private static OverlayAnimationFrameRate GetOverlayAnimationFrameRateFromComboBox(System.Windows.Controls.ComboBox comboBox)
    {
        return comboBox.SelectedItem is ComboBoxItem item &&
               Enum.TryParse<OverlayAnimationFrameRate>(item.Tag?.ToString(), out var frameRate)
            ? frameRate
            : OverlayDisplaySettings.Default.AnimationFrameRate;
    }

    private void RefreshOverlayEventDurationOverrideControls()
    {
        var enabled = ShowEventNotificationsCheck?.IsChecked == true;
        BuildOverlayEventDurationOverrideControls(OverlayEventDurationOverridesPanel, enabled, false);
    }

    private void BuildOverlayEventDurationOverrideControls(StackPanel? panel, bool enabled, bool compact)
    {
        if (panel is null)
        {
            return;
        }

        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        panel.Children.Clear();
        panel.IsEnabled = enabled;
        panel.Opacity = enabled ? 1.0 : 0.58;

        var title = new TextBlock
        {
            Text = zh ? "事件停留时间（秒）" : "EVENT DURATION (SEC)",
            Margin = new Thickness(0, 0, 0, 6)
        };
        if (TryFindResource("HudCaptionText") is Style captionStyle)
        {
            title.Style = captionStyle;
        }

        panel.Children.Add(title);

        var hint = new TextBlock
        {
            Text = zh
                ? "留空跟随默认时长；重要事件常驻开启时不倒计时。"
                : "Blank follows the default duration. Pinned important events do not count down.",
            FontSize = 11,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 8)
        };
        if (TryFindResource("MutedTextBrush") is System.Windows.Media.Brush mutedBrush)
        {
            hint.Foreground = mutedBrush;
        }

        panel.Children.Add(hint);

        foreach (var eventType in OverlayEventDurationOrder)
        {
            var grid = new Grid
            {
                Margin = new Thickness(0, 0, 0, 7)
            };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(compact ? 76 : 88) });

            var label = new TextBlock
            {
                Text = GetOverlayEventNotificationTypeLabel(eventType, zh),
                VerticalAlignment = VerticalAlignment.Center,
                TextTrimming = TextTrimming.CharacterEllipsis,
                ToolTip = GetOverlayEventNotificationTypeLabel(eventType, zh)
            };
            if (TryFindResource("HudCaptionText") is Style rowCaptionStyle)
            {
                label.Style = rowCaptionStyle;
            }

            var overrideSeconds = _overlaySettings.EventNotificationDurations.Get(eventType);
            var textBox = new System.Windows.Controls.TextBox
            {
                Text = overrideSeconds > 0
                    ? overrideSeconds.ToString("0.##", CultureInfo.InvariantCulture)
                    : "",
                Tag = eventType,
                Height = 28,
                MinWidth = compact ? 66 : 78,
                VerticalContentAlignment = VerticalAlignment.Center,
                HorizontalContentAlignment = HorizontalAlignment.Right,
                ToolTip = zh
                    ? $"留空跟随默认 {_overlaySettings.EventNotificationDurationSeconds:0.#} 秒"
                    : $"Blank follows default {_overlaySettings.EventNotificationDurationSeconds:0.#}s"
            };
            textBox.LostFocus += OverlayEventDurationOverrideBox_LostFocus;
            textBox.KeyDown += OverlayEventDurationOverrideBox_KeyDown;

            Grid.SetColumn(label, 0);
            Grid.SetColumn(textBox, 1);
            grid.Children.Add(label);
            grid.Children.Add(textBox);
            panel.Children.Add(grid);
        }
    }

    private static string GetOverlayEventNotificationTypeLabel(OverlayEventNotificationTypes eventType, bool zh)
    {
        return eventType switch
        {
            OverlayEventNotificationTypes.MemberPresence => zh ? "成员上线/离线" : "Member online/offline",
            OverlayEventNotificationTypes.MemberServer => zh ? "成员进出服务器" : "Member enters/leaves server",
            OverlayEventNotificationTypes.SameServer => zh ? "同服提醒与概况" : "Same-server alerts",
            OverlayEventNotificationTypes.ShipChange => zh ? "飞船变化" : "Ship changes",
            OverlayEventNotificationTypes.LocationChange => zh ? "地点变化" : "Location changes",
            OverlayEventNotificationTypes.OnlineSummary => zh ? "在线人数变化" : "Online count changes",
            OverlayEventNotificationTypes.PrimaryServer => zh ? "主服务器变化" : "Primary server changes",
            OverlayEventNotificationTypes.DeathAndRespawn => zh ? "倒地 / 死亡 / 获救 / 重生" : "Downed / death / revived / respawn",
            OverlayEventNotificationTypes.LocalPlayReminder => zh ? "连续游戏提醒" : "Continuous play reminder",
            _ => zh ? "事件" : "Event"
        };
    }

    private void OverlayEventDurationOverrideBox_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key != Key.Enter)
        {
            return;
        }

        CommitOverlayEventDurationOverride(sender as System.Windows.Controls.TextBox);
        e.Handled = true;
        Keyboard.ClearFocus();
    }

    private void OverlayEventDurationOverrideBox_LostFocus(object sender, RoutedEventArgs e)
    {
        CommitOverlayEventDurationOverride(sender as System.Windows.Controls.TextBox);
    }

    private void CommitOverlayEventDurationOverride(System.Windows.Controls.TextBox? textBox)
    {
        if (_isLoadingSettings ||
            textBox?.Tag is not OverlayEventNotificationTypes eventType)
        {
            return;
        }

        var text = textBox.Text.Trim();
        var seconds = 0d;
        if (!string.IsNullOrWhiteSpace(text) &&
            !double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out seconds) &&
            !double.TryParse(text, NumberStyles.Float, CultureInfo.CurrentCulture, out seconds))
        {
            RefreshOverlayEventDurationOverrideControls();
            return;
        }

        seconds = string.IsNullOrWhiteSpace(text)
            ? OverlayEventNotificationDurationOverrides.InheritDefaultSeconds
            : OverlayEventNotificationDurationOverrides.NormalizeOverrideOrInherit(seconds);
        var nextDurations = _overlaySettings.EventNotificationDurations.Set(eventType, seconds);
        if (Equals(nextDurations, _overlaySettings.EventNotificationDurations))
        {
            RefreshOverlayEventDurationOverrideControls();
            return;
        }

        _overlaySettings = _overlaySettings with { EventNotificationDurations = nextDurations };
        MarkOverlayEditorLayoutDirty();
        SaveCurrentConfig();
        RenderOverlayEditor();
        RefreshOverlayWindow();
        RefreshOverlayEventDurationOverrideControls();
        RefreshOverlayInspector();
    }

    private void ApplyOverlayEventNotificationTypeChecks(OverlayEventNotificationTypes types)
    {
        types = OverlayDisplaySettings.NormalizeEventNotificationTypes(types);
        if (EventNotifyMemberPresenceCheck is not null)
        {
            EventNotifyMemberPresenceCheck.IsChecked = types.HasFlag(OverlayEventNotificationTypes.MemberPresence);
        }

        if (EventNotifyMemberServerCheck is not null)
        {
            EventNotifyMemberServerCheck.IsChecked = types.HasFlag(OverlayEventNotificationTypes.MemberServer);
        }

        if (EventNotifySameServerCheck is not null)
        {
            EventNotifySameServerCheck.IsChecked = types.HasFlag(OverlayEventNotificationTypes.SameServer);
        }

        if (EventNotifyShipChangeCheck is not null)
        {
            EventNotifyShipChangeCheck.IsChecked = types.HasFlag(OverlayEventNotificationTypes.ShipChange);
        }

        if (EventNotifyLocationChangeCheck is not null)
        {
            EventNotifyLocationChangeCheck.IsChecked = types.HasFlag(OverlayEventNotificationTypes.LocationChange);
        }

        if (EventNotifyOnlineSummaryCheck is not null)
        {
            EventNotifyOnlineSummaryCheck.IsChecked = types.HasFlag(OverlayEventNotificationTypes.OnlineSummary);
        }

        if (EventNotifyPrimaryServerCheck is not null)
        {
            EventNotifyPrimaryServerCheck.IsChecked = types.HasFlag(OverlayEventNotificationTypes.PrimaryServer);
        }

        if (EventNotifyDeathAndRespawnCheck is not null)
        {
            EventNotifyDeathAndRespawnCheck.IsChecked = types.HasFlag(OverlayEventNotificationTypes.DeathAndRespawn);
        }

        if (EventNotifyLocalPlayReminderCheck is not null)
        {
            EventNotifyLocalPlayReminderCheck.IsChecked = types.HasFlag(OverlayEventNotificationTypes.LocalPlayReminder);
        }
    }

    private IEnumerable<System.Windows.Controls.CheckBox> GetOverlayEventNotificationTypeCheckBoxes()
    {
        if (EventNotifyMemberPresenceCheck is not null)
        {
            yield return EventNotifyMemberPresenceCheck;
        }

        if (EventNotifyMemberServerCheck is not null)
        {
            yield return EventNotifyMemberServerCheck;
        }

        if (EventNotifySameServerCheck is not null)
        {
            yield return EventNotifySameServerCheck;
        }

        if (EventNotifyShipChangeCheck is not null)
        {
            yield return EventNotifyShipChangeCheck;
        }

        if (EventNotifyLocationChangeCheck is not null)
        {
            yield return EventNotifyLocationChangeCheck;
        }

        if (EventNotifyOnlineSummaryCheck is not null)
        {
            yield return EventNotifyOnlineSummaryCheck;
        }

        if (EventNotifyPrimaryServerCheck is not null)
        {
            yield return EventNotifyPrimaryServerCheck;
        }

        if (EventNotifyDeathAndRespawnCheck is not null)
        {
            yield return EventNotifyDeathAndRespawnCheck;
        }

        if (EventNotifyLocalPlayReminderCheck is not null)
        {
            yield return EventNotifyLocalPlayReminderCheck;
        }
    }

    private void CrosshairSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        RefreshCrosshairSettingLabels();

        if (_isLoadingSettings)
        {
            return;
        }

        OverlaySetting_Changed(sender, new RoutedEventArgs());
    }

    private void CrosshairColorBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        RefreshCrosshairSettingLabels();

        if (_isLoadingSettings)
        {
            return;
        }

        OverlaySetting_Changed(sender, new RoutedEventArgs());
    }

    private void CrosshairColorPreview_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        CrosshairColorPickerButton_Click(sender, e);
    }

    private void CrosshairColorPickerButton_Click(object sender, RoutedEventArgs e)
    {
        if (CrosshairColorBox is null ||
            CrosshairThemeColorCheck is null)
        {
            return;
        }

        var currentColor = TryParseHexColor(CrosshairColorBox.Text, out var parsedColor)
            ? parsedColor
            : Color.FromRgb(235, 247, 255);

        var dialog = new StarBridgeColorPickerWindow(
            currentColor,
            _language.Equals("zh", StringComparison.OrdinalIgnoreCase))
        {
            Owner = this
        };

        if (dialog.ShowDialog() != true)
        {
            return;
        }

        var selectedColor = $"#{dialog.SelectedColor.R:X2}{dialog.SelectedColor.G:X2}{dialog.SelectedColor.B:X2}";
        var wasLoading = _isLoadingSettings;
        _isLoadingSettings = true;
        CrosshairThemeColorCheck.IsChecked = false;
        CrosshairColorBox.Text = selectedColor;
        _isLoadingSettings = wasLoading;

        RefreshCrosshairSettingLabels();

        if (!wasLoading)
        {
            OverlaySetting_Changed(sender, new RoutedEventArgs());
        }
    }

    private void OverlayOpacitySlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (OverlayTextOpacityValueText is not null && OverlayTextOpacitySlider is not null)
        {
            OverlayTextOpacityValueText.Text = $"{Math.Round(OverlayTextOpacitySlider.Value)}%";
        }

        if (OverlayBackgroundOpacityValueText is not null && OverlayBackgroundOpacitySlider is not null)
        {
            OverlayBackgroundOpacityValueText.Text = $"{Math.Round(OverlayBackgroundOpacitySlider.Value)}%";
        }

        if (_isLoadingSettings)
        {
            return;
        }

        OverlaySetting_Changed(sender, new RoutedEventArgs());
    }

    private void OverlayThemeBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isLoadingSettings)
        {
            return;
        }

        OverlaySetting_Changed(sender, new RoutedEventArgs());
    }

    private void OverlaySkinBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isLoadingSettings ||
            OverlaySkinBox.SelectedItem is not ComboBoxItem { Tag: OverlaySkin skin })
        {
            return;
        }

        if (!CanUseOverlaySkin(skin))
        {
            RefreshOverlaySkinControls();
            return;
        }

        SelectOverlaySkin(skin);
        OverlaySetting_Changed(sender, new RoutedEventArgs());
    }

    private void OverlayNightShadowBloomBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isLoadingSettings)
        {
            return;
        }

        OverlaySetting_Changed(sender, new RoutedEventArgs());
    }

    private void OverlayPresetBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isLoadingSettings ||
            OverlayPresetBox.SelectedItem is not ComboBoxItem { Tag: string preset })
        {
            return;
        }

        LoadOverlayPreset(preset);
    }

    private void RenameOverlayPreset_Click(object sender, RoutedEventArgs e)
    {
        var currentIndex = _overlayPresetEntries.FindIndex(entry =>
            entry.Id.Equals(_activeOverlayPreset, StringComparison.OrdinalIgnoreCase));
        if (currentIndex < 0)
        {
            return;
        }

        var current = _overlayPresetEntries[currentIndex];
        var requestedName = StarBridgeTextInputDialog.Show(
            this,
            "重命名预设",
            "输入新的预设名称。",
            current.Name);
        var name = CleanOverlayPresetName(requestedName);
        if (name is null)
        {
            return;
        }

        _overlayPresetEntries[currentIndex] = current with { Name = name };
        SaveOverlayPresetManifest();
        RefreshOverlayPresetBoxItems();
        RefreshOverlayOverviewSummary();
        SaveCurrentConfig();
    }

    private void DuplicateOverlayPreset_Click(object sender, RoutedEventArgs e)
    {
        var currentName = GetOverlayPresetDisplayName(_activeOverlayPreset);
        var requestedName = StarBridgeTextInputDialog.Show(
            this,
            "复制预设",
            "为复制出的预设输入名称。",
            CreateUniqueOverlayPresetName($"{currentName} 副本"));
        var cleanName = CleanOverlayPresetName(requestedName);
        if (cleanName is null)
        {
            return;
        }

        var id = CreateOverlayPresetId();
        var name = CreateUniqueOverlayPresetName(cleanName);
        DesktopAppConfig.SaveOverlayPresetSettings(id, _overlaySettings.Serialize());
        DesktopAppConfig.SaveOverlayPresetLayout(id, SerializeOverlayLayout());
        _overlayPresetEntries.Add(new OverlayPresetEntry(id, name));
        SaveOverlayPresetManifest();
        LoadOverlayPreset(id);
    }

    private void DeleteOverlayPreset_Click(object sender, RoutedEventArgs e)
    {
        if (_overlayPresetEntries.Count <= 1)
        {
            StarBridgeMessageBox.Show(
                this,
            "至少需要保留一个浮层预设。",
                "无法删除预设",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            return;
        }

        var current = _overlayPresetEntries.FirstOrDefault(entry =>
            entry.Id.Equals(_activeOverlayPreset, StringComparison.OrdinalIgnoreCase));
        if (current is null)
        {
            return;
        }

        var result = StarBridgeMessageBox.Show(
            this,
            $"删除预设“{current.Name}”？此操作只会删除这个预设，不会影响其它预设。",
            "删除预设",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);
        if (result != MessageBoxResult.Yes)
        {
            return;
        }

        DesktopAppConfig.DeleteOverlayPreset(current.Id);
        _overlayPresetEntries.RemoveAll(entry => entry.Id.Equals(current.Id, StringComparison.OrdinalIgnoreCase));
        SaveOverlayPresetManifest();
        LoadOverlayPreset(_overlayPresetEntries[0].Id);
    }

    private void ImportOverlayPreset_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "导入浮层预设",
            Filter = "星海舰桥浮层预设 (*.sbop;*.json)|*.sbop;*.json|所有文件 (*.*)|*.*"
        };
        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        try
        {
            var package = JsonSerializer.Deserialize<OverlayPresetPackage>(File.ReadAllText(dialog.FileName));
            if (package is null ||
                string.IsNullOrWhiteSpace(package.Settings) ||
                string.IsNullOrWhiteSpace(package.Layout))
            {
                throw new InvalidDataException("预设文件内容不完整。");
            }

            var requestedSettings = OverlayDisplaySettings.Parse(package.Settings);
            var importedResolution = OverlaySkinCatalog.Resolve(
                requestedSettings,
                IsLoggedIn ? EnumerateActiveOverlayEntitlements() : []);
            var importedSettings = ApplyOverlayFeatureLocks(requestedSettings).Serialize();
            var importedLayout = OverlayLayoutItem.ParseMany(package.Layout).ToArray();
            var importedLayoutPayload = SerializeOverlayLayout(importedLayout.Length == 0
                ? CreateDefaultOverlayLayout(OverlayPresetDefault)
                : importedLayout);
            var baseName = CleanOverlayPresetName(package.Name) ??
                CleanOverlayPresetName(Path.GetFileNameWithoutExtension(dialog.FileName)) ??
                "导入预设";
            var id = CreateOverlayPresetId();
            var name = CreateUniqueOverlayPresetName(baseName);
            DesktopAppConfig.SaveOverlayPresetSettings(id, importedSettings);
            DesktopAppConfig.SaveOverlayPresetLayout(id, importedLayoutPayload);
            _overlayPresetEntries.Add(new OverlayPresetEntry(id, name));
            SaveOverlayPresetManifest();
            LoadOverlayPreset(id);
            if (!importedResolution.IsAvailable)
            {
                var requestedProfile = OverlaySkinCatalog.Get(importedResolution.RequestedSkin);
                var fallbackProfile = OverlaySkinCatalog.Get(importedResolution.EffectiveSkin);
                var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
                StarBridgeMessageBox.Show(
                    this,
                    zh
                        ? $"布局已导入，但“{requestedProfile.DisplayNameZh}”外观尚未解锁。本次先使用“{fallbackProfile.DisplayNameZh}”；原始外观请求已保留，获得资格后会自动恢复。"
                        : $"The layout was imported, but {requestedProfile.DisplayNameEn} is still locked. {fallbackProfile.DisplayNameEn} is active for now; the original appearance request is preserved and will restore after unlock.",
                    zh ? "外观尚未解锁" : "Appearance locked",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
            }
        }
        catch (Exception ex)
        {
            StarBridgeMessageBox.Show(
                this,
                UserFacingError.Describe(ex, "预设未能导入，请确认文件有效后重试。"),
                "导入失败",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }

    private void ExportOverlayPreset_Click(object sender, RoutedEventArgs e)
    {
        var presetName = GetOverlayPresetDisplayName(_activeOverlayPreset);
        var dialog = new SaveFileDialog
        {
            Title = "导出浮层预设",
            FileName = $"{presetName}.sbop",
            Filter = "星海舰桥浮层预设 (*.sbop)|*.sbop|JSON (*.json)|*.json|所有文件 (*.*)|*.*"
        };
        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        try
        {
            var package = new OverlayPresetPackage(
                1,
                presetName,
                _overlaySettings.Serialize(),
                SerializeOverlayLayout());
            File.WriteAllText(dialog.FileName, JsonSerializer.Serialize(package, OverlayPresetJsonOptions));
            StarBridgeMessageBox.Show(
                this,
                "预设已导出，可以分享给其他 StarBridge 用户使用。",
                "导出完成",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            StarBridgeMessageBox.Show(
                this,
                UserFacingError.Describe(ex, "预设未能导出，请检查保存位置后重试。"),
                "导出失败",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }
}
