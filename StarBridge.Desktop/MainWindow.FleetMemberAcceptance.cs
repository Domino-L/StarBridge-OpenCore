using StarBridge.Core.Presence;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using StarBridge.Desktop.Controls;
using Button = System.Windows.Controls.Button;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void InitializeFleetMemberAcceptanceScenarios()
    {
        if (!AcceptanceControlPolicy.IsVisible)
        {
            return;
        }

#if DEBUG
        if (_fleetMemberAcceptanceScenarioButton is not null)
        {
            return;
        }

        _fleetMemberAcceptanceScenarioButton = new Button
        {
            Content = "验收场景",
            Height = 30,
            MinWidth = 92,
            Margin = new Thickness(0, 0, 10, 0),
            ToolTip = "切换组织成员页的本地模拟状态",
            Style = (Style)FindResource("SecondaryButton")
        };
        AutomationProperties.SetName(_fleetMemberAcceptanceScenarioButton, "组织成员验收场景");
        _fleetMemberAcceptanceScenarioButton.Click += FleetMemberAcceptanceScenarioButton_Click;
        FleetMembersHeaderActionsGrid.Children.Insert(0, _fleetMemberAcceptanceScenarioButton);

        _fleetMemberAcceptanceScenarioPopup = new Popup
        {
            Placement = PlacementMode.Bottom,
            PlacementTarget = _fleetMemberAcceptanceScenarioButton,
            StaysOpen = false,
            AllowsTransparency = true,
            Child = BuildFleetMemberAcceptanceScenarioPanel()
        };
        FleetMembersHeaderActionsGrid.Children.Add(_fleetMemberAcceptanceScenarioPopup);
#endif
    }

