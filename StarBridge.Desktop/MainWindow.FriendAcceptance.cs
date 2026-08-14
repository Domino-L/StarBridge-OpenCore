using StarBridge.Core.Friends;
using StarBridge.Core.Presence;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using Button = System.Windows.Controls.Button;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private bool IsFriendCenterAcceptanceMode
    {
        get
        {
#if DEBUG
            return _friendCenterAcceptanceMode;
#else
            return false;
#endif
        }
    }

    private void InitializeFriendCenterAcceptanceScenarios()
    {
        if (!AcceptanceControlPolicy.IsVisible)
        {
            return;
        }

#if DEBUG
        if (_friendCenterAcceptanceScenarioButton is not null)
        {
            return;
        }

        FriendCenterHeaderActionsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        _friendCenterAcceptanceScenarioButton = new Button
        {
            Content = "验收场景",
            MinWidth = 96,
            Height = 34,
            Margin = new Thickness(8, 0, 0, 0),
            ToolTip = "切换好友中心的模拟验收状态",
            Style = (Style)FindResource("FriendCenterSecondaryButtonStyle")
        };
        AutomationProperties.SetName(_friendCenterAcceptanceScenarioButton, "好友中心验收场景");
        _friendCenterAcceptanceScenarioButton.Click += FriendCenterAcceptanceScenarioButton_Click;
        Grid.SetColumn(_friendCenterAcceptanceScenarioButton, 5);
        FriendCenterHeaderActionsGrid.Children.Add(_friendCenterAcceptanceScenarioButton);

        var popupContent = BuildFriendCenterAcceptanceScenarioPanel();
        _friendCenterAcceptanceScenarioPopup = new Popup
        {
            Placement = PlacementMode.Bottom,
            PlacementTarget = _friendCenterAcceptanceScenarioButton,
            StaysOpen = false,
            AllowsTransparency = true,
            Child = popupContent
        };
        FriendCenterHeaderActionsGrid.Children.Add(_friendCenterAcceptanceScenarioPopup);
#endif
    }

    private void SelectFriendAcceptanceConversation(FriendChatConversationRow row)
    {
#if DEBUG
        if (!IsFriendCenterAcceptanceMode)
        {
            return;
        }

        ApplyFriendAcceptanceConversation(row);
#endif
    }

