using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using StarBridge.Desktop.Theming;
using Brushes = System.Windows.Media.Brushes;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void OpenPublishTaskButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("发布任务需要先登录星海舰桥账号。"))
        {
            return;
        }

        if (!CanCurrentUserPublishTasks())
        {
            PublishTaskValidationText.Text = "当前账号没有发布任务的权限。";
            return;
        }

        OpenPublishTaskPanel();
    }

    private void OpenPublishRallyButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("发布集结点需要先登录星海舰桥账号。"))
        {
            return;
        }

        if (!CanCurrentUserPublishTasks())
        {
            PublishTaskValidationText.Text = "当前账号没有发布集结点的权限。";
            return;
        }

        OpenPublishTaskPanel(rallyOnly: true);
    }

    private static string GetComboBoxText(System.Windows.Controls.ComboBox comboBox, string fallback)
    {
        return comboBox.SelectedItem is ComboBoxItem item
            ? item.Content?.ToString() ?? fallback
            : string.IsNullOrWhiteSpace(comboBox.Text)
                ? fallback
                : comboBox.Text.Trim();
    }

    private static void SelectComboBoxText(System.Windows.Controls.ComboBox comboBox, string value)
    {
        for (var index = 0; index < comboBox.Items.Count; index++)
        {
            if (comboBox.Items[index] is ComboBoxItem item &&
                string.Equals(item.Content?.ToString(), value, StringComparison.OrdinalIgnoreCase))
            {
                comboBox.SelectedIndex = index;
                return;
            }
        }
    }

    private static FleetTaskBriefInfo ParseFleetTaskBriefInfo(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return new FleetTaskBriefInfo();
        }

        var normalized = text.Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n');
        var lines = normalized.Split('\n');
        var headerIndex = Array.FindIndex(lines, line =>
            line.Trim().Equals(FleetTaskMetaHeader, StringComparison.OrdinalIgnoreCase));
        if (headerIndex < 0)
        {
            var brief = NormalizeOptionalField(normalized);
            return new FleetTaskBriefInfo
            {
                Brief = string.Equals(brief, "未指定", StringComparison.OrdinalIgnoreCase) ? "" : brief
            };
        }

        var rawBrief = string.Join(Environment.NewLine, lines.Take(headerIndex))
            .Trim();
        var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var line in lines.Skip(headerIndex + 1))
        {
            var entry = line.Trim().TrimStart('-', '•').Trim();
            if (string.IsNullOrWhiteSpace(entry))
            {
                continue;
            }

            var separatorIndex = entry.IndexOf(':');
            if (separatorIndex < 0)
            {
                separatorIndex = entry.IndexOf(':');
            }

            if (separatorIndex <= 0)
            {
                continue;
            }

            values[entry[..separatorIndex].Trim()] = entry[(separatorIndex + 1)..].Trim();
        }

        static bool IsPositive(string value)
        {
            if (value.Contains("不需要", StringComparison.OrdinalIgnoreCase) ||
                value.Contains("不包含", StringComparison.OrdinalIgnoreCase) ||
                value.Contains("否", StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            return value.Contains("需要", StringComparison.OrdinalIgnoreCase) ||
                   value.Contains("是", StringComparison.OrdinalIgnoreCase) ||
                   value.Contains("包含", StringComparison.OrdinalIgnoreCase);
        }

        return new FleetTaskBriefInfo
        {
            Brief = rawBrief,
            TaskType = values.TryGetValue("任务覆盖面", out var coverage)
                ? NormalizeOptionalField(coverage)
                : values.TryGetValue("类型", out var type)
                    ? NormalizeOptionalField(type)
                    : "自定义",
            Duration = values.TryGetValue("预计时长", out var duration) ? NormalizeOptionalField(duration) : "待定",
            CombatIntensity = values.TryGetValue("战斗强度", out var intensity) ? NormalizeOptionalField(intensity) : "未指定",
            MedicalRequired = values.TryGetValue("医疗床", out var medical) && IsPositive(medical),
            GroundCombat = values.TryGetValue("地面作战", out var ground) && IsPositive(ground),
            Division = values.TryGetValue("分工", out var division) ? NormalizeOptionalField(division) : "未指定",
            HasStructuredMeta = true
        };
    }

    private static string BuildFleetTaskBriefPayload(
        string brief,
        string taskType,
        string duration,
        string combatIntensity,
        bool medicalRequired,
        bool groundCombat)
    {
        var cleanBrief = NormalizeOptionalField(brief);
        if (string.IsNullOrWhiteSpace(cleanBrief) ||
            cleanBrief.Equals("未指定", StringComparison.OrdinalIgnoreCase) ||
            cleanBrief.Equals("简要说明任务目标、行动范围或注意事项。", StringComparison.OrdinalIgnoreCase) ||
            cleanBrief.Equals("说明目标、风险、抵达后要做的事。", StringComparison.OrdinalIgnoreCase))
        {
            cleanBrief = "等待现场指挥补充。";
        }

        return string.Join(Environment.NewLine, new[]
        {
            cleanBrief,
            "",
            FleetTaskMetaHeader,
            $"- 任务覆盖面：{NormalizeOptionalField(taskType)}",
            $"- 预计时长：{NormalizeOptionalField(duration)}",
            $"- 战斗强度：{NormalizeOptionalField(combatIntensity)}",
            $"- 医疗床：{(medicalRequired ? "需要" : "不需要")}",
            $"- 地面作战：{(groundCombat ? "需要" : "不需要")}"
        });
    }

    private static string FormatTaskBriefForDisplay(FleetTaskBriefInfo info)
    {
        return string.IsNullOrWhiteSpace(info.Brief)
            ? "等待现场指挥补充。"
            : info.Brief;
    }

    private static string FormatTaskConditionSummary(FleetTaskBriefInfo info)
    {
        var parts = new List<string>();
        if (!string.IsNullOrWhiteSpace(info.TaskType) &&
            !info.TaskType.Equals("自定义", StringComparison.OrdinalIgnoreCase) &&
            !info.TaskType.Equals("未指定", StringComparison.OrdinalIgnoreCase))
        {
            parts.Add(info.TaskType);
        }

        if (!string.IsNullOrWhiteSpace(info.Duration) && !info.Duration.Equals("待定", StringComparison.OrdinalIgnoreCase))
        {
            parts.Add(info.Duration);
        }

        if (!string.IsNullOrWhiteSpace(info.CombatIntensity) && !info.CombatIntensity.Equals("未指定", StringComparison.OrdinalIgnoreCase))
        {
            parts.Add(info.CombatIntensity);
        }

        if (info.MedicalRequired &&
            !info.TaskType.Contains("医疗", StringComparison.OrdinalIgnoreCase))
        {
            parts.Add("需要医疗床");
        }

        if (info.GroundCombat &&
            !info.TaskType.Contains("地面", StringComparison.OrdinalIgnoreCase))
        {
            parts.Add("地面作战");
        }

        return parts.Count == 0 ? "按现场指挥" : string.Join(" / ", parts);
    }

    private static string FormatTaskDetailText(FleetTaskBriefInfo info)
    {
        var lines = new List<string> { FormatTaskBriefForDisplay(info) };
        var condition = FormatTaskConditionSummary(info);
        if (!string.IsNullOrWhiteSpace(condition) && !condition.Equals("按现场指挥", StringComparison.OrdinalIgnoreCase))
        {
            lines.Add($"任务条件 / {condition}");
        }

        if (!string.IsNullOrWhiteSpace(info.Division) &&
            !info.Division.Equals("未指定", StringComparison.OrdinalIgnoreCase) &&
            !info.Division.Equals("按现场指挥分配", StringComparison.OrdinalIgnoreCase))
        {
            lines.Add($"分工提示 / {info.Division}");
        }

        return string.Join(Environment.NewLine, lines);
    }

    private IEnumerable<(System.Windows.Controls.CheckBox Check, string Label)> GetPublishTaskTypeChecks()
    {
        yield return (PublishTaskTypeGroundCombatCheck, "地面战斗");
        yield return (PublishTaskTypeAirCombatCheck, "空战");
        yield return (PublishTaskTypeEscortCheck, "护航");
        yield return (PublishTaskTypeCargoCheck, "货运");
        yield return (PublishTaskTypeMiningCheck, "采矿");
        yield return (PublishTaskTypeSalvageCheck, "打捞");
        yield return (PublishTaskTypeMedicalCheck, "医疗救援");
        yield return (PublishTaskTypeSearchRescueCheck, "搜救");
        yield return (PublishTaskTypeReconCheck, "侦察扫描");
        yield return (PublishTaskTypeExplorationCheck, "探索");
        yield return (PublishTaskTypeRepairRefuelCheck, "维修补给");
        yield return (PublishTaskTypeRallyCheck, "集结组织");
    }

    private string GetSelectedPublishTaskCoverage()
    {
        var selected = GetPublishTaskTypeChecks()
            .Where(item => item.Check.IsChecked == true)
            .Select(item => item.Label)
            .ToArray();

        return selected.Length == 0 ? "未指定" : string.Join("、", selected);
    }

    private void SetPublishTaskCoverage(string coverage)
    {
        var selected = coverage
            .Split(['?', '/', ',', ','], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        foreach (var (check, label) in GetPublishTaskTypeChecks())
        {
            check.IsChecked = selected.Contains(label) ||
                              selected.Any(value => PublishTaskCoverageMatches(label, value));
        }
    }

    private static bool PublishTaskCoverageMatches(string label, string value)
    {
        if (string.IsNullOrWhiteSpace(value) ||
            value.Equals("未指定", StringComparison.OrdinalIgnoreCase) ||
            value.Equals("自定义", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (value.Equals("战斗", StringComparison.OrdinalIgnoreCase))
        {
            return label.Equals("空战", StringComparison.OrdinalIgnoreCase);
        }

        if (value.Contains("地面", StringComparison.OrdinalIgnoreCase))
        {
            return label.Equals("地面战斗", StringComparison.OrdinalIgnoreCase);
        }

        if (value.Contains("空战", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("航空", StringComparison.OrdinalIgnoreCase))
        {
            return label.Equals("空战", StringComparison.OrdinalIgnoreCase);
        }

        if (value.Contains("护航", StringComparison.OrdinalIgnoreCase))
        {
            return label.Equals("护航", StringComparison.OrdinalIgnoreCase);
        }

        if (value.Contains("运输", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("货运", StringComparison.OrdinalIgnoreCase))
        {
            return label.Equals("货运", StringComparison.OrdinalIgnoreCase);
        }

        if (value.Contains("采矿", StringComparison.OrdinalIgnoreCase))
        {
            return label.Equals("采矿", StringComparison.OrdinalIgnoreCase);
        }

        if (value.Contains("打捞", StringComparison.OrdinalIgnoreCase))
        {
            return label.Equals("打捞", StringComparison.OrdinalIgnoreCase);
        }

        if (value.Contains("医疗", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("救援", StringComparison.OrdinalIgnoreCase))
        {
            return label.Equals("医疗救援", StringComparison.OrdinalIgnoreCase) ||
                   label.Equals("搜救", StringComparison.OrdinalIgnoreCase);
        }

        if (value.Contains("侦察", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("扫描", StringComparison.OrdinalIgnoreCase))
        {
            return label.Equals("侦察扫描", StringComparison.OrdinalIgnoreCase);
        }

        if (value.Contains("探索", StringComparison.OrdinalIgnoreCase))
        {
            return label.Equals("探索", StringComparison.OrdinalIgnoreCase);
        }

        if (value.Contains("维修", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("补给", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("工业", StringComparison.OrdinalIgnoreCase))
        {
            return label.Equals("维修补给", StringComparison.OrdinalIgnoreCase) ||
                   label.Equals("采矿", StringComparison.OrdinalIgnoreCase) ||
                   label.Equals("打捞", StringComparison.OrdinalIgnoreCase);
        }

        if (value.Contains("集结", StringComparison.OrdinalIgnoreCase))
        {
            return label.Equals("集结组织", StringComparison.OrdinalIgnoreCase);
        }

        return label.Contains(value, StringComparison.OrdinalIgnoreCase) ||
               value.Contains(label, StringComparison.OrdinalIgnoreCase);
    }

    private void PublishTaskRallyBox_KeyUp(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (PublishTaskRallyBox is null)
        {
            return;
        }

        var query = PublishTaskRallyBox.Text.Trim();
        var matches = string.IsNullOrWhiteSpace(query) || query.Equals("未指定", StringComparison.OrdinalIgnoreCase)
            ? PublishTaskLocationSuggestions
            : PublishTaskLocationSuggestions
                .Where(location => location.Contains(query, StringComparison.CurrentCultureIgnoreCase))
                .ToArray();

        PublishTaskRallyBox.ItemsSource = matches;
        PublishTaskRallyBox.Text = query;
        PublishTaskRallyBox.IsDropDownOpen = !string.IsNullOrWhiteSpace(query) && matches.Length > 0;
        if (PublishTaskRallyBox.Template.FindName("PART_EditableTextBox", PublishTaskRallyBox) is System.Windows.Controls.TextBox textBox)
        {
            textBox.CaretIndex = textBox.Text.Length;
        }
    }

    private void PublishTaskShipFilter_Changed(object sender, RoutedEventArgs e)
    {
        RefreshPublishTaskShipOptions();
    }

    private void RefreshPublishTaskShipOptions(string? preferredSelection = null)
    {
        if (PublishTaskShipList is null)
        {
            return;
        }

        var previousSelection = preferredSelection ??
                                (PublishTaskShipList.SelectedItem as PublishTaskShipOptionRow)?.SelectionText;
        _publishTaskShipOptions.Clear();
        foreach (var row in BuildPublishTaskShipOptions())
        {
            _publishTaskShipOptions.Add(row);
        }

        PublishTaskShipList.IsEnabled = PublishTaskShipRequiredCheck?.IsChecked == true;
        if (string.IsNullOrWhiteSpace(previousSelection))
        {
            PublishTaskShipList.SelectedIndex = _publishTaskShipOptions.Count > 0 ? 0 : -1;
            return;
        }

        var selected = _publishTaskShipOptions.FirstOrDefault(row =>
            row.SelectionText.Equals(previousSelection, StringComparison.OrdinalIgnoreCase) ||
            row.ShipName.Equals(previousSelection, StringComparison.OrdinalIgnoreCase) ||
            row.ShipCode.Equals(previousSelection, StringComparison.OrdinalIgnoreCase) ||
            previousSelection.Contains(row.ShipName, StringComparison.OrdinalIgnoreCase) ||
            previousSelection.Contains(row.ShipCode, StringComparison.OrdinalIgnoreCase));
        PublishTaskShipList.SelectedItem = selected;
        if (selected is null && _publishTaskShipOptions.Count > 0)
        {
            PublishTaskShipList.SelectedIndex = 0;
        }
    }

    private IEnumerable<PublishTaskShipOptionRow> BuildPublishTaskShipOptions()
    {
        var onlineOnly = PublishTaskShipOnlineOnlyCheck?.IsChecked == true;
        var includeCatalog = PublishTaskShipIncludeCatalogCheck?.IsChecked == true;
        var seenCodes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var ship in _fleetShipInventory)
        {
            if (onlineOnly && !IsFleetShipOwnerOnline(ship))
            {
                continue;
            }

            seenCodes.Add(ShipNameLocalizer.NormalizeCode(ship.ShipCode));
            yield return CreatePublishTaskShipOption(ship);
        }

        if (!includeCatalog || onlineOnly)
        {
            yield break;
        }

        foreach (var entry in ShipCatalog.Entries
                     .OrderBy(entry => entry.Spec, StringComparer.CurrentCultureIgnoreCase)
                     .ThenBy(entry => entry.DisplayName(_language), StringComparer.CurrentCultureIgnoreCase))
        {
            var code = FormatFleetShipEnglishName(entry.EnglishName, entry.EnglishName);
            if (!seenCodes.Add(ShipNameLocalizer.NormalizeCode(code)))
            {
                continue;
            }

            yield return new PublishTaskShipOptionRow(
                entry.DisplayName(_language),
                code,
                string.IsNullOrWhiteSpace(entry.Spec) ? "待分类" : entry.Spec,
                entry.RoleDisplay(_language),
                string.IsNullOrWhiteSpace(entry.Status) ? "概念" : entry.Status,
                "未指定持有者",
                "全库目录",
                "目录项",
                FleetCommandBrush(BridgeBrushToken.Ink2),
                IsCatalogOnly: true);
        }
    }

    private PublishTaskShipOptionRow CreatePublishTaskShipOption(FleetShipInventoryRow ship)
    {
        var isOnline = IsFleetShipOwnerOnline(ship);
        return new PublishTaskShipOptionRow(
            ship.ShipName,
            ship.ShipCode,
            ship.ShipSpec,
            ship.ShipRoleTag,
            ship.ShipStatus,
            ship.OwnerDisplay,
            "舰队库",
            isOnline ? "在线" : "离线",
            FleetCommandBrush(isOnline ? BridgeBrushToken.StatusOk : BridgeBrushToken.StatusOff),
            IsCatalogOnly: false);
    }

    private string GetSelectedPublishTaskShipText()
    {
        return PublishTaskShipList.SelectedItem is PublishTaskShipOptionRow row
            ? row.SelectionText
            : "";
    }

    private void OpenPublishTaskPanel(bool rallyOnly = false, bool editCurrent = false)
    {
        PublishTaskValidationText.Text = "";
        PublishTaskObjectiveBox.Text = editCurrent ? _fleetCurrentTaskTitle : rallyOnly ? "舰队集结" : "战术打击";
        var taskInfo = editCurrent
            ? ParseFleetTaskBriefInfo(_fleetCurrentTaskBrief)
            : new FleetTaskBriefInfo
            {
                Brief = rallyOnly ? "舰队集结，等待进一步指令。" : "说明目标、风险、抵达后要做的事。",
                TaskType = rallyOnly ? "集结组织" : "空战",
                Duration = rallyOnly ? "15-30 分钟" : "30-60 分钟",
                CombatIntensity = rallyOnly ? "非战斗" : "未知"
            };
        PublishTaskBriefBox.Text = editCurrent ? taskInfo.Brief : rallyOnly
            ? "舰队集结，等待进一步指令。"
            : "说明目标、风险、抵达后要做的事。";
        SetPublishTaskCoverage(taskInfo.TaskType);
        SelectComboBoxText(PublishTaskDurationBox, taskInfo.Duration);
        SelectComboBoxText(PublishTaskCombatIntensityBox, taskInfo.CombatIntensity);
        PublishTaskRallyCheck.IsChecked = editCurrent ? !string.IsNullOrWhiteSpace(_fleetCurrentTaskRally) : rallyOnly;
        PublishTaskRallyBox.ItemsSource = PublishTaskLocationSuggestions;
        PublishTaskRallyBox.Text = editCurrent ? NormalizeOptionalField(_fleetCurrentTaskRally) : "未指定";
        PublishTaskShipRequiredCheck.IsChecked = editCurrent && !string.IsNullOrWhiteSpace(_fleetCurrentTaskShip);
        PublishTaskShipOnlineOnlyCheck.IsChecked = false;
        PublishTaskShipIncludeCatalogCheck.IsChecked = false;
        RefreshPublishTaskShipOptions(editCurrent ? NormalizeOptionalField(_fleetCurrentTaskShip) : null);
        PublishTaskEmailCallCheck.IsChecked = editCurrent ? _fleetCurrentTaskEmailCall : false;

        PublishTaskPanel.Show();
    }

    private void CancelPublishTaskButton_Click(object sender, RoutedEventArgs e)
    {
        PublishTaskPanel.Hide();
    }

    private async void PublishFleetTaskButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("发布任务需要先登录星海舰桥账号。"))
        {
            return;
        }

        if (!CanCurrentUserPublishTasks())
        {
            PublishTaskValidationText.Text = "当前账号没有发布任务的权限。";
            return;
        }

        var objective = PublishTaskObjectiveBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(objective))
        {
            PublishTaskValidationText.Text = "请输入任务目标。";
            return;
        }

        const string participants = "全员参与";
        var brief = PublishTaskBriefBox.Text.Trim();
        var rallyEnabled = PublishTaskRallyCheck.IsChecked == true;
        var rally = PublishTaskRallyBox.Text.Trim();
        var shipRequired = PublishTaskShipRequiredCheck.IsChecked == true;
        var ship = GetSelectedPublishTaskShipText();
        var emailCall = PublishTaskEmailCallCheck.IsChecked == true;
        var taskType = GetSelectedPublishTaskCoverage();
        var duration = GetComboBoxText(PublishTaskDurationBox, "待定");
        var combatIntensity = GetComboBoxText(PublishTaskCombatIntensityBox, "未指定");
        var medicalRequired = taskType.Contains("医疗", StringComparison.OrdinalIgnoreCase);
        var groundCombat = taskType.Contains("地面", StringComparison.OrdinalIgnoreCase);
        if (shipRequired && string.IsNullOrWhiteSpace(ship))
        {
            PublishTaskValidationText.Text = "请选择指定舰船，或关闭“指定”。";
            return;
        }

        var structuredBrief = BuildFleetTaskBriefPayload(
            brief,
            taskType,
            duration,
            combatIntensity,
            medicalRequired,
            groundCombat);
        var rollbackState = CaptureFleetStateForRollback();

        _fleetCurrentTaskTitle = objective;
        _fleetCurrentTaskBrief = structuredBrief;
        _fleetCurrentTaskParticipants = participants;
        _fleetCurrentTaskRally = rallyEnabled ? NormalizeOptionalField(rally) : "";
        _fleetCurrentTaskShip = shipRequired ? NormalizeOptionalField(ship) : "";
        _fleetCurrentTaskEmailCall = emailCall;
        _fleetCurrentTaskTime = DateTime.Now;
        _fleetCurrentTaskNoticeRevision++;
        if (string.IsNullOrWhiteSpace(_fleetCurrentTaskHistoryKey))
        {
            _fleetCurrentTaskHistoryKey = Guid.NewGuid().ToString("N");
        }

        UpsertCurrentTaskHistory("进行中");
        AddFleetLog("任务", "任务发布", $"{objective} / {participants}");
        _selectedFleetInfoPanel = FleetInfoPanelKind.CurrentTask;
        PublishTaskPanel.Hide();
        RefreshFleetOperationalSurfaces();
        SaveCurrentConfig();
        if (!await PushFleetTaskAsync(silent: false))
        {
            RestoreFleetStateAfterFailedMutation(rollbackState, "任务同步失败，已恢复本地任务状态。");
            PublishTaskPanel.Show();
            PublishTaskValidationText.Text = "任务同步失败，已恢复本地状态，请稍后重试。";
            return;
        }

        if (emailCall)
        {
            _ = SendFleetEmailNotificationAsync(
                $"StarBridge 舰队任务：{objective}",
                BuildFleetEmailBody(
                    "舰队任务发布",
                    ("任务目标", objective),
                    ("任务简述", FormatTaskDetailText(ParseFleetTaskBriefInfo(_fleetCurrentTaskBrief))),
                    ("参与范围", participants),
                    ("集结点", _fleetCurrentTaskRally),
                    ("指定舰船", _fleetCurrentTaskShip),
                    ("发布时间", _fleetCurrentTaskTime?.ToString("yyyy-MM-dd HH:mm") ?? "")),
                silent: true);
        }

        AppendOutput($"Fleet task published: {objective}");
    }

    private void EditCurrentTaskButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("编辑任务需要先登录。"))
        {
            return;
        }

        if (!CanCurrentUserPublishTasks())
        {
            AppendOutput("Current account cannot edit fleet tasks.");
            return;
        }

        if (string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle))
        {
            return;
        }

        OpenPublishTaskPanel(editCurrent: true);
    }

    private async void CompleteCurrentTaskButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("完成任务需要先登录。"))
        {
            return;
        }

        if (!CanCurrentUserPublishTasks())
        {
            AppendOutput("Current account cannot complete fleet tasks.");
            return;
        }

        if (string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle))
        {
            return;
        }

        var rollbackState = CaptureFleetStateForRollback();
        UpsertCurrentTaskHistory("已完成");
        AddFleetLog("任务", "任务完成", _fleetCurrentTaskTitle);
        ClearCurrentTask();
        RefreshFleetOperationalSurfaces();
        SaveCurrentConfig();
        if (!await PushFleetTaskAsync(silent: false))
        {
            RestoreFleetStateAfterFailedMutation(rollbackState, "任务完成同步失败，已恢复本地任务状态。");
        }
    }

    private async void DeleteCurrentTaskButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("删除任务需要先登录。"))
        {
            return;
        }

        if (!CanCurrentUserPublishTasks())
        {
            AppendOutput("Current account cannot delete fleet tasks.");
            return;
        }

        if (string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle))
        {
            return;
        }

        var taskTitle = _fleetCurrentTaskTitle;
        var confirmed = await ShowAppConfirmationAsync(
            "取消当前任务？",
            $"将取消任务「{taskTitle}」。",
            "成员将不再看到此即时任务，任务会进入过往事件。此操作同步后不可从事件栏继续回应。",
            "确认取消",
            "保留任务");
        if (!confirmed ||
            string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle) ||
            !string.Equals(_fleetCurrentTaskTitle, taskTitle, StringComparison.Ordinal))
        {
            return;
        }

        var rollbackState = CaptureFleetStateForRollback();
        UpsertCurrentTaskHistory("已取消");
        AddFleetLog("任务", "任务取消", _fleetCurrentTaskTitle);
        ClearCurrentTask();
        RefreshFleetOperationalSurfaces();
        SaveCurrentConfig();
        if (!await PushFleetTaskAsync(silent: false))
        {
            RestoreFleetStateAfterFailedMutation(rollbackState, "任务取消同步失败，已恢复本地任务状态。");
        }
    }

    private async void RenotifyCurrentTaskButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("再次通知需要先登录。"))
        {
            return;
        }

        if (!CanCurrentUserPublishTasks())
        {
            AppendOutput("Current account cannot re-notify fleet tasks.");
            return;
        }

        if (string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle))
        {
            return;
        }

        var rollbackState = CaptureFleetStateForRollback();
        _selectedFleetInfoPanel = FleetInfoPanelKind.CurrentTask;
        _fleetCurrentTaskNoticeRevision++;
        AddFleetLog("任务", "再次通知", _fleetCurrentTaskTitle);
        RefreshFleetOperationalSurfaces();
        SaveCurrentConfig();
        if (!await PushFleetTaskAsync(silent: false))
        {
            RestoreFleetStateAfterFailedMutation(rollbackState, "任务再次通知同步失败，已恢复本地任务状态。");
            return;
        }

        _ = SendFleetEmailNotificationAsync(
            $"StarBridge 舰队任务提醒：{_fleetCurrentTaskTitle}",
            BuildFleetEmailBody(
                "舰队任务再次通知",
                ("任务目标", _fleetCurrentTaskTitle),
                ("任务简述", FormatTaskDetailText(ParseFleetTaskBriefInfo(_fleetCurrentTaskBrief))),
                ("参与范围", _fleetCurrentTaskParticipants),
                ("集结点", _fleetCurrentTaskRally),
                ("指定舰船", _fleetCurrentTaskShip)),
            silent: true);
        AppendOutput($"Fleet task re-notified: {_fleetCurrentTaskTitle}");
    }

    private void FleetEventPublishTaskButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("发布任务需要先登录星海舰桥账号。"))
        {
            return;
        }

        if (!CanCurrentUserPublishTasks())
        {
            AppendOutput("Current account cannot publish fleet tasks.");
            return;
        }

        OpenManageFleetSection(ManageFleetTaskTab);
        OpenPublishTaskPanel();
    }

    private void FleetEventCreatePlanButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("创建行动计划需要先登录。"))
        {
            return;
        }

        if (!CanCurrentUserPublishPlans())
        {
            AppendOutput("Current account cannot publish fleet action plans.");
            return;
        }

        if (CountOpenActionPlans() >= 3)
        {
            AppendOutput("Action plan creation skipped: open plan limit reached.");
            return;
        }

        OpenManageFleetSection(ManageFleetPlanTab);
        OpenActionPlanEditor(null);
    }

    private async void FleetEventActionPlanJoinButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("接取行动计划需要先登录。"))
        {
            return;
        }

        if (sender is not FrameworkElement { DataContext: FleetEventActionPlanRow row })
        {
            return;
        }

        var plan = _fleetActionPlans.FirstOrDefault(plan =>
            plan.Id.Equals(row.Id, StringComparison.OrdinalIgnoreCase));
        if (plan is null)
        {
            RefreshFleetEventActionPlans();
            return;
        }

        if (!plan.IsJoinable)
        {
            AppendOutput("Action reservation skipped: action plan is no longer joinable.");
            RefreshFleetEventActionPlans();
            return;
        }

        _selectedActionPlanId = plan.Id;
        _fleetActionTitle = plan.Title;
        _fleetActionContent = plan.Content;
        _fleetActionStartTime = plan.StartTime;
        _fleetActionNotifyMembers = plan.NotifyMembers;

        if (_joinedActionPlanIds.Contains(plan.Id))
        {
            if (await LeaveSelectedActionPlanAsync())
            {
                RefreshFleetOperationalSurfaces();
                AppendOutput("Action reservation canceled from event hub.");
            }

            return;
        }

        JoinActionPlanTitleText.Text = string.IsNullOrWhiteSpace(plan.Title)
            ? "行动计划"
            : plan.Title;
        JoinActionNotifyCheck.IsChecked = _joinActionNotifyMe;
        JoinActionPlanPanel.Show();
    }

    private void FleetEventRenotifyTaskButton_Click(object sender, RoutedEventArgs e)
    {
        RenotifyCurrentTaskButton_Click(sender, e);
        RefreshFleetEventCommandCenter();
    }

    private async void FleetCommandRemindButton_Click(object sender, RoutedEventArgs e)
    {
        if (!string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle))
        {
            FleetEventRenotifyTaskButton_Click(sender, e);
            RefreshFleetCommandDeck();
            return;
        }

        var plan = _fleetActionPlans
            .Where(plan => plan.IsOpen)
            .OrderBy(plan => plan.StartTime)
            .FirstOrDefault();
        if (plan is null)
        {
            return;
        }

        var rollbackState = CaptureFleetStateForRollback();
        var actor = GetLocalFleetActorDisplayName();
        var title = string.IsNullOrWhiteSpace(plan.Title) ? "未命名预约行动" : plan.Title;
        AddFleetLog("计划", "提醒成员预约行动", $"{actor} 提醒成员预约：{title}");
        RefreshFleetOperationalSurfaces();
        SaveCurrentConfig();
        if (!await PushFleetActionPlansAsync(silent: false))
        {
            RestoreFleetStateAfterFailedMutation(rollbackState, "行动提醒同步失败，已恢复本地状态。");
        }
    }

    private void FleetEventCompleteTaskButton_Click(object sender, RoutedEventArgs e)
    {
        CompleteCurrentTaskButton_Click(sender, e);
        RefreshFleetEventCommandCenter();
    }

    private void FleetEventCancelTaskButton_Click(object sender, RoutedEventArgs e)
    {
        DeleteCurrentTaskButton_Click(sender, e);
        RefreshFleetEventCommandCenter();
    }

    private async void FleetEventConfirmTaskButton_Click(object sender, RoutedEventArgs e)
    {
        await RecordFleetInstantTaskResponseAsync("确认收到");
    }

    private async void FleetEventReadyTaskButton_Click(object sender, RoutedEventArgs e)
    {
        await RecordFleetInstantTaskResponseAsync("已就位");
    }

    private async void FleetEventUnableTaskButton_Click(object sender, RoutedEventArgs e)
    {
        await RecordFleetInstantTaskResponseAsync("无法参与");
    }

    private async Task RecordFleetInstantTaskResponseAsync(string response)
    {
        if (!EnsureLoggedIn("反馈任务状态需要先登录。"))
        {
            return;
        }

        if (string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle))
        {
            return;
        }

        var currentResponse = GetLocalInstantTaskResponse();
        var key = GetCurrentFleetOrderKey();
        if (currentResponse.Equals(response, StringComparison.OrdinalIgnoreCase))
        {
            RefreshFleetOperationalSurfaces();
            if (!await PushFleetTaskResponseAsync(response, _fleetCurrentTaskTitle, _fleetCurrentTaskTime, silent: true))
            {
                AppendOutput("Fleet event response already recorded locally; response sync will retry later.");
            }

            return;
        }

        string? previousLocalResponse = null;
        var hadPreviousLocalResponse = !string.IsNullOrWhiteSpace(key) &&
                                       _fleetInstantTaskResponses.TryGetValue(key, out previousLocalResponse);
        if (!string.IsNullOrWhiteSpace(key))
        {
            _fleetInstantTaskResponses[key] = response;
        }

        RefreshFleetOperationalSurfaces();
        if (!await PushFleetTaskResponseAsync(response, _fleetCurrentTaskTitle, _fleetCurrentTaskTime, silent: true))
        {
            if (!string.IsNullOrWhiteSpace(key))
            {
                if (hadPreviousLocalResponse && previousLocalResponse is not null)
                {
                    _fleetInstantTaskResponses[key] = previousLocalResponse;
                }
                else
                {
                    _fleetInstantTaskResponses.Remove(key);
                }
            }

            RefreshFleetOperationalSurfaces();
            NetworkStatusText.Text = "任务回应同步失败，已恢复本地回应状态。";
            AppendOutput("Fleet event response sync failed; local response restored.");
        }
    }

    private void OpenActionPlanEditorButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("创建行动计划需要先登录。"))
        {
            return;
        }

        if (!CanCurrentUserPublishPlans())
        {
            ActionPlanValidationText.Text = "当前账号没有发布行动计划的权限。";
            return;
        }

        OpenActionPlanEditor(null);
    }

    private void ClearCurrentTask()
    {
        _fleetCurrentTaskTitle = "";
        _fleetCurrentTaskBrief = "";
        _fleetCurrentTaskParticipants = "";
        _fleetCurrentTaskRally = "";
        _fleetCurrentTaskShip = "";
        _fleetCurrentTaskEmailCall = false;
        _fleetCurrentTaskTime = null;
        _fleetCurrentTaskHistoryKey = "";
        _fleetCurrentTaskNoticeRevision++;
    }

    private static string NormalizeFleetTaskParticipants(string? value) =>
        string.IsNullOrWhiteSpace(value) ? "" : "全员参与";

    private void UpsertCurrentTaskHistory(string status)
    {
        if (string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle))
        {
            return;
        }

        if (string.IsNullOrWhiteSpace(_fleetCurrentTaskHistoryKey))
        {
            _fleetCurrentTaskHistoryKey = Guid.NewGuid().ToString("N");
        }

        var taskInfo = ParseFleetTaskBriefInfo(_fleetCurrentTaskBrief);
        var row = new FleetTaskHistoryRow(
            _fleetCurrentTaskHistoryKey,
            _fleetCurrentTaskTitle,
            FormatTaskDetailText(taskInfo),
            status,
            $"参与范围 / {NormalizeOptionalField(_fleetCurrentTaskParticipants)}",
            string.IsNullOrWhiteSpace(_fleetCurrentTaskRally) ? "集结点 / 未发布" : $"集结点 / {_fleetCurrentTaskRally}",
            string.IsNullOrWhiteSpace(_fleetCurrentTaskShip)
                ? $"任务条件 / {FormatTaskConditionSummary(taskInfo)}"
                : $"指定舰船 / {_fleetCurrentTaskShip}",
            (_fleetCurrentTaskTime ?? DateTime.Now).ToString("yyyy-MM-dd HH:mm"));

        var existingIndex = _fleetTaskHistory
            .Select((task, index) => new { task, index })
            .FirstOrDefault(item => item.task.Key.Equals(_fleetCurrentTaskHistoryKey, StringComparison.OrdinalIgnoreCase))
            ?.index;
        if (existingIndex is int index)
        {
            _fleetTaskHistory[index] = row;
        }
        else
        {
            _fleetTaskHistory.Insert(0, row);
        }
    }

    private static string NormalizeOptionalField(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? "未指定" : value;
    }

    private static string NormalizeFleetDescription(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "";
        }

        var normalized = value.Trim();
        return normalized is "未指定" or FleetDescriptionPublicPlaceholder
            ? ""
            : normalized;
    }

    private void CustomTitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2)
        {
            ToggleWindowMaximize();
            return;
        }

        DragMove();
    }

    private void MinimizeWindowButton_Click(object sender, RoutedEventArgs e)
    {
        WindowState = WindowState.Minimized;
    }

    private void MaximizeWindowButton_Click(object sender, RoutedEventArgs e)
    {
        ToggleWindowMaximize();
    }

    private void CloseWindowButton_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }

    private void ToggleWindowMaximize()
    {
        WindowState = WindowState == WindowState.Maximized
            ? WindowState.Normal
            : WindowState.Maximized;
        UpdateMaximizeButtonText();
    }

    private void UpdateMaximizeButtonText()
    {
        if (MaximizeWindowButton is not null)
        {
            var isMaximized = WindowState == WindowState.Maximized;
            MaximizeWindowButton.Tag = isMaximized ? "Restore" : "Maximize";
            MaximizeWindowButton.ToolTip = isMaximized ? "还原" : "最大化";
            System.Windows.Automation.AutomationProperties.SetName(MaximizeWindowButton, isMaximized ? "还原" : "最大化");
        }
    }

    private static string GetAppVersion()
    {
        return AppVersionIdentity.GetCurrentVersion();
    }

    private string GetAppDisplayTitle() => _language == "zh"
        ? $"星海舰桥 V{GetAppVersion()} 测试版"
        : $"Star Bridge V{GetAppVersion()} Test Build";

    private static string GetAppUpdateVersion()
    {
        return AppVersionIdentity.GetCurrentVersion();
    }

    private void FleetActionPlanCard_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (_selectedFleetInfoPanel == FleetInfoPanelKind.ActionPlan)
        {
            if (!CanCurrentUserPublishPlans())
            {
                return;
            }

            if (!EnsureLoggedIn("编辑行动计划需要先登录。"))
            {
                return;
            }

            OpenActionPlanEditor(GetSelectedActionPlanRow());
        }
        else if (_selectedFleetInfoPanel == FleetInfoPanelKind.CurrentTask)
        {
            OpenCurrentTaskDetail();
        }
        else if (_selectedFleetInfoPanel == FleetInfoPanelKind.Notice && CanCurrentUserManageAnnouncements())
        {
            OpenFleetNoticeEditor();
        }
    }

    private void FleetNotificationCenterAction_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not FleetNotificationCenterItemRow row ||
            string.IsNullOrWhiteSpace(row.ActionKey))
        {
            return;
        }

        switch (row.ActionKey)
        {
            case "find-fleet":
                if (!TryLeaveOverlayEditorTab())
                {
                    return;
                }

                MainTabs.SelectedItem = FindFleetTab;
                SetActiveNav(FindFleetNavButton);
                _ = PullNetworkFleetsAsync(silent: true);
                break;
            case "applications":
                OpenManageFleetSection(FleetApplicationsTab);
                break;
            case "task-detail":
                _selectedFleetInfoPanel = FleetInfoPanelKind.CurrentTask;
                RefreshFleetInfoPanel();
                OpenCurrentTaskDetail();
                break;
            case "task-manage":
                OpenManageFleetSection(ManageFleetTaskTab);
                break;
            case "plan-detail":
                _selectedFleetInfoPanel = FleetInfoPanelKind.ActionPlan;
                RefreshFleetInfoPanel();
                if (CanCurrentUserPublishPlans())
                {
                    OpenManageFleetSection(ManageFleetPlanTab);
                }
                break;
            case "plan-manage":
                OpenManageFleetSection(ManageFleetPlanTab);
                break;
            case "notice-detail":
                _selectedFleetInfoPanel = FleetInfoPanelKind.Notice;
                RefreshFleetInfoPanel();
                _ = OpenFleetAnnouncementCenterAsync();
                break;
            case "notice-edit":
                OpenManageFleetSection(ManageFleetNoticeTab);
                _ = OpenFleetAnnouncementCenterAsync();
                break;
            case "logs":
                OpenManageFleetSection(ManageFleetLogTab);
                break;
        }
    }

    private void OpenManageFleetSection(TabItem? manageTab)
    {
        if (!TryLeaveOverlayEditorTab())
        {
            return;
        }

        if (!_hasFleet || manageTab is null)
        {
            return;
        }

        if (!EnableFleetActionManagementUi &&
            (manageTab == ManageFleetTaskTab || manageTab == ManageFleetPlanTab))
        {
            manageTab = ManageFleetProfileTab.Visibility == Visibility.Visible
                ? ManageFleetProfileTab
                : ManageFleetOverviewTab;
        }

        RefreshFleetManagementPermissions();
        MainTabs.SelectedItem = FleetTab;
        FleetSubTabs.SelectedItem = ManageFleetTab;
        if (ManageFleetTab.Visibility == Visibility.Visible &&
            manageTab.Visibility == Visibility.Visible)
        {
            ManageFleetTabs.SelectedItem = manageTab;
        }

        SetActiveNav(MyFleetNavButton);
    }

    private void FleetRightModuleOneLinkButton_Click(object sender, RoutedEventArgs e)
    {
        OpenFleetApplicationReviewQueue();
    }

    private void FleetRightModuleThreeLinkButton_Click(object sender, RoutedEventArgs e)
    {
        if (!CanCurrentUserViewFleetLogs() ||
            ManageFleetLogTab.Visibility != Visibility.Visible)
        {
            return;
        }

        OpenManageFleetSection(ManageFleetLogTab);
    }

    private void OpenFleetApplicationReviewQueue()
    {
        if (!CanCurrentUserOpenFleetManagement() ||
            FleetApplicationsTab.Visibility != Visibility.Visible)
        {
            return;
        }

        OpenManageFleetSection(FleetApplicationsTab);
        Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Loaded, new Action(() =>
        {
            FleetApplicationReviewQueuePanel.BringIntoView();
        }));
    }

    private void OpenFleetNoticeEditor()
    {
        OpenFleetNoticeEditor(
            createNew: _fleetCurrentAnnouncement is null,
            returnToCenter: false);
    }

    private void CancelFleetNoticeButton_Click(object sender, RoutedEventArgs e)
    {
        FleetNoticeEditorPanel.Hide();
        if (_returnToAnnouncementCenterAfterEdit)
        {
            FleetAnnouncementCenterPanel.Show();
        }
    }

    private async void PublishFleetNoticeButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("发布舰队公告需要先登录。"))
        {
            return;
        }

        if (!CanCurrentUserManageAnnouncements())
        {
            FleetNoticeValidationText.Text = "当前账号没有发布舰队公告的权限。";
            return;
        }

        await PublishFleetAnnouncementDraftAsync();
    }

    private async void SaveFleetDescriptionButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("修改舰队介绍需要先登录。"))
        {
            return;
        }

        if (!CanCurrentUserManageFleetInfo())
        {
            SetFleetDescriptionStatus("当前账号没有修改舰队介绍的权限。", ManageProfileStatusTone.Locked);
            return;
        }

        var rollbackState = CaptureFleetStateForRollback();
        _fleetDescription = NormalizeFleetDescription(FleetDescriptionEditBox.Text);
        AddFleetLog("舰队", "舰队介绍更新", _fleetDescription);
        RefreshFleetHeader();
        RefreshTaskManagementPanel();
        SaveCurrentConfig();
        if (!await PushFleetInfoAsync(silent: false, scope: FleetInfoUpdateScope.Description))
        {
            RestoreFleetStateAfterFailedMutation(rollbackState, "舰队介绍同步失败，已恢复本地资料状态。");
            SetFleetDescriptionStatus("舰队介绍同步失败，已恢复本地状态。", ManageProfileStatusTone.Danger);
            return;
        }

        SetFleetDescriptionStatus("舰队介绍已保存并同步。", ManageProfileStatusTone.Success);
    }

    private async void SaveFleetNotificationSettingsButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("修改舰队邮件通知需要先登录。"))
        {
            return;
        }

        if (!CanCurrentUserManageFleetInfo())
        {
            FleetEmailNotificationsStatusText.Text = "当前账号没有修改舰队邮件通知的权限。";
            return;
        }

        var enabled = FleetEmailNotificationsEnabledCheck.IsChecked == true;
        var rollbackState = CaptureFleetStateForRollback();
        if (_fleetEmailNotificationsEnabled != enabled)
        {
            AddFleetLog("舰队", enabled ? "启用基础邮件通知" : "关闭基础邮件通知", "舰队级基础邮件通知设置已更新");
        }

        _fleetEmailNotificationsEnabled = enabled;
        RefreshTaskManagementPanel();
        SaveCurrentConfig();
        if (!await PushFleetInfoAsync(silent: false, scope: FleetInfoUpdateScope.EmailNotifications))
        {
            RestoreFleetStateAfterFailedMutation(rollbackState, "舰队邮件通知设置同步失败，已恢复本地设置。");
            FleetEmailNotificationsEnabledCheck.IsChecked = _fleetEmailNotificationsEnabled;
            FleetEmailNotificationsStatusText.Text = "舰队邮件通知设置同步失败，已恢复本地状态。";
            return;
        }

        FleetEmailNotificationsStatusText.Text = enabled
            ? "基础邮件通知已启用。"
            : "基础邮件通知已关闭。";
    }

    private void OpenCurrentTaskDetail()
    {
        if (string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle))
        {
            return;
        }

        CurrentTaskDetailPanel.Title = _fleetCurrentTaskTitle;
        var taskInfo = ParseFleetTaskBriefInfo(_fleetCurrentTaskBrief);
        CurrentTaskDetailBriefText.Text = FormatTaskDetailText(taskInfo);
        CurrentTaskDetailParticipantsText.Text = $"参与范围 / {_fleetCurrentTaskParticipants}";
        CurrentTaskDetailRallyText.Text = string.IsNullOrWhiteSpace(_fleetCurrentTaskRally)
            ? "集结点 / 未发布"
            : $"集结点 / {_fleetCurrentTaskRally}";
        CurrentTaskDetailShipText.Text = string.IsNullOrWhiteSpace(_fleetCurrentTaskShip)
            ? $"任务条件 / {FormatTaskConditionSummary(taskInfo)}"
            : $"指定舰船 / {_fleetCurrentTaskShip}    条件 / {FormatTaskConditionSummary(taskInfo)}";
        CurrentTaskDetailTimeText.Text = _fleetCurrentTaskTime is null
            ? ""
            : $"发布时间 / {_fleetCurrentTaskTime:yyyy-MM-dd HH:mm}";
        CurrentTaskDetailPanel.Show();
    }

    private void CloseCurrentTaskDetailButton_Click(object sender, RoutedEventArgs e)
    {
        CurrentTaskDetailPanel.Hide();
    }

    private void OpenCommandDeckActionPlanDetail(FleetActionPlanRow? plan = null)
    {
        plan ??= GetCommandDeckDetailPlan();
        if (plan is null)
        {
            FleetCommandViewPlansButton_Click(this, new RoutedEventArgs());
            return;
        }

        _commandDeckActionPlanDetailId = plan.Id;
        ActionPlanDetailPanel.DataContext = plan;
        ActionPlanDetailRemindButton.DataContext = plan;
        ActionPlanDetailEditButton.DataContext = plan;
        ActionPlanDetailCompleteButton.DataContext = plan;
        ActionPlanDetailCancelButton.DataContext = plan;

        var title = string.IsNullOrWhiteSpace(plan.Title) ? "未命名行动" : plan.Title;
        var participants = plan.Participants.Count.ToString(CultureInfo.InvariantCulture);
        ActionPlanDetailPanel.Description = title;
        ActionPlanDetailBriefText.Text = string.IsNullOrWhiteSpace(plan.Content)
            ? "成员可在事件栏接取此预约，指挥官可在这里查看状态并进行管理操作。"
            : plan.Content.Trim();
        ActionPlanDetailTimeText.Text = $"开始时间 / {plan.StartTime:yyyy-MM-dd HH:mm}";
        ActionPlanDetailParticipantsText.Text = $"接取情况 / {participants} / 不限";
        ActionPlanDetailCommanderText.Text = $"指挥官 / {FormatCommanderName(_callsign, _localPlayer, _fleetChiefCommander)}";
        ActionPlanDetailScopeText.Text = "参与范围 / 全舰队";
        ActionPlanDetailStatusText.Text = $"当前状态 / {FormatActionPlanStatusForCommandDeck(plan)}";
        ActionPlanDetailNotifyText.Text = plan.NotifyMembers ? "提醒 / 已启用" : "提醒 / 未启用";
        ActionPlanDetailMembersText.Text = plan.Participants.Count == 0
            ? "暂无成员接取。"
            : string.Join("、", plan.Participants.Select(participant =>
                FormatCommanderName(participant.Callsign, participant.GameName)));

        var canManage = CanCurrentUserPublishPlans();
        ActionPlanDetailRemindButton.IsEnabled = canManage && plan.IsOpen;
        ActionPlanDetailEditButton.IsEnabled = canManage && plan.CanEdit;
        ActionPlanDetailCompleteButton.IsEnabled = canManage && plan.CanComplete;
        ActionPlanDetailCancelButton.IsEnabled = canManage && plan.CanCancel;
        ActionPlanDetailPanel.Show();
    }

    private FleetActionPlanRow? GetCommandDeckDetailPlan()
    {
        if (!string.IsNullOrWhiteSpace(_commandDeckActionPlanDetailId))
        {
            var selected = _fleetActionPlans.FirstOrDefault(plan =>
                plan.Id.Equals(_commandDeckActionPlanDetailId, StringComparison.OrdinalIgnoreCase));
            if (selected is not null)
            {
                return selected;
            }
        }

        return _fleetActionPlans
            .Where(plan => plan.IsOpen)
            .OrderBy(plan => plan.StartTime)
            .FirstOrDefault();
    }

    private void CloseActionPlanDetailButton_Click(object sender, RoutedEventArgs e)
    {
        ActionPlanDetailPanel.Hide();
    }

    private void ActionPlanDetailRemindButton_Click(object sender, RoutedEventArgs e)
    {
        e.Handled = true;
        FleetCommandRemindButton_Click(sender, e);
    }

    private void ActionPlanDetailEditButton_Click(object sender, RoutedEventArgs e)
    {
        e.Handled = true;
        var plan = GetCommandDeckDetailPlan();
        if (plan is null)
        {
            return;
        }

        ActionPlanDetailPanel.Hide();
        OpenActionPlanEditor(plan);
    }

    private void ActionPlanDetailCompleteButton_Click(object sender, RoutedEventArgs e)
    {
        e.Handled = true;
        if (GetCommandDeckDetailPlan() is not { } plan)
        {
            return;
        }

        ActionPlanDetailCompleteButton.DataContext = plan;
        CompleteActionPlanRowButton_Click(ActionPlanDetailCompleteButton, e);
    }

    private void ActionPlanDetailCancelButton_Click(object sender, RoutedEventArgs e)
    {
        e.Handled = true;
        if (GetCommandDeckDetailPlan() is not { } plan)
        {
            return;
        }

        ActionPlanDetailCancelButton.DataContext = plan;
        CancelActionPlanRowButton_Click(ActionPlanDetailCancelButton, e);
    }

    private void FleetNoticeInfoTabButton_Click(object sender, RoutedEventArgs e)
    {
        _selectedFleetInfoPanel = FleetInfoPanelKind.Notice;
        RefreshFleetInfoPanel();
    }

    private void FleetCurrentTaskInfoTabButton_Click(object sender, RoutedEventArgs e)
    {
        _selectedFleetInfoPanel = FleetInfoPanelKind.CurrentTask;
        RefreshFleetInfoPanel();
    }

    private void FleetActionPlanInfoTabButton_Click(object sender, RoutedEventArgs e)
    {
        _selectedFleetInfoPanel = FleetInfoPanelKind.ActionPlan;
        RefreshFleetInfoPanel();
    }

    private void OpenActionPlanEditor(FleetActionPlanRow? plan = null)
    {
        if (!IsLoggedIn)
        {
            return;
        }

        if (!CanCurrentUserPublishPlans())
        {
            return;
        }

        if (plan is { CanEdit: false })
        {
            ActionPlanValidationText.Text = "已到时、已完成或已取消的行动计划不能继续编辑。";
            return;
        }

        if (plan is null && CountOpenActionPlans() >= 3)
        {
            ActionPlanValidationText.Text = "同一舰队最多同时存在 3 个未结束行动计划。";
            return;
        }

        _editingActionPlanId = plan?.Id ?? "";
        ActionPlanTitleBox.Text = plan?.Title ?? "";
        ActionPlanContentBox.Text = plan?.Content ?? "";
        var start = plan?.StartTime ?? DateTime.Now.AddHours(1);
        ActionPlanDatePicker.SelectedDate = start.Date;
        ActionPlanTimeBox.Text = start.ToString("HH:mm");
        ActionPlanNotifyFleetCheck.IsChecked = plan?.NotifyMembers ?? _fleetActionNotifyMembers;
        ActionPlanValidationText.Text = "";
        ActionPlanEditorPanel.Title = plan is null ? "安排稍后行动" : "编辑稍后行动";

        if (PublishActionPlanButton is not null)
        {
            PublishActionPlanButton.Content = plan is null ? "发布" : "保存";
        }

        ActionPlanEditorPanel.Show();
    }

    private void CancelActionPlanButton_Click(object sender, RoutedEventArgs e)
    {
        _editingActionPlanId = "";
        ActionPlanEditorPanel.Hide();
    }

    private async void PublishActionPlanButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("发布行动计划需要先登录。"))
        {
            return;
        }

        if (!CanCurrentUserPublishPlans())
        {
            ActionPlanValidationText.Text = "当前账号没有发布行动计划的权限。";
            return;
        }

        var title = ActionPlanTitleBox.Text.Trim();
        var content = ActionPlanContentBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(title))
        {
            ActionPlanValidationText.Text = "请输入行动标题。";
            return;
        }

        if (string.IsNullOrWhiteSpace(content))
        {
            ActionPlanValidationText.Text = "请输入行动内容。";
            return;
        }

        if (!TryReadActionPlanStartTime(out var startTime, out var message))
        {
            ActionPlanValidationText.Text = message;
            return;
        }

        var notifyMembers = ActionPlanNotifyFleetCheck.IsChecked == true;
        var isEditing = !string.IsNullOrWhiteSpace(_editingActionPlanId);
        var plan = isEditing
            ? _fleetActionPlans.FirstOrDefault(plan =>
                plan.Id.Equals(_editingActionPlanId, StringComparison.OrdinalIgnoreCase))
            : null;

        if (isEditing && plan is null)
        {
            ActionPlanValidationText.Text = "要编辑的行动计划不存在，请刷新后重试。";
            return;
        }

        if (plan is { CanEdit: false })
        {
            ActionPlanValidationText.Text = "已到时、已完成或已取消的行动计划不能继续编辑。";
            return;
        }

        var rollbackState = CaptureFleetStateForRollback();
        if (plan is null)
        {
            if (CountOpenActionPlans() >= 3)
            {
                ActionPlanValidationText.Text = "同一舰队最多同时存在 3 个未结束行动计划。";
                return;
            }

            plan = new FleetActionPlanRow(
                Guid.NewGuid().ToString("N"),
                title,
                content,
                startTime,
                notifyMembers);
            _fleetActionPlans.Add(plan);
            AddFleetLog("计划", "行动计划创建", $"{title} / {startTime:yyyy-MM-dd HH:mm}");
        }
        else
        {
            plan.UpdatePlan(title, content, startTime, notifyMembers);
            AddFleetLog("计划", "行动计划更新", $"{title} / {startTime:yyyy-MM-dd HH:mm}");
        }

        SelectFeaturedActionPlan();
        _selectedFleetInfoPanel = FleetInfoPanelKind.ActionPlan;
        ActionPlanEditorPanel.Hide();
        RefreshFleetOperationalSurfaces();
        SaveCurrentConfig();
        var pushed = await PushFleetActionPlansAsync(silent: false);
        if (!pushed)
        {
            RestoreFleetStateAfterFailedMutation(rollbackState, "行动计划同步失败，已恢复本地计划状态。");
            ActionPlanEditorPanel.Show();
            ActionPlanValidationText.Text = "行动计划同步失败，已恢复本地状态，请稍后重试。";
            return;
        }

        _editingActionPlanId = "";
        if (pushed && plan.NotifyMembers)
        {
            _ = SendFleetEmailNotificationAsync(
                isEditing ? $"StarBridge 行动计划更新：{title}" : $"StarBridge 行动计划：{title}",
                BuildFleetEmailBody(
                    isEditing ? "行动计划更新" : "行动计划发布",
                    ("行动标题", title),
                    ("行动内容", content),
                    ("行动时间", startTime.ToString("yyyy-MM-dd HH:mm"))),
                silent: true);
        }
    }

    private FleetActionPlanRow? GetSelectedActionPlanRow()
    {
        return string.IsNullOrWhiteSpace(_selectedActionPlanId)
            ? null
            : _fleetActionPlans.FirstOrDefault(plan =>
                plan.Id.Equals(_selectedActionPlanId, StringComparison.OrdinalIgnoreCase));
    }

    private void EditActionPlanRowButton_Click(object sender, RoutedEventArgs e)
    {
        e.Handled = true;
        if (sender is FrameworkElement { DataContext: FleetActionPlanRow plan })
        {
            OpenActionPlanEditor(plan);
        }
    }

    private void SetActionPlanOperationStatus(string message, bool isError = false)
    {
        if (string.IsNullOrWhiteSpace(message))
        {
            return;
        }

        if (ActionPlanValidationText is not null)
        {
            ActionPlanValidationText.Text = message;
            ActionPlanValidationText.Foreground = isError
                ? FleetCommandBrush(BridgeBrushToken.StatusBad)
                : FleetCommandBrush(BridgeBrushToken.Ink2);
        }

        if (NetworkStatusText is not null)
        {
            NetworkStatusText.Text = message;
        }

        AppendOutput($"ACTION_PLAN | {(isError ? "error" : "status")}={message}");
    }

    private async void CancelActionPlanRowButton_Click(object sender, RoutedEventArgs e)
    {
        e.Handled = true;
        if (sender is not FrameworkElement { DataContext: FleetActionPlanRow plan })
        {
            SetActionPlanOperationStatus("无法识别要取消的行动计划，请刷新后重试。", isError: true);
            return;
        }

        if (!EnsureLoggedIn("取消行动计划需要先登录。"))
        {
            return;
        }

        if (!CanCurrentUserPublishPlans())
        {
            SetActionPlanOperationStatus("当前账号没有取消行动计划的权限。", isError: true);
            return;
        }

        if (!plan.CanCancel)
        {
            SetActionPlanOperationStatus(
                plan.IsCanceled ? "该行动计划已经取消。" : "该行动计划不能取消。",
                isError: true);
            return;
        }

        var result = StarBridgeMessageBox.Show(
            $"确认取消行动计划「{plan.Title}」？成员将不能继续预约，计划会保留为已取消状态。",
            "取消行动计划",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);
        if (result != MessageBoxResult.Yes)
        {
            return;
        }

        var reason = "由舰队管理取消";
        var title = plan.Title;
        var content = plan.Content;
        var startTime = plan.StartTime;
        var notifyMembers = plan.NotifyMembers;
        var clickedButton = sender as System.Windows.Controls.Button;
        if (clickedButton is not null)
        {
            clickedButton.IsEnabled = false;
        }

        SetActionPlanOperationStatus($"正在取消行动计划：{title}...");
        try
        {
            var pushed = await PushFleetActionPlanCancelAsync(plan, reason, silent: false);
            if (!pushed)
            {
                var failureDetail = NetworkStatusText?.Text;
                SetActionPlanOperationStatus(
                    string.IsNullOrWhiteSpace(failureDetail) ||
                    failureDetail.StartsWith("正在取消行动计划", StringComparison.Ordinal)
                        ? "取消行动计划失败，请刷新后重试。"
                        : failureDetail,
                    isError: true);
                RefreshFleetOperationalSurfaces();
                return;
            }

            SetActionPlanOperationStatus($"已取消行动计划：{title}。");
            RefreshFleetOperationalSurfaces();

            if (notifyMembers)
            {
                _ = SendFleetEmailNotificationAsync(
                    $"StarBridge 行动计划取消：{title}",
                    BuildFleetEmailBody(
                        "行动计划取消",
                        ("行动标题", title),
                        ("行动内容", content),
                        ("行动时间", startTime.ToString("yyyy-MM-dd HH:mm")),
                        ("取消原因", reason)),
                    silent: true);
            }
        }
        finally
        {
            if (clickedButton is not null)
            {
                clickedButton.IsEnabled = true;
            }
        }
    }

    private async void CompleteActionPlanRowButton_Click(object sender, RoutedEventArgs e)
    {
        e.Handled = true;
        if (sender is not FrameworkElement { DataContext: FleetActionPlanRow plan })
        {
            SetActionPlanOperationStatus("无法识别要完成的行动计划，请刷新后重试。", isError: true);
            return;
        }

        if (!EnsureLoggedIn("完成行动计划需要先登录。"))
        {
            return;
        }

        if (!CanCurrentUserPublishPlans())
        {
            SetActionPlanOperationStatus("当前账号没有完成行动计划的权限。", isError: true);
            return;
        }

        if (!plan.CanComplete)
        {
            SetActionPlanOperationStatus(
                plan.IsPublished ? "行动计划尚未到时，不能完成。" : "该行动计划不能完成。",
                isError: true);
            return;
        }

        var result = StarBridgeMessageBox.Show(
            $"确认完成行动计划「{plan.Title}」？完成后计划将进入只读历史状态。",
            "完成行动计划",
            MessageBoxButton.YesNo,
            MessageBoxImage.Information);
        if (result != MessageBoxResult.Yes)
        {
            return;
        }

        var clickedButton = sender as System.Windows.Controls.Button;
        if (clickedButton is not null)
        {
            clickedButton.IsEnabled = false;
        }

        SetActionPlanOperationStatus($"正在完成行动计划：{plan.Title}...");
        try
        {
            if (!await PushFleetActionPlanCompleteAsync(plan, silent: false))
            {
                var failureDetail = NetworkStatusText?.Text;
                SetActionPlanOperationStatus(
                    string.IsNullOrWhiteSpace(failureDetail) ||
                    failureDetail.StartsWith("正在完成行动计划", StringComparison.Ordinal)
                        ? "完成行动计划失败，请刷新后重试。"
                        : failureDetail,
                    isError: true);
                RefreshFleetOperationalSurfaces();
                return;
            }

            SetActionPlanOperationStatus($"已完成行动计划：{plan.Title}。");
            RefreshFleetOperationalSurfaces();
        }
        finally
        {
            if (clickedButton is not null)
            {
                clickedButton.IsEnabled = true;
            }
        }
    }

    private bool TryReadActionPlanStartTime(out DateTime startTime, out string message)
    {
        startTime = default;
        message = "";
        if (ActionPlanDatePicker.SelectedDate is not { } selectedDate)
        {
            message = "请选择行动日期。";
            return false;
        }

        if (!IsValidTime24(ActionPlanTimeBox.Text.Trim()))
        {
            message = "行动时间必须使用 24 小时制 HH:mm。";
            return false;
        }

        var hour = int.Parse(ActionPlanTimeBox.Text[..2]);
        var minute = int.Parse(ActionPlanTimeBox.Text[3..]);
        startTime = selectedDate.Date.AddHours(hour).AddMinutes(minute);
        var now = DateTime.Now;
        if (startTime < now)
        {
            message = "行动时间不能早于当前时间。";
            return false;
        }

        if (startTime > now.AddDays(7))
        {
            message = "行动时间只能设定在现在开始的 7 天之内。";
            return false;
        }

        return true;
    }

    private async void JoinFleetActionButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("预约行动计划需要先登录。"))
        {
            return;
        }

        e.Handled = true;
        var selectedPlan = GetSelectedActionPlanRow();
        if (selectedPlan is null || !selectedPlan.IsJoinable)
        {
            AppendOutput("Action reservation skipped: action plan is no longer joinable.");
            return;
        }

        if (_joinedActionPlanIds.Contains(_selectedActionPlanId))
        {
            if (await LeaveSelectedActionPlanAsync())
            {
                RefreshFleetOperationalSurfaces();
                AppendOutput("Action reservation canceled.");
            }

            return;
        }

        JoinActionPlanTitleText.Text = string.IsNullOrWhiteSpace(_fleetActionTitle)
            ? "行动计划"
            : _fleetActionTitle;
        JoinActionNotifyCheck.IsChecked = _joinActionNotifyMe;
        JoinActionPlanPanel.Show();
    }

    private void CancelJoinActionPlanButton_Click(object sender, RoutedEventArgs e)
    {
        JoinActionPlanPanel.Hide();
    }

    private async void ConfirmJoinActionPlanButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("预约行动计划需要先登录。"))
        {
            return;
        }

        _joinActionNotifyMe = JoinActionNotifyCheck.IsChecked == true;
        if (!await JoinSelectedActionPlanAsync())
        {
            NetworkStatusText.Text = "行动预约同步失败，已恢复本地预约状态。";
            AppendOutput("NETWORK | action reservation failed and rolled back");
            return;
        }

        JoinActionPlanPanel.Hide();
        RefreshFleetOperationalSurfaces();
        AppendOutput(_joinActionNotifyMe
            ? "Action joined. Email reminder requested for 5 minutes before start."
            : "Action joined.");
    }

    private async Task<bool> JoinSelectedActionPlanAsync()
    {
        if (string.IsNullOrWhiteSpace(_selectedActionPlanId))
        {
            return false;
        }

        var plan = _fleetActionPlans.FirstOrDefault(plan =>
            plan.Id.Equals(_selectedActionPlanId, StringComparison.OrdinalIgnoreCase));
        if (plan is null || !plan.IsJoinable || !_joinedActionPlanIds.Add(plan.Id))
        {
            return false;
        }

        var gameName = string.IsNullOrWhiteSpace(_localPlayer) ? "Unknown" : _localPlayer!;
        var callsign = string.IsNullOrWhiteSpace(_callsign) ? gameName : _callsign!;
        var participant = new ActionPlanParticipantRow(
            callsign,
            gameName,
            _avatarPath,
            GetInitials(gameName),
            _joinActionNotifyMe);
        plan.Participants.Add(participant);
        plan.RefreshParticipantSummary();
        SaveCurrentConfig();
        if (!await PushFleetActionPlanJoinAsync(plan, participant, silent: false))
        {
            _joinedActionPlanIds.Remove(plan.Id);
            plan.Participants.Remove(participant);
            plan.RefreshParticipantSummary();
            SaveCurrentConfig();
            return false;
        }

        return true;
    }

    private async Task<bool> LeaveSelectedActionPlanAsync()
    {
        if (string.IsNullOrWhiteSpace(_selectedActionPlanId))
        {
            return false;
        }

        var plan = _fleetActionPlans.FirstOrDefault(plan =>
            plan.Id.Equals(_selectedActionPlanId, StringComparison.OrdinalIgnoreCase));
        if (plan is null || !plan.IsJoinable || !_joinedActionPlanIds.Remove(plan.Id))
        {
            return false;
        }

        var rollbackState = CaptureFleetStateForRollback();
        var identities = EnumerateLocalIdentities().ToHashSet(StringComparer.OrdinalIgnoreCase);
        for (var index = plan.Participants.Count - 1; index >= 0; index--)
        {
            var participant = plan.Participants[index];
            if (identities.Contains(participant.GameName) ||
                identities.Contains(participant.Callsign) ||
                IsLocalPlayer(participant.GameName))
            {
                plan.Participants.RemoveAt(index);
            }
        }

        plan.RefreshParticipantSummary();
        SaveCurrentConfig();
        if (!await PushFleetActionPlanLeaveAsync(plan.Id, silent: false))
        {
            RestoreFleetStateAfterFailedMutation(rollbackState, "取消行动预约失败，已恢复本地预约状态。");
            return false;
        }

        RefreshOverlayWindow();
        RefreshFleetOperationalSurfaces();
        return true;
    }
}
