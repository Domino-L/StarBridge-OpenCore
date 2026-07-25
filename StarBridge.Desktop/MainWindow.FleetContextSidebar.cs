using Microsoft.Win32;
using StarBridge.Core.Events;
using StarBridge.Core.FleetChat;
using StarBridge.Core.Presence;
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
            FleetNotificationCenterSummaryText.Text = "加入或创建舰队后显示任务、计划和舰队动态。";
            _fleetNotificationCenterItems.Add(new FleetNotificationCenterItemRow(
                "入门",
                "尚未加入舰队",
                "寻找已有舰队，或创建自己的舰队。",
                "",
                "前往",
                "find-fleet",
                FindBrush("StatusInfoBrush", Brushes.DeepSkyBlue)));
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
                "前往管理舰队审核新成员。",
                "",
                "处理",
                "applications",
                FindBrush("StatusWarningBrush", Brushes.Orange));
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
                FindBrush("StatusInfoBrush", Brushes.DeepSkyBlue));
        }
        else if (CanCurrentUserPublishTasks())
        {
            AddItem(
                "当前任务",
                "暂无当前任务",
                "前往管理舰队发布任务或集结点。",
                "",
                "发布",
                "task-manage",
                FindBrush("StatusInfoBrush", Brushes.DeepSkyBlue));
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
                    ? FindBrush("StatusSuccessBrush", Brushes.MediumSpringGreen)
                    : FindBrush("StatusWarningBrush", Brushes.Orange));
        }
        else if (CanCurrentUserPublishPlans())
        {
            AddItem(
                "行动计划",
                "未来 7 天暂无计划",
                "前往管理舰队创建行动计划。",
                "",
                "创建",
                "plan-manage",
                FindBrush("StatusSuccessBrush", Brushes.MediumSpringGreen));
        }

        if (!string.IsNullOrWhiteSpace(_fleetNoticeTitle))
        {
            AddItem(
                "舰队公告",
                _fleetNoticeTitle,
                string.IsNullOrWhiteSpace(_fleetNoticeContent) ? "点击查看公告。" : _fleetNoticeContent,
                "",
                CanCurrentUserManageAnnouncements() ? "编辑" : "查看",
                "notice-detail",
                FindBrush("StatusInfoBrush", Brushes.Cyan));
        }
        else if (CanCurrentUserManageAnnouncements())
        {
            AddItem(
                "舰队公告",
                "暂无舰队公告",
                "发布公告后会同步给舰队成员，并保留在公告历史中。",
                "",
                "发布",
                "notice-edit",
                FindBrush("StatusInfoBrush", Brushes.Cyan));
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
                "舰队状态",
                "暂无新的舰队动态",
                "任务、公告、计划、申请和日志会在这里聚合。",
                "",
                "",
                "",
                FindBrush("StatusDisabledBrush", Brushes.LightSlateGray));
        }

        var activeCount = _fleetNotificationCenterItems.Count;
        FleetNotificationCenterSummaryText.Text = activeCount == 0
            ? "暂无待处理事项。"
            : $"{activeCount} 条舰队动态，点击卡片可跳转处理。";
    }

    private void RefreshFleetRightContextSidebar()
    {
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

        if (FleetSubTabs?.SelectedItem == AllPlayersTab)
        {
            if (_membersPanelMode == MembersPanelMode.Admin && CanUseMembersAdminView())
            {
                RenderCommanderSidebarContent();
            }
            else
            {
                _membersPanelMode = MembersPanelMode.Member;
                RenderMemberSidebarContent();
            }

            return;
        }

        var mode = GetFleetRightSidebarMode();
        switch (mode)
        {
            case FleetRightSidebarMode.Commander:
                RenderCommanderSidebarContent();
                break;
            case FleetRightSidebarMode.SquadLeader:
                RenderSquadLeaderSidebarContent();
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

        return GetCurrentUserCommandedSquad() is not null
            ? FleetRightSidebarMode.SquadLeader
            : FleetRightSidebarMode.Member;
    }

    private bool HasCurrentUserFleetAdministrationPermission()
    {
        return _hasFleet &&
               (IsCurrentUserFleetCommander() ||
                CanCurrentUserManageFleetInfo() ||
                CanCurrentUserRemoveMembers());
    }

    private SquadRow? GetCurrentUserCommandedSquad()
    {
        return _squads.FirstOrDefault(CanCurrentUserManageSquad);
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
        FleetRightModuleTwoPanel.Visibility = Visibility.Collapsed;
        FleetRightModuleTwoRow.Height = new GridLength(0);
        FleetRightModuleOneRow.Height = new GridLength(0.86, GridUnitType.Star);
        FleetRightModuleThreeRow.Height = new GridLength(1.42, GridUnitType.Star);
    }

    private void RenderFleetShipSidebarContent()
    {
        ApplyFleetShipSidebarLayout();

        var totalCount = _fleetShipInventory.Count;
        var schedulableShips = BuildSchedulableFleetShips();
        var flyableCount = schedulableShips.Length;
        var onlineShips = schedulableShips
            .Where(IsFleetShipOwnerOnline)
            .ToArray();
        var onlineFlyableCount = onlineShips.Length;
        var onlineOwnerCount = onlineShips
            .Select(ship => NormalizeLocalKey(ship.OwnerGameId))
            .Where(owner => owner != "unknown")
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Count();
        var primaryShip = onlineShips
            .OrderBy(ship => GetFleetShipSpecSortRank(ship.ShipSpec, largeFirst: true))
            .ThenByDescending(ship => ship.ShipPriceValue ?? 0m)
            .FirstOrDefault();

        SetRightSidebarModuleHeader(
            FleetRightModuleOneTitleText,
            FleetRightModuleOneBadge,
            FleetRightModuleOneBadgeText,
            "可调度舰船",
            $"{onlineFlyableCount.ToString(CultureInfo.InvariantCulture)}/{flyableCount.ToString(CultureInfo.InvariantCulture)}");

        if (totalCount == 0)
        {
            AddRightSidebarInfoRow(FleetRightModuleOneItems, "当前资产", "暂无舰船数据", "成员上传机库数据后将在这里显示。", "#91A5B5");
        }
        else if (primaryShip is null)
        {
            AddRightSidebarInfoRow(
                FleetRightModuleOneItems,
                "当前可调度",
                "暂无在线可飞舰船",
                $"在线持有人 {onlineOwnerCount.ToString(CultureInfo.InvariantCulture)} 人 / 全舰队 {totalCount.ToString(CultureInfo.InvariantCulture)} 艘",
                "#D9A23B");
        }
        else
        {
            AddRightSidebarInfoRow(
                FleetRightModuleOneItems,
                "首选出动",
                primaryShip.ShipName,
                $"{primaryShip.OwnerDisplay} / {primaryShip.ShipSpec} / {primaryShip.ShipRoleTag}",
                "#42CF7C");
        }

        foreach (var visual in FleetShipRoleVisuals)
        {
            AddFleetShipDispatchCategoryRow(
                visual.DisplayName,
                visual.Category,
                onlineShips,
                schedulableShips,
                visual.DispatchDescription,
                visual.ColorHex);
        }

        SetRightSidebarModuleHeader(
            FleetRightModuleThreeTitleText,
            null,
            null,
            "舰船动态",
            "");

        foreach (var activity in _fleetShipActivities
                     .OrderByDescending(activity => activity.Timestamp)
                     .ThenBy(activity => activity.ShipName, StringComparer.CurrentCultureIgnoreCase))
        {
            AddRightSidebarShipActivity(FleetRightModuleThreeItems, activity);
        }

        AddRightSidebarEmptyStateIfNeeded(FleetRightModuleThreeItems, "暂无舰船动态。");
    }

    private void SyncFleetShipActivities(
        IReadOnlyList<FleetShipInventoryRow> currentRows,
        bool suppressRemovalActivities = false)
    {
        var currentRowsByKey = currentRows
            .GroupBy(BuildFleetShipActivityKey, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First(), StringComparer.OrdinalIgnoreCase);

        if (!_fleetShipActivitySnapshotInitialized)
        {
            foreach (var row in currentRowsByKey.Values
                         .OrderBy(row => GetFleetShipImportedSortDate(row.FleetSharedAtText)))
            {
                var firstSharedAt = ParseFleetShipActivityTimestamp(row.FleetSharedAtText, DateTimeOffset.UtcNow);
                AddFleetShipActivity(row, isRemoval: false, ResolveFleetShipOwnerJoinedAt(row, firstSharedAt));
            }
        }
        else
        {
            var now = DateTimeOffset.UtcNow;
            foreach (var row in currentRowsByKey.Values
                         .Where(row => !_fleetShipActivitySnapshot.ContainsKey(BuildFleetShipActivityKey(row)))
                         .OrderBy(row => GetFleetShipImportedSortDate(row.FleetSharedAtText)))
            {
                var firstSharedAt = ParseFleetShipActivityTimestamp(row.FleetSharedAtText, now);
                AddFleetShipActivity(row, isRemoval: false, ResolveFleetShipOwnerJoinedAt(row, firstSharedAt));
            }

            foreach (var row in _fleetShipActivitySnapshot
                         .Where(pair => !currentRowsByKey.ContainsKey(pair.Key))
                         .Select(pair => pair.Value)
                         .OrderBy(row => row.ShipName, StringComparer.CurrentCultureIgnoreCase))
            {
                if (!suppressRemovalActivities)
                {
                    AddFleetShipActivity(row, isRemoval: true, now);
                }
            }
        }

        _fleetShipActivitySnapshot.Clear();
        foreach (var pair in currentRowsByKey)
        {
            _fleetShipActivitySnapshot[pair.Key] = pair.Value;
        }

        _fleetShipActivitySnapshotInitialized = true;
        if (_fleetShipActivities.Count > 80)
        {
            _fleetShipActivities.RemoveRange(80, _fleetShipActivities.Count - 80);
        }
    }

    private void AddFleetShipActivity(FleetShipInventoryRow ship, bool isRemoval, DateTimeOffset timestamp)
    {
        _fleetShipActivities.Insert(0, new FleetShipActivityRow(
            isRemoval ? "移出舰船" : "加入舰船",
            ship.ShipName,
            ship.OwnerDisplay,
            isRemoval ? "变更时间" : "加入舰队时间",
            timestamp.ToLocalTime().ToString("yyyy-MM-dd"),
            timestamp,
            isRemoval,
            IsFleetShipFlyable(ship)));
    }

    private DateTimeOffset ResolveFleetShipOwnerJoinedAt(
        FleetShipInventoryRow ship,
        DateTimeOffset fallback)
    {
        foreach (var key in new[]
                 {
                     BuildFleetMemberJoinIdentityKey("account", ship.OwnerAccountId),
                     BuildFleetMemberJoinIdentityKey("game", ship.OwnerGameId),
                     BuildFleetMemberJoinIdentityKey("callsign", ship.OwnerCallsign)
                 })
        {
            if (!string.IsNullOrWhiteSpace(key) &&
                _fleetMemberJoinedAtByIdentity.TryGetValue(key, out var joinedAt))
            {
                return joinedAt;
            }
        }

        if (IsLocalPlayer(ship.OwnerGameId) &&
            _fleetJoinedAtUtc != default &&
            _fleetJoinedAtUtc != DateTimeOffset.MinValue)
        {
            return _fleetJoinedAtUtc.ToUniversalTime();
        }

        return fallback;
    }

    private static string BuildFleetShipActivityKey(FleetShipInventoryRow ship)
    {
        return BuildFleetShipKey(ship.OwnerGameId, ship.ShipCode, ship.ShipInstanceId);
    }

    private static DateTimeOffset ParseFleetShipActivityTimestamp(string value, DateTimeOffset fallback)
    {
        var parsed = GetFleetShipImportedSortDate(value);
        return parsed == DateTime.MinValue
            ? fallback
            : new DateTimeOffset(parsed);
    }

    private void ResetFleetShipActivities()
    {
        _fleetShipActivities.Clear();
        _fleetShipActivitySnapshot.Clear();
        _fleetMemberJoinedAtByIdentity.Clear();
        _fleetShipActivitySnapshotInitialized = false;
    }

    private void AddFleetShipDispatchCategoryRow(
        string label,
        FleetShipRoleCategory category,
        IReadOnlyCollection<FleetShipInventoryRow> onlineShips,
        IReadOnlyCollection<FleetShipInventoryRow> schedulableShips,
        string detail,
        string accentHex)
    {
        var onlineCount = CountFleetShipsByRoleCategory(onlineShips, category);
        var totalCount = CountFleetShipsByRoleCategory(schedulableShips, category);
        AddRightSidebarInfoRow(
            FleetRightModuleOneItems,
            label,
            $"{onlineCount.ToString(CultureInfo.InvariantCulture)} / {totalCount.ToString(CultureInfo.InvariantCulture)} 艘",
            $"在线 / 全部 · {detail}",
            onlineCount > 0 ? accentHex : "#91A5B5");
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
        var unassignedCount = _players.Count(player => IsUnassignedSquad(player.SquadName));
        var unknownShipCount = _players.Count(player => IsUnknownValue(player.RawShip) || IsUnknownValue(player.Ship));
        var unknownLocationCount = _players.Count(player => IsUnknownLocation(player.RawLocation) || IsUnknownLocation(player.Location));
        var onlineCount = _players.Count(player => IsOnlineStatus(player.SharedOnlineStatusValue));
        var offlineCount = Math.Max(0, _players.Count - onlineCount);
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
        AddRightSidebarMetric(FleetRightModuleTwoItems, "在线成员", onlineCount.ToString(CultureInfo.InvariantCulture), "#42CF7C");
        AddRightSidebarMetric(FleetRightModuleTwoItems, "离线成员", offlineCount.ToString(CultureInfo.InvariantCulture), "#91A5B5");
        AddRightSidebarMetric(FleetRightModuleTwoItems, "未分配小队", unassignedCount.ToString(CultureInfo.InvariantCulture), unassignedCount > 0 ? "#D9A23B" : "#42CF7C");
        AddRightSidebarMetric(FleetRightModuleTwoItems, "飞船未知", unknownShipCount.ToString(CultureInfo.InvariantCulture), unknownShipCount > 0 ? "#D9A23B" : "#42CF7C");
        AddRightSidebarMetric(FleetRightModuleTwoItems, "位置未知", unknownLocationCount.ToString(CultureInfo.InvariantCulture), unknownLocationCount > 0 ? "#D9A23B" : "#42CF7C");
        AddRightSidebarMetric(FleetRightModuleTwoItems, "同步异常", syncIssueCount.ToString(CultureInfo.InvariantCulture), syncIssueCount > 0 ? "#D9A23B" : "#42CF7C");

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

        AddRightSidebarEmptyStateIfNeeded(FleetRightModuleThreeItems, "暂无舰队动态。");
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
            Foreground = CreateSolidBrush("#91A5B5"),
            FontFamily = new MediaFontFamily("Microsoft YaHei UI"),
            FontSize = 11,
            FontWeight = FontWeights.SemiBold,
            VerticalAlignment = VerticalAlignment.Center
        });

        header.Children.Add(new Border
        {
            Background = CreateSolidBrush("#0D1D29"),
            BorderBrush = CreateSolidBrush("#173447"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Padding = new Thickness(5, 0, 5, 1),
            Margin = new Thickness(6, 0, 0, 0),
            Child = new TextBlock
            {
                Text = count.ToString(CultureInfo.InvariantCulture),
                Foreground = CreateSolidBrush(count > 0 ? "#D9A23B" : "#637A89"),
                FontFamily = new MediaFontFamily("Segoe UI"),
                FontSize = 10.5,
                FontWeight = FontWeights.SemiBold
            }
        });

        FleetRightModuleOneItems.Children.Add(header);
    }

    private void AddRightSidebarPendingApplicationRow(FleetApplicationRow application)
    {
        var border = new Border
        {
            MinHeight = 44,
            Background = CreateSolidBrush("#0D1D29"),
            BorderBrush = CreateSolidBrush("#173447"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Padding = new Thickness(7, 5, 7, 5),
            Margin = new Thickness(0, 0, 0, 5),
            SnapsToDevicePixels = true
        };

        border.MouseEnter += (_, _) =>
        {
            border.Background = CreateSolidBrush("#102737");
            border.BorderBrush = CreateSolidBrush("#25536C");
        };
        border.MouseLeave += (_, _) =>
        {
            border.Background = CreateSolidBrush("#0D1D29");
            border.BorderBrush = CreateSolidBrush("#173447");
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
            Foreground = CreateSolidBrush("#E6F1F8"),
            FontFamily = new MediaFontFamily("Microsoft YaHei UI"),
            FontSize = 12,
            FontWeight = FontWeights.SemiBold,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        identity.Children.Add(new TextBlock
        {
            Text = "申请加入舰队",
            Foreground = CreateSolidBrush("#637A89"),
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
            Foreground = CreateSolidBrush("#91A5B5"),
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
            Background = CreateSolidBrush("#0A1823"),
            BorderBrush = CreateSolidBrush("#28506A"),
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
            frame.Child = CreateIdentityBeaconAvatarPlaceholder(CreateSolidBrush("#63C7FF"));
        }

        return frame;
    }

    private void AddRightSidebarPendingApplicationMoreHint(int remainingCount)
    {
        var border = new Border
        {
            Background = CreateSolidBrush("#081722"),
            BorderBrush = CreateSolidBrush("#142B39"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Padding = new Thickness(8, 4, 8, 4),
            Margin = new Thickness(0, 0, 0, 4),
            SnapsToDevicePixels = true
        };

        border.Child = new TextBlock
        {
            Text = $"还有 {remainingCount.ToString(CultureInfo.InvariantCulture)} 条待审核申请，点击全部查看",
            Foreground = CreateSolidBrush("#637A89"),
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
            Background = CreateSolidBrush("#0C1D29"),
            BorderBrush = CreateSolidBrush("#28506A"),
            Foreground = CreateSolidBrush("#D5E5EF")
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

        var hoverBorder = approve ? "#42CF7C" : "#F15B65";
        button.MouseEnter += (_, _) =>
        {
            button.Background = CreateSolidBrush("#102737");
            button.BorderBrush = CreateSolidBrush(hoverBorder);
            button.Foreground = CreateSolidBrush("#FFFFFF");
        };
        button.MouseLeave += (_, _) =>
        {
            button.Background = CreateSolidBrush("#0C1D29");
            button.BorderBrush = CreateSolidBrush("#28506A");
            button.Foreground = CreateSolidBrush("#D5E5EF");
        };
        button.PreviewMouseDown += (_, _) =>
        {
            button.Background = CreateSolidBrush("#091721");
            button.BorderBrush = CreateSolidBrush("#28617E");
        };
        button.PreviewMouseUp += (_, _) =>
        {
            button.Background = CreateSolidBrush("#102737");
            button.BorderBrush = CreateSolidBrush(hoverBorder);
        };

        return button;
    }

    private void AddRightSidebarPendingApplicationEmptyState()
    {
        var border = new Border
        {
            Background = CreateSolidBrush("#0D1D29"),
            BorderBrush = CreateSolidBrush("#173447"),
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
            Foreground = CreateSolidBrush("#C8D8E2"),
            FontFamily = new MediaFontFamily("Microsoft YaHei UI"),
            FontSize = 12,
            FontWeight = FontWeights.SemiBold
        });
        stack.Children.Add(new TextBlock
        {
            Text = "所有加入申请均已处理",
            Foreground = CreateSolidBrush("#637A89"),
            FontFamily = new MediaFontFamily("Microsoft YaHei UI"),
            FontSize = 10.5,
            Margin = new Thickness(0, 3, 0, 0)
        });

        border.Child = stack;
        FleetRightModuleOneItems.Children.Add(border);
    }

    private void RenderMemberSidebarContent()
    {
        var local = GetLocalPlayerRow();
        var fleetChannel = _fleetChatChannels.FirstOrDefault(channel =>
            channel.Type == StarBridge.Core.FleetChat.FleetChatChannelTypes.Fleet);

        SetRightSidebarModuleHeader(
            FleetRightModuleOneTitleText,
            FleetRightModuleOneBadge,
            FleetRightModuleOneBadgeText,
            "舰队通讯",
            fleetChannel is { UnreadCount: > 0 }
                ? $"{fleetChannel.UnreadText} 未读"
                : "最新");

        foreach (var message in _fleetMemberSidebarChatPreview)
        {
            AddRightSidebarChatPreviewRow(FleetRightModuleOneItems, message);
        }

        if (_fleetMemberSidebarChatPreview.Count == 0)
        {
            AddRightSidebarInfoRow(
                FleetRightModuleOneItems,
                "暂无舰队消息",
                _fleetMemberSidebarChatPreviewLoaded ? "频道暂时安静" : "正在获取最新通讯",
                "新消息会在这里显示，不会自动标记为已读。",
                "#91A5B5");
        }

        FleetRightModuleOneActionButton.Content = "进入舰队通讯";
        FleetRightModuleOneActionButton.Visibility = Visibility.Visible;
        if (!_fleetMemberSidebarChatPreviewLoaded)
        {
            _ = RefreshFleetMemberSidebarChatPreviewAsync();
        }

        SetRightSidebarModuleHeader(
            FleetRightModuleTwoTitleText,
            FleetRightModuleTwoBadge,
            FleetRightModuleTwoBadgeText,
            "我的状态",
            local?.Status.Equals("Online", StringComparison.OrdinalIgnoreCase) == true ? "在线" : "离线");
        FleetRightModuleTwoItems.Margin = new Thickness(0, 8, 0, 0);
        AddRightSidebarStatusMetric(FleetRightModuleTwoItems, "我的角色", GetCurrentUserRoleTitle(), "#29AFFF");
        AddRightSidebarStatusMetric(FleetRightModuleTwoItems, "我的小队", _joinedSquad?.Name ?? "未加入", _joinedSquad is null ? "#D9A23B" : "#42CF7C");
        AddRightSidebarStatusMetric(FleetRightModuleTwoItems, "当前飞船", NormalizeOptionalDisplay(local?.Ship, "Unknown"), IsUnknownValue(local?.Ship) ? "#D9A23B" : "#E6F1F8");
        AddRightSidebarStatusMetric(FleetRightModuleTwoItems, "当前位置", NormalizeOptionalDisplay(local?.Location, "地点：未知星域"), IsUnknownLocation(local?.Location) ? "#D9A23B" : "#E6F1F8");
        AddRightSidebarStatusMetric(FleetRightModuleTwoItems, "服务器区域", GetGameServerRegionDisplay(), GetGameServerRegionAccent());
        AddRightSidebarStatusMetric(FleetRightModuleTwoItems, "同步状态", GetNetworkSyncStatusText(), _isNetworkSyncRunning ? "#D9A23B" : IsLoggedIn ? "#42CF7C" : "#91A5B5");
        AddRightSidebarStatusMetric(FleetRightModuleTwoItems, "游戏浮层", _overlayWindow?.IsVisible == true ? "已开启" : "未开启", _overlayWindow?.IsVisible == true ? "#42CF7C" : "#91A5B5");

        SetRightSidebarModuleHeader(
            FleetRightModuleThreeTitleText,
            null,
            null,
            "舰队动态",
            "");
        foreach (var log in GetMemberVisibleFleetActivity())
        {
            AddRightSidebarActivity(FleetRightModuleThreeItems, SanitizeFleetEventText(log.Title), log.Timestamp.ToLocalTime().ToString("MM-dd HH:mm"), log.AccentBrush);
        }

        AddRightSidebarEmptyStateIfNeeded(FleetRightModuleThreeItems, "暂无普通成员可见动态。");
    }

    private void AddRightSidebarChatPreviewRow(
        System.Windows.Controls.Panel panel,
        FleetChatMessageRow message)
    {
        var row = new Border
        {
            Background = Brushes.Transparent,
            BorderBrush = CreateSolidBrush("#173447"),
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
            Foreground = CreateSolidBrush("#637A89"),
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
            Foreground = CreateSolidBrush("#C8D8E2"),
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
            Foreground = foreground ?? CreateSolidBrush("#79CFF4")
        };
        if (TryFindResource("IdentityBeaconAvatarPlaceholderStyle") is Style placeholderStyle)
        {
            placeholder.Style = placeholderStyle;
        }

        return placeholder;
    }

    private void RenderSquadLeaderSidebarContent()
    {
        var squad = GetCurrentUserCommandedSquad();
        var squadMembers = squad is null
            ? []
            : _players.Where(player => player.SquadName.Equals(squad.Name, StringComparison.OrdinalIgnoreCase)).ToList();
        var onlineCount = squadMembers.Count(player => IsOnlineStatus(player.SharedOnlineStatusValue));
        var offlineCount = Math.Max(0, squadMembers.Count - onlineCount);
        var unknownShipCount = squadMembers.Count(player => IsUnknownValue(player.RawShip) || IsUnknownValue(player.Ship));
        var unknownLocationCount = squadMembers.Count(player => IsUnknownLocation(player.RawLocation) || IsUnknownLocation(player.Location));

        SetRightSidebarModuleHeader(
            FleetRightModuleOneTitleText,
            FleetRightModuleOneBadge,
            FleetRightModuleOneBadgeText,
            "小队指令",
            squad is null ? "等待" : squad.Name);
        AddRightSidebarInfoRow(FleetRightModuleOneItems, "当前小队任务", GetSquadMissionText(squad), GetSquadRallyText(squad), "#29AFFF");
        AddRightSidebarInfoRow(FleetRightModuleOneItems, "小队集结点", squad?.RallyPoint ?? "未指定", "以小队长发布的信息为准", "#D9A23B");
        AddRightSidebarInfoRow(FleetRightModuleOneItems, "需要确认的队员", "0 人", "暂无队员确认队列", "#42CF7C");

        SetRightSidebarModuleHeader(
            FleetRightModuleTwoTitleText,
            FleetRightModuleTwoBadge,
            FleetRightModuleTwoBadgeText,
            "小队态势",
            squadMembers.Count.ToString(CultureInfo.InvariantCulture));
        AddRightSidebarMetric(FleetRightModuleTwoItems, "小队在线", onlineCount.ToString(CultureInfo.InvariantCulture), "#42CF7C");
        AddRightSidebarMetric(FleetRightModuleTwoItems, "小队离线", offlineCount.ToString(CultureInfo.InvariantCulture), "#91A5B5");
        AddRightSidebarMetric(FleetRightModuleTwoItems, "飞船未知", unknownShipCount.ToString(CultureInfo.InvariantCulture), unknownShipCount > 0 ? "#D9A23B" : "#42CF7C");
        AddRightSidebarMetric(FleetRightModuleTwoItems, "位置未知", unknownLocationCount.ToString(CultureInfo.InvariantCulture), unknownLocationCount > 0 ? "#D9A23B" : "#42CF7C");

        SetRightSidebarModuleHeader(
            FleetRightModuleThreeTitleText,
            null,
            null,
            "小队动态",
            "");
        foreach (var item in BuildSquadLeaderActivityRows(squad, squadMembers))
        {
            AddRightSidebarActivity(FleetRightModuleThreeItems, item.Title, item.Meta, item.Brush);
        }

        AddRightSidebarEmptyStateIfNeeded(FleetRightModuleThreeItems, "暂无小队动态。");
    }

    private void SetRightSidebarModuleHeader(TextBlock title, Border? badge, TextBlock? badgeText, string titleText, string badgeValue)
    {
        title.Text = titleText;
        if (badge is null || badgeText is null)
        {
            return;
        }

        badgeText.Text = badgeValue;
        badge.Visibility = string.IsNullOrWhiteSpace(badgeValue) ? Visibility.Collapsed : Visibility.Visible;
    }

    private void AddRightSidebarInfoRow(System.Windows.Controls.Panel panel, string label, string value, string detail, string accentHex)
    {
        var border = new Border
        {
            Background = CreateSolidBrush("#0D1D29"),
            BorderBrush = CreateSolidBrush("#173447"),
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
            Fill = CreateSolidBrush(accentHex),
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
            Foreground = CreateSolidBrush("#91A5B5"),
            FontSize = 10.5,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        stack.Children.Add(new TextBlock
        {
            Text = value,
            Foreground = CreateSolidBrush("#E6F1F8"),
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

    private void AddRightSidebarMetric(System.Windows.Controls.Panel panel, string label, string value, string accentHex)
    {
        var border = new Border
        {
            Background = CreateSolidBrush("#0D1D29"),
            BorderBrush = CreateSolidBrush("#173447"),
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
            Foreground = CreateSolidBrush("#91A5B5"),
            FontSize = 10,
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        Grid.SetColumn(labelText, 0);
        grid.Children.Add(labelText);

        var valueText = new TextBlock
        {
            Text = value,
            Foreground = CreateSolidBrush(accentHex),
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

    private void AddRightSidebarStatusMetric(System.Windows.Controls.Panel panel, string label, string value, string accentHex)
    {
        var border = new Border
        {
            Background = CreateSolidBrush("#0D1D29"),
            BorderBrush = CreateSolidBrush("#173447"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Padding = new Thickness(6, 2, 6, 2),
            Margin = new Thickness(0, 0, 4, 3),
            MinHeight = 21,
            ToolTip = $"{label} / {value}"
        };

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(58) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var labelText = new TextBlock
        {
            Text = label,
            Foreground = CreateSolidBrush("#7A8E9B"),
            FontSize = 9.5,
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        Grid.SetColumn(labelText, 0);
        grid.Children.Add(labelText);

        var valueText = new TextBlock
        {
            Text = value,
            Foreground = CreateSolidBrush(accentHex),
            FontSize = 10.5,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(5, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            TextAlignment = TextAlignment.Right,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        Grid.SetColumn(valueText, 1);
        grid.Children.Add(valueText);

        border.Child = grid;
        panel.Children.Add(border);
    }

    private void AddRightSidebarActivity(System.Windows.Controls.Panel panel, string title, string timeText, System.Windows.Media.Brush accentBrush)
    {
        var grid = new Grid { Margin = new Thickness(0, 0, 0, 7) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(10) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var marker = new System.Windows.Shapes.Ellipse
        {
            Width = 5,
            Height = 5,
            Fill = accentBrush,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(marker, 0);
        grid.Children.Add(marker);

        var titleText = new TextBlock
        {
            Text = title,
            Foreground = CreateSolidBrush("#E6F1F8"),
            FontSize = 11,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        Grid.SetColumn(titleText, 1);
        grid.Children.Add(titleText);

        var time = new TextBlock
        {
            Text = timeText,
            Foreground = CreateSolidBrush("#91A5B5"),
            FontSize = 10.5,
            Margin = new Thickness(8, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(time, 2);
        grid.Children.Add(time);

        panel.Children.Add(grid);
    }

    private void AddRightSidebarShipActivity(System.Windows.Controls.Panel panel, FleetShipActivityRow activity)
    {
        var border = new Border
        {
            Background = CreateSolidBrush("#0D1D29"),
            BorderBrush = CreateSolidBrush("#173447"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Padding = new Thickness(8, 6, 8, 6),
            Margin = new Thickness(0, 0, 0, 6),
            MinHeight = 56,
            SnapsToDevicePixels = true
        };

        border.MouseEnter += (_, _) =>
        {
            border.Background = CreateSolidBrush("#102737");
            border.BorderBrush = CreateSolidBrush("#25536C");
        };
        border.MouseLeave += (_, _) =>
        {
            border.Background = CreateSolidBrush("#0D1D29");
            border.BorderBrush = CreateSolidBrush("#173447");
        };

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(9) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(78) });

        var marker = new System.Windows.Shapes.Rectangle
        {
            Width = 3,
            RadiusX = 1,
            RadiusY = 1,
            Fill = activity.IsRemoval
                ? CreateSolidBrush("#F15B65")
                : activity.IsFlyable
                    ? CreateSolidBrush("#42CF7C")
                    : CreateSolidBrush("#9A70E8"),
            VerticalAlignment = VerticalAlignment.Stretch,
            Margin = new Thickness(0, 2, 0, 2)
        };
        Grid.SetColumn(marker, 0);
        grid.Children.Add(marker);

        var info = new StackPanel
        {
            Margin = new Thickness(4, 0, 8, 0),
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(info, 1);

        info.Children.Add(new TextBlock
        {
            Text = $"{activity.Action}  {activity.ShipName}",
            Foreground = CreateSolidBrush("#E6F1F8"),
            FontFamily = new MediaFontFamily("Microsoft YaHei UI"),
            FontSize = 11.5,
            FontWeight = FontWeights.SemiBold,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        info.Children.Add(new TextBlock
        {
            Text = $"持有人  {activity.OwnerDisplay}",
            Foreground = CreateSolidBrush("#91A5B5"),
            FontFamily = new MediaFontFamily("Microsoft YaHei UI"),
            FontSize = 10.5,
            Margin = new Thickness(0, 3, 0, 0),
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        grid.Children.Add(info);

        var time = new StackPanel
        {
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(time, 2);
        time.Children.Add(new TextBlock
        {
            Text = activity.TimeLabel,
            Foreground = CreateSolidBrush("#637A89"),
            FontFamily = new MediaFontFamily("Microsoft YaHei UI"),
            FontSize = 9.5,
            HorizontalAlignment = HorizontalAlignment.Right
        });
        time.Children.Add(new TextBlock
        {
            Text = activity.TimeText,
            Foreground = CreateSolidBrush("#D7E6F0"),
            FontFamily = new MediaFontFamily("Segoe UI"),
            FontSize = 10.5,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 3, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Right
        });
        grid.Children.Add(time);

        border.Child = grid;
        panel.Children.Add(border);
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

    private static DateTime GetFleetShipImportedSortDate(string value)
    {
        return DateTime.TryParse(value, CultureInfo.CurrentCulture, DateTimeStyles.AssumeLocal, out var date) ||
               DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.AssumeLocal, out date)
            ? date
            : DateTime.MinValue;
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
            Foreground = CreateSolidBrush("#91A5B5"),
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
               text.Contains("上线", StringComparison.OrdinalIgnoreCase) ||
               text.Contains("离线", StringComparison.OrdinalIgnoreCase) ||
               text.Contains("小队", StringComparison.OrdinalIgnoreCase) ||
               text.Contains("计划", StringComparison.OrdinalIgnoreCase);
    }

    private IEnumerable<(string Title, string Meta, System.Windows.Media.Brush Brush)> BuildSquadLeaderActivityRows(
        SquadRow? squad,
        IReadOnlyCollection<PlayerRow> squadMembers)
    {
        if (squad is not null)
        {
            yield return ($"小队任务 / {GetSquadMissionText(squad)}", squad.UpdatedAt.ToLocalTime().ToString("MM-dd HH:mm"), FindBrush("StatusInfoBrush", Brushes.DeepSkyBlue));
        }

        foreach (var player in squadMembers.OrderByDescending(player => IsOnlineStatus(player.SharedOnlineStatusValue)).ThenBy(player => player.Name).Take(4))
        {
            var status = IsOnlineStatus(player.SharedOnlineStatusValue) ? "在线" : "离线";
            yield return ($"{DisplayCallsign(player.Callsign, player.Name)} / {status}", player.SharedShipText, IsOnlineStatus(player.SharedOnlineStatusValue)
                ? FindBrush("StatusSuccessBrush", Brushes.MediumSpringGreen)
                : FindBrush("StatusDisabledBrush", Brushes.LightSlateGray));
        }
    }

    private PlayerRow? GetLocalPlayerRow()
    {
        return _players.FirstOrDefault(player => IsLocalPlayerIdentity(player.Name, player.Callsign));
    }

    private string GetCurrentUserRoleTitle()
    {
        if (IsCurrentUserFleetCommander())
        {
            return "舰队指挥官";
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

    private string GetSquadMissionText(SquadRow? squad)
    {
        if (squad is null || string.IsNullOrWhiteSpace(squad.Mission) || squad.Mission.Equals("Standby", StringComparison.OrdinalIgnoreCase))
        {
            return "暂无小队任务";
        }

        return squad.Mission;
    }

    private string GetSquadRallyText(SquadRow? squad)
    {
        if (squad is null || string.IsNullOrWhiteSpace(squad.RallyPoint) || squad.RallyPoint.Equals("Use Global", StringComparison.OrdinalIgnoreCase))
        {
            return "集结点 / 跟随舰队";
        }

        return $"集结点 / {squad.RallyPoint}";
    }

    private string GetGameServerRegionDisplay()
    {
        if (IsGameServerRegionCurrent())
        {
            return _gameServerRegion;
        }

        return _isGameProcessRunning ? "等待确认" : "仅游戏中显示";
    }

    private string GetGameServerRegionAccent()
    {
        return IsGameServerRegionCurrent() ? "#42CF7C" : "#91A5B5";
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

        return NetworkAutoSyncCheck?.IsChecked == true ? "自动同步" : "已连接";
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

    private static bool IsUnassignedSquad(string? squadName)
    {
        return string.IsNullOrWhiteSpace(squadName) ||
               squadName.Equals("Unassigned", StringComparison.OrdinalIgnoreCase) ||
               squadName.Equals("未分配", StringComparison.OrdinalIgnoreCase);
    }

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