#if DEBUG
    private static readonly string[] FriendAcceptanceCallsigns =
    [
        "曙光",
        "星港守望",
        "北辰",
        "远航者",
        "白鲸",
        "折跃信标",
        "边境巡航员",
        "阿卡迪亚",
        "晨星",
        "静默航线",
        "深空回声",
        "奥德赛",
        "星海旅人",
        "赤色彗星",
        "长夜灯塔",
        "第七码头",
        "银翼",
        "极光观测站",
        "联合巡航观察员",
        "新巴贝奇夜班引航员",
        "地平线之外",
        "狮鹫",
        "坠星",
        "远日点"
    ];

    private bool _friendCenterAcceptanceMode;
    private Button? _friendCenterAcceptanceScenarioButton;
    private Popup? _friendCenterAcceptanceScenarioPopup;

    private Border BuildFriendCenterAcceptanceScenarioPanel()
    {
        var panel = new StackPanel();
        var title = new TextBlock
        {
            Text = "验收场景",
            FontWeight = FontWeights.SemiBold
        };
        title.SetResourceReference(TextBlock.ForegroundProperty, "BridgeInk");
        title.SetResourceReference(TextBlock.FontFamilyProperty, "BridgeCjkFont");
        title.SetResourceReference(TextBlock.FontSizeProperty, "BridgeFontBody");
        panel.Children.Add(title);

        var description = new TextBlock
        {
            Text = "仅更改当前窗口显示，不会修改账户数据。",
            Margin = new Thickness(0, 3, 0, 10),
            TextWrapping = TextWrapping.Wrap,
            Style = (Style)FindResource("BridgeAuxTextStyle")
        };
        panel.Children.Add(description);

        panel.Children.Add(CreateFriendCenterAcceptanceScenarioButton("live", "返回实际数据", true));
        panel.Children.Add(CreateFriendCenterAcceptanceScenarioButton("loading", "正在同步"));
        panel.Children.Add(CreateFriendCenterAcceptanceScenarioButton("no-permission", "未登录或不可用"));
        panel.Children.Add(CreateFriendCenterAcceptanceScenarioButton("empty", "空好友列表"));
        panel.Children.Add(CreateFriendCenterAcceptanceScenarioButton("single", "单个好友"));
        panel.Children.Add(CreateFriendCenterAcceptanceScenarioButton("many", "多位好友"));
        panel.Children.Add(CreateFriendCenterAcceptanceScenarioButton("relationships", "申请与屏蔽"));
        panel.Children.Add(CreateFriendCenterAcceptanceScenarioButton("cached-offline", "有缓存时断网"));
        panel.Children.Add(CreateFriendCenterAcceptanceScenarioButton("offline-error", "无缓存时断网"));
        panel.Children.Add(CreateFriendCenterAcceptanceScenarioButton("search", "搜索结果"));
        panel.Children.Add(CreateFriendCenterAcceptanceScenarioButton("conversation", "私信会话"));
        panel.Children.Add(CreateFriendCenterAcceptanceScenarioButton("badges", "统一角标", bottomMargin: 0));

        var border = new Border
        {
            Width = 250,
            Margin = new Thickness(0, 6, 0, 0),
            Padding = new Thickness(12),
            BorderThickness = new Thickness(1),
            Child = panel
        };
        border.SetResourceReference(Border.BackgroundProperty, "BridgePanelRaised");
        border.SetResourceReference(Border.BorderBrushProperty, "BridgeHairline");
        return border;
    }

    private Button CreateFriendCenterAcceptanceScenarioButton(
        string scenario,
        string label,
        bool primary = false,
        double bottomMargin = 4)
    {
        var button = new Button
        {
            Tag = scenario,
            Content = label,
            Height = 32,
            Margin = new Thickness(0, 0, 0, bottomMargin),
            Style = (Style)FindResource(primary
                ? "FriendCenterPrimaryButtonStyle"
                : "FriendCenterSecondaryButtonStyle")
        };
        button.Click += FriendCenterAcceptanceScenarioMenuItem_Click;
        return button;
    }

    private void FriendCenterAcceptanceScenarioButton_Click(object sender, RoutedEventArgs e)
    {
        if (_friendCenterAcceptanceScenarioPopup is not null)
        {
            _friendCenterAcceptanceScenarioPopup.IsOpen = !_friendCenterAcceptanceScenarioPopup.IsOpen;
        }
    }

    private async void FriendCenterAcceptanceScenarioMenuItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string scenario })
        {
            return;
        }

        if (_friendCenterAcceptanceScenarioPopup is not null)
        {
            _friendCenterAcceptanceScenarioPopup.IsOpen = false;
        }

        await ApplyFriendCenterAcceptanceScenarioAsync(scenario);
    }

    private async Task ApplyFriendCenterAcceptanceScenarioAsync(string scenario)
    {
        if (scenario == "live")
        {
            await RestoreFriendCenterLiveDataAsync();
            return;
        }

        _friendCenterAcceptanceMode = true;
        ResetFriendCenterAcceptancePresentation();
        FriendSearchBox.Clear();
        SetFriendCenterAcceptanceButtonLabel(GetFriendCenterAcceptanceScenarioLabel(scenario));

        switch (scenario)
        {
            case "loading":
                SetFriendCenterViewState(FriendCenterViewState.Loading);
                SetFriendCenterStatus("模拟场景 · 正在同步", StatusPalette.InfoBrush);
                break;
            case "no-permission":
                SetFriendCenterViewState(FriendCenterViewState.NoPermission);
                SetFriendCenterStatus("模拟场景 · 当前账号不可用", StatusPalette.DisabledBrush);
                break;
            case "empty":
                ApplyFriendCenterAcceptanceSnapshot(CreateFriendCenterAcceptanceSnapshot(0));
                SetFriendCenterStatus("模拟场景 · 好友列表为空", StatusPalette.InfoBrush);
                break;
            case "single":
                ApplyFriendCenterAcceptanceSnapshot(CreateFriendCenterAcceptanceSnapshot(1));
                SetFriendCenterStatus("模拟场景 · 单个好友", StatusPalette.InfoBrush);
                break;
            case "many":
                ApplyFriendCenterAcceptanceSnapshot(CreateFriendCenterAcceptanceSnapshot(24));
                SetFriendCenterStatus("模拟场景 · 多位好友", StatusPalette.InfoBrush);
                break;
            case "relationships":
                ApplyFriendCenterAcceptanceSnapshot(CreateFriendCenterRelationshipAcceptanceSnapshot());
                SetFriendCenterSection(FriendCenterSection.Incoming);
                SetFriendCenterStatus("模拟场景 · 可切换查看申请与屏蔽", StatusPalette.WarningBrush);
                break;
            case "cached-offline":
                ApplyFriendCenterAcceptanceSnapshot(CreateFriendCenterAcceptanceSnapshot(8));
                SetFriendCenterDegradedState(
                    true,
                    "连接暂时不可用，当前显示上次同步的好友数据。恢复连接后会自动更新。");
                SetFriendCenterStatus("模拟场景 · 显示缓存数据", StatusPalette.WarningBrush);
                break;
            case "offline-error":
                SetFriendCenterViewState(
                    FriendCenterViewState.Error,
                    "网络连接长时间没有响应，好友、申请与在线状态暂时无法读取。请确认设备已连接网络，或稍后重新尝试；你已有的账户资料不会受到影响。");
                SetFriendCenterStatus("模拟场景 · 数据暂时不可用", StatusPalette.DangerBrush);
                break;
            case "search":
                ApplyFriendCenterAcceptanceSnapshot(CreateFriendCenterAcceptanceSnapshot(3));
                _friendSearchResults = Enumerable.Range(30, 7)
                    .Select(index => CreateFriendCenterAcceptanceUser(index, FriendRelationshipStates.None))
                    .ToArray();
                FriendSearchBox.Text = "星港";
                SetFriendCenterSection(FriendCenterSection.Search);
                SetFriendCenterStatus("模拟场景 · 找到 7 位用户", StatusPalette.InfoBrush);
                break;
            case "conversation":
                ApplyFriendCenterAcceptanceConversationScenario();
                SetFriendCenterStatus("模拟场景 · 私信会话", StatusPalette.InfoBrush);
                break;
            case "badges":
                ApplyFriendCenterAcceptanceConversationScenario();
                RefreshNavigationActivityBadges();
                BridgeInboxUnreadBadgeText.Text = "12";
                BridgeInboxUnreadBadge.Visibility = Visibility.Visible;
                SetFriendCenterStatus("模拟场景 · 三处统一角标", StatusPalette.InfoBrush);
                break;
        }
    }

    private void ResetFriendCenterAcceptancePresentation()
    {
        _friendCenterSnapshot = null;
        _friendSearchResults = [];
        _friendCenterRows.Clear();
        _friendChatConversations.Clear();
        _friendChatMessages.Clear();
        _activeFriendChatUser = null;
        _activeFriendChatConversation = null;
        _activeFriendChatOrigin = DirectMessageOrigins.Unknown;
        _friendChatLatestSequence = 0;
        ResetFriendChatPagingState();

        FriendCenterFriendsCountText.Text = "0";
        FriendCenterIncomingCountText.Text = "0";
        FriendCenterOutgoingCountText.Text = "0";
        FriendCenterBlockedCountText.Text = "0";
        FriendCenterConversationUnreadText.Text = "0";
        FriendCenterConversationUnreadBadge.Visibility = Visibility.Collapsed;
        ApplyFriendCenterCountVisuals(0, 0, 0, 0);
        RefreshNavigationActivityBadges();
        RefreshBridgeNotificationBadge();
        SetFriendCenterDegradedState(false);
        SetFriendCenterViewState(FriendCenterViewState.Content);
        SetFriendCenterSection(FriendCenterSection.Friends);
        FriendChatConversationEmptyState.Visibility = Visibility.Visible;
        FriendChatMessageEmptyState.Visibility = Visibility.Visible;
        FriendChatMessageList.Visibility = Visibility.Collapsed;
        RenderActiveFriendChat();
    }

    private void ApplyFriendCenterAcceptanceSnapshot(FriendCenterSnapshotContract snapshot)
    {
        _friendCenterSnapshot = snapshot;
        FriendCenterFriendsCountText.Text = snapshot.Friends.Length.ToString();
        FriendCenterIncomingCountText.Text = snapshot.IncomingRequests.Length.ToString();
        FriendCenterOutgoingCountText.Text = snapshot.OutgoingRequests.Length.ToString();
        FriendCenterBlockedCountText.Text = snapshot.BlockedUsers.Length.ToString();
        ApplyFriendCenterCountVisuals(
            snapshot.Friends.Length,
            snapshot.IncomingRequests.Length,
            snapshot.OutgoingRequests.Length,
            snapshot.BlockedUsers.Length);
        SetFriendCenterViewState(FriendCenterViewState.Content);
        SetFriendCenterDegradedState(false);
        SetFriendCenterSection(FriendCenterSection.Friends);
    }

    private FriendCenterSnapshotContract CreateFriendCenterAcceptanceSnapshot(int friendCount)
    {
        var friends = Enumerable.Range(0, friendCount)
            .Select(index => CreateFriendCenterAcceptanceEntry(index, FriendRelationshipStates.Friend))
            .ToArray();
        return new FriendCenterSnapshotContract(friends, [], [], [], DateTimeOffset.Now);
    }

    private FriendCenterSnapshotContract CreateFriendCenterRelationshipAcceptanceSnapshot() => new(
        Enumerable.Range(0, 6)
            .Select(index => CreateFriendCenterAcceptanceEntry(index, FriendRelationshipStates.Friend))
            .ToArray(),
        Enumerable.Range(10, 3)
            .Select(index => CreateFriendCenterAcceptanceEntry(index, FriendRelationshipStates.Incoming))
            .ToArray(),
        Enumerable.Range(14, 2)
            .Select(index => CreateFriendCenterAcceptanceEntry(index, FriendRelationshipStates.Outgoing))
            .ToArray(),
        Enumerable.Range(18, 4)
            .Select(index => CreateFriendCenterAcceptanceEntry(index, FriendRelationshipStates.Blocked))
            .ToArray(),
        DateTimeOffset.Now);

    private FriendEntryContract CreateFriendCenterAcceptanceEntry(int index, string relationshipState) =>
        new(
            CreateFriendCenterAcceptanceUser(index, relationshipState),
            DateTimeOffset.Now.AddMinutes(-(index + 1) * 6));

    private FriendUserContract CreateFriendCenterAcceptanceUser(int index, string relationshipState)
    {
        var presence = (index % 4) switch
        {
            0 => PlayerPresenceKind.InGame,
            1 => PlayerPresenceKind.AppOnline,
            2 => PlayerPresenceKind.Away,
            _ => PlayerPresenceKind.Offline
        };
        var callsign = FriendAcceptanceCallsigns[index % FriendAcceptanceCallsigns.Length];
        return new FriendUserContract(
            $"debug-acceptance-{index:00}",
            callsign,
            $"Citizen-{2800 + index}",
            null,
            PlayerPresence.ToWireValue(presence),
            relationshipState,
            DateTimeOffset.Now.AddMinutes(-(index + 1) * 3));
    }

    private void ApplyFriendCenterAcceptanceConversationScenario()
    {
        ApplyFriendCenterAcceptanceSnapshot(CreateFriendCenterAcceptanceSnapshot(5));
        var users = Enumerable.Range(0, 4)
            .Select(index => CreateFriendCenterAcceptanceUser(index, FriendRelationshipStates.Friend))
            .ToArray();
        var now = DateTimeOffset.Now;
        _friendChatConversations.Clear();
        for (var index = 0; index < users.Length; index++)
        {
            var conversation = new FriendChatConversationContract(
                users[index],
                index == 0 ? "今晚一起测试房间吗？" : "收到，稍后联系。",
                now.AddMinutes(-(index + 1) * 4),
                users[index].AccountId,
                index == 0 ? 3 : 0,
                10 + index,
                DirectMessageConversationStates.Friend,
                new DirectMessageContextContract(
                    DirectMessageOrigins.FriendCenter,
                    SharedFleetName: index == 0 ? "Star Bridge Test Fleet" : null));
            _friendChatConversations.Add(new FriendChatConversationRow(conversation));
        }

        FriendCenterConversationUnreadText.Text = "3";
        FriendCenterConversationUnreadBadge.Visibility = Visibility.Visible;
        FriendChatConversationEmptyState.Visibility = Visibility.Collapsed;
        SetFriendCenterSection(FriendCenterSection.Conversations);
        ApplyFriendAcceptanceConversation(_friendChatConversations[0]);
    }

    private void ApplyFriendAcceptanceConversation(FriendChatConversationRow row)
    {
        _activeFriendChatUser = row.User;
        _activeFriendChatConversation = row.Conversation;
        _activeFriendChatOrigin = DirectMessageOrigins.FriendCenter;
        _friendChatLatestSequence = 4;
        _friendChatMessages.Clear();
        ResetFriendChatPagingState();

        var localAccountId = string.IsNullOrWhiteSpace(_accountId)
            ? "debug-acceptance-local"
            : _accountId;
        var now = DateTimeOffset.Now;
        var messages = new[]
        {
            new FriendChatMessageContract(1, $"debug-message-{row.AccountId}-1", row.AccountId, localAccountId,
                "今晚一起测试房间吗？我准备在赫斯顿附近活动。", now.AddMinutes(-12)),
            new FriendChatMessageContract(2, $"debug-message-{row.AccountId}-2", localAccountId, row.AccountId,
                "可以，我会先检查舰船和补给。", now.AddMinutes(-10)),
            new FriendChatMessageContract(3, $"debug-message-{row.AccountId}-3", row.AccountId, localAccountId,
                "好，准备完成后发我房间邀请。", now.AddMinutes(-8)),
            new FriendChatMessageContract(4, $"debug-message-{row.AccountId}-4", localAccountId, row.AccountId,
                "收到，稍后见。", now.AddMinutes(-6))
        };
        foreach (var message in messages)
        {
            _friendChatMessages.Add(CreateFriendChatMessageRow(message, row.AccountId));
        }

        FriendChatMessageEmptyState.Visibility = Visibility.Collapsed;
        FriendChatMessageList.Visibility = Visibility.Visible;
        FriendChatInputBox.IsEnabled = true;
        FriendChatSendButton.IsEnabled = true;
        FriendChatAttachmentButton.IsEnabled = true;
        RenderActiveFriendChat();
        SelectActiveFriendChatConversation();
        FriendChatStatusText.Text = "模拟场景 · 可以输入，但不会发送消息";
        FriendChatStatusText.Foreground = StatusPalette.InfoBrush;
        ChatHistoryViewport.ScrollToLatest(FriendChatMessageList);
    }

    private async Task RestoreFriendCenterLiveDataAsync()
    {
        _friendCenterAcceptanceMode = false;
        ResetFriendCenterAcceptancePresentation();
        SetFriendCenterAcceptanceButtonLabel(null);
        SetFriendCenterViewState(FriendCenterViewState.Loading);
        SetFriendCenterStatus("正在恢复实际数据…", StatusPalette.InfoBrush);
        await RefreshFriendCenterAsync(showErrors: true);
        await RefreshFriendChatAsync(showErrors: false);
        await RefreshDirectMessagePrivacyAsync(showErrors: false);
    }

    private void SetFriendCenterAcceptanceButtonLabel(string? scenarioLabel)
    {
        if (_friendCenterAcceptanceScenarioButton is null)
        {
            return;
        }

        _friendCenterAcceptanceScenarioButton.Content = string.IsNullOrWhiteSpace(scenarioLabel)
            ? "验收场景"
            : $"场景 · {scenarioLabel}";
        _friendCenterAcceptanceScenarioButton.ToolTip = string.IsNullOrWhiteSpace(scenarioLabel)
            ? "切换好友中心的模拟验收状态"
            : $"正在显示模拟场景：{scenarioLabel}。点击可切换或返回实际数据。";
    }

    private static string GetFriendCenterAcceptanceScenarioLabel(string scenario) => scenario switch
    {
        "loading" => "正在同步",
        "no-permission" => "未登录",
        "empty" => "空列表",
        "single" => "单个好友",
        "many" => "多位好友",
        "relationships" => "申请与屏蔽",
        "cached-offline" => "缓存断网",
        "offline-error" => "断网错误",
        "search" => "搜索结果",
        "conversation" => "私信会话",
        "badges" => "统一角标",
        _ => "验收"
    };
#endif
}
