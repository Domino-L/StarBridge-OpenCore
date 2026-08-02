using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using WpfButton = System.Windows.Controls.Button;
using WpfColor = System.Windows.Media.Color;
using WpfPoint = System.Windows.Point;
using UserControl = System.Windows.Controls.UserControl;

namespace StarBridge.Desktop;

public partial class InGameMenuPreviewSurface : UserControl
{
    private const double DefaultPreviewWidth = 1920;
    private const double DefaultPreviewHeight = 1080;
    private static readonly CultureInfo ChineseCulture =
        CultureInfo.GetCultureInfo("zh-CN");
    private readonly DispatcherTimer _clockTimer = new()
    {
        Interval = TimeSpan.FromMinutes(1)
    };
    private InGameMenuSettings _settings = InGameMenuSettings.Default;

    public InGameMenuPreviewSurface()
    {
        InitializeComponent();
        _clockTimer.Tick += (_, _) => RefreshClock();
        Loaded += (_, _) =>
        {
            RefreshClock();
            _clockTimer.Start();
        };
        Unloaded += (_, _) => _clockTimer.Stop();
        RefreshClock();
    }

    internal void ApplyPreview(
        Rect targetBounds,
        InGameMenuSnapshot snapshot,
        InGameMenuSettings settings,
        bool informationOverlayVisible)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        ArgumentNullException.ThrowIfNull(settings);

        var width = ResolveDimension(
            targetBounds.IsEmpty ? double.NaN : targetBounds.Width,
            DefaultPreviewWidth);
        var height = ResolveDimension(
            targetBounds.IsEmpty ? double.NaN : targetBounds.Height,
            DefaultPreviewHeight);
        PreviewRoot.Width = width;
        PreviewRoot.Height = height;

