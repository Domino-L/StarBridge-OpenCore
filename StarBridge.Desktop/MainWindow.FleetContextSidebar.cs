using Microsoft.Win32;
using StarBridge.Core.Events;
using StarBridge.Core.FleetChat;
using StarBridge.Core.Presence;
using StarBridge.Core.State;
using StarBridge.Desktop.Theming;
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
using MediaFontFamily = System.Windows.Media.FontFamily;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void RefreshFleetInfoPanel()
    {
        if (FleetActionPlanTitleText is null)
        {
            return;
        }

        var activeInfoButton = _selectedFleetInfoPanel switch
        {
            FleetInfoPanelKind.Notice => FleetNoticeInfoTabButton,
            FleetInfoPanelKind.CurrentTask => FleetCurrentTaskInfoTabButton,
            _ => FleetActionPlanInfoTabButton
        };
        UiMotion.ApplyNavigationSelection(
            [FleetNoticeInfoTabButton, FleetCurrentTaskInfoTabButton, FleetActionPlanInfoTabButton],
            activeInfoButton);

        switch (_selectedFleetInfoPanel)
        {
            case FleetInfoPanelKind.Notice:
                RefreshNoticePanel();
                break;
            case FleetInfoPanelKind.CurrentTask:
                RefreshCurrentTaskPanel();
                break;
            default:
                RefreshActionPlanPanel();
                break;
        }

        ApplyFleetReplicaPlaceholderPanel();
        RefreshFleetNotificationCenter();
        RefreshFleetRightContextSidebar();
    }

    private void ApplyFleetReplicaPlaceholderPanel()
    {
        FleetActionPlanTitleText.Text = "深渊回响：L5 遗迹清剿行动";
        FleetActionPlanSummaryText.Text = "任务目标        清除 L5 遗迹内敌对势力，回收遗迹数据核心";
        FleetActionPlanTimeText.Text = "开始时间                                      2025-05-24 20:00";
        JoinFleetActionButton.Visibility = Visibility.Visible;
        JoinFleetActionButton.Content = "查看任务详情";
        JoinFleetActionButton.IsEnabled = true;
    }

    private void RefreshFleetNotificationCenter()
    {
        if (FleetNotificationCenterSummaryText is null)
        {
            return;
        }

        _fleetNotificationCenterItems.Clear();

        if (!_hasFleet)
        {
            FleetNotificationCenterSummaryText.Text = "加入或创建组织后显示任务、计划和组织动态。";
            _fleetNotificationCenterItems.Add(new FleetNotificationCenterItemRow(
                "入门",
                "尚未加入组织",
                "寻找已有组织，或创建自己的组织。",
                "",
                "前往",
                "find-fleet",
                FleetCommandBrush(BridgeBrushToken.StatusInfo)));
            return;
        }

        var added = 0;
        void AddItem(
            string kind,
            string title,
            string detail,
            string timeText,
            string actionText,
            string actionKey,
            System.Windows.Media.Brush accentBrush)
        {
            if (added >= 5)
            {
                return;
            }

            _fleetNotificationCenterItems.Add(new FleetNotificationCenterItemRow(
                kind,
                TruncateNotificationText(title, 34),
                TruncateNotificationText(detail, 52),
                timeText,
                actionText,
                actionKey,
                accentBrush));
            added++;
        }

        var pendingApplications = CountPendingFleetApplications();
        if (pendingApplications > 0 && CanCurrentUserManageFleetInfo())
        {
            AddItem(
                "待处理",
                $"{pendingApplications} 个加入申请",
                "前往管理组织审核新成员。",
                "",
                "处理",
                "applications",
                FleetCommandBrush(BridgeBrushToken.StatusWarn));
        }

        if (!string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle))
        {
            AddItem(
                "当前任务",
                _fleetCurrentTaskTitle,
                BuildCurrentTaskNotificationDetail(),
                _fleetCurrentTaskTime is null ? "" : _fleetCurrentTaskTime.Value.ToString("MM-dd HH:mm"),
                "详情",
                "task-detail",
                FleetCommandBrush(BridgeBrushToken.StatusInfo));
        }
        else if (CanCurrentUserPublishTasks())
        {
            AddItem(
                "当前任务",
                "暂无当前任务",
                "前往管理组织发布任务或集结点。",
                "",
                "发布",
                "task-manage",
                FleetCommandBrush(BridgeBrushToken.StatusInfo));
        }

        var nextPlan = GetVisibleActionPlans()
            .Where(plan => !plan.IsCanceled)
            .Where(plan => plan.StartTime >= DateTime.Now)
            .OrderBy(plan => plan.StartTime)
            .FirstOrDefault();
        if (nextPlan is not null)
        {
            AddItem(
                "行动计划",
                nextPlan.Title,
                $"开始时间 {nextPlan.StartTime:MM-dd HH:mm}，{nextPlan.ParticipantCountText}",
                nextPlan.StartTime.ToString("MM-dd HH:mm"),
                _joinedActionPlanIds.Contains(nextPlan.Id) ? "已预约" : "查看",
                "plan-detail",
                _joinedActionPlanIds.Contains(nextPlan.Id)
                    ? FleetCommandBrush(BridgeBrushToken.StatusOk)
                    : FleetCommandBrush(BridgeBrushToken.StatusWarn));
        }
        else if (CanCurrentUserPublishPlans())
        {
            AddItem(
                "行动计划",
                "未来 7 天暂无计划",
                "前往管理组织创建行动计划。",
                "",
                "创建",
                "plan-manage",
                FleetCommandBrush(BridgeBrushToken.StatusOk));
        }

        if (!string.IsNullOrWhiteSpace(_fleetNoticeTitle))
        {
            AddItem(
                "组织公告",
                _fleetNoticeTitle,
                string.IsNullOrWhiteSpace(_fleetNoticeContent) ? "点击查看公告。" : _fleetNoticeContent,
                "",
                CanCurrentUserManageAnnouncements() ? "编辑" : "查看",
                "notice-detail",
                FleetCommandBrush(BridgeBrushToken.StatusInfo));
        }
        else if (CanCurrentUserManageAnnouncements())
        {
            AddItem(
                "组织公告",
                "暂无组织公告",
                "发布公告后会同步给组织成员，并保留在公告历史中。",
                "",
                "发布",
                "notice-edit",
                FleetCommandBrush(BridgeBrushToken.StatusInfo));
        }

        var canOpenManagement = CanCurrentUserOpenFleetManagement();
        foreach (var log in _allFleetEventLogs
                     .Where(log => !IsPersonalPlanParticipationLog(log))
                     .OrderByDescending(log => log.Timestamp)
                     .Take(2))
        {
            AddItem(
                $"日志 / {log.Type}",
                SanitizeFleetEventText(log.Title),
                SanitizeFleetEventText(log.Detail),
                log.Timestamp.ToLocalTime().ToString("MM-dd HH:mm"),
                canOpenManagement ? "查看" : "",
                canOpenManagement ? "logs" : "",
                log.AccentBrush);
        }

        if (_fleetNotificationCenterItems.Count == 0)
        {
            AddItem(
                "组织状态",
                "暂无新的组织动态",
                "任务、公告、计划、申请和日志会在这里聚合。",
                "",
                "",
                "",
                FleetCommandBrush(BridgeBrushToken.StatusOff));
        }

        var activeCount = _fleetNotificationCenterItems.Count;
        FleetNotificationCenterSummaryText.Text = activeCount == 0
            ? "暂无待处理事项。"
            : $"{activeCount} 条组织动态，点击卡片可跳转处理。";
    }

    private void RefreshFleetRightContextSidebar()
    {
        if (FleetSubTabs?.SelectedItem == AllPlayersTab)
        {
            _membersPanelMode = MembersPanelMode.Member;
            RenderMemberSidebarContent();
            return;
        }

        if (FleetRightModuleOneTitleText is null)
        {
            return;
        }

        if (FleetSubTabs?.SelectedItem == FleetShipDatabaseTab)
        {
            var snapshot = BuildFleetShipSidebarSnapshot();
            if (string.Equals(_fleetShipSidebarSnapshot, snapshot, StringComparison.Ordinal))
            {
                return;
            }

            _fleetShipSidebarSnapshot = snapshot;
            ClearRightSidebarContent();
            UpdateMembersSidebarModeToggle();
            RenderFleetShipSidebarContent();
            return;
        }

        _fleetShipSidebarSnapshot = null;
        ClearRightSidebarContent();
        UpdateMembersSidebarModeToggle();

        var mode = GetFleetRightSidebarMode();
        switch (mode)
        {
            case FleetRightSidebarMode.Commander:
                RenderCommanderSidebarContent();
                break;
            default:
                RenderMemberSidebarContent();
                break;
        }
    }

    private FleetRightSidebarMode GetFleetRightSidebarMode()
    {
        if (HasCurrentUserFleetAdministrationPermission())
        {
            return FleetRightSidebarMode.Commander;
        }

        return FleetRightSidebarMode.Member;
    }

    private bool HasCurrentUserFleetAdministrationPermission()
    {
        return _hasFleet &&
               (IsCurrentUserFleetCommander() ||
                CanCurrentUserManageFleetInfo() ||
                CanCurrentUserRemoveMembers());
    }

    private void ClearRightSidebarContent()
    {
        RestoreRightSidebarModuleLayout();
        FleetRightModuleOneItems.Children.Clear();
        FleetRightModuleTwoItems.Children.Clear();
        FleetRightModuleThreeItems.Children.Clear();
        FleetRightModuleTwoItems.Columns = 2;
        FleetRightModuleTwoItems.Margin = new Thickness(0, 10, 0, 0);
        FleetRightModuleOneActionButton.Visibility = Visibility.Collapsed;
        FleetRightModuleOneActionButton.IsEnabled = true;
        FleetRightModuleOneActionButton.Content = "确认收到";
        FleetRightModuleOneBadge.Visibility = Visibility.Visible;
        FleetRightModuleTwoBadge.Visibility = Visibility.Visible;
        FleetRightModuleOneLinkButton.Visibility = Visibility.Collapsed;
        FleetRightModuleThreeLinkButton.Visibility = Visibility.Collapsed;
    }

    private void RestoreRightSidebarModuleLayout()
    {
        FleetRightModuleOnePanel.Visibility = Visibility.Visible;
        FleetRightModuleTwoPanel.Visibility = Visibility.Visible;
        FleetRightModuleThreePanel.Visibility = Visibility.Visible;
        FleetRightModuleOneRow.Height = new GridLength(0.96, GridUnitType.Star);
        FleetRightModuleTwoRow.Height = new GridLength(0.74, GridUnitType.Star);
        FleetRightModuleThreeRow.Height = new GridLength(0.97, GridUnitType.Star);
    }

    private void ApplyFleetShipSidebarLayout()
    {
        FleetRightModuleOnePanel.Visibility = Visibility.Visible;
        FleetRightModuleOneRow.Height = new GridLength(1, GridUnitType.Star);
        FleetRightModuleTwoPanel.Visibility = Visibility.Visible;
        FleetRightModuleTwoRow.Height = GridLength.Auto;
        FleetRightModuleThreePanel.Visibility = Visibility.Collapsed;
        FleetRightModuleThreeRow.Height = new GridLength(0);
        FleetRightModuleTwoItems.Columns = 1;
        FleetRightModuleTwoItems.Margin = new Thickness(0, 8, 0, 0);
    }

    private void RenderFleetShipSidebarContent()
    {
        ApplyFleetShipSidebarLayout();

        var classifiedShips = _fleetShipInventory
            .Select(ship => (Ship: ship, Category: ClassifyFleetShipAsset(ship)))
            .ToArray();
        var deployableShips = classifiedShips
            .Where(item => item.Category == FleetShipDeployabilityCategory.Deployable)
            .Select(item => item.Ship)
            .ToArray();
        var offlineCount = classifiedShips.Count(item =>
            item.Category == FleetShipDeployabilityCategory.OwnerOffline);
        var notFlyableCount = classifiedShips.Count(item =>
            item.Category == FleetShipDeployabilityCategory.NotFlyable);

        SetRightSidebarModuleHeader(
            FleetRightModuleOneTitleText,
            FleetRightModuleOneBadge,
            FleetRightModuleOneBadgeText,
            "可调度",
            deployableShips.Length.ToString(CultureInfo.InvariantCulture));

        var availabilityGroups = FleetShipAvailabilityGrouping.Project(
            deployableShips.Select(ship =>
            {
                var flyableLoaner = IsFleetShipConcept(ship)
                    ? ship.LoanerRows.FirstOrDefault(IsFleetShipFlyable)
                    : null;
                return new FleetShipAvailabilityEntry(
                    BuildFleetShipInventoryKey(ship),
                    FirstNonEmpty(ship.OwnerAccountId, ship.OwnerGameId, ship.OwnerCallsign, ship.OwnerDisplay),
                    ship.OwnerDisplay,
                    ship.ShipName,
                    flyableLoaner is null ? ship.ShipRole : $"可飞替代 / {flyableLoaner.ShipName}",
                    GetFleetShipSpecSortRank(ship.ShipSpec, largeFirst: true),
                    ship.ShipPriceValue ?? 0m);
            }));

        foreach (var group in availabilityGroups)
        {
            AddFleetShipAvailabilityOwnerHeader(group.OwnerDisplay, group.Ships.Count);
            foreach (var ship in group.Ships)
            {
                AddFleetShipAvailabilityRow(ship.ShipName, ship.Detail);
            }
        }

        AddRightSidebarEmptyStateIfNeeded(FleetRightModuleOneItems, "当前没有可调度舰船。");

        var blockedCount = offlineCount + notFlyableCount;
        SetRightSidebarModuleHeader(
            FleetRightModuleTwoTitleText,
            FleetRightModuleTwoBadge,
            FleetRightModuleTwoBadgeText,
            "暂不可调度",
            blockedCount.ToString(CultureInfo.InvariantCulture));
        AddRightSidebarMetric(
            FleetRightModuleTwoItems,
            "持有人离线",
            offlineCount.ToString(CultureInfo.InvariantCulture),
            FleetCommandBrush(offlineCount > 0 ? BridgeBrushToken.StatusWarn : BridgeBrushToken.StatusOff));
        AddRightSidebarMetric(
            FleetRightModuleTwoItems,
            "当前不可飞",
            notFlyableCount.ToString(CultureInfo.InvariantCulture),
            FleetCommandBrush(notFlyableCount > 0 ? BridgeBrushToken.StatusWarn : BridgeBrushToken.StatusOff));
    }

    private void AddFleetShipAvailabilityOwnerHeader(string ownerDisplay, int shipCount)
    {
        var header = new Grid
        {
            Margin = new Thickness(1, FleetRightModuleOneItems.Children.Count == 0 ? 0 : 4, 1, 2)
        };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.Children.Add(new TextBlock
        {
            Text = ownerDisplay,
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink),
            FontFamily = new MediaFontFamily("Microsoft YaHei UI"),
            FontSize = 11.5,
            FontWeight = FontWeights.SemiBold,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        var count = new TextBlock
        {
            Text = $"{shipCount} 艘",
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink3),
            FontFamily = new MediaFontFamily("Segoe UI"),
            FontSize = 10.5,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(count, 1);
        header.Children.Add(count);
        FleetRightModuleOneItems.Children.Add(header);
    }

    private void AddFleetShipAvailabilityRow(string shipName, string detail)
    {
        var row = new Grid
        {
            MinHeight = 30,
            Margin = new Thickness(0, 0, 0, 1)
        };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(10) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.Children.Add(new System.Windows.Shapes.Ellipse
        {
            Width = 5,
            Height = 5,
            Fill = FleetCommandBrush(BridgeBrushToken.StatusOk),
            VerticalAlignment = VerticalAlignment.Center
        });

        var content = new Grid { Margin = new Thickness(5, 0, 0, 0) };
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        content.Children.Add(new TextBlock
        {
            Text = shipName,
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink),
            FontSize = 11,
            FontWeight = FontWeights.SemiBold,
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        var detailText = new TextBlock
        {
            Text = detail,
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink3),
            FontSize = 10,
            Margin = new Thickness(7, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        Grid.SetColumn(detailText, 1);
        content.Children.Add(detailText);
        Grid.SetColumn(content, 1);
        row.Children.Add(content);
        FleetRightModuleOneItems.Children.Add(row);
    }

    private static string BuildFleetShipInventoryKey(FleetShipInventoryRow ship)
    {
        return BuildFleetShipKey(ship.OwnerGameId, ship.ShipCode, ship.ShipInstanceId);
    }

    private FleetShipInventoryRow[] BuildSchedulableFleetShips()
    {
        var rows = new List<FleetShipInventoryRow>();
        foreach (var ship in _fleetShipInventory)
        {
            if (IsFleetShipConcept(ship))
            {
                rows.AddRange(ship.LoanerRows.Where(IsFleetShipFlyable));
                continue;
            }

            if (IsFleetShipFlyable(ship))
            {
                rows.Add(ship);
            }
        }

        return rows.ToArray();
    }

    private bool IsFleetShipDispatchableAsset(FleetShipInventoryRow ship)
    {
        return ClassifyFleetShipAsset(ship) == FleetShipDeployabilityCategory.Deployable;
    }

    private FleetShipDeployabilityCategory ClassifyFleetShipAsset(FleetShipInventoryRow ship)
    {
        var hasFlyableLoaner = IsFleetShipConcept(ship) &&
                               ship.LoanerRows.Any(IsFleetShipFlyable);
        return FleetShipDeployabilityPolicy.Classify(
            ownerOnline: IsFleetShipOwnerOnline(ship),
            isSynced: true,
            shipFlyable: IsFleetShipFlyable(ship),
            hasFlyableLoaner: hasFlyableLoaner);
    }

    private FleetShipInventoryRow? ResolvePreferredFleetShipDispatch()
    {
        return BuildSchedulableFleetShips()
            .Where(IsFleetShipOwnerOnline)
            .OrderBy(ship => GetFleetShipSpecSortRank(ship.ShipSpec, largeFirst: true))
            .ThenByDescending(ship => ship.ShipPriceValue ?? 0m)
            .FirstOrDefault();
    }

    private int CountFleetShipsByRoleCategory(IEnumerable<FleetShipInventoryRow> ships, FleetShipRoleCategory category)
    {
        return ships.Count(ship => GetFleetShipRoleCategory(ship.ShipRole) == category);
    }

    private bool IsFleetShipOwnerOnline(FleetShipInventoryRow ship)
    {
        return _players.Any(player =>
            IsOnlineStatus(player.SharedOnlineStatusValue) &&
            MatchesFleetShipOwner(player, ship));
    }

    private static bool MatchesFleetShipOwner(PlayerRow player, FleetShipInventoryRow ship)
    {
        return IdentityValueEquals(player.Name, ship.OwnerGameId) ||
               IdentityValueEquals(player.Name, ship.OwnerCallsign) ||
               IdentityValueEquals(player.Name, ship.OwnerDisplay) ||
               IdentityValueEquals(player.Callsign, ship.OwnerGameId) ||
               IdentityValueEquals(player.Callsign, ship.OwnerCallsign) ||
               IdentityValueEquals(player.Callsign, ship.OwnerDisplay);
    }

    private static bool IdentityValueEquals(string? left, string? right)
    {
        return !string.IsNullOrWhiteSpace(left) &&
               !string.IsNullOrWhiteSpace(right) &&
               left.Trim().Equals(right.Trim(), StringComparison.OrdinalIgnoreCase);
    }

    private void RenderCommanderSidebarContent()
    {
        var pendingApplicationRows = BuildPendingFleetApplicationRows();
        var pendingApplications = pendingApplicationRows.Length;
        var notInGameCount = _players.Count(player =>
            player.ServerShardDisplayText.Equals("未进入游戏", StringComparison.Ordinal));
        var unknownShipCount = _players.Count(player => IsUnknownValue(player.RawShip) || IsUnknownValue(player.Ship));
        var unknownLocationCount = _players.Count(player => IsUnknownLocation(player.RawLocation) || IsUnknownLocation(player.Location));
        var syncIssueCount = IsLoggedIn ? 0 : 1;
        var pendingTotal = pendingApplications;

        SetRightSidebarModuleHeader(
            FleetRightModuleOneTitleText,
            FleetRightModuleOneBadge,
            FleetRightModuleOneBadgeText,
            "待处理",
            pendingTotal.ToString(CultureInfo.InvariantCulture));
        FleetRightModuleOneLinkButton.Visibility = CanCurrentUserOpenFleetManagement()
            ? Visibility.Visible
            : Visibility.Collapsed;

        RenderRightSidebarPendingApplications(pendingApplicationRows);

        SetRightSidebarModuleHeader(
            FleetRightModuleTwoTitleText,
            FleetRightModuleTwoBadge,
            FleetRightModuleTwoBadgeText,
            "成员态势",
            _players.Count.ToString(CultureInfo.InvariantCulture));
        AddRightSidebarMetric(FleetRightModuleTwoItems, "未进入游戏", notInGameCount.ToString(CultureInfo.InvariantCulture), FleetCommandBrush(notInGameCount > 0 ? BridgeBrushToken.StatusWarn : BridgeBrushToken.StatusOk));
        AddRightSidebarMetric(FleetRightModuleTwoItems, "飞船未知", unknownShipCount.ToString(CultureInfo.InvariantCulture), FleetCommandBrush(unknownShipCount > 0 ? BridgeBrushToken.StatusWarn : BridgeBrushToken.StatusOk));
        AddRightSidebarMetric(FleetRightModuleTwoItems, "位置未知", unknownLocationCount.ToString(CultureInfo.InvariantCulture), FleetCommandBrush(unknownLocationCount > 0 ? BridgeBrushToken.StatusWarn : BridgeBrushToken.StatusOk));
        AddRightSidebarMetric(FleetRightModuleTwoItems, "同步异常", syncIssueCount.ToString(CultureInfo.InvariantCulture), FleetCommandBrush(syncIssueCount > 0 ? BridgeBrushToken.StatusWarn : BridgeBrushToken.StatusOk));

        SetRightSidebarModuleHeader(
            FleetRightModuleThreeTitleText,
            null,
            null,
            "管理动态",
            "");
        FleetRightModuleThreeLinkButton.Visibility = CanCurrentUserViewFleetLogs()
            ? Visibility.Visible
            : Visibility.Collapsed;
        foreach (var log in GetCommanderVisibleFleetActivity())
        {
            AddRightSidebarActivity(FleetRightModuleThreeItems, SanitizeFleetEventText(log.Title), log.Timestamp.ToLocalTime().ToString("MM-dd HH:mm"), log.AccentBrush);
        }

        AddRightSidebarEmptyStateIfNeeded(FleetRightModuleThreeItems, "暂无组织动态。");
    }

    private void RenderRightSidebarPendingApplications(IReadOnlyCollection<FleetApplicationRow> applications)
    {
        AddRightSidebarPendingApplicationHeader(applications.Count);

        if (applications.Count == 0)
        {
            AddRightSidebarPendingApplicationEmptyState();
            return;
        }

        const int previewLimit = 2;
        foreach (var application in applications.Take(previewLimit))
        {
            AddRightSidebarPendingApplicationRow(application);
        }

        var remainingCount = applications.Count - previewLimit;
        if (remainingCount > 0)
        {
            AddRightSidebarPendingApplicationMoreHint(remainingCount);
        }
    }

    private void AddRightSidebarPendingApplicationHeader(int count)
    {
        var header = new StackPanel
        {
            Orientation = ControlsOrientation.Horizontal,
            Margin = new Thickness(0, 0, 0, 5)
        };

        header.Children.Add(new TextBlock
        {
            Text = "待审核申请",
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink2),
            FontFamily = new MediaFontFamily("Microsoft YaHei UI"),
            FontSize = 11,
            FontWeight = FontWeights.SemiBold,
            VerticalAlignment = VerticalAlignment.Center
        });

        if (count > 0)
        {
            header.Children.Add(new Border
            {
                Margin = new Thickness(6, 0, 0, 0),
                Style = (Style)FindResource("BridgeCountBadgeStyle"),
                Child = new TextBlock
                {
                    Text = count.ToString(CultureInfo.InvariantCulture),
                    Style = (Style)FindResource("BridgeCountBadgeTextStyle")
                }
            });
        }

        FleetRightModuleOneItems.Children.Add(header);
    }

    private void AddRightSidebarPendingApplicationRow(FleetApplicationRow application)
    {
        var border = new Border
        {
            MinHeight = 44,
            Background = FleetCommandBrush(BridgeBrushToken.Panel),
            BorderBrush = FleetCommandBrush(BridgeBrushToken.Hairline),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Padding = new Thickness(7, 5, 7, 5),
            Margin = new Thickness(0, 0, 0, 5),
            SnapsToDevicePixels = true
        };

        border.MouseEnter += (_, _) =>
        {
            border.Background = FleetCommandBrush(BridgeBrushToken.RowHover);
            border.BorderBrush = FleetCommandBrush(BridgeBrushToken.ChipHairline);
        };
        border.MouseLeave += (_, _) =>
        {
            border.Background = FleetCommandBrush(BridgeBrushToken.Panel);
            border.BorderBrush = FleetCommandBrush(BridgeBrushToken.Hairline);
        };

        var grid = new Grid { VerticalAlignment = VerticalAlignment.Center };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var avatar = CreateRightSidebarApplicationAvatar(application);
        avatar.Margin = new Thickness(0, 0, 8, 0);
        Grid.SetColumn(avatar, 0);
        grid.Children.Add(avatar);

        var identity = new StackPanel
        {
            VerticalAlignment = VerticalAlignment.Center,
            MinWidth = 78
        };
        identity.Children.Add(new TextBlock
        {
            Text = application.DisplayName,
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink),
            FontFamily = new MediaFontFamily("Microsoft YaHei UI"),
            FontSize = 12,
            FontWeight = FontWeights.SemiBold,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        identity.Children.Add(new TextBlock
        {
            Text = "申请加入组织",
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink3),
            FontFamily = new MediaFontFamily("Microsoft YaHei UI"),
            FontSize = 10.5,
            Margin = new Thickness(0, 2, 0, 0),
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        Grid.SetColumn(identity, 1);
        grid.Children.Add(identity);

        var createdAt = new TextBlock
        {
            Text = application.CreatedAtText,
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink2),
            FontFamily = new MediaFontFamily("Segoe UI"),
            FontSize = 10.5,
            Width = 94,
            Margin = new Thickness(8, 0, 8, 0),
            TextAlignment = TextAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        Grid.SetColumn(createdAt, 2);
        grid.Children.Add(createdAt);

        var acceptButton = CreateRightSidebarApplicationDecisionButton(application, approve: true);
        Grid.SetColumn(acceptButton, 3);
        grid.Children.Add(acceptButton);

        var rejectButton = CreateRightSidebarApplicationDecisionButton(application, approve: false);
        rejectButton.Margin = new Thickness(5, 0, 0, 0);
        Grid.SetColumn(rejectButton, 4);
        grid.Children.Add(rejectButton);

        border.Child = grid;
        FleetRightModuleOneItems.Children.Add(border);
    }

    private FrameworkElement CreateRightSidebarApplicationAvatar(FleetApplicationRow application)
    {
        var frame = new Border
        {
            Width = 28,
            Height = 28,
            Background = FleetCommandBrush(BridgeBrushToken.Rail),
            BorderBrush = FleetCommandBrush(BridgeBrushToken.ChipHairline),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            SnapsToDevicePixels = true
        };

        var avatarSource = TryCreateImageSource(application.AvatarPath);
        if (avatarSource is not null)
        {
            frame.Child = new ControlsImage
            {
                Source = avatarSource,
                Stretch = Stretch.UniformToFill,
                Width = 24,
                Height = 24
            };
        }
        else
        {
            frame.Child = CreateIdentityBeaconAvatarPlaceholder(
                BridgeSceneContext.GetRequiredAccentBrush(this));
        }

        return frame;
    }

    private void AddRightSidebarPendingApplicationMoreHint(int remainingCount)
    {
        var border = new Border
        {
            Background = FleetCommandBrush(BridgeBrushToken.Rail),
            BorderBrush = FleetCommandBrush(BridgeBrushToken.RowHairline),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Padding = new Thickness(8, 4, 8, 4),
            Margin = new Thickness(0, 0, 0, 4),
            SnapsToDevicePixels = true
        };

        border.Child = new TextBlock
        {
            Text = $"还有 {remainingCount.ToString(CultureInfo.InvariantCulture)} 条待审核申请，点击全部查看",
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink3),
            FontFamily = new MediaFontFamily("Microsoft YaHei UI"),
            FontSize = 10.5,
            TextTrimming = TextTrimming.CharacterEllipsis
        };

        FleetRightModuleOneItems.Children.Add(border);
    }

    private static ImageSource? TryCreateImageSource(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        return new ImagePathConverter().Convert(value, typeof(ImageSource), null!, CultureInfo.InvariantCulture) as ImageSource;
    }

    private System.Windows.Controls.Button CreateRightSidebarApplicationDecisionButton(FleetApplicationRow application, bool approve)
    {
        var button = new System.Windows.Controls.Button
        {
            Content = approve ? "\u2713" : "\u00d7",
            Width = 28,
            Height = 28,
            Tag = application,
            ToolTip = approve ? "接受申请" : "拒绝申请",
            Background = FleetCommandBrush(BridgeBrushToken.Panel),
            BorderBrush = FleetCommandBrush(BridgeBrushToken.ChipHairline),
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink)
        };

        if (FleetRightModuleOneItems.TryFindResource("RightSidebarDecisionButton") is Style style)
        {
            button.Style = style;
        }

        if (approve)
        {
            button.Click += ApproveFleetApplication_Click;
        }
        else
        {
            button.Click += RejectFleetApplication_Click;
        }

        var hoverBorder = FleetCommandBrush(
            approve ? BridgeBrushToken.StatusOk : BridgeBrushToken.StatusBad);
        button.MouseEnter += (_, _) =>
        {
            button.Background = FleetCommandBrush(BridgeBrushToken.RowHover);
            button.BorderBrush = hoverBorder;
            button.Foreground = FleetCommandBrush(BridgeBrushToken.Ink);
        };
        button.MouseLeave += (_, _) =>
        {
            button.Background = FleetCommandBrush(BridgeBrushToken.Panel);
            button.BorderBrush = FleetCommandBrush(BridgeBrushToken.ChipHairline);
            button.Foreground = FleetCommandBrush(BridgeBrushToken.Ink);
        };
        button.PreviewMouseDown += (_, _) =>
        {
            button.Background = FleetCommandBrush(BridgeBrushToken.Rail);
            button.BorderBrush = BridgeSceneContext.GetRequiredAccentBrush(this);
        };
        button.PreviewMouseUp += (_, _) =>
        {
            button.Background = FleetCommandBrush(BridgeBrushToken.RowHover);
            button.BorderBrush = hoverBorder;
        };

        return button;
    }

    private void AddRightSidebarPendingApplicationEmptyState()
    {
        var border = new Border
        {
            Background = FleetCommandBrush(BridgeBrushToken.Panel),
            BorderBrush = FleetCommandBrush(BridgeBrushToken.Hairline),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Padding = new Thickness(9, 7, 9, 7),
            Margin = new Thickness(0, 0, 0, 4),
            SnapsToDevicePixels = true
        };

        var stack = new StackPanel();
        stack.Children.Add(new TextBlock
        {
            Text = "暂无待审核申请",
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink),
            FontFamily = new MediaFontFamily("Microsoft YaHei UI"),
            FontSize = 12,
            FontWeight = FontWeights.SemiBold
        });
        stack.Children.Add(new TextBlock
        {
            Text = "所有加入申请均已处理",
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink3),
            FontFamily = new MediaFontFamily("Microsoft YaHei UI"),
            FontSize = 10.5,
            Margin = new Thickness(0, 3, 0, 0)
        });

        border.Child = stack;
        FleetRightModuleOneItems.Children.Add(border);
    }

    private void RenderMemberSidebarContent()
    {
        if (FleetMemberTimelinePanel is null)
        {
            return;
        }

        FleetMemberTimelinePanel.Visibility = Visibility.Visible;

        var now = DateTimeOffset.Now;
        var timeline = new List<(DateTimeOffset Timestamp, FleetNotificationCenterItemRow Row)>();
        timeline.AddRange(_fleetMemberSidebarChatPreview.Select(message =>
            (message.Message.CreatedAt,
             new FleetNotificationCenterItemRow(
                 "通讯",
                 message.SenderCallsign,
                 message.Text,
                 CommunicationTimeFormatter.Format(message.Message.CreatedAt, now),
                 "",
                 "",
                 null))));
        timeline.AddRange(GetMemberVisibleFleetActivity().Select(log =>
            (log.Timestamp,
             new FleetNotificationCenterItemRow(
                 ResolveFleetTimelineCategory(log),
                 SanitizeFleetEventText(log.Title),
                 SanitizeFleetEventText(log.Detail),
                 CommunicationTimeFormatter.Format(log.Timestamp, now),
                 "",
                 "",
                 null))));

        _fleetMemberTimelineItems.Clear();
        foreach (var entry in timeline
                     .OrderByDescending(entry => entry.Timestamp)
                     .Take(10))
        {
            _fleetMemberTimelineItems.Add(entry.Row);
        }

        if (_fleetMemberTimelineItems.Count == 0)
        {
            _fleetMemberTimelineItems.Add(new FleetNotificationCenterItemRow(
                "资料",
                _fleetMemberSidebarChatPreviewLoaded ? "暂无组织动态" : "正在获取最新通讯",
                "新通讯和成员可见事件会按时间合并显示。",
                "",
                "",
                "",
                null));
        }

        FleetMemberTimelineOpenChatButton.IsEnabled = _hasFleet;
        if (!_fleetMemberSidebarChatPreviewLoaded)
        {
            _ = RefreshFleetMemberSidebarChatPreviewAsync();
        }
    }

    private static string ResolveFleetTimelineCategory(FleetEventLogRow log)
    {
        var text = $"{log.Type} {log.Title} {log.Detail}";
        if (text.Contains("小队", StringComparison.OrdinalIgnoreCase))
        {
            return "小队";
        }

        if (text.Contains("公告", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("任务", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("计划", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("集结", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("通知", StringComparison.OrdinalIgnoreCase))
        {
            return "公告";
        }

        if (text.Contains("成员", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("加入", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("退出", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("上线", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("离线", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("移出", StringComparison.OrdinalIgnoreCase))
        {
            return "人员";
        }

        return "资料";
    }

    private void FleetMemberTimelineOpenChatButton_Click(object sender, RoutedEventArgs e)
    {
        NavigateToFleetChatFromMemberPreview();
    }

    private void AddRightSidebarChatPreviewRow(
        System.Windows.Controls.Panel panel,
        FleetChatMessageRow message)
    {
        var row = new Border
        {
            Background = Brushes.Transparent,
            BorderBrush = FleetCommandBrush(BridgeBrushToken.Hairline),
            BorderThickness = new Thickness(0, 0, 0, 1),
            Padding = new Thickness(0, 5, 0, 7),
            Margin = new Thickness(0, 0, 0, 2)
        };

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var avatarButton = new System.Windows.Controls.Button
        {
            Width = 32,
            Height = 32,
            Margin = new Thickness(0, 1, 9, 0),
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top,
            DataContext = message,
            ToolTip = "用户菜单"
        };
        if (TryFindResource("UserAvatarButtonStyle") is Style avatarStyle)
        {
            avatarButton.Style = avatarStyle;
        }

        var avatarGrid = new Grid();
        var avatarSource = TryCreateImageSource(message.SenderAvatarImageData);
        if (avatarSource is null)
        {
            avatarGrid.Children.Add(CreateIdentityBeaconAvatarPlaceholder(message.SenderRoleBrush));
        }
        else
        {
            avatarGrid.Children.Add(new System.Windows.Controls.Image
            {
                Source = avatarSource,
                Stretch = Stretch.UniformToFill
            });
        }
        avatarButton.Content = avatarGrid;
        avatarButton.Click += UserAvatarButton_Click;
        Grid.SetColumn(avatarButton, 0);
        grid.Children.Add(avatarButton);

        var content = new StackPanel();
        var meta = new Grid();
        meta.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        meta.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        meta.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        meta.Children.Add(new TextBlock
        {
            Text = message.SenderCallsign,
            Foreground = message.SenderRoleBrush,
            FontSize = 10.5,
            FontWeight = FontWeights.SemiBold,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        var role = new TextBlock
        {
            Text = message.SenderRoleTitle,
            Foreground = message.SenderRoleBrush,
            FontSize = 9,
            Margin = new Thickness(7, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
            Visibility = message.RoleVisibility
        };
        Grid.SetColumn(role, 1);
        meta.Children.Add(role);
        var time = new TextBlock
        {
            Text = message.TimeText,
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink3),
            FontFamily = new MediaFontFamily("Bahnschrift"),
            FontSize = 9,
            Margin = new Thickness(8, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(time, 2);
        meta.Children.Add(time);
        content.Children.Add(meta);
        content.Children.Add(new TextBlock
        {
            Text = message.Text,
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink),
            FontSize = 10.5,
            Margin = new Thickness(0, 4, 0, 0),
            MaxHeight = 34,
            TextWrapping = TextWrapping.Wrap,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        Grid.SetColumn(content, 1);
        grid.Children.Add(content);
        row.Child = grid;
        panel.Children.Add(row);
    }

    private ContentControl CreateIdentityBeaconAvatarPlaceholder(System.Windows.Media.Brush? foreground = null)
    {
        var placeholder = new ContentControl
        {
            Foreground = foreground ?? BridgeSceneContext.GetRequiredAccentBrush(this)
        };
        if (TryFindResource("IdentityBeaconAvatarPlaceholderStyle") is Style placeholderStyle)
        {
            placeholder.Style = placeholderStyle;
        }

        return placeholder;
    }

    private void SetRightSidebarModuleHeader(TextBlock title, Border? badge, TextBlock? badgeText, string titleText, string badgeValue)
    {
        title.Text = titleText;
        if (badge is null || badgeText is null)
        {
            return;
        }

        badgeText.Text = badgeValue;
        badge.Visibility = string.IsNullOrWhiteSpace(badgeValue) ||
                           badgeValue.Equals("0", StringComparison.Ordinal)
            ? Visibility.Collapsed
            : Visibility.Visible;
    }

    private void AddRightSidebarInfoRow(
        System.Windows.Controls.Panel panel,
        string label,
        string value,
        string detail,
        string serializedAccent) =>
        AddRightSidebarInfoRow(panel, label, value, detail, ParseRequiredSidebarAccent(serializedAccent));

    private void AddRightSidebarInfoRow(
        System.Windows.Controls.Panel panel,
        string label,
        string value,
        string detail,
        System.Windows.Media.Brush accentBrush)
    {
        var border = new Border
        {
            Background = FleetCommandBrush(BridgeBrushToken.Panel),
            BorderBrush = FleetCommandBrush(BridgeBrushToken.Hairline),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Padding = new Thickness(7, 4, 7, 4),
            Margin = new Thickness(0, 0, 0, 4)
        };

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var marker = new System.Windows.Shapes.Ellipse
        {
            Width = 6,
            Height = 6,
            Fill = accentBrush,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 0)
        };
        Grid.SetColumn(marker, 0);
        grid.Children.Add(marker);

        var stack = new StackPanel { Margin = new Thickness(7, 0, 0, 0) };
        Grid.SetColumn(stack, 1);
        stack.Children.Add(new TextBlock
        {
            Text = label,
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink2),
            FontSize = 10.5,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        stack.Children.Add(new TextBlock
        {
            Text = value,
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink),
            FontSize = 12,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 2, 0, 0),
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        if (!string.IsNullOrWhiteSpace(detail))
        {
            stack.Children.Add(new TextBlock
            {
                Text = detail,
                Foreground = FleetCommandBrush(BridgeBrushToken.Ink3),
                FontSize = 10.5,
                Margin = new Thickness(0, 2, 0, 0),
                TextTrimming = TextTrimming.CharacterEllipsis
            });
        }
        grid.Children.Add(stack);

        border.Child = grid;
        panel.Children.Add(border);
    }

    private void AddRightSidebarMetric(
        System.Windows.Controls.Panel panel,
        string label,
        string value,
        System.Windows.Media.Brush accentBrush)
    {
        var border = new Border
        {
            Background = FleetCommandBrush(BridgeBrushToken.Panel),
            BorderBrush = FleetCommandBrush(BridgeBrushToken.Hairline),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Padding = new Thickness(7, 4, 7, 4),
            Margin = new Thickness(0, 0, 6, 5)
        };

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var labelText = new TextBlock
        {
            Text = label,
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink2),
            FontSize = 10,
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        Grid.SetColumn(labelText, 0);
        grid.Children.Add(labelText);

        var valueText = new TextBlock
        {
            Text = value,
            Foreground = accentBrush,
            FontSize = 11.5,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(6, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        Grid.SetColumn(valueText, 1);
        grid.Children.Add(valueText);

        border.Child = grid;
        panel.Children.Add(border);
    }

    private void AddRightSidebarStatusMetric(
        System.Windows.Controls.Panel panel,
        string label,
        string value,
        System.Windows.Media.Brush accentBrush)
    {
        var row = new StackPanel
        {
            Style = TryFindResource("BridgeDirectoryFieldRowStyle") as Style,
            Margin = new Thickness(0, 2, 0, 6),
            ToolTip = $"{label} / {value}"
        };

        var labelText = new TextBlock
        {
            Text = label,
            Style = TryFindResource("BridgeDirectoryFieldLabelTextStyle") as Style
        };
        row.Children.Add(labelText);

        var valueText = new TextBlock
        {
            Text = value,
            Style = TryFindResource("BridgeDirectoryFieldValueTextStyle") as Style,
            Foreground = accentBrush,
            MaxWidth = 126,
            ToolTip = value
        };
        row.Children.Add(valueText);

        panel.Children.Add(row);
    }

    private void AddRightSidebarActivity(System.Windows.Controls.Panel panel, string title, string timeText, System.Windows.Media.Brush accentBrush)
    {
        _ = accentBrush;
        var grid = new Grid { Margin = new Thickness(0, 0, 0, 7) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var titleText = new TextBlock
        {
            Text = title,
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink),
            FontSize = 11,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        Grid.SetColumn(titleText, 0);
        grid.Children.Add(titleText);

        var time = new TextBlock
        {
            Text = timeText,
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink2),
            FontSize = 10.5,
            Margin = new Thickness(8, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(time, 1);
        grid.Children.Add(time);

        panel.Children.Add(grid);
    }

    private static bool IsFleetShipFlyable(FleetShipInventoryRow ship)
    {
        return ship.ShipStatus.Equals("可飞", StringComparison.OrdinalIgnoreCase) ||
               ship.ShipStatus.Equals("Flyable", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsFleetShipConcept(FleetShipInventoryRow ship)
    {
        return ship.ShipStatus.Contains("概念", StringComparison.OrdinalIgnoreCase) ||
               ship.ShipStatus.Contains("Concept", StringComparison.OrdinalIgnoreCase);
    }

    private void AddRightSidebarEmptyStateIfNeeded(System.Windows.Controls.Panel panel, string message)
    {
        if (panel.Children.Count > 0)
        {
            return;
        }

        panel.Children.Add(new TextBlock
        {
            Text = message,
            Foreground = FleetCommandBrush(BridgeBrushToken.Ink2),
            FontSize = 11.5,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 4, 0, 0)
        });
    }

    private IEnumerable<FleetEventLogRow> GetCommanderVisibleFleetActivity()
    {
        return _allFleetEventLogs
            .Where(log => !IsPersonalPlanParticipationLog(log))
            .Where(log => EnableFleetActionManagementUi || !IsFleetActionManagementLog(log))
            .Where(log => IsCommanderActivity(log))
            .OrderByDescending(log => log.Timestamp);
    }

    private IEnumerable<FleetEventLogRow> GetMemberVisibleFleetActivity()
    {
        return _allFleetEventLogs
            .Where(log => !IsPersonalPlanParticipationLog(log))
            .Where(log => IsMemberVisibleActivity(log))
            .OrderByDescending(log => log.Timestamp);
    }

    private static bool IsCommanderActivity(FleetEventLogRow log)
    {
        var text = $"{log.Type} {log.Title} {log.Detail}";
        var isGovernanceActivity =
            text.Contains("加入", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("退出", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("申请", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("公告", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("介绍", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("资料", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("角色", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("权限", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("资源", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("通知", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("舰队", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("小队", StringComparison.OrdinalIgnoreCase);

        if (isGovernanceActivity)
        {
            return true;
        }

        return EnableFleetActionManagementUi && IsFleetActionManagementLog(log);
    }

    private static bool IsFleetActionManagementLog(FleetEventLogRow log)
    {
        var text = $"{log.Type} {log.Title} {log.Detail}";
        return text.Contains("任务", StringComparison.OrdinalIgnoreCase) ||
               text.Contains("计划", StringComparison.OrdinalIgnoreCase) ||
               text.Contains("行动", StringComparison.OrdinalIgnoreCase) ||
               text.Contains("预约", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsMemberVisibleActivity(FleetEventLogRow log)
    {
        var text = $"{log.Type} {log.Title} {log.Detail}";
        if (text.Contains("审核", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("申请", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("权限", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("移出", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("封禁", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        return text.Contains("任务", StringComparison.OrdinalIgnoreCase) ||
               text.Contains("集结", StringComparison.OrdinalIgnoreCase) ||
               text.Contains("公告", StringComparison.OrdinalIgnoreCase) ||
               text.Contains("加入", StringComparison.OrdinalIgnoreCase) ||
               text.Contains("退出", StringComparison.OrdinalIgnoreCase) ||
               text.Contains("上线", StringComparison.OrdinalIgnoreCase) ||
               text.Contains("离线", StringComparison.OrdinalIgnoreCase) ||
               text.Contains("小队", StringComparison.OrdinalIgnoreCase) ||
               text.Contains("计划", StringComparison.OrdinalIgnoreCase) ||
               text.Contains("资料", StringComparison.OrdinalIgnoreCase) ||
               text.Contains("介绍", StringComparison.OrdinalIgnoreCase);
    }

    private PlayerRow? GetLocalPlayerRow()
    {
        return _players.FirstOrDefault(player => IsLocalPlayerIdentity(player.Name, player.Callsign));
    }

    private string GetCurrentUserRoleTitle()
    {
        if (IsCurrentUserFleetCommander())
        {
            return "组织负责人";
        }

        var permission = GetCurrentUserFleetPermission();
        if (permission is { PermissionEnabled: true } &&
            !string.IsNullOrWhiteSpace(permission.RoleTitle))
        {
            return NormalizeRoleTitle(permission.RoleTitle);
        }

        return GetLocalPlayerRow()?.Role ?? "成员";
    }

    private string GetCurrentFleetOrderKey()
    {
        if (!string.IsNullOrWhiteSpace(_fleetCurrentTaskHistoryKey))
        {
            return _fleetCurrentTaskHistoryKey;
        }

        return $"{_fleetCurrentTaskTitle}|{_fleetCurrentTaskTime:O}|{_fleetCurrentTaskNoticeRevision}";
    }

    private string GetGameServerRegionDisplay()
    {
        if (IsGameServerRegionCurrent())
        {
            return _gameServerRegion;
        }

        return _isGameProcessRunning ? "等待确认" : "仅游戏中显示";
    }

    private string GetNetworkSyncStatusText()
    {
        if (IsLoggedIn && !CanSynchronizeUserData)
        {
            return _identityBindingAssessment.State == StarBridge.Core.Identity.IdentityVerificationState.Mismatch
                ? "无法验证身份"
                : "等待身份绑定";
        }

        if (IsLoggedIn && _syncPrivacySettings.PresenceVisibilityMode == PlayerPresenceVisibilityMode.Offline)
        {
            return "离线模式";
        }

        if (IsLoggedIn && _syncPrivacySettings.PresenceVisibilityMode == PlayerPresenceVisibilityMode.Invisible)
        {
            return "隐身接收";
        }

        if (_isNetworkSyncRunning)
        {
            return "同步中";
        }

        if (!IsLoggedIn)
        {
            return "等待同步";
        }

        return _syncPrivacySettings.SyncEnabled ? "同步已开启" : "同步已关闭";
    }

    private static bool IsOnlineStatus(string? status)
    {
        return string.Equals(status, "Online", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(status, "在线", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(status, "运行中", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(status, "游戏运行中", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsOverlayGamePresence(PlayerRow player) =>
        player.Presence == PlayerPresenceKind.InGame;

    private static bool IsUnknownValue(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ||
               value.Equals("Unknown", StringComparison.OrdinalIgnoreCase) ||
               value.Equals("飞船：未知", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsUnknownLocation(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ||
               value.Equals("Unknown", StringComparison.OrdinalIgnoreCase) ||
               value.Contains("未知", StringComparison.OrdinalIgnoreCase);
    }

    private static string NormalizeOptionalDisplay(string? value, string fallback)
    {
        return string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();
    }

    private static SolidColorBrush CreateSolidBrush(string hex)
    {
        var brush = new SolidColorBrush((Color)System.Windows.Media.ColorConverter.ConvertFromString(hex));
        brush.Freeze();
        return brush;
    }

    private static SolidColorBrush ParseRequiredSidebarAccent(string serializedAccent)
    {
        if (string.IsNullOrWhiteSpace(serializedAccent))
        {
            throw new InvalidOperationException("A required fleet sidebar accent was empty.");
        }

        return BrushFromHex(serializedAccent);
    }

    private static SolidColorBrush BrushFromHex(string hex, double opacity = 1.0)
    {
        var color = (Color)System.Windows.Media.ColorConverter.ConvertFromString(hex);
        color.A = (byte)Math.Clamp((int)Math.Round(opacity * 255), 0, 255);
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    private void FleetRightModuleOneActionButton_Click(object sender, RoutedEventArgs e)
    {
        if (FleetSubTabs?.SelectedItem == AllPlayersTab &&
            _membersPanelMode == MembersPanelMode.Member)
        {
            NavigateToFleetChatFromMemberPreview();
            return;
        }

        var key = GetCurrentFleetOrderKey();
        if (!string.IsNullOrWhiteSpace(key))
        {
            _acknowledgedFleetOrderKeys.Add(key);
        }

        RefreshFleetRightContextSidebar();
    }

    private int CountPendingFleetApplications()
    {
        return (_fleetApplicationSnapshots ?? [])
            .Count(application =>
                string.IsNullOrWhiteSpace(application.Status) ||
                application.Status.Equals("Pending", StringComparison.OrdinalIgnoreCase));
    }

    private string BuildCurrentTaskNotificationDetail()
    {
        var taskInfo = ParseFleetTaskBriefInfo(_fleetCurrentTaskBrief);
        var detail = FormatTaskBriefForDisplay(taskInfo);
        var condition = FormatTaskConditionSummary(taskInfo);
        if (!string.IsNullOrWhiteSpace(condition) &&
            !condition.Equals("按现场指挥", StringComparison.OrdinalIgnoreCase))
        {
            detail = $"{detail} / {condition}";
        }

        if (!string.IsNullOrWhiteSpace(_fleetCurrentTaskRally))
        {
            detail = string.IsNullOrWhiteSpace(detail)
                ? $"集结点：{_fleetCurrentTaskRally}"
                : $"{detail} / 集结点：{_fleetCurrentTaskRally}";
        }

        return string.IsNullOrWhiteSpace(detail) ? "点击查看任务详情。" : detail;
    }

    private static string TruncateNotificationText(string? value, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "";
        }

        var normalized = value.ReplaceLineEndings(" ").Trim();
        return normalized.Length <= maxLength
            ? normalized
            : normalized[..Math.Max(0, maxLength - 1)] + "…";
    }
}
