using System.Globalization;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using WpfBrush = System.Windows.Media.Brush;
using WpfColor = System.Windows.Media.Color;
using WpfPoint = System.Windows.Point;

namespace StarBridge.Desktop;

internal enum InGameMenuAction
{
    ToggleInformationOverlay,
    OpenFleet,
    OpenFriends,
    OpenChat,
    OpenRooms,
    OpenOverlaySettings,
    CaptureFullscreen,
    OpenImage,
    OpenBrowser
}

internal sealed class InGameMenuActionRequestedEventArgs(InGameMenuAction action) : EventArgs
{
    internal InGameMenuAction Action { get; } = action;
}

internal sealed record InGameMenuSnapshot(
    string DisplayName,
    string Presence,
    string SceneTitle,
    string SceneDetail,
    string SceneMode,
    int MemberCount,
    string Ship,
    string Location,
    string Server,
    int FriendAlertCount = 0,
    int MessageUnreadCount = 0,
    int RoomAlertCount = 0);

public partial class InGameMenuWindow : Window
{
    private static readonly CultureInfo ChineseCulture =
        CultureInfo.GetCultureInfo("zh-CN");

    private readonly DispatcherTimer _noticeResetTimer = new()
    {
        Interval = TimeSpan.FromSeconds(4.5)
    };
    private readonly DispatcherTimer _clockTimer = new()
    {
        Interval = TimeSpan.FromMinutes(1)
    };
    private readonly BitmapCache _toolMoveCache = new BitmapCache(1)
    {
        EnableClearType = false,
        SnapsToDevicePixels = false
    };
    private InGameMenuSnapshot? _lastSnapshot;
    private Rect _lastSurfaceBounds = Rect.Empty;
    private InGameMenuSnapshot? _pendingSnapshot;
    private Rect? _pendingSurfaceBounds;
    private bool _informationOverlayEnabled;
    private string _informationOverlayHotkey = "";
    private bool _toolMoveActive;
    private bool _contentRendered;
    private bool _preparingFirstOpen;
    private bool _revealOnContentRendered;
    private bool _menuOpen;
    private InGameMenuLayoutPreset _layoutPreset =
        InGameMenuLayoutPreset.BottomDock;
    private InGameMenuSettings _settings = InGameMenuSettings.Default;

    internal event EventHandler<InGameMenuActionRequestedEventArgs>? ActionRequested;
    internal event EventHandler? MenuCloseRequested;
    internal event EventHandler? MenuDeactivated;

    internal InGameMenuWindow()
    {
        InitializeComponent();
        InGameMenuVisualContext.Apply(this);
        Activated += Window_Activated;
        IsVisibleChanged += Window_IsVisibleChanged;
        _clockTimer.Tick += (_, _) => RefreshLocalClock();
        _noticeResetTimer.Tick += (_, _) =>
        {
            if (_toolMoveActive)
            {
                _noticeResetTimer.Stop();
                _noticeResetTimer.Start();
                return;
            }

            _noticeResetTimer.Stop();
            NoticeText.Text = "菜单浮层已就绪";
            Controls.InGameLoadingPresentation.Apply(NoticeLoadingIndicator, false);
            Controls.InGameLoadingPresentation.Apply(NoticePopupLoadingIndicator, false);
            NoticePopup.Visibility = Visibility.Collapsed;
        };
        RefreshLocalClock();
        _clockTimer.Start();
        ApplyLayoutPreset(_layoutPreset);
    }

    internal bool IsMenuOpen => _menuOpen;

    internal bool IsPreparedForFirstOpen =>
        _contentRendered &&
        !_preparingFirstOpen &&
        !_menuOpen &&
        IsVisible &&
        Opacity <= 0;

    internal void PrepareForFirstOpen()
    {
        if (_contentRendered || IsVisible)
        {
            return;
        }

        _preparingFirstOpen = true;
        _revealOnContentRendered = false;
        _menuOpen = false;
        ShowActivated = false;
        Focusable = false;
        IsHitTestVisible = false;
        InGameToolWindowBehavior.SetClickThrough(this, enabled: true);
        BeginAnimation(OpacityProperty, null);
        Opacity = 0;
        Show();
    }

    internal void ShowForMenu()
    {
        _menuOpen = true;
        _preparingFirstOpen = false;
        ShowActivated = true;
        Focusable = true;
        IsHitTestVisible = true;
        InGameToolWindowBehavior.SetClickThrough(this, enabled: false);
        _revealOnContentRendered = !_contentRendered;

        if (_contentRendered)
        {
            PlayOpenTransition();
        }
        else
        {
            BeginAnimation(OpacityProperty, null);
            Opacity = 0;
        }

        if (!IsVisible)
        {
            Show();
        }

        TakeInputOwnership();
    }

