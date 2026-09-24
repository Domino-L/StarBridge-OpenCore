using StarBridge.Core.TrustSafety;
using StarBridge.Core.Presence;
using StarBridge.Desktop.Theming;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using MediaColor = System.Windows.Media.Color;
using WpfBrushes = System.Windows.Media.Brushes;
using WpfButton = System.Windows.Controls.Button;
using WpfControl = System.Windows.Controls.Control;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private const double BridgeModuleRailWidth = 72d;
    private static readonly TimeSpan BridgeGameRecognitionGracePeriod = TimeSpan.FromMinutes(2);
    private DateTimeOffset? _bridgeGameProcessStartedAtUtc;
    private ToggleButton? _bridgeSelectedRailButton;

    private void ConfigureBridgeShellMode()
    {
        BridgeSceneContext.ApplyAnimated(this, SceneState.Current);

        if (BridgeRail is null ||
            BridgeSceneBand is null ||
            BridgeContentHost is null ||
            LegacyTopShellHost is null)
        {
            return;
        }

        BridgeRail.Visibility = IsBridgeShellEnabled ? Visibility.Visible : Visibility.Collapsed;
        BridgeSceneBand.Visibility = IsBridgeShellEnabled ? Visibility.Visible : Visibility.Collapsed;
        LegacyTopShellHost.Visibility = IsBridgeShellEnabled ? Visibility.Collapsed : Visibility.Visible;
        LegacyStatusHost.Visibility = Visibility.Collapsed;
        BridgeRailColumn.Width = IsBridgeShellEnabled
            ? new GridLength(BridgeModuleRailWidth)
            : new GridLength(0);
        TopNavigationRow.Height = IsBridgeShellEnabled
            ? new GridLength(74)
            : new GridLength(56);

        Grid.SetColumn(BridgeContentHost, IsBridgeShellEnabled ? 1 : 0);
        Grid.SetColumnSpan(BridgeContentHost, IsBridgeShellEnabled ? 1 : 2);
        if (IsBridgeShellEnabled)
        {
            BridgeContentHost.ClearValue(WpfControl.BackgroundProperty);
            BridgeContentHost.ClearValue(WpfControl.PaddingProperty);
            BridgeContentHost.SetResourceReference(
                FrameworkElement.StyleProperty,
                "BridgeContentHostStyle");
        }
        else
        {
            BridgeContentHost.ClearValue(FrameworkElement.StyleProperty);
            BridgeContentHost.Background = WpfBrushes.Transparent;
            BridgeContentHost.Padding = new Thickness(0);
        }

        Grid.SetColumn(TopFleetBannerLayer, IsBridgeShellEnabled ? 1 : 0);
        Grid.SetColumnSpan(TopFleetBannerLayer, IsBridgeShellEnabled ? 1 : 2);
        FleetFooterStatusBar.Visibility = IsBridgeShellEnabled
            ? Visibility.Collapsed
            : Visibility.Visible;

        RefreshBridgeShellAccountState();
        RefreshBridgeShellForSelectedTab();
    }

    private void SetBridgeShellFullScreenEditorState(bool isFullScreen)
    {
        if (!IsBridgeShellEnabled || BridgeRail is null || BridgeSceneBand is null)
        {
            return;
        }

        BridgeRail.Visibility = isFullScreen ? Visibility.Collapsed : Visibility.Visible;
        BridgeSceneBand.Visibility = isFullScreen ? Visibility.Collapsed : Visibility.Visible;
        BridgeRailColumn.Width = isFullScreen
            ? new GridLength(0)
            : new GridLength(BridgeModuleRailWidth);
        Grid.SetColumn(BridgeContentHost, isFullScreen ? 0 : 1);
        Grid.SetColumnSpan(BridgeContentHost, isFullScreen ? 2 : 1);

        if (isFullScreen)
        {
            BridgeContentHost.ClearValue(FrameworkElement.StyleProperty);
            BridgeContentHost.Background = WpfBrushes.Transparent;
            BridgeContentHost.Padding = new Thickness(0);
        }
        else
        {
            BridgeContentHost.ClearValue(WpfControl.BackgroundProperty);
            BridgeContentHost.ClearValue(WpfControl.PaddingProperty);
            BridgeContentHost.SetResourceReference(
                FrameworkElement.StyleProperty,
                "BridgeContentHostStyle");
        }
    }

    private void BridgeFleetNav_Click(object sender, RoutedEventArgs e)
    {
        if (_hasFleet)
        {
            MyFleetNav_Click(sender, e);
        }
        else
        {
            FindFleetNav_Click(sender, e);
        }

        RefreshBridgeShellForSelectedTab();
    }

    private void BridgeFindFleetSectionButton_Click(object sender, RoutedEventArgs e)
    {
        FindFleetNav_Click(sender, e);
        RefreshBridgeShellForSelectedTab();
    }

    private void BridgeMyFleetSectionButton_Click(object sender, RoutedEventArgs e)
    {
        MyFleetNav_Click(sender, e);
        RefreshBridgeShellForSelectedTab();
    }

    private void BridgePartyNav_Click(object sender, RoutedEventArgs e)
    {
        MySquadNav_Click(sender, e);
        RefreshBridgeShellForSelectedTab();
    }

    private void BridgeSocialNav_Click(object sender, RoutedEventArgs e)
    {
        HeaderFriendCenterButton_Click(sender, e);
        RefreshBridgeShellForSelectedTab();
    }

    private void BridgeOverlayNav_Click(object sender, RoutedEventArgs e)
    {
        OverlayNav_Click(sender, e);
        RefreshBridgeShellForSelectedTab();
    }

    private void BridgeInfoNav_Click(object sender, RoutedEventArgs e)
    {
        OpenHelpSupportPage();
        RefreshBridgeShellForSelectedTab();
    }

    private void BridgeSettingsButton_Click(object sender, RoutedEventArgs e)
    {
        HeaderSettingsButton_Click(sender, e);
        RefreshBridgeShellForSelectedTab();
    }

    private void BridgeAccountMenuButton_Click(object sender, RoutedEventArgs e)
    {
        RefreshBridgeShellForSelectedTab();
        HeaderAccountMenu.PlacementTarget = BridgePersonalNavButton;
        HeaderAccountMenu.Placement = PlacementMode.Bottom;
        HeaderAccountMenu.HorizontalOffset = -18;
        HeaderAccountMenu.IsOpen = true;
        BridgePersonalNavButton.IsChecked = true;
        NotifyGuidedTourAction(GuideStep.OpenAccountMenu);
        e.Handled = true;
    }

    private void HeaderAccountMenu_Closed(object sender, RoutedEventArgs e)
    {
        BridgePersonalNavButton.IsChecked = false;
    }

    private void BridgePresenceModeButton_Click(object sender, RoutedEventArgs e)
    {
        if (!IsAccountAuthenticated)
        {
            LoginButton_Click(sender, e);
            return;
        }

        RefreshBridgePresenceModeOptions();
        BridgePresenceModePopup.IsOpen = true;
        e.Handled = true;
    }

    private void BridgePresenceModePopup_Opened(object? sender, EventArgs e)
    {
        BridgePresenceModeButton.Tag = "Active";
    }

    private void BridgePresenceModePopup_Closed(object? sender, EventArgs e)
    {
        BridgePresenceModeButton.Tag = null;
    }

    private async void BridgePresenceModeOption_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not WpfButton { CommandParameter: string modeName } ||
            !Enum.TryParse<PlayerPresenceVisibilityMode>(modeName, ignoreCase: true, out var mode) ||
            !Enum.IsDefined(mode) ||
            mode == PlayerPresenceVisibilityMode.Offline)
        {
            return;
        }

        BridgePresenceModePopup.IsOpen = false;
        await ApplyPresenceVisibilityModeAsync(mode);
        RefreshBridgeSceneBandStatus();
        e.Handled = true;
    }

    private void BridgeGameRecognitionAlert_Click(object sender, RoutedEventArgs e)
    {
        OpenPersonalIdentitySettings_Click(sender, e);
        RefreshBridgeShellForSelectedTab();
    }

    private void BridgeCurrentRoomButton_Click(object sender, RoutedEventArgs e)
    {
        if (_currentPartyRoom is null)
        {
            return;
        }

        NavigateToPartyLobby(animate: true, showGuideHint: false);
        ShowCurrentPartyRoom();
        RefreshBridgeShellForSelectedTab();
    }

    private void BridgeReviewNav_Click(object sender, RoutedEventArgs e)
    {
        if (!IsLoggedIn ||
            !_accountEntitlements.Contains(TrustSafetyEntitlements.ModerateReports))
        {
            return;
        }

        SetBridgeScene(
            BridgeSceneKind.Review,
            "审核",
            "举报审核",
            "查看待处理举报与证据",
            "\uE73E");
        SetBridgeSelectedModule(BridgeReviewNavButton);
        OpenReportModerationWorkspace_Click(sender, e);
    }

    private void SetBridgeReviewWorkspaceState(string title, string description)
    {
        if (!IsBridgeShellEnabled)
        {
            return;
        }

        SetBridgeScene(
            BridgeSceneKind.Review,
            "审核",
            title,
            description,
            "\uE73E");
        SetBridgeSelectedModule(BridgeReviewNavButton);
    }

    private void RefreshBridgeShellForSelectedTab()
    {
        if (!IsBridgeShellEnabled || MainTabs is null)
        {
            return;
        }

        RefreshBridgeFleetSectionNavigation();

        if (ReferenceEquals(MainTabs.SelectedItem, FindFleetTab))
        {
            SetBridgeScene(
                BridgeSceneKind.Fleet,
                "组织",
                "寻找组织",
                "浏览公开组织与加入条件",
                "\uE902");
            SetBridgeSelectedModule(BridgeFleetNavButton);
        }
        else if (ReferenceEquals(MainTabs.SelectedItem, FleetTab))
        {
            var startupFleetDataIsLive = _startupDataGate.Current.State == StartupDataGateState.Live;
            SetBridgeScene(
                BridgeSceneKind.Fleet,
                "组织",
                startupFleetDataIsLive && _hasFleet && !string.IsNullOrWhiteSpace(_fleetName)
                    ? _fleetName
                    : "我的组织",
                "成员、舰船与协作",
                "\uE902");
            SetBridgeSelectedModule(BridgeFleetNavButton);
        }
        else if (ReferenceEquals(MainTabs.SelectedItem, HomeTab))
        {
            SetBridgeScene(
                BridgeSceneKind.System,
                "总览",
                "舰桥总览",
                "当前状态与常用入口",
                "\uE80F");
            SetBridgeSelectedModule(null);
        }
        else if (ReferenceEquals(MainTabs.SelectedItem, MySquadTab))
        {
            SetBridgeScene(
                BridgeSceneKind.Party,
                "房间",
                "房间大厅",
                "寻找队友与管理当前房间",
                "\uE716");
            SetBridgeSelectedModule(BridgePartyNavButton);
        }
        else if (ReferenceEquals(MainTabs.SelectedItem, HangarTab))
        {
            SetBridgeScene(
                BridgeSceneKind.Hangar,
                "机库",
                "我的机库",
                "舰船资产、状态与专属图片",
                "\uE7B8");
            SetBridgeSelectedModule(BridgePersonalNavButton);
        }
        else if (ReferenceEquals(MainTabs.SelectedItem, FriendCenterTab))
        {
            SetBridgeScene(
                BridgeSceneKind.Social,
                "好友",
                "好友与私信",
                "好友、申请与私聊",
                "\uE715");
            SetBridgeSelectedModule(BridgeSocialNavButton);
        }
        else if (ReferenceEquals(MainTabs.SelectedItem, PersonalTab))
        {
            SetBridgeScene(
                BridgeSceneKind.Personal,
                "个人",
                "个人主页",
                "公开资料与游戏定位",
                "\uE77B");
            SetBridgeSelectedModule(BridgePersonalNavButton);
        }
        else if (ReferenceEquals(MainTabs.SelectedItem, OverlayEditTab))
        {
            SetBridgeScene(
                BridgeSceneKind.Overlay,
                "浮层",
                "游戏浮层",
                "信息浮层与菜单浮层",
                "\uE7FC");
            SetBridgeSelectedModule(BridgeOverlayNavButton);
        }
        else if (ReferenceEquals(MainTabs.SelectedItem, SettingsTab))
        {
            SetBridgeScene(
                BridgeSceneKind.System,
                "设置",
                "设置",
                "账号、同步与应用选项",
                "\uE713");
            SetBridgeSelectedModule(null, settingsSelected: true);
        }
        else if (ReferenceEquals(MainTabs.SelectedItem, SupportTab))
        {
            SetBridgeScene(
                BridgeSceneKind.System,
                "信息",
                "说明与支持",
                "使用说明、版本信息与问题反馈",
                "\uE946");
            SetBridgeSelectedModule(BridgeInfoNavButton);
        }
        else if (ReferenceEquals(MainTabs.SelectedItem, MonitorTab))
        {
            SetBridgeScene(
                BridgeSceneKind.System,
                "设置",
                "运行状态",
                "连接与本地运行信息",
                "\uE9D9");
            SetBridgeSelectedModule(null, settingsSelected: true);
        }

        RefreshBridgeSceneBandStatus();
    }

    private void RefreshBridgeFleetSectionNavigation()
    {
        var isFindFleet = ReferenceEquals(MainTabs.SelectedItem, FindFleetTab);
        var isMyFleet = ReferenceEquals(MainTabs.SelectedItem, FleetTab);

        BridgeFleetSectionNav.Visibility = isFindFleet || isMyFleet
            ? Visibility.Visible
            : Visibility.Collapsed;
        BridgeFindFleetSectionButton.IsChecked = isFindFleet;
        BridgeMyFleetSectionButton.IsChecked = isMyFleet;
    }

    private void SetBridgeSelectedModule(
        ToggleButton? selectedButton,
        bool settingsSelected = false)
    {
        if (!IsBridgeShellEnabled)
        {
            return;
        }

        var nextRailButton = IsBridgeRailButton(selectedButton) ? selectedButton : null;
        var previousRailButton = _bridgeSelectedRailButton;
        var selectionChanged = !ReferenceEquals(previousRailButton, nextRailButton);
        if (selectionChanged)
        {
            // Start from the pixels currently on screen. The checked state is committed
            // immediately below, so the old surface can contract while the new one opens.
            UiMotion.CollapseNavigationSelection(previousRailButton);
        }
        ApplyBridgeSelectedModuleState(selectedButton, settingsSelected);
        if (selectionChanged)
        {
            UiMotion.RevealNavigationSelection(nextRailButton);
        }
        _bridgeSelectedRailButton = nextRailButton;
    }

    private void ApplyBridgeSelectedModuleState(
        ToggleButton? selectedButton,
        bool settingsSelected)
    {
        BridgeFleetNavButton.IsChecked = ReferenceEquals(selectedButton, BridgeFleetNavButton);
        BridgePartyNavButton.IsChecked = ReferenceEquals(selectedButton, BridgePartyNavButton);
        BridgeSocialNavButton.IsChecked = ReferenceEquals(selectedButton, BridgeSocialNavButton);
        BridgeOverlayNavButton.IsChecked = ReferenceEquals(selectedButton, BridgeOverlayNavButton);
        BridgeReviewNavButton.IsChecked = ReferenceEquals(selectedButton, BridgeReviewNavButton);
        BridgeInfoNavButton.IsChecked = ReferenceEquals(selectedButton, BridgeInfoNavButton);
        BridgePersonalNavButton.IsChecked = ReferenceEquals(selectedButton, BridgePersonalNavButton);
        BridgeSettingsButton.Tag = settingsSelected ? "Active" : null;
    }

    private bool IsBridgeRailButton(ToggleButton? button) =>
        ReferenceEquals(button, BridgeFleetNavButton) ||
        ReferenceEquals(button, BridgePartyNavButton) ||
        ReferenceEquals(button, BridgeSocialNavButton) ||
        ReferenceEquals(button, BridgeOverlayNavButton) ||
        ReferenceEquals(button, BridgeReviewNavButton) ||
        ReferenceEquals(button, BridgeInfoNavButton);

    private void SetBridgeScene(
        BridgeSceneKind scene,
        string eyebrow,
        string title,
        string description,
        string glyph)
    {
        if (!IsBridgeShellEnabled || BridgeSceneTitleText is null)
        {
            return;
        }

        BridgeSceneEyebrowText.Text = eyebrow;
        BridgeSceneTitleText.Text = title;
        BridgeSceneMetaText.Text = description;
        BridgeSceneGlyphText.Text = glyph;

        var (accent, ambient) = BridgeScenePalette.Resolve(scene);

        AnimateBridgeSceneColors(accent, ambient);
    }

    private static void AnimateBridgeSceneColors(MediaColor accent, MediaColor ambient)
    {
        var state = SceneState.Current;
        UiMotion.ApplySceneColor(
            state,
            SceneState.AccentColorProperty,
            accent);
        UiMotion.ApplySceneColor(
            state,
            SceneState.AmbientColorProperty,
            ambient);
    }

    private void RefreshBridgeShellAccountState()
    {
        if (!IsBridgeShellEnabled || BridgeAuthenticationButton is null)
        {
            return;
        }

        BridgeAuthenticationButton.Visibility = IsAccountAuthenticated
            ? Visibility.Collapsed
            : Visibility.Visible;
        BridgeAuthenticationButton.Content = AccountState.AuthenticationExpired
            ? "重新登录"
            : "登录账号";
        BridgeInboxButton.Visibility = IsAccountAuthenticated
            ? Visibility.Visible
            : Visibility.Collapsed;
        BridgeReviewNavButton.Visibility = IsLoggedIn &&
                                           _accountEntitlements.Contains(TrustSafetyEntitlements.ModerateReports)
            ? Visibility.Visible
            : Visibility.Collapsed;
        var scmIdentityAbnormal = IsScmLoggedIn &&
                                  ResolveStartupIdentityGateDecision() !=
                                  StartupIdentityGateDecision.Allow;
        BridgeRsiAbnormalDot.Visibility = scmIdentityAbnormal
            ? Visibility.Visible
            : Visibility.Collapsed;
        HeaderIdentityAbnormalDot.Visibility = scmIdentityAbnormal
            ? Visibility.Visible
            : Visibility.Collapsed;
        BridgeRsiAbnormalDot.ToolTip = scmIdentityAbnormal
            ? ResolveStartupIdentityGateDecision() == StartupIdentityGateDecision.IdentityMismatch
                ? "SCM、兼容账号或 Game.log 的游戏 ID 不一致"
                : "RSI 账号尚未验证或验证状态异常"
            : null;
        BridgeAccountNameText.Text = IsScmLoggedIn
            ? _scmOAuthSession!.DisplayName
            : IsLoggedIn ? GetPersonalDisplayName() : "星海舰桥访客";
        RefreshBridgeAccountPresence();
        RefreshBridgeNotificationBadge();
        RefreshBridgeSceneBandStatus();
    }

    private void RefreshBridgeAccountPresence()
    {
        if (!IsAccountAuthenticated)
        {
            BridgeAccountStatusText.Text = "离线";
            BridgeAccountStatusText.Foreground = FindBrush("StatusDisabledBrush", WpfBrushes.LightSlateGray);
        }
        else
        {
            BridgeAccountStatusText.Text = PlayerPresencePresentation.FormatLocal(
                _localPresence,
                _syncPrivacySettings.PresenceVisibilityMode,
                _language);
            BridgeAccountStatusText.Foreground = PlayerPresencePresentation.LocalBrush(
                _localPresence,
                _syncPrivacySettings.PresenceVisibilityMode);
        }

        BridgeAccountStatusDot.Fill = BridgeAccountStatusText.Foreground;
        BridgeAccountStatusGlow.Color = BridgeAccountStatusText.Foreground is SolidColorBrush brush
            ? brush.Color
            : MediaColor.FromRgb(105, 204, 255);
        BridgeAccountStatusGlow.Opacity = IsAccountAuthenticated ? 0.4 : 0;
    }

    private void RefreshBridgeSceneBandStatus()
    {
        if (!IsBridgeShellEnabled ||
            BridgePresenceModeButton is null ||
            BridgeGameRecognitionAlert is null ||
            BridgeCurrentRoomButton is null)
        {
            return;
        }

        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        BridgePresenceModeLabel.Text = zh ? "对外状态" : "Visibility";
        RefreshBridgePresenceModeOptions();

        var accountState = AccountState;
        if (!accountState.IsAuthenticated)
        {
            BridgePresenceModeText.Text = zh ? "未登录" : "Signed out";
            BridgePresenceModeText.Foreground = FindBrush("StatusDisabledBrush", WpfBrushes.LightSlateGray);
            BridgePresenceModeDot.Fill = FindBrush("StatusDisabledBrush", WpfBrushes.LightSlateGray);
            BridgePresenceModeButton.ToolTip = zh ? "登录后设置对外状态" : "Sign in to set your visibility";
        }
        else if (!accountState.HasRelaySession)
        {
            var option = PlayerPresenceVisibilityCatalog.Find(
                _syncPrivacySettings.PresenceVisibilityMode);
            BridgePresenceModeText.Text = PlayerPresencePresentation.FormatLocal(
                _localPresence, option.Mode, _language);
            BridgePresenceModeText.Foreground = PlayerPresencePresentation.LocalBrush(
                _localPresence, option.Mode);
            BridgePresenceModeDot.Fill = BridgePresenceModeText.Foreground;
            BridgePresenceModeButton.ToolTip = zh
                ? "选择本机对外状态；完成旧账号关联后可同步到兼容服务"
                : "Choose local visibility; linking is required to publish to legacy services";
        }
        else
        {
            var option = PlayerPresenceVisibilityCatalog.Find(
                _syncPrivacySettings.PresenceVisibilityMode);

            BridgePresenceModeText.Text = PlayerPresencePresentation.FormatLocal(
                _localPresence, option.Mode, _language);
            BridgePresenceModeText.Foreground = PlayerPresencePresentation.LocalBrush(
                _localPresence, option.Mode);
            BridgePresenceModeDot.Fill = BridgePresenceModeText.Foreground;
            BridgePresenceModeButton.ToolTip = zh
                ? "选择对外状态"
                : "Choose your visibility";
        }

        var gameRunningPastGrace = _isGameProcessRunning &&
                                   _bridgeGameProcessStartedAtUtc is { } gameStartedAtUtc &&
                                   DateTimeOffset.UtcNow - gameStartedAtUtc >= BridgeGameRecognitionGracePeriod;
        var logMissing = string.IsNullOrWhiteSpace(_logPath) || !File.Exists(_logPath);
        var logUnread = gameRunningPastGrace && _lastGameLogReadAt == DateTimeOffset.MinValue;
        var serverPending = gameRunningPastGrace && !IsGameServerRegionCurrent();
        var showRecognitionAlert = logMissing || logUnread || serverPending;

        BridgeGameRecognitionAlert.Visibility = showRecognitionAlert
            ? Visibility.Visible
            : Visibility.Collapsed;
        if (showRecognitionAlert)
        {
            BridgeGameRecognitionAlertText.Text = zh
                ? logMissing ? "连接 Game.log" : "状态待识别"
                : logMissing ? "Connect Game.log" : "Recognition pending";
            BridgeGameRecognitionAlert.ToolTip = zh
                ? logMissing
                    ? "尚未连接可用的 Game.log。单击前往账号与识别。"
                    : "游戏已启动，但应用尚未识别当前服务器。单击检查游戏识别设置。"
                : logMissing
                    ? "Game.log is not connected. Click to open account and identity settings."
                    : "The game is running, but the current server has not been recognized yet.";
        }

        var hasCurrentRoom = _currentPartyRoom is not null;
        BridgeCurrentRoomButton.Visibility = hasCurrentRoom
            ? Visibility.Visible
            : Visibility.Collapsed;
        if (hasCurrentRoom)
        {
            var roomName = string.IsNullOrWhiteSpace(_currentPartyRoom!.Title)
                ? zh ? "未命名房间" : "Unnamed room"
                : _currentPartyRoom.Title.Trim();
            BridgeCurrentRoomText.Text = roomName;
            BridgeCurrentRoomButton.ToolTip = zh
                ? $"返回当前房间：{roomName}"
                : $"Return to current room: {roomName}";
        }
    }

    private void RefreshBridgePresenceModeOptions()
    {
        if (BridgePresenceOnlineOption is null ||
            BridgePresenceInGameOption is null ||
            BridgePresenceInvisibleOption is null ||
            BridgePresencePopupTitle is null)
        {
            return;
        }

        var currentMode = _syncPrivacySettings.PresenceVisibilityMode;
        BridgePresenceOnlineOption.Tag = currentMode == PlayerPresenceVisibilityMode.Online ? "Active" : null;
        BridgePresenceInGameOption.Tag = currentMode == PlayerPresenceVisibilityMode.InGame ? "Active" : null;
        BridgePresenceInvisibleOption.Tag = currentMode == PlayerPresenceVisibilityMode.Invisible ? "Active" : null;

        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        BridgePresencePopupTitle.Text = zh ? "选择对外状态" : "Choose your visibility";
        BridgePresenceOnlineTitle.Text = zh ? "在线" : "Online";
        BridgePresenceOnlineDescription.Text = zh ? "检测到游戏后自动显示游戏中" : "Switch to in game when detected";
        BridgePresenceInGameTitle.Text = zh ? "游戏中" : "In game";
        BridgePresenceInGameDescription.Text = zh ? "对外显示游戏中" : "Show your status as in game";
        BridgePresenceInvisibleTitle.Text = zh ? "隐身" : "Invisible";
        BridgePresenceInvisibleDescription.Text = zh ? "对外显示离线，仍可接收内容" : "Appear offline and keep receiving updates";
    }

    private void RefreshBridgeNotificationBadge()
    {
        if (!IsBridgeShellEnabled || BridgeInboxUnreadBadge is null ||
            HeaderInboxUnreadBadge is null)
        {
            return;
        }

        var scmStationUnread = (int)Math.Min(
            int.MaxValue,
            Math.Max(0L, _scmBootstrapSnapshot?.UnreadNotifications ?? 0L));
        var relayStationUnread = Math.Max(0, _notificationInbox?.UnreadCount ?? 0);
        var relayChatUnread = Math.Max(0, _fleetChatTotalUnread) +
                              Math.Max(0, _partyRoomChatUnreadCount) +
                              _friendChatConversations.Sum(conversation =>
                                  Math.Max(0, conversation.Conversation.UnreadCount));
        var count = (long)scmStationUnread + relayStationUnread + relayChatUnread;
        var badgeText = count > 99 ? "99+" : count.ToString(CultureInfo.InvariantCulture);
        var visibility = IsAccountAuthenticated && count > 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        BridgeInboxUnreadBadgeText.Text = badgeText;
        BridgeInboxUnreadBadge.Visibility = visibility;
        HeaderInboxUnreadBadgeText.Text = badgeText;
        HeaderInboxUnreadBadge.Visibility = visibility;
        var tooltip = count > 0
            ? $"消息 · {count} 条未读（SCM 站内信与舰桥通讯）"
            : "消息";
        BridgeInboxButton.ToolTip = tooltip;
        HeaderInboxButton.ToolTip = tooltip;
    }

}
