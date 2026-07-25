using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Brushes = System.Windows.Media.Brushes;
using HorizontalAlignment = System.Windows.HorizontalAlignment;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void AddFleetLog(string type, string title, string detail)
    {
        if (!_hasFleet)
        {
            return;
        }

        var row = new FleetEventLogRow(
            Guid.NewGuid().ToString("N"),
            DateTimeOffset.Now,
            type,
            SanitizeFleetEventText(title),
            SanitizeFleetEventText(detail));
        var previous = _allFleetEventLogs.FirstOrDefault();
        if (previous is not null &&
            previous.Type.Equals(row.Type, StringComparison.Ordinal) &&
            previous.Title.Equals(row.Title, StringComparison.Ordinal) &&
            previous.Detail.Equals(row.Detail, StringComparison.Ordinal))
        {
            _allFleetEventLogs[0] = previous with
            {
                EndTimestamp = row.Timestamp,
                OccurrenceCount = Math.Max(1, previous.OccurrenceCount) + 1
            };
        }
        else
        {
            _allFleetEventLogs.Insert(0, row);
        }
        ApplyFleetEventLogFilter();
        RefreshFleetEventCommandCenter();
        RefreshFleetNotificationCenter();
        SaveCurrentConfig();
    }

    private void ApplyFleetEventLogFilter()
    {
        if (FleetLogFilterBox is null)
        {
            return;
        }

        var selectedType = "All";
        if (FleetLogFilterBox.SelectedItem is ComboBoxItem { Tag: string tag })
        {
            selectedType = tag;
        }

        var query = FleetLogSearchBox?.Text.Trim() ?? "";
        var canDeleteLogs = CanCurrentUserDeleteFleetLogs();
        var rows = _allFleetEventLogs
            .Where(row => EnableFleetActionManagementUi || !IsFleetActionManagementLog(row))
            .Where(row => selectedType.Equals("All", StringComparison.OrdinalIgnoreCase) ||
                           row.Type.Equals(selectedType, StringComparison.OrdinalIgnoreCase))
            .Where(row => string.IsNullOrWhiteSpace(query) ||
                          SanitizeFleetEventText(row.Title).Contains(query, StringComparison.OrdinalIgnoreCase) ||
                          SanitizeFleetEventText(row.Detail).Contains(query, StringComparison.OrdinalIgnoreCase))
            .OrderByDescending(row => row.EffectiveEndTimestamp)
            .ToArray();

        _fleetEventLogs.Clear();
        foreach (var row in rows)
        {
            _fleetEventLogs.Add(new FleetEventLogRow(
                row.Id,
                row.Timestamp,
                row.Type,
                SanitizeFleetEventText(row.Title),
                SanitizeFleetEventText(row.Detail),
                canDeleteLogs,
                row.EndTimestamp,
                row.OccurrenceCount));
        }

        if (FleetLogEmptyText is not null)
        {
            FleetLogEmptyText.Visibility = _fleetEventLogs.Count == 0
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        RefreshFleetEventTimeline();
    }

    private void RefreshFleetEventCommandCenter()
    {
        if (FleetEventsTaskTitleText is null)
        {
            return;
        }

        var hasTask = !string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle);
        var localResponse = GetLocalInstantTaskResponse();
        var responseStats = GetCurrentTaskResponseStats();
        var confirmedCount = responseStats.ConfirmedCount;
        var readyCount = responseStats.ReadyCount;
        var unableCount = responseStats.UnableCount;
        var onlineMembers = _players.Count(player => IsOnlineStatus(player.SharedOnlineStatusValue));
        var respondedCount = responseStats.RespondedCount;
        var pendingCount = hasTask ? Math.Max(0, onlineMembers - respondedCount) : onlineMembers;

        if (FleetEventsConfirmedCountText is not null)
        {
            FleetEventsConfirmedCountText.Text = confirmedCount.ToString(CultureInfo.InvariantCulture);
        }

        if (FleetEventsReadyCountText is not null)
        {
            FleetEventsReadyCountText.Text = readyCount.ToString(CultureInfo.InvariantCulture);
        }

        if (FleetEventsUnableCountText is not null)
        {
            FleetEventsUnableCountText.Text = unableCount.ToString(CultureInfo.InvariantCulture);
        }

        if (FleetEventsPendingCountText is not null)
        {
            FleetEventsPendingCountText.Text = pendingCount.ToString(CultureInfo.InvariantCulture);
        }

        FleetEventsConfirmButton.IsEnabled = hasTask &&
            !localResponse.Equals("确认收到", StringComparison.OrdinalIgnoreCase) &&
            !localResponse.Equals("已确认", StringComparison.OrdinalIgnoreCase) &&
            !localResponse.Equals("已就位", StringComparison.OrdinalIgnoreCase);
        FleetEventsReadyButton.IsEnabled = hasTask && !localResponse.Equals("已就位", StringComparison.OrdinalIgnoreCase) && !localResponse.Equals("无法参与", StringComparison.OrdinalIgnoreCase);
        FleetEventsUnableButton.IsEnabled = hasTask && !localResponse.Equals("无法参与", StringComparison.OrdinalIgnoreCase);

        RefreshFleetEventActionPlans();
    }

    private void RefreshFleetEventTimeline()
    {
    }

    private void RefreshFleetEventActionPlans()
    {
        var visiblePlans = GetVisibleActionPlans().ToArray();
        var futurePlans = visiblePlans
            .Where(plan => plan.IsPublished)
            .OrderBy(plan => plan.StartTime)
            .ToArray();
        var pastPlans = visiblePlans
            .Where(plan => !plan.IsPublished)
            .OrderByDescending(plan => plan.StartTime)
            .ToArray();
        var actionablePlans = futurePlans
            .Where(plan => plan.IsJoinable)
            .ToArray();

        _fleetEventActionPlanRows.Clear();
        foreach (var plan in futurePlans.Take(10))
        {
            _fleetEventActionPlanRows.Add(BuildFleetEventActionPlanRow(plan));
        }

        RefreshFleetEventFocus(visiblePlans, futurePlans, pastPlans);
        RefreshFleetEventTodoList();
        RefreshFleetEventFuturePlanList(futurePlans);
        RefreshFleetEventPastPlanList(pastPlans);

        if (FleetEventsPlanSummaryText is not null)
        {
            var joinableCount = actionablePlans.Count(plan => !_joinedActionPlanIds.Contains(plan.Id));
            FleetEventsPlanSummaryText.Text = futurePlans.Length == 0
                ? "暂无即将开始的行动"
                : $"{futurePlans.Length.ToString(CultureInfo.InvariantCulture)} 个即将开始，{joinableCount.ToString(CultureInfo.InvariantCulture)} 个可预约";
        }

        if (FleetEventsPlanTitleText is not null)
        {
            FleetEventsPlanTitleText.Text = "即将开始";
        }

        if (FleetEventsPlanHintText is not null)
        {
            FleetEventsPlanHintText.Text = "可预约或取消预约";
        }
    }

    private FleetEventActionPlanRow BuildFleetEventActionPlanRow(FleetActionPlanRow plan)
    {
        var joined = _joinedActionPlanIds.Contains(plan.Id);
        var canAct = plan.IsJoinable;
        var actionText = plan.IsJoinable
            ? joined ? "取消预约" : "预约行动"
            : plan.EffectiveStatus switch
            {
                "Reached" => "已到时",
                "Completed" => "已完成",
                "Canceled" => "已取消",
                _ => "不可参与"
            };
        return new FleetEventActionPlanRow(
            plan.Id,
            string.IsNullOrWhiteSpace(plan.Title) ? "未命名行动" : plan.Title,
            string.IsNullOrWhiteSpace(plan.Content) ? "暂无行动说明" : plan.Content,
            plan.StartTime.ToString("MM-dd HH:mm", CultureInfo.InvariantCulture),
            plan.ParticipantCountText.Replace("参与 / ", "", StringComparison.OrdinalIgnoreCase),
            plan.StatusText.Replace("状态 / ", "", StringComparison.OrdinalIgnoreCase),
            actionText,
            canAct,
            plan.StatusBrush);
    }

    private void RefreshFleetEventFocus(
        IReadOnlyCollection<FleetActionPlanRow> visiblePlans,
        IReadOnlyCollection<FleetActionPlanRow> futurePlans,
        IReadOnlyCollection<FleetActionPlanRow> pastPlans)
    {
        var hasTask = !string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle);
        var localResponse = GetLocalInstantTaskResponse();
        var selectedPlan = visiblePlans.FirstOrDefault(plan =>
            plan.Id.Equals(_selectedFleetEventFocusPlanId, StringComparison.OrdinalIgnoreCase));

        if (selectedPlan is not null)
        {
            ApplyFleetEventPlanFocus(selectedPlan);
            return;
        }

        if (hasTask)
        {
            ApplyFleetEventTaskFocus(localResponse);
            return;
        }

        var actionablePlan = futurePlans.FirstOrDefault(plan => plan.IsJoinable && !_joinedActionPlanIds.Contains(plan.Id));
        if (actionablePlan is not null)
        {
            ApplyFleetEventPlanFocus(actionablePlan);
            return;
        }

        var futurePlan = futurePlans.FirstOrDefault();
        if (futurePlan is not null)
        {
            ApplyFleetEventPlanFocus(futurePlan);
            return;
        }

        var pastPlan = pastPlans.FirstOrDefault();
        if (pastPlan is not null)
        {
            ApplyFleetEventPlanFocus(pastPlan);
            return;
        }

        ApplyFleetEventEmptyFocus();
    }

    private void ApplyFleetEventTaskFocus(string localResponse)
    {
        if (FleetEventsFocusKindText is not null)
        {
            FleetEventsFocusKindText.Text = "当前行动";
        }

        FleetEventsTaskTitleText.Text = string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle)
            ? "暂无当前行动"
            : _fleetCurrentTaskTitle;
        FleetEventsTaskStateBadgeText.Text = string.IsNullOrWhiteSpace(localResponse) ? "待确认" : localResponse;
        var taskInfo = ParseFleetTaskBriefInfo(_fleetCurrentTaskBrief);
        FleetEventsTaskSummaryText.Text = BuildCurrentTaskNotificationDetail();
        FleetEventsTaskParticipantsText.Text = NormalizeOptionalField(_fleetCurrentTaskParticipants);
        FleetEventsTaskRallyText.Text = NormalizeOptionalField(_fleetCurrentTaskRally);
        FleetEventsTaskShipText.Text = string.IsNullOrWhiteSpace(_fleetCurrentTaskShip)
            ? FormatTaskConditionSummary(taskInfo)
            : $"{_fleetCurrentTaskShip} / {FormatTaskConditionSummary(taskInfo)}";
        FleetEventsTaskPublishedText.Text = _fleetCurrentTaskTime is not null
            ? _fleetCurrentTaskTime.Value.ToString("MM-dd HH:mm")
            : "等待发布";
        if (FleetEventsTaskStageText is not null)
        {
            FleetEventsTaskStageText.Text = localResponse;
        }
        ApplyFleetEventFocusVisual(localResponse);

        if (FleetEventsFeedbackTitleText is not null)
        {
            FleetEventsFeedbackTitleText.Text = "我的行动状态";
        }

        if (FleetEventsFeedbackStatsPanel is not null)
        {
            FleetEventsFeedbackStatsPanel.Visibility = Visibility.Visible;
        }

        FleetEventsMemberStatusText.Text = GetFleetEventResponseGuidance(localResponse);
        if (FleetEventsMemberActionPanel is not null)
        {
            FleetEventsMemberActionPanel.Visibility = Visibility.Visible;
        }
    }

    private void ApplyFleetEventPlanFocus(FleetActionPlanRow plan)
    {
        var joined = _joinedActionPlanIds.Contains(plan.Id);
        if (FleetEventsFocusKindText is not null)
        {
            FleetEventsFocusKindText.Text = plan.IsPublished ? "预约行动" : "过往事件";
        }

        FleetEventsTaskTitleText.Text = string.IsNullOrWhiteSpace(plan.Title) ? "未命名行动" : plan.Title;
        FleetEventsTaskStateBadgeText.Text = plan.IsPublished
            ? joined ? "已预约" : "可预约"
            : plan.StatusText.Replace("状态 / ", "", StringComparison.OrdinalIgnoreCase);
        FleetEventsTaskSummaryText.Text = string.IsNullOrWhiteSpace(plan.Content)
            ? "暂无行动说明。"
            : plan.Content;
        FleetEventsTaskParticipantsText.Text = joined ? "我已预约" : plan.IsJoinable ? "可预约" : "不可参与";
        FleetEventsTaskRallyText.Text = "预约行动";
        FleetEventsTaskShipText.Text = plan.NotifyMembers ? "通知开启" : "通知关闭";
        FleetEventsTaskPublishedText.Text = plan.StartTime.ToString("MM-dd HH:mm", CultureInfo.InvariantCulture);
        if (FleetEventsTaskStageText is not null)
        {
            FleetEventsTaskStageText.Text = plan.StatusText.Replace("状态 / ", "", StringComparison.OrdinalIgnoreCase);
        }
        ApplyFleetEventFocusVisual(plan.IsPublished ? (joined ? "已预约" : "可预约") : "过往事件");

        if (FleetEventsFeedbackTitleText is not null)
        {
            FleetEventsFeedbackTitleText.Text = "预约状态";
        }

        if (FleetEventsFeedbackStatsPanel is not null)
        {
            FleetEventsFeedbackStatsPanel.Visibility = Visibility.Collapsed;
        }

        FleetEventsMemberStatusText.Text = plan.IsJoinable
            ? joined ? "你已预约此行动，可在列表中取消预约。" : "这个行动可以预约。"
            : "此行动已不可预约。";
        if (FleetEventsMemberActionPanel is not null)
        {
            FleetEventsMemberActionPanel.Visibility = Visibility.Collapsed;
        }
    }

    private void ApplyFleetEventEmptyFocus()
    {
        if (FleetEventsFocusKindText is not null)
        {
            FleetEventsFocusKindText.Text = "行动焦点";
        }

        FleetEventsTaskTitleText.Text = "暂无待处理事项";
        FleetEventsTaskStateBadgeText.Text = "待命";
        FleetEventsTaskSummaryText.Text = "当前没有需要你回应的行动。指挥台创建行动后会显示在这里。";
        FleetEventsTaskParticipantsText.Text = "等待发布";
        FleetEventsTaskRallyText.Text = "未指定";
        FleetEventsTaskShipText.Text = "未指定";
        FleetEventsTaskPublishedText.Text = "待定";
        if (FleetEventsTaskStageText is not null)
        {
            FleetEventsTaskStageText.Text = "待命";
        }
        ApplyFleetEventFocusVisual("待命");

        if (FleetEventsFeedbackTitleText is not null)
        {
            FleetEventsFeedbackTitleText.Text = "我的行动状态";
        }

        if (FleetEventsFeedbackStatsPanel is not null)
        {
            FleetEventsFeedbackStatsPanel.Visibility = Visibility.Collapsed;
        }

        FleetEventsMemberStatusText.Text = "没有需要回应的事项";
        if (FleetEventsMemberActionPanel is not null)
        {
            FleetEventsMemberActionPanel.Visibility = Visibility.Collapsed;
        }
    }

    private void RefreshFleetEventTodoList()
    {
        if (FleetEventsTodoItems is null || FleetEventsTodoEmptyText is null)
        {
            return;
        }

        FleetEventsTodoItems.Children.Clear();
        var count = 0;
        var hasTask = !string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle);
        var localResponse = GetLocalInstantTaskResponse();
        if (hasTask && NeedsCurrentTaskResponse(localResponse))
        {
            AddFleetEventTaskTodoRow(localResponse);
            count++;
        }

        FleetEventsTodoEmptyText.Visibility = count == 0 ? Visibility.Visible : Visibility.Collapsed;
        if (FleetEventsTodoSummaryText is not null)
        {
            FleetEventsTodoSummaryText.Text = count == 0
                ? "当前没有行动需要回应。"
                : "显示当前行动与你的回应状态。";
        }
    }

    private void RefreshFleetEventFuturePlanList(IReadOnlyList<FleetActionPlanRow> futurePlans)
    {
        if (FleetEventsFuturePlanItems is null || FleetEventActionPlanEmptyText is null)
        {
            return;
        }

        FleetEventsFuturePlanItems.Children.Clear();
        foreach (var plan in futurePlans.Take(8))
        {
            AddFleetEventPlanRow(FleetEventsFuturePlanItems, plan, includePrimaryAction: true);
        }

        FleetEventActionPlanEmptyText.Visibility = futurePlans.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void RefreshFleetEventPastPlanList(IReadOnlyList<FleetActionPlanRow> pastPlans)
    {
        if (FleetEventsPastPlanItems is null || FleetEventsPastEmptyText is null)
        {
            return;
        }

        FleetEventsPastPlanItems.Children.Clear();
        var decisivePastPlans = pastPlans
            .Where(IsDecisiveFleetActionPlanHistory)
            .ToArray();
        var eventLogs = _allFleetEventLogs
            .Where(IsDecisiveFleetEventLog)
            .ToArray();
        var historyItems = new List<(DateTimeOffset Timestamp, FleetActionPlanRow? Plan, FleetEventLogRow? Log)>();
        foreach (var plan in decisivePastPlans)
        {
            historyItems.Add((GetFleetActionPlanHistoryTimestamp(plan), plan, null));
        }

        foreach (var log in eventLogs)
        {
            historyItems.Add((log.Timestamp, null, log));
        }

        var visibleItems = historyItems
            .OrderByDescending(item => item.Timestamp)
            .Take(8)
            .ToArray();

        foreach (var item in visibleItems)
        {
            if (item.Plan is not null)
            {
                AddFleetEventPlanRow(FleetEventsPastPlanItems, item.Plan, includePrimaryAction: false);
            }
            else if (item.Log is not null)
            {
                AddFleetEventLogRow(FleetEventsPastPlanItems, item.Log);
            }
        }

        FleetEventsPastEmptyText.Visibility = visibleItems.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        if (FleetEventsPastSummaryText is not null)
        {
            var totalCount = historyItems.Count;
            FleetEventsPastSummaryText.Text = totalCount == 0
                ? "行动的发布、完成、取消或删除会留在这里。"
                : $"最近 {Math.Min(8, totalCount).ToString(CultureInfo.InvariantCulture)} 条决定性事件";
        }
    }

    private static bool IsDecisiveFleetActionPlanHistory(FleetActionPlanRow plan)
    {
        return plan.IsCanceled || plan.IsCompleted;
    }

    private static bool IsDecisiveFleetEventLog(FleetEventLogRow log)
    {
        var title = log.Title.Trim();
        if (log.Type.Equals("任务", StringComparison.OrdinalIgnoreCase))
        {
            return ContainsAny(title, "发布", "完成", "删除", "取消");
        }

        if (log.Type.Equals("计划", StringComparison.OrdinalIgnoreCase))
        {
            if (ContainsAny(title, "接取", "预约"))
            {
                return false;
            }

            return ContainsAny(title, "创建", "发布", "完成", "删除", "取消", "关闭");
        }

        return false;
    }

    private static bool IsPersonalPlanParticipationLog(FleetEventLogRow log)
    {
        return IsPersonalPlanParticipationLog(log.Type, log.Title);
    }

    private static bool IsPersonalPlanParticipationLog(string? type, string? title)
    {
        if (!string.Equals(type, "计划", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        return ContainsAny(title ?? "", "接取", "预约");
    }

    private static string SanitizeFleetEventText(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return text ?? "";
        }

        return EmailAddressRegex.Replace(text, "未知玩家");
    }

    private static bool ContainsAny(string value, params string[] keywords)
    {
        return keywords.Any(keyword => value.Contains(keyword, StringComparison.OrdinalIgnoreCase));
    }

    private static DateTimeOffset GetFleetActionPlanHistoryTimestamp(FleetActionPlanRow plan)
    {
        if (plan.CanceledAt is not null)
        {
            return plan.CanceledAt.Value;
        }

        if (plan.CompletedAt is not null)
        {
            return plan.CompletedAt.Value;
        }

        if (plan.ReachedAt is not null)
        {
            return plan.ReachedAt.Value;
        }

        return new DateTimeOffset(DateTime.SpecifyKind(plan.StartTime, DateTimeKind.Local));
    }

    private static bool NeedsCurrentTaskResponse(string response)
    {
        return !response.Equals("已就位", StringComparison.OrdinalIgnoreCase) &&
               !response.Equals("无法参与", StringComparison.OrdinalIgnoreCase);
    }

    private static string GetFleetEventResponseAccent(string response)
    {
        if (response.Equals("已就位", StringComparison.OrdinalIgnoreCase))
        {
            return "#42CF7C";
        }

        if (response.Equals("无法参与", StringComparison.OrdinalIgnoreCase))
        {
            return "#D9A23B";
        }

        if (response.Equals("确认收到", StringComparison.OrdinalIgnoreCase) ||
            response.Equals("已确认", StringComparison.OrdinalIgnoreCase))
        {
            return "#29AFFF";
        }

        if (response.Equals("可接取", StringComparison.OrdinalIgnoreCase) ||
            response.Equals("可预约", StringComparison.OrdinalIgnoreCase) ||
            response.Equals("已预约", StringComparison.OrdinalIgnoreCase))
        {
            return "#29AFFF";
        }

        if (response.Equals("过往事件", StringComparison.OrdinalIgnoreCase) ||
            response.Equals("待命", StringComparison.OrdinalIgnoreCase))
        {
            return "#91A5B5";
        }

        return "#D9A23B";
    }

    private static string GetFleetEventResponseGuidance(string response)
    {
        if (response.Equals("已就位", StringComparison.OrdinalIgnoreCase))
        {
            return "你已标记就位。任务信息仍可查看，情况变化时可改为无法参与。";
        }

        if (response.Equals("无法参与", StringComparison.OrdinalIgnoreCase))
        {
            return "你已反馈无法参与。任务仍保留，方便查看要求。";
        }

        if (response.Equals("确认收到", StringComparison.OrdinalIgnoreCase) ||
            response.Equals("已确认", StringComparison.OrdinalIgnoreCase))
        {
            return "你已确认收到。到达集结点后可以标记就位。";
        }

        return "请先确认收到；到达集结点后标记就位，无法参加时及时反馈。";
    }

    private void ApplyFleetEventFocusVisual(string state)
    {
        var accentHex = GetFleetEventResponseAccent(state);
        var panelBackground = state.Equals("已就位", StringComparison.OrdinalIgnoreCase)
            ? "#081D16"
            : state.Equals("无法参与", StringComparison.OrdinalIgnoreCase)
                ? "#1C170D"
                : state.Equals("确认收到", StringComparison.OrdinalIgnoreCase) ||
                  state.Equals("已确认", StringComparison.OrdinalIgnoreCase) ||
                  state.Equals("可接取", StringComparison.OrdinalIgnoreCase) ||
                  state.Equals("可预约", StringComparison.OrdinalIgnoreCase) ||
                  state.Equals("已预约", StringComparison.OrdinalIgnoreCase)
                    ? "#091A26"
                    : "#07131D";
        var badgeBackground = state.Equals("已就位", StringComparison.OrdinalIgnoreCase)
            ? "#102A1D"
            : state.Equals("无法参与", StringComparison.OrdinalIgnoreCase)
                ? "#2A2415"
                : "#102B3D";

        if (FleetEventsFocusBanner is not null)
        {
            FleetEventsFocusBanner.Background = CreateSolidBrush(panelBackground);
            FleetEventsFocusBanner.BorderBrush = CreateSolidBrush(accentHex);
        }

        if (FleetEventsTaskStateBadge is not null)
        {
            FleetEventsTaskStateBadge.Background = CreateSolidBrush(badgeBackground);
            FleetEventsTaskStateBadge.BorderBrush = CreateSolidBrush(accentHex);
        }

        if (FleetEventsTaskStateBadgeText is not null)
        {
            FleetEventsTaskStateBadgeText.Foreground = CreateSolidBrush(accentHex);
        }

        if (FleetEventsFeedbackCard is not null)
        {
            FleetEventsFeedbackCard.Background = CreateSolidBrush(panelBackground);
            FleetEventsFeedbackCard.BorderBrush = CreateSolidBrush(accentHex);
        }
    }

    private void AddFleetEventTaskTodoRow(string localResponse)
    {
        var actions = new List<FrameworkElement>
        {
            CreateFleetEventSmallButton("查看", "#28506A", (_, _) =>
            {
                _selectedFleetEventFocusPlanId = "";
                RefreshFleetEventCommandCenter();
            })
        };

        var accentHex = GetFleetEventResponseAccent(localResponse);
        AddFleetEventRow(
            FleetEventsTodoItems,
            "当前行动",
            _fleetCurrentTaskTitle,
            BuildCurrentTaskNotificationDetail(),
            _fleetCurrentTaskTime is null ? "发布时间待定" : _fleetCurrentTaskTime.Value.ToString("MM-dd HH:mm", CultureInfo.InvariantCulture),
            string.IsNullOrWhiteSpace(localResponse) ? "待确认" : localResponse,
            accentHex,
            actions);
    }

    private void AddFleetEventPlanRow(System.Windows.Controls.Panel panel, FleetActionPlanRow plan, bool includePrimaryAction)
    {
        var row = BuildFleetEventActionPlanRow(plan);
        var actions = new List<FrameworkElement>
        {
            CreateFleetEventSmallButton("查看", "#28506A", (_, _) =>
            {
                _selectedFleetEventFocusPlanId = plan.Id;
                _selectedActionPlanId = plan.Id;
                RefreshFleetEventCommandCenter();
            })
        };

        if (includePrimaryAction)
        {
            var actionButton = CreateFleetEventSmallButton(row.ActionText, "#28506A", null);
            actionButton.IsEnabled = row.CanAct;
            actionButton.DataContext = row;
            actionButton.Click += FleetEventActionPlanJoinButton_Click;
            actions.Add(actionButton);
        }

        AddFleetEventRow(
            panel,
            plan.IsPublished ? (_joinedActionPlanIds.Contains(plan.Id) ? "已预约行动" : "可预约行动") : "行动记录",
            row.Title,
            row.Summary,
            row.TimeText,
            row.StatusText,
            GetBrushHex(row.AccentBrush, "#29AFFF"),
            actions);
    }

    private void AddFleetEventLogRow(System.Windows.Controls.Panel panel, FleetEventLogRow log)
    {
        var safeTitle = SanitizeFleetEventText(log.Title);
        var safeDetail = SanitizeFleetEventText(log.Detail);
        AddFleetEventRow(
            panel,
            "行动记录",
            safeTitle,
            safeDetail,
            log.Timestamp.ToLocalTime().ToString("MM-dd HH:mm", CultureInfo.InvariantCulture),
            log.Type,
            GetBrushHex(log.AccentBrush, log.Type.Equals("任务", StringComparison.OrdinalIgnoreCase) ? "#29AFFF" : "#D9A23B"),
            Array.Empty<FrameworkElement>());
    }

    private void AddFleetEventRow(
        System.Windows.Controls.Panel panel,
        string label,
        string title,
        string detail,
        string meta,
        string status,
        string accentHex,
        IReadOnlyList<FrameworkElement> actions)
    {
        var border = new Border
        {
            Background = CreateSolidBrush("#0A1823"),
            BorderBrush = CreateSolidBrush("#173447"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Margin = new Thickness(0, 0, 0, 7),
            Padding = new Thickness(0)
        };

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(3) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(130) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(112) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        grid.Children.Add(new Border { Background = CreateSolidBrush(accentHex) });

        var textStack = new StackPanel
        {
            Margin = new Thickness(12, 8, 12, 8)
        };
        textStack.Children.Add(new TextBlock
        {
            Text = label,
            Foreground = CreateSolidBrush("#637A89"),
            FontSize = 10,
            FontWeight = FontWeights.SemiBold
        });
        textStack.Children.Add(new TextBlock
        {
            Text = string.IsNullOrWhiteSpace(title) ? "未命名事项" : title,
            Foreground = FindBrush("PrimaryTextBrush", Brushes.AliceBlue),
            FontWeight = FontWeights.SemiBold,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Margin = new Thickness(0, 3, 0, 0)
        });
        textStack.Children.Add(new TextBlock
        {
            Text = string.IsNullOrWhiteSpace(detail) ? "暂无说明" : detail,
            Foreground = FindBrush("MutedTextBrush", Brushes.LightSlateGray),
            FontSize = 11,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Margin = new Thickness(0, 3, 0, 0)
        });
        Grid.SetColumn(textStack, 1);
        grid.Children.Add(textStack);

        var metaStack = new StackPanel
        {
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 12, 0)
        };
        metaStack.Children.Add(new TextBlock { Text = "时间", Style = (Style)FindResource("HudCaptionText") });
        metaStack.Children.Add(new TextBlock
        {
            Text = meta,
            Foreground = FindBrush("PrimaryTextBrush", Brushes.AliceBlue),
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 3, 0, 0)
        });
        Grid.SetColumn(metaStack, 2);
        grid.Children.Add(metaStack);

        var statusBorder = new Border
        {
            Background = CreateSolidBrush("#102536"),
            BorderBrush = CreateSolidBrush(accentHex),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Padding = new Thickness(8, 2, 8, 2),
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 12, 0),
            Child = new TextBlock
            {
                Text = status,
                Foreground = CreateSolidBrush(accentHex),
                FontSize = 11,
                FontWeight = FontWeights.SemiBold,
                TextTrimming = TextTrimming.CharacterEllipsis
            }
        };
        Grid.SetColumn(statusBorder, 3);
        grid.Children.Add(statusBorder);

        var actionStack = new StackPanel
        {
            Orientation = System.Windows.Controls.Orientation.Horizontal,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 10, 0)
        };
        foreach (var action in actions)
        {
            actionStack.Children.Add(action);
        }

        Grid.SetColumn(actionStack, 4);
        grid.Children.Add(actionStack);

        border.Child = grid;
        panel.Children.Add(border);
    }

    private System.Windows.Controls.Button CreateFleetEventSmallButton(string text, string borderHex, RoutedEventHandler? handler)
    {
        var button = new System.Windows.Controls.Button
        {
            Content = text,
            Style = (Style)FindResource("SecondaryButton"),
            Height = 28,
            MinWidth = 72,
            Margin = new Thickness(0, 0, 6, 0),
            Padding = new Thickness(10, 0, 10, 0)
        };

        if (handler is not null)
        {
            button.Click += handler;
        }

        return button;
    }

    private static string GetBrushHex(System.Windows.Media.Brush brush, string fallback)
    {
        if (brush is SolidColorBrush solid)
        {
            return $"#{solid.Color.R:X2}{solid.Color.G:X2}{solid.Color.B:X2}";
        }

        return fallback;
    }

    private string GetLocalInstantTaskResponse()
    {
        if (string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle))
        {
            return "待命";
        }

        var actor = GetLocalFleetActorDisplayName();
        var latestEventResponse = GetLatestCurrentTaskResponseForActor(actor);
        if (!string.IsNullOrWhiteSpace(latestEventResponse))
        {
            return latestEventResponse;
        }

        var key = GetCurrentFleetOrderKey();
        if (!string.IsNullOrWhiteSpace(key) &&
            _fleetInstantTaskResponses.TryGetValue(key, out var response) &&
            !string.IsNullOrWhiteSpace(response))
        {
            return response;
        }

        return "待确认";
    }

    private int CountCurrentTaskEvent(string eventTitle)
    {
        var stats = GetCurrentTaskResponseStats();
        if (eventTitle.Equals("确认收到", StringComparison.OrdinalIgnoreCase) ||
            eventTitle.Equals("已确认", StringComparison.OrdinalIgnoreCase))
        {
            return stats.ConfirmedCount;
        }

        if (eventTitle.Equals("已就位", StringComparison.OrdinalIgnoreCase))
        {
            return stats.ReadyCount;
        }

        return eventTitle.Equals("无法参与", StringComparison.OrdinalIgnoreCase)
            ? stats.UnableCount
            : 0;
    }

    private FleetInstantTaskResponseStats GetCurrentTaskResponseStats()
    {
        if (string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle))
        {
            return FleetInstantTaskResponseStats.Empty;
        }

        var latestByActor = new Dictionary<string, (DateTimeOffset Timestamp, string Response)>(StringComparer.OrdinalIgnoreCase);
        foreach (var row in _allFleetEventLogs)
        {
            if (!TryReadCurrentTaskResponse(row, out var actor, out var response))
            {
                continue;
            }

            var actorKey = GetFleetTaskResponseActorKey(actor);
            if (!latestByActor.TryGetValue(actorKey, out var existing) ||
                row.Timestamp > existing.Timestamp)
            {
                latestByActor[actorKey] = (row.Timestamp, response);
            }
        }

        var confirmed = 0;
        var ready = 0;
        var unable = 0;
        foreach (var (_, response) in latestByActor.Values)
        {
            if (response.Equals("已就位", StringComparison.OrdinalIgnoreCase))
            {
                confirmed++;
                ready++;
            }
            else if (response.Equals("无法参与", StringComparison.OrdinalIgnoreCase))
            {
                unable++;
            }
            else if (response.Equals("确认收到", StringComparison.OrdinalIgnoreCase))
            {
                confirmed++;
            }
        }

        return new FleetInstantTaskResponseStats(confirmed, ready, unable, latestByActor.Count);
    }

    private string? GetLatestCurrentTaskResponseForActor(string actor)
    {
        if (string.IsNullOrWhiteSpace(actor))
        {
            return null;
        }

        var actorKey = GetFleetTaskResponseActorKey(actor);
        return _allFleetEventLogs
            .Where(row => TryReadCurrentTaskResponse(row, out var rowActor, out _) &&
                          GetFleetTaskResponseActorKey(rowActor).Equals(actorKey, StringComparison.OrdinalIgnoreCase))
            .OrderByDescending(row => row.Timestamp)
            .Select(row =>
            {
                TryReadCurrentTaskResponse(row, out _, out var response);
                return response;
            })
            .FirstOrDefault();
    }

    private string GetFleetTaskResponseActorKey(string actor)
    {
        var normalizedActor = NormalizeDisplayIdentityPart(actor);
        if (string.IsNullOrWhiteSpace(normalizedActor))
        {
            return actor.Trim();
        }

        var actorAliases = EnumerateIdentityAliases(normalizedActor, null)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var member in _fleetMemberRows)
        {
            var memberAliases = EnumerateIdentityAliases(member.GameName, member.Callsign)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            if (memberAliases.Count == 0 || !memberAliases.Overlaps(actorAliases))
            {
                continue;
            }

            var canonical = NormalizeDisplayIdentityPart(member.GameName);
            return string.IsNullOrWhiteSpace(canonical)
                ? FormatCommanderName(member.Callsign, member.GameName)
                : canonical;
        }

        return normalizedActor;
    }

    private bool TryReadCurrentTaskResponse(FleetEventLogRow row, out string actor, out string response)
    {
        actor = "";
        response = "";
        var detail = row.Detail ?? "";

        if (string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle) ||
            !string.Equals(row.Type, "任务", StringComparison.OrdinalIgnoreCase) ||
            !detail.Contains(_fleetCurrentTaskTitle, StringComparison.OrdinalIgnoreCase) ||
            IsOlderThanCurrentTask(row.Timestamp))
        {
            return false;
        }

        var marker = "";
        if (string.Equals(row.Title, "确认收到", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(row.Title, "已确认", StringComparison.OrdinalIgnoreCase))
        {
            response = "确认收到";
            marker = "已确认";
        }
        else if (string.Equals(row.Title, "已就位", StringComparison.OrdinalIgnoreCase))
        {
            response = "已就位";
            marker = "已就位";
        }
        else if (string.Equals(row.Title, "无法参与", StringComparison.OrdinalIgnoreCase))
        {
            response = "无法参与";
            marker = "标记无法参与";
        }

        if (string.IsNullOrWhiteSpace(marker))
        {
            return false;
        }

        var markerIndex = detail.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
        if (markerIndex <= 0)
        {
            return false;
        }

        actor = detail[..markerIndex].Trim();
        return !string.IsNullOrWhiteSpace(actor);
    }

    private bool IsOlderThanCurrentTask(DateTimeOffset eventTimestamp)
    {
        if (_fleetCurrentTaskTime is null)
        {
            return false;
        }

        var currentTaskTime = DateTime.SpecifyKind(_fleetCurrentTaskTime.Value, DateTimeKind.Local);
        var taskStart = new DateTimeOffset(currentTaskTime).AddSeconds(-10);
        return eventTimestamp < taskStart;
    }

    private static string GetFleetEventTaskStageText(bool hasTask, int confirmedCount, int readyCount, int unableCount)
    {
        if (!hasTask)
        {
            return "未发布";
        }

        if (readyCount > 0)
        {
            return "集结中";
        }

        if (confirmedCount > 0 || unableCount > 0)
        {
            return "确认中";
        }

        return "发布中";
    }

    private void FleetLogFilter_Changed(object sender, EventArgs e)
    {
        ApplyFleetEventLogFilter();
    }

    private async void DeleteFleetLogEntry_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not string logId || string.IsNullOrWhiteSpace(logId))
        {
            return;
        }

        if (!CanCurrentUserDeleteFleetLogs())
        {
            FleetMemberManagementStatusText.Text = "当前账号没有删除舰队日志的权限。";
            return;
        }

        var deleted = await PushFleetMutationAsync(
            "api/fleets/logs/delete",
            new FleetLogDeleteRequest(_fleetCode, logId),
            "舰队日志已删除并同步。",
            "舰队日志删除失败",
            silent: false);
        if (!deleted)
        {
            return;
        }

        await PullNetworkSnapshotsAsync(silent: true);
        ApplyFleetEventLogFilter();
        RefreshFleetEventCommandCenter();
        RefreshFleetNotificationCenter();
        SaveCurrentConfig();
    }

    private void PlayersList_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {

    }
}
