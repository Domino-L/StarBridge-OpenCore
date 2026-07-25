using Microsoft.Win32;
using StarBridge.Core.Events;
using StarBridge.Core.FleetChat;
using StarBridge.Core.LogWatching;
using StarBridge.Core.Parsing;
using StarBridge.Core.Presence;
using StarBridge.Core.Profiles;
using StarBridge.Core.State;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void RefreshFleetDirectoryViewState()
    {
        var status = _fleetDirectoryState.LoadStatus;
        var showStatus = status is FleetDirectoryLoadStatus.OfflineCache or
            FleetDirectoryLoadStatus.Error;

        if (FindFleetDirectoryStatusPanel is not null)
        {
            FindFleetDirectoryStatusPanel.Visibility = showStatus
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (FindFleetDirectoryStatusText is not null)
        {
            FindFleetDirectoryStatusText.Text = _fleetDirectoryState.StatusMessage;
            FindFleetDirectoryStatusText.Foreground = status switch
            {
                FleetDirectoryLoadStatus.Error => BrushFromHex("#F15B65"),
                FleetDirectoryLoadStatus.OfflineCache => BrushFromHex("#D9A23B"),
                _ => BrushFromHex("#29AFFF")
            };
        }

        if (FindFleetDirectoryStatusDot is not null)
        {
            FindFleetDirectoryStatusDot.Fill = status switch
            {
                FleetDirectoryLoadStatus.Error => BrushFromHex("#F15B65"),
                FleetDirectoryLoadStatus.OfflineCache => BrushFromHex("#D9A23B"),
                _ => BrushFromHex("#29AFFF")
            };
        }

        if (FindFleetDirectoryRetryButton is not null)
        {
            FindFleetDirectoryRetryButton.Visibility = status is FleetDirectoryLoadStatus.OfflineCache or FleetDirectoryLoadStatus.Error
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (RefreshFleetDirectoryButton is not null)
        {
            var isLoading = status is FleetDirectoryLoadStatus.Loading or FleetDirectoryLoadStatus.Refreshing;
            RefreshFleetDirectoryButton.IsEnabled = !isLoading;
            RefreshFleetDirectoryButton.Content = isLoading ? "正在刷新" : "刷新舰队";
            RefreshFleetDirectoryButton.Opacity = isLoading ? 0.66 : 1;
        }
    }

    private async void FindFleetDirectoryRetryButton_Click(object sender, RoutedEventArgs e)
    {
        await PullNetworkFleetsAsync();
    }

    private void ApplyFleetSearchFilter(IReadOnlyList<string>? preservedVisibleOrder = null)
    {
        if (FindFleetSearchBox is null)
        {
            return;
        }

        var query = FindFleetSearchBox.Text.Trim();
        var hasAdvancedFilters = HasFindFleetAdvancedFilters();
        var scored = _allNetworkFleets
            .Select(ApplyCurrentFleetBannerFallback)
            .Select(DecorateFleetDirectoryTags)
            .Select(card => card with { SearchScore = CalculateFleetSearchScore(card, query) })
            .Where(card => string.IsNullOrWhiteSpace(query) || card.SearchScore > 0)
            .Where(PassesFindFleetAdvancedFilters);

        var sortedMatches = ApplyFindFleetSort(scored).ToArray();
        var matches = preservedVisibleOrder is { Count: > 0 }
            ? FleetPassiveRefreshPolicy.PreserveVisibleOrder(
                sortedMatches,
                preservedVisibleOrder,
                card => card.Snapshot.Code)
            : sortedMatches;

        _networkFleets.Clear();
        foreach (var card in matches)
        {
            _networkFleets.Add(card);
        }

        if (FindFleetSearchCountText is not null)
        {
            FindFleetSearchCountText.Text = string.IsNullOrWhiteSpace(query)
                ? hasAdvancedFilters ? $"筛选 {_networkFleets.Count}" : $"{_networkFleets.Count} 个舰队"
                : $"匹配 {_networkFleets.Count}";
        }

        if (FindFleetEmptyText is not null)
        {
            var canShowEmpty = _fleetDirectoryState.LoadStatus is not FleetDirectoryLoadStatus.Loading and
                not FleetDirectoryLoadStatus.Refreshing and
                not FleetDirectoryLoadStatus.Error;
            FindFleetEmptyText.Visibility = canShowEmpty && _networkFleets.Count == 0
                ? Visibility.Visible
                : Visibility.Collapsed;
            FindFleetEmptyText.Text = string.IsNullOrWhiteSpace(query)
                ? hasAdvancedFilters
                    ? "没有符合筛选条件的舰队。可以重置筛选或稍后刷新目录。"
                    : "暂无公开舰队。你可以创建舰队，或稍后刷新目录。"
                : "没有找到匹配的舰队。请尝试舰队全名、识别码或标签。";
        }

        RefreshFindFleetDetailSelection();
    }

    private IOrderedEnumerable<NetworkFleetCard> ApplyFindFleetSort(IEnumerable<NetworkFleetCard> cards)
    {
        return _fleetDirectoryState.SortMode switch
        {
            FleetDirectorySortMode.RecentlyActive => cards
                .OrderByDescending(card => card.Snapshot.LastUpdated)
                .ThenBy(card => card.Name, StringComparer.OrdinalIgnoreCase),
            FleetDirectorySortMode.MemberCount => cards
                .OrderByDescending(card => card.Snapshot.TotalMembers)
                .ThenByDescending(card => card.Snapshot.RecruitingEnabled)
                .ThenBy(card => card.Name, StringComparer.OrdinalIgnoreCase),
            FleetDirectorySortMode.Name => cards
                .OrderBy(card => card.Name, StringComparer.OrdinalIgnoreCase),
            _ => cards
                .OrderByDescending(card => card.SearchScore)
                .ThenByDescending(card => card.Snapshot.RecruitingEnabled)
                .ThenByDescending(card => card.Snapshot.OnlineMembers)
                .ThenByDescending(card => card.Snapshot.LastUpdated)
                .ThenBy(card => card.Name, StringComparer.OrdinalIgnoreCase)
        };
    }

    private static bool IsChecked(System.Windows.Controls.CheckBox? checkBox) => checkBox?.IsChecked == true;

    private bool HasFindFleetAdvancedFilters() => _fleetDirectoryState.AppliedFilters.HasAny;

    private bool PassesFindFleetAdvancedFilters(NetworkFleetCard card)
    {
        var filters = _fleetDirectoryState.AppliedFilters;
        if (filters.Recruiting && !card.Snapshot.RecruitingEnabled)
        {
            return false;
        }

        if (filters.RecruitingTargets.Count > 0 &&
            (!card.Snapshot.RecruitingEnabled ||
             !filters.RecruitingTargets.Contains(
                 NormalizeFleetRecruitingTarget(card.Snapshot.RecruitingTarget),
                 StringComparer.OrdinalIgnoreCase)))
        {
            return false;
        }

        if (filters.ActivityCadences.Count > 0 &&
            !filters.ActivityCadences.Contains(
                NormalizeManageProfileOption(card.Snapshot.ActivityCadence, "休闲"),
                StringComparer.OrdinalIgnoreCase))
        {
            return false;
        }

        var openJoinOnly = filters.OpenJoin;
        var applicationOnly = filters.Application;
        var inviteOnly = filters.InviteOnly;
        if (openJoinOnly || applicationOnly || inviteOnly)
        {
            var matchesJoinMode =
                openJoinOnly && !card.RequiresApplication && !card.IsInviteOnly ||
                applicationOnly && card.RequiresApplication ||
                inviteOnly && card.IsInviteOnly;
            if (!matchesJoinMode)
            {
                return false;
            }
        }

        if (filters.Pending && !card.HasPendingApplication)
        {
            return false;
        }

        if (!PassesFindFleetScaleFilters(card))
        {
            return false;
        }

        if (filters.HasShips &&
            (Math.Max(card.Snapshot.PublicShipCount, card.Snapshot.Ships?.Length ?? 0) == 0 ||
             string.Equals(card.Snapshot.PublicShipScaleMode, "Hidden", StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }

        if (!PassesFindFleetShipFilters(card.Snapshot))
        {
            return false;
        }

        if (!PassesFindFleetActivityFilters(card.Snapshot))
        {
            return false;
        }

        if (!PassesFindFleetTagFilters(card))
        {
            return false;
        }

        if (filters.SystemIds.Count > 0 &&
            !filters.SystemIds.Any(required =>
                (card.Snapshot.ActiveSystemIds ?? []).Contains(required, StringComparer.OrdinalIgnoreCase)))
        {
            return false;
        }

        return true;
    }

    private bool PassesFindFleetScaleFilters(NetworkFleetCard card)
    {
        var filters = _fleetDirectoryState.AppliedFilters;
        var small = filters.ScaleSmall;
        var medium = filters.ScaleMedium;
        var large = filters.ScaleLarge;
        var veryLarge = filters.ScaleVeryLarge;
        if (!small && !medium && !large && !veryLarge)
        {
            return true;
        }

        var totalMembers = card.Snapshot.TotalMembers;
        return small && totalMembers <= 10 ||
               medium && totalMembers is > 10 and <= 50 ||
               large && totalMembers is > 50 and < 300 ||
               veryLarge && totalMembers >= 300;
    }

    private bool PassesFindFleetActivityFilters(NetworkFleetSnapshot snapshot)
    {
        var filters = _fleetDirectoryState.AppliedFilters;
        var hasPeriodFilter = filters.ActiveEarlyMorning || filters.ActiveMorning ||
                              filters.ActiveAfternoon || filters.ActiveEvening;
        var hasDayFilter = filters.ActivityDayIds.Count > 0;
        if (!filters.SameTimeZone && !hasPeriodFilter && !hasDayFilter)
        {
            return true;
        }

        if (!snapshot.PublicShowActivityTime)
        {
            return false;
        }

        if (filters.SameTimeZone || hasPeriodFilter)
        {
            if (string.IsNullOrWhiteSpace(snapshot.TimeZoneId))
            {
                return false;
            }

            try
            {
                var now = DateTimeOffset.UtcNow;
                var fleetZone = TimeZoneInfo.FindSystemTimeZoneById(snapshot.TimeZoneId);
                if (fleetZone.GetUtcOffset(now) != TimeZoneInfo.Local.GetUtcOffset(now))
                {
                    return false;
                }
            }
            catch (TimeZoneNotFoundException)
            {
                return false;
            }
            catch (InvalidTimeZoneException)
            {
                return false;
            }
        }

        if (!hasPeriodFilter)
        {
            return PassesFindFleetActivityDayFilters(snapshot, filters.ActivityDayIds);
        }

        var periods = new List<(int Start, int End)>();
        AddPeriod(filters.ActiveEarlyMorning, 0, 6 * 60);
        AddPeriod(filters.ActiveMorning, 6 * 60, 12 * 60);
        AddPeriod(filters.ActiveAfternoon, 12 * 60, 18 * 60);
        AddPeriod(filters.ActiveEvening, 18 * 60, 24 * 60);

        return PassesFindFleetActivityDayFilters(snapshot, filters.ActivityDayIds) &&
               (snapshot.ActivityWindows ?? [])
               .Any(window => ActivityWindowOverlapsAnyPeriod(window, periods));

        void AddPeriod(bool include, int start, int end)
        {
            if (include)
            {
                periods.Add((start, end));
            }
        }
    }

    private static bool PassesFindFleetActivityDayFilters(
        NetworkFleetSnapshot snapshot,
        IReadOnlyList<string> requiredDays)
    {
        if (requiredDays.Count == 0)
        {
            return true;
        }

        return (snapshot.ActivityWindows ?? []).Any(window =>
            (window.Days ?? []).Any(day => requiredDays.Contains(day, StringComparer.OrdinalIgnoreCase)));
    }

    private bool PassesFindFleetShipFilters(NetworkFleetSnapshot snapshot)
    {
        var filters = _fleetDirectoryState.AppliedFilters;
        var hasCountFilter = filters.ShipCountSmall || filters.ShipCountMedium ||
                             filters.ShipCountLarge || filters.ShipCountVeryLarge;
        if (hasCountFilter)
        {
            if (string.Equals(snapshot.PublicShipScaleMode, FleetPublicShipScaleHidden, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            var count = Math.Max(snapshot.PublicShipCount, snapshot.Ships?.Length ?? 0);
            var countMatches = filters.ShipCountSmall && count is >= 1 and <= 10 ||
                               filters.ShipCountMedium && count is >= 11 and <= 30 ||
                               filters.ShipCountLarge && count is >= 31 and < 100 ||
                               filters.ShipCountVeryLarge && count >= 100;
            if (!countMatches)
            {
                return false;
            }
        }

        if (filters.ShipRoleIds.Count == 0)
        {
            return true;
        }

        if (!string.Equals(
                NormalizeFleetPublicShipScaleMode(snapshot.PublicShipScaleMode),
                FleetPublicShipScaleTypeSummary,
                StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var counts = ParsePublicShipTypeSummary(snapshot.PublicShipTypeSummary);
        return filters.ShipRoleIds.Any(roleId => counts.GetValueOrDefault(roleId) > 0);
    }

    private static bool ActivityWindowOverlapsAnyPeriod(
        NetworkFleetActivityWindowSnapshot window,
        IReadOnlyList<(int Start, int End)> periods)
    {
        if (!TimeSpan.TryParse(window.StartTime, CultureInfo.InvariantCulture, out var startTime) ||
            !TimeSpan.TryParse(window.EndTime, CultureInfo.InvariantCulture, out var endTime))
        {
            return false;
        }

        var start = Math.Clamp((int)startTime.TotalMinutes, 0, 1439);
        var end = Math.Clamp((int)endTime.TotalMinutes, 0, 1440);
        if (start == end)
        {
            return true;
        }

        if (window.EndsNextDay || end < start)
        {
            return periods.Any(period =>
                IntervalsOverlap(start, 1440, period.Start, period.End) ||
                IntervalsOverlap(0, end, period.Start, period.End));
        }

        return periods.Any(period => IntervalsOverlap(start, end, period.Start, period.End));
    }

    private static bool IntervalsOverlap(int firstStart, int firstEnd, int secondStart, int secondEnd) =>
        firstStart < secondEnd && secondStart < firstEnd;

    private bool PassesFindFleetTagFilters(NetworkFleetCard card)
    {
        var tagIds = _fleetDirectoryState.AppliedFilters.TagIds;
        if (tagIds.Count == 0)
        {
            return true;
        }

        var chips = card.TagChips.Count > 0 ? card.TagChips : BuildFleetDirectoryTagChips(card);
        var requiredTags = GetTagRows(tagIds).ToArray();
        bool MatchesTag(ManageFleetTagOptionRow required) => chips.Any(chip =>
            chip.Name.Equals(required.Name, StringComparison.OrdinalIgnoreCase) ||
            chip.Name.Contains(required.Name, StringComparison.OrdinalIgnoreCase) ||
            chip.CategoryName.Equals(required.CategoryName, StringComparison.OrdinalIgnoreCase));

        return _fleetDirectoryState.AppliedFilters.MatchAllTags
            ? requiredTags.All(MatchesTag)
            : requiredTags.Any(MatchesTag);
    }

    private void FindFleetFilterToggleButton_Click(object sender, RoutedEventArgs e)
    {
        SetFindFleetFilterPanelVisible(true);
    }

    private void FindFleetFilterApplyButton_Click(object sender, RoutedEventArgs e)
    {
        _fleetDirectoryState.ApplyFilters(CaptureFindFleetFilterDraft());
        RefreshFindFleetAppliedFilters();
        ApplyFleetSearchFilter();
        SetFindFleetFilterPanelVisible(true);
    }

    private void FindFleetFilterResetButton_Click(object sender, RoutedEventArgs e)
    {
        SetFindFleetFilterChecks(false);
        _fleetDirectoryState.ApplyFilters(FleetDirectoryFilters.Empty);
        RefreshFindFleetAppliedFilters();
        ApplyFleetSearchFilter();
    }

    private void FindFleetFilterChanged(object sender, RoutedEventArgs e)
    {
        RefreshFindFleetFilterDraftSummary();
    }

    private void FindFleetRecruitingChanged(object sender, RoutedEventArgs e)
    {
        var enabled = IsChecked(FindFleetRecruitingCheck);
        if (FindFleetRecruitingTargetPanel is not null)
        {
            FindFleetRecruitingTargetPanel.IsEnabled = enabled;
        }

        if (!enabled)
        {
            if (FindFleetTargetAllCheck is not null) FindFleetTargetAllCheck.IsChecked = false;
            if (FindFleetTargetBeginnerCheck is not null) FindFleetTargetBeginnerCheck.IsChecked = false;
            if (FindFleetTargetCombatCheck is not null) FindFleetTargetCombatCheck.IsChecked = false;
            if (FindFleetTargetIndustrialCheck is not null) FindFleetTargetIndustrialCheck.IsChecked = false;
            if (FindFleetTargetTradeCheck is not null) FindFleetTargetTradeCheck.IsChecked = false;
            if (FindFleetTargetSupportCheck is not null) FindFleetTargetSupportCheck.IsChecked = false;
        }

        RefreshFindFleetFilterDraftSummary();
    }

    private void FindFleetFilterTagMatchModeChanged(object sender, SelectionChangedEventArgs e)
    {
        RefreshFindFleetFilterDraftSummary();
    }

    private void FindFleetSameTimeZoneChanged(object sender, RoutedEventArgs e)
    {
        var enabled = IsChecked(FindFleetSameTimeZoneCheck);
        if (FindFleetActivePeriodPanel is not null)
        {
            FindFleetActivePeriodPanel.IsEnabled = enabled;
        }

        if (!enabled)
        {
            FindFleetActiveEarlyMorningCheck.IsChecked = false;
            FindFleetActiveMorningCheck.IsChecked = false;
            FindFleetActiveAfternoonCheck.IsChecked = false;
            FindFleetActiveEveningCheck.IsChecked = false;
        }

        RefreshFindFleetFilterDraftSummary();
    }

    private void FindFleetFilterEditTagsButton_Click(object sender, RoutedEventArgs e)
    {
        _isCreateFleetTagSelectorMode = false;
        _isFindFleetTagFilterSelectorMode = true;
        OpenManageTagSelector();
    }

    private void SetFindFleetFilterPanelVisible(bool visible)
    {
        if (FindFleetFilterPanel is not null)
        {
            FindFleetFilterPanel.Visibility = Visibility.Visible;
        }

        if (FindFleetFilterToggleButton is not null)
        {
            FindFleetFilterToggleButton.Visibility = Visibility.Collapsed;
        }

        RefreshFindFleetFilterDraftSummary();
    }

    private FleetDirectoryFilters CaptureFindFleetFilterDraft() => new FleetDirectoryFilters(
        IsChecked(FindFleetRecruitingCheck),
        IsChecked(FindFleetOpenJoinCheck),
        IsChecked(FindFleetApplicationCheck),
        IsChecked(FindFleetInviteOnlyCheck),
        IsChecked(FindFleetPendingCheck),
        IsChecked(FindFleetScaleSmallCheck),
        IsChecked(FindFleetScaleMediumCheck),
        IsChecked(FindFleetScaleLargeCheck),
        IsChecked(FindFleetScaleVeryLargeCheck),
        false,
        IsChecked(FindFleetSameTimeZoneCheck),
        IsChecked(FindFleetSameTimeZoneCheck) && IsChecked(FindFleetActiveEarlyMorningCheck),
        IsChecked(FindFleetSameTimeZoneCheck) && IsChecked(FindFleetActiveMorningCheck),
        IsChecked(FindFleetSameTimeZoneCheck) && IsChecked(FindFleetActiveAfternoonCheck),
        IsChecked(FindFleetSameTimeZoneCheck) && IsChecked(FindFleetActiveEveningCheck),
        new[]
        {
            IsChecked(FindFleetDayMondayCheck) ? "mon" : "",
            IsChecked(FindFleetDayTuesdayCheck) ? "tue" : "",
            IsChecked(FindFleetDayWednesdayCheck) ? "wed" : "",
            IsChecked(FindFleetDayThursdayCheck) ? "thu" : "",
            IsChecked(FindFleetDayFridayCheck) ? "fri" : "",
            IsChecked(FindFleetDaySaturdayCheck) ? "sat" : "",
            IsChecked(FindFleetDaySundayCheck) ? "sun" : ""
        },
        IsChecked(FindFleetRecruitingCheck) ? new[]
        {
            IsChecked(FindFleetTargetAllCheck) ? "所有玩家" : "",
            IsChecked(FindFleetTargetBeginnerCheck) ? "新手友好" : "",
            IsChecked(FindFleetTargetCombatCheck) ? "战斗玩家" : "",
            IsChecked(FindFleetTargetIndustrialCheck) ? "工业玩家" : "",
            IsChecked(FindFleetTargetTradeCheck) ? "贸易与货运" : "",
            IsChecked(FindFleetTargetSupportCheck) ? "医疗与支援" : ""
        } : Array.Empty<string>(),
        new[]
        {
            IsChecked(FindFleetCadenceCasualCheck) ? "休闲" : "",
            IsChecked(FindFleetCadenceRegularCheck) ? "固定开黑" : "",
            IsChecked(FindFleetCadenceWeekendCheck) ? "周末行动" : "",
            IsChecked(FindFleetCadenceFrequentCheck) ? "高频组织" : "",
            IsChecked(FindFleetCadenceNoticeCheck) ? "大型行动前通知" : ""
        },
        IsChecked(FindFleetShipCountSmallCheck),
        IsChecked(FindFleetShipCountMediumCheck),
        IsChecked(FindFleetShipCountLargeCheck),
        IsChecked(FindFleetShipCountVeryLargeCheck),
        new[]
        {
            IsChecked(FindFleetShipCombatCheck) ? "Combat" : "",
            IsChecked(FindFleetShipTransportCheck) ? "Transport" : "",
            IsChecked(FindFleetShipIndustrialCheck) ? "Industrial" : "",
            IsChecked(FindFleetShipExplorationCheck) ? "Exploration" : "",
            IsChecked(FindFleetShipSupportCheck) ? "Support" : "",
            IsChecked(FindFleetShipUtilityCheck) ? "Utility" : ""
        },
        FindFleetTagMatchModeBox?.SelectedItem is ComboBoxItem { Tag: "all" },
        new[]
        {
            IsChecked(FindFleetSystemStantonCheck) ? "stanton" : "",
            IsChecked(FindFleetSystemPyroCheck) ? "pyro" : "",
            IsChecked(FindFleetSystemNyxCheck) ? "nyx" : ""
        },
        _findFleetFilterTagIds.ToArray()).Snapshot();

    private void RefreshFindFleetFilterDraftSummary()
    {
        if (FindFleetFilterSummaryText is null)
        {
            return;
        }

        var draft = CaptureFindFleetFilterDraft();
        var labels = BuildFindFleetFilterLabels(draft);
        FindFleetFilterSummaryText.Text = labels.Count == 0
            ? "未设置筛选条件。点击“确定”返回完整目录。"
            : $"已选择 {labels.Count.ToString(CultureInfo.InvariantCulture)} 项筛选条件，点击“确定”应用。";
    }

    private void RefreshFindFleetAppliedFilters()
    {
        _findFleetAppliedFilterLabels.Clear();
        foreach (var label in BuildFindFleetFilterLabels(_fleetDirectoryState.AppliedFilters))
        {
            _findFleetAppliedFilterLabels.Add(label);
        }

        if (FindFleetAppliedFiltersPanel is not null)
        {
            FindFleetAppliedFiltersPanel.Visibility = _findFleetAppliedFilterLabels.Count > 0
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (FindFleetAppliedFiltersRow is not null)
        {
            FindFleetAppliedFiltersRow.Visibility = _findFleetAppliedFilterLabels.Count > 0
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        SetFindFleetFilterPanelVisible(FindFleetFilterPanel?.Visibility == Visibility.Visible);
    }

    private IReadOnlyList<string> BuildFindFleetFilterLabels(FleetDirectoryFilters filters)
    {
        var labels = new List<string>();
        AddFilterLabel(filters.Recruiting, "正在招募");
        AddFilterLabel(filters.OpenJoin, "无需审核");
        AddFilterLabel(filters.Application, "申请加入");
        AddFilterLabel(filters.InviteOnly, "邀请码加入");
        AddFilterLabel(filters.Pending, "申请处理中");
        AddFilterLabel(filters.ScaleSmall, "小型舰队 · 1–10 人");
        AddFilterLabel(filters.ScaleMedium, "中型舰队 · 11–50 人");
        AddFilterLabel(filters.ScaleLarge, "大型舰队 · 51–299 人");
        AddFilterLabel(filters.ScaleVeryLarge, "超大型舰队 · 300 人以上");
        AddFilterLabel(filters.SameTimeZone, "同时区");
        AddFilterLabel(filters.ActiveEarlyMorning, "凌晨活跃");
        AddFilterLabel(filters.ActiveMorning, "上午活跃");
        AddFilterLabel(filters.ActiveAfternoon, "下午活跃");
        AddFilterLabel(filters.ActiveEvening, "晚间活跃");
        labels.AddRange(filters.ActivityDayIds.Select(GetFindFleetActivityDayLabel));
        labels.AddRange(filters.RecruitingTargets);
        labels.AddRange(filters.ActivityCadences);
        AddFilterLabel(filters.ShipCountSmall, "1–10 艘");
        AddFilterLabel(filters.ShipCountMedium, "11–30 艘");
        AddFilterLabel(filters.ShipCountLarge, "31–99 艘");
        AddFilterLabel(filters.ShipCountVeryLarge, "100+ 艘");
        labels.AddRange(filters.ShipRoleIds.Select(GetFindFleetShipRoleLabel));
        foreach (var systemId in filters.SystemIds)
        {
            labels.Add(systemId.ToLowerInvariant() switch
            {
                "stanton" => "斯坦顿",
                "pyro" => "派罗",
                "nyx" => "尼克斯",
                _ => systemId
            });
        }
        var selectedTagNames = GetTagRows(filters.TagIds).Select(tag => tag.Name).ToArray();
        if (selectedTagNames.Length > 0)
        {
            labels.Add($"标签{(filters.MatchAllTags ? "全部" : "任一")}：{string.Join("、", selectedTagNames)}");
        }
        return labels;

        void AddFilterLabel(bool include, string label)
        {
            if (include)
            {
                labels.Add(label);
            }
        }
    }

    private static string GetFindFleetActivityDayLabel(string dayId) => dayId.ToLowerInvariant() switch
    {
        "mon" => "周一",
        "tue" => "周二",
        "wed" => "周三",
        "thu" => "周四",
        "fri" => "周五",
        "sat" => "周六",
        "sun" => "周日",
        _ => dayId
    };

    private static string GetFindFleetShipRoleLabel(string roleId) => roleId.ToLowerInvariant() switch
    {
        "combat" => "战斗舰",
        "transport" => "运输舰",
        "industrial" => "工业舰",
        "exploration" => "探索舰",
        "support" => "支援舰",
        "utility" => "其他舰船",
        _ => roleId
    };

    private void FindFleetClearFiltersButton_Click(object sender, RoutedEventArgs e)
    {
        SetFindFleetFilterChecks(false);
        _fleetDirectoryState.ApplyFilters(FleetDirectoryFilters.Empty);
        RefreshFindFleetAppliedFilters();
        ApplyFleetSearchFilter();
    }

    private void FindFleetSortBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (FindFleetSortBox?.SelectedItem is not ComboBoxItem { Tag: string tag })
        {
            return;
        }

        var sortMode = tag switch
        {
            "recent" => FleetDirectorySortMode.RecentlyActive,
            "members" => FleetDirectorySortMode.MemberCount,
            "name" => FleetDirectorySortMode.Name,
            _ => FleetDirectorySortMode.Recommended
        };
        _fleetDirectoryState.SetSortMode(sortMode);
        ApplyFleetSearchFilter();
    }

    private void SetFindFleetFilterChecks(bool isChecked)
    {
        if (FindFleetRecruitingCheck is not null)
        {
            FindFleetRecruitingCheck.IsChecked = isChecked;
        }

        if (FindFleetRecruitingTargetPanel is not null)
        {
            FindFleetRecruitingTargetPanel.IsEnabled = isChecked;
        }

        if (FindFleetOpenJoinCheck is not null)
        {
            FindFleetOpenJoinCheck.IsChecked = isChecked;
        }

        if (FindFleetApplicationCheck is not null)
        {
            FindFleetApplicationCheck.IsChecked = isChecked;
        }

        if (FindFleetInviteOnlyCheck is not null)
        {
            FindFleetInviteOnlyCheck.IsChecked = isChecked;
        }

        if (FindFleetPendingCheck is not null)
        {
            FindFleetPendingCheck.IsChecked = isChecked;
        }

        if (FindFleetScaleSmallCheck is not null)
        {
            FindFleetScaleSmallCheck.IsChecked = isChecked;
        }

        if (FindFleetScaleMediumCheck is not null)
        {
            FindFleetScaleMediumCheck.IsChecked = isChecked;
        }

        if (FindFleetScaleLargeCheck is not null)
        {
            FindFleetScaleLargeCheck.IsChecked = isChecked;
        }

        if (FindFleetScaleVeryLargeCheck is not null)
        {
            FindFleetScaleVeryLargeCheck.IsChecked = isChecked;
        }

        FindFleetTargetAllCheck.IsChecked = isChecked;
        FindFleetTargetBeginnerCheck.IsChecked = isChecked;
        FindFleetTargetCombatCheck.IsChecked = isChecked;
        FindFleetTargetIndustrialCheck.IsChecked = isChecked;
        FindFleetTargetTradeCheck.IsChecked = isChecked;
        FindFleetTargetSupportCheck.IsChecked = isChecked;
        FindFleetCadenceCasualCheck.IsChecked = isChecked;
        FindFleetCadenceRegularCheck.IsChecked = isChecked;
        FindFleetCadenceWeekendCheck.IsChecked = isChecked;
        FindFleetCadenceFrequentCheck.IsChecked = isChecked;
        FindFleetCadenceNoticeCheck.IsChecked = isChecked;

        if (FindFleetHasBannerCheck is not null)
        {
            FindFleetHasBannerCheck.IsChecked = isChecked;
        }

        FindFleetSameTimeZoneCheck.IsChecked = isChecked;
        FindFleetActiveEarlyMorningCheck.IsChecked = isChecked;
        FindFleetActiveMorningCheck.IsChecked = isChecked;
        FindFleetActiveAfternoonCheck.IsChecked = isChecked;
        FindFleetActiveEveningCheck.IsChecked = isChecked;
        FindFleetActivePeriodPanel.IsEnabled = isChecked;
        FindFleetDayMondayCheck.IsChecked = isChecked;
        FindFleetDayTuesdayCheck.IsChecked = isChecked;
        FindFleetDayWednesdayCheck.IsChecked = isChecked;
        FindFleetDayThursdayCheck.IsChecked = isChecked;
        FindFleetDayFridayCheck.IsChecked = isChecked;
        FindFleetDaySaturdayCheck.IsChecked = isChecked;
        FindFleetDaySundayCheck.IsChecked = isChecked;
        FindFleetShipCountSmallCheck.IsChecked = isChecked;
        FindFleetShipCountMediumCheck.IsChecked = isChecked;
        FindFleetShipCountLargeCheck.IsChecked = isChecked;
        FindFleetShipCountVeryLargeCheck.IsChecked = isChecked;
        FindFleetShipCombatCheck.IsChecked = isChecked;
        FindFleetShipTransportCheck.IsChecked = isChecked;
        FindFleetShipIndustrialCheck.IsChecked = isChecked;
        FindFleetShipExplorationCheck.IsChecked = isChecked;
        FindFleetShipSupportCheck.IsChecked = isChecked;
        FindFleetShipUtilityCheck.IsChecked = isChecked;
        if (FindFleetTagMatchModeBox is not null)
        {
            FindFleetTagMatchModeBox.SelectedIndex = 0;
        }

        if (FindFleetSystemStantonCheck is not null)
        {
            FindFleetSystemStantonCheck.IsChecked = isChecked;
        }

        if (FindFleetSystemPyroCheck is not null)
        {
            FindFleetSystemPyroCheck.IsChecked = isChecked;
        }

        if (FindFleetSystemNyxCheck is not null)
        {
            FindFleetSystemNyxCheck.IsChecked = isChecked;
        }

        _findFleetFilterTagIds.Clear();
        RefreshFindFleetFilterSelectedTags();

        SetFindFleetFilterPanelVisible(FindFleetFilterPanel?.Visibility == Visibility.Visible);
    }

    private void SetFindFleetFilterTagIds(IEnumerable<string> tagIds)
    {
        _findFleetFilterTagIds.Clear();
        foreach (var id in tagIds
                     .Where(id => !string.IsNullOrWhiteSpace(id))
                     .Select(id => id.Trim())
                     .Where(IsKnownFleetTagId)
                     .Distinct(StringComparer.OrdinalIgnoreCase)
                     .Take(MaxManageFleetTags))
        {
            _findFleetFilterTagIds.Add(id);
        }

        RefreshFindFleetFilterSelectedTags();
        SetFindFleetFilterPanelVisible(FindFleetFilterPanel?.Visibility == Visibility.Visible);
    }

    private void RefreshFindFleetFilterSelectedTags()
    {
        _findFleetFilterSelectedTags.Clear();
        foreach (var tag in GetTagRows(_findFleetFilterTagIds))
        {
            _findFleetFilterSelectedTags.Add(tag);
        }

        if (FindFleetFilterTagCountText is not null)
        {
            FindFleetFilterTagCountText.Text =
                $"{_findFleetFilterTagIds.Count.ToString(CultureInfo.InvariantCulture)} / {MaxManageFleetTags.ToString(CultureInfo.InvariantCulture)}";
        }

        var hasTags = _findFleetFilterTagIds.Count > 0;
        if (FindFleetFilterTagEmptyText is not null)
        {
            FindFleetFilterTagEmptyText.Visibility = hasTags ? Visibility.Collapsed : Visibility.Visible;
        }

        if (FindFleetFilterSelectedTagsList is not null)
        {
            FindFleetFilterSelectedTagsList.Visibility = hasTags ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    private NetworkFleetCard ApplyCurrentFleetBannerFallback(NetworkFleetCard card)
    {
        return card;
    }

    private static NetworkFleetCard DecorateFleetDirectoryTags(NetworkFleetCard card)
    {
        var chips = BuildFleetDirectoryTagChips(card);
        var systemChips = BuildFleetDirectorySystemRecommendationChips(card);
        return card with
        {
            TagChips = chips,
            SystemRecommendationChips = systemChips
        };
    }

    private static IReadOnlyList<FleetDirectoryTagChip> BuildFleetDirectorySystemRecommendationChips(NetworkFleetCard card)
    {
        var candidates = new List<(int Priority, FleetDirectoryTagChip Chip)>();
        var snapshot = card.Snapshot;

        if (snapshot.PublicShowActivityTime && !string.IsNullOrWhiteSpace(snapshot.TimeZoneId))
        {
            try
            {
                var fleetZone = TimeZoneInfo.FindSystemTimeZoneById(snapshot.TimeZoneId);
                var now = DateTimeOffset.UtcNow;
                var offsetDifference = (fleetZone.GetUtcOffset(now) - TimeZoneInfo.Local.GetUtcOffset(now)).Duration();
                if (offsetDifference == TimeSpan.Zero)
                {
                    candidates.Add((100, CreateFleetDirectorySystemChip(
                        "时区相同",
                        "舰队默认时区与你当前时区的 UTC 偏移一致。",
                        "#42CFB0")));
                }
                else if (offsetDifference <= TimeSpan.FromHours(1))
                {
                    candidates.Add((95, CreateFleetDirectorySystemChip(
                        "时差较小",
                        "舰队默认时区与你当前时区相差不超过 1 小时。",
                        "#42CFB0")));
                }
            }
            catch (TimeZoneNotFoundException)
            {
                // Invalid public time-zone data should not block directory rendering.
            }
            catch (InvalidTimeZoneException)
            {
                // Invalid public time-zone data should not block directory rendering.
            }
        }

        if (!card.RequiresApplication && !card.IsInviteOnly)
        {
            candidates.Add((90, CreateFleetDirectorySystemChip(
                "无门槛",
                "该舰队公开设置为直接加入，无需申请审核或邀请码。",
                "#42CF7C")));
        }

        if (!string.Equals(snapshot.PublicMemberScaleMode, "Hidden", StringComparison.OrdinalIgnoreCase) &&
            snapshot.TotalMembers >= 51)
        {
            candidates.Add((85, CreateFleetDirectorySystemChip(
                "大规模",
                "该舰队公开成员规模达到 51 人或以上。",
                "#29AFFF")));
        }

        if (snapshot.RecruitingEnabled)
        {
            var recruitingTarget = string.IsNullOrWhiteSpace(snapshot.RecruitingTarget)
                ? "所有玩家"
                : snapshot.RecruitingTarget.Trim();
            candidates.Add((110, CreateFleetDirectorySystemChip(
                $"正在招募 · {recruitingTarget}",
                $"该舰队当前公开招募群体：{recruitingTarget}。",
                "#42CF7C")));
        }

        var publicShipCount = Math.Max(snapshot.PublicShipCount, snapshot.Ships?.Length ?? 0);
        if (!string.Equals(snapshot.PublicShipScaleMode, "Hidden", StringComparison.OrdinalIgnoreCase) &&
            publicShipCount >= 20)
        {
            candidates.Add((70, CreateFleetDirectorySystemChip(
                "舰船丰富",
                "该舰队公开舰船总数达到 20 艘或以上。",
                "#29AFFF")));
        }

        if (string.Equals(snapshot.PublicShipScaleMode, "TypeSummary", StringComparison.OrdinalIgnoreCase) &&
            ParsePublicShipTypeSummary(snapshot.PublicShipTypeSummary).Count(item => item.Value > 0) >= 3)
        {
            candidates.Add((65, CreateFleetDirectorySystemChip(
                "舰种多样",
                "该舰队公开的舰船资源覆盖至少 3 个类型。",
                "#29AFFF")));
        }

        if (snapshot.PublicShowActiveSystems &&
            (snapshot.ActiveSystemIds ?? []).Where(id => !string.IsNullOrWhiteSpace(id)).Distinct(StringComparer.OrdinalIgnoreCase).Count() >= 2)
        {
            candidates.Add((60, CreateFleetDirectorySystemChip(
                "多区域活动",
                "该舰队公开了至少 2 个主要活跃星系。",
                "#41BDE8")));
        }

        var hasCompleteProfile = snapshot.PublicShowDescription && !string.IsNullOrWhiteSpace(snapshot.Description) &&
                                 snapshot.PublicShowTags && !string.IsNullOrWhiteSpace(snapshot.Type) &&
                                 snapshot.PublicShowActivityTime && !string.IsNullOrWhiteSpace(snapshot.ActiveTime) &&
                                 snapshot.PublicShowActiveSystems && (snapshot.ActiveSystemIds?.Length ?? 0) > 0;
        if (hasCompleteProfile)
        {
            candidates.Add((50, CreateFleetDirectorySystemChip(
                "资料完整",
                "该舰队公开了介绍、玩法标签、活动时间和主要活跃区域。",
                "#91A5B5")));
        }

        return candidates
            .OrderByDescending(item => item.Priority)
            .Select(item => item.Chip)
            .Take(3)
            .ToArray();
    }

    private static FleetDirectoryTagChip CreateFleetDirectorySystemChip(
        string name,
        string reason,
        string color)
    {
        return new FleetDirectoryTagChip(
            name,
            "系统推荐",
            reason,
            BrushFromHex(color),
            BrushFromHex(color, 0.72),
            BrushFromHex(color, 0.16),
            $"{name}：{reason}");
    }

    private static IReadOnlyList<FleetDirectoryTagChip> BuildFleetDirectoryTagChips(NetworkFleetCard card)
    {
        var rawTags = card.Snapshot.PublicShowTags && !string.IsNullOrWhiteSpace(card.Snapshot.Type)
            ? card.Snapshot.Type
            : ExtractFleetDirectoryTagText(card.TypeLine);
        if (string.IsNullOrWhiteSpace(rawTags) ||
            rawTags.Equals("未公开", StringComparison.OrdinalIgnoreCase))
        {
            return Array.Empty<FleetDirectoryTagChip>();
        }

        var chips = new List<FleetDirectoryTagChip>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var token in SplitFleetDirectoryTags(rawTags))
        {
            if (chips.Count >= MaxManageFleetTags)
            {
                break;
            }

            var chip = CreateFleetDirectoryTagChip(token);
            if (chip is null || !seen.Add(chip.Name))
            {
                continue;
            }

            chips.Add(chip);
        }

        return chips.Count == 0 ? Array.Empty<FleetDirectoryTagChip>() : chips;
    }

    private static string ExtractFleetDirectoryTagText(string typeLine)
    {
        if (string.IsNullOrWhiteSpace(typeLine))
        {
            return "";
        }

        var slashIndex = typeLine.IndexOf('/');
        return slashIndex >= 0
            ? typeLine[(slashIndex + 1)..].Trim()
            : typeLine.Trim();
    }

    private static IEnumerable<string> SplitFleetDirectoryTags(string rawTags)
    {
        return rawTags
            .Split(['/', '、', ',', '，', ';', '；', '|'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(tag => !string.IsNullOrWhiteSpace(tag));
    }

    private static FleetDirectoryTagChip? CreateFleetDirectoryTagChip(string rawTag)
    {
        var tagText = rawTag.Trim();
        if (tagText.Length == 0 || tagText.Equals("未公开", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var tag = FleetTagDefinitions.FirstOrDefault(item =>
            item.Id.Equals(tagText, StringComparison.OrdinalIgnoreCase) ||
            item.Name.Equals(tagText, StringComparison.OrdinalIgnoreCase));
        if (tag is not null)
        {
            var category = FleetTagCategoryDefinitions.FirstOrDefault(item =>
                item.Id.Equals(tag.CategoryId, StringComparison.OrdinalIgnoreCase));
            if (category is not null)
            {
                var row = new ManageFleetTagOptionRow(tag, category);
                return new FleetDirectoryTagChip(
                    row.Name,
                    row.CategoryName,
                    row.Description,
                    row.AccentBrush,
                    row.BorderBrush,
                    row.BackgroundBrush,
                    row.TooltipText);
            }
        }

        var accent = BrushFromHex("#91A5B5");
        return new FleetDirectoryTagChip(
            tagText,
            "舰队标签",
            "旧标签或未归类标签。",
            accent,
            BrushFromHex("#91A5B5", 0.62),
            BrushFromHex("#91A5B5", 0.14),
            tagText);
    }

    private static int CalculateFleetSearchScore(NetworkFleetCard card, string query)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return 1;
        }

        var name = card.Name ?? "";
        var code = card.Snapshot.Code ?? "";
        if (code.Equals(query, StringComparison.OrdinalIgnoreCase))
        {
            return 100;
        }

        if (name.Equals(query, StringComparison.OrdinalIgnoreCase))
        {
            return 95;
        }

        if (code.StartsWith(query, StringComparison.OrdinalIgnoreCase))
        {
            return 80;
        }

        if (name.StartsWith(query, StringComparison.OrdinalIgnoreCase))
        {
            return 70;
        }

        if (code.Contains(query, StringComparison.OrdinalIgnoreCase))
        {
            return 50;
        }

        if (name.Contains(query, StringComparison.OrdinalIgnoreCase))
        {
            return 40;
        }

        if (card.Snapshot.RecruitingEnabled &&
            card.Snapshot.RecruitingTarget?.Contains(query, StringComparison.OrdinalIgnoreCase) == true)
        {
            return 35;
        }

        if (card.CommanderLine.Contains(query, StringComparison.OrdinalIgnoreCase) ||
            card.Description.Contains(query, StringComparison.OrdinalIgnoreCase) ||
            card.TypeLine.Contains(query, StringComparison.OrdinalIgnoreCase) ||
            card.ActiveTimeLine.Contains(query, StringComparison.OrdinalIgnoreCase) ||
            card.PublicShipScaleLine.Contains(query, StringComparison.OrdinalIgnoreCase) ||
            card.FleetScaleLine.Contains(query, StringComparison.OrdinalIgnoreCase))
        {
            return 30;
        }

        if (card.TagChips.Any(chip =>
                chip.Name.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                chip.CategoryName.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                chip.Description.Contains(query, StringComparison.OrdinalIgnoreCase)))
        {
            return 45;
        }

        return 0;
    }

    private void FindFleetSearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        ApplyFleetSearchFilter();
    }

    private void RefreshFindFleetDetailSelection()
    {
        if (_selectedFindFleetCard is not null)
        {
            var selectedCode = _selectedFindFleetCard.Snapshot.Code;
            var updated = _networkFleets.FirstOrDefault(card =>
                card.Snapshot.Code.Equals(selectedCode, StringComparison.OrdinalIgnoreCase));
            ShowFindFleetDetails(updated, revealPanel: false);
            return;
        }

        ShowFindFleetDetails(_networkFleets.FirstOrDefault(), revealPanel: false);
    }

    private void FindFleetCard_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (FindVisualParent<System.Windows.Controls.Primitives.ButtonBase>(e.OriginalSource as DependencyObject) is not null)
        {
            return;
        }

        if ((sender as FrameworkElement)?.Tag is NetworkFleetCard card)
        {
            ShowFindFleetDetails(card);
        }
    }

    private void FindFleetCardDetails_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is NetworkFleetCard card)
        {
            ShowFindFleetDetails(card);
        }
    }

    private void FindFleetDetailCloseButton_Click(object sender, RoutedEventArgs e)
    {
        _fleetDirectoryState.CloseDetails();
        ApplyFindFleetDetailPanelState();
    }

    private void FindFleetDetailScrim_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        _fleetDirectoryState.CloseDetails();
        ApplyFindFleetDetailPanelState();
        e.Handled = true;
    }

    private void ShowFindFleetDetails(NetworkFleetCard? card, bool revealPanel = true)
    {
        _selectedFindFleetCard = card;
        if (revealPanel)
        {
            _fleetDirectoryState.SelectFromUser(card?.Snapshot.Code);
        }
        else
        {
            _fleetDirectoryState.RefreshSelection(card?.Snapshot.Code);
        }

        ApplyFindFleetDetailPanelState();

        if (FindFleetDetailJoinButton is not null)
        {
            FindFleetDetailJoinButton.Tag = card;
            FindFleetDetailJoinButton.IsEnabled = card?.CanJoin == true;
            FindFleetDetailJoinButton.Content = card?.JoinButtonText ?? "选择舰队";
            FindFleetDetailJoinButton.Opacity = FindFleetDetailJoinButton.IsEnabled ? 1 : 0.58;
            FindFleetDetailJoinButton.Visibility = card?.CanJoin == true ? Visibility.Visible : Visibility.Collapsed;
        }

        if (FindFleetDetailCopyCodeButton is not null)
        {
            FindFleetDetailCopyCodeButton.IsEnabled = card is not null;
            FindFleetDetailCopyCodeButton.Opacity = card is null ? 0.58 : 1;
        }

        if (card is null)
        {
            SetText(FindFleetDetailNameText, "选择一个舰队");
            SetText(FindFleetDetailCodeText, "识别码 / --");
            SetText(FindFleetDetailCommanderText, "指挥官：--");
            SetText(FindFleetDetailDescriptionText, "从左侧目录中选择舰队后，这里会显示简介、活动时间、舰船展示和加入方式。");
            SetText(FindFleetDetailActiveTimeText, "活动时间 / --");
            SetText(FindFleetDetailTimeZoneText, "舰队默认时间 / 未公开");
            SetText(FindFleetDetailMembersText, "成员规模 / --");
            SetText(FindFleetDetailJoinPolicyText, "加入方式 / --");
            SetText(FindFleetDetailRecruitingText, "招募状态 / --");
            SetText(FindFleetDetailNoticeText, "暂无舰船展示。");
            SetText(FindFleetDetailSystemText, "未公开");
            SetText(FindFleetDetailLanguageText, "语言 / 未公开");
            SetText(FindFleetDetailContactText, "未公开联系方式");
            SetText(FindFleetDetailRequirementText, "选择舰队后查看加入要求。");
            SetText(FindFleetDetailHintText, "选择适合的舰队后，可以申请加入或使用邀请码进入。");
            RefreshFindFleetDetailShipDistribution(null);
            if (FindFleetDetailTagChips is not null)
            {
                FindFleetDetailTagChips.ItemsSource = Array.Empty<FleetDirectoryTagChip>();
            }

            if (FindFleetDetailLogoImage is not null)
            {
                FindFleetDetailLogoImage.Source = null;
                FindFleetDetailLogoImage.Visibility = Visibility.Collapsed;
            }

            if (FindFleetDetailLogoText is not null)
            {
                FindFleetDetailLogoText.Visibility = Visibility.Visible;
                FindFleetDetailLogoText.Text = "LOGO";
            }

            return;
        }

        SetText(FindFleetDetailNameText, card.Name);
        SetText(FindFleetDetailCodeText, $"识别码 / {card.FleetCodeText}");
        SetText(FindFleetDetailCommanderText, $"指挥官：{card.CommanderText}");
        SetText(FindFleetDetailDescriptionText, string.IsNullOrWhiteSpace(card.Description)
            ? "暂无公开舰队介绍。"
            : card.Description);
        SetText(FindFleetDetailActiveTimeText, card.LocalActiveTimeLine);
        SetText(FindFleetDetailTimeZoneText, $"舰队默认时间 / {card.FleetDefaultTimeText}");
        SetText(FindFleetDetailMembersText, card.MembersLine);
        SetText(FindFleetDetailJoinPolicyText, card.JoinPolicyLine);
        SetText(FindFleetDetailRecruitingText, card.RecruitingStatusText);
        SetText(FindFleetDetailNoticeText, $"公开舰船规模：{card.PublicShipTotalValueText}");
        SetText(FindFleetDetailSystemText, card.ActiveSystemText);
        SetText(FindFleetDetailLanguageText, card.LanguageLine);
        SetText(FindFleetDetailContactText, card.PublicContactText);
        SetText(FindFleetDetailRequirementText, card.InviteRequirementLine);
        SetText(FindFleetDetailHintText, card.DetailActionHint);
        RefreshFindFleetDetailShipDistribution(card.Snapshot);

        if (FindFleetDetailTagChips is not null)
        {
            FindFleetDetailTagChips.ItemsSource = card.TagChips;
        }

        if (FindFleetDetailLogoImage is not null && TryCreateBitmapImageFromImageData(card.Snapshot.LogoImageData, out var logo))
        {
            FindFleetDetailLogoImage.Source = logo;
            FindFleetDetailLogoImage.Visibility = Visibility.Visible;
            if (FindFleetDetailLogoText is not null)
            {
                FindFleetDetailLogoText.Visibility = Visibility.Collapsed;
            }
        }
        else
        {
            if (FindFleetDetailLogoImage is not null)
            {
                FindFleetDetailLogoImage.Source = null;
                FindFleetDetailLogoImage.Visibility = Visibility.Collapsed;
            }

            if (FindFleetDetailLogoText is not null)
            {
                FindFleetDetailLogoText.Visibility = Visibility.Visible;
                FindFleetDetailLogoText.Text = string.IsNullOrWhiteSpace(card.Snapshot.LogoText)
                    ? "LOGO"
                    : card.Snapshot.LogoText!.Trim();
            }
        }
    }

    private void RefreshFindFleetDetailShipDistribution(NetworkFleetSnapshot? snapshot)
    {
        if (FindFleetDetailShipDistributionPanel is null ||
            FindFleetDetailShipDistributionBar is null ||
            FindFleetDetailShipDistributionLegend is null)
        {
            return;
        }

        FindFleetDetailShipDistributionBar.Children.Clear();
        FindFleetDetailShipDistributionBar.ColumnDefinitions.Clear();
        FindFleetDetailShipDistributionLegend.ItemsSource = null;
        FindFleetDetailShipDistributionPanel.Visibility = Visibility.Collapsed;

        if (snapshot is null ||
            !string.Equals(NormalizeFleetPublicShipScaleMode(snapshot.PublicShipScaleMode), FleetPublicShipScaleTypeSummary, StringComparison.Ordinal))
        {
            return;
        }

        var counts = ParsePublicShipTypeSummary(snapshot.PublicShipTypeSummary);
        if (counts.Count == 0 && snapshot.Ships is { Length: > 0 })
        {
            foreach (var group in snapshot.Ships
                         .GroupBy(ResolveFindFleetShipTypeKey, StringComparer.OrdinalIgnoreCase))
            {
                counts[group.Key] = group.Count();
            }
        }

        var rows = FleetShipRoleVisuals
            .Select(category => new
            {
                Name = category.DisplayName,
                Brush = CreateSolidBrush(category.ColorHex),
                Count = counts.GetValueOrDefault(category.Key)
            })
            .ToArray();
        var visibleSegments = rows.Where(row => row.Count > 0).ToArray();
        if (visibleSegments.Length == 0)
        {
            return;
        }

        for (var index = 0; index < visibleSegments.Length; index++)
        {
            var segment = visibleSegments[index];
            FindFleetDetailShipDistributionBar.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = new GridLength(segment.Count, GridUnitType.Star)
            });
            var block = new Border
            {
                Background = segment.Brush,
                Opacity = 0.72,
                Margin = index == 0 ? new Thickness(0) : new Thickness(4, 0, 0, 0)
            };
            Grid.SetColumn(block, index);
            FindFleetDetailShipDistributionBar.Children.Add(block);
        }

        FindFleetDetailShipDistributionLegend.ItemsSource = rows
            .Select(row => new PersonalHangarDistributionRow(row.Name, $"{row.Count} 艘", row.Brush))
            .ToArray();
        FindFleetDetailShipDistributionPanel.Visibility = Visibility.Visible;
    }

    private static string ResolveFindFleetShipTypeKey(NetworkFleetShipSnapshot ship)
    {
        var stored = (ship.RoleCategory ?? "").Trim();
        var normalizedStored = stored.ToLowerInvariant() switch
        {
            "combat" => "Combat",
            "transport" => "Transport",
            "industrial" => "Industrial",
            "exploration" => "Exploration",
            "support" => "Support",
            _ => "Utility"
        };
        if (!normalizedStored.Equals("Utility", StringComparison.Ordinal))
        {
            return normalizedStored;
        }

        var catalog = ShipCatalog.Find(ship.Code, ship.DisplayName);
        return GetFleetShipRoleCategory(catalog?.Role ?? "") switch
        {
            FleetShipRoleCategory.Combat => "Combat",
            FleetShipRoleCategory.Transport => "Transport",
            FleetShipRoleCategory.Industrial => "Industrial",
            FleetShipRoleCategory.Exploration => "Exploration",
            FleetShipRoleCategory.Support => "Support",
            _ => "Utility"
        };
    }

    private static Dictionary<string, int> ParsePublicShipTypeSummary(string? summary)
    {
        var result = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        if (string.IsNullOrWhiteSpace(summary))
        {
            return result;
        }

        foreach (var item in summary.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var parts = item.Split('=', 2, StringSplitOptions.TrimEntries);
            if (parts.Length == 2 && int.TryParse(parts[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out var count) && count >= 0)
            {
                result[parts[0]] = count;
            }
        }

        return result;
    }

    private void ApplyFindFleetDetailPanelState()
    {
        if (_fleetDirectoryState.IsDetailVisible)
        {
            UiMotion.ShowModal(FindFleetDetailScrim, FindFleetDetailPanel);
        }
        else
        {
            UiMotion.HideModal(FindFleetDetailScrim, FindFleetDetailPanel);
        }
    }

    private static void SetText(TextBlock? textBlock, string value)
    {
        if (textBlock is not null)
        {
            textBlock.Text = value;
        }
    }

    private static bool TryCreateBitmapImageFromImageData(string? imageData, out BitmapImage? bitmap)
    {
        bitmap = null;
        if (!TryDecodeImageData(imageData, 2 * 1024 * 1024, out var bytes))
        {
            return false;
        }

        try
        {
            using var stream = new MemoryStream(bytes);
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.StreamSource = stream;
            image.EndInit();
            image.Freeze();
            bitmap = image;
            return true;
        }
        catch
        {
            bitmap = null;
            return false;
        }
    }

    private void CopyFindFleetCode_Click(object sender, RoutedEventArgs e)
    {
        var code = _selectedFindFleetCard?.FleetCodeText;
        if (string.IsNullOrWhiteSpace(code) || code.Equals("N/A", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        System.Windows.Clipboard.SetText(code);
        NetworkStatusText.Text = $"已复制舰队识别码：{code}";
    }

    private void FindFleetInviteButton_Click(object sender, RoutedEventArgs e)
    {
        OpenFindFleetInviteDialog();
    }

    private void OpenFindFleetInviteDialog()
    {
        _findFleetInvitePreview = null;
        _findFleetInviteCode = "";

        if (FindFleetInviteCodeBox is not null)
        {
            FindFleetInviteCodeBox.Text = "";
            FindFleetInviteCodeBox.Focus();
        }

        if (FindFleetInvitePreviewCard is not null)
        {
            FindFleetInvitePreviewCard.Visibility = Visibility.Collapsed;
        }

        if (FindFleetInviteJoinButton is not null)
        {
            FindFleetInviteJoinButton.Content = "加入舰队";
            FindFleetInviteJoinButton.IsEnabled = false;
            FindFleetInviteJoinButton.Opacity = 0.58;
        }

        SetFindFleetInviteStatus("输入邀请码后先验证，再加入舰队。", ManageProfileStatusTone.Info);

        UiMotion.ShowModal(FindFleetInviteDialogOverlay, FindFleetInviteDialogCard);
    }

    private void CloseFindFleetInviteDialog()
    {
        UiMotion.HideModal(FindFleetInviteDialogOverlay, FindFleetInviteDialogCard);
    }

    private void FindFleetInviteDialogCloseButton_Click(object sender, RoutedEventArgs e)
    {
        CloseFindFleetInviteDialog();
    }

    private void FindFleetInviteDialogOverlay_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (FindFleetInviteDialogCard?.IsMouseOver == true)
        {
            return;
        }

        CloseFindFleetInviteDialog();
    }

    private void FindFleetInviteDialogCard_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        e.Handled = true;
    }

    private async void FindFleetInviteVerifyButton_Click(object sender, RoutedEventArgs e)
    {
        var code = FindFleetInviteCodeBox?.Text.Trim() ?? "";
        _findFleetInvitePreview = null;
        _findFleetInviteCode = "";

        if (FindFleetInvitePreviewCard is not null)
        {
            FindFleetInvitePreviewCard.Visibility = Visibility.Collapsed;
        }

        if (FindFleetInviteJoinButton is not null)
        {
            FindFleetInviteJoinButton.IsEnabled = false;
            FindFleetInviteJoinButton.Opacity = 0.58;
        }

        if (string.IsNullOrWhiteSpace(code))
        {
            SetFindFleetInviteStatus("请输入邀请码。", ManageProfileStatusTone.Warning);
            return;
        }

        SetFindFleetInviteStatus("正在验证邀请码...", ManageProfileStatusTone.Info);
        try
        {
            var response = await PostNetworkJsonAsync("api/fleets/invites/preview", new FleetInvitePreviewRequest(code));
            if (!response.IsSuccessStatusCode)
            {
                SetFindFleetInviteStatus(FormatFindFleetInviteError(response.StatusCode, await ReadResponseErrorAsync(response)), ManageProfileStatusTone.Danger);
                return;
            }

            var preview = await response.Content.ReadFromJsonAsync<FleetInvitePreviewResponse>();
            if (preview is null)
            {
                SetFindFleetInviteStatus("服务器没有返回邀请码信息，请稍后重试。", ManageProfileStatusTone.Danger);
                return;
            }

            _findFleetInvitePreview = preview;
            _findFleetInviteCode = code;
            RefreshFindFleetInvitePreview(preview);
            if (IsFindFleetInviteForCurrentFleet(preview))
            {
                SetFindFleetInviteStatus("你已经在这个舰队中，可以继续查看名片详情。", ManageProfileStatusTone.Info);
            }
            else if (_hasFleet)
            {
                SetFindFleetInviteStatus(
                    $"你当前已加入“{_fleetName}”。如需接受邀请，请先手动退出当前舰队。",
                    ManageProfileStatusTone.Warning);
            }
            else
            {
                SetFindFleetInviteStatus("邀请有效。确认舰队信息后可以加入。", ManageProfileStatusTone.Success);
            }
        }
        catch (Exception ex)
        {
            SetFindFleetInviteStatus(UserFacingError.Describe(ex, "邀请码暂时无法验证，请稍后重试。"), ManageProfileStatusTone.Danger);
        }
    }

    private async Task<bool> ChooseSyncScopeForFleetEntryAsync(string fleetName, bool isApplication)
    {
        var action = isApplication ? "提交加入申请" : "加入舰队";
        var result = await ShowSyncChoiceAsync(
            $"{action}前选择同步范围",
            isApplication
                ? $"如果申请获批，StarBridge 将按以下选择向“{fleetName}”共享状态。"
                : $"加入“{fleetName}”后，StarBridge 将按以下选择共享状态。",
            resetPersonalHangar: false,
            confirmText: isApplication ? "保存并申请" : "保存并加入");
        return result is not null;
    }

    private async void FindFleetInviteJoinButton_Click(object sender, RoutedEventArgs e)
    {
        if (_findFleetInvitePreview is null || string.IsNullOrWhiteSpace(_findFleetInviteCode))
        {
            SetFindFleetInviteStatus("请先验证邀请码。", ManageProfileStatusTone.Warning);
            return;
        }

        if (IsFindFleetInviteForCurrentFleet(_findFleetInvitePreview))
        {
            SetFindFleetInviteStatus("你已经在这个舰队中，可以继续查看名片详情。", ManageProfileStatusTone.Info);
            return;
        }

        if (_hasFleet)
        {
            SetFindFleetInviteStatus(
                $"请先手动退出“{_fleetName}”，再返回这张名片接受邀请。",
                ManageProfileStatusTone.Warning);
            return;
        }

        if (!EnsureLoggedIn("使用邀请码加入舰队需要先登录星海舰桥账号。"))
        {
            return;
        }

        if (!EnsureIdentityInitialized("邀请码加入舰队"))
        {
            return;
        }

        if (!await ChooseSyncScopeForFleetEntryAsync(_findFleetInvitePreview.FleetName, isApplication: false))
        {
            return;
        }

        SetFindFleetInviteStatus("正在加入舰队...", ManageProfileStatusTone.Info);
        try
        {
            var response = await PostNetworkJsonAsync("api/fleets/invites/accept", new FleetInviteAcceptRequest(_findFleetInviteCode));
            if (!response.IsSuccessStatusCode)
            {
                SetFindFleetInviteStatus(FormatFindFleetInviteError(response.StatusCode, await ReadResponseErrorAsync(response)), ManageProfileStatusTone.Danger);
                return;
            }

            var snapshot = await response.Content.ReadFromJsonAsync<NetworkFleetSnapshot>();
            if (snapshot is null)
            {
                SetFindFleetInviteStatus("服务器没有返回舰队资料，请稍后重试。", ManageProfileStatusTone.Danger);
                return;
            }

            JoinNetworkFleet(snapshot);
            await PushLocalSnapshotAsync(silent: true, pushFleetDirectory: false);
            await PullNetworkFleetsAsync(silent: true);
            await PullNetworkSnapshotsAsync(silent: true);
            NetworkStatusText.Text = $"已加入舰队：{snapshot.Name}";
            CloseFindFleetInviteDialog();
            NavigateToMyFleet();
        }
        catch (Exception ex)
        {
            SetFindFleetInviteStatus(UserFacingError.Describe(ex, "暂时无法加入舰队，请稍后重试。"), ManageProfileStatusTone.Danger);
        }
    }

    private void RefreshFindFleetInvitePreview(FleetInvitePreviewResponse preview)
    {
        SetText(FindFleetInvitePreviewFleetText, $"{preview.FleetName} / {preview.FleetCode}");
        SetText(FindFleetInvitePreviewCommanderText, $"邀请舰队：{preview.FleetName} · 指挥官：{NormalizeOptionalField(preview.Commander)}");
        SetText(FindFleetInvitePreviewMetaText, $"{FormatFindFleetInviteAcceptMode(preview)} · {FormatFindFleetInviteExpiry(preview)}");
        SetText(FindFleetInvitePreviewUsesText, FormatFindFleetInviteUses(preview));

        if (FindFleetInvitePreviewCard is not null)
        {
            FindFleetInvitePreviewCard.Visibility = Visibility.Visible;
        }

        if (FindFleetInviteJoinButton is not null)
        {
            var alreadyInTargetFleet = IsFindFleetInviteForCurrentFleet(preview);
            var mustLeaveCurrentFleet = _hasFleet && !alreadyInTargetFleet;
            FindFleetInviteJoinButton.Content = alreadyInTargetFleet
                ? "已在该舰队"
                : mustLeaveCurrentFleet
                    ? "请先退出当前舰队"
                    : "加入舰队";
            FindFleetInviteJoinButton.IsEnabled = !_hasFleet;
            FindFleetInviteJoinButton.Opacity = _hasFleet ? 0.58 : 1;
        }
    }

    private bool IsFindFleetInviteForCurrentFleet(FleetInvitePreviewResponse? preview)
    {
        if (preview is null || !_hasFleet)
        {
            return false;
        }

        return !string.IsNullOrWhiteSpace(_fleetCode) &&
               preview.FleetCode.Equals(_fleetCode.Trim(), StringComparison.OrdinalIgnoreCase);
    }

    private void SetFindFleetInviteStatus(string message, ManageProfileStatusTone tone)
    {
        if (FindFleetInviteStatusText is null)
        {
            return;
        }

        FindFleetInviteStatusText.Text = message;
        FindFleetInviteStatusText.Foreground = tone switch
        {
            ManageProfileStatusTone.Success => FindBrush("StatusSuccessBrush", Brushes.LightGreen),
            ManageProfileStatusTone.Warning => FindBrush("StatusWarningBrush", Brushes.Orange),
            ManageProfileStatusTone.Danger => FindBrush("StatusDangerBrush", Brushes.IndianRed),
            ManageProfileStatusTone.Locked => FindBrush("MutedTextBrush", Brushes.LightSlateGray),
            _ => FindBrush("MutedTextBrush", Brushes.LightSlateGray)
        };
    }

    private static string FormatFindFleetInviteError(HttpStatusCode statusCode, string serverMessage)
    {
        if (statusCode == HttpStatusCode.NotFound)
        {
            return "邀请码不存在、已过期或已用完。";
        }

        if (statusCode == HttpStatusCode.Conflict)
        {
            return string.IsNullOrWhiteSpace(serverMessage) ? "当前状态无法使用该邀请码。" : serverMessage;
        }

        if (statusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
        {
            return "当前账号没有使用该邀请码的权限，请先登录或更换账号。";
        }

        return string.IsNullOrWhiteSpace(serverMessage)
            ? $"邀请码操作失败：{(int)statusCode}"
            : serverMessage;
    }

    private static string FormatFindFleetInviteAcceptMode(FleetInvitePreviewResponse preview) =>
        preview.AcceptMode.Equals("Direct", StringComparison.OrdinalIgnoreCase)
            ? "直接加入"
            : "需要确认";

    private static string FormatFindFleetInviteExpiry(FleetInvitePreviewResponse preview)
    {
        if (preview.ExpiresAt == default)
        {
            return "长期有效";
        }

        var local = preview.ExpiresAt.ToLocalTime();
        if (preview.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            return "已过期";
        }

        var remaining = preview.ExpiresAt - DateTimeOffset.UtcNow;
        var remainingText = remaining.TotalDays >= 1
            ? $"还剩 {(int)Math.Floor(remaining.TotalDays)} 天"
            : remaining.TotalHours >= 1
                ? $"还剩 {(int)Math.Ceiling(remaining.TotalHours)} 小时"
                : $"还剩 {Math.Max(1, (int)Math.Ceiling(remaining.TotalMinutes))} 分钟";
        return $"{remainingText} · {local:MM-dd HH:mm} 过期";
    }

    private static string FormatFindFleetInviteUses(FleetInvitePreviewResponse preview)
    {
        if (preview.RemainingUses < 0)
        {
            return "剩余次数：不限";
        }

        return $"剩余次数：{preview.RemainingUses}";
    }
}
