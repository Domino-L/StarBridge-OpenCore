using StarBridge.Core.PartyRooms;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using Button = System.Windows.Controls.Button;
using Panel = System.Windows.Controls.Panel;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private bool IsFindFleetAcceptanceMode
    {
        get
        {
#if DEBUG
            return _findFleetAcceptanceMode;
#else
            return false;
#endif
        }
    }

    private bool IsPartyLobbyAcceptanceMode
    {
        get
        {
#if DEBUG
            return _partyLobbyAcceptanceMode;
#else
            return false;
#endif
        }
    }

    private bool IsPartyLobbyLoadingAcceptanceMode
    {
        get
        {
#if DEBUG
            return _partyLobbyAcceptanceScenario == "loading";
#else
            return false;
#endif
        }
    }

    private void InitializeDirectoryAcceptanceScenarios()
    {
        if (!AcceptanceControlPolicy.IsVisible)
        {
            return;
        }

#if DEBUG
        if (_findFleetAcceptanceScenarioButton is not null ||
            FindFleetHeaderActionsPanel is null ||
            PartyLobbyHeaderActionsPanel is null)
        {
            return;
        }

        (_findFleetAcceptanceScenarioButton, _findFleetAcceptanceScenarioPopup) =
            CreateDirectoryAcceptanceScenarioControl(
                FindFleetHeaderActionsPanel,
                "寻找舰队验收场景",
                FindFleetAcceptanceScenarioMenuItem_Click);
        (_partyLobbyAcceptanceScenarioButton, _partyLobbyAcceptanceScenarioPopup) =
            CreateDirectoryAcceptanceScenarioControl(
                PartyLobbyHeaderActionsPanel,
                "房间大厅验收场景",
                PartyLobbyAcceptanceScenarioMenuItem_Click);
#endif
    }