    internal void TakeInputOwnership()
    {
        if (!_menuOpen || !IsVisible)
        {
            return;
        }

        ShowActivated = true;
        _ = InGameToolWindowBehavior.TakeForegroundInput(this);
        CaptureMouseInput();
    }

    internal void ApplySnapshot(InGameMenuSnapshot snapshot)
    {
        if (_toolMoveActive)
        {
            _pendingSnapshot = snapshot;
            return;
        }

        _pendingSnapshot = null;
        if (_lastSnapshot == snapshot)
        {
            return;
        }

        _lastSnapshot = snapshot;
        PresenceText.Text = Normalize(snapshot.Presence, "应用在线");
        SceneTitleText.Text = Normalize(snapshot.SceneTitle, "当前协作");
        SceneTitleText.ToolTip = Normalize(snapshot.SceneDetail, "等待协作信息同步");
        MemberCountText.Text = $"{Math.Max(0, snapshot.MemberCount)} 人";
        ShipText.Text = Normalize(snapshot.Ship, "等待识别");
        LocationText.Text = _settings.EffectiveShowExactLocation
            ? Normalize(snapshot.Location, "等待识别")
            : "已隐藏";
        ServerText.Text = Normalize(snapshot.Server, "等待连接");
        ApplyUnreadBadge(
            FriendsUnreadBadge,
            FriendsUnreadText,
            snapshot.FriendAlertCount);
        ApplyUnreadBadge(
            ChatUnreadBadge,
            ChatUnreadText,
            snapshot.MessageUnreadCount);
        ApplyUnreadBadge(
            RoomsUnreadBadge,
            RoomsUnreadText,
            snapshot.RoomAlertCount);
    }

    internal void ApplySettings(InGameMenuSettings settings)
    {
        var normalized = settings.Normalize();
        _settings = normalized;
        var shortcutText =
            normalized.EnableHotkey &&
            OverlayHotkeyBindingPolicy.TryParse(
                normalized.Hotkey,
                out var shortcut)
                ? shortcut.DisplayText
                : "";
        MenuReturnHotkeyText.Text = string.IsNullOrWhiteSpace(shortcutText)
            ? "ESC"
            : $"{shortcutText.ToUpperInvariant()} / ESC";
        MenuFooterHotkeyText.Text = string.IsNullOrWhiteSpace(shortcutText)
            ? "按 Esc 返回游戏 · 工具窗口会随菜单自动隐藏"
            : $"按 {shortcutText} 或 Esc 返回游戏 · 工具窗口会随菜单自动隐藏";
        ApplyLayoutPreset(normalized.LayoutPreset);
        ApplyToolbarSettings(normalized);
        ApplyContextSettings(normalized);
        ApplyAppearanceSettings(normalized);
        if (_lastSnapshot is { } snapshot)
        {
            _lastSnapshot = null;
            ApplySnapshot(snapshot);
        }

        RefreshLocalClock();
    }

