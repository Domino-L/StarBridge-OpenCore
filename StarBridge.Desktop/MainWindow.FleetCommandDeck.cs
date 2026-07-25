using Microsoft.Win32;
using StarBridge.Core.Events;
using StarBridge.Core.FleetChat;
using StarBridge.Core.State;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
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
using ControlsImage = System.Windows.Controls.Image;
using ControlsOrientation = System.Windows.Controls.Orientation;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void ToggleFleetRailButton_Click(object sender, RoutedEventArgs e)
    {
        _isFleetRailCollapsed = !_isFleetRailCollapsed;
        RefreshFleetRailHeaders();
    }

    private void FleetRailButton_Click(object sender, RoutedEventArgs e)
    {
        if (FleetSubTabs is null)
        {
            return;
        }

        var previousSection = FleetSubTabs.SelectedItem;
        if (sender == AllPlayersRailButton)
        {
            FleetSubTabs.SelectedItem = AllPlayersTab;
        }
        else if (sender == SquadsRailButton)
        {
            FleetSubTabs.SelectedItem = SquadsTab;
        }
        else if (sender == FleetChatRailButton)
        {
            FleetSubTabs.SelectedItem = FleetChatTab;
        }
        else if (sender == FleetEventsRailButton)
        {
            FleetSubTabs.SelectedItem = FleetEventsTab;
        }
        else if (sender == FleetCommandDeckRailButton)
        {
            FleetSubTabs.SelectedItem = FleetCommandDeckTab;
        }
        else if (sender == FleetShipDatabaseRailButton)
        {
            FleetSubTabs.SelectedItem = FleetShipDatabaseTab;
        }
        else if (sender == ManageFleetRailButton)
        {
            if (!CanCurrentUserOpenFleetManagement())
            {
                FleetSubTabs.SelectedItem = AllPlayersTab;
                RefreshFleetRailHeaders();
                RefreshFleetMainContentView();
                return;
            }

            FleetSubTabs.SelectedItem = ManageFleetTab;
        }

        RefreshFleetRailHeaders();
        RefreshFleetMainContentView();
        if (!ReferenceEquals(previousSection, FleetSubTabs.SelectedItem))
        {
            QueueFleetSectionReveal();
        }
    }

    private void FleetSubTabs_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (sender == FleetSubTabs)
        {
            RefreshFleetRailHeaders();
            RefreshFleetMainContentView();
        }
    }

    private void RefreshFleetMainContentView()
    {
        if (FleetMembersDeckPanel is null ||
            FleetSquadsDeckPanel is null ||
            FleetActionPlanCard is null ||
            FleetDeckContentPanel is null ||
            FleetSubTabs is null)
        {
            return;
        }

        var showMembers = FleetSubTabs.SelectedItem == AllPlayersTab;
        var showSquads = FleetSubTabs.SelectedItem == SquadsTab;
        var showChat = FleetSubTabs.SelectedItem == FleetChatTab;
        var showEvents = FleetSubTabs.SelectedItem == FleetEventsTab;
        var showCommandDeck = FleetSubTabs.SelectedItem == FleetCommandDeckTab;
        var showManage = FleetSubTabs.SelectedItem == ManageFleetTab;
        var showExpandedCore = showChat || showEvents || showCommandDeck || showManage;
        var showDirectoryPanel = showMembers || showSquads;
        var showSubTabContent = !showDirectoryPanel;
        FleetMembersDeckPanel.Visibility = showMembers ? Visibility.Visible : Visibility.Collapsed;
        FleetSquadsDeckPanel.Visibility = showSquads ? Visibility.Visible : Visibility.Collapsed;
        Grid.SetColumnSpan(FleetSquadsDeckPanel, showSquads ? 2 : 1);
        FleetSquadsDeckPanel.Margin = showSquads ? new Thickness(0) : new Thickness(0, 0, 10, 0);
        FleetActionPlanCard.Visibility = showDirectoryPanel || showSubTabContent ? Visibility.Collapsed : Visibility.Visible;
        FleetDeckContentPanel.Visibility = showDirectoryPanel ? Visibility.Collapsed : Visibility.Visible;
        FleetSubTabs.Visibility = showSubTabContent ? Visibility.Visible : Visibility.Collapsed;
        FleetDeckContentPanel.Margin = showSubTabContent
            ? showExpandedCore ? new Thickness(0, 0, 0, 0) : new Thickness(0, 0, 10, 0)
            : new Thickness(0, 10, 10, 0);
        Grid.SetRow(FleetDeckContentPanel, showSubTabContent ? 0 : 1);
        Grid.SetRowSpan(FleetDeckContentPanel, showSubTabContent ? 2 : 1);
        Grid.SetColumnSpan(FleetDeckContentPanel, showExpandedCore ? 2 : 1);
        if (FleetRightSidebarPanel is not null)
        {
            FleetRightSidebarPanel.Visibility = showExpandedCore || showSquads
                ? Visibility.Collapsed
                : Visibility.Visible;
        }

        FleetDeckOverviewHeader.Visibility = showSubTabContent ? Visibility.Collapsed : Visibility.Visible;
        FleetDeckOverviewList.Visibility = showSubTabContent ? Visibility.Collapsed : Visibility.Visible;
        FleetDeckOverviewHeaderRow.Height = showSubTabContent ? new GridLength(0) : GridLength.Auto;
        FleetDeckOverviewListRow.Height = showSubTabContent ? new GridLength(0) : new GridLength(1, GridUnitType.Star);
        FleetSubTabsHostRow.Height = showSubTabContent ? new GridLength(1, GridUnitType.Star) : new GridLength(0);
        UpdateMembersSidebarModeToggle();
        if (showMembers)
        {
            RefreshMemberActionVisibilityForPermissions();
        }

        if (showSquads)
        {
            Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(RefreshSquadPreviewLimitFromLayout));
        }

        if (showEvents)
        {
            RefreshFleetEventCommandCenter();
        }

        if (showChat)
        {
            _ = OpenFleetChatAsync();
        }

        if (showCommandDeck)
        {
            RefreshFleetCommandDeck();
        }

        if (!showExpandedCore)
        {
            RefreshFleetRightContextSidebar();
        }
    }

    private void FleetCommandOpenEventsButton_Click(object sender, RoutedEventArgs e)
    {
        if (FleetSubTabs is null)
        {
            return;
        }

        FleetSubTabs.SelectedItem = FleetEventsTab;
        RefreshFleetRailHeaders();
        RefreshFleetMainContentView();
    }

    private void FleetCommandOpenShipsButton_Click(object sender, RoutedEventArgs e)
    {
        if (FleetSubTabs is null)
        {
            return;
        }

        FleetSubTabs.SelectedItem = FleetShipDatabaseTab;
        RefreshFleetRailHeaders();
        RefreshFleetMainContentView();
    }

    private void RefreshFleetCommandDeck()
    {
        if (FleetCommandStageTitleText is null ||
            FleetCommandDispatchItems is null ||
            FleetCommandMemberResponseItems is null ||
            FleetCommandOpenPlanItems is null ||
            FleetCommandSquadStateItems is null ||
            FleetCommandAdviceItems is null ||
            FleetCommandRecentEventItems is null ||
            FleetCommandBannerTagsPanel is null)
        {
            return;
        }

        FleetCommandDispatchItems.Children.Clear();
        FleetCommandMemberResponseItems.Children.Clear();
        FleetCommandOpenPlanItems.Children.Clear();
        FleetCommandSquadStateItems.Children.Clear();
        FleetCommandAdviceItems.Children.Clear();
        FleetCommandRecentEventItems.Children.Clear();
        FleetCommandBannerTagsPanel.Children.Clear();

        var hasTask = !string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle);
        var totalMembers = _players.Count;
        var onlineMembers = _players.Count(player => IsOnlineStatus(player.SharedOnlineStatusValue));
        var schedulableShips = BuildSchedulableFleetShips();
        var onlineShips = schedulableShips.Where(IsFleetShipOwnerOnline).ToArray();
        var openPlans = CountOpenActionPlans();
        var responseStats = GetCurrentTaskResponseStats();
        var confirmedCount = responseStats.ConfirmedCount;
        var readyCount = responseStats.ReadyCount;
        var unableCount = responseStats.UnableCount;
        var respondedCount = responseStats.RespondedCount;
        var pendingCount = hasTask ? Math.Max(0, onlineMembers - respondedCount) : 0;
        var taskStage = GetFleetEventTaskStageText(hasTask, confirmedCount, readyCount, unableCount);
        var latestEvent = _allFleetEventLogs
            .OrderByDescending(row => row.Timestamp)
            .FirstOrDefault();
        var latestEventText = latestEvent is null
            ? "暂无"
            : $"{latestEvent.Title} · {latestEvent.Timestamp.ToLocalTime():MM-dd HH:mm}";
        var canManageTasks = CanCurrentUserPublishTasks();
        var canManagePlans = CanCurrentUserPublishPlans();

        if (FleetCommandPublishTaskButton is not null)
        {
            FleetCommandPublishTaskButton.Visibility = canManageTasks ? Visibility.Visible : Visibility.Collapsed;
            FleetCommandPublishTaskButton.IsEnabled = canManageTasks;
        }

        if (FleetCommandCreatePlanButton is not null)
        {
            FleetCommandCreatePlanButton.Visibility = canManagePlans ? Visibility.Visible : Visibility.Collapsed;
            FleetCommandCreatePlanButton.IsEnabled = canManagePlans && openPlans < 3;
        }

        if (FleetCommandRenotifyButton is not null)
        {
            var canRemind = hasTask
                ? canManageTasks
                : canManagePlans && openPlans > 0;
            FleetCommandRenotifyButton.Content = hasTask ? "提醒成员" : "提醒接取";
            FleetCommandRenotifyButton.Visibility = (canManageTasks || canManagePlans) ? Visibility.Visible : Visibility.Collapsed;
            FleetCommandRenotifyButton.IsEnabled = canRemind;
        }

        if (FleetCommandCompleteTaskButton is not null)
        {
            FleetCommandCompleteTaskButton.Visibility = Visibility.Collapsed;
            FleetCommandCompleteTaskButton.IsEnabled = canManageTasks && hasTask;
        }

        if (FleetCommandCancelTaskButton is not null)
        {
            FleetCommandCancelTaskButton.Visibility = Visibility.Collapsed;
            FleetCommandCancelTaskButton.IsEnabled = canManageTasks && hasTask;
        }

        if (FleetCommandCurrentTaskDetailButton is not null)
        {
            FleetCommandCurrentTaskDetailButton.IsEnabled = hasTask;
            FleetCommandCurrentTaskDetailButton.Content = hasTask ? "查看详情" : "等待行动";
            FleetCommandCurrentTaskDetailButton.Visibility = hasTask ? Visibility.Visible : Visibility.Collapsed;
        }

        if (FleetCommandMemberResponsePanel is not null)
        {
            FleetCommandMemberResponsePanel.Visibility = hasTask ? Visibility.Visible : Visibility.Collapsed;
        }

        FleetCommandStageTitleText.Text = "舰队行动指挥";
        FleetCommandStageDetailText.Text = hasTask
            ? "当前行动 · 成员响应 · 结束判断"
            : "态势总览 · 调度判断 · 行动建议";
        FleetCommandOnlineMembersText.Text = $"{onlineMembers.ToString(CultureInfo.InvariantCulture)} / {totalMembers.ToString(CultureInfo.InvariantCulture)}";
        FleetCommandSchedulableShipsText.Text = $"{onlineShips.Length.ToString(CultureInfo.InvariantCulture)} / {schedulableShips.Length.ToString(CultureInfo.InvariantCulture)}";
        FleetCommandOpenPlansText.Text = openPlans.ToString(CultureInfo.InvariantCulture);
        var commandMood = hasTask
            ? $"行动进行中 · {taskStage}"
            : openPlans > 0
                ? $"舰队待命 · 有 {openPlans.ToString(CultureInfo.InvariantCulture)} 个开放预约"
                : "舰队待命";
        FleetCommandResponseSummaryText.Text = commandMood;
        if (FleetCommandResponseReadyText is not null)
        {
            FleetCommandResponseReadyText.Text = hasTask
                ? $"{readyCount.ToString(CultureInfo.InvariantCulture)} / {Math.Max(1, onlineMembers).ToString(CultureInfo.InvariantCulture)}"
                : "待命";
        }

        if (FleetCommandBannerConclusionText is not null)
        {
            FleetCommandBannerConclusionText.Text = hasTask
                ? $"当前行动处于“{taskStage}”，已有 {respondedCount.ToString(CultureInfo.InvariantCulture)} 名成员回应。"
                : openPlans > 0
                    ? $"当前没有即时行动，但已有 {openPlans.ToString(CultureInfo.InvariantCulture)} 个开放预约。"
                    : "当前没有即时行动，也没有开放预约。";
        }

        if (FleetCommandBannerSuggestionText is not null)
        {
            FleetCommandBannerSuggestionText.Text = hasTask
                ? readyCount < confirmedCount
                    ? "优先看谁还没就位，必要时再提醒一次。"
                    : "成员已经准备好，可以继续执行或结束任务。"
                : onlineMembers > 0
                    ? openPlans > 0
                        ? "建议提醒成员预约；如果人已经够，也可以发布即时行动。"
                        : "有人在线，可以发布即时行动；如果要约时间，就创建预约。"
                    : "暂时没人在线，先创建预约，等成员上线再推进。";
        }

        AddFleetCommandBannerTag(hasTask ? "行动进行中" : "暂无当前行动", hasTask ? "#29AFFF" : "#91A5B5");
        if (openPlans > 0)
        {
            AddFleetCommandBannerTag("开放预约", "#29AFFF");
        }
        if (onlineShips.Length > 0)
        {
            AddFleetCommandBannerTag("有在线舰船", "#42CF7C");
        }
        if (hasTask && pendingCount > 0)
        {
            AddFleetCommandBannerTag("需提醒", "#D9A23B");
        }

        UpdateFleetCommandObjectPriority(hasTask, openPlans);

        FleetCommandCurrentTaskTitleText.Text = hasTask ? _fleetCurrentTaskTitle : "暂无当前行动";
        FleetCommandCurrentTaskDetailText.Text = hasTask
            ? BuildCurrentTaskNotificationDetail()
            : "暂无当前行动，成员无需响应；有即时行动时这里会切换为执行监控。";
        FleetCommandCurrentTaskMetaText.Text = hasTask ? taskStage : "待命";
            FleetCommandCurrentTaskNextText.Text = hasTask
            ? confirmedCount == 0
                ? "提醒成员确认"
                : readyCount < confirmedCount
                    ? "等待成员就位"
                    : "完成或更新任务"
            : onlineMembers > 0 ? "发布行动或提醒预约" : "等待成员上线";
        FleetCommandCurrentTaskSourceText.Text = hasTask ? "立即开始" : "无";
        FleetCommandCurrentTaskRecentText.Text = latestEventText;
        FleetCommandCurrentTaskStateText.Text = hasTask ? taskStage : "待命";

        if (hasTask)
        {
            AddRightSidebarInfoRow(FleetCommandMemberResponseItems, "确认收到", $"{confirmedCount.ToString(CultureInfo.InvariantCulture)} 人", "已确认任务信息", "#29AFFF");
            AddRightSidebarInfoRow(FleetCommandMemberResponseItems, "已就位", $"{readyCount.ToString(CultureInfo.InvariantCulture)} 人", "可进入下一步行动", "#42CF7C");
            AddRightSidebarInfoRow(FleetCommandMemberResponseItems, "无法参与", $"{unableCount.ToString(CultureInfo.InvariantCulture)} 人", "需要替补或调整范围", "#F15B65");
            AddRightSidebarInfoRow(FleetCommandMemberResponseItems, "未响应", $"{pendingCount.ToString(CultureInfo.InvariantCulture)} 人", "可再次提醒或缩小范围", "#D9A23B");
        }

        AddFleetCommandOpenPlanRows(openPlans);
        AddFleetCommandResourceRows(onlineMembers, totalMembers, onlineShips, schedulableShips);

        if (_squads.Count == 0)
        {
            AddFleetCommandCompactRow(FleetCommandSquadStateItems, "小队", "暂无小队", "创建小队后会显示准备情况。", "#91A5B5");
        }
        else
        {
            var squad = _squads
                .OrderByDescending(squad => squad.OnlineCount)
                .ThenBy(squad => squad.Name, StringComparer.CurrentCultureIgnoreCase)
                .First();
            var squadReady = squad.OnlineCount > 0;
            AddFleetCommandCompactRow(
                FleetCommandSquadStateItems,
                "小队",
                squad.Name,
                $"{squad.OnlineCount.ToString(CultureInfo.InvariantCulture)} / {squad.MemberCount.ToString(CultureInfo.InvariantCulture)} 在线",
                squadReady ? "#42CF7C" : "#91A5B5");
            AddFleetCommandCompactRow(
                FleetCommandSquadStateItems,
                "行动条件",
                squadReady ? "可以行动" : "等待成员",
                string.IsNullOrWhiteSpace(GetSquadMissionText(squad)) ? "暂无小队任务" : GetSquadMissionText(squad),
                squadReady ? "#42CF7C" : "#D9A23B");
        }

        AddFleetCommandAdviceRows(hasTask, onlineMembers, totalMembers, onlineShips.Length, schedulableShips.Length, openPlans, readyCount, confirmedCount);
        AddFleetCommandRecentEventRows();
    }

    private void AddFleetCommandOpenPlanRows(int openPlans)
    {
        if (openPlans == 0)
        {
            AddFleetCommandCompactRow(
                FleetCommandOpenPlanItems,
                "暂无开放行动",
                "等待创建",
                "创建预约后，成员可在事件栏预约。",
                "#91A5B5");
            AddFleetCommandCompactRow(
                FleetCommandOpenPlanItems,
                "行动入口",
                "创建预约",
                "适合提前约定时间、人数与集结安排。",
                "#29AFFF");
            return;
        }

        var plans = _fleetActionPlans
            .Where(plan => plan.IsOpen)
            .OrderBy(plan => plan.StartTime)
            .Take(2)
            .ToArray();
        var primaryPlan = plans.FirstOrDefault();
        if (primaryPlan is not null)
        {
            AddFleetCommandPlanSummary(primaryPlan, openPlans);
        }

        foreach (var plan in plans.Skip(1))
        {
            AddFleetCommandCompactRow(
                FleetCommandOpenPlanItems,
                "后续行动",
                string.IsNullOrWhiteSpace(plan.Title) ? "未命名行动" : plan.Title,
                $"{plan.Participants.Count.ToString(CultureInfo.InvariantCulture)} 人接取 · {plan.StartTime:MM-dd HH:mm}",
                plan.IsReached ? "#D9A23B" : "#29AFFF");
        }

        if (openPlans > plans.Length)
        {
            AddFleetCommandCompactRow(
                FleetCommandOpenPlanItems,
                "更多行动",
                $"还有 {(openPlans - plans.Length).ToString(CultureInfo.InvariantCulture)} 个",
                "可到事件栏查看全部预约行动。",
                "#91A5B5");
        }
    }

    private void AddFleetCommandPlanSummary(FleetActionPlanRow plan, int openPlans)
    {
        var title = string.IsNullOrWhiteSpace(plan.Title) ? "未命名行动" : plan.Title;
        var participantLimit = "不限";
        var participants = $"{plan.Participants.Count.ToString(CultureInfo.InvariantCulture)} / {participantLimit}";
        var border = new Border
        {
            Background = CreateSolidBrush("#0A1823"),
            BorderBrush = CreateSolidBrush("#24506A"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Padding = new Thickness(10, 8, 10, 8),
            Margin = new Thickness(0, 0, 0, 8)
        };

        var stack = new StackPanel();
        var titleRow = new DockPanel();
        var statusBadge = new Border
        {
            Background = CreateSolidBrush(plan.IsReached ? "#2A2415" : "#102B3D"),
            BorderBrush = CreateSolidBrush(plan.IsReached ? "#725B29" : "#2E8FBA"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Padding = new Thickness(7, 2, 7, 2),
            HorizontalAlignment = HorizontalAlignment.Right
        };
        statusBadge.Child = new TextBlock
        {
            Text = FormatActionPlanStatusForCommandDeck(plan),
            Foreground = CreateSolidBrush(plan.IsReached ? "#E8C765" : "#DFF5FF"),
            FontSize = 10.5,
            FontWeight = FontWeights.SemiBold
        };
        DockPanel.SetDock(statusBadge, Dock.Right);
        titleRow.Children.Add(statusBadge);
        titleRow.Children.Add(new TextBlock
        {
            Text = title,
            Foreground = CreateSolidBrush("#E6F1F8"),
            FontSize = 16,
            FontWeight = FontWeights.SemiBold,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Margin = new Thickness(0, 0, 10, 0)
        });
        stack.Children.Add(titleRow);
        stack.Children.Add(new TextBlock
        {
            Text = "成员可在事件栏接取预约，指挥官可查看状态或提醒成员。",
            Foreground = CreateSolidBrush("#91A5B5"),
            FontSize = 11.5,
            Margin = new Thickness(0, 6, 0, 0),
            TextTrimming = TextTrimming.CharacterEllipsis
        });

        var fields = new System.Windows.Controls.Primitives.UniformGrid
        {
            Columns = 5,
            Margin = new Thickness(0, 9, 0, 0)
        };
        AddFleetCommandMiniField(fields, "开始时间", plan.StartTime.ToString("MM-dd HH:mm"), "#D7E6F0");
        AddFleetCommandMiniField(fields, "接取情况", participants, "#29AFFF");
        AddFleetCommandMiniField(fields, "指挥官", FormatCommanderName(_callsign, _localPlayer, _fleetChiefCommander), "#D7E6F0");
        AddFleetCommandMiniField(fields, "参与范围", "全舰队", "#D7E6F0");
        AddFleetCommandMiniField(fields, "当前状态", FormatActionPlanStatusForCommandDeck(plan), plan.IsReached ? "#D9A23B" : "#42CF7C");
        stack.Children.Add(fields);
        stack.Children.Add(new TextBlock
        {
            Text = "下一步 / 提醒成员接取",
            Foreground = CreateSolidBrush("#D9A23B"),
            FontSize = 11.5,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 9, 0, 0),
            TextTrimming = TextTrimming.CharacterEllipsis
        });

        var actions = new StackPanel
        {
            Orientation = System.Windows.Controls.Orientation.Horizontal,
            Margin = new Thickness(0, 9, 0, 0)
        };
        var viewButton = new System.Windows.Controls.Button
        {
            Content = "查看详情",
            Style = (Style)FindResource("SecondaryButton"),
            Height = 28,
            MinWidth = 76,
            Margin = new Thickness(0, 0, 8, 0)
        };
        viewButton.Click += (_, e) =>
        {
            e.Handled = true;
            OpenCommandDeckActionPlanDetail(plan);
        };
        actions.Children.Add(viewButton);
        var remindButton = new System.Windows.Controls.Button
        {
            Content = "提醒接取",
            Style = (Style)FindResource("SecondaryButton"),
            Height = 28,
            MinWidth = 76,
            IsEnabled = CanCurrentUserPublishPlans() && plan.IsOpen
        };
        remindButton.Click += (sender, e) =>
        {
            e.Handled = true;
            FleetCommandRemindButton_Click(sender, e);
        };
        actions.Children.Add(remindButton);
        stack.Children.Add(actions);

        border.Child = stack;
        FleetCommandOpenPlanItems.Children.Add(border);
    }

    private void AddFleetCommandCompactRow(System.Windows.Controls.Panel panel, string label, string value, string detail, string accentHex)
    {
        var border = new Border
        {
            Background = CreateSolidBrush("#0D1D29"),
            BorderBrush = CreateSolidBrush("#173447"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Padding = new Thickness(8, 5, 8, 5),
            Margin = new Thickness(0, 0, 0, 5)
        };

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(10) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var marker = new System.Windows.Shapes.Ellipse
        {
            Width = 6,
            Height = 6,
            Fill = CreateSolidBrush(accentHex),
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(marker, 0);
        grid.Children.Add(marker);

        var stack = new StackPanel { Margin = new Thickness(7, 0, 0, 0) };
        Grid.SetColumn(stack, 1);
        var titleRow = new DockPanel();
        var labelText = new TextBlock
        {
            Text = label,
            Foreground = CreateSolidBrush("#91A5B5"),
            FontSize = 10.5,
            Margin = new Thickness(0, 0, 8, 0),
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        DockPanel.SetDock(labelText, Dock.Left);
        titleRow.Children.Add(labelText);
        titleRow.Children.Add(new TextBlock
        {
            Text = value,
            Foreground = CreateSolidBrush("#E6F1F8"),
            FontSize = 12,
            FontWeight = FontWeights.SemiBold,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        stack.Children.Add(titleRow);
        if (!string.IsNullOrWhiteSpace(detail))
        {
            stack.Children.Add(new TextBlock
            {
                Text = detail,
                Foreground = CreateSolidBrush("#6F8796"),
                FontSize = 10.5,
                Margin = new Thickness(0, 2, 0, 0),
                TextTrimming = TextTrimming.CharacterEllipsis
            });
        }

        grid.Children.Add(stack);
        border.Child = grid;
        panel.Children.Add(border);
    }

    private void AddFleetCommandMiniField(System.Windows.Controls.Panel panel, string label, string value, string accentHex)
    {
        var stack = new StackPanel { Margin = new Thickness(0, 0, 8, 0) };
        stack.Children.Add(new TextBlock
        {
            Text = label,
            Foreground = new SolidColorBrush(Color.FromRgb(111, 135, 150)),
            FontSize = 10.5,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        stack.Children.Add(new TextBlock
        {
            Text = value,
            Foreground = CreateSolidBrush(accentHex),
            FontSize = 12,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 3, 0, 0),
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        panel.Children.Add(stack);
    }

    private void FleetCommandViewPlansButton_Click(object sender, RoutedEventArgs e)
    {
        if (FleetSubTabs is null)
        {
            return;
        }

        FleetSubTabs.SelectedItem = FleetEventsTab;
        RefreshFleetRailHeaders();
        RefreshFleetMainContentView();
    }

    private void FleetCommandCurrentTaskDetailButton_Click(object sender, RoutedEventArgs e)
    {
        OpenCurrentTaskDetail();
    }

    private void FleetCommandCurrentActionCard_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (IsCommandDeckCardClickFromButton(e.OriginalSource as DependencyObject))
        {
            return;
        }

        OpenCurrentTaskDetail();
        e.Handled = true;
    }

    private void FleetCommandOpenPlanCard_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (IsCommandDeckCardClickFromButton(e.OriginalSource as DependencyObject))
        {
            return;
        }

        OpenCommandDeckActionPlanDetail();
        e.Handled = true;
    }

    private static bool IsCommandDeckCardClickFromButton(DependencyObject? source)
    {
        while (source is not null)
        {
            if (source is System.Windows.Controls.Primitives.ButtonBase)
            {
                return true;
            }

            source = VisualTreeHelper.GetParent(source);
        }

        return false;
    }

    private void UpdateFleetCommandObjectPriority(bool hasTask, int openPlans)
    {
        if (FleetCommandCurrentActionCard is null ||
            FleetCommandOpenPlanCard is null ||
            FleetCommandMainActionHost is null ||
            FleetCommandAuxiliaryActionHost is null)
        {
            return;
        }

        var currentIsPrimary = hasTask || openPlans == 0;
        var primaryCard = currentIsPrimary
            ? FleetCommandCurrentActionCard
            : FleetCommandOpenPlanCard;
        var secondaryCard = currentIsPrimary
            ? FleetCommandOpenPlanCard
            : FleetCommandCurrentActionCard;

        MoveCommandDeckCard(primaryCard, FleetCommandMainActionHost);
        MoveCommandDeckCard(secondaryCard, FleetCommandAuxiliaryActionHost);

        ApplyCommandDeckCardEmphasis(FleetCommandCurrentActionCard, currentIsPrimary && hasTask);
        ApplyCommandDeckCardEmphasis(FleetCommandOpenPlanCard, !currentIsPrimary && openPlans > 0);

        FleetCommandCurrentActionCard.MinHeight = hasTask
            ? 154
            : 132;
        FleetCommandOpenPlanCard.MinHeight = !currentIsPrimary && openPlans > 0
            ? 230
            : 150;

        if (FleetCommandOpenPlanCardTitleText is not null)
        {
            FleetCommandOpenPlanCardTitleText.Text = currentIsPrimary
                ? "开放预约"
                : "开放预约行动";
        }

        if (FleetCommandOpenPlanCardHintText is not null)
        {
            FleetCommandOpenPlanCardHintText.Text = currentIsPrimary
                ? "成员在事件栏预约，指挥台只看概览和入口。"
                : "成员可在事件栏接取该预约，点击卡片查看详情。";
        }
    }

    private static void MoveCommandDeckCard(Border card, System.Windows.Controls.Panel targetHost)
    {
        if (card.Parent is System.Windows.Controls.Panel parent && !ReferenceEquals(parent, targetHost))
        {
            parent.Children.Remove(card);
        }

        if (!targetHost.Children.Contains(card))
        {
            targetHost.Children.Insert(0, card);
        }

        card.Margin = new Thickness(0);
    }

    private void ApplyCommandDeckCardEmphasis(Border card, bool isPrimary)
    {
        card.BorderBrush = CreateSolidBrush(isPrimary ? "#2E8FBA" : "#173447");
        card.Background = CreateSolidBrush(isPrimary ? "#0A1F2C" : "#07131D");
    }

    private void AddFleetCommandResourceRows(
        int onlineMembers,
        int totalMembers,
        IReadOnlyCollection<FleetShipInventoryRow> onlineShips,
        IReadOnlyCollection<FleetShipInventoryRow> schedulableShips)
    {
        var wrap = new WrapPanel
        {
            Orientation = System.Windows.Controls.Orientation.Horizontal
        };
        FleetCommandDispatchItems.Children.Add(wrap);

        var resourceConclusion = onlineMembers == 0
            ? "等待成员"
            : onlineShips.Count == 0 ? "缺少在线舰船" : "可以行动";
        var conclusionAccent = resourceConclusion == "可以行动"
            ? "#42CF7C"
            : "#D9A23B";

        AddFleetCommandMetricChip(
            wrap,
            "可联络成员",
            $"{onlineMembers.ToString(CultureInfo.InvariantCulture)} / {totalMembers.ToString(CultureInfo.InvariantCulture)}",
            onlineMembers > 0 ? "#42CF7C" : "#91A5B5");
        var commandServer = GetFleetCommandMajorityServer(onlineMembers);
        AddFleetCommandMetricChip(wrap, "推荐服务器", commandServer.Text, commandServer.AccentHex);
        AddFleetCommandMetricChip(
            wrap,
            "在线舰船",
            $"{onlineShips.Count.ToString(CultureInfo.InvariantCulture)} / {schedulableShips.Count.ToString(CultureInfo.InvariantCulture)}",
            onlineShips.Count > 0 ? "#42CF7C" : "#D9A23B");
        AddFleetCommandMetricChip(wrap, "行动判断", resourceConclusion, conclusionAccent);
        foreach (var visual in FleetShipRoleVisuals)
        {
            AddFleetCommandResourceCategoryChip(
                wrap,
                visual.DisplayName,
                visual.Category,
                onlineShips,
                schedulableShips,
                visual.ColorHex);
        }
    }

    private (string Text, string AccentHex) GetFleetCommandMajorityServer(int onlineMembers)
    {
        if (onlineMembers <= 0)
        {
            return ("无人在线", "#91A5B5");
        }

        var serverGroups = _players
            .Where(player => IsOnlineStatus(player.SharedOnlineStatusValue))
            .Select(TryGetFleetCommandServerRegion)
            .Where(region => !string.IsNullOrWhiteSpace(region))
            .GroupBy(region => region!, StringComparer.OrdinalIgnoreCase)
            .Select(group => new
            {
                Region = group.First(),
                Count = group.Count()
            })
            .OrderByDescending(group => group.Count)
            .ThenBy(group => group.Region, StringComparer.CurrentCulture)
            .ToArray();

        if (serverGroups.Length == 0)
        {
            return ("等待确认", "#91A5B5");
        }

        var primary = serverGroups[0];
        var accent = primary.Count >= onlineMembers ? "#42CF7C" : "#29AFFF";
        return ($"{primary.Region} · {primary.Count.ToString(CultureInfo.InvariantCulture)} 人", accent);
    }

    private string? TryGetFleetCommandServerRegion(PlayerRow player)
    {
        if (!IsOnlineStatus(player.SharedOnlineStatusValue))
        {
            return null;
        }

        if (player.IsSelf && IsGameServerRegionCurrent())
        {
            return NormalizeFleetCommandServerRegion(_gameServerRegion);
        }

        return TryExtractFleetCommandServerRegion(player.RawLocation) ??
               TryExtractFleetCommandServerRegion(player.Location);
    }

    private static string? TryExtractFleetCommandServerRegion(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        if (IsUnknownLocation(value))
        {
            return null;
        }

        var text = value.Trim();
        if (text.Equals("等待确认", StringComparison.OrdinalIgnoreCase) ||
            text.Equals("仅游戏中显示", StringComparison.OrdinalIgnoreCase) ||
            text.Equals("未连接", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var normalized = text.ToLowerInvariant();
        if (text.Contains("美服", StringComparison.OrdinalIgnoreCase) ||
            normalized.Contains("us east") ||
            normalized.Contains("us west") ||
            normalized.Contains("usa"))
        {
            return "美服";
        }

        if (text.Contains("欧服", StringComparison.OrdinalIgnoreCase) ||
            normalized.Contains("europe") ||
            normalized.Contains(" eu "))
        {
            return "欧服";
        }

        if (text.Contains("澳服", StringComparison.OrdinalIgnoreCase) ||
            normalized.Contains("australia") ||
            normalized.Contains("oceania"))
        {
            return "澳服";
        }

        if (text.Contains("亚服", StringComparison.OrdinalIgnoreCase) ||
            normalized.Contains("asia") ||
            normalized.Contains("singapore") ||
            normalized.Contains("hong kong") ||
            normalized.Contains("japan"))
        {
            return "亚服";
        }

        if (normalized.Contains("pub_") ||
            normalized.Contains("shard") ||
            normalized.Contains("server"))
        {
            return NormalizeFleetCommandServerRegion(MapGameServerRegion(normalized));
        }

        return null;
    }

    private static string? NormalizeFleetCommandServerRegion(string? region)
    {
        if (string.IsNullOrWhiteSpace(region) ||
            region.Equals("未知", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        return region.Trim();
    }

    private void AddFleetCommandResourceCategoryChip(
        System.Windows.Controls.Panel panel,
        string label,
        FleetShipRoleCategory category,
        IEnumerable<FleetShipInventoryRow> onlineShips,
        IEnumerable<FleetShipInventoryRow> schedulableShips,
        string accentHex)
    {
        var onlineCount = CountFleetShipsByRoleCategory(onlineShips, category);
        var totalCount = CountFleetShipsByRoleCategory(schedulableShips, category);
        AddFleetCommandMetricChip(
            panel,
            label,
            $"{onlineCount.ToString(CultureInfo.InvariantCulture)} / {totalCount.ToString(CultureInfo.InvariantCulture)}",
            onlineCount > 0 ? accentHex : "#91A5B5");
    }

    private void AddFleetCommandMetricChip(System.Windows.Controls.Panel panel, string label, string value, string accentHex)
    {
        var border = new Border
        {
            Background = CreateSolidBrush("#0D1D29"),
            BorderBrush = CreateSolidBrush("#173447"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Padding = new Thickness(7, 4, 7, 4),
            Margin = new Thickness(0, 0, 6, 6),
            MinWidth = 86
        };

        var stack = new StackPanel
        {
            Orientation = System.Windows.Controls.Orientation.Horizontal,
            VerticalAlignment = VerticalAlignment.Center
        };
        stack.Children.Add(new TextBlock
        {
            Text = label,
            Foreground = CreateSolidBrush("#91A5B5"),
            FontSize = 10.5,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        stack.Children.Add(new TextBlock
        {
            Text = value,
            Foreground = CreateSolidBrush(accentHex),
            FontSize = 12,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(6, 0, 0, 0),
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        border.Child = stack;
        panel.Children.Add(border);
    }

    private string FormatActionPlanStatusForCommandDeck(FleetActionPlanRow plan)
    {
        return plan.EffectiveStatus switch
        {
            "Reached" => "即将开始",
            "Completed" => "已完成",
            "Canceled" => "已取消",
            _ => "开放"
        };
    }

    private void AddFleetCommandBannerTag(string text, string accentHex)
    {
        if (FleetCommandBannerTagsPanel is null)
        {
            return;
        }

        var border = new Border
        {
            Background = CreateSolidBrush("#0D1D29"),
            BorderBrush = CreateSolidBrush(accentHex),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Padding = new Thickness(8, 3, 8, 3),
            Margin = new Thickness(0, 0, 6, 0)
        };
        border.Child = new TextBlock
        {
            Text = text,
            Foreground = CreateSolidBrush("#D7E6F0"),
            FontSize = 11,
            FontWeight = FontWeights.SemiBold,
            VerticalAlignment = VerticalAlignment.Center
        };
        FleetCommandBannerTagsPanel.Children.Add(border);
    }

    private void AddFleetCommandRecentEventRows()
    {
        var events = _allFleetEventLogs
            .Where(row => !IsPersonalPlanParticipationLog(row))
            .OrderByDescending(row => row.Timestamp)
            .Take(4)
            .ToArray();

        if (events.Length == 0)
        {
            AddFleetCommandCompactRow(
                FleetCommandRecentEventItems,
                "暂无事件记录",
                "等待行动",
                "任务发布、计划变化和成员反馈会显示在这里。",
                "#91A5B5");
            return;
        }

        foreach (var row in events)
        {
            AddFleetCommandCompactRow(
                FleetCommandRecentEventItems,
                row.Type,
                SanitizeFleetEventText(row.Title),
                $"{row.Timestamp.ToLocalTime():MM-dd HH:mm} · {SanitizeFleetEventText(row.Detail)}",
                GetFleetCommandEventAccent(row.Type, row.Title));
        }
    }

    private static string GetFleetCommandEventAccent(string type, string title)
    {
        var value = $"{type} {title}";
        if (value.Contains("取消", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("删除", StringComparison.OrdinalIgnoreCase))
        {
            return "#F15B65";
        }

        if (value.Contains("完成", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("就位", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("加入", StringComparison.OrdinalIgnoreCase))
        {
            return "#42CF7C";
        }

        if (value.Contains("计划", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("任务", StringComparison.OrdinalIgnoreCase))
        {
            return "#29AFFF";
        }

        return "#91A5B5";
    }

    private void AddFleetCommandAdviceRows(
        bool hasTask,
        int onlineMembers,
        int totalMembers,
        int onlineShips,
        int schedulableShips,
        int openPlans,
        int readyCount,
        int confirmedCount)
    {
        void AddAdvice(string title, string value, string detail, string accentHex)
        {
            if (FleetCommandAdviceItems.Children.Count >= 3)
            {
                return;
            }

            AddFleetCommandCompactRow(FleetCommandAdviceItems, title, value, detail, accentHex);
        }

        if (hasTask)
        {
            if (confirmedCount == 0)
            {
                AddAdvice("先收回应", "还没人确认", "提醒成员确认是否参与。", "#D9A23B");
            }
            else if (readyCount < confirmedCount)
            {
                AddAdvice("等就位", $"{readyCount.ToString(CultureInfo.InvariantCulture)} / {confirmedCount.ToString(CultureInfo.InvariantCulture)}", "优先跟进未就位成员。", "#D9A23B");
            }
            else
            {
                AddAdvice("可以推进", "成员已准备", "继续执行，或结束当前行动。", "#42CF7C");
            }
        }
        else if (onlineMembers > 0)
        {
            AddAdvice("现在可行动", $"{onlineMembers.ToString(CultureInfo.InvariantCulture)} 人在线", "可以创建行动或提醒预约。", "#29AFFF");
        }
        else
        {
            AddAdvice("先等成员", "暂无在线成员", "成员上线后再组织行动。", "#91A5B5");
        }

        if (schedulableShips == 0)
        {
            AddAdvice("缺少舰船", "暂无可飞数据", "让成员同步个人机库。", "#D9A23B");
        }
        else if (onlineShips == 0)
        {
            AddAdvice("等持有人", "无在线舰船", "等待舰船持有人上线。", "#D9A23B");
        }
        else
        {
            AddAdvice("舰船够用", $"{onlineShips.ToString(CultureInfo.InvariantCulture)} 艘在线", "需要细分舰种时再看舰船库。", "#42CF7C");
        }

        if (!hasTask && openPlans > 0)
        {
            AddAdvice("提醒预约", $"{openPlans.ToString(CultureInfo.InvariantCulture)} 个行动", "让成员去事件栏预约。", "#29AFFF");
        }
        else if (!hasTask)
        {
            AddAdvice("安排下一场", "暂无预约", "可以安排稍后行动。", "#91A5B5");
        }

        if (totalMembers == 0)
        {
            AddAdvice("先招成员", "暂无成员", "成员加入后才会有行动建议。", "#91A5B5");
        }
    }

    private void MembersSidebarMemberModeButton_Click(object sender, RoutedEventArgs e)
    {
        ShowMembersSidebarMode(MembersPanelMode.Member);
    }

    private void MembersSidebarAdminModeButton_Click(object sender, RoutedEventArgs e)
    {
        ShowMembersSidebarMode(MembersPanelMode.Admin);
    }

    private void ShowMembersSidebarMode(MembersPanelMode mode)
    {
        _membersPanelModeTouched = true;
        if (mode == MembersPanelMode.Admin && !CanUseMembersAdminView())
        {
            mode = MembersPanelMode.Member;
        }

        _membersPanelMode = mode;
        UpdateMembersSidebarModeToggle();
        RefreshFleetRightContextSidebar();
    }

    private bool CanUseMembersAdminView()
    {
        // Any current fleet-management capability grants access to the shared member administration view.
        return _hasFleet &&
               (IsCurrentUserFleetCommander() ||
                CanCurrentUserManageFleetInfo() ||
                CanCurrentUserRemoveMembers());
    }

    private bool CanShowMemberActionsForCurrentUser()
    {
        return CanUseMembersAdminView();
    }

    private void UpdateMembersSidebarModeToggle()
    {
        if (MembersSidebarModeTogglePanel is null)
        {
            return;
        }

        var canUseAdminView = CanUseMembersAdminView();
        if (canUseAdminView && !_membersPanelModeTouched)
        {
            _membersPanelMode = MembersPanelMode.Admin;
        }
        else if (!canUseAdminView)
        {
            _membersPanelMode = MembersPanelMode.Member;
        }

        var showToggle = FleetSubTabs?.SelectedItem == AllPlayersTab && canUseAdminView;
        MembersSidebarModeTogglePanel.Visibility = showToggle ? Visibility.Visible : Visibility.Collapsed;
        UiMotion.ApplyNavigationSelection(
            [MembersSidebarMemberModeButton, MembersSidebarAdminModeButton],
            _membersPanelMode == MembersPanelMode.Member
                ? MembersSidebarMemberModeButton
                : MembersSidebarAdminModeButton);
        MembersSidebarMemberModeButton.IsEnabled = _membersPanelMode != MembersPanelMode.Member;
        MembersSidebarAdminModeButton.IsEnabled = canUseAdminView && _membersPanelMode != MembersPanelMode.Admin;
    }

    private void RefreshMemberActionVisibilityForPermissions()
    {
        if (_players.Count == 0)
        {
            return;
        }

        var showActions = CanShowMemberActionsForCurrentUser();
        for (var index = 0; index < _players.Count; index++)
        {
            var player = _players[index];
            if (player.ShowMemberActions == showActions)
            {
                continue;
            }

            _players[index] = player with { ShowMemberActions = showActions };
        }
    }

    private void RefreshFleetRailHeaders()
    {
        if (AllPlayersTab is null ||
            SquadsTab is null ||
            FleetChatTab is null ||
            FleetEventsTab is null ||
            FleetCommandDeckTab is null ||
            FleetShipDatabaseTab is null ||
            ManageFleetTab is null)
        {
            return;
        }

        var zh = _language == "zh";
        ApplyOverlayLayerAndModuleStyleLanguage(zh);
        _isFleetRailCollapsed = false;
        FleetRailColumn.Width = new GridLength(118);
        if (_isFleetRailCollapsed)
        {
            AllPlayersTab.Header = zh ? "员" : "M";
            SquadsTab.Header = zh ? "队" : "T";
            FleetChatTab.Header = zh ? "讯" : "C";
            FleetEventsTab.Header = zh ? "事" : "E";
            FleetCommandDeckTab.Header = zh ? "令" : "C";
            FleetShipDatabaseTab.Header = zh ? "船" : "S";
            ManageFleetTab.Header = zh ? "管" : "G";
            AllPlayersRailButton.Content = "";
            SquadsRailButton.Content = "";
            FleetChatRailButton.Content = "";
            FleetEventsRailButton.Content = "";
            FleetCommandDeckRailButton.Content = "";
            FleetShipDatabaseRailButton.Content = "";
            ManageFleetRailButton.Content = "";
        }
        else
        {
            AllPlayersTab.Header = zh ? "成员" : "Members";
            SquadsTab.Header = zh ? "小队" : "Squads";
            FleetChatTab.Header = zh ? "通讯" : "Comms";
            FleetEventsTab.Header = zh ? "事件" : "Events";
            FleetCommandDeckTab.Header = zh ? "指挥台" : "Command";
            FleetShipDatabaseTab.Header = zh ? "舰船" : "Ships";
            ManageFleetTab.Header = zh ? "管理" : "Manage";
            AllPlayersRailButton.Content = zh ? "成员" : "Members";
            SquadsRailButton.Content = zh ? "小队" : "Squads";
            FleetChatRailButton.Content = zh ? "通讯" : "Comms";
            FleetEventsRailButton.Content = zh ? "事件" : "Events";
            FleetCommandDeckRailButton.Content = zh ? "指挥" : "Command";
            FleetShipDatabaseRailButton.Content = zh ? "舰船" : "Ships";
            ManageFleetRailButton.Content = zh ? "管理" : "Manage";
        }

        var activeRailButton = FleetSubTabs.SelectedItem switch
        {
            _ when FleetSubTabs.SelectedItem == AllPlayersTab => AllPlayersRailButton,
            _ when FleetSubTabs.SelectedItem == SquadsTab => SquadsRailButton,
            _ when FleetSubTabs.SelectedItem == FleetChatTab => FleetChatRailButton,
            _ when FleetSubTabs.SelectedItem == FleetEventsTab => FleetEventsRailButton,
            _ when FleetSubTabs.SelectedItem == FleetCommandDeckTab => FleetCommandDeckRailButton,
            _ when FleetSubTabs.SelectedItem == FleetShipDatabaseTab => FleetShipDatabaseRailButton,
            _ when FleetSubTabs.SelectedItem == ManageFleetTab => ManageFleetRailButton,
            _ => null
        };
        UiMotion.ApplyNavigationSelection(
            [
                AllPlayersRailButton,
                SquadsRailButton,
                FleetChatRailButton,
                FleetEventsRailButton,
                FleetCommandDeckRailButton,
                FleetShipDatabaseRailButton,
                ManageFleetRailButton
            ],
            activeRailButton);
        UpdateFleetChatRailUnreadLabel();

        if (ToggleFleetRailButton is not null)
        {
            ToggleFleetRailButton.Content = zh ? "退出舰队" : "Leave Fleet";
            ToggleFleetRailButton.ToolTip = zh ? "退出当前舰队" : "Leave current fleet";
        }
    }
}