#if DEBUG
    private bool _findFleetAcceptanceMode;
    private bool _partyLobbyAcceptanceMode;
    private string? _partyLobbyAcceptanceScenario;
    private Button? _findFleetAcceptanceScenarioButton;
    private Popup? _findFleetAcceptanceScenarioPopup;
    private Button? _partyLobbyAcceptanceScenarioButton;
    private Popup? _partyLobbyAcceptanceScenarioPopup;

    private (Button Button, Popup Popup) CreateDirectoryAcceptanceScenarioControl(
        Panel host,
        string accessibleName,
        RoutedEventHandler scenarioHandler)
    {
        var button = new Button
        {
            Content = "验收场景",
            MinWidth = 96,
            Height = 34,
            Margin = new Thickness(8, 0, 0, 0),
            ToolTip = "切换当前页面的模拟验收状态",
            Style = (Style)FindResource("BridgeDirectorySecondaryButtonStyle")
        };
        AutomationProperties.SetName(button, accessibleName);

        var popup = new Popup
        {
            Placement = PlacementMode.Bottom,
            PlacementTarget = button,
            StaysOpen = false,
            AllowsTransparency = true,
            Child = BuildDirectoryAcceptanceScenarioPanel(scenarioHandler)
        };
        button.Click += (_, _) => popup.IsOpen = !popup.IsOpen;
        host.Children.Add(button);
        host.Children.Add(popup);
        return (button, popup);
    }

    private Border BuildDirectoryAcceptanceScenarioPanel(RoutedEventHandler scenarioHandler)
    {
        var panel = new StackPanel();
        var title = new TextBlock
        {
            Text = "验收场景",
            Style = (Style)FindResource("BridgeDirectorySectionTitleStyle")
        };
        panel.Children.Add(title);
        panel.Children.Add(new TextBlock
        {
            Text = "只改变当前窗口显示，不会修改账号或服务器数据。",
            Margin = new Thickness(0, 3, 0, 10),
            TextWrapping = TextWrapping.Wrap,
            Style = (Style)FindResource("BridgeDirectoryAuxTextStyle")
        });

        AddDirectoryAcceptanceButton(panel, scenarioHandler, "live", "返回实际数据", true);
        AddDirectoryAcceptanceButton(panel, scenarioHandler, "loading", "正在加载");
        AddDirectoryAcceptanceButton(panel, scenarioHandler, "empty", "空目录");
        AddDirectoryAcceptanceButton(panel, scenarioHandler, "no-results", "无匹配结果");
        AddDirectoryAcceptanceButton(panel, scenarioHandler, "filter-conflict", "筛选条件冲突");
        AddDirectoryAcceptanceButton(panel, scenarioHandler, "many", "大量条目");
        AddDirectoryAcceptanceButton(panel, scenarioHandler, "cached-offline", "有缓存时断网");
        AddDirectoryAcceptanceButton(panel, scenarioHandler, "error", "加载失败");
        AddDirectoryAcceptanceButton(panel, scenarioHandler, "no-permission", "当前账号不可用", false, 0);

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

    private void AddDirectoryAcceptanceButton(
        Panel panel,
        RoutedEventHandler handler,
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
                ? "BridgeDirectoryPrimaryButtonStyle"
                : "BridgeDirectorySecondaryButtonStyle")
        };
        button.Click += handler;
        panel.Children.Add(button);
    }

    private async void FindFleetAcceptanceScenarioMenuItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string scenario })
        {
            return;
        }

        if (_findFleetAcceptanceScenarioPopup is not null)
        {
            _findFleetAcceptanceScenarioPopup.IsOpen = false;
        }

        await ApplyFindFleetAcceptanceScenarioAsync(scenario);
    }

    private async Task ApplyFindFleetAcceptanceScenarioAsync(string scenario)
    {
        if (scenario == "live")
        {
            _findFleetAcceptanceMode = false;
            SetDirectoryAcceptanceButtonLabel(_findFleetAcceptanceScenarioButton, "验收场景");
            _fleetDirectoryState.InvalidateLoads();
            FindFleetSearchBox.Clear();
            FindFleetFilterResetButton_Click(this, new RoutedEventArgs());
            await PullNetworkFleetsAsync();
            return;
        }

        _findFleetAcceptanceMode = true;
        ResetFindFleetAcceptancePresentation();
        SetDirectoryAcceptanceButtonLabel(_findFleetAcceptanceScenarioButton, $"场景 · {DirectoryAcceptanceScenarioLabel(scenario)}");

        var cards = scenario switch
        {
            "many" => CreateFindFleetAcceptanceCards(36),
            "cached-offline" => CreateFindFleetAcceptanceCards(8),
            "no-results" or "filter-conflict" => CreateFindFleetAcceptanceCards(6),
            _ => []
        };
        _allNetworkFleets.AddRange(cards);

        var requestVersion = _fleetDirectoryState.BeginLoad(cards.Length > 0);
        switch (scenario)
        {
            case "loading":
                break;
            case "cached-offline":
                _fleetDirectoryState.FailLoad(requestVersion, true, "");
                break;
            case "error":
                _fleetDirectoryState.FailLoad(requestVersion, false, "暂时无法读取舰队目录，请稍后重试。");
                break;
            case "no-permission":
                _fleetDirectoryState.FailLoad(requestVersion, false, "当前账号暂时无法查看公开舰队，请检查登录状态。");
                break;
            default:
                _fleetDirectoryState.CompleteLoad(requestVersion, cards.Length);
                break;
        }

        if (scenario is "no-results" or "filter-conflict")
        {
            FindFleetSearchBox.Text = scenario == "no-results" ? "不存在的舰队" : "互相冲突的筛选条件";
        }

        ApplyFleetSearchFilter();
        RefreshFleetDirectoryViewState();
    }

    private void ResetFindFleetAcceptancePresentation()
    {
        _fleetDirectoryState.InvalidateLoads();
        _allNetworkFleets.Clear();
        _networkFleets.Clear();
        FindFleetSearchBox.Clear();
        SetFindFleetFilterChecks(false);
        _fleetDirectoryState.ApplyFilters(FleetDirectoryFilters.Empty);
        RefreshFindFleetAppliedFilters();
        FindFleetResults.Items.Refresh();
    }

    private NetworkFleetCard[] CreateFindFleetAcceptanceCards(int count)
    {
        var names = new[]
        {
            "星桥联合远征舰队",
            "北辰深空协作组",
            "地平线工业联盟",
            "曙光医疗与救援舰队",
            "长夜灯塔探索协会",
            "新巴贝奇周末飞行团"
        };
        return Enumerable.Range(0, count)
            .Select(index =>
            {
                var name = index == count - 1 && count > 12
                    ? "用于验证极长舰队名称在窄窗口中仍能安全省略而不会挤压操作区域的联合舰队"
                    : $"{names[index % names.Length]} {index + 1:00}";
                var snapshot = new NetworkFleetSnapshot(
                    Name: name,
                    Code: $"QA{index + 1:000}",
                    Commander: index % 3 == 0 ? "多米诺" : $"指挥官 {index + 1:00}",
                    Description: "用于检查列表、筛选、详情、长文案和高密度滚动的模拟舰队资料。",
                    Type: index % 2 == 0 ? "综合协作" : "专项行动",
                    ActiveTime: index % 2 == 0 ? "周末 19:00–23:00" : "工作日 20:00–22:00",
                    JoinPolicy: index % 3 == 0 ? "直接加入" : "申请加入",
                    LogoText: name[..1],
                    LogoImageData: null,
                    OnlineMembers: 1 + index % 8,
                    TotalMembers: 8 + index * 3,
                    NoticeTitle: "公开舰队公告",
                    NoticeContent: "欢迎查看舰队公开资料。",
                    CurrentTaskTitle: null,
                    CurrentTaskBrief: null,
                    CurrentTaskParticipants: null,
                    CurrentTaskRally: null,
                    CurrentTaskShip: null,
                    CurrentTaskTime: null,
                    ActionPlans: null,
                    LastUpdated: DateTimeOffset.Now.AddMinutes(-index * 7),
                    RecruitingEnabled: index % 4 != 0,
                    RecruitingTarget: index % 2 == 0 ? "所有玩家" : "固定活动成员",
                    Language: index % 3 == 0 ? "中英双语" : "中文",
                    ActiveSystemIds: index % 2 == 0 ? ["stanton"] : ["pyro"]);
                return NetworkFleetCard.FromSnapshot(
                    snapshot,
                    _fleetName,
                    _fleetCode,
                    _hasFleet,
                    _pendingFleetApplicationCodes);
            })
            .ToArray();
    }

    private async void PartyLobbyAcceptanceScenarioMenuItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string scenario })
        {
            return;
        }

        if (_partyLobbyAcceptanceScenarioPopup is not null)
        {
            _partyLobbyAcceptanceScenarioPopup.IsOpen = false;
        }

        await ApplyPartyLobbyAcceptanceScenarioAsync(scenario);
    }

    private async Task ApplyPartyLobbyAcceptanceScenarioAsync(string scenario)
    {
        if (scenario == "live")
        {
            _partyLobbyAcceptanceMode = false;
            _partyLobbyAcceptanceScenario = null;
            SetDirectoryAcceptanceButtonLabel(_partyLobbyAcceptanceScenarioButton, "验收场景");
            PartyLobbyClearFilters_Click(this, new RoutedEventArgs());
            await RefreshPartyRoomsFromServerAsync(showErrors: false);
            return;
        }

        _partyLobbyAcceptanceMode = true;
        _partyLobbyAcceptanceScenario = scenario;
        SetDirectoryAcceptanceButtonLabel(_partyLobbyAcceptanceScenarioButton, $"场景 · {DirectoryAcceptanceScenarioLabel(scenario)}");
        PartyLobbyClearFilters_Click(this, new RoutedEventArgs());
        _partyLobbyRooms.Clear();

        var rooms = scenario switch
        {
            "many" => CreatePartyLobbyAcceptanceRooms(36),
            "cached-offline" => CreatePartyLobbyAcceptanceRooms(8),
            "no-results" or "filter-conflict" => CreatePartyLobbyAcceptanceRooms(6),
            _ => []
        };
        foreach (var room in rooms)
        {
            _partyLobbyRooms.Add(room);
        }

        var (title, detail) = scenario switch
        {
            "loading" => ("正在读取房间", "请稍候，房间列表正在同步。"),
            "error" => ("暂时无法读取房间", "网络连接没有响应，请稍后重试。"),
            "no-permission" => ("当前账号不可用", "请检查登录状态后重新打开房间大厅。"),
            "filter-conflict" => ("筛选条件互相冲突", "清除部分条件后即可继续查找房间。"),
            "no-results" => ("没有找到匹配的房间", "可以修改关键词，或清除筛选条件。"),
            _ => ("当前没有可加入的房间", "可以稍后刷新，或创建一间临时房间。")
        };
        PartyLobbyRoomEmptyTitleText.Text = title;
        PartyLobbyRoomEmptyDetailText.Text = detail;

        if (scenario is "no-results" or "filter-conflict")
        {
            PartyLobbySearchBox.Text = scenario == "no-results" ? "不存在的房间" : "互相冲突的筛选条件";
        }

        RefreshPartyLobbyFilter();
        if (_partyLobbyRoomsView?.Cast<PartyLobbyRoomCard>().FirstOrDefault() is { } firstRoom)
        {
            PartyLobbyRoomList.SelectedItem = firstRoom;
            PartyLobbyRoomList.ScrollIntoView(firstRoom);
            RefreshPartyLobbyPreview(firstRoom);
        }
    }

    private PartyLobbyRoomCard[] CreatePartyLobbyAcceptanceRooms(int count)
    {
        var categoryIds = new[] { "combat", "industry", "logistics", "support", "exploration", "arena", "social", "special" };
        var titles = new[] { "赫斯顿赏金协作", "采矿与精炼轮班", "货运护航", "医疗救援待命", "深空探索", "竞技场训练", "休闲观光", "特别行动" };
        return Enumerable.Range(0, count)
            .Select(index => new PartyLobbyRoomCard(
                RoomId: $"qa-room-{index + 1:000}",
                Title: index == count - 1 && count > 12
                    ? "用于验证极长房间名称、多个标签与窄窗口布局仍然稳定的临时协作房间"
                    : $"{titles[index % titles.Length]} {index + 1:00}",
                Goal: "检查房间列表、筛选、详情与长文案在真实密度下的表现。",
                HostDisplay: $"房主 {index + 1:00}",
                Activity: titles[index % titles.Length],
                Tags: [],
                MemberCount: 1 + index % 5,
                Capacity: 6,
                VoiceRequirement: index % 3 == 0 ? PartyLobbyVoiceRequirement.Required : PartyLobbyVoiceRequirement.Recommended,
                AdmissionMode: index % 2 == 0 ? PartyLobbyAdmissionMode.Direct : PartyLobbyAdmissionMode.HostApproval,
                IsPublic: true,
                PasswordRequired: index % 7 == 0,
                Members:
                [
                    new PartyLobbyMemberPreview($"领航员 {index + 1:00}", $"Citizen-{2000 + index}", IsHost: true)
                ],
                UpdatedAt: DateTimeOffset.Now.AddMinutes(-index * 3))
            {
                GameplayTagNodeIds = [categoryIds[index % categoryIds.Length]],
                ContextTagIds = index % 2 == 0 ? ["voice-recommended"] : [],
                TagCatalogVersion = PartyRoomTagCatalog.Version
            })
            .ToArray();
    }

    private static string DirectoryAcceptanceScenarioLabel(string scenario) => scenario switch
    {
        "loading" => "正在加载",
        "empty" => "空目录",
        "no-results" => "无匹配结果",
        "filter-conflict" => "筛选冲突",
        "many" => "大量条目",
        "cached-offline" => "离线缓存",
        "error" => "加载失败",
        "no-permission" => "账号不可用",
        _ => "验收场景"
    };

    private static void SetDirectoryAcceptanceButtonLabel(Button? button, string label)
    {
        if (button is not null)
        {
            button.Content = label;
        }
    }
#endif
}