    private void ApplyToolbarSettings(InGameMenuSettings settings)
    {
        var buttons = new Dictionary<InGameMenuTool, System.Windows.Controls.Button>
        {
            [InGameMenuTool.InformationOverlay] = InformationOverlayDockButton,
            [InGameMenuTool.Fleet] = FleetDockButton,
            [InGameMenuTool.Friends] = FriendsDockButton,
            [InGameMenuTool.Chat] = ChatDockButton,
            [InGameMenuTool.Rooms] = RoomsDockButton,
            [InGameMenuTool.Screenshot] = ScreenshotDockButton,
            [InGameMenuTool.Image] = ImageDockButton,
            [InGameMenuTool.Browser] = BrowserDockButton
        };
        var labels = new[]
        {
            InformationOverlayDockLabel,
            FleetDockLabel,
            FriendsDockLabel,
            ChatDockLabel,
            RoomsDockLabel,
            ScreenshotDockLabel,
            ImageDockLabel,
            BrowserDockLabel
        };
        var (width, height, margin) = settings.ToolbarDensity switch
        {
            InGameMenuToolbarDensity.Compact => (66d, 60d, 2d),
            InGameMenuToolbarDensity.Comfortable => (94d, 82d, 5d),
            _ => (82d, 76d, 4d)
        };
        foreach (var button in buttons.Values)
        {
            button.Width = width;
            button.Height = height;
            button.Margin = new Thickness(margin, 0, margin, 0);
        }

        var showLabels =
            settings.ToolLabelMode != InGameMenuToolLabelMode.IconsOnly;
        foreach (var label in labels)
        {
            label.Visibility = showLabels
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        PrimaryDockPanel.Children.Clear();
        var ordered = settings.ResolveToolOrder()
            .Where(settings.IsToolVisible)
            .ToArray();
        var dividerAdded = false;
        foreach (var tool in ordered)
        {
            if (!dividerAdded &&
                (tool is InGameMenuTool.Screenshot or
                    InGameMenuTool.Image or
                    InGameMenuTool.Browser) &&
                PrimaryDockPanel.Children.Count > 0)
            {
                PrimaryDockPanel.Children.Add(DockGroupDivider);
                dividerAdded = true;
            }

            PrimaryDockPanel.Children.Add(buttons[tool]);
        }
    }

    private void ApplyContextSettings(InGameMenuSettings settings)
    {
        MenuContextPanel.Visibility = settings.ShowContextBar
            ? Visibility.Visible
            : Visibility.Collapsed;
        SceneContextPanel.Visibility = settings.ShowScene
            ? Visibility.Visible
            : Visibility.Collapsed;
        MemberContextPanel.Visibility = settings.ShowMemberCount
            ? Visibility.Visible
            : Visibility.Collapsed;
        ShipContextPanel.Visibility = settings.ShowShip
            ? Visibility.Visible
            : Visibility.Collapsed;
        LocationContextPanel.Visibility = settings.ShowLocation
            ? Visibility.Visible
            : Visibility.Collapsed;
        ServerContextPanel.Visibility = settings.ShowServer
            ? Visibility.Visible
            : Visibility.Collapsed;
        TimeInformationPanel.Visibility =
            settings.ShowClock ||
            settings.ShowDate ||
            settings.ShowPresence
                ? Visibility.Visible
                : Visibility.Collapsed;
        LocalTimeText.Visibility = settings.ShowClock
            ? Visibility.Visible
            : Visibility.Collapsed;
        LocalDateText.Visibility = settings.ShowDate
            ? Visibility.Visible
            : Visibility.Collapsed;
        PresencePanel.Visibility = settings.ShowPresence
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void ApplyAppearanceSettings(InGameMenuSettings settings)
    {
        var dim = Math.Clamp(settings.BackgroundDimPercent, 0, 100);
        BackgroundDimLayer.Fill = InGameMenuVisualContext.CreateDimBrush(this, dim);

        var interfaceScale = settings.InterfaceScalePercent <= 0
            ? 1d
            : settings.InterfaceScalePercent / 100d;
        var scale = interfaceScale * settings.TextScalePercent / 100d;
        foreach (var (element, origin) in
                 new (FrameworkElement Element, WpfPoint Origin)[]
                 {
                     (TimeInformationPanel, new WpfPoint(0d, 0d)),
                     (TopActionsPanel, new WpfPoint(1d, 0d)),
                     (BottomMenuWorkspacePanel, new WpfPoint(0.5d, 1d))
                 })
        {
            element.RenderTransformOrigin = origin;
            element.RenderTransform = new ScaleTransform(scale, scale);
        }

        System.Windows.Controls.ToolTipService.SetInitialShowDelay(
            RootGrid,
            settings.ToolTipDelayMilliseconds);
        var strongBorder = InGameMenuVisualContext.ResolveStrongBorder(this, settings.HighContrast);
        MenuDockContainer.BorderBrush = strongBorder;
        MenuContextPanel.BorderBrush = strongBorder;
    }

    private void ApplyLayoutPreset(
        InGameMenuLayoutPreset layoutPreset)
    {
        _layoutPreset = layoutPreset;
        var leftRail =
            layoutPreset == InGameMenuLayoutPreset.LeftRail;
        LeftRailDockContainer.Visibility = leftRail
            ? Visibility.Visible
            : Visibility.Collapsed;
        MenuDockContainer.Visibility = leftRail
            ? Visibility.Collapsed
            : Visibility.Visible;
        MenuBottomFooterPanel.Visibility = leftRail
            ? Visibility.Collapsed
            : Visibility.Visible;
        BottomMenuWorkspacePanel.Margin = leftRail
            ? new Thickness(116, 0, 28, 26)
            : new Thickness(28, 0, 28, 26);
        MenuContextPanel.Margin = leftRail
            ? new Thickness(0)
            : new Thickness(0, 0, 0, 9);
        MenuContextPanel.MaxWidth = leftRail ? 1120 : 980;
    }

    internal void ApplySurfaceBounds(Rect bounds)
    {
        if (_toolMoveActive)
        {
            _pendingSurfaceBounds = bounds;
            return;
        }

        _pendingSurfaceBounds = null;
        if (_lastSurfaceBounds == bounds)
        {
            return;
        }

        _lastSurfaceBounds = bounds;
        Left = bounds.Left;
        Top = bounds.Top;
        Width = Math.Max(1, bounds.Width);
        Height = Math.Max(1, bounds.Height);
    }

    internal void SetToolMoveMode(bool active)
    {
        if (_toolMoveActive == active)
        {
            return;
        }

        _toolMoveActive = active;
        RootGrid.CacheMode = active ? _toolMoveCache : null;
        if (active)
        {
            return;
        }

        var pendingSnapshot = _pendingSnapshot;
        var pendingSurfaceBounds = _pendingSurfaceBounds;
        _pendingSnapshot = null;
        _pendingSurfaceBounds = null;
        if (pendingSurfaceBounds is { } bounds)
        {
            ApplySurfaceBounds(bounds);
        }

        if (pendingSnapshot is not null)
        {
            ApplySnapshot(pendingSnapshot);
        }

        RefreshLocalClock();
    }

    internal void ApplyInformationOverlayState(bool enabled)
    {
        _informationOverlayEnabled = enabled;
        var text = enabled ? "关闭信息浮层" : "打开信息浮层";
        InformationOverlayTopButton.Content =
            string.IsNullOrWhiteSpace(_informationOverlayHotkey)
                ? text
                : $"{text}  {_informationOverlayHotkey}";
        InformationOverlayDockLabel.Text = text;
        InformationOverlayDockButton.ToolTip =
            string.IsNullOrWhiteSpace(_informationOverlayHotkey)
                ? text
                : $"{text}（信息浮层快捷键 {_informationOverlayHotkey}）";
    }

    internal void ApplyInformationOverlayHotkey(string? displayText)
    {
        _informationOverlayHotkey = displayText?.Trim() ?? "";
        ApplyInformationOverlayState(_informationOverlayEnabled);
    }

    internal void ShowNotice(
        string text,
        string? detail = null,
        bool isLoading = false)
    {
        NoticeText.Text = text;
        NoticePopupTitle.Text = text;
        Controls.InGameLoadingPresentation.Apply(NoticeLoadingIndicator, isLoading);
        Controls.InGameLoadingPresentation.Apply(NoticePopupLoadingIndicator, isLoading);
        NoticePopupDetail.Text = detail ?? "";
        NoticePopupDetail.Visibility = string.IsNullOrWhiteSpace(detail)
            ? Visibility.Collapsed
            : Visibility.Visible;
        NoticePopup.Visibility = Visibility.Visible;
        _noticeResetTimer.Stop();
        _noticeResetTimer.Start();
    }

    protected override void OnContentRendered(EventArgs e)
    {
        base.OnContentRendered(e);
        _contentRendered = true;
        if (_preparingFirstOpen && !_menuOpen)
        {
            _preparingFirstOpen = false;
            return;
        }

        if (!_revealOnContentRendered && !_menuOpen)
        {
            return;
        }

        _revealOnContentRendered = false;
        PlayOpenTransition();
    }

    private void PlayOpenTransition()
    {
        BeginAnimation(OpacityProperty, null);
        Opacity = 1;
        var motionMode = _settings.EffectiveMotionMode;
        if (_settings.EffectivePerformanceMode ==
            InGameMenuPerformanceMode.ResourceSaving)
        {
            motionMode = InGameMenuMotionMode.Off;
        }
        else if (motionMode == InGameMenuMotionMode.System &&
                 _settings.AutoReduceEffects &&
                 _settings.EffectivePerformanceMode ==
                 InGameMenuPerformanceMode.Auto &&
                 (RenderCapability.Tier >> 16) < 2)
        {
            motionMode = InGameMenuMotionMode.Reduced;
        }

        if (motionMode == InGameMenuMotionMode.Off)
        {
            return;
        }

        var duration = motionMode == InGameMenuMotionMode.Reduced
            ? TimeSpan.FromMilliseconds(90)
            : TimeSpan.FromMilliseconds(160);
        BeginAnimation(
            OpacityProperty,
            new DoubleAnimation(0, 1, duration)
            {
                EasingFunction = new QuadraticEase
                {
                    EasingMode = EasingMode.EaseOut
                },
                FillBehavior = FillBehavior.Stop
            },
            HandoffBehavior.SnapshotAndReplace);
    }

    protected override void OnClosed(EventArgs e)
    {
        ReleaseInputOwnership();
        _menuOpen = false;
        _preparingFirstOpen = false;
        _revealOnContentRendered = false;
        _clockTimer.Stop();
        _noticeResetTimer.Stop();
        base.OnClosed(e);
    }

    private void Window_PreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key == Key.Escape)
        {
            e.Handled = true;
            MenuCloseRequested?.Invoke(this, EventArgs.Empty);
        }
    }