        RefreshClock();
        ApplySettings(settings, informationOverlayVisible);
        ApplySnapshot(snapshot);
    }

    private void RefreshClock()
    {
        var now = DateTime.Now;
        PreviewLocalTimeText.Text = _settings.ClockFormat switch
        {
            InGameMenuClockFormat.TwelveHour =>
                now.ToString("h:mm tt", ChineseCulture),
            InGameMenuClockFormat.TwentyFourHour =>
                now.ToString("HH:mm", ChineseCulture),
            _ => now.ToString(
                CultureInfo.CurrentCulture.DateTimeFormat.ShortTimePattern,
                CultureInfo.CurrentCulture)
        };
        PreviewLocalDateText.Text =
            now.ToString("yyyy年M月d日 dddd", ChineseCulture);
    }

    private void ApplySnapshot(InGameMenuSnapshot snapshot)
    {
        PreviewPresenceText.Text =
            Normalize(snapshot.Presence, "应用在线");
        PreviewSceneTitleText.Text =
            Normalize(snapshot.SceneTitle, "当前协作");
        PreviewSceneTitleText.ToolTip =
            Normalize(snapshot.SceneDetail, "等待协作信息同步");
        PreviewMemberCountText.Text =
            $"{Math.Max(0, snapshot.MemberCount)} 人";
        PreviewShipText.Text =
            Normalize(snapshot.Ship, "等待识别");
        PreviewLocationText.Text =
            _settings.EffectiveShowExactLocation
                ? Normalize(snapshot.Location, "等待识别")
                : "已隐藏";
        PreviewServerText.Text =
            Normalize(snapshot.Server, "等待连接");
        ApplyUnreadBadge(
            PreviewFriendsUnreadBadge,
            PreviewFriendsUnreadText,
            snapshot.FriendAlertCount);
        ApplyUnreadBadge(
            PreviewChatUnreadBadge,
            PreviewChatUnreadText,
            snapshot.MessageUnreadCount);
        ApplyUnreadBadge(
            PreviewRoomsUnreadBadge,
            PreviewRoomsUnreadText,
            snapshot.RoomAlertCount);
    }

    private void ApplySettings(
        InGameMenuSettings settings,
        bool informationOverlayVisible)
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
        var informationOverlayText = informationOverlayVisible
            ? "关闭信息浮层"
            : "打开信息浮层";

        PreviewInformationOverlayTopButton.Content =
            informationOverlayText;
        PreviewInformationOverlayDockLabel.Text =
            informationOverlayText;
        PreviewMenuReturnHotkeyText.Text =
            string.IsNullOrWhiteSpace(shortcutText)
                ? "ESC"
                : $"{shortcutText.ToUpperInvariant()} / ESC";
        PreviewMenuFooterHotkeyText.Text =
            string.IsNullOrWhiteSpace(shortcutText)
                ? "按 Esc 返回游戏 · 工具窗口会随菜单自动隐藏"
                : $"按 {shortcutText} 或 Esc 返回游戏 · 工具窗口会随菜单自动隐藏";
        ApplyToolbarSettings(normalized);
        ApplyContextSettings(normalized);
        ApplyAppearanceSettings(normalized);
        RefreshClock();
    }

    private void ApplyToolbarSettings(InGameMenuSettings settings)
    {
        var buttons = new Dictionary<InGameMenuTool, WpfButton>
        {
            [InGameMenuTool.InformationOverlay] =
                PreviewInformationOverlayDockButton,
            [InGameMenuTool.Fleet] = PreviewFleetDockButton,
            [InGameMenuTool.Friends] = PreviewFriendsDockButton,
            [InGameMenuTool.Chat] = PreviewChatDockButton,
            [InGameMenuTool.Rooms] = PreviewRoomsDockButton,
            [InGameMenuTool.Screenshot] = PreviewScreenshotDockButton,
            [InGameMenuTool.Image] = PreviewImageDockButton,
            [InGameMenuTool.Browser] = PreviewBrowserDockButton
        };
        var labels = new[]
        {
            PreviewInformationOverlayDockLabel,
            PreviewFleetDockLabel,
            PreviewFriendsDockLabel,
            PreviewChatDockLabel,
            PreviewRoomsDockLabel,
            PreviewScreenshotDockLabel,
            PreviewImageDockLabel,
            PreviewBrowserDockLabel
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

        PreviewPrimaryDockPanel.Children.Clear();
        var dividerAdded = false;
        foreach (var tool in settings.ResolveToolOrder()
                     .Where(settings.IsToolVisible))
        {
            if (!dividerAdded &&
                (tool is InGameMenuTool.Screenshot or
                    InGameMenuTool.Image or
                    InGameMenuTool.Browser) &&
                PreviewPrimaryDockPanel.Children.Count > 0)
            {
                PreviewPrimaryDockPanel.Children.Add(
                    PreviewDockGroupDivider);
                dividerAdded = true;
            }

            PreviewPrimaryDockPanel.Children.Add(buttons[tool]);
        }
    }

    private void ApplyContextSettings(InGameMenuSettings settings)
    {
        PreviewMenuContextPanel.Visibility = settings.ShowContextBar
            ? Visibility.Visible
            : Visibility.Collapsed;
        PreviewSceneContextPanel.Visibility = settings.ShowScene
            ? Visibility.Visible
            : Visibility.Collapsed;
        PreviewMemberContextPanel.Visibility = settings.ShowMemberCount
            ? Visibility.Visible
            : Visibility.Collapsed;
        PreviewShipContextPanel.Visibility = settings.ShowShip
            ? Visibility.Visible
            : Visibility.Collapsed;
        PreviewLocationContextPanel.Visibility = settings.ShowLocation
            ? Visibility.Visible
            : Visibility.Collapsed;
        PreviewServerContextPanel.Visibility = settings.ShowServer
            ? Visibility.Visible
            : Visibility.Collapsed;
        PreviewTimeInformationPanel.Visibility =
            settings.ShowClock ||
            settings.ShowDate ||
            settings.ShowPresence
                ? Visibility.Visible
                : Visibility.Collapsed;
        PreviewLocalTimeText.Visibility = settings.ShowClock
            ? Visibility.Visible
            : Visibility.Collapsed;
        PreviewLocalDateText.Visibility = settings.ShowDate
            ? Visibility.Visible
            : Visibility.Collapsed;
        PreviewPresencePanel.Visibility = settings.ShowPresence
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void ApplyAppearanceSettings(InGameMenuSettings settings)
    {
        PreviewBackgroundDimLayer.Fill = new SolidColorBrush(
            WpfColor.FromArgb(
                (byte)Math.Round(
                    settings.BackgroundDimPercent / 100d * byte.MaxValue),
                0,
                6,
                11));
        var interfaceScale = settings.InterfaceScalePercent <= 0
            ? 1d
            : settings.InterfaceScalePercent / 100d;
        var scale = interfaceScale * settings.TextScalePercent / 100d;
        foreach (var (element, origin) in
                 new (FrameworkElement Element, WpfPoint Origin)[]
                 {
                     (PreviewTimeInformationPanel, new WpfPoint(0d, 0d)),
                     (PreviewTopControlsPanel, new WpfPoint(1d, 0d)),
                     (PreviewBottomMenuWorkspacePanel, new WpfPoint(0.5d, 1d))
                 })
        {
            element.RenderTransformOrigin = origin;
            element.RenderTransform = new ScaleTransform(scale, scale);
        }
    }

    private static double ResolveDimension(
        double candidate,
        double fallback) =>
        double.IsFinite(candidate) && candidate > 0
            ? candidate
            : fallback;

    private static string Normalize(
        string? value,
        string fallback) =>
        string.IsNullOrWhiteSpace(value)
            ? fallback
            : value.Trim();

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