#if DEBUG
    private Button? _fleetMemberAcceptanceScenarioButton;
    private Popup? _fleetMemberAcceptanceScenarioPopup;

    private Border BuildFleetMemberAcceptanceScenarioPanel()
    {
        var panel = new StackPanel();
        var title = new TextBlock
        {
            Text = "成员页验收场景",
            FontWeight = FontWeights.SemiBold
        };
        title.SetResourceReference(TextBlock.ForegroundProperty, "BridgeInk");
        title.SetResourceReference(TextBlock.FontFamilyProperty, "BridgeCjkFont");
        title.SetResourceReference(TextBlock.FontSizeProperty, "BridgeFontBody");
        panel.Children.Add(title);

        var description = new TextBlock
        {
            Text = "只改变当前窗口显示，不会修改组织或账号数据。",
            Margin = new Thickness(0, 3, 0, 10),
            TextWrapping = TextWrapping.Wrap
        };
        description.SetResourceReference(TextBlock.ForegroundProperty, "BridgeInk3");
        description.SetResourceReference(TextBlock.FontFamilyProperty, "BridgeCjkFont");
        description.SetResourceReference(TextBlock.FontSizeProperty, "BridgeFontAux");
        panel.Children.Add(description);

        panel.Children.Add(CreateFleetMemberAcceptanceScenarioButton("live", "返回实际数据", true));
        panel.Children.Add(CreateFleetMemberAcceptanceScenarioButton("other-commander", "指挥官是别人"));
        panel.Children.Add(CreateFleetMemberAcceptanceScenarioButton("all-states", "全部成员状态"));
        panel.Children.Add(CreateFleetMemberAcceptanceScenarioButton("loading", "正在同步"));
        panel.Children.Add(CreateFleetMemberAcceptanceScenarioButton("empty", "空成员列表"));
        panel.Children.Add(CreateFleetMemberAcceptanceScenarioButton("error", "读取失败"));
        panel.Children.Add(CreateFleetMemberAcceptanceScenarioButton("timeout", "同步超时"));
        panel.Children.Add(CreateFleetMemberAcceptanceScenarioButton("no-permission", "无查看权限"));
        panel.Children.Add(CreateFleetMemberAcceptanceScenarioButton("cached-offline", "离线缓存"));
        panel.Children.Add(CreateFleetMemberAcceptanceScenarioButton("reduced-motion", "减少动态效果", bottomMargin: 0));

        var border = new Border
        {
            Width = 230,
            Margin = new Thickness(0, 6, 0, 0),
            Padding = new Thickness(12),
            BorderThickness = new Thickness(1),
            Child = panel
        };
        border.SetResourceReference(Border.BackgroundProperty, "BridgePanelRaised");
        border.SetResourceReference(Border.BorderBrushProperty, "BridgeHairline");
        return border;
    }

    private Button CreateFleetMemberAcceptanceScenarioButton(
        string scenario,
        string label,
        bool primary = false,
        double bottomMargin = 4)
    {
        var button = new Button
        {
            Tag = scenario,
            Content = label,
            Height = 30,
            Margin = new Thickness(0, 0, 0, bottomMargin),
            Style = (Style)FindResource(primary ? "PrimaryButton" : "SecondaryButton")
        };
        button.Click += FleetMemberAcceptanceScenarioMenuItem_Click;
        return button;
    }

    private void FleetMemberAcceptanceScenarioButton_Click(object sender, RoutedEventArgs e)
    {
        if (_fleetMemberAcceptanceScenarioPopup is not null)
        {
            _fleetMemberAcceptanceScenarioPopup.IsOpen = !_fleetMemberAcceptanceScenarioPopup.IsOpen;
        }
    }

    private void FleetMemberAcceptanceScenarioMenuItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string scenario })
        {
            return;
        }

        if (_fleetMemberAcceptanceScenarioPopup is not null)
        {
            _fleetMemberAcceptanceScenarioPopup.IsOpen = false;
        }

        ApplyFleetMemberAcceptanceScenario(scenario);
    }

    private void ApplyFleetMemberAcceptanceScenario(string scenario)
    {
        if (scenario == "live")
        {
            RestoreFleetMemberLiveData();
            return;
        }

        if (scenario is "loading" or "empty" or "error" or "timeout" or "no-permission" or "cached-offline" or "reduced-motion")
        {
            ApplyFleetStateAcceptanceScenario(scenario);
            return;
        }

        ResetFleetStateAcceptanceScenario();

        FleetMembersSearchBox.Clear();
        FleetMembersSearchBox.IsEnabled = true;

        var rows = scenario switch
        {
            "other-commander" => CreateFleetMemberOtherCommanderScenario(),
            "all-states" => CreateFleetMemberAllStatesScenario(),
            _ => []
        };
        FleetMembersDeckList.ItemsSource = rows;

        (FleetMembersSearchEmptyText.Text, FleetMembersSearchEmptyDetailText.Text) = scenario switch
        {
            _ => ("暂无组织成员", "成员加入组织后将在此显示。")
        };
        SetFleetMemberAcceptanceButtonLabel(GetFleetMemberAcceptanceScenarioLabel(scenario));
    }

    private void RestoreFleetMemberLiveData()
    {
        ResetFleetStateAcceptanceScenario();
        RefreshStartupDataGatePresentation();
        FleetMembersSearchBox.IsEnabled = true;
        FleetMembersSearchBox.Clear();
        FleetMembersDeckList.ItemsSource = _fleetMemberSearchView;
        _fleetMemberSearchView?.Refresh();
        FleetMembersSearchEmptyText.Text = "暂无组织成员";
        FleetMembersSearchEmptyDetailText.Text = "成员加入组织后将在此显示。";
        SetFleetMemberAcceptanceButtonLabel(null);
    }

    private static PlayerRow[] CreateFleetMemberAllStatesScenario() =>
    [
        CreateFleetMemberAcceptanceRow("多米诺", "domino_CN", "组织负责人", "Online", "InGame", "圣盾 伊德里斯-P", "地点：新巴贝奇", "pub_use1", true, true, FleetCommanderDefaultRoleColor),
        CreateFleetMemberAcceptanceRow("曙光", "Citizen-2800", "组织副负责人", "Online", "AppOnline", "Unknown", "Unknown", null, false, false, FleetRoleColorPalette.Blue),
        CreateFleetMemberAcceptanceRow("北辰", "Citizen-2801", "成员", "Offline", "Offline", "Unknown", "Unknown", null, false),
        CreateFleetMemberAcceptanceRow("远航者", "Citizen-2802", "成员", "Online", "InGame", "Unknown", "Unknown", null, false),
        CreateFleetMemberAcceptanceRow("星港守望", "Citizen-2803", "成员", "Online", "InGame", "Unknown", "Unknown", "pub_euw1", true),
        CreateFleetMemberAcceptanceRow("长夜灯塔", "Citizen-2804", "成员", "Online", "InGame", "Unknown", "Unknown", null, null)
    ];

    private static PlayerRow[] CreateFleetMemberOtherCommanderScenario() =>
    [
        CreateFleetMemberAcceptanceRow("多米诺", "domino_CN", "组织副负责人", "Online", "InGame", "圣盾 伊德里斯-P", "地点：新巴贝奇", "pub_use1", true, false, FleetRoleColorPalette.Blue),
        CreateFleetMemberAcceptanceRow("曙光", "Citizen-2800", "组织负责人", "Online", "AppOnline", "Unknown", "Unknown", null, false, true, FleetCommanderDefaultRoleColor),
        CreateFleetMemberAcceptanceRow("北辰", "Citizen-2801", "成员", "Offline", "Offline", "Unknown", "Unknown", null, false)
    ];

    private static PlayerRow CreateFleetMemberAcceptanceRow(
        string callsign,
        string gameId,
        string role,
        string onlineStatus,
        string liveStatus,
        string ship,
        string location,
        string? serverShard,
        bool? hasServerSession,
        bool isFleetCommander = false,
        string? roleColorHex = null) =>
        new(
            Name: gameId,
            Status: onlineStatus,
            Ship: ship,
            ShipInfo: "",
            Location: location,
            Callsign: callsign,
            Initials: callsign[..1],
            Role: role,
            ShowMemberActions: false,
            ServerShard: serverShard,
            LiveStatus: liveStatus,
            AccountId: $"debug-fleet-member-{gameId}",
            SharedOnlineStatus: onlineStatus,
            SharedLiveStatus: liveStatus,
            SharedShip: ship,
            SharedLocation: location,
            SharedHasServerSession: hasServerSession,
            IsFleetCommander: isFleetCommander,
            RoleColorBrush: StatusPalette.TryBrushFromHex(roleColorHex));

    private void SetFleetMemberAcceptanceButtonLabel(string? scenarioLabel)
    {
        if (_fleetMemberAcceptanceScenarioButton is null)
        {
            return;
        }

        _fleetMemberAcceptanceScenarioButton.Content = string.IsNullOrWhiteSpace(scenarioLabel)
            ? "验收场景"
            : $"场景 · {scenarioLabel}";
    }

    private static string GetFleetMemberAcceptanceScenarioLabel(string scenario) => scenario switch
    {
        "other-commander" => "他人指挥官",
        "all-states" => "全部状态",
        "loading" => "正在同步",
        "empty" => "空列表",
        "error" => "读取失败",
        "timeout" => "同步超时",
        "no-permission" => "无权限",
        "cached-offline" => "离线缓存",
        "reduced-motion" => "减少动态",
        _ => "验收"
    };

    private void ApplyFleetStateAcceptanceScenario(string scenario)
    {
        var descriptor = BridgeStateAcceptanceCatalog.Resolve(scenario);
        FleetServerDataContent.Visibility = Visibility.Collapsed;
        FleetStartupOfflineState.Visibility = Visibility.Collapsed;
        FleetStartupBlockingState.State = descriptor.State;
        FleetStartupBlockingState.TitleOverride = descriptor.Title;
        FleetStartupBlockingState.DescriptionOverride = descriptor.Description;
        FleetStartupBlockingState.ActionTextOverride = descriptor.ActionText;
        FleetStartupBlockingState.Visibility = Visibility.Visible;
        SetFleetStateAcceptanceMotion(descriptor.MotionEnabledOverride);
        SetFleetMemberAcceptanceButtonLabel(GetFleetMemberAcceptanceScenarioLabel(scenario));
    }

    private void ResetFleetStateAcceptanceScenario()
    {
        SetFleetStateAcceptanceMotion(null);
        FleetStartupBlockingState.Visibility = Visibility.Collapsed;
        FleetStartupBlockingState.TitleOverride = null;
        FleetStartupBlockingState.DescriptionOverride = null;
        FleetStartupBlockingState.ActionTextOverride = null;
    }

    private void SetFleetStateAcceptanceMotion(bool? motionEnabled)
    {
        FleetStartupBlockingState.ApplyTemplate();
        if (FleetStartupBlockingState.Template.FindName("PART_LoadingSpinner", FleetStartupBlockingState) is BridgeLoadingIndicator indicator)
        {
            indicator.SetAcceptanceMotionEnabledOverride(motionEnabled);
        }
    }
#endif
}
