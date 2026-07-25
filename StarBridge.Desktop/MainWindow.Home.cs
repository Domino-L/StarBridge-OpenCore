using StarBridge.Core.Identity;
using StarBridge.Core.State;
using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using ColorConverter = System.Windows.Media.ColorConverter;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private readonly ObservableCollection<HomeDashboardActionRow> _homePendingItems = [];
    private readonly ObservableCollection<HomeDashboardEventRow> _homeRecentEvents = [];

    private void OpenHomePage(bool animate = true)
    {
        var previousTab = MainTabs.SelectedItem;
        OpenHelpSupportPage();
        if (animate && !ReferenceEquals(previousTab, MainTabs.SelectedItem))
        {
            QueueMainPageReveal(previousTab);
        }
    }

    private void RefreshHomeDashboard()
    {
        if (HomePendingItemsList is null || HomeRecentEventsList is null)
        {
            return;
        }

        if (!ReferenceEquals(HomePendingItemsList.ItemsSource, _homePendingItems))
        {
            HomePendingItemsList.ItemsSource = _homePendingItems;
        }

        if (!ReferenceEquals(HomeRecentEventsList.ItemsSource, _homeRecentEvents))
        {
            HomeRecentEventsList.ItemsSource = _homeRecentEvents;
        }

        RefreshHomeIdentity();
        RefreshHomeJourney();
        RefreshHomePendingItems();
        RefreshHomeFleetAndCommunication();
        RefreshHomeRecentEvents();
    }

    private void RefreshHomeIdentity()
    {
        var displayName = !string.IsNullOrWhiteSpace(_callsign)
            ? _callsign!
            : !string.IsNullOrWhiteSpace(_localPlayer)
                ? _localPlayer!
                : !string.IsNullOrWhiteSpace(_accountName)
                    ? _accountName!
                    : "舰桥成员";
        var hour = DateTime.Now.Hour;
        var greeting = hour < 6
            ? "夜深了"
            : hour < 11
                ? "早上好"
                : hour < 14
                    ? "中午好"
                    : hour < 18
                        ? "下午好"
                        : "晚上好";
        HomeGreetingText.Text = IsLoggedIn
            ? $"{greeting}，{displayName}"
            : "欢迎来到星海舰桥";
        HomeIdentityInitialText.Content = BuildHomeInitials(displayName);

        if (!IsLoggedIn)
        {
            HomeIdentityDetailText.Text = "登录后可同步好友、舰队、房间与个人资料；本地 Game.log 识别仍可使用。";
        }
        else if (!string.IsNullOrWhiteSpace(_localPlayer))
        {
            HomeIdentityDetailText.Text = CanSynchronizeUserData
                ? $"游戏 ID：{_localPlayer} · 当前资料已连接"
                : $"游戏 ID：{_localPlayer} · 当前仅保留本地识别";
        }
        else
        {
            HomeIdentityDetailText.Text = "尚未从 Game.log 识别游戏 ID，连接日志后即可补全当前航程。";
        }

        ApplyHomeStatus(
            HomeAccountStatusDot,
            HomeAccountStatusText,
            IsLoggedIn ? "账号已登录" : "账号未登录",
            IsLoggedIn ? "StatusSuccessBrush" : "StatusDisabledBrush");
        ApplyHomeStatus(
            HomeGameStatusDot,
            HomeGameStatusText,
            _isGameProcessRunning ? "游戏运行中" : "游戏未运行",
            _isGameProcessRunning ? "StatusSuccessBrush" : "StatusDisabledBrush");

        var syncText = GetHeaderConnectionStatus();
        var syncBrush = syncText is "连接正常" or "同步中"
            ? "StatusSuccessBrush"
            : syncText == "连接异常"
                ? "StatusDangerBrush"
                : !CanSynchronizeUserData && IsLoggedIn
                    ? "StatusWarningBrush"
                    : "StatusDisabledBrush";
        ApplyHomeStatus(HomeSyncStatusDot, HomeSyncStatusText, syncText, syncBrush);

        var action = ResolveHomePrimaryAction();
        HomePrimaryActionButton.Content = action.Label;
        HomePrimaryActionButton.Tag = action.Key;
    }

    private void RefreshHomeJourney()
    {
        var local = GetHomeLocalPlayer();
        var gameRunning = _isGameProcessRunning;
        HomeJourneyGameText.Text = gameRunning ? "Star Citizen 运行中" : "未启动";
        HomeJourneyGameText.Foreground = FindBrush(
            gameRunning ? "StatusSuccessBrush" : "PrimaryTextBrush",
            gameRunning ? Brushes.SpringGreen : Brushes.WhiteSmoke);
        HomeJourneyDurationText.Text = gameRunning
            ? GetHomeCurrentSessionDurationText()
            : "启动游戏后自动更新当前航程";

        var rawShip = local?.Ship;
        var hasShip = gameRunning && !IsHomeUnknown(rawShip);
        HomeJourneyShipText.Text = hasShip ? FormatShipForUser(rawShip) : "等待识别";
        HomeJourneyShipEvidenceText.Text = hasShip
            ? $"识别可信度：{FormatHomeConfidence(local?.ShipConfidence)}"
            : gameRunning ? "正在等待舰船信号" : "游戏启动后开始识别";

        var rawLocation = local?.Location;
        var hasLocation = gameRunning && !IsHomeUnknown(rawLocation);
        HomeJourneyLocationText.Text = hasLocation ? FormatLocationForUser(rawLocation) : "等待识别";
        HomeJourneyLocationEvidenceText.Text = hasLocation
            ? $"识别可信度：{FormatHomeConfidence(local?.LocationConfidence)}"
            : gameRunning ? "正在等待地点信号" : "游戏启动后开始识别";

        HomeJourneyServerText.Text = IsGameServerRegionCurrent()
            ? GetGameServerRegionDisplay()
            : gameRunning ? "等待服务器确认" : "未连接";
        HomeJourneyServerText.Foreground = FindBrush(
            IsGameServerRegionCurrent() ? "StatusSuccessBrush" : "MutedTextBrush",
            IsGameServerRegionCurrent() ? Brushes.SpringGreen : Brushes.SlateGray);
        HomeJourneyOverlayText.Text = IsOverlayRunning ? "已开启" : "未开启";
        HomeJourneyOverlayText.Foreground = FindBrush(
            IsOverlayRunning ? "StatusSuccessBrush" : "MutedTextBrush",
            IsOverlayRunning ? Brushes.SpringGreen : Brushes.SlateGray);
        HomeJourneyRecordingText.Text = _gameplayStatisticsRecorder.IsRecordingAllowed ? "已允许记录" : "未启用";
        HomeJourneyRecordingText.Foreground = FindBrush(
            _gameplayStatisticsRecorder.IsRecordingAllowed ? "StatusSuccessBrush" : "MutedTextBrush",
            _gameplayStatisticsRecorder.IsRecordingAllowed ? Brushes.SpringGreen : Brushes.SlateGray);
        HomeJourneyUpdatedText.Text = _lastGameLogReadAt == DateTimeOffset.MinValue
            ? "等待 Game.log"
            : $"Game.log · {_lastGameLogReadAt.LocalDateTime:HH:mm:ss}";
    }

    private void RefreshHomePendingItems()
    {
        _homePendingItems.Clear();
        var warning = FindBrush("StatusWarningBrush", Brushes.Goldenrod);
        var accent = FindBrush("AccentBrush", Brushes.DeepSkyBlue);
        var danger = FindBrush("StatusDangerBrush", Brushes.IndianRed);
        var success = FindBrush("StatusSuccessBrush", Brushes.SpringGreen);

        void Add(string key, string title, string detail, Brush brush)
        {
            if (_homePendingItems.Count < 4)
            {
                _homePendingItems.Add(new HomeDashboardActionRow(key, title, detail, brush, true));
            }
        }

        if (!IsLoggedIn)
        {
            Add("login", "登录或注册账号", "同步好友、舰队、房间与个人资料", accent);
        }

        if (string.IsNullOrWhiteSpace(_logPath) || !File.Exists(_logPath))
        {
            Add("log", "连接 Game.log", "识别游戏身份、舰船、地点与会话状态", warning);
        }

        if (IsLoggedIn && _identityBindingSupported && !CanSynchronizeUserData)
        {
            var detail = _identityBindingAssessment.State == IdentityVerificationState.Mismatch
                ? "当前游戏 ID 与绑定信息不一致，同步已暂停"
                : "确认当前游戏 ID 后即可启用多人同步";
            Add("identity", "完成游戏身份验证", detail, danger);
        }

        var incomingFriendRequests = _friendCenterSnapshot?.IncomingRequests.Length ?? 0;
        if (incomingFriendRequests > 0)
        {
            Add("friends", $"{incomingFriendRequests} 个好友申请", "前往好友中心处理申请", accent);
        }

        var pendingFleetApplications = CountPendingFleetApplications();
        if (pendingFleetApplications > 0 && CanCurrentUserManageFleetInfo())
        {
            Add("fleet-applications", $"{pendingFleetApplications} 个舰队加入申请", "直接前往审核队列", warning);
        }

        var pendingRoomApplications = _currentPartyRoom is { ViewerIsHost: true } room
            ? room.PendingApplications.Length
            : 0;
        if (pendingRoomApplications > 0)
        {
            Add("room", $"{pendingRoomApplications} 个房间加入申请", "返回当前房间处理申请", warning);
        }

        var directUnread = _friendChatConversations.Sum(row => row.Conversation.UnreadCount);
        var totalUnread = directUnread + Math.Max(0, _fleetChatTotalUnread);
        if (totalUnread > 0)
        {
            Add("messages", $"{totalUnread} 条未读消息", "查看好友私聊与舰队通讯", success);
        }

        HomePendingCountText.Text = $"{_homePendingItems.Count} 项";
        if (_homePendingItems.Count == 0)
        {
            _homePendingItems.Add(new HomeDashboardActionRow(
                "none",
                "当前没有待处理事项",
                "舰桥状态正常，可以继续当前航程",
                FindBrush("StatusDisabledBrush", Brushes.SlateGray),
                false));
        }
    }

    private void RefreshHomeFleetAndCommunication()
    {
        HomeFleetTitleText.Text = _hasFleet && !string.IsNullOrWhiteSpace(_fleetName)
            ? _fleetName
            : "舰队与通讯";
        HomeFleetActionButton.Content = _hasFleet ? "进入我的舰队" : "寻找舰队";
        HomeFleetActionButton.Tag = _hasFleet ? "fleet" : "find-fleet";

        if (_hasFleet)
        {
            var announcementTitle = _fleetCurrentAnnouncement?.Title ?? _fleetNoticeTitle;
            var announcementContent = _fleetCurrentAnnouncement?.Content ?? _fleetNoticeContent;
            HomeFleetAnnouncementTitleText.Text = string.IsNullOrWhiteSpace(announcementTitle)
                ? "暂无当前公告"
                : announcementTitle;
            HomeFleetAnnouncementDetailText.Text = string.IsNullOrWhiteSpace(announcementContent)
                ? "舰队当前没有正在广播的公告。"
                : announcementContent;
        }
        else
        {
            HomeFleetAnnouncementTitleText.Text = "尚未加入舰队";
            HomeFleetAnnouncementDetailText.Text = "寻找适合你的舰队，或使用邀请码加入。";
        }

        if (_currentPartyRoom is { } room)
        {
            HomePartyRoomTitleText.Text = room.Title;
            HomePartyRoomDetailText.Text = $"{room.MemberCount} / {room.Capacity} 人 · {room.GoalDisplay}";
        }
        else
        {
            HomePartyRoomTitleText.Text = "当前未加入房间";
            HomePartyRoomDetailText.Text = "前往组队大厅寻找临时队友。";
        }

        var latestFleetMessage = _fleetMemberSidebarChatPreview.LastOrDefault() ?? _fleetChatMessages.LastOrDefault();
        if (_hasFleet && latestFleetMessage is not null)
        {
            var preview = !string.IsNullOrWhiteSpace(latestFleetMessage.Text)
                ? latestFleetMessage.Text
                : latestFleetMessage.Attachment?.Title ?? "发送了一条舰队消息";
            HomeFleetCommunicationText.Text = $"{latestFleetMessage.SenderCallsign}：{preview}";
        }
        else
        {
            HomeFleetCommunicationText.Text = _hasFleet ? "暂无新消息" : "加入舰队后可使用舰队与小队频道";
        }

        HomeFleetUnreadText.Text = _fleetChatTotalUnread > 0
            ? $"{(_fleetChatTotalUnread > 99 ? "99+" : _fleetChatTotalUnread.ToString(CultureInfo.InvariantCulture))} 未读"
            : "";
    }

    private void RefreshHomeRecentEvents()
    {
        _homeRecentEvents.Clear();
        var entries = _localGameEventJournal.Entries.Take(4).ToArray();
        foreach (var entry in entries)
        {
            _homeRecentEvents.Add(new HomeDashboardEventRow(
                entry.Title,
                string.IsNullOrWhiteSpace(entry.Detail) ? FormatHomeEventCategory(entry.Category) : entry.Detail,
                CommunicationTimeFormatter.Format(entry.OccurredAt),
                GetHomeEventAccent(entry.Category)));
        }

        HomeRecentEventCountText.Text = $"{_localGameEventJournal.Entries.Length} 条";
        if (_homeRecentEvents.Count == 0)
        {
            _homeRecentEvents.Add(new HomeDashboardEventRow(
                "等待新的游戏事件",
                "连接 Game.log 后，最近识别结果会出现在这里。",
                "",
                FindBrush("StatusDisabledBrush", Brushes.SlateGray)));
        }
    }

    private async void HomePrimaryActionButton_Click(object sender, RoutedEventArgs e)
    {
        switch (HomePrimaryActionButton.Tag as string)
        {
            case "login":
                await ShowLoginDialogAsync();
                if (IsLoggedIn)
                {
                    await AutoConnectNetworkAsync();
                }
                break;
            case "log":
            case "identity":
                OpenPersonalIdentitySettings_Click(sender, e);
                break;
            case "room":
                MySquadNav_Click(sender, e);
                break;
            case "overlay":
                OverlayNav_Click(sender, e);
                break;
            case "find-fleet":
                FindFleetNav_Click(sender, e);
                break;
            case "fleet-chat":
                NavigateToMyFleet();
                NavigateToFleetChatFromMemberPreview();
                await OpenFleetChatAsync();
                break;
        }

        RefreshHomeDashboard();
    }

    private void HomeOpenPersonalProfileButton_Click(object sender, RoutedEventArgs e) =>
        PersonalNav_Click(sender, e);

    private void HomeFleetActionButton_Click(object sender, RoutedEventArgs e)
    {
        if (HomeFleetActionButton.Tag as string == "fleet")
        {
            NavigateToMyFleet();
            return;
        }

        FindFleetNav_Click(sender, e);
    }

    private async void HomePendingItemButton_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is not HomeDashboardActionRow row)
        {
            return;
        }

        switch (row.Key)
        {
            case "login":
                await ShowLoginDialogAsync();
                if (IsLoggedIn)
                {
                    await AutoConnectNetworkAsync();
                }
                break;
            case "log":
            case "identity":
                OpenPersonalIdentitySettings_Click(sender, e);
                break;
            case "friends":
                HeaderFriendCenterButton_Click(HeaderFriendCenterButton, e);
                break;
            case "fleet-applications":
                OpenFleetApplicationReviewQueue();
                break;
            case "room":
                MySquadNav_Click(sender, e);
                break;
            case "messages":
                if (_fleetChatTotalUnread > 0 && _hasFleet)
                {
                    NavigateToMyFleet();
                    NavigateToFleetChatFromMemberPreview();
                    await OpenFleetChatAsync();
                }
                else
                {
                    HeaderFriendCenterButton_Click(HeaderFriendCenterButton, e);
                }
                break;
        }
    }

    private void HomeOpenLocalJournalButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryLeaveOverlayEditorTab())
        {
            return;
        }

        var previousTab = MainTabs.SelectedItem;
        MainTabs.SelectedItem = SettingsTab;
        SetActiveNav(HeaderSettingsButton);
        ShowPersonalSection(PersonalSection.AppSettings);
        ShowPersonalDashboardSection(PersonalDashboardSection.AppSettings);
        QueueMainPageReveal(previousTab);
        Dispatcher.BeginInvoke(
            DispatcherPriority.Loaded,
            new Action(() => LocalGameEventList?.BringIntoView()));
    }

    private void HomeOpenUnofficialDisclaimerButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryLeaveOverlayEditorTab())
        {
            return;
        }

        var previousTab = MainTabs.SelectedItem;
        MainTabs.SelectedItem = SupportTab;
        SetActiveNav(null);
        ShowHelpSupportSection("privacy", HelpSupportPrivacyButton, animate: false);
        HelpSupportUnofficialExpander.IsExpanded = true;
        Dispatcher.BeginInvoke(
            DispatcherPriority.Loaded,
            new Action(() => HelpSupportUnofficialExpander.BringIntoView()));
        QueueMainPageReveal(previousTab);
    }

    private (string Key, string Label) ResolveHomePrimaryAction()
    {
        if (!IsLoggedIn)
        {
            return ("login", "登录 / 注册");
        }

        if (string.IsNullOrWhiteSpace(_logPath) || !File.Exists(_logPath))
        {
            return ("log", "连接 Game.log");
        }

        if (_identityBindingSupported && !CanSynchronizeUserData)
        {
            return ("identity", "检查身份验证");
        }

        if (_currentPartyRoom is not null)
        {
            return ("room", "返回当前房间");
        }

        if (_isGameProcessRunning)
        {
            return ("overlay", IsOverlayRunning ? "调整游戏浮层" : "开启游戏浮层");
        }

        if (!_hasFleet)
        {
            return ("find-fleet", "寻找舰队");
        }

        return ("fleet-chat", "打开舰队通讯");
    }

    private FleetPlayer? GetHomeLocalPlayer()
    {
        if (string.IsNullOrWhiteSpace(_localPlayer))
        {
            return null;
        }

        return _fleetState.Players.FirstOrDefault(player =>
            player.Name.Equals(_localPlayer, StringComparison.OrdinalIgnoreCase));
    }

    private string GetHomeCurrentSessionDurationText()
    {
        var entries = _localGameEventJournal.Entries;
        var lastStarted = entries.FirstOrDefault(entry => entry.EventType == "GameStarted");
        var lastStopped = entries.FirstOrDefault(entry => entry.EventType == "GameStopped");
        if (lastStarted is null || lastStopped is not null && lastStopped.OccurredAt > lastStarted.OccurredAt)
        {
            return "本次会话已开始";
        }

        var elapsed = DateTimeOffset.Now - lastStarted.OccurredAt;
        if (elapsed < TimeSpan.Zero)
        {
            elapsed = TimeSpan.Zero;
        }

        return elapsed.TotalHours >= 1
            ? $"已连续运行 {(int)elapsed.TotalHours} 小时 {elapsed.Minutes} 分钟"
            : $"已连续运行 {Math.Max(1, elapsed.Minutes)} 分钟";
    }

    private void ApplyHomeStatus(Ellipse dot, TextBlock text, string label, string brushKey)
    {
        var fallback = brushKey switch
        {
            "StatusSuccessBrush" => Brushes.SpringGreen,
            "StatusWarningBrush" => Brushes.Goldenrod,
            "StatusDangerBrush" => Brushes.IndianRed,
            _ => Brushes.SlateGray
        };
        var brush = FindBrush(brushKey, fallback);
        dot.Fill = brush;
        text.Text = label;
        text.Foreground = brush;
    }

    private Brush GetHomeEventAccent(string category) => category switch
    {
        LocalGameEventCategories.Session => FindBrush("StatusSuccessBrush", Brushes.SpringGreen),
        LocalGameEventCategories.Identity => FindBrush("AccentBrush", Brushes.DeepSkyBlue),
        LocalGameEventCategories.Server => FindBrush("StatusInfoBrush", Brushes.DodgerBlue),
        LocalGameEventCategories.Ship => HomeBrush("#7BB6D8"),
        LocalGameEventCategories.Location => FindBrush("StatusWarningBrush", Brushes.Goldenrod),
        LocalGameEventCategories.Life => FindBrush("StatusDangerBrush", Brushes.IndianRed),
        _ => FindBrush("StatusDisabledBrush", Brushes.SlateGray)
    };

    private static Brush HomeBrush(string color)
    {
        var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
        brush.Freeze();
        return brush;
    }

    private static string FormatHomeEventCategory(string category) => category switch
    {
        LocalGameEventCategories.Session => "游戏会话",
        LocalGameEventCategories.Identity => "身份识别",
        LocalGameEventCategories.Server => "服务器",
        LocalGameEventCategories.Ship => "舰船",
        LocalGameEventCategories.Location => "地点",
        LocalGameEventCategories.Life => "生命状态",
        _ => "本地事件"
    };

    private static string FormatHomeConfidence(string? confidence) => confidence?.Trim().ToLowerInvariant() switch
    {
        "high" => "高",
        "medium" => "中",
        "low" => "低",
        _ => "待确认"
    };

    private static bool IsHomeUnknown(string? value) =>
        string.IsNullOrWhiteSpace(value) ||
        value.Equals("Unknown", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("None", StringComparison.OrdinalIgnoreCase);

    private static string BuildHomeInitials(string value)
    {
        var parts = value.Split([' ', '_', '-'], StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0)
        {
            return "SB";
        }

        return parts.Length > 1
            ? string.Concat(parts[0][0], parts[1][0]).ToUpperInvariant()
            : parts[0][..Math.Min(2, parts[0].Length)].ToUpperInvariant();
    }
}

internal sealed record HomeDashboardActionRow(
    string Key,
    string Title,
    string Detail,
    Brush AccentBrush,
    bool IsEnabled);

internal sealed record HomeDashboardEventRow(
    string Title,
    string Detail,
    string TimeText,
    Brush AccentBrush);
