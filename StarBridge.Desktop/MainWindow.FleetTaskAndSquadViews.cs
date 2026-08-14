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

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void RefreshTaskManagementPanel()
    {
        if (ManageCurrentTaskTitleText is null)
        {
            return;
        }

        RefreshFleetManagementPermissions();

        ManageFleetNoticeTitleText.Text = string.IsNullOrWhiteSpace(_fleetNoticeTitle)
            ? "暂无舰队公告"
            : _fleetNoticeTitle;
        ManageFleetNoticeSummaryText.Text = string.IsNullOrWhiteSpace(_fleetNoticeContent)
            ? "舰队公告会显示在我的舰队信息栏。"
            : _fleetNoticeContent;
        RefreshManageFleetBasicProfile();

        if (FleetEmailNotificationsEnabledCheck is not null)
        {
            FleetEmailNotificationsEnabledCheck.IsChecked = _fleetEmailNotificationsEnabled;
            FleetEmailNotificationsStatusText.Text = _fleetEmailNotificationsEnabled
                ? "基础邮件通知已启用。"
                : "基础邮件通知已关闭。";
        }

        RefreshManageFleetOverview();

        SelectFeaturedActionPlan();
        foreach (var plan in _fleetActionPlans)
        {
            plan.RefreshParticipantSummary();
        }

        FleetActionPlansEmptyText.Visibility = GetVisibleActionPlans().Any()
            ? Visibility.Collapsed
            : Visibility.Visible;
        if (OpenActionPlanEditorButton is not null)
        {
            OpenActionPlanEditorButton.IsEnabled = CanCurrentUserPublishPlans() && CountOpenActionPlans() < 3;
        }

        var hasTask = !string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle);
        ManageCurrentTaskTitleText.Text = hasTask ? _fleetCurrentTaskTitle : "暂无当前任务";
        ManageCurrentTaskSummaryText.Text = hasTask
            ? FormatCurrentTaskPreview()
            : "请前往 管理舰队-发布任务 进行任务发布";
        ManageCurrentTaskMetaText.Text = hasTask && _fleetCurrentTaskTime is not null
            ? $"发布时间 / {_fleetCurrentTaskTime:yyyy-MM-dd HH:mm}"
            : "";

        var canPublishTasks = CanCurrentUserPublishTasks();
        OpenPublishTaskButton.IsEnabled = canPublishTasks;
        EditCurrentTaskButton.IsEnabled = hasTask && canPublishTasks;
        CompleteCurrentTaskButton.IsEnabled = hasTask && canPublishTasks;
        DeleteCurrentTaskButton.IsEnabled = hasTask && canPublishTasks;
        RenotifyCurrentTaskButton.IsEnabled = hasTask && canPublishTasks;
        FleetTaskHistoryEmptyText.Visibility = _fleetTaskHistory.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        ApplyFleetEventLogFilter();
        RefreshFleetEventCommandCenter();
    }

    private bool IsLocalPlayer(string playerName)
    {
        return !string.IsNullOrWhiteSpace(_localPlayer) &&
               playerName.Equals(_localPlayer, StringComparison.OrdinalIgnoreCase);
    }

    private bool IsLocalPlayerIdentity(string? gameName, string? callsign)
    {
        return (!string.IsNullOrWhiteSpace(gameName) &&
                !string.IsNullOrWhiteSpace(_localPlayer) &&
                gameName.Equals(_localPlayer, StringComparison.OrdinalIgnoreCase)) ||
               (!string.IsNullOrWhiteSpace(callsign) &&
                !string.IsNullOrWhiteSpace(_callsign) &&
                callsign.Equals(_callsign, StringComparison.OrdinalIgnoreCase));
    }

    private bool IsCurrentUserFleetCommander()
    {
        return !string.IsNullOrWhiteSpace(_localPlayer) &&
               IsFleetCommander(_localPlayer, _callsign);
    }

    private static string GetGameNameFromDisplayName(string value)
    {
        var start = value.LastIndexOf('(');
        var end = value.LastIndexOf(')');
        return start >= 0 && end > start
            ? value[(start + 1)..end].Trim()
            : value.Trim();
    }

    private static string GetCallsignFromDisplayName(string value)
    {
        var start = value.LastIndexOf('(');
        return start > 0 ? value[..start].Trim() : value.Trim();
    }

    private static string GetInitials(string name)
    {
        return string.IsNullOrWhiteSpace(name)
            ? "?"
            : name.Length >= 2 ? name[..2].ToUpperInvariant() : name[..1].ToUpperInvariant();
    }

    private static IEnumerable<OverlayLayoutItem> CreateDefaultOverlayLayout()
    {
        return CreateDefaultOverlayLayout(OverlayPresetDefault);
    }

    private static IEnumerable<OverlayLayoutItem> CreateDefaultOverlayLayout(string preset)
    {
        switch (NormalizeOverlayPreset(preset))
        {
            case OverlayPresetCompact:
                yield return new OverlayLayoutItem("Notice", "通讯事件", 0.34, 0, 0.32, 0.055, Brushes.Yellow);
                yield return new OverlayLayoutItem("Squads", "舰队总览", 0.01, 0.36, 0.13, 0.24, Brushes.DeepSkyBlue);
                yield return new OverlayLayoutItem("Members", "成员状态", 0.84, 0.58, 0.15, 0.18, Brushes.Gray);
                yield return new OverlayLayoutItem("Chat", "场景通讯", 0.35, 0.78, 0.30, 0.18, Brushes.MediumPurple);
                break;
            case OverlayPresetCommand:
                yield return new OverlayLayoutItem("Notice", "通讯事件", 0.285, 0, 0.43, 0.075, Brushes.Yellow);
                yield return new OverlayLayoutItem("Squads", "舰队总览", 0.01, 0.30, 0.18, 0.42, Brushes.DeepSkyBlue);
                yield return new OverlayLayoutItem("Members", "成员状态", 0.78, 0.54, 0.21, 0.26, Brushes.Gray);
                yield return new OverlayLayoutItem("Chat", "场景通讯", 0.35, 0.75, 0.30, 0.21, Brushes.MediumPurple);
                break;
            default:
                foreach (var item in OverlayLayoutItem.ParseMany(OverlayDefaultPreset.LayoutPayload))
                {
                    yield return item;
                }
                break;
        }
    }
}