    private void Window_Deactivated(object? sender, EventArgs e)
    {
        ReleaseInputOwnership();
        if (!_menuOpen)
        {
            return;
        }

        Dispatcher.BeginInvoke(() =>
        {
            if (_menuOpen && IsVisible && !IsActive)
            {
                MenuDeactivated?.Invoke(this, EventArgs.Empty);
            }
        }, DispatcherPriority.ContextIdle);
    }

    private void Window_Activated(object? sender, EventArgs e)
    {
        if (_menuOpen)
        {
            CaptureMouseInput();
        }
    }

    private void Window_IsVisibleChanged(
        object sender,
        DependencyPropertyChangedEventArgs e)
    {
        if (e.NewValue is false)
        {
            ReleaseInputOwnership();
        }
    }

    private void CaptureMouseInput()
    {
        if (!ReferenceEquals(Mouse.Captured, this))
        {
            Mouse.Capture(this, CaptureMode.SubTree);
        }
    }

    private void ReleaseInputOwnership()
    {
        if (ReferenceEquals(Mouse.Captured, this))
        {
            Mouse.Capture(null);
        }
    }

    private void CloseMenu_Click(object sender, RoutedEventArgs e) =>
        MenuCloseRequested?.Invoke(this, EventArgs.Empty);

    private void SwitchToInformationOverlay_Click(object sender, RoutedEventArgs e) =>
        RaiseAction(InGameMenuAction.ToggleInformationOverlay);

