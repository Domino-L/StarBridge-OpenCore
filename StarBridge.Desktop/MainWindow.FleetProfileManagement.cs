using Microsoft.Win32;
using StarBridge.Core.Events;
using StarBridge.Core.FleetChat;
using StarBridge.Core.Fleets;
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
using StarBridge.Desktop.Theming;
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
    private void RefreshNoticePanel()
    {
        var hasNotice = !string.IsNullOrWhiteSpace(_fleetNoticeTitle);
        if (!hasNotice)
        {
            FleetActionPlanTitleText.Text = "暂无组织公告";
            FleetActionPlanSummaryText.Text = "等待组织负责人发布公告";
            FleetActionPlanTimeText.Text = "";
            JoinFleetActionButton.Visibility = Visibility.Collapsed;
            return;
        }

        FleetActionPlanTitleText.Text = _fleetNoticeTitle;
        FleetActionPlanSummaryText.Text = _fleetNoticeContent;
        FleetActionPlanTimeText.Text = CanCurrentUserManageFleetInfo()
            ? "点击编辑公告"
            : "";
        JoinFleetActionButton.Visibility = Visibility.Collapsed;
    }

    private void RefreshCurrentTaskPanel()
    {
        var hasTask = !string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle);
        if (!hasTask)
        {
            FleetActionPlanTitleText.Text = CanCurrentUserPublishTasks()
                ? "暂无当前任务"
                : "当前无任务";
            FleetActionPlanSummaryText.Text = CanCurrentUserPublishTasks()
                ? "请前往 管理组织-发布任务 进行任务发布"
                : "";
            FleetActionPlanTimeText.Text = "";
            JoinFleetActionButton.Visibility = Visibility.Collapsed;
            return;
        }

        FleetActionPlanTitleText.Text = _fleetCurrentTaskTitle;
        FleetActionPlanSummaryText.Text = FormatCurrentTaskPreview();
        FleetActionPlanTimeText.Text = _fleetCurrentTaskTime is null
            ? "点击查看任务详情"
            : $"发布时间 / {_fleetCurrentTaskTime:yyyy-MM-dd HH:mm}    点击查看任务详情";
        JoinFleetActionButton.Visibility = Visibility.Collapsed;
    }

    private string FormatCurrentTaskPreview()
    {
        var lines = new List<string>();
        var taskInfo = ParseFleetTaskBriefInfo(_fleetCurrentTaskBrief);
        var brief = FormatTaskBriefForDisplay(taskInfo);
        if (!string.IsNullOrWhiteSpace(brief))
        {
            lines.Add($"任务简述 / {brief}");
        }

        var condition = FormatTaskConditionSummary(taskInfo);
        if (!string.IsNullOrWhiteSpace(condition))
        {
            lines.Add($"任务条件 / {condition}");
        }

        if (!string.IsNullOrWhiteSpace(taskInfo.Division) &&
            !taskInfo.Division.Equals("未指定", StringComparison.OrdinalIgnoreCase))
        {
            lines.Add($"分工提示 / {taskInfo.Division}");
        }

        if (!string.IsNullOrWhiteSpace(_fleetCurrentTaskRally))
        {
            lines.Add($"集结点 / {_fleetCurrentTaskRally}");
        }

        if (!string.IsNullOrWhiteSpace(_fleetCurrentTaskShip))
        {
            lines.Add($"指定舰船 / {_fleetCurrentTaskShip}");
        }

        lines.Add($"参与范围 / {_fleetCurrentTaskParticipants}");
        return string.Join(Environment.NewLine, lines);
    }

    private void RefreshActionPlanPanel()
    {
        SelectFeaturedActionPlan();
        var hasAction = !string.IsNullOrWhiteSpace(_fleetActionTitle);
        if (!hasAction)
        {
            FleetActionPlanTitleText.Text = "暂无行动计划，等待下一步指挥";
            FleetActionPlanSummaryText.Text = "";
            FleetActionPlanTimeText.Text = "";
            JoinFleetActionButton.Visibility = Visibility.Collapsed;
            JoinFleetActionButton.Content = "参与";
            JoinFleetActionButton.IsEnabled = true;
            return;
        }

        FleetActionPlanTitleText.Text = _fleetActionTitle;
        FleetActionPlanSummaryText.Text = _fleetActionContent;
        FleetActionPlanTimeText.Text = _fleetActionStartTime is null
            ? ""
            : $"开始时间 / {_fleetActionStartTime:yyyy-MM-dd HH:mm}";
        var selectedPlan = GetSelectedActionPlanRow();
        if (selectedPlan is not null && !selectedPlan.IsJoinable)
        {
            var status = selectedPlan.StatusText.Replace("状态 / ", "");
            FleetActionPlanTimeText.Text = $"{FleetActionPlanTimeText.Text} / {status}";
            JoinFleetActionButton.Visibility = Visibility.Visible;
            JoinFleetActionButton.Content = selectedPlan.EffectiveStatus switch
            {
                "Reached" => "已到时",
                "Completed" => "已完成",
                "Canceled" => "已取消",
                _ => "不可参与"
            };
            JoinFleetActionButton.IsEnabled = false;
            return;
        }

        JoinFleetActionButton.Visibility = Visibility.Visible;
        var joined = _joinedActionPlanIds.Contains(_selectedActionPlanId);
        JoinFleetActionButton.Content = joined ? "取消预约" : "参与";
        JoinFleetActionButton.IsEnabled = true;
    }

    private void SelectFeaturedActionPlan()
    {
        var visiblePlans = GetVisibleActionPlans().ToArray();
        var selected = visiblePlans
            .Where(plan => plan.IsJoinable)
            .OrderBy(plan => plan.StartTime)
            .FirstOrDefault() ??
            visiblePlans
                .Where(plan => plan.IsReached)
                .OrderByDescending(plan => plan.StartTime)
                .FirstOrDefault() ??
            visiblePlans
                .Where(plan => plan.IsCompleted)
                .OrderByDescending(plan => plan.StartTime)
                .FirstOrDefault();

        if (selected is null)
        {
            _selectedActionPlanId = "";
            _fleetActionTitle = "";
            _fleetActionContent = "";
            _fleetActionStartTime = null;
            _fleetActionNotifyMembers = false;
            return;
        }

        _selectedActionPlanId = selected.Id;
        _fleetActionTitle = selected.Title;
        _fleetActionContent = selected.Content;
        _fleetActionStartTime = selected.StartTime;
        _fleetActionNotifyMembers = selected.NotifyMembers;
    }

    private IEnumerable<FleetActionPlanRow> GetVisibleActionPlans()
    {
        var now = DateTime.Now;
        var from = now.AddDays(-2);
        var to = now.AddDays(7);
        return _fleetActionPlans
            .Where(plan => plan.StartTime >= from && plan.StartTime <= to)
            .OrderBy(plan => plan.StartTime);
    }

    private int CountOpenActionPlans()
    {
        return _fleetActionPlans.Count(plan => plan.IsOpen);
    }

    private void RefreshManageFleetOverview()
    {
        if (ManageOverviewNoticeText is null)
        {
            return;
        }

        var pendingApplicationCount = BuildPendingFleetApplicationRows().Length;
        var hasDescription = !string.IsNullOrWhiteSpace(_fleetDescription);
        var hasAnnouncement = !string.IsNullOrWhiteSpace(_fleetNoticeTitle);
        ManageOverviewProfileText.Text = hasDescription
            ? "资料与介绍已完善"
            : "组织介绍尚未填写";
        ManageOverviewNoticeText.Text = string.IsNullOrWhiteSpace(_fleetNoticeTitle)
            ? "尚未发布"
            : $"已发布 · {_fleetNoticeTitle}";
        ManageOverviewApplicationText.Text = $"{pendingApplicationCount.ToString(CultureInfo.InvariantCulture)} 个";
        ManageOverviewMemberText.Text = $"{_players.Count.ToString(CultureInfo.InvariantCulture)} 名成员";
        ManageOverviewResourceText.Text = _fleetShipInventory.Count > 0
            ? $"{_fleetShipInventory.Count.ToString(CultureInfo.InvariantCulture)} 艘舰船"
            : "等待成员共享";
        var governanceLogCount = _allFleetEventLogs.Count(log => !IsFleetActionManagementLog(log));
        ManageOverviewAuditText.Text = $"{governanceLogCount.ToString(CultureInfo.InvariantCulture)} 条";

        var priority = FleetManagementOverviewPresentation.BuildPriority(
            pendingApplicationCount,
            hasDescription,
            CanCurrentUserReviewFleetApplications(),
            CanCurrentUserEditAnyFleetProfileField(),
            CanCurrentUserViewFleetLogs());
        ManageOverviewPriorityTitleText.Text = priority.Title;
        ManageOverviewPriorityDescriptionText.Text = priority.Description;
        ManageOverviewPriorityTitleText.Foreground = FleetCommandBrush(
            priority.RequiresAttention ? BridgeBrushToken.StatusWarn : BridgeBrushToken.StatusOk);
        ManageOverviewPriorityButton.Content = priority.ActionText;
        ManageOverviewPriorityButton.Tag = priority.Target.ToString();
        ManageOverviewPriorityButton.Visibility = priority.Target == FleetManagementOverviewTarget.None
            ? Visibility.Collapsed
            : Visibility.Visible;
    }

    private void ManageOverviewShortcutButton_Click(object sender, RoutedEventArgs e)
    {
        var target = (sender as FrameworkElement)?.Tag?.ToString()?.Trim().ToLowerInvariant();
        var targetTab = target switch
        {
            "applications" => FleetApplicationsTab,
            "announcement" => ManageFleetNoticeTab,
            "profile" => ManageFleetProfileTab,
            "members" => ManageFleetMembersTab,
            "visibility" => ManageFleetShipsTab,
            "log" => ManageFleetLogTab,
            _ => null
        };

        OpenManageFleetSection(targetTab);
    }

    private void RefreshManageFleetJoinSettings(int? pendingApplicationCount = null)
    {
        if (ManageJoinPolicyBox is null)
        {
            return;
        }

        var pendingCount = pendingApplicationCount ?? BuildPendingFleetApplicationRows().Length;
        var normalizedPolicy = NormalizeFleetJoinPolicyTag(_fleetJoinPolicy);

        var wasRefreshing = _isManageProfileRefreshing;
        _isManageProfileRefreshing = true;
        try
        {
            SelectComboBoxItemByTag(ManageJoinPolicyBox, normalizedPolicy);
        }
        finally
        {
            _isManageProfileRefreshing = wasRefreshing;
        }

        RefreshManageFleetJoinDerivedText(normalizedPolicy, pendingCount);
        RefreshManageFleetRecruitingSettings();
    }

    private void RefreshManageFleetJoinDerivedText(string? joinPolicy, int? pendingApplicationCount = null)
    {
        var normalizedPolicy = NormalizeFleetJoinPolicyTag(joinPolicy);

        if (ManageJoinPendingCountText is not null)
        {
            var pendingCount = pendingApplicationCount ?? BuildPendingFleetApplicationRows().Length;
            ManageJoinPendingCountText.Text = pendingCount.ToString(CultureInfo.InvariantCulture);
        }

        if (ManageJoinPolicySummaryText is not null)
        {
            ManageJoinPolicySummaryText.Text = FormatFleetJoinPolicy(normalizedPolicy);
        }

        if (ManageJoinAudienceText is not null)
        {
            ManageJoinAudienceText.Text = normalizedPolicy switch
            {
                "Closed" => "暂不接受新成员",
                "Invite" => "仅接受邀请",
                _ => "所有玩家"
            };
        }

        if (ManageJoinReviewText is not null)
        {
            ManageJoinReviewText.Text = normalizedPolicy switch
            {
                "Application" => "需要管理者审核",
                "Closed" => "入口已关闭",
                "Invite" => "由管理者发起邀请",
                _ => "无需审核"
            };
        }

        if (ManageJoinPolicyImpactText is not null)
        {
            ManageJoinPolicyImpactText.Text = normalizedPolicy switch
            {
                "Application" => "玩家可在寻找组织中提交申请，批准后才会加入组织。",
                "Invite" => "组织不会开放公开入口，后续通过邀请流程加入。",
                "Closed" => "组织入口会显示为暂停加入，玩家不能直接加入或提交申请。",
                _ => "玩家可在寻找组织中直接加入，适合公开招募阶段。"
            };
        }
    }

    private void RefreshManageFleetRecruitingSettings()
    {
        if (ManageRecruitingEnabledCheck is null)
        {
            return;
        }

        var wasRefreshing = _isManageProfileRefreshing;
        _isManageProfileRefreshing = true;
        try
        {
            ManageRecruitingEnabledCheck.IsChecked = _fleetRecruitingEnabled;
            SelectComboBoxItemByTag(ManageRecruitingTargetBox, _fleetRecruitingTarget);
            SelectComboBoxItemByTag(ManageInviteCodePolicyBox, _fleetInviteCodeCreationPolicy);
            SelectComboBoxItemByTag(ManageInvitationCardPolicyBox, _fleetInvitationCardPolicy);
        }
        finally
        {
            _isManageProfileRefreshing = wasRefreshing;
        }

        RefreshManageFleetRecruitingSummary();
    }

    private void RefreshManageFleetRecruitingSummary()
    {
        if (ManageRecruitingSummaryText is null)
        {
            return;
        }

        var recruitingEnabled = ManageRecruitingEnabledCheck?.IsChecked == true;
        var recruitingTarget = NormalizeFleetRecruitingTarget(GetSelectedComboBoxTag(ManageRecruitingTargetBox) ?? _fleetRecruitingTarget);
        ManageRecruitingSummaryText.Text = recruitingEnabled
            ? $"寻找组织会标记为正在招募，优先面向：{recruitingTarget}。组织说明统一使用基础资料中的组织介绍。"
            : "未开启招募时，组织仍可被搜索，但不会获得招募展示加权。";
    }

    private void RefreshManageFleetPublicVisibilitySettings()
    {
        if (ManagePublicListingCheck is null)
        {
            return;
        }

        ManagePublicListingCheck.IsChecked = _fleetPublicListingEnabled;
        ManagePublicProfileCheck.IsChecked = true;
        ManagePublicDescriptionCheck.IsChecked = _manageShowDescriptionPublic;
        ManagePublicTagsCheck.IsChecked = _fleetPublicShowTags;
        ManagePublicSystemsCheck.IsChecked = _fleetPublicShowActiveSystems;
        ManagePublicActivityCheck.IsChecked = _fleetPublicShowActivityTime;
        SelectComboBoxItemByTag(ManagePublicMemberScaleBox, _fleetPublicMemberScaleMode);
        SelectComboBoxItemByTag(ManagePublicShipScaleBox, _fleetPublicShipScaleMode);
        RefreshManageFleetPublicVisibilitySummary();
    }

    private void RefreshManageFleetPublicVisibilitySummary()
    {
        if (ManagePublicVisibilitySummaryText is null)
        {
            return;
        }

        var listingEnabled = ManagePublicListingCheck?.IsChecked ?? _fleetPublicListingEnabled;
        const bool profileEnabled = true;
        var memberScaleMode = NormalizeFleetPublicMemberScaleMode(
            GetSelectedComboBoxTag(ManagePublicMemberScaleBox) ?? _fleetPublicMemberScaleMode);
        var shipScaleMode = NormalizeFleetPublicShipScaleMode(
            GetSelectedComboBoxTag(ManagePublicShipScaleBox) ?? _fleetPublicShipScaleMode);
        var listing = listingEnabled ? "公开展示" : "不出现在寻找组织";
        var profile = profileEnabled ? "资料可见" : "资料关闭";
        var members = memberScaleMode switch
        {
            FleetPublicMemberScaleApprox => "规模区间",
            FleetPublicMemberScaleHidden => "隐藏规模",
            _ => "精确人数"
        };
        var ships = shipScaleMode switch
        {
            FleetPublicShipScaleTotalOnly => "舰船总数",
            FleetPublicShipScaleHidden => "隐藏资源",
            _ => "资源摘要"
        };
        ManagePublicVisibilitySummaryText.Text = $"{listing} · {profile} · {members} · {ships}";
    }

    private void RefreshManageFleetBasicProfile(bool forceTextBoxes = false)
    {
        if (ManageBasicFleetNameText is null || ManageProfileFleetNameBox is null)
        {
            return;
        }

        // Passive fleet refreshes must not replace an in-progress settings draft.
        // Saving/discarding passes forceTextBoxes so the controls can be reconciled explicitly.
        var preserveDraft = _isManageProfileDirty && !forceTextBoxes;
        _isManageProfileRefreshing = true;
        try
        {
            var fleetName = string.IsNullOrWhiteSpace(_fleetName) ? "未命名组织" : _fleetName;
            var fleetCode = string.IsNullOrWhiteSpace(_fleetCode) ? "未设置" : _fleetCode;

            ManageBasicFleetNameText.Text = fleetName;
            ManageBasicFleetCodeText.Text = fleetCode;

            SetImagePreview(ManageProfileLogoImage, ManageProfileLogoText, _fleetLogoPath);
            SetImagePreview(ManageProfileBannerImage, ManageProfileBannerText, _fleetBannerPath);

            if (!preserveDraft)
            {
                SetTextIfSafe(ManageProfileFleetNameBox, fleetName, forceTextBoxes);
                SetTextIfSafe(ManageProfileFleetCodeBox, fleetCode, forceTextBoxes);
                SetTextIfSafe(ManageProfileShortNameBox, _manageProfileDisplayShortName, forceTextBoxes);
                SetTextIfSafe(ManageProfilePublicNameBox, _manageProfilePublicDisplayName, forceTextBoxes);
                SetTextIfSafe(FleetDescriptionEditBox, string.IsNullOrWhiteSpace(_fleetDescription) ? "" : _fleetDescription, forceTextBoxes);
                SetTextIfSafe(ManageProfileAnnouncementBox, string.IsNullOrWhiteSpace(_fleetNoticeContent) ? "" : _fleetNoticeContent, forceTextBoxes);
                RefreshFleetActivityWindowEditor();
                SelectComboBoxItemByContent(ManageFleetActivityCadenceBox, _fleetActivityCadence);

                ManageProfileShowDescriptionCheck.IsChecked = _manageShowDescriptionPublic;
                ManageProfileShowAnnouncementCheck.IsChecked = _manageShowAnnouncementPublic;
                ManageProfileAllowPublicProfileCheck.IsChecked = true;
                RefreshManageFleetPublicVisibilitySettings();

                RefreshManageProfileCharacterCounters();
                RefreshManageProfileSelectedTags();
                RefreshManageProfileSystemOptionsState();
            }

            ManageBasicCreatedAtText.Text = _fleetJoinedAtUtc == DateTimeOffset.MinValue
                ? "未知"
                : _fleetJoinedAtUtc.ToLocalTime().ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
            ManageBasicMemberCountText.Text = _players.Count.ToString(CultureInfo.InvariantCulture);
            ManageBasicShipCountText.Text = _fleetShipInventory.Count.ToString(CultureInfo.InvariantCulture);
            var latestProfileUpdate = _allFleetEventLogs
                .Where(log => $"{log.Type} {log.Title}".Contains("资料", StringComparison.OrdinalIgnoreCase) ||
                              $"{log.Type} {log.Title}".Contains("公告", StringComparison.OrdinalIgnoreCase))
                .OrderByDescending(log => log.Timestamp)
                .FirstOrDefault();
            ManageBasicUpdatedAtText.Text = latestProfileUpdate is null
                ? "暂无"
                : latestProfileUpdate.Timestamp.ToLocalTime().ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture);
            if (!preserveDraft && ManageFleetLanguageBox is not null)
            {
                ManageFleetLanguageBox.SelectedIndex = 0;
            }

            if (!preserveDraft)
            {
                SelectFleetTimeZone(_fleetTimeZoneId);
                RefreshManageFleetActivityTimeZoneSummary();
                SetTextIfSafe(ManageFleetWebsiteBox, _fleetWebsiteUrl, forceTextBoxes);
                RefreshFleetExternalContactsEditor();
                RefreshManageFleetJoinSettings();
            }
        }
        finally
        {
            _isManageProfileRefreshing = false;
        }

        SetManageProfileEditMode(CanCurrentUserManageFleetInfo());
        RefreshManageSettingsPreview();
    }

    private void ManageProfileEditButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("编辑组织基础资料需要先登录。"))
        {
            return;
        }

        if (!CanCurrentUserManageFleetInfo())
        {
            SetFleetDescriptionStatus("当前账号没有修改组织资料的权限。", ManageProfileStatusTone.Locked);
            return;
        }

        SetManageProfileEditMode(true);
        SetFleetDescriptionStatus("正在编辑基础资料。保存前只在本地预览中生效。", ManageProfileStatusTone.Info);
    }

    private void SetManageProfileEditMode(bool isEditing)
    {
        _isManageProfileEditMode = isEditing;
        var canEditProfile = isEditing && CanCurrentUserEditFleetProfile();
        var canEditAvatar = isEditing && CanCurrentUserEditFleetAvatar();
        var canEditBanner = isEditing && CanCurrentUserEditFleetBanner();
        var canAccessProfileFields = CanCurrentUserEditFleetProfile();
        var canAccessAvatar = CanCurrentUserEditFleetAvatar();
        if (!isEditing && !_isManageProfileDirty)
        {
            _manageProfileDraftBaselineStateJson = null;
        }

        if (ManageProfileEditButton is not null)
        {
            ManageProfileEditButton.Visibility = Visibility.Collapsed;
            ManageProfileEditButton.IsEnabled = false;
        }

        RefreshManageProfileSaveControls();

        if (ManageProfileLogoButton is not null)
        {
            ManageProfileLogoButton.IsEnabled = canEditAvatar;
            ManageProfileLogoButton.Opacity = canEditAvatar ? 1 : 0.62;
        }

        if (ManageProfileBannerButton is not null)
        {
            ManageProfileBannerButton.IsEnabled = canEditBanner;
            ManageProfileBannerButton.Opacity = canEditBanner ? 1 : 0.62;
        }

        if (ManageProfileRemoveBannerButton is not null)
        {
            var canRemoveBanner = canEditBanner && !string.IsNullOrWhiteSpace(_fleetBannerPath);
            ManageProfileRemoveBannerButton.IsEnabled = canRemoveBanner;
            ManageProfileRemoveBannerButton.Opacity = canRemoveBanner ? 1 : 0.62;
        }

        if (ManageProfilePermissionNotice is not null && ManageProfilePermissionNoticeText is not null)
        {
            var lockedAreas = new List<string>();
            if (!canAccessProfileFields)
            {
                lockedAreas.Add("组织介绍、活跃区域、活动信息、更多信息");
            }

            if (!canAccessAvatar)
            {
                lockedAreas.Add("组织标志");
            }

            ManageProfilePermissionNotice.Visibility = lockedAreas.Count > 0
                ? Visibility.Visible
                : Visibility.Collapsed;
            ManageProfilePermissionNoticeText.Text = lockedAreas.Count > 0
                ? $"当前账号不能更改：{string.Join("、", lockedAreas)}。"
                : "";
        }

        SetTextBoxEditableState(ManageProfileFleetNameBox, false);
        SetTextBoxEditableState(ManageProfileFleetCodeBox, false);
        SetTextBoxEditableState(ManageProfileShortNameBox, canEditProfile);
        SetTextBoxEditableState(ManageProfilePublicNameBox, canEditProfile);
        SetTextBoxEditableState(FleetDescriptionEditBox, canEditProfile);
        SetTextBoxEditableState(ManageProfileAnnouncementBox, canEditProfile);
        SetTextBoxEditableState(ManageFleetWebsiteBox, canEditProfile);
        SetFleetActivityWindowEditorEditableState(canEditProfile);
        SetComboBoxEditableState(ManageFleetActivityCadenceBox, canEditProfile);
        SetComboBoxEditableState(ManageFleetTimeZoneBox, canEditProfile);
        SetComboBoxEditableState(ManageJoinPolicyBox, canEditProfile);
        SetComboBoxEditableState(ManageRecruitingTargetBox, canEditProfile);
        SetComboBoxEditableState(ManageInviteCodePolicyBox, canEditProfile);
        SetComboBoxEditableState(ManageInvitationCardPolicyBox, canEditProfile);
        SetComboBoxEditableState(ManagePublicMemberScaleBox, canEditProfile);
        SetComboBoxEditableState(ManagePublicShipScaleBox, canEditProfile);

        SetCheckBoxEditableState(ManageProfileShowDescriptionCheck, canEditProfile);
        SetCheckBoxEditableState(ManageProfileShowAnnouncementCheck, canEditProfile);
        SetCheckBoxEditableState(ManageProfileAllowPublicProfileCheck, canEditProfile);
        SetCheckBoxEditableState(ManageRecruitingEnabledCheck, canEditProfile);
        SetCheckBoxEditableState(ManagePublicListingCheck, canEditProfile);
        SetCheckBoxEditableState(ManagePublicProfileCheck, canEditProfile);
        SetCheckBoxEditableState(ManagePublicDescriptionCheck, canEditProfile);
        SetCheckBoxEditableState(ManagePublicTagsCheck, canEditProfile);
        SetCheckBoxEditableState(ManagePublicSystemsCheck, canEditProfile);
        SetCheckBoxEditableState(ManagePublicActivityCheck, canEditProfile);
        if (ManageProfileSystemOptionsList is not null)
        {
            ManageProfileSystemOptionsList.IsEnabled = canEditProfile && _manageFleetSystemOptions.Any(option => option.IsImageAvailable);
            ManageProfileSystemOptionsList.Opacity = ManageProfileSystemOptionsList.IsEnabled ? 1 : 0.75;
        }

        if (ManageProfileEditTagsButton is not null)
        {
            ManageProfileEditTagsButton.IsEnabled = canEditProfile;
            ManageProfileEditTagsButton.Opacity = canEditProfile ? 1 : 0.62;
        }

        if (ManageAddExternalContactButton is not null)
        {
            ManageAddExternalContactButton.IsEnabled = canEditProfile && _fleetExternalContacts.Count < 5;
            ManageAddExternalContactButton.Opacity = ManageAddExternalContactButton.IsEnabled ? 1 : 0.62;
        }

        if (ManageUnsavedChangesBar is not null)
        {
            ManageUnsavedChangesBar.Visibility = _isManageProfileDirty
                ? Visibility.Visible
                : Visibility.Collapsed;
        }
    }

    private void EnsureManageProfileDraftBaseline()
    {
        if (!_hasFleet ||
            !string.IsNullOrWhiteSpace(_manageProfileDraftBaselineStateJson))
        {
            return;
        }

        _manageProfileDraftBaselineStateJson = CaptureFleetStateForRollback();
    }

    private void ClearManageProfileDraftBaseline()
    {
        _manageProfileDraftBaselineStateJson = null;
    }

    private bool IsManageProfileDraftChangeSuppressed()
    {
        return _isManageProfileRefreshing || _isManageProfileDiscardingDraft;
    }

    private bool ShouldIgnoreProgrammaticManageProfileDraftChanged(object sender)
    {
        if (IsManageProfileDraftChangeSuppressed())
        {
            return true;
        }

        if (!string.IsNullOrWhiteSpace(_manageProfileDraftBaselineStateJson))
        {
            return false;
        }

        return sender is FrameworkElement element &&
               !element.IsKeyboardFocusWithin &&
               !element.IsMouseCaptureWithin;
    }

    private void RefreshManageProfileSaveControls()
    {
        var canSave = _isManageProfileEditMode && _isManageProfileDirty;
        if (ManageProfileHeaderSaveButton is not null)
        {
            ManageProfileHeaderSaveButton.Visibility = canSave ? Visibility.Visible : Visibility.Collapsed;
            ManageProfileHeaderSaveButton.IsEnabled = canSave;
        }

        if (ManageProfileHeaderCancelButton is not null)
        {
            ManageProfileHeaderCancelButton.Visibility = canSave ? Visibility.Visible : Visibility.Collapsed;
            ManageProfileHeaderCancelButton.IsEnabled = canSave;
        }
    }

    private static void SetTextBoxEditableState(System.Windows.Controls.TextBox? textBox, bool isEditing)
    {
        if (textBox is null)
        {
            return;
        }

        textBox.IsReadOnly = !isEditing;
        textBox.Opacity = isEditing ? 1 : 0.82;
        textBox.Focusable = isEditing;
    }

    private static void SetComboBoxEditableState(System.Windows.Controls.ComboBox? comboBox, bool isEditing)
    {
        if (comboBox is null)
        {
            return;
        }

        comboBox.IsEnabled = isEditing;
        comboBox.Opacity = isEditing ? 1 : 0.82;
    }

    private static void SetCheckBoxEditableState(System.Windows.Controls.CheckBox? checkBox, bool isEditing)
    {
        if (checkBox is null)
        {
            return;
        }

        checkBox.IsEnabled = isEditing;
        checkBox.Opacity = isEditing ? 1 : 0.82;
    }

    private void ManageProfileDraftChanged(object sender, TextChangedEventArgs e)
    {
        if (ShouldIgnoreProgrammaticManageProfileDraftChanged(sender))
        {
            return;
        }

        HandleManageProfileDraftChanged();
    }

    private void ManageProfileDraftChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ShouldIgnoreProgrammaticManageProfileDraftChanged(sender))
        {
            return;
        }

        HandleManageProfileDraftChanged();
    }

    private void ManageProfileDraftChanged(object sender, RoutedEventArgs e)
    {
        if (ShouldIgnoreProgrammaticManageProfileDraftChanged(sender))
        {
            return;
        }

        HandleManageProfileDraftChanged();
    }

    private void ManageProfileSystemSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (IsManageProfileDraftChangeSuppressed())
        {
            return;
        }

        EnsureManageProfileDraftBaseline();
        foreach (var addedItem in e.AddedItems.OfType<ManageFleetSystemOptionRow>().Where(option => !option.IsImageAvailable).ToArray())
        {
            ManageProfileSystemOptionsList.SelectedItems.Remove(addedItem);
            SetFleetDescriptionStatus("请先放置本地星系图片后再选择所属星系。", ManageProfileStatusTone.Warning);
        }

        SyncSelectedFleetSystemIdsFromList();

        if (_selectedFleetSystemIds.Count > 0)
        {
            SetFleetDescriptionStatus(
                $"已选择 {_selectedFleetSystemIds.Count.ToString(CultureInfo.InvariantCulture)} 个主要活跃星系，保存后生效。",
                ManageProfileStatusTone.Info);
        }
        else
        {
            SetFleetDescriptionStatus("主要活跃星系已清空，保存后生效。", ManageProfileStatusTone.Warning);
        }

        HandleManageProfileDraftChanged();
    }

    private void SyncSelectedFleetSystemIdsFromList()
    {
        if (ManageProfileSystemOptionsList is null)
        {
            return;
        }

        SetSelectedFleetSystemIds(
            ManageProfileSystemOptionsList.SelectedItems
                .OfType<ManageFleetSystemOptionRow>()
                .Where(option => option.IsImageAvailable)
                .Select(option => option.Id),
            refreshSelection: false);
    }

    private void HandleManageProfileDraftChanged()
    {
        if (IsManageProfileDraftChangeSuppressed())
        {
            return;
        }

        EnsureManageProfileDraftBaseline();
        SyncFleetActivityWindowsFromEditor();
        RefreshManageFleetJoinDerivedText(GetSelectedComboBoxTag(ManageJoinPolicyBox) ?? _fleetJoinPolicy);
        RefreshManageFleetRecruitingSummary();
        RefreshManageFleetPublicVisibilitySummary();
        RefreshManageProfileCharacterCounters();
        RefreshManageFleetActivityTimeZoneSummary();
        SetManageProfileDirty(true);
        SetManageProfileSaveBarMessage("");
        RefreshManageSettingsPreview();
    }

    private void RefreshManageProfileCharacterCounters()
    {
        if (ManageProfileDescriptionCountText is not null)
        {
            var length = NormalizeFleetDescription(FleetDescriptionEditBox?.Text).Length;
            ManageProfileDescriptionCountText.Text = $"{length.ToString(CultureInfo.InvariantCulture)} / 500";
        }

        if (FleetDescriptionPlaceholderText is not null)
        {
            FleetDescriptionPlaceholderText.Visibility = string.IsNullOrWhiteSpace(NormalizeFleetDescription(FleetDescriptionEditBox?.Text))
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (ManageProfileAnnouncementCountText is not null)
        {
            var length = ManageProfileAnnouncementBox?.Text?.Length ?? 0;
            ManageProfileAnnouncementCountText.Text = $"{length.ToString(CultureInfo.InvariantCulture)} / 300";
        }
    }

    private void LoadFleetTimeZoneOptions()
    {
        _fleetTimeZoneOptions.Clear();
        var timeZones = TimeZoneInfo.GetSystemTimeZones();
        foreach (var timeZone in timeZones
                     .GroupBy(zone => zone.BaseUtcOffset)
                     .Select(group => SelectPreferredTimeZone(group, timeZones))
                     .OrderBy(zone => zone.BaseUtcOffset)
                     .ThenBy(zone => zone.DisplayName, StringComparer.CurrentCultureIgnoreCase))
        {
            _fleetTimeZoneOptions.Add(new FleetTimeZoneOptionRow(
                timeZone.Id,
                FormatFleetTimeZoneDisplayName(timeZone)));
        }

        if (_fleetTimeZoneOptions.All(option =>
                !option.Id.Equals("UTC", StringComparison.OrdinalIgnoreCase)))
        {
            _fleetTimeZoneOptions.Insert(0, new FleetTimeZoneOptionRow("UTC", "(UTC+00:00) UTC"));
        }
    }

    private static TimeZoneInfo SelectPreferredTimeZone(
        IGrouping<TimeSpan, TimeZoneInfo> group,
        IReadOnlyCollection<TimeZoneInfo> allTimeZones)
    {
        if (group.Key == TimeSpan.Zero)
        {
            return allTimeZones.FirstOrDefault(zone =>
                       zone.Id.Equals("UTC", StringComparison.OrdinalIgnoreCase)) ??
                   group.First();
        }

        if (group.Key == TimeSpan.FromHours(8))
        {
            return group.FirstOrDefault(zone =>
                       zone.Id.Equals("China Standard Time", StringComparison.OrdinalIgnoreCase)) ??
                   group.FirstOrDefault(zone =>
                       zone.DisplayName.Contains("Beijing", StringComparison.OrdinalIgnoreCase) ||
                       zone.DisplayName.Contains("Chongqing", StringComparison.OrdinalIgnoreCase) ||
                       zone.DisplayName.Contains("Hong Kong", StringComparison.OrdinalIgnoreCase) ||
                       zone.DisplayName.Contains("Urumqi", StringComparison.OrdinalIgnoreCase)) ??
                   group.First();
        }

        return group.FirstOrDefault(zone => !zone.Id.Contains("Taipei", StringComparison.OrdinalIgnoreCase) &&
                                           !zone.DisplayName.Contains("Taipei", StringComparison.OrdinalIgnoreCase)) ??
               group.First();
    }

    private static string FormatFleetTimeZoneDisplayName(TimeZoneInfo timeZone)
    {
        var offset = timeZone.BaseUtcOffset;
        var sign = offset < TimeSpan.Zero ? "-" : "+";
        offset = offset.Duration();
        if (timeZone.Id.Equals("China Standard Time", StringComparison.OrdinalIgnoreCase))
        {
            return string.Format(
                CultureInfo.InvariantCulture,
                "(UTC{0}{1:00}:{2:00}) 中国标准时间 / 北京时间",
                sign,
                offset.Hours,
                offset.Minutes);
        }

        if (timeZone.Id.Equals("UTC", StringComparison.OrdinalIgnoreCase))
        {
            return "(UTC+00:00) UTC";
        }

        return string.Format(
            CultureInfo.InvariantCulture,
            "(UTC{0}{1:00}:{2:00}) {3}",
            sign,
            offset.Hours,
            offset.Minutes,
            StripUtcPrefix(timeZone.DisplayName));
    }

    private static string StripUtcPrefix(string displayName)
    {
        if (string.IsNullOrWhiteSpace(displayName))
        {
            return "UTC";
        }

        var endIndex = displayName.IndexOf(')');
        return endIndex >= 0 && endIndex + 1 < displayName.Length
            ? displayName[(endIndex + 1)..].Trim()
            : displayName.Trim();
    }

    private void SelectFleetTimeZone(string? timeZoneId)
    {
        if (ManageFleetTimeZoneBox is null)
        {
            return;
        }

        var normalizedId = string.IsNullOrWhiteSpace(timeZoneId)
            ? "China Standard Time"
            : timeZoneId.Trim();
        var option = _fleetTimeZoneOptions.FirstOrDefault(item =>
            item.Id.Equals(normalizedId, StringComparison.OrdinalIgnoreCase)) ??
                     FindFleetTimeZoneOptionBySameOffset(normalizedId) ??
                     _fleetTimeZoneOptions.FirstOrDefault(item =>
                         item.Id.Equals("China Standard Time", StringComparison.OrdinalIgnoreCase)) ??
                     _fleetTimeZoneOptions.FirstOrDefault();
        ManageFleetTimeZoneBox.SelectedValue = option?.Id;
    }

    private void RefreshManageFleetActivityTimeZoneSummary()
    {
        if (ManageFleetActivityTimeZoneSummaryText is null)
        {
            return;
        }

        var selectedId = ManageFleetTimeZoneBox?.SelectedValue as string;
        var timeZoneId = string.IsNullOrWhiteSpace(selectedId)
            ? _fleetTimeZoneId
            : selectedId;
        var option = _fleetTimeZoneOptions.FirstOrDefault(item =>
                         item.Id.Equals(timeZoneId, StringComparison.OrdinalIgnoreCase)) ??
                     FindFleetTimeZoneOptionBySameOffset(timeZoneId);

        ManageFleetActivityTimeZoneSummaryText.Text =
            $"按组织默认时区：{option?.DisplayName ?? "未设置"}";
    }

    private FleetTimeZoneOptionRow? FindFleetTimeZoneOptionBySameOffset(string timeZoneId)
    {
        if (!TryGetTimeZoneOffset(timeZoneId, out var targetOffset))
        {
            return null;
        }

        return _fleetTimeZoneOptions.FirstOrDefault(option =>
            TryGetTimeZoneOffset(option.Id, out var optionOffset) &&
            optionOffset == targetOffset);
    }

    private static bool TryGetTimeZoneOffset(string timeZoneId, out TimeSpan offset)
    {
        offset = TimeSpan.Zero;
        try
        {
            offset = TimeZoneInfo.FindSystemTimeZoneById(timeZoneId).BaseUtcOffset;
            return true;
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

    private void LoadFleetActivityWindows(
        IEnumerable<LocalFleetActivityWindow>? windows,
        string? legacyDays,
        string? legacyTime)
    {
        _fleetActivityWindows.Clear();

        foreach (var window in windows ?? [])
        {
            var normalized = NormalizeFleetActivityWindow(
                window.Days,
                window.StartTime,
                window.EndTime,
                window.EndsNextDay,
                allowEmptyDays: false);
            if (normalized is not null)
            {
                _fleetActivityWindows.Add(normalized);
            }

            if (_fleetActivityWindows.Count >= MaxFleetActivityWindowCount)
            {
                break;
            }
        }

        if (_fleetActivityWindows.Count == 0)
        {
            var (start, end, endsNextDay) = ParseLegacyFleetActivityTime(legacyTime);
            _fleetActivityWindows.Add(new FleetActivityWindowDraft(
                ParseLegacyFleetActivityDays(legacyDays),
                start,
                end,
                endsNextDay));
        }

        UpdateFleetActivitySummaries();
    }

    private static FleetActivityWindowDraft? NormalizeFleetActivityWindow(
        IEnumerable<string>? days,
        string? startTime,
        string? endTime,
        bool endsNextDay,
        bool allowEmptyDays)
    {
        var normalizedStart = NormalizeFleetActivityClockText(startTime, DefaultFleetActivityStartTime);
        var normalizedEnd = NormalizeFleetActivityClockText(endTime, DefaultFleetActivityEndTime);
        var normalizedDays = NormalizeFleetActivityDays(days);
        if (normalizedDays.Length == 0 && !allowEmptyDays)
        {
            normalizedDays = AllFleetActivityDayIds();
        }

        return new FleetActivityWindowDraft(
            normalizedDays,
            normalizedStart,
            normalizedEnd,
            ShouldFleetActivityEndNextDay(normalizedStart, normalizedEnd, endsNextDay));
    }

    private static string NormalizeFleetActivityClockText(string? value, string fallback)
    {
        return TryParseFleetActivityClock(value, out var minutes)
            ? FormatFleetActivityClock(minutes)
            : fallback;
    }

    private static bool TryParseFleetActivityClock(string? value, out int minutes)
    {
        minutes = 0;
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var match = Regex.Match(value.Trim(), @"^(?<hour>\d{1,2}):(?<minute>\d{2})$", RegexOptions.CultureInvariant);
        if (!match.Success ||
            !int.TryParse(match.Groups["hour"].Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var hour) ||
            !int.TryParse(match.Groups["minute"].Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var minute) ||
            hour is < 0 or > 23 ||
            minute is < 0 or > 59)
        {
            return false;
        }

        minutes = (hour * 60) + minute;
        return true;
    }

    private static string FormatFleetActivityClock(int minutes)
    {
        minutes = Math.Clamp(minutes, 0, (24 * 60) - 1);
        return $"{minutes / 60:00}:{minutes % 60:00}";
    }

    private static bool ShouldFleetActivityEndNextDay(string? startTime, string? endTime, bool explicitNextDay)
    {
        var start = NormalizeFleetActivityClockText(startTime, DefaultFleetActivityStartTime);
        var end = NormalizeFleetActivityClockText(endTime, DefaultFleetActivityEndTime);
        _ = explicitNextDay;
        return TryParseFleetActivityClock(start, out var startMinutes) &&
               TryParseFleetActivityClock(end, out var endMinutes) &&
               endMinutes <= startMinutes;
    }

    private static (string Start, string End, bool EndsNextDay) ParseLegacyFleetActivityTime(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return (DefaultFleetActivityStartTime, DefaultFleetActivityEndTime, false);
        }

        var endsNextDay = value.Contains("次日", StringComparison.OrdinalIgnoreCase) ||
                          value.Contains("+1", StringComparison.OrdinalIgnoreCase);
        var normalized = Regex.Replace(value, @"UTC\s*[+-]?\d{1,2}(:\d{2})?", "", RegexOptions.IgnoreCase)
            .Replace("-", "-", StringComparison.Ordinal)
            .Replace("–", "-", StringComparison.Ordinal)
            .Replace("—", "-", StringComparison.Ordinal)
            .Replace("至", "-", StringComparison.Ordinal)
            .Replace("次日", "", StringComparison.OrdinalIgnoreCase)
            .Replace("+1", "", StringComparison.OrdinalIgnoreCase)
            .Trim();
        var match = Regex.Match(normalized, @"(?<start>\d{1,2}:\d{2})\s*-\s*(?<end>\d{1,2}:\d{2})");
        if (!match.Success)
        {
            return (DefaultFleetActivityStartTime, DefaultFleetActivityEndTime, false);
        }

        var start = NormalizeFleetActivityClockText(match.Groups["start"].Value, DefaultFleetActivityStartTime);
        var end = NormalizeFleetActivityClockText(match.Groups["end"].Value, DefaultFleetActivityEndTime);
        return (start, end, ShouldFleetActivityEndNextDay(start, end, endsNextDay));
    }

    private static string[] ParseLegacyFleetActivityDays(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return AllFleetActivityDayIds();
        }

        var text = value.Trim();
        if (text.Contains("工作日", StringComparison.OrdinalIgnoreCase))
        {
            return ["mon", "tue", "wed", "thu", "fri"];
        }

        if (text.Contains("周末", StringComparison.OrdinalIgnoreCase))
        {
            return ["sat", "sun"];
        }

        if (text.Contains("每日", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("每天", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("全周", StringComparison.OrdinalIgnoreCase))
        {
            return AllFleetActivityDayIds();
        }

        var ids = new List<string>();
        foreach (var day in GetFleetWeekDays())
        {
            var id = GetFleetActivityDayId(day);
            var label = GetFleetActivityDayLabel(day);
            if (text.Contains(label, StringComparison.OrdinalIgnoreCase))
            {
                ids.Add(id);
            }
        }

        return ids.Count == 0
            ? AllFleetActivityDayIds()
            : NormalizeFleetActivityDays(ids);
    }

    private static DayOfWeek[] GetFleetWeekDays() =>
    [
        DayOfWeek.Monday,
        DayOfWeek.Tuesday,
        DayOfWeek.Wednesday,
        DayOfWeek.Thursday,
        DayOfWeek.Friday,
        DayOfWeek.Saturday,
        DayOfWeek.Sunday
    ];

    private static DayOfWeek[] GetLocalizedFleetWeekDays()
    {
        var firstDay = CultureInfo.CurrentCulture.DateTimeFormat.FirstDayOfWeek;
        return Enumerable.Range(0, 7)
            .Select(offset => (DayOfWeek)(((int)firstDay + offset) % 7))
            .ToArray();
    }

    private static string GetFleetActivityDayId(DayOfWeek day) => day switch
    {
        DayOfWeek.Monday => "mon",
        DayOfWeek.Tuesday => "tue",
        DayOfWeek.Wednesday => "wed",
        DayOfWeek.Thursday => "thu",
        DayOfWeek.Friday => "fri",
        DayOfWeek.Saturday => "sat",
        DayOfWeek.Sunday => "sun",
        _ => "mon"
    };

    private static string GetFleetActivityDayLabel(DayOfWeek day) => day switch
    {
        DayOfWeek.Monday => "周一",
        DayOfWeek.Tuesday => "周二",
        DayOfWeek.Wednesday => "周三",
        DayOfWeek.Thursday => "周四",
        DayOfWeek.Friday => "周五",
        DayOfWeek.Saturday => "周六",
        DayOfWeek.Sunday => "周日",
        _ => "周一"
    };

    private static string[] AllFleetActivityDayIds() =>
        GetFleetWeekDays()
            .Select(GetFleetActivityDayId)
            .ToArray();

    private static string[] BuildFleetActivityTimeOptions()
    {
        var options = Enumerable.Range(0, 48)
            .Select(index => FormatFleetActivityClock(index * 30))
            .ToList();
        if (!options.Contains("23:59", StringComparer.Ordinal))
        {
            options.Add("23:59");
        }

        return options
            .Distinct(StringComparer.Ordinal)
            .OrderBy(option => TryParseFleetActivityClock(option, out var minutes) ? minutes : 0)
            .ToArray();
    }

    private void InitializeFleetActivityTimeSelectors()
    {
        foreach (var comboBox in EnumerateFleetActivityTimeSelectors())
        {
            comboBox.ItemsSource = FleetActivityTimeOptions;
        }
    }

    private IEnumerable<System.Windows.Controls.ComboBox> EnumerateFleetActivityTimeSelectors()
    {
        if (ManageFleetScheduleSlot1StartBox is not null) yield return ManageFleetScheduleSlot1StartBox;
        if (ManageFleetScheduleSlot1EndBox is not null) yield return ManageFleetScheduleSlot1EndBox;
        if (ManageFleetScheduleSlot2StartBox is not null) yield return ManageFleetScheduleSlot2StartBox;
        if (ManageFleetScheduleSlot2EndBox is not null) yield return ManageFleetScheduleSlot2EndBox;
        if (ManageFleetScheduleSlot3StartBox is not null) yield return ManageFleetScheduleSlot3StartBox;
        if (ManageFleetScheduleSlot3EndBox is not null) yield return ManageFleetScheduleSlot3EndBox;
    }

    private static string[] NormalizeFleetActivityDays(IEnumerable<string>? days)
    {
        var orderedDayIds = AllFleetActivityDayIds();
        var validIds = orderedDayIds.ToHashSet(StringComparer.OrdinalIgnoreCase);
        return (days ?? [])
            .Where(day => !string.IsNullOrWhiteSpace(day))
            .Select(day => day.Trim().ToLowerInvariant())
            .Where(validIds.Contains)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(day => Array.IndexOf(orderedDayIds, day))
            .ToArray();
    }

    private void EnsureDefaultFleetActivityWindow()
    {
        if (_fleetActivityWindows.Count == 0)
        {
            _fleetActivityWindows.Add(new FleetActivityWindowDraft(
                AllFleetActivityDayIds(),
                DefaultFleetActivityStartTime,
                DefaultFleetActivityEndTime,
                false));
        }
    }

    private void RefreshFleetActivityWindowEditor()
    {
        _isUpdatingFleetActivityWindowEditor = true;
        try
        {
            EnsureDefaultFleetActivityWindow();
            while (_fleetActivityWindows.Count > MaxFleetActivityWindowCount)
            {
                _fleetActivityWindows.RemoveAt(_fleetActivityWindows.Count - 1);
            }

            var count = Math.Clamp(_fleetActivityWindows.Count, 1, MaxFleetActivityWindowCount);
            PopulateFleetActivityWindowSlot(1, _fleetActivityWindows[0]);
            PopulateFleetActivityWindowSlot(2, count >= 2 ? _fleetActivityWindows[1] : null);
            PopulateFleetActivityWindowSlot(3, count >= 3 ? _fleetActivityWindows[2] : null);

            if (ManageFleetScheduleSlot2Panel is not null)
            {
                ManageFleetScheduleSlot2Panel.Visibility = count >= 2 ? Visibility.Visible : Visibility.Collapsed;
            }

            if (ManageFleetScheduleSlot3Panel is not null)
            {
                ManageFleetScheduleSlot3Panel.Visibility = count >= 3 ? Visibility.Visible : Visibility.Collapsed;
            }
        }
        finally
        {
            _isUpdatingFleetActivityWindowEditor = false;
        }

        SetFleetActivityWindowEditorEditableState(_isManageProfileEditMode);
    }

    private void PopulateFleetActivityWindowSlot(int slot, FleetActivityWindowDraft? window)
    {
        var effectiveWindow = window ?? new FleetActivityWindowDraft(
            AllFleetActivityDayIds(),
            DefaultFleetActivityStartTime,
            DefaultFleetActivityEndTime,
            false);
        PopulateFleetActivityDayPanel(GetFleetActivityDaysPanel(slot), effectiveWindow.Days);
        SelectFleetActivityTimeIfSafe(GetFleetActivityStartBox(slot), effectiveWindow.StartTime);
        SelectFleetActivityTimeIfSafe(GetFleetActivityEndBox(slot), effectiveWindow.EndTime);
        if (GetFleetActivityNextDayCheck(slot) is { } nextDayCheck)
        {
            nextDayCheck.IsChecked = ShouldFleetActivityEndNextDay(
                effectiveWindow.StartTime,
                effectiveWindow.EndTime,
                effectiveWindow.EndsNextDay);
        }
    }

    private void PopulateFleetActivityDayPanel(WrapPanel? panel, IEnumerable<string> selectedDays)
    {
        if (panel is null)
        {
            return;
        }

        panel.Children.Clear();
        var selected = new HashSet<string>(selectedDays, StringComparer.OrdinalIgnoreCase);
        var chipStyle = panel.TryFindResource("ManageProfileDayChipStyle") as Style;
        foreach (var day in GetLocalizedFleetWeekDays())
        {
            var id = GetFleetActivityDayId(day);
            var checkBox = new System.Windows.Controls.CheckBox
            {
                Content = GetFleetActivityDayLabel(day),
                Tag = id,
                IsChecked = selected.Contains(id),
                IsEnabled = _isManageProfileEditMode,
                ToolTip = "选择此时间段覆盖的活动日"
            };
            if (chipStyle is not null)
            {
                checkBox.Style = chipStyle;
            }

            checkBox.Checked += ManageFleetActivityWindowChanged;
            checkBox.Unchecked += ManageFleetActivityWindowChanged;
            panel.Children.Add(checkBox);
        }
    }

    private WrapPanel? GetFleetActivityDaysPanel(int slot) => slot switch
    {
        1 => ManageFleetScheduleSlot1DaysPanel,
        2 => ManageFleetScheduleSlot2DaysPanel,
        3 => ManageFleetScheduleSlot3DaysPanel,
        _ => null
    };

    private System.Windows.Controls.ComboBox? GetFleetActivityStartBox(int slot) => slot switch
    {
        1 => ManageFleetScheduleSlot1StartBox,
        2 => ManageFleetScheduleSlot2StartBox,
        3 => ManageFleetScheduleSlot3StartBox,
        _ => null
    };

    private System.Windows.Controls.ComboBox? GetFleetActivityEndBox(int slot) => slot switch
    {
        1 => ManageFleetScheduleSlot1EndBox,
        2 => ManageFleetScheduleSlot2EndBox,
        3 => ManageFleetScheduleSlot3EndBox,
        _ => null
    };

    private System.Windows.Controls.CheckBox? GetFleetActivityNextDayCheck(int slot) => slot switch
    {
        1 => ManageFleetScheduleSlot1NextDayCheck,
        2 => ManageFleetScheduleSlot2NextDayCheck,
        3 => ManageFleetScheduleSlot3NextDayCheck,
        _ => null
    };

    private FrameworkElement? GetFleetActivitySlotPanel(int slot) => slot switch
    {
        1 => ManageFleetScheduleSlot1Panel,
        2 => ManageFleetScheduleSlot2Panel,
        3 => ManageFleetScheduleSlot3Panel,
        _ => null
    };

    private static string GetSelectedFleetActivityTime(System.Windows.Controls.ComboBox? comboBox, string fallback)
    {
        return comboBox?.SelectedItem as string ??
               comboBox?.SelectedValue as string ??
               NormalizeFleetActivityClockText(comboBox?.Text, fallback);
    }

    private static void SelectFleetActivityTimeIfSafe(System.Windows.Controls.ComboBox? comboBox, string value)
    {
        if (comboBox is null)
        {
            return;
        }

        var normalized = NormalizeFleetActivityClockText(value, DefaultFleetActivityStartTime);
        if (!FleetActivityTimeOptions.Contains(normalized, StringComparer.Ordinal))
        {
            normalized = FindNearestFleetActivityTimeOption(normalized);
        }

        comboBox.SelectedItem = normalized;
    }

    private static string FindNearestFleetActivityTimeOption(string value)
    {
        if (!TryParseFleetActivityClock(value, out var targetMinutes))
        {
            return DefaultFleetActivityStartTime;
        }

        return FleetActivityTimeOptions
            .OrderBy(option => TryParseFleetActivityClock(option, out var minutes)
                ? Math.Abs(minutes - targetMinutes)
                : int.MaxValue)
            .FirstOrDefault() ?? DefaultFleetActivityStartTime;
    }

    private void SetFleetActivityWindowEditorEditableState(bool isEditing)
    {
        for (var slot = 1; slot <= MaxFleetActivityWindowCount; slot++)
        {
            SetComboBoxEditableState(GetFleetActivityStartBox(slot), isEditing);
            SetComboBoxEditableState(GetFleetActivityEndBox(slot), isEditing);
            SetCheckBoxEditableState(GetFleetActivityNextDayCheck(slot), isEditing);
            if (GetFleetActivityDaysPanel(slot) is not { } panel)
            {
                continue;
            }

            foreach (var checkBox in panel.Children.OfType<System.Windows.Controls.CheckBox>())
            {
                checkBox.IsEnabled = isEditing;
                checkBox.Opacity = isEditing ? 1 : 0.82;
            }
        }

        if (ManageFleetRemoveScheduleSlot2Button is not null)
        {
            ManageFleetRemoveScheduleSlot2Button.IsEnabled = isEditing;
            ManageFleetRemoveScheduleSlot2Button.Opacity = isEditing ? 1 : 0.62;
        }

        if (ManageFleetRemoveScheduleSlot3Button is not null)
        {
            ManageFleetRemoveScheduleSlot3Button.IsEnabled = isEditing;
            ManageFleetRemoveScheduleSlot3Button.Opacity = isEditing ? 1 : 0.62;
        }

        if (ManageFleetAddScheduleWindowButton is not null)
        {
            var canAdd = isEditing && _fleetActivityWindows.Count < MaxFleetActivityWindowCount;
            ManageFleetAddScheduleWindowButton.IsEnabled = canAdd;
            ManageFleetAddScheduleWindowButton.Opacity = canAdd ? 1 : 0.62;
        }
    }

    private void SyncFleetActivityWindowsFromEditor()
    {
        var windows = new List<FleetActivityWindowDraft>();
        for (var slot = 1; slot <= MaxFleetActivityWindowCount; slot++)
        {
            var panel = GetFleetActivitySlotPanel(slot);
            if (panel is not null && panel.Visibility != Visibility.Visible)
            {
                continue;
            }

            var normalized = NormalizeFleetActivityWindow(
                GetFleetActivitySelectedDays(slot),
                GetSelectedFleetActivityTime(GetFleetActivityStartBox(slot), DefaultFleetActivityStartTime),
                GetSelectedFleetActivityTime(GetFleetActivityEndBox(slot), DefaultFleetActivityEndTime),
                GetFleetActivityNextDayCheck(slot)?.IsChecked == true,
                allowEmptyDays: false);
            if (normalized is not null)
            {
                windows.Add(normalized);
            }
        }

        _fleetActivityWindows.Clear();
        _fleetActivityWindows.AddRange(windows.Take(MaxFleetActivityWindowCount));
        EnsureDefaultFleetActivityWindow();
        UpdateFleetActivitySummaries();
    }

    private string[] GetFleetActivitySelectedDays(int slot)
    {
        var panel = GetFleetActivityDaysPanel(slot);
        if (panel is null)
        {
            return [];
        }

        return NormalizeFleetActivityDays(
            panel.Children
                .OfType<System.Windows.Controls.CheckBox>()
                .Where(checkBox => checkBox.IsChecked == true)
                .Select(checkBox => checkBox.Tag as string ?? ""));
    }

    private void UpdateFleetActivitySummaries()
    {
        EnsureDefaultFleetActivityWindow();
        _fleetActiveTime = string.Join(";", _fleetActivityWindows.Select(FormatFleetActivityWindow));
        _fleetActiveDaysDescription = FormatFleetActivityDaysSummary(_fleetActivityWindows);
    }

    private static string FormatFleetActivityWindow(FleetActivityWindowDraft window) =>
        $"{FormatFleetActivityDays(window.Days)} {window.StartTime}-{(window.EndsNextDay ? "次日 " : "")}{window.EndTime}";

    private static string FormatFleetActivityDaysSummary(IEnumerable<FleetActivityWindowDraft> windows)
    {
        var summary = string.Join(";", windows.Select(window => FormatFleetActivityDays(window.Days)));
        return string.IsNullOrWhiteSpace(summary) ? "未设置" : summary;
    }

    private static string FormatFleetActivityDays(IEnumerable<string> days)
    {
        var normalized = NormalizeFleetActivityDays(days);
        var allDays = AllFleetActivityDayIds();
        if (normalized.Length == allDays.Length)
        {
            return "每日";
        }

        if (normalized.SequenceEqual(["mon", "tue", "wed", "thu", "fri"]))
        {
            return "工作日";
        }

        if (normalized.SequenceEqual(["sat", "sun"]))
        {
            return "周末";
        }

        return normalized.Length == 0
            ? "未选择日期"
            : string.Join("、", normalized.Select(id =>
            {
                var day = GetFleetWeekDays().FirstOrDefault(item =>
                    GetFleetActivityDayId(item).Equals(id, StringComparison.OrdinalIgnoreCase));
                return GetFleetActivityDayLabel(day);
            }));
    }

    private void ManageFleetActivityWindowChanged(object sender, RoutedEventArgs e)
    {
        if (_isUpdatingFleetActivityWindowEditor || _isManageProfileRefreshing || _isLoadingSettings)
        {
            return;
        }

        UpdateFleetActivityNextDayStateFromEditor(sender);
        HandleManageProfileDraftChanged();
    }

    private void ManageFleetActivityWindowChanged(object sender, SelectionChangedEventArgs e)
    {
        ManageFleetActivityWindowChanged(sender, (RoutedEventArgs)e);
    }

    private void UpdateFleetActivityNextDayStateFromEditor(object sender)
    {
        if (sender is not FrameworkElement source)
        {
            return;
        }

        for (var slot = 1; slot <= MaxFleetActivityWindowCount; slot++)
        {
            var startBox = GetFleetActivityStartBox(slot);
            var endBox = GetFleetActivityEndBox(slot);
            var nextDayCheck = GetFleetActivityNextDayCheck(slot);
            if (source != startBox && source != endBox && source != nextDayCheck)
            {
                continue;
            }

            var start = GetSelectedFleetActivityTime(startBox, DefaultFleetActivityStartTime);
            var end = GetSelectedFleetActivityTime(endBox, DefaultFleetActivityEndTime);
            var hasStart = TryParseFleetActivityClock(start, out var startMinutes);
            var hasEnd = TryParseFleetActivityClock(end, out var endMinutes);
            if (!hasStart || !hasEnd || nextDayCheck is null)
            {
                return;
            }

            _isUpdatingFleetActivityWindowEditor = true;
            try
            {
                if (source == nextDayCheck)
                {
                    if (nextDayCheck.IsChecked == true && endMinutes > startMinutes)
                    {
                        SelectFleetActivityTimeIfSafe(endBox, start);
                    }
                    else if (nextDayCheck.IsChecked != true && endMinutes <= startMinutes)
                    {
                        SelectFleetActivityTimeIfSafe(endBox, FindNextSameDayFleetActivityEndTime(startMinutes));
                    }
                }
                else
                {
                    nextDayCheck.IsChecked = endMinutes <= startMinutes;
                }
            }
            finally
            {
                _isUpdatingFleetActivityWindowEditor = false;
            }

            return;
        }
    }

    private static string FindNextSameDayFleetActivityEndTime(int startMinutes)
    {
        return FleetActivityTimeOptions
            .Where(option => TryParseFleetActivityClock(option, out var minutes) && minutes > startMinutes)
            .OrderBy(option => TryParseFleetActivityClock(option, out var minutes) ? minutes : int.MaxValue)
            .FirstOrDefault() ?? DefaultFleetActivityEndTime;
    }

    private void ManageFleetAddScheduleWindowButton_Click(object sender, RoutedEventArgs e)
    {
        EnsureManageProfileDraftBaseline();
        SyncFleetActivityWindowsFromEditor();
        if (_fleetActivityWindows.Count >= MaxFleetActivityWindowCount)
        {
            SetFleetDescriptionStatus("主要活跃时间最多添加 3 个时间段。", ManageProfileStatusTone.Warning);
            RefreshFleetActivityWindowEditor();
            return;
        }

        _fleetActivityWindows.Add(new FleetActivityWindowDraft(
            ["mon", "tue", "wed", "thu", "fri"],
            DefaultFleetActivityStartTime,
            DefaultFleetActivityEndTime,
            false));
        RefreshFleetActivityWindowEditor();
        SetFleetDescriptionStatus("已添加活动时间段。", ManageProfileStatusTone.Success);
        HandleManageProfileDraftChanged();
    }

    private void ManageFleetRemoveScheduleWindowButton_Click(object sender, RoutedEventArgs e)
    {
        EnsureManageProfileDraftBaseline();
        SyncFleetActivityWindowsFromEditor();
        if ((sender as FrameworkElement)?.Tag is not string slotText ||
            !int.TryParse(slotText, NumberStyles.Integer, CultureInfo.InvariantCulture, out var slot) ||
            slot <= 1 ||
            slot > _fleetActivityWindows.Count)
        {
            return;
        }

        _fleetActivityWindows.RemoveAt(slot - 1);
        EnsureDefaultFleetActivityWindow();
        RefreshFleetActivityWindowEditor();
        SetFleetDescriptionStatus("已移除活动时间段。", ManageProfileStatusTone.Info);
        HandleManageProfileDraftChanged();
    }

    private void SetFleetExternalContacts(IEnumerable<LocalFleetExternalContact> contacts)
    {
        _fleetExternalContacts.Clear();
        foreach (var contact in contacts
                     .Where(contact => !string.IsNullOrWhiteSpace(contact.Platform) &&
                                       !string.IsNullOrWhiteSpace(contact.Value))
                     .Take(5))
        {
            _fleetExternalContacts.Add(new FleetExternalContactRow(contact.Platform, contact.Value));
        }

        RefreshFleetExternalContactsEditor();
    }

    private void NormalizeFleetExternalContactsFromRows()
    {
        var normalized = _fleetExternalContacts
            .Where(contact => !string.IsNullOrWhiteSpace(contact.Value))
            .Select(contact => new FleetExternalContactRow(
                string.IsNullOrWhiteSpace(contact.Platform) ? "QQ" : contact.Platform.Trim(),
                contact.Value.Trim()))
            .Take(5)
            .ToArray();

        _fleetExternalContacts.Clear();
        foreach (var contact in normalized)
        {
            _fleetExternalContacts.Add(contact);
        }

        RefreshFleetExternalContactsEditor();
    }

    private void ApplyLoadedExternalContactPublicationState(bool isCurrentlyPublished)
    {
        _fleetExternalContactPublicationMode = FleetExternalContactPublication.ResolveLoadedMode(
            isCurrentlyPublished,
            _fleetExternalContacts);
        _legacyExternalContactPublicationConfirmed = false;
        RefreshFleetExternalContactsEditor();
    }

    private void RefreshFleetExternalContactsEditor()
    {
        if (ManageExternalContactCountText is not null)
        {
            ManageExternalContactCountText.Text =
                $"{_fleetExternalContacts.Count.ToString(CultureInfo.InvariantCulture)} / 5";
        }

        if (ManageExternalContactsEmptyText is not null)
        {
            ManageExternalContactsEmptyText.Visibility = _fleetExternalContacts.Count == 0
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (ManageAddExternalContactButton is not null)
        {
            ManageAddExternalContactButton.IsEnabled = _isManageProfileEditMode && _fleetExternalContacts.Count < 5;
            ManageAddExternalContactButton.Opacity = ManageAddExternalContactButton.IsEnabled ? 1 : 0.62;
        }

        var requiresLegacyDecision =
            _fleetExternalContactPublicationMode == FleetExternalContactPublicationMode.LegacyPrivate &&
            FleetExternalContactPublication.ShouldPublish(_fleetExternalContacts);
        if (ManageLegacyPrivateExternalContactsWarning is not null)
        {
            ManageLegacyPrivateExternalContactsWarning.Visibility = requiresLegacyDecision
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (ManageLegacyPrivateExternalContactsText is not null)
        {
            ManageLegacyPrivateExternalContactsText.Text = _legacyExternalContactPublicationConfirmed
                ? "已确认：保存后，这些联系方式将在寻找组织中公开。"
                : "这些旧版联系方式目前未公开。保存其他设置不会公开它们；请清空不希望公开的内容，或确认公开后再保存。";
        }

        if (ConfirmLegacyPrivateExternalContactsButton is not null)
        {
            ConfirmLegacyPrivateExternalContactsButton.Content = _legacyExternalContactPublicationConfirmed
                ? "已确认公开"
                : "确认公开";
            ConfirmLegacyPrivateExternalContactsButton.IsEnabled =
                _isManageProfileEditMode &&
                requiresLegacyDecision &&
                !_legacyExternalContactPublicationConfirmed;
        }
    }

    private void ConfirmLegacyPrivateExternalContactsButton_Click(object sender, RoutedEventArgs e)
    {
        if (_fleetExternalContactPublicationMode != FleetExternalContactPublicationMode.LegacyPrivate ||
            !FleetExternalContactPublication.ShouldPublish(_fleetExternalContacts))
        {
            return;
        }

        EnsureManageProfileDraftBaseline();
        _legacyExternalContactPublicationConfirmed = true;
        RefreshFleetExternalContactsEditor();
        SetFleetDescriptionStatus("已确认公开旧版联系方式；保存更改后生效。", ManageProfileStatusTone.Info);
        HandleManageProfileDraftChanged();
    }

    private void ManageFleetTimeZoneChanged(object sender, SelectionChangedEventArgs e)
    {
        HandleManageProfileDraftChanged();
    }

    private void ManageExternalContactChanged(object sender, RoutedEventArgs e)
    {
        HandleManageProfileDraftChanged();
    }

    private void AddExternalContactButton_Click(object sender, RoutedEventArgs e)
    {
        EnsureManageProfileDraftBaseline();
        if (_fleetExternalContacts.Count >= 5)
        {
            SetFleetDescriptionStatus("外部联系方式最多添加 5 个。", ManageProfileStatusTone.Warning);
            return;
        }

        _fleetExternalContacts.Add(new FleetExternalContactRow());
        RefreshFleetExternalContactsEditor();
        HandleManageProfileDraftChanged();
    }

    private void RemoveExternalContactButton_Click(object sender, RoutedEventArgs e)
    {
        EnsureManageProfileDraftBaseline();
        if ((sender as FrameworkElement)?.DataContext is not FleetExternalContactRow row)
        {
            return;
        }

        _fleetExternalContacts.Remove(row);
        RefreshFleetExternalContactsEditor();
        HandleManageProfileDraftChanged();
    }

    private void SetManageProfileSelectedTagIds(IEnumerable<string> tagIds)
    {
        _manageProfileSelectedTagIds.Clear();
        foreach (var id in tagIds
                     .Where(id => !string.IsNullOrWhiteSpace(id))
                     .Select(id => id.Trim())
                     .Where(IsKnownFleetTagId)
                     .Distinct(StringComparer.OrdinalIgnoreCase)
                     .Take(MaxManageFleetTags))
        {
            _manageProfileSelectedTagIds.Add(id);
        }

        RefreshManageProfileSelectedTags();
    }

    private void RefreshManageProfileSelectedTags()
    {
        _manageProfileSelectedTags.Clear();
        foreach (var tag in GetTagRows(_manageProfileSelectedTagIds))
        {
            _manageProfileSelectedTags.Add(tag);
        }

        if (ManageProfileTagCountText is not null)
        {
            ManageProfileTagCountText.Text =
                $"{_manageProfileSelectedTagIds.Count.ToString(CultureInfo.InvariantCulture)} / {MaxManageFleetTags.ToString(CultureInfo.InvariantCulture)}";
        }
    }

    private void SetCreateFleetSelectedTagIds(IEnumerable<string> tagIds)
    {
        _createFleetSelectedTagIds.Clear();
        foreach (var id in tagIds
                     .Where(id => !string.IsNullOrWhiteSpace(id))
                     .Select(id => id.Trim())
                     .Where(IsKnownFleetTagId)
                     .Distinct(StringComparer.OrdinalIgnoreCase)
                     .Take(MaxManageFleetTags))
        {
            _createFleetSelectedTagIds.Add(id);
        }

        RefreshCreateFleetSelectedTags();
    }

    private void RefreshCreateFleetSelectedTags()
    {
        _createFleetSelectedTags.Clear();
        foreach (var tag in GetTagRows(_createFleetSelectedTagIds))
        {
            _createFleetSelectedTags.Add(tag);
        }

        if (CreateFleetTagCountText is not null)
        {
            CreateFleetTagCountText.Text =
                $"{_createFleetSelectedTagIds.Count.ToString(CultureInfo.InvariantCulture)} / {MaxManageFleetTags.ToString(CultureInfo.InvariantCulture)}";
        }
    }

    private void CreateFleetEditTagsButton_Click(object sender, RoutedEventArgs e)
    {
        _isCreateFleetTagSelectorMode = true;
        _isFindFleetTagFilterSelectorMode = false;
        OpenManageTagSelector();
    }

    private static void ApplyOverlaySceneComboLanguage(System.Windows.Controls.ComboBox? comboBox, bool zh)
    {
        if (comboBox is null || comboBox.Items.Count < 3)
        {
            return;
        }

        ((ComboBoxItem)comboBox.Items[0]).Content = zh ? "自动" : "Auto";
        ((ComboBoxItem)comboBox.Items[1]).Content = zh ? "组织" : "Organization";
        ((ComboBoxItem)comboBox.Items[2]).Content = zh ? "当前房间" : "Current party";
    }

    private void ManageProfileEditTagsButton_Click(object sender, RoutedEventArgs e)
    {
        if (!CanCurrentUserEditFleetProfile())
        {
            SetFleetDescriptionStatus("当前账号没有修改组织标签的权限。", ManageProfileStatusTone.Locked);
            return;
        }

        _isCreateFleetTagSelectorMode = false;
        _isFindFleetTagFilterSelectorMode = false;
        OpenManageTagSelector();
    }

    private void OpenManageTagSelector()
    {
        _manageTagDraftIds.Clear();
        var sourceTagIds = GetManageTagSelectorSourceIds();
        foreach (var id in sourceTagIds)
        {
            _manageTagDraftIds.Add(id);
        }

        if (string.IsNullOrWhiteSpace(_activeManageTagCategoryId) ||
            FleetTagCategoryDefinitions.All(category => !category.Id.Equals(_activeManageTagCategoryId, StringComparison.OrdinalIgnoreCase)))
        {
            _activeManageTagCategoryId = FleetTagCategoryDefinitions[0].Id;
        }

        if (ManageTagUnsavedPrompt is not null)
        {
            ManageTagUnsavedPrompt.Visibility = Visibility.Collapsed;
        }
        ManageTagSelectorFooter.Visibility = Visibility.Visible;

        ManageTagSelectorOverlay.Show();

        RenderManageTagSelector();
    }

    private void RenderManageTagSelector()
    {
        RenderManageTagCategoryList();
        RenderManageTagOptions();
        RefreshManageTagDraftPreview();
    }

    private void RenderManageTagCategoryList()
    {
        if (ManageTagCategoryList is null)
        {
            return;
        }

        ManageTagCategoryList.Children.Clear();
        foreach (var category in FleetTagCategoryDefinitions)
        {
            var isActive = category.Id.Equals(_activeManageTagCategoryId, StringComparison.OrdinalIgnoreCase);
            var selectedInCategory = _manageTagDraftIds.Count(id =>
                GetFleetTagDefinition(id)?.CategoryId.Equals(category.Id, StringComparison.OrdinalIgnoreCase) == true);

            var button = new System.Windows.Controls.Button
            {
                Height = 38,
                Margin = new Thickness(0, 0, 0, 7),
                Padding = new Thickness(0),
                HorizontalContentAlignment = HorizontalAlignment.Stretch,
                Cursor = Cursors.Hand,
                Tag = category.Id,
                Background = isActive ? BrushFromHex(category.AccentHex, 0.24) : FleetCommandBrush(BridgeBrushToken.Rail),
                BorderBrush = isActive ? BrushFromHex(category.AccentHex, 0.92) : FleetCommandBrush(BridgeBrushToken.Hairline),
                BorderThickness = new Thickness(1),
                ToolTip = category.Description
            };
            button.Click += ManageTagCategoryButton_Click;

            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(4) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            grid.Children.Add(new Border
            {
                Background = BrushFromHex(category.AccentHex),
                CornerRadius = new CornerRadius(2, 0, 0, 2),
                Opacity = isActive ? 1 : 0.62
            });

            var nameText = new TextBlock
            {
                Text = category.Name,
                Margin = new Thickness(10, 0, 6, 0),
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = FleetCommandBrush(isActive ? BridgeBrushToken.Ink : BridgeBrushToken.Ink2),
                FontWeight = isActive ? FontWeights.SemiBold : FontWeights.Normal,
                TextTrimming = TextTrimming.CharacterEllipsis
            };
            Grid.SetColumn(nameText, 1);
            grid.Children.Add(nameText);

            var countText = new TextBlock
            {
                Text = selectedInCategory > 0 ? selectedInCategory.ToString(CultureInfo.InvariantCulture) : "",
                Margin = new Thickness(0, 0, 10, 0),
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = BrushFromHex(category.AccentHex),
                FontWeight = FontWeights.SemiBold
            };
            Grid.SetColumn(countText, 2);
            grid.Children.Add(countText);

            button.Content = grid;
            ManageTagCategoryList.Children.Add(button);
        }
    }

    private void ManageTagCategoryButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.Button { Tag: string categoryId })
        {
            return;
        }

        _activeManageTagCategoryId = categoryId;
        if (ManageTagUnsavedPrompt is not null)
        {
            ManageTagUnsavedPrompt.Visibility = Visibility.Collapsed;
        }
        ManageTagSelectorFooter.Visibility = Visibility.Visible;

        RenderManageTagSelector();
    }

    private void RenderManageTagOptions()
    {
        if (ManageTagOptionsPanel is null)
        {
            return;
        }

        var category = FleetTagCategoryDefinitions.FirstOrDefault(item =>
            item.Id.Equals(_activeManageTagCategoryId, StringComparison.OrdinalIgnoreCase)) ?? FleetTagCategoryDefinitions[0];
        if (ManageTagActiveCategoryText is not null)
        {
            ManageTagActiveCategoryText.Text = category.Name;
            ManageTagActiveCategoryText.Foreground = BrushFromHex(category.AccentHex);
        }

        if (ManageTagActiveCategoryDescriptionText is not null)
        {
            ManageTagActiveCategoryDescriptionText.Text = category.Description;
        }

        ManageTagOptionsPanel.Children.Clear();
        foreach (var tag in FleetTagDefinitions
                     .Where(tag => tag.CategoryId.Equals(category.Id, StringComparison.OrdinalIgnoreCase))
                     .Select(tag => new ManageFleetTagOptionRow(tag, category)))
        {
            var isSelected = _manageTagDraftIds.Contains(tag.Id);
            var border = new Border
            {
                MinHeight = 32,
                Margin = new Thickness(0, 0, 8, 8),
                Padding = new Thickness(10, 6, 10, 6),
                Background = isSelected ? tag.BackgroundBrush : FleetCommandBrush(BridgeBrushToken.Panel),
                BorderBrush = isSelected ? tag.AccentBrush : FleetCommandBrush(BridgeBrushToken.ChipHairline),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(2),
                Cursor = Cursors.Hand,
                Tag = tag,
                ToolTip = tag.TooltipText
            };
            border.MouseLeftButtonUp += ManageTagOptionBorder_MouseLeftButtonUp;

            var content = new StackPanel { Orientation = ControlsOrientation.Horizontal };
            content.Children.Add(new Border
            {
                Width = 6,
                Height = 16,
                Margin = new Thickness(0, 0, 7, 0),
                VerticalAlignment = VerticalAlignment.Center,
                Background = tag.AccentBrush,
                CornerRadius = new CornerRadius(2),
                Opacity = isSelected ? 1 : 0.62
            });
            content.Children.Add(new TextBlock
            {
                Text = tag.Name,
                Foreground = FleetCommandBrush(isSelected ? BridgeBrushToken.Ink : BridgeBrushToken.Ink2),
                FontSize = 12,
                FontWeight = FontWeights.SemiBold,
                VerticalAlignment = VerticalAlignment.Center
            });
            if (isSelected)
            {
                content.Children.Add(new TextBlock
                {
                    Text = "  ✓",
                    Foreground = tag.AccentBrush,
                    FontWeight = FontWeights.Bold,
                    VerticalAlignment = VerticalAlignment.Center
                });
            }

            border.Child = content;
            ManageTagOptionsPanel.Children.Add(border);
        }
    }

    private void ManageTagOptionBorder_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (sender is not Border { Tag: ManageFleetTagOptionRow tag })
        {
            return;
        }

        if (_manageTagDraftIds.Contains(tag.Id))
        {
            _manageTagDraftIds.Remove(tag.Id);
            SetManageTagStatus($"已移除：{tag.Name}");
        }
        else
        {
            if (_manageTagDraftIds.Count >= MaxManageFleetTags)
            {
                SetManageTagStatus($"最多选择 {MaxManageFleetTags.ToString(CultureInfo.InvariantCulture)} 个组织标签。");
                return;
            }

            _manageTagDraftIds.Add(tag.Id);
            SetManageTagStatus($"已选择：{tag.Name}");
        }

        if (ManageTagUnsavedPrompt is not null)
        {
            ManageTagUnsavedPrompt.Visibility = Visibility.Collapsed;
        }
        ManageTagSelectorFooter.Visibility = Visibility.Visible;

        RenderManageTagSelector();
    }

    private void RefreshManageTagDraftPreview()
    {
        _manageTagDraftPreviewRows.Clear();
        foreach (var tag in GetTagRows(_manageTagDraftIds))
        {
            _manageTagDraftPreviewRows.Add(tag);
        }

        if (ManageTagDraftCountText is not null)
        {
            ManageTagDraftCountText.Text =
                $"{_manageTagDraftIds.Count.ToString(CultureInfo.InvariantCulture)} / {MaxManageFleetTags.ToString(CultureInfo.InvariantCulture)}";
        }
    }

    private void ManageTagSelectorSaveButton_Click(object sender, RoutedEventArgs e)
    {
        ApplyManageTagDraftAndClose();
    }

    private void ManageTagSelectorCancelButton_Click(object sender, RoutedEventArgs e)
    {
        TryCloseManageTagSelector();
    }

    private void ManageTagSelectorCloseButton_Click(object sender, RoutedEventArgs e)
    {
        e.Handled = true;
        TryCloseManageTagSelector();
    }

    private void TryCloseManageTagSelector()
    {
        var sourceTagIds = GetManageTagSelectorSourceIds();
        if (!AreTagSetsEqual(_manageTagDraftIds, sourceTagIds))
        {
            ShowManageTagUnsavedPrompt();
            return;
        }

        CloseManageTagSelector();
    }

    private void ShowManageTagUnsavedPrompt()
    {
        ManageTagSelectorFooter.Visibility = Visibility.Collapsed;
        UiMotion.ShowStatus(ManageTagUnsavedPrompt);

        SetManageTagStatus("标签选择尚未保存。");
    }

    private void ManageTagUnsavedContinueButton_Click(object sender, RoutedEventArgs e)
    {
        UiMotion.HideStatus(ManageTagUnsavedPrompt);
        ManageTagSelectorFooter.Visibility = Visibility.Visible;

        SetManageTagStatus("继续编辑标签。");
    }

    private void ManageTagUnsavedDiscardButton_Click(object sender, RoutedEventArgs e)
    {
        CloseManageTagSelector();
    }

    private void ManageTagUnsavedSaveButton_Click(object sender, RoutedEventArgs e)
    {
        ApplyManageTagDraftAndClose();
    }

    private void ApplyManageTagDraftAndClose()
    {
        if (_isCreateFleetTagSelectorMode)
        {
            SetCreateFleetSelectedTagIds(_manageTagDraftIds);
            ValidateCreateFleetForm(showRequiredErrors: false);
            CloseManageTagSelector();
            SetManageTagStatus("点击标签选择或取消选择。");
            return;
        }

        if (_isFindFleetTagFilterSelectorMode)
        {
            SetFindFleetFilterTagIds(_manageTagDraftIds);
            RefreshFindFleetFilterDraftSummary();
            CloseManageTagSelector();
            SetManageTagStatus("点击标签选择或取消选择。");
            return;
        }

        EnsureManageProfileDraftBaseline();
        SetManageProfileSelectedTagIds(_manageTagDraftIds);
        HandleManageProfileDraftChanged();
        CloseManageTagSelector();
        SetFleetDescriptionStatus("组织标签已更新，保存基础资料后生效。", ManageProfileStatusTone.Info);
    }

    private ISet<string> GetManageTagSelectorSourceIds()
    {
        if (_isFindFleetTagFilterSelectorMode)
        {
            return _findFleetFilterTagIds;
        }

        return _isCreateFleetTagSelectorMode
            ? _createFleetSelectedTagIds
            : _manageProfileSelectedTagIds;
    }

    private void CloseManageTagSelector()
    {
        ManageTagSelectorOverlay.Hide();

        UiMotion.HideStatus(ManageTagUnsavedPrompt);
        ManageTagSelectorFooter.Visibility = Visibility.Visible;

        SetManageTagStatus("点击标签选择或取消选择。");
        _isCreateFleetTagSelectorMode = false;
        _isFindFleetTagFilterSelectorMode = false;
    }

    private void SetManageTagStatus(string message)
    {
        if (ManageTagSelectorStatusText is not null)
        {
            ManageTagSelectorStatusText.Text = message;
        }
    }

    private static bool AreTagSetsEqual(ISet<string> left, ISet<string> right)
    {
        return left.Count == right.Count && left.All(right.Contains);
    }

    private static bool IsKnownFleetTagId(string id)
    {
        return FleetTagDefinitions.Any(tag => tag.Id.Equals(id, StringComparison.OrdinalIgnoreCase));
    }

    private static ManageFleetTagDefinition? GetFleetTagDefinition(string id)
    {
        return FleetTagDefinitions.FirstOrDefault(tag =>
            tag.Id.Equals(id, StringComparison.OrdinalIgnoreCase));
    }

    private static IEnumerable<ManageFleetTagOptionRow> GetTagRows(IEnumerable<string> tagIds)
    {
        foreach (var id in tagIds)
        {
            var tag = GetFleetTagDefinition(id);
            if (tag is null)
            {
                continue;
            }

            var category = FleetTagCategoryDefinitions.FirstOrDefault(item =>
                item.Id.Equals(tag.CategoryId, StringComparison.OrdinalIgnoreCase));
            if (category is null)
            {
                continue;
            }

            yield return new ManageFleetTagOptionRow(tag, category);
        }
    }

    private void RefreshManageProfileSystemOptionsState()
    {
        if (ManageProfileSystemOptionsList is null || ManageProfileSystemEmptyText is null)
        {
            return;
        }

        ManageProfileSystemOptionsList.Visibility = _manageFleetSystemOptions.Count == 0
            ? Visibility.Collapsed
            : Visibility.Visible;
        ManageProfileSystemEmptyText.Visibility = _manageFleetSystemOptions.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;

        if (_manageFleetSystemOptions.Count == 0)
        {
            ManageProfileSystemOptionsList.SelectedItems.Clear();
            return;
        }

        var wasRefreshing = _isManageProfileRefreshing;
        _isManageProfileRefreshing = true;
        try
        {
            ManageProfileSystemOptionsList.SelectedItems.Clear();
            foreach (var option in _manageFleetSystemOptions.Where(option =>
                         option.IsImageAvailable &&
                         _selectedFleetSystemIds.Contains(option.Id)))
            {
                ManageProfileSystemOptionsList.SelectedItems.Add(option);
            }
        }
        finally
        {
            _isManageProfileRefreshing = wasRefreshing;
        }
    }

    private void LoadAllowedFleetSystemOptions()
    {
        var options = AllowedFleetSystemAssets.Select(asset =>
        {
            var relativePath = Path.Combine(LocalSystemAssetsRelativeDirectory, asset.FileName)
                .Replace('\\', '/');
            var resolvedPath = ResolveAllowedFleetSystemAssetPath(asset.FileName);
            var isAvailable = resolvedPath is not null;
            var imagePath = isAvailable ? resolvedPath! : relativePath;
            var detail = asset.Id switch
            {
                "stanton" => "核心民用星系，企业世界集中，交通与活动密度高。",
                "pyro" => "危险边境星系，秩序薄弱，适合高风险行动。",
                "nyx" => "偏远隐秘星系，小行星与边境据点密集。",
                _ => "等待本地星系资料"
            };
            return new ManageFleetSystemOptionRow(asset.Id, asset.Name, asset.ChineseName, imagePath, detail, isAvailable);
        });

        SetManageFleetSystemOptions(options);
    }

    private static string? ResolveAllowedFleetSystemAssetPath(string fileName)
    {
        if (AllowedFleetSystemAssets.All(asset =>
                !asset.FileName.Equals(fileName, StringComparison.OrdinalIgnoreCase)))
        {
            return null;
        }

        var appAssetPath = Path.Combine(AppContext.BaseDirectory, LocalSystemAssetsRelativeDirectory, fileName);
        if (File.Exists(appAssetPath))
        {
            return appAssetPath;
        }

        var sourceAssetPath = Path.Combine(AppContext.BaseDirectory, "..", "..", "..", LocalSystemAssetsRelativeDirectory, fileName);
        sourceAssetPath = Path.GetFullPath(sourceAssetPath);
        return File.Exists(sourceAssetPath) ? sourceAssetPath : null;
    }

    private void SetManageFleetSystemOptions(IEnumerable<ManageFleetSystemOptionRow> options)
    {
        _manageFleetSystemOptions.Clear();
        foreach (var option in options
                     .Where(option => !string.IsNullOrWhiteSpace(option.Id) &&
                                      !string.IsNullOrWhiteSpace(option.Name) &&
                                      !string.IsNullOrWhiteSpace(option.ImagePath))
                     .Take(3))
        {
            _manageFleetSystemOptions.Add(option);
        }

        _selectedFleetSystemIds.RemoveWhere(id =>
            _manageFleetSystemOptions.All(option =>
                !option.IsImageAvailable ||
                !option.Id.Equals(id, StringComparison.OrdinalIgnoreCase)));

        if (_selectedFleetSystemId is not null &&
            !_selectedFleetSystemIds.Contains(_selectedFleetSystemId) &&
            _manageFleetSystemOptions.Any(option =>
                option.IsImageAvailable &&
                option.Id.Equals(_selectedFleetSystemId, StringComparison.OrdinalIgnoreCase)))
        {
            _selectedFleetSystemIds.Add(_selectedFleetSystemId);
        }

        RefreshPrimarySelectedFleetSystemId();
        RefreshManageProfileSystemOptionsState();
        RefreshManageSettingsPreview();
    }

    private void SetSelectedFleetSystemIds(IEnumerable<string> systemIds, bool refreshSelection = true)
    {
        _selectedFleetSystemIds.Clear();
        foreach (var id in systemIds
                     .Where(id => !string.IsNullOrWhiteSpace(id))
                     .Select(id => id.Trim())
                     .Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (_manageFleetSystemOptions.Count > 0 &&
                _manageFleetSystemOptions.All(option =>
                    !option.IsImageAvailable ||
                    !option.Id.Equals(id, StringComparison.OrdinalIgnoreCase)))
            {
                continue;
            }

            _selectedFleetSystemIds.Add(id);
        }

        RefreshPrimarySelectedFleetSystemId();
        if (refreshSelection)
        {
            RefreshManageProfileSystemOptionsState();
        }
    }

    private void RefreshPrimarySelectedFleetSystemId()
    {
        _selectedFleetSystemId = _manageFleetSystemOptions
            .FirstOrDefault(option => _selectedFleetSystemIds.Contains(option.Id))
            ?.Id;
    }

    private void SetManageProfileDirty(bool isDirty)
    {
        _isManageProfileDirty = isDirty;
        if (isDirty)
        {
            UiMotion.ShowStatus(ManageUnsavedChangesBar);
        }
        else
        {
            UiMotion.HideStatus(ManageUnsavedChangesBar);
        }

        if (!isDirty)
        {
            SetManageProfileSaveBarMessage("");
            _manageProfileSaveState = ManageProfileSaveState.Idle;
        }
        else if (_manageProfileSaveState != ManageProfileSaveState.Saving)
        {
            SetManageProfileSaveState(ManageProfileSaveState.Idle, "");
        }

        RefreshManageProfileSaveControls();
    }

    private enum ManageProfileStatusTone
    {
        Info,
        Success,
        Warning,
        Danger,
        Locked
    }

    private enum ManageProfileSaveState
    {
        Idle,
        Saving,
        Success,
        Error
    }

    private void SetManageProfileSaveState(ManageProfileSaveState state, string message)
    {
        _manageProfileSaveState = state;
        if (ManageUnsavedChangesBar is null || ManageUnsavedChangesTitleText is null)
        {
            return;
        }

        if (ManageUnsavedChangesBar.Visibility != Visibility.Visible)
        {
            UiMotion.ShowStatus(ManageUnsavedChangesBar);
        }
        ManageUnsavedChangesTitleText.Text = state switch
        {
            ManageProfileSaveState.Saving => "正在保存更改",
            ManageProfileSaveState.Success => "更改已保存",
            ManageProfileSaveState.Error => "保存失败",
            _ => "你有未保存的更改"
        };
        var tone = state switch
        {
            ManageProfileSaveState.Success => ManageProfileStatusTone.Success,
            ManageProfileSaveState.Error => ManageProfileStatusTone.Danger,
            ManageProfileSaveState.Saving => ManageProfileStatusTone.Info,
            _ => ManageProfileStatusTone.Warning
        };
        SetManageProfileSaveBarMessage(message, state == ManageProfileSaveState.Error);
        ManageUnsavedChangesBar.BorderBrush = GetManageProfileStatusBrush(tone);
        ManageUnsavedChangesTitleText.Foreground = GetManageProfileStatusBrush(tone);
        if (ManageUnsavedChangesStatusText is not null)
        {
            ManageUnsavedChangesStatusText.Foreground = GetManageProfileStatusBrush(tone);
        }

        var canInteract = state is ManageProfileSaveState.Idle or ManageProfileSaveState.Error;
        if (ManageDiscardChangesButton is not null)
        {
            ManageDiscardChangesButton.IsEnabled = canInteract;
        }

        if (ManageSaveChangesButton is not null)
        {
            ManageSaveChangesButton.IsEnabled = canInteract;
            ManageSaveChangesButton.Content = state == ManageProfileSaveState.Saving ? "保存中..." : "保存更改";
        }

        if (ManageProfileHeaderSaveButton is not null)
        {
            ManageProfileHeaderSaveButton.IsEnabled = canInteract;
            ManageProfileHeaderSaveButton.Content = state == ManageProfileSaveState.Saving ? "保存中..." : "保存更改";
        }

        if (ManageProfileHeaderCancelButton is not null)
        {
            ManageProfileHeaderCancelButton.IsEnabled = canInteract;
        }
    }

    private string BuildFleetShipSidebarSnapshot()
    {
        var snapshot = new StringBuilder(2048);
        foreach (var ship in _fleetShipInventory)
        {
            snapshot
                .Append(BuildFleetShipInventoryKey(ship)).Append('|')
                .Append(ship.ShipName).Append('|')
                .Append(ship.OwnerDisplay).Append('|')
                .Append(ship.OwnerGameId).Append('|')
                .Append(ship.ShipSpec).Append('|')
                .Append(ship.ShipRole).Append('|')
                .Append(ship.ShipRoleTag).Append('|')
                .Append(ship.ShipPriceValue?.ToString(CultureInfo.InvariantCulture)).Append('|')
                .Append(IsFleetShipConcept(ship) ? '1' : '0').Append('|')
                .Append(IsFleetShipFlyable(ship) ? '1' : '0').Append(';');

            foreach (var loaner in ship.LoanerRows)
            {
                snapshot
                    .Append("L:").Append(BuildFleetShipInventoryKey(loaner)).Append('|')
                    .Append(loaner.ShipName).Append('|')
                    .Append(loaner.ShipSpec).Append('|')
                    .Append(loaner.ShipRole).Append('|')
                    .Append(IsFleetShipFlyable(loaner) ? '1' : '0').Append(';');
            }
        }

        snapshot.Append("#P#");
        foreach (var player in _players
                     .OrderBy(player => player.Name, StringComparer.OrdinalIgnoreCase)
                     .ThenBy(player => player.Callsign, StringComparer.OrdinalIgnoreCase))
        {
            snapshot
                .Append(player.Name).Append('|')
                .Append(player.Callsign).Append('|')
                .Append(player.Status).Append(';');
        }

        return snapshot.ToString();
    }

    private System.Windows.Media.Brush GetManageProfileStatusBrush(ManageProfileStatusTone tone)
    {
        return tone switch
        {
            ManageProfileStatusTone.Success => FleetCommandBrush(BridgeBrushToken.StatusOk),
            ManageProfileStatusTone.Warning => FleetCommandBrush(BridgeBrushToken.StatusWarn),
            ManageProfileStatusTone.Danger => FleetCommandBrush(BridgeBrushToken.StatusBad),
            ManageProfileStatusTone.Locked => FleetCommandBrush(BridgeBrushToken.StatusOff),
            _ => FleetCommandBrush(BridgeBrushToken.StatusInfo)
        };
    }

    private void SetFleetDescriptionStatus(string message, ManageProfileStatusTone tone = ManageProfileStatusTone.Info)
    {
        if (FleetDescriptionStatusText is null)
        {
            return;
        }

        FleetDescriptionStatusText.Text = message;
        FleetDescriptionStatusText.Foreground = GetManageProfileStatusBrush(tone);
    }

    private void SetManageProfileSaveBarMessage(string? message, bool isError = false)
    {
        if (ManageUnsavedChangesStatusText is null)
        {
            return;
        }

        var tone = isError ? ManageProfileStatusTone.Danger : ManageProfileStatusTone.Warning;
        var hasMessage = !string.IsNullOrWhiteSpace(message);
        ManageUnsavedChangesStatusText.Text = hasMessage ? message!.Trim() : "";
        ManageUnsavedChangesStatusText.Visibility = hasMessage
            ? Visibility.Visible
            : Visibility.Collapsed;
        ManageUnsavedChangesStatusText.Foreground = GetManageProfileStatusBrush(tone);
        if (ManageUnsavedChangesBar is not null)
        {
            ManageUnsavedChangesBar.BorderBrush = GetManageProfileStatusBrush(tone);
        }
    }

    private void ShowManageProfileSaveFailure(string message)
    {
        SetManageProfileDirty(true);
        if (ManageUnsavedChangesBar is not null)
        {
            ManageUnsavedChangesBar.Visibility = Visibility.Visible;
        }

        SetManageProfileSaveState(ManageProfileSaveState.Error, message);
    }

    private void ResetFleetProfileDraftButton_Click(object sender, RoutedEventArgs e)
    {
#if DEBUG
        if (TryHandleFleetProfileAcceptanceReset())
        {
            return;
        }
#endif

        _isManageProfileDiscardingDraft = true;
        var baselineState = _manageProfileDraftBaselineStateJson;
        ClearManageProfileDraftBaseline();
        try
        {
            if (!string.IsNullOrWhiteSpace(baselineState))
            {
                LoadFleetState(baselineState);
                RefreshFleetViewsAfterRestore();
                ForceRefreshFleetEditorControlsAfterRestore();
                SaveCurrentConfig();
            }
            else
            {
                RefreshManageFleetBasicProfile(forceTextBoxes: true);
            }

            SetManageProfileDirty(false);
            SetManageProfileEditMode(CanCurrentUserManageFleetInfo());
            SetFleetDescriptionStatus("已重置未保存的基础资料修改。", ManageProfileStatusTone.Warning);
        }
        finally
        {
            Dispatcher.BeginInvoke(new Action(() =>
            {
                SetManageProfileDirty(false);
                RefreshManageProfileSaveControls();
                _isManageProfileDiscardingDraft = false;
            }), DispatcherPriority.ContextIdle);
        }
    }

    private async void SaveFleetProfileDraftButton_Click(object sender, RoutedEventArgs e)
    {
#if DEBUG
        if (TryHandleFleetProfileAcceptanceSave())
        {
            return;
        }
#endif

        if (_manageProfileSaveState == ManageProfileSaveState.Saving)
        {
            return;
        }

        if (!EnsureLoggedIn("保存组织基础资料需要先登录。"))
        {
            return;
        }

        if (!CanCurrentUserManageFleetInfo())
        {
            SetFleetDescriptionStatus("当前账号没有保存组织资料的权限。", ManageProfileStatusTone.Locked);
            return;
        }

        SetManageProfileSaveState(ManageProfileSaveState.Saving, "正在保存本地设置并同步到组织...");

        var hadManageProfileDraftChanges = _isManageProfileDirty;
        var rollbackState = CaptureManageProfileRollbackState();
        SyncSelectedFleetSystemIdsFromList();
        var descriptionBefore = _fleetDescription;
        var fleetTypeBefore = _fleetType;
        var fleetActiveTimeBefore = _fleetActiveTime;
        var fleetJoinPolicyBefore = _fleetJoinPolicy;
        var fleetRecruitingEnabledBefore = _fleetRecruitingEnabled;
        var fleetRecruitingTargetBefore = _fleetRecruitingTarget;
        var fleetInviteCodeCreationPolicyBefore = _fleetInviteCodeCreationPolicy;
        var fleetInvitationCardPolicyBefore = _fleetInvitationCardPolicy;
        var emailNotificationsBefore = _fleetEmailNotificationsEnabled;
        var publicListingBefore = _fleetPublicListingEnabled;
        var publicMemberScaleBefore = _fleetPublicMemberScaleMode;
        var publicShipScaleBefore = _fleetPublicShipScaleMode;
        var publicProfileBefore = _manageAllowPublicProfileView;
        var publicDescriptionBefore = _manageShowDescriptionPublic;
        var publicTagsBefore = _fleetPublicShowTags;
        var publicSystemsBefore = _fleetPublicShowActiveSystems;
        var publicActivityBefore = _fleetPublicShowActivityTime;
        var publicContactsBefore = _fleetPublicShowExternalContacts;
        var fleetTimeZoneBefore = _fleetTimeZoneId;
        var fleetActivityCadenceBefore = _fleetActivityCadence;
        var fleetActivityWindowsKeyBefore = BuildFleetActivityWindowsKey(BuildNetworkFleetActivityWindows());
        _manageProfileDisplayShortName = NormalizeOptionalField(ManageProfileShortNameBox?.Text);
        _manageProfilePublicDisplayName = NormalizeOptionalField(ManageProfilePublicNameBox?.Text);
        _fleetDescription = NormalizeFleetDescription(FleetDescriptionEditBox?.Text);
        _fleetType = BuildCreateFleetTypeSummary(_manageProfileSelectedTagIds);
        _fleetJoinPolicy = NormalizeFleetJoinPolicyTag(GetSelectedComboBoxTag(ManageJoinPolicyBox) ?? _fleetJoinPolicy);
        _fleetRecruitingEnabled = ManageRecruitingEnabledCheck?.IsChecked == true;
        _fleetRecruitingTarget = NormalizeFleetRecruitingTarget(GetSelectedComboBoxTag(ManageRecruitingTargetBox) ?? _fleetRecruitingTarget);
        _fleetInviteCodeCreationPolicy = FleetInvitationAccessPolicy.Normalize(
            GetSelectedComboBoxTag(ManageInviteCodePolicyBox) ?? _fleetInviteCodeCreationPolicy);
        _fleetInvitationCardPolicy = FleetInvitationAccessPolicy.Normalize(
            GetSelectedComboBoxTag(ManageInvitationCardPolicyBox) ?? _fleetInvitationCardPolicy);
        _manageShowDescriptionPublic = ManagePublicDescriptionCheck?.IsChecked ??
                                       ManageProfileShowDescriptionCheck.IsChecked == true;
        _manageShowAnnouncementPublic = ManageProfileShowAnnouncementCheck.IsChecked == true;
        _manageAllowPublicProfileView = true;
        _fleetPublicListingEnabled = ManagePublicListingCheck?.IsChecked ?? _fleetPublicListingEnabled;
        _fleetPublicMemberScaleMode = NormalizeFleetPublicMemberScaleMode(
            GetSelectedComboBoxTag(ManagePublicMemberScaleBox) ?? _fleetPublicMemberScaleMode);
        _fleetPublicShipScaleMode = NormalizeFleetPublicShipScaleMode(
            GetSelectedComboBoxTag(ManagePublicShipScaleBox) ?? _fleetPublicShipScaleMode);
        _fleetPublicShowTags = ManagePublicTagsCheck?.IsChecked ?? _fleetPublicShowTags;
        _fleetPublicShowActiveSystems = ManagePublicSystemsCheck?.IsChecked ?? _fleetPublicShowActiveSystems;
        _fleetPublicShowActivityTime = ManagePublicActivityCheck?.IsChecked ?? _fleetPublicShowActivityTime;
        _fleetLanguage = "zh-CN";
        _fleetTimeZoneId = ManageFleetTimeZoneBox?.SelectedValue as string ?? _fleetTimeZoneId;
        SyncFleetActivityWindowsFromEditor();
        _fleetActivityCadence = NormalizeManageProfileOption(
            GetSelectedComboBoxContent(ManageFleetActivityCadenceBox),
            "休闲");
        _fleetWebsiteUrl = NormalizeOptionalField(ManageFleetWebsiteBox?.Text);
        NormalizeFleetExternalContactsFromRows();
        _fleetPublicShowExternalContacts = FleetExternalContactPublication.ResolveOnSave(
            _fleetExternalContactPublicationMode,
            _legacyExternalContactPublicationConfirmed,
            _fleetExternalContacts);

        AddFleetLog("组织", "基础资料更新", "公开展示与活动信息已更新");
        RefreshFleetHeader();
        RefreshTaskManagementPanel();
        SaveCurrentConfig();

        var shouldSyncFleetInfo = hadManageProfileDraftChanges ||
                                  !string.Equals(descriptionBefore, _fleetDescription, StringComparison.Ordinal) ||
                                  !string.Equals(fleetTypeBefore, _fleetType, StringComparison.Ordinal) ||
                                  !string.Equals(fleetActiveTimeBefore, _fleetActiveTime, StringComparison.Ordinal) ||
                                  !string.Equals(fleetJoinPolicyBefore, _fleetJoinPolicy, StringComparison.Ordinal) ||
                                  fleetRecruitingEnabledBefore != _fleetRecruitingEnabled ||
                                  !string.Equals(fleetRecruitingTargetBefore, _fleetRecruitingTarget, StringComparison.Ordinal) ||
                                  !string.Equals(fleetInviteCodeCreationPolicyBefore, _fleetInviteCodeCreationPolicy, StringComparison.Ordinal) ||
                                  !string.Equals(fleetInvitationCardPolicyBefore, _fleetInvitationCardPolicy, StringComparison.Ordinal) ||
                                  !string.Equals(fleetTimeZoneBefore, _fleetTimeZoneId, StringComparison.Ordinal) ||
                                  !string.Equals(fleetActivityCadenceBefore, _fleetActivityCadence, StringComparison.Ordinal) ||
                                  !string.Equals(fleetActivityWindowsKeyBefore, BuildFleetActivityWindowsKey(BuildNetworkFleetActivityWindows()), StringComparison.Ordinal) ||
                                  emailNotificationsBefore != _fleetEmailNotificationsEnabled ||
                                  publicListingBefore != _fleetPublicListingEnabled ||
                                  !string.Equals(publicMemberScaleBefore, _fleetPublicMemberScaleMode, StringComparison.Ordinal) ||
                                  !string.Equals(publicShipScaleBefore, _fleetPublicShipScaleMode, StringComparison.Ordinal) ||
                                  publicProfileBefore != _manageAllowPublicProfileView ||
                                  publicDescriptionBefore != _manageShowDescriptionPublic ||
                                  publicTagsBefore != _fleetPublicShowTags ||
                                  publicSystemsBefore != _fleetPublicShowActiveSystems ||
                                  publicActivityBefore != _fleetPublicShowActivityTime ||
                                  publicContactsBefore != _fleetPublicShowExternalContacts;
        SetFleetDescriptionStatus(
            shouldSyncFleetInfo
                ? "已保存到本地，正在同步组织资料..."
                : "基础资料已保存到本地。",
            ManageProfileStatusTone.Info);

        if (shouldSyncFleetInfo)
        {
            ProtectFleetProfileUntilServerEcho();
            SetFleetDescriptionStatus("正在同步组织基础资料...", ManageProfileStatusTone.Info);
            if (!await PushFleetInfoAsync(silent: false))
            {
                ClearFleetProfileSyncEchoProtection();
                RestoreFleetStateAfterFailedMutation(rollbackState, "组织基础资料同步失败，已恢复本地资料状态。");
                ShowManageProfileSaveFailure("基础资料同步失败，已恢复本地设置。");
                return;
            }
        }

        SetFleetDescriptionStatus("基础资料已保存并同步。", ManageProfileStatusTone.Success);
        SetManageProfileSaveState(ManageProfileSaveState.Success, "基础资料已保存并同步");
        ApplyLoadedExternalContactPublicationState(_fleetPublicShowExternalContacts);
        RefreshManageFleetOverview();
        RefreshManageFleetBasicProfile();
        RefreshManageSettingsPreview();
        SaveCurrentConfig();
        await Task.Delay(900);
        ClearManageProfileDirtyAfterSuccessfulSave();
        SetManageProfileEditMode(CanCurrentUserManageFleetInfo());
    }

    private void ClearManageProfileDirtyAfterSuccessfulSave()
    {
        ClearManageProfileDraftBaseline();
        SetManageProfileDirty(false);
        Dispatcher.BeginInvoke(new Action(() =>
        {
            SetManageProfileDirty(false);
        }), DispatcherPriority.ContextIdle);
    }

    private void RefreshManageSettingsPreview()
    {
        if (ManagePreviewFleetNameText is null)
        {
            return;
        }

        var fleetName = GetTextBoxDraftValue(ManageProfileFleetNameBox, _fleetName);
        if (string.IsNullOrWhiteSpace(fleetName))
        {
            fleetName = "未命名组织";
        }

        var fleetCode = GetTextBoxDraftValue(ManageProfileFleetCodeBox, _fleetCode);
        if (string.IsNullOrWhiteSpace(fleetCode))
        {
            fleetCode = "未设置";
        }

        var commander = FormatCommanderName(_callsign, _localPlayer, _fleetChiefCommander);
        var description = NormalizeFleetDescription(GetTextBoxDraftValue(FleetDescriptionEditBox, _fleetDescription));
        var noticeSummary = GetTextBoxDraftValue(ManageProfileAnnouncementBox, _fleetNoticeContent);
        var noticeTitle = string.IsNullOrWhiteSpace(noticeSummary) ? "暂无组织公告" : "组织公告";
        var selectedSystems = _manageFleetSystemOptions
            .Where(option => _selectedFleetSystemIds.Contains(option.Id))
            .Select(option => option.ChineseName)
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .ToArray();
        var systemText = selectedSystems.Length == 0
            ? "未选择"
            : string.Join(" / ", selectedSystems);
        var profileVisibilityText = ManageProfileAllowPublicProfileCheck?.IsChecked == true
            ? "基础资料可见"
            : "仅内部可见";
        noticeSummary = string.IsNullOrWhiteSpace(noticeSummary)
            ? "公告会显示在组织信息页。"
            : noticeSummary;

        ManagePreviewFleetNameText.Text = fleetName;
        ManagePreviewFleetCodeText.Text = fleetCode;
        ManagePreviewCommanderText.Text = commander;
        ManagePreviewSystemText.Text = systemText;
        ManagePreviewNoticeTitleText.Text = noticeTitle;
        ManagePreviewNoticeSummaryText.Text = noticeSummary;
        ManagePreviewJoinTitleText.Text = "组织简介";
        ManagePreviewJoinSummaryText.Text = string.IsNullOrWhiteSpace(description) ? FleetDescriptionPublicPlaceholder : description;
        ManagePreviewJoinPolicyText.Text = profileVisibilityText;

        SetImagePreview(ManagePreviewFleetLogoImage, ManagePreviewFleetLogoText, _fleetLogoPath);
    }

    private static string GetTextBoxDraftValue(System.Windows.Controls.TextBox? textBox, string fallback)
    {
        if (textBox is not null && !string.IsNullOrWhiteSpace(textBox.Text))
        {
            return textBox.Text.Trim();
        }

        return fallback;
    }

    private static string NormalizeFleetJoinPolicyTag(string? value)
    {
        return value?.Trim().ToLowerInvariant() switch
        {
            "closed" or "不招募" => "Closed",
            "application" or "申请加入" => "Application",
            "invite" or "邀请加入" => "Invite",
            _ => "Open"
        };
    }

    private static string FormatFleetJoinPolicy(string? value)
    {
        return NormalizeFleetJoinPolicyTag(value) switch
        {
            "Closed" => "不招募",
            "Application" => "申请加入",
            "Invite" => "邀请加入",
            _ => "公开招募"
        };
    }

    private static string NormalizeFleetRecruitingTarget(string? value)
    {
        var normalized = NormalizeOptionalField(value);
        return normalized switch
        {
            "新手友好" or "战斗玩家" or "工业玩家" or "贸易与货运" or "医疗与支援" => normalized,
            _ => "所有玩家"
        };
    }

    private static string NormalizeFleetPublicMemberScaleMode(string? value)
    {
        return value?.Trim().ToLowerInvariant() switch
        {
            "approx" => FleetPublicMemberScaleApprox,
            "hidden" => FleetPublicMemberScaleHidden,
            _ => FleetPublicMemberScaleExact
        };
    }

    private static string NormalizeFleetPublicShipScaleMode(string? value)
    {
        return value?.Trim().ToLowerInvariant() switch
        {
            "totalonly" => FleetPublicShipScaleTotalOnly,
            "hidden" => FleetPublicShipScaleHidden,
            _ => FleetPublicShipScaleTypeSummary
        };
    }

    private static string NormalizeManageProfileOption(string? value, string fallback)
    {
        return string.IsNullOrWhiteSpace(value)
            ? fallback
            : value.Trim();
    }

    private static void SelectComboBoxItemByTag(System.Windows.Controls.ComboBox? comboBox, string? tag)
    {
        if (comboBox is null)
        {
            return;
        }

        foreach (var item in comboBox.Items.OfType<ComboBoxItem>())
        {
            if (string.Equals(item.Tag?.ToString(), tag, StringComparison.OrdinalIgnoreCase))
            {
                comboBox.SelectedItem = item;
                return;
            }
        }

        comboBox.SelectedIndex = comboBox.Items.Count > 0 ? 0 : -1;
    }

    private static void SelectComboBoxItemByContent(System.Windows.Controls.ComboBox? comboBox, string content)
    {
        if (comboBox is null)
        {
            return;
        }

        foreach (var item in comboBox.Items.OfType<ComboBoxItem>())
        {
            if (string.Equals(item.Content?.ToString(), content, StringComparison.OrdinalIgnoreCase))
            {
                comboBox.SelectedItem = item;
                return;
            }
        }

        comboBox.SelectedIndex = comboBox.Items.Count > 0 ? 0 : -1;
    }

    private static string? GetSelectedComboBoxTag(System.Windows.Controls.ComboBox? comboBox)
    {
        return (comboBox?.SelectedItem as ComboBoxItem)?.Tag?.ToString();
    }

    private static string? GetSelectedComboBoxContent(System.Windows.Controls.ComboBox? comboBox)
    {
        return (comboBox?.SelectedItem as ComboBoxItem)?.Content?.ToString();
    }

    private static void SetTextIfSafe(System.Windows.Controls.TextBox? textBox, string value, bool force = false)
    {
        if (textBox is null || (!force && textBox.IsKeyboardFocusWithin))
        {
            return;
        }

        textBox.Text = value;
    }

    private static void SetImagePreview(System.Windows.Controls.Image? imageControl, TextBlock? placeholder, string? path)
    {
        if (imageControl is null || placeholder is null)
        {
            return;
        }

        if (!TryLoadBitmapImage(path, out var image))
        {
            imageControl.Source = null;
            placeholder.Visibility = Visibility.Visible;
            return;
        }

        imageControl.Source = image;
        placeholder.Visibility = Visibility.Collapsed;
    }

    private static bool TryLoadBitmapImage(string? path, out BitmapImage? image)
    {
        image = null;
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
        {
            return false;
        }

        try
        {
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.UriSource = new Uri(path);
            bitmap.EndInit();
            bitmap.Freeze();
            image = bitmap;
            return true;
        }
        catch
        {
            return false;
        }
    }
}
