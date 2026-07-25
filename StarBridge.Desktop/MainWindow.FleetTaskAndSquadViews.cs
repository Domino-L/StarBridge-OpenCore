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

    private void SeedSquads()
    {
        if (_squads.Count > 0)
        {
            return;
        }
    }

    private void RenderSquads()
    {
        RepairLocalSquadLifecycle();

        var joinedSquadName = _joinedSquad?.Name;
        var joinedSquad = string.IsNullOrWhiteSpace(joinedSquadName)
            ? null
            : _squads.FirstOrDefault(squad =>
                squad.Name.Equals(joinedSquadName, StringComparison.OrdinalIgnoreCase));
        if (joinedSquad is not null && !ReferenceEquals(joinedSquad, _joinedSquad))
        {
            _joinedSquad = joinedSquad;
        }

        foreach (var squad in _squads)
        {
            squad.IsJoinedByCurrentUser = joinedSquad is not null && ReferenceEquals(squad, joinedSquad);
            squad.CanManageByCurrentUser = CanCurrentUserManageSquad(squad);
            squad.Members.Clear();
            squad.PreviewMembers.Clear();
            squad.StatusMembers.Clear();
            if (_hasFleet)
            {
                foreach (var player in _players.Where(player =>
                             player.SquadName.Equals(squad.Name, StringComparison.OrdinalIgnoreCase)))
                {
                    squad.Members.Add(CreateSquadAvatarRow(squad, player));
                    squad.StatusMembers.Add(CreateSquadStatusRow(squad, player));
                }
            }

            squad.RefreshComputed();
        }

        RefreshSquadPreviewMembers();

        NoSquadsPanel.Visibility = _squads.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        SquadSelectionList.Visibility = _squads.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        RefreshFleetMySquadSummary(joinedSquad);
    }

    private void RefreshFleetMySquadSummary(SquadRow? joinedSquad)
    {
        if (FleetMySquadEmptyPanel is null || FleetMySquadSummaryPanel is null)
        {
            return;
        }

        var hasJoinedSquad = joinedSquad is not null;
        FleetMySquadEmptyPanel.Visibility = hasJoinedSquad ? Visibility.Collapsed : Visibility.Visible;
        FleetMySquadSummaryPanel.Visibility = hasJoinedSquad ? Visibility.Visible : Visibility.Collapsed;
        FleetSquadCreateButton.IsEnabled = !CurrentUserCommandsAnySquad();
        FleetSquadCreateButton.ToolTip = FleetSquadCreateButton.IsEnabled
            ? "创建新的舰队小队"
            : "你已经负责一个舰队小队";
        if (joinedSquad is null)
        {
            return;
        }

        FleetMySquadNameText.Text = joinedSquad.Name;
        FleetMySquadCommanderText.Text = $"小队指挥官 / {joinedSquad.Commander}";
        FleetMySquadMemberText.Text = $"{joinedSquad.MemberCount} 名成员 · {joinedSquad.OnlineCount} 人在线";
        FleetMySquadTypeText.Text = $"定位 / {joinedSquad.Type}";
    }

    private void RefreshSquadPreviewLimitFromLayout()
    {
        var nextLimit = CalculateSquadPreviewLimit();
        if (nextLimit == _squadPreviewLimit)
        {
            return;
        }

        _squadPreviewLimit = nextLimit;
        RefreshSquadPreviewMembers();
    }

    private int CalculateSquadPreviewLimit()
    {
        var width = FleetSquadsDeckPanel?.ActualWidth ?? 0;
        if (width <= 0)
        {
            width = ActualWidth;
        }

        if (width >= 1320)
        {
            return 6;
        }

        if (width >= 1140)
        {
            return 5;
        }

        if (width >= 940)
        {
            return 4;
        }

        if (width >= 760)
        {
            return 3;
        }

        return 2;
    }

    private void RefreshSquadPreviewMembers()
    {
        foreach (var squad in _squads)
        {
            squad.PreviewMembers.Clear();
            foreach (var member in squad.Members
                         .OrderByDescending(member => member.IsCommander)
                         .Take(_squadPreviewLimit))
            {
                squad.PreviewMembers.Add(member);
            }

            squad.RefreshComputed();
        }
    }

    private void RepairLocalSquadLifecycle()
    {
        if (_joinedSquad is not null &&
            !_squads.Any(squad => squad.Name.Equals(_joinedSquad.Name, StringComparison.OrdinalIgnoreCase)))
        {
            _joinedSquad = null;
        }

        if (_selectedSquad is not null &&
            !_squads.Any(squad => squad.Name.Equals(_selectedSquad.Name, StringComparison.OrdinalIgnoreCase)))
        {
            _selectedSquad = _joinedSquad;
        }

        if (SquadSelectionList is not null &&
            !ReferenceEquals(SquadSelectionList.SelectedItem, _selectedSquad))
        {
            SquadSelectionList.SelectedItem = _selectedSquad;
        }
    }

    private MemberAvatarRow CreateSquadAvatarRow(SquadRow squad, PlayerRow player)
    {
        var isCommander = IsSquadCommander(squad, player);
        return new MemberAvatarRow(
            DisplayCallsign(player.Callsign, player.Name),
            GetInitials(player.Name),
            player.SharedOnlineStatusValue,
            player.AvatarPath,
            GetSquadNameBrush(squad, player),
            isCommander,
            player.Name,
            player.Callsign,
            player.AccountId,
            player.IsSelf,
            player.SharedLiveStatusValue);
    }

    private SquadMemberStatusRow CreateSquadStatusRow(SquadRow squad, PlayerRow player)
    {
        var canManageSquad = CanCurrentUserManageSquad(squad);
        var isTargetCommander = IsSquadCommander(squad, player);
        var isTargetSelf = IsLocalPlayerIdentity(player.Name, player.Callsign);
        return new SquadMemberStatusRow(
            GetInitials(player.Name),
            player.AvatarPath,
            GetSquadRole(squad, player),
            DisplayCallsign(player.Callsign, player.Name),
            player.Name,
            player.SharedOnlineStatusValue,
            player.SharedShipText,
            player.SharedLocationText,
            GetSquadNameBrush(squad, player),
            CanCurrentUserRemoveSquadMember(squad, player),
            squad.Name,
            canManageSquad && !isTargetCommander && !isTargetSelf,
            player.AccountId,
            player.IsSelf,
            player.SharedLiveStatusValue);
    }

    private bool CanCurrentUserManageSquad(SquadRow squad)
    {
        if (!_hasFleet)
        {
            return false;
        }

        if (IsCurrentUserFleetCommander())
        {
            return true;
        }

        var commanderGameName = GetGameNameFromDisplayName(squad.Commander);
        var commanderCallsign = GetCallsignFromDisplayName(squad.Commander);
        return (!string.IsNullOrWhiteSpace(_localPlayer) &&
                commanderGameName.Equals(_localPlayer, StringComparison.OrdinalIgnoreCase)) ||
               (!string.IsNullOrWhiteSpace(_callsign) &&
                commanderCallsign.Equals(_callsign, StringComparison.OrdinalIgnoreCase));
    }

    private bool CanCurrentUserRemoveSquadMember(SquadRow squad, PlayerRow player)
    {
        if (!CanCurrentUserManageSquad(squad))
        {
            return false;
        }

        if (!player.SquadName.Equals(squad.Name, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (IsSquadCommander(squad, player))
        {
            return false;
        }

        return !IsLocalPlayerIdentity(player.Name, player.Callsign);
    }

    private void RenderMySquad()
    {
        var squad = _selectedSquad;
        if (squad is null)
        {
            MySquadEmptyDetailPanel.Visibility = Visibility.Visible;
            MySquadDetailPanel.Visibility = Visibility.Collapsed;
            if (!MySquadDescriptionBox.IsKeyboardFocusWithin)
            {
                MySquadDescriptionBox.Text = "";
            }
            _mySquadMembers.Clear();
            return;
        }

        MySquadEmptyDetailPanel.Visibility = Visibility.Collapsed;
        MySquadDetailPanel.Visibility = Visibility.Visible;
        MySquadNameText.Text = squad.Name;
        MySquadCommanderText.Text = $"指挥官 / {squad.Commander}";
        MySquadMemberCountText.Text = $"{squad.Members.Count(member => member.Status == "Online")}/{squad.Members.Count} 在线";
        MySquadTypeText.Text = $"类型 / {squad.Type}";
        if (!MySquadDescriptionBox.IsKeyboardFocusWithin)
        {
            MySquadDescriptionBox.Text = squad.Description == "No squad briefing yet."
                ? "暂无小队简介。"
                : squad.Description;
        }
        MySquadIconText.Text = squad.Icon;
        LoadMySquadEmblem(squad.EmblemPath);

        _mySquadMembers.Clear();
        foreach (var player in _players.Where(player =>
                     player.SquadName.Equals(squad.Name, StringComparison.OrdinalIgnoreCase)))
        {
            _mySquadMembers.Add(CreateSquadStatusRow(squad, player));
        }
    }

    private static string GetSquadRole(SquadRow squad, PlayerRow player)
    {
        return IsSquadCommander(squad, player)
            ? "小队指挥官"
            : "成员";
    }

    private static bool IsSquadCommander(SquadRow squad, PlayerRow player)
    {
        return player.Name.Equals(GetGameNameFromDisplayName(squad.Commander), StringComparison.OrdinalIgnoreCase) ||
               player.Callsign?.Equals(GetCallsignFromDisplayName(squad.Commander), StringComparison.OrdinalIgnoreCase) == true;
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

    private void LoadMySquadEmblem(string? emblemPath)
    {
        if (string.IsNullOrWhiteSpace(emblemPath) || !File.Exists(emblemPath))
        {
            MySquadEmblemImage.Source = null;
            MySquadIconText.Visibility = Visibility.Visible;
            MySquadEmblemHintText.Visibility = Visibility.Visible;
            return;
        }

        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.UriSource = new Uri(emblemPath);
        image.EndInit();
        image.Freeze();

        MySquadEmblemImage.Source = image;
        MySquadIconText.Visibility = Visibility.Collapsed;
        MySquadEmblemHintText.Visibility = Visibility.Collapsed;
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
                yield return new OverlayLayoutItem("Squads", "小队态势", 0.01, 0.36, 0.13, 0.24, Brushes.DeepSkyBlue);
                yield return new OverlayLayoutItem("Members", "成员状态", 0.84, 0.58, 0.15, 0.18, Brushes.Gray);
                yield return new OverlayLayoutItem("Chat", "场景通讯", 0.35, 0.78, 0.30, 0.18, Brushes.MediumPurple);
                break;
            case OverlayPresetCommand:
                yield return new OverlayLayoutItem("Notice", "通讯事件", 0.285, 0, 0.43, 0.075, Brushes.Yellow);
                yield return new OverlayLayoutItem("Squads", "小队态势", 0.01, 0.30, 0.18, 0.42, Brushes.DeepSkyBlue);
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