    private void OpenFriends_Click(object sender, RoutedEventArgs e) =>
        RaiseAction(InGameMenuAction.OpenFriends);

    private void OpenFleet_Click(object sender, RoutedEventArgs e) =>
        RaiseAction(InGameMenuAction.OpenFleet);

    private void OpenChat_Click(object sender, RoutedEventArgs e) =>
        RaiseAction(InGameMenuAction.OpenChat);

    private void OpenRooms_Click(object sender, RoutedEventArgs e) =>
        RaiseAction(InGameMenuAction.OpenRooms);

    private void OpenOverlaySettings_Click(object sender, RoutedEventArgs e) =>
        RaiseAction(InGameMenuAction.OpenOverlaySettings);

    private void CaptureFullscreen_Click(object sender, RoutedEventArgs e) =>
        RaiseAction(InGameMenuAction.CaptureFullscreen);

    private void OpenImage_Click(object sender, RoutedEventArgs e) =>
        RaiseAction(InGameMenuAction.OpenImage);

    private void OpenBrowser_Click(object sender, RoutedEventArgs e) =>
        RaiseAction(InGameMenuAction.OpenBrowser);

    private void RaiseAction(InGameMenuAction action) =>
        ActionRequested?.Invoke(this, new InGameMenuActionRequestedEventArgs(action));

    private void RefreshLocalClock()
    {
        var now = DateTime.Now;
        LocalTimeText.Text = _settings.ClockFormat switch
        {
            InGameMenuClockFormat.TwelveHour =>
                now.ToString("h:mm tt", ChineseCulture),
            InGameMenuClockFormat.TwentyFourHour =>
                now.ToString("HH:mm", ChineseCulture),
            _ => now.ToString(
                CultureInfo.CurrentCulture.DateTimeFormat.ShortTimePattern,
                CultureInfo.CurrentCulture)
        };
        LocalDateText.Text = now.ToString("yyyy年M月d日 dddd", ChineseCulture);
    }

    private static string Normalize(string? value, string fallback) =>
        string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();

    private void ApplyUnreadBadge(
        FrameworkElement badge,
        System.Windows.Controls.TextBlock text,
        int count)
    {
        var safeCount = Math.Max(0, count);
        text.Text = safeCount > 99 ? "99+" : safeCount.ToString(ChineseCulture);
        badge.Visibility = _settings.ShowUnreadBadges && safeCount > 0
            ? Visibility.Visible
            : Visibility.Collapsed;
    }
}
