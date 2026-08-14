using StarBridge.Core.Events;
using StarBridge.Core.FleetChat;
using StarBridge.Core.Fleets;
using System.Text.Json;
using Visibility = System.Windows.Visibility;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private const string FleetCommanderRoleGroupKey = "fleet_commander";
    private const string FleetCommanderDefaultRoleColor = FleetRoleColorPalette.Gold;
    private const string FleetDeputyCommanderRoleGroupKey = "fleet_deputy_commander";
    private const string FleetDeputyCommanderDefaultRoleColor = FleetRoleColorPalette.Blue;

    private void RenderCachedIdentity()
    {
        if (!IsLoggedIn)
        {
            GameNameText.Text = "请登录后查看";
            PlayerIdText.Text = "请登录后查看";
            ProfileStatusText.Text = "浏览模式";
            return;
        }

        if (!string.IsNullOrWhiteSpace(_logPath))
        {
            LogPathBox.Text = _logPath;
        }

        if (string.IsNullOrWhiteSpace(_localPlayer))
        {
            GameNameText.Text = _language == "zh" ? "等待游戏日志身份信息" : "Waiting for Game.log identity";
            PlayerIdText.Text = "等待识别游戏 ID";
            ProfileStatusText.Text = _language == "zh" ? "需要身份信息" : "Identity Required";
            return;
        }

        GameNameText.Text = _localPlayer;
        PlayerIdText.Text = string.IsNullOrWhiteSpace(_localPlayerId) ? "Unknown" : _localPlayerId;
        ProfileStatusText.Text = _language == "zh" ? "已缓存身份" : "Cached Identity";
        _fleetState.Apply(new FleetEvent(FleetEventType.PlayerOffline, _localPlayer));
        RenderState();
    }

    private void SaveCurrentConfig(bool clearSavedSession = false)
    {
        if (OverlayHotkeyBox is null ||
            NetworkServerUrlBox is null ||
            NetworkServerKeyBox is null)
        {
            return;
        }

        var isLoggedIn = IsLoggedIn;
        var persistedAccountName = _accountName;
        var persistedAccountId = isLoggedIn ? _accountId : null;
        var persistedAuthToken = isLoggedIn ? _authToken : null;
        if (!isLoggedIn && !clearSavedSession)
        {
            var existingConfig = DesktopAppConfig.Load();
            if (!string.IsNullOrWhiteSpace(existingConfig.AuthToken))
            {
                persistedAccountName = string.IsNullOrWhiteSpace(persistedAccountName)
                    ? existingConfig.AccountName
                    : persistedAccountName;
                persistedAccountId = string.IsNullOrWhiteSpace(persistedAccountId)
                    ? existingConfig.AccountId
                    : persistedAccountId;
                persistedAuthToken = existingConfig.AuthToken;
            }
        }

        _overlaySettings = ApplyOverlayFeatureLocks(_overlaySettings);
        var currentOverlaySettings = _overlaySettings.Serialize();
        var currentOverlayLayout = SerializeOverlayLayout();
        var overlaySettings = _isOverlayEditorLayoutDirty && !string.IsNullOrWhiteSpace(_savedOverlaySettingsSnapshot)
            ? _savedOverlaySettingsSnapshot
            : currentOverlaySettings;
        var overlayLayout = _isOverlayEditorLayoutDirty && !string.IsNullOrWhiteSpace(_savedOverlayLayoutSnapshot)
            ? _savedOverlayLayoutSnapshot
            : currentOverlayLayout;
        var activeOverlayPreset = _isOverlayEditorLayoutDirty && !string.IsNullOrWhiteSpace(_savedOverlayPresetSnapshot)
            ? _savedOverlayPresetSnapshot
            : _activeOverlayPreset;
        var fleetStateJson = SerializeFleetState();
        DesktopAppConfig.Save(new DesktopAppConfig(
            _logPath,
            _localPlayer,
            _localPlayerId,
            _avatarPath,
            OverlayHotkeyBox.Text,
            overlayLayout,
            _callsign,
            overlaySettings,
            _language,
            NormalizeNetworkServerUrl(NetworkServerUrlBox.Text),
            NetworkServerKeyBox.Password,
            persistedAccountName,
            persistedAuthToken,
            fleetStateJson,
            _allowEmailNotifications,
            OverlayGlobalHotkeyEnabledCheck.IsChecked == true,
            persistedAccountId,
            _fleetStateCachedAtUtc));
        DesktopAppConfig.SaveOverlaySettings(overlaySettings);
        DesktopAppConfig.SaveOverlayLayout(overlayLayout);
        DesktopAppConfig.SaveActiveOverlayPreset(activeOverlayPreset);
        SaveOverlayPresetManifest();
        DesktopAppConfig.SaveOverlayPresetSettings(activeOverlayPreset, overlaySettings);
        DesktopAppConfig.SaveOverlayPresetLayout(activeOverlayPreset, overlayLayout);
    }

    private string SerializeFleetState()
    {
#if DEBUG
        if (TryGetFleetProfileAcceptancePersistenceState(out var acceptanceState))
        {
            return acceptanceState;
        }
#endif

        var cache = new LocalFleetState(
            _hasFleet,
            _fleetName,
            _fleetCode,
            _fleetChiefCommander,
            _fleetDeputyCommander,
            _fleetDescription,
            _fleetType,
            _fleetJoinPolicy,
            _fleetActiveTime,
            _fleetLogoPath,
            _fleetNoticeTitle,
            _fleetNoticeContent,
            _fleetCurrentTaskTitle,
            _fleetCurrentTaskBrief,
            _fleetCurrentTaskParticipants,
            _fleetCurrentTaskRally,
            _fleetCurrentTaskShip,
            _fleetCurrentTaskEmailCall,
            _fleetCurrentTaskTime,
            _fleetCurrentTaskHistoryKey,
            _fleetCurrentTaskNoticeRevision,
            _fleetTaskHistory.Select(item => new LocalFleetTaskHistory(
                item.Key,
                item.Title,
                item.Brief,
                item.Status,
                item.Participants,
                item.Rally,
                item.RequiredShip,
                item.PublishedAtText)).ToArray(),
            _fleetActionPlans.Select(plan => new LocalFleetActionPlan(
                plan.Id,
                plan.Title,
                plan.Content,
                plan.StartTime,
                plan.NotifyMembers,
                plan.Participants.ToArray(),
                plan.Status,
                plan.CanceledAt,
                plan.CanceledBy,
                plan.CancelReason,
                plan.ReachedAt,
                plan.CompletedAt,
                plan.CompletedBy,
                plan.CompletionMode,
                plan.UpdatedAt,
                plan.Version)).ToArray(),
            _joinedActionPlanIds.ToArray(),
            _allFleetEventLogs.Where(row => !IsPersonalPlanParticipationLog(row)).Select(row => new LocalFleetEventLog(
                row.Id,
                row.Timestamp,
                row.Type,
                SanitizeFleetEventText(row.Title),
                SanitizeFleetEventText(row.Detail),
                row.EndTimestamp,
                row.OccurrenceCount)).ToArray(),
            _fleetMemberPermissions.Values.ToArray(),
            _fleetEmailNotificationsEnabled,
            _fleetJoinedAtUtc,
            _manageProfileSelectedTagIds.ToArray(),
            _fleetBannerPath,
            _fleetBannerSourcePath,
            _selectedFleetSystemIds.ToArray(),
            _fleetLanguage,
            _fleetTimeZoneId,
            _fleetWebsiteUrl,
            _fleetExternalContacts
                .Where(contact => !string.IsNullOrWhiteSpace(contact.Platform) &&
                                  !string.IsNullOrWhiteSpace(contact.Value))
                .Select(contact => new LocalFleetExternalContact(contact.Platform.Trim(), contact.Value.Trim()))
                .ToArray(),
            _fleetActivityWindows
                .Select(window => new LocalFleetActivityWindow(
                    window.Days.ToArray(),
                    window.StartTime,
                    window.EndTime,
                    window.EndsNextDay))
                .ToArray(),
            _fleetActiveDaysDescription,
            _fleetActivityCadence,
            _fleetRecruitmentStatus,
            _fleetRecruitingEnabled,
            _fleetRecruitingTarget,
            "",
            RoleGroups: BuildLocalFleetRoleGroups(),
            FleetPublicListingEnabled: _fleetPublicListingEnabled,
            FleetPublicMemberScaleMode: _fleetPublicMemberScaleMode,
            FleetPublicShipScaleMode: _fleetPublicShipScaleMode,
            FleetPublicProfileEnabled: true,
            FleetPublicShowDescription: _manageShowDescriptionPublic,
            FleetPublicShowTags: _fleetPublicShowTags,
            FleetPublicShowActiveSystems: _fleetPublicShowActiveSystems,
            FleetPublicShowActivityTime: _fleetPublicShowActivityTime,
            FleetPublicShowExternalContacts: _fleetPublicShowExternalContacts,
            FleetNoticePublishedAt: _fleetNoticePublishedAt,
            FleetInviteCodeCreationPolicy: _fleetInviteCodeCreationPolicy,
            FleetInvitationCardPolicy: _fleetInvitationCardPolicy);
        return LocalFleetStateCodec.Serialize(cache);
    }

    private LocalFleetRoleGroup[] BuildLocalFleetRoleGroups()
    {
        return GetFleetRoleGroupDefinitionsForPersistenceForCurrentSave()
            .ToArray();
    }

    private static string[] BuildFleetRoleGroupPermissionIds(FleetRoleGroupRow role)
    {
        return role.HiddenPermissionIds
            .Concat(role.PermissionGroups
                .SelectMany(group => group.Items)
                .Where(item => item.IsAllowed)
                .Select(item => item.Id))
            .Append(FleetPermissionPolicy.AnnouncementPermissionSchemaMarker)
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(id => id, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private IEnumerable<LocalFleetRoleGroup> GetFleetRoleGroupDefinitionsForPersistence()
    {
        EnsureDefaultFleetRoleGroupDefinitions();
        return _fleetRoleGroupDefinitions.Values
            .Where(role => IsPersistableFleetRoleGroupKey(role.Key))
            .OrderBy(role => role.SortOrder)
            .ThenBy(role => role.DisplayName, StringComparer.OrdinalIgnoreCase);
    }

    private IEnumerable<LocalFleetRoleGroup> GetFleetRoleGroupDefinitionsForPersistenceForCurrentSave()
    {
        if (_isFleetRoleGroupsDirty &&
            !_isSavingFleetRoleGroupsDraft &&
            TryGetFleetRoleGroupDraftBaseline(out var baseline))
        {
            return baseline
                .Where(role => IsPersistableFleetRoleGroupKey(role.Key))
                .OrderBy(role => role.SortOrder)
                .ThenBy(role => role.DisplayName, StringComparer.OrdinalIgnoreCase)
                .ToArray();
        }

        return GetFleetRoleGroupDefinitionsForPersistence().ToArray();
    }

    private bool TryGetFleetRoleGroupDraftBaseline(out LocalFleetRoleGroup[] roleGroups)
    {
        roleGroups = [];
        if (string.IsNullOrWhiteSpace(_fleetRoleGroupsDraftBaselineJson))
        {
            return false;
        }

        try
        {
            roleGroups = JsonSerializer.Deserialize<LocalFleetRoleGroup[]>(_fleetRoleGroupsDraftBaselineJson) ?? [];
            return true;
        }
        catch
        {
            roleGroups = [];
            return false;
        }
    }

    private void EnsureDefaultFleetRoleGroupDefinitions()
    {
        if (!_fleetRoleGroupDefinitions.ContainsKey(FleetCommanderRoleGroupKey))
        {
            var row = CreateFleetRoleGroupRow(
                FleetCommanderRoleGroupKey,
                "舰队指挥官",
                "舰队的唯一指挥席位，默认拥有全部权限；可调整公开显示的身份颜色。",
                FleetCommanderDefaultRoleColor,
                0,
                true,
                0,
                [
                    FleetPermissionPolicy.EditFleetProfile,
                    FleetPermissionPolicy.ManageAnnouncements,
                    FleetPermissionPolicy.AnnouncementPermissionSchemaMarker,
                    "members.review",
                    "members.remove",
                    "audit.view"
                ]);
            _fleetRoleGroupDefinitions[row.Key] = ToLocalFleetRoleGroup(row);
        }

        if (!_fleetRoleGroupDefinitions.ContainsKey(FleetDeputyCommanderRoleGroupKey))
        {
            var row = CreateFleetRoleGroupRow(
                FleetDeputyCommanderRoleGroupKey,
                "舰队副指挥官",
                "协助舰队指挥官处理日常管理与调度。",
                FleetDeputyCommanderDefaultRoleColor,
                1,
                true,
                0,
                [
                    FleetPermissionPolicy.EditFleetProfile,
                    FleetPermissionPolicy.ManageAnnouncements,
                    FleetPermissionPolicy.AnnouncementPermissionSchemaMarker,
                    "members.review",
                    "members.remove",
                    "audit.view"
                ]);
            _fleetRoleGroupDefinitions[row.Key] = ToLocalFleetRoleGroup(row);
        }
    }

    private void RememberFleetRoleGroupDefinitionsFromRows()
    {
        var rows = _fleetSystemRoleGroups.Concat(_fleetCustomRoleGroups).ToArray();
        var currentKeys = rows
            .Where(role => IsPersistableFleetRoleGroupKey(role.Key))
            .Select(role => role.Key)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        foreach (var key in _fleetRoleGroupDefinitions.Keys
                     .Where(IsPersistableFleetRoleGroupKey)
                     .Where(key => !currentKeys.Contains(key))
                     .ToArray())
        {
            _fleetRoleGroupDefinitions.Remove(key);
        }

        foreach (var role in rows)
        {
            if (!IsPersistableFleetRoleGroupKey(role.Key))
            {
                continue;
            }

            _fleetRoleGroupDefinitions[role.Key] = ToLocalFleetRoleGroup(role);
        }
    }

    private void LoadFleetRoleGroupDefinitions(IEnumerable<LocalFleetRoleGroup>? roleGroups)
    {
        if (roleGroups is null)
        {
            return;
        }

        _fleetRoleGroupDefinitions.Clear();
        var sourceRoles = roleGroups.ToArray();
        var migrateLegacyAnnouncementPermission = sourceRoles.Length > 0 &&
            !FleetPermissionPolicy.UsesAnnouncementPermissionSchema(sourceRoles.Select(role => role.Permissions));
        foreach (var role in sourceRoles)
        {
            var normalized = NormalizeFleetRoleGroupDefinition(role, migrateLegacyAnnouncementPermission);
            if (normalized is not null)
            {
                _fleetRoleGroupDefinitions[normalized.Key] = normalized;
            }
        }

        EnsureDefaultFleetRoleGroupDefinitions();
    }

    private static LocalFleetRoleGroup? NormalizeFleetRoleGroupDefinition(
        LocalFleetRoleGroup role,
        bool migrateLegacyAnnouncementPermission)
    {
        var key = NormalizeRoleGroupKey(role.Key, role.DisplayName);
        if (!IsPersistableFleetRoleGroupKey(key))
        {
            return null;
        }

        var displayName = string.IsNullOrWhiteSpace(role.DisplayName)
            ? NormalizeRoleDisplayTitle(null, key)
            : role.DisplayName.Trim();
        var isCommander = key.Equals(FleetCommanderRoleGroupKey, StringComparison.OrdinalIgnoreCase);
        var isDeputyCommander = key.Equals(FleetDeputyCommanderRoleGroupKey, StringComparison.OrdinalIgnoreCase);
        var color = string.IsNullOrWhiteSpace(role.Color)
            ? isCommander ? FleetCommanderDefaultRoleColor : FleetDeputyCommanderDefaultRoleColor
            : role.Color.Trim();
        var createdAt = role.CreatedAt == default ? DateTimeOffset.UtcNow : role.CreatedAt;
        var updatedAt = role.UpdatedAt == default ? createdAt : role.UpdatedAt;

        return new LocalFleetRoleGroup(
            key,
            displayName,
            role.Description?.Trim() ?? "",
            color,
            isCommander ? 0 : isDeputyCommander ? 1 : Math.Max(10, role.SortOrder),
            isCommander || isDeputyCommander || role.IsSystem,
            role.IsEnabled,
            Math.Max(0, role.MemberCount),
            FleetPermissionPolicy.NormalizeRolePermissions(
                role.Permissions,
                migrateLegacyAnnouncementPermission),
            createdAt,
            updatedAt);
    }

    private static string[] NormalizeFleetRolePermissionIds(IEnumerable<string>? permissions)
    {
        return FleetPermissionPolicy.NormalizeRolePermissions(
            permissions,
            migrateLegacyProfileManagers: false);
    }

    private static bool IsPersistableFleetRoleGroupKey(string? key)
    {
        return !string.IsNullOrWhiteSpace(key);
    }

    private static LocalFleetRoleGroup ToLocalFleetRoleGroup(FleetRoleGroupRow role)
    {
        return new LocalFleetRoleGroup(
            role.Key,
            role.DisplayName,
            role.Description,
            role.Color,
            role.SortOrder,
            role.IsSystem,
            role.IsEnabled,
            role.MemberCount,
            BuildFleetRoleGroupPermissionIds(role),
            role.CreatedAt,
            role.UpdatedAt);
    }

    private static LocalFleetRoleGroup ToLocalFleetRoleGroup(NetworkFleetRoleGroupSnapshot role)
    {
        return new LocalFleetRoleGroup(
            NormalizeRoleGroupKey(role.Key, role.DisplayName),
            role.DisplayName,
            role.Description,
            role.Color,
            role.SortOrder,
            role.IsSystem,
            role.IsEnabled,
            role.MemberCount,
            role.Permissions,
            role.CreatedAt,
            role.UpdatedAt);
    }

    private string CaptureFleetStateForRollback()
    {
        return SerializeFleetState();
    }

    private string CaptureManageProfileRollbackState()
    {
        EnsureManageProfileDraftBaseline();
        return !string.IsNullOrWhiteSpace(_manageProfileDraftBaselineStateJson)
            ? _manageProfileDraftBaselineStateJson
            : CaptureFleetStateForRollback();
    }

    private void RestoreFleetStateAfterFailedMutation(string fleetStateJson, string message)
    {
        LoadFleetState(fleetStateJson);
        RefreshFleetViewsAfterRestore();
        ForceRefreshFleetEditorControlsAfterRestore();
        SaveCurrentConfig();
        NetworkStatusText.Text = message;
        AppendOutput($"NETWORK | rollback={message}");
    }

    private void RefreshFleetViewsAfterRestore()
    {
        LocalFleetText.Text = _hasFleet ? $"{_fleetName} [{_fleetCode}]" : "未加入舰队";
        RefreshFleetHeader();
        UpdateFleetEntryPanels();
        RefreshFleetOperationalSurfaces();
        RefreshFleetMemberManagement();
        RefreshFleetApplications();
        RenderState();
    }

    private void RefreshFleetOperationalSurfaces()
    {
        SelectFeaturedActionPlan();
        RefreshFleetInfoPanel();
        RefreshTaskManagementPanel();
        RefreshFleetEventActionPlans();
        RefreshFleetEventCommandCenter();
        RefreshFleetCommandDeck();
        RefreshFleetRightContextSidebar();
        RefreshOverlayWindow();
    }

    private void ForceRefreshFleetEditorControlsAfterRestore()
    {
        var wasLoading = _isLoadingSettings;
        _isLoadingSettings = true;
        try
        {
            if (FleetDescriptionEditBox is not null)
            {
                FleetDescriptionEditBox.Text = _fleetDescription;
            }
            RefreshManageFleetBasicProfile(forceTextBoxes: true);

            if (FleetEmailNotificationsEnabledCheck is not null)
            {
                FleetEmailNotificationsEnabledCheck.IsChecked = _fleetEmailNotificationsEnabled;
            }

            if (ActionPlanEditorPanel is { Visibility: Visibility.Visible } &&
                !string.IsNullOrWhiteSpace(_editingActionPlanId))
            {
                var editingPlan = _fleetActionPlans.FirstOrDefault(plan =>
                    plan.Id.Equals(_editingActionPlanId, StringComparison.OrdinalIgnoreCase));
                if (editingPlan is not null)
                {
                    ActionPlanTitleBox.Text = editingPlan.Title;
                    ActionPlanContentBox.Text = editingPlan.Content;
                    ActionPlanDatePicker.SelectedDate = editingPlan.StartTime.Date;
                    ActionPlanTimeBox.Text = editingPlan.StartTime.ToString("HH:mm");
                    ActionPlanNotifyFleetCheck.IsChecked = editingPlan.NotifyMembers;
                    ActionPlanEditorPanel.Title = "编辑稍后行动";
                    PublishActionPlanButton.Content = "保存";
                }
            }
        }
        finally
        {
            _isLoadingSettings = wasLoading;
        }
    }

    private void LoadFleetState(string? fleetStateJson)
    {
        if (string.IsNullOrWhiteSpace(fleetStateJson))
        {
            return;
        }

        try
        {
            var cache = LocalFleetStateCodec.Deserialize(fleetStateJson);
            if (cache is null)
            {
                return;
            }

            _hasFleet = cache.HasFleet;
            _fleetName = string.IsNullOrWhiteSpace(cache.FleetName) ? "No Fleet" : cache.FleetName;
            _fleetCode = string.IsNullOrWhiteSpace(cache.FleetCode) ? "N/A" : cache.FleetCode;
            _fleetChiefCommander = string.IsNullOrWhiteSpace(cache.FleetChiefCommander) ? "Unassigned" : cache.FleetChiefCommander;
            _fleetDeputyCommander = string.IsNullOrWhiteSpace(cache.FleetDeputyCommander) ? "Unassigned" : cache.FleetDeputyCommander;
            _fleetDescription = NormalizeFleetDescription(cache.FleetDescription);
            _fleetType = string.IsNullOrWhiteSpace(cache.FleetType) ? "Combat" : cache.FleetType;
            _fleetJoinPolicy = string.IsNullOrWhiteSpace(cache.FleetJoinPolicy) ? "Open" : cache.FleetJoinPolicy;
            _fleetActiveTime = string.IsNullOrWhiteSpace(cache.FleetActiveTime) ? DefaultFleetActiveTimeText : cache.FleetActiveTime;
            _fleetJoinedAtUtc = _hasFleet
                ? cache.FleetJoinedAt == default
                    ? DateTimeOffset.UtcNow
                    : cache.FleetJoinedAt.ToUniversalTime()
                : DateTimeOffset.MinValue;
            _fleetLogoPath = _hasFleet ? cache.FleetLogoPath : null;
            _fleetBannerPath = _hasFleet ? cache.FleetBannerPath : null;
            _fleetBannerSourcePath = _hasFleet ? cache.FleetBannerSourcePath : null;
            _createFleetLogoPath = null;
            _fleetNoticeTitle = cache.FleetNoticeTitle ?? "";
            _fleetNoticeContent = cache.FleetNoticeContent ?? "";
            _fleetNoticePublishedAt = cache.FleetNoticePublishedAt;
            _fleetCurrentTaskTitle = cache.FleetCurrentTaskTitle ?? "";
            _fleetCurrentTaskBrief = cache.FleetCurrentTaskBrief ?? "";
            _fleetCurrentTaskParticipants = NormalizeFleetTaskParticipants(cache.FleetCurrentTaskParticipants);
            _fleetCurrentTaskRally = cache.FleetCurrentTaskRally ?? "";
            _fleetCurrentTaskShip = cache.FleetCurrentTaskShip ?? "";
            _fleetCurrentTaskEmailCall = cache.FleetCurrentTaskEmailCall;
            _fleetEmailNotificationsEnabled = cache.FleetEmailNotificationsEnabled;
            _fleetCurrentTaskTime = cache.FleetCurrentTaskTime;
            _fleetCurrentTaskHistoryKey = cache.FleetCurrentTaskHistoryKey ?? "";
            _fleetCurrentTaskNoticeRevision = cache.FleetCurrentTaskNoticeRevision;

            _fleetTaskHistory.Clear();
            foreach (var item in cache.TaskHistory ?? [])
            {
                _fleetTaskHistory.Add(new FleetTaskHistoryRow(
                    item.Key,
                    item.Title,
                    item.Brief,
                    item.Status,
                    item.Participants,
                    item.Rally,
                    item.RequiredShip,
                    item.PublishedAtText));
            }

            _fleetActionPlans.Clear();
            foreach (var plan in cache.ActionPlans ?? [])
            {
                var row = new FleetActionPlanRow(
                    plan.Id,
                    plan.Title,
                    plan.Content,
                    plan.StartTime,
                    plan.NotifyMembers,
                    plan.Status,
                    plan.CanceledAt,
                    plan.CanceledBy,
                    plan.CancelReason,
                    plan.ReachedAt,
                    plan.CompletedAt,
                    plan.CompletedBy,
                    plan.CompletionMode,
                    plan.UpdatedAt,
                    plan.Version);
                foreach (var participant in plan.Participants ?? [])
                {
                    row.Participants.Add(participant);
                }

                row.RefreshParticipantSummary();
                _fleetActionPlans.Add(row);
            }

            _joinedActionPlanIds.Clear();
            foreach (var id in cache.JoinedActionPlanIds ?? [])
            {
                if (!string.IsNullOrWhiteSpace(id))
                {
                    _joinedActionPlanIds.Add(id);
                }
            }

            _allFleetEventLogs.Clear();
            foreach (var item in cache.EventLog ?? [])
            {
                if (IsPersonalPlanParticipationLog(item.Type, item.Title))
                {
                    continue;
                }

                _allFleetEventLogs.Add(new FleetEventLogRow(
                    item.Id,
                    item.Timestamp,
                    item.Type,
                    SanitizeFleetEventText(item.Title),
                    SanitizeFleetEventText(item.Detail),
                    EndTimestamp: item.EndTimestamp,
                    OccurrenceCount: Math.Max(1, item.OccurrenceCount)));
            }

            _fleetMemberPermissions.Clear();
            foreach (var item in cache.MemberPermissions ?? [])
            {
                if (!string.IsNullOrWhiteSpace(item.GameName))
                {
                    _fleetMemberPermissions[item.GameName.Trim()] = item;
                }
            }

            LoadFleetRoleGroupDefinitions(cache.RoleGroups);

            if (cache.FleetTagIds is { Length: > 0 })
            {
                SetManageProfileSelectedTagIds(cache.FleetTagIds);
            }

            SetSelectedFleetSystemIds(cache.FleetSystemIds ?? []);
            _fleetLanguage = string.IsNullOrWhiteSpace(cache.FleetLanguage) ? "zh-CN" : cache.FleetLanguage.Trim();
            _fleetTimeZoneId = string.IsNullOrWhiteSpace(cache.FleetTimeZoneId) ? "China Standard Time" : cache.FleetTimeZoneId.Trim();
            _fleetWebsiteUrl = NormalizeOptionalField(cache.FleetWebsiteUrl);
            SetFleetExternalContacts(cache.FleetExternalContacts ?? []);
            LoadFleetActivityWindows(
                cache.FleetActivityWindows,
                cache.FleetActiveDaysDescription,
                cache.FleetActiveTime);
            _fleetActivityCadence = NormalizeManageProfileOption(cache.FleetActivityCadence, "休闲");
            _fleetRecruitmentStatus = NormalizeManageProfileOption(cache.FleetRecruitmentStatus, "开放招募");
            _fleetRecruitingEnabled = cache.FleetRecruitingEnabled;
            _fleetRecruitingTarget = NormalizeFleetRecruitingTarget(cache.FleetRecruitingTarget);
            _fleetInviteCodeCreationPolicy = FleetInvitationAccessPolicy.Normalize(cache.FleetInviteCodeCreationPolicy);
            _fleetInvitationCardPolicy = FleetInvitationAccessPolicy.Normalize(cache.FleetInvitationCardPolicy);
            _fleetPublicListingEnabled = cache.FleetPublicListingEnabled;
            _fleetPublicMemberScaleMode = NormalizeFleetPublicMemberScaleMode(cache.FleetPublicMemberScaleMode);
            _fleetPublicShipScaleMode = NormalizeFleetPublicShipScaleMode(cache.FleetPublicShipScaleMode);
            _manageAllowPublicProfileView = true;
            _manageShowDescriptionPublic = cache.FleetPublicShowDescription;
            _fleetPublicShowTags = cache.FleetPublicShowTags;
            _fleetPublicShowActiveSystems = cache.FleetPublicShowActiveSystems;
            _fleetPublicShowActivityTime = cache.FleetPublicShowActivityTime;
            _fleetPublicShowExternalContacts = cache.FleetPublicShowExternalContacts;
            ApplyLoadedExternalContactPublicationState(_fleetPublicShowExternalContacts);

            ApplyFleetEventLogFilter();

            LocalFleetText.Text = _hasFleet ? $"{_fleetName} [{_fleetCode}]" : "未加入舰队";
        }
        catch
        {
            // ignore invalid cache and continue with current in-memory defaults
        }
    }
}
