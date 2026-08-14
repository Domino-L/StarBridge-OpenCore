using System.Diagnostics;
using System.IO;
using System.Net.Http.Json;
using System.Text;
using System.Windows;
using StarBridge.Core.Friends;
using StarBridge.Core.Presence;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private bool _dualAxisPrivacySavePending;

    private string? CurrentDualAxisPrivacyAccountIdentity =>
        string.IsNullOrWhiteSpace(_authToken)
            ? null
            : !string.IsNullOrWhiteSpace(_accountId)
                ? _accountId
                : _accountName;

    private void ReloadDualAxisPrivacySettings()
    {
        _dualAxisPrivacySettings = DualAxisPrivacyTakeover.WithoutRoomGroupReferences(
            _dualAxisPrivacySettingsStore.LoadOrMigrate(
                CurrentDualAxisPrivacyAccountIdentity,
                _syncPrivacySettings,
                _playerEventSharingSettings,
                SyncPrivacySettings.HasStoredSettings));
    }

    private void InitializeDualAxisPrivacyEditor()
    {
        _privateVisibilityGroupClient = new PrivateVisibilityGroupClient(_relayClient);
        _privateVisibilityGroupLoader = new PrivateVisibilityGroupDirectoryLoader(
            _accountSessionCoordinator,
            cancellationToken => _privateVisibilityGroupClient.LoadAsync(cancellationToken));
        _privateVisibilityGroupMutationGate = new PrivateVisibilityGroupMutationGate(
            _accountSessionCoordinator);
        DualAxisPrivacyEditor.SetGroups(_privateVisibilityGroups);
        DualAxisPrivacyEditor.SettingsChanged += DualAxisPrivacyEditor_SettingsChanged;
        DualAxisPrivacyEditor.GameIdVisibilityChanged += DualAxisPrivacyEditor_GameIdVisibilityChanged;
        DualAxisPrivacyEditor.CreateGroupRequested += (_, _) => OpenVisibilityGroupEditor(null);
        DualAxisPrivacyEditor.EditGroupRequested += (_, group) => OpenVisibilityGroupEditor(group);
    }

    private async void DualAxisPrivacyEditor_GameIdVisibilityChanged(object? sender, EventArgs e)
    {
        if (_isLoadingSettings || _isApplyingDualAxisPrivacyEditor)
        {
            return;
        }

        await SaveGameIdVisibilityAsync();
    }

    private async void DualAxisPrivacyEditor_SettingsChanged(object? sender, EventArgs e)
    {
        if (_isLoadingSettings || _isApplyingDualAxisPrivacyEditor)
        {
            return;
        }

        await CommitDualAxisPrivacyEditorAsync();
    }

    private void ApplyDualAxisPrivacySettingsToEditor()
    {
        if (DualAxisPrivacyEditor is null)
        {
            return;
        }

        _isApplyingDualAxisPrivacyEditor = true;
        try
        {
            DualAxisPrivacyEditor.Apply(
                _dualAxisPrivacySettings,
                BuildPrivacyAudienceProjection());
            DualAxisPrivacyEditor.ApplyGameIdVisibility(_gameIdVisibilityPreference);
            RefreshPrivateVisibilityGroupSelections();
        }
        finally
        {
            _isApplyingDualAxisPrivacyEditor = false;
        }
    }

    private void ApplyGameIdVisibilityToEditor()
    {
        if (DualAxisPrivacyEditor is null)
        {
            return;
        }

        _isApplyingDualAxisPrivacyEditor = true;
        try
        {
            DualAxisPrivacyEditor.ApplyGameIdVisibility(_gameIdVisibilityPreference);
        }
        finally
        {
            _isApplyingDualAxisPrivacyEditor = false;
        }
    }

    private async Task SaveGameIdVisibilityAsync()
    {
        if (_isSavingGameIdVisibility)
        {
            _gameIdVisibilitySavePending = true;
            return;
        }

        if (!_gameIdVisibilityPreference.CanConfigure)
        {
            ApplyGameIdVisibilityToEditor();
            return;
        }

        _isSavingGameIdVisibility = true;
        try
        {
            do
            {
                _gameIdVisibilitySavePending = false;
                if (!CanSynchronizeUserData)
                {
                    DualAxisPrivacyEditor.SetGroupStatus("请先完成登录和身份验证，再保存游戏 ID 展示位置。");
                    ApplyGameIdVisibilityToEditor();
                    return;
                }

                var requestedLocations = DualAxisPrivacyEditor.ReadGameIdVisibility();
                var session = _accountSessionCoordinator.Capture();
                try
                {
                    using var response = await PostNetworkJsonAsync(
                        "api/auth/profile",
                        new ProfileUpdateRequest(
                            _callsign,
                            _allowEmailNotifications,
                            GameIdVisibilityLocations: requestedLocations));
                    if (!_accountSessionCoordinator.IsCurrent(session))
                    {
                        return;
                    }

                    if (HandleAuthorizationFailure(response.StatusCode, "游戏 ID 展示设置", silent: true) ||
                        !response.IsSuccessStatusCode)
                    {
                        DualAxisPrivacyEditor.SetGroupStatus("游戏 ID 展示设置保存失败，请稍后重试。");
                        ApplyGameIdVisibilityToEditor();
                        return;
                    }

                    var auth = await response.Content.ReadFromJsonAsync<AuthResponse>();
                    if (!_accountSessionCoordinator.IsCurrent(session))
                    {
                        return;
                    }

                    if (auth is null)
                    {
                        DualAxisPrivacyEditor.SetGroupStatus("服务器没有返回新的游戏 ID 展示设置。");
                        ApplyGameIdVisibilityToEditor();
                        return;
                    }

                    _gameIdVisibilityPreference = GameIdVisibilityPolicy.Normalize(
                        auth.Callsign ?? _callsign,
                        auth.GameName ?? _localPlayer,
                        auth.GameIdVisibilityLocations);
                    ApplyGameIdVisibilityToEditor();
                    DualAxisPrivacyEditor.SetGroupStatus("游戏 ID 展示位置已保存。");
                }
                catch (Exception exception)
                {
                    if (!_accountSessionCoordinator.IsCurrent(session))
                    {
                        return;
                    }

                    DualAxisPrivacyEditor.SetGroupStatus($"游戏 ID 展示设置保存失败：{exception.Message}");
                    ApplyGameIdVisibilityToEditor();
                    return;
                }
            }
            while (_gameIdVisibilitySavePending);
        }
        finally
        {
            _isSavingGameIdVisibility = false;
        }
    }

    private PlayerSharedStateAudienceProjection BuildPrivacyAudienceProjection()
    {
        var normalized = _dualAxisPrivacySettings.Normalize();
        var publication = normalized.ToPublicationPolicy(
            _syncPrivacySettings.FriendsCanViewPresence,
            normalized.Fleet.Fields.HasFlag(PlayerSharedStateFields.PersonalHangar));
        return PlayerSharedStateAudienceProjectionPolicy.Project(
            publication,
            hasSelectedFleetGroups: normalized.Fleet.VisibilityGroupIds is { Length: > 0 },
            hasSelectedRoomGroups: false);
    }

    private async Task CommitDualAxisPrivacyEditorAsync()
    {
        if (_isSavingDualAxisPrivacy)
        {
            _dualAxisPrivacySavePending = true;
            return;
        }

        _isSavingDualAxisPrivacy = true;
        try
        {
            do
            {
                _dualAxisPrivacySavePending = false;
                var draft = DualAxisPrivacyEditor.Read(_dualAxisPrivacySettings);
                if (!CanSynchronizeUserData)
                {
                    DualAxisPrivacyEditor.SetGroupStatus("请先完成登录和身份验证，再保存新的隐私设置。");
                    ApplyDualAxisPrivacySettingsToEditor();
                    return;
                }

                var session = _accountSessionCoordinator.Capture();

                try
                {
                    draft = await MaterializePendingVisibilityGroupsAsync(draft);
                    if (draft is null || !_accountSessionCoordinator.IsCurrent(session))
                    {
                        return;
                    }
                }
                catch (Exception exception)
                {
                    DualAxisPrivacyEditor.SetGroupStatus($"无法完成分组迁移：{exception.Message}");
                    ApplyDualAxisPrivacySettingsToEditor();
                    return;
                }

                _dualAxisPrivacySettings = (draft with { TracksLegacySettings = false }).Normalize();
                MirrorLegacyPrivacySettingsFromDualAxis(_syncPrivacySettings.FriendsCanViewPresence);
                PersistDualAxisPrivacySettings();
                SyncPrivacySettings.Save(_syncPrivacySettings);
                ApplySyncPrivacySettingsToControls();
                ApplyNetworkSyncMasterState();
                UpdateShipDatabaseSummary();
                NetworkStatusText.Text = "隐私设置已保存";
                DualAxisPrivacyEditor.SetGroupStatus("已保存；舰队成员与同房间的人会按各自设置查看。");

                await RefreshPrivateVisibilityGroupsAsync();
                if (!_accountSessionCoordinator.IsCurrent(session))
                {
                    return;
                }
                if (IsLoggedIn)
                {
                    await PushLocalSnapshotAsync(
                        silent: true,
                        pushFleetDirectory: false,
                        forcePrivacyClear: !_dualAxisPrivacySettings.PublicationEnabled);
                }
            }
            while (_dualAxisPrivacySavePending);
        }
        finally
        {
            _isSavingDualAxisPrivacy = false;
        }
    }

    private async Task<DualAxisPrivacySettings?> MaterializePendingVisibilityGroupsAsync(
        DualAxisPrivacySettings settings)
    {
        if (settings.PendingGroupMigrations.Length == 0)
        {
            return settings;
        }

        if (_privateVisibilityGroupClient is null || _privateVisibilityGroupMutationGate is null)
        {
            throw new InvalidOperationException("可见性分组服务尚未就绪。");
        }

        return await _privateVisibilityGroupMutationGate.RunLatestAsync(
            async cancellationToken =>
            {
                var current = settings;
                foreach (var pending in settings.PendingGroupMigrations)
                {
                    var existing = _privateVisibilityGroups.FirstOrDefault(group =>
                        !group.IsPendingMigration &&
                        group.Name.Equals(pending.Name, StringComparison.Ordinal) &&
                        group.MemberAccountIds.ToHashSet(StringComparer.OrdinalIgnoreCase)
                            .SetEquals(pending.MemberAccountIds));
                    var groupId = existing?.GroupId;
                    if (string.IsNullOrWhiteSpace(groupId))
                    {
                        var saved = await _privateVisibilityGroupClient.SaveAsync(
                            null,
                            pending.Name,
                            pending.MemberAccountIds,
                            cancellationToken);
                        groupId = saved.GroupId;
                    }

                    current = DualAxisPrivacyTakeover.ReplaceGroupReference(
                        current,
                        pending.LocalReferenceId,
                        groupId);
                }

                return current;
            });
    }

    private void MirrorLegacyPrivacySettingsFromDualAxis(bool friendsCanViewPresence)
    {
        var normalized = _dualAxisPrivacySettings.Normalize();
        var fields = normalized.Fleet.Fields | normalized.Room.Fields;
        var selectedGroupIds = (normalized.Fleet.VisibilityGroupIds ?? [])
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var specifiedMembers = PlayerSharedStateVisibility.NormalizeSpecifiedMemberAccountIds(
            _privateVisibilityGroups
                .Where(group => !group.IsPendingMigration && selectedGroupIds.Contains(group.GroupId))
                .SelectMany(group => group.MemberAccountIds));
        var legacyScope = normalized.Fleet.AllMembersCanView
            ? SyncPrivacyVisibilityScope.Fleet
            : normalized.Fleet.AdministratorsCanView && specifiedMembers.Length > 0
                ? SyncPrivacyVisibilityScope.SpecifiedMembers
                : normalized.Fleet.AdministratorsCanView
                    ? SyncPrivacyVisibilityScope.AdminOnly
                    : SyncPrivacyVisibilityScope.Private;

        _syncPrivacySettings = ApplyFleetActionSettingsLock((_syncPrivacySettings with
        {
            SyncEnabled = normalized.PublicationEnabled,
            SyncOnlineStatus = fields.HasFlag(PlayerSharedStateFields.Presence),
            SyncShipStatus = fields.HasFlag(PlayerSharedStateFields.Ship),
            SyncLocationStatus = fields.HasFlag(PlayerSharedStateFields.Location),
            SyncServerInfo = fields.HasFlag(PlayerSharedStateFields.Server),
            PersonalHangarVisible = normalized.Fleet.Fields.HasFlag(PlayerSharedStateFields.PersonalHangar),
            VisibilityScope = legacyScope,
            SpecifiedMemberAccountIds = legacyScope == SyncPrivacyVisibilityScope.SpecifiedMembers
                ? specifiedMembers
                : [],
            FriendsCanViewPresence = friendsCanViewPresence,
            SyncConsentCompleted = true,
            SyncConsentVersion = CurrentSyncConsentVersion
        }).NormalizeVisibilityScope());
    }

    private void PersistDualAxisPrivacySettings()
    {
        try
        {
            _dualAxisPrivacySettingsStore.Save(
                CurrentDualAxisPrivacyAccountIdentity,
                _dualAxisPrivacySettings);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            DualAxisPrivacyEditor.SetGroupStatus($"本机无法保存隐私设置：{exception.Message}");
        }
    }

    private async Task RefreshPrivateVisibilityGroupsAsync()
    {
        if (DualAxisPrivacyEditor is null)
        {
            return;
        }

        PrivateVisibilityGroupContract[] remoteGroups = [];
        if (CanSynchronizeUserData && _privateVisibilityGroupLoader is not null)
        {
            try
            {
                DualAxisPrivacyEditor.SetGroupStatus("正在读取私有分组…");
                var loaded = await _privateVisibilityGroupLoader.LoadLatestAsync();
                if (loaded is null)
                {
                    return;
                }

                remoteGroups = loaded;
            }
            catch (Exception exception)
            {
                DualAxisPrivacyEditor.SetGroupStatus($"分组读取失败：{exception.Message}");
                return;
            }
        }

        var fleetIds = (_dualAxisPrivacySettings.Fleet.VisibilityGroupIds ?? [])
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        _privateVisibilityGroups.Clear();
        foreach (var group in remoteGroups.OrderBy(group => group.Name, StringComparer.CurrentCultureIgnoreCase))
        {
            _privateVisibilityGroups.Add(new PrivateVisibilityGroupRow
            {
                GroupId = group.GroupId,
                Name = group.Name,
                MemberAccountIds = group.MemberAccountIds,
                FleetSelected = fleetIds.Contains(group.GroupId)
            });
        }

        foreach (var pending in _dualAxisPrivacySettings.PendingGroupMigrations)
        {
            _privateVisibilityGroups.Add(new PrivateVisibilityGroupRow
            {
                GroupId = pending.LocalReferenceId,
                Name = pending.Name,
                MemberAccountIds = pending.MemberAccountIds,
                IsPendingMigration = true,
                FleetSelected = fleetIds.Contains(pending.LocalReferenceId)
            });
        }

        DualAxisPrivacyEditor.SetGroups(_privateVisibilityGroups);
        DualAxisPrivacyEditor.SetGroupStatus(!CanSynchronizeUserData
            ? "登录并完成身份验证后可管理私有分组。"
            : _dualAxisPrivacySettings.PendingGroupMigrations.Length > 0
                ? "旧“指定成员”将在首次保存时等价转换为私有分组。"
                : $"{_privateVisibilityGroups.Count} / {DualAxisPrivacySettings.MaxVisibilityGroups} 个私有分组");
    }

    private void RefreshPrivateVisibilityGroupSelections()
    {
        var fleetIds = (_dualAxisPrivacySettings.Fleet.VisibilityGroupIds ?? [])
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var group in _privateVisibilityGroups)
        {
            group.FleetSelected = fleetIds.Contains(group.GroupId);
        }

        DualAxisPrivacyEditor.SetGroups(_privateVisibilityGroups);
    }

    private void OpenVisibilityGroupEditor(PrivateVisibilityGroupRow? group)
    {
        if (!CanSynchronizeUserData)
        {
            DualAxisPrivacyEditor.SetGroupStatus("请先完成登录和身份验证，再管理私有分组。");
            return;
        }

        if (group is null && _privateVisibilityGroups.Count >= DualAxisPrivacySettings.MaxVisibilityGroups)
        {
            DualAxisPrivacyEditor.SetGroupStatus("最多可以创建 12 个私有分组。");
            return;
        }

        _editingVisibilityGroupId = group is { IsPendingMigration: false } ? group.GroupId : null;
        _editingVisibilityGroupLocalReferenceId = group is { IsPendingMigration: true } ? group.GroupId : null;
        VisibilityGroupNameBox.Text = group?.Name ?? "";
        VisibilityGroupDeleteButton.Visibility = group is null ? Visibility.Collapsed : Visibility.Visible;
        PopulateVisibilityGroupMemberCandidates(group?.MemberAccountIds ?? []);
        SpecifiedVisibilityMembersOverlay.Title = group is null ? "新建私有分组" : "编辑私有分组";
        SpecifiedVisibilityMembersOverlay.Description =
            "选择这组观看者。分组只属于你，不改变舰队角色、房间准入或任何管理权限。";
        RefreshSpecifiedVisibilitySelectionText();
        SpecifiedVisibilityMembersOverlay.Show();
        VisibilityGroupNameBox.Focus();
    }

    private void PopulateVisibilityGroupMemberCandidates(IEnumerable<string> selectedAccountIds)
    {
        var selected = selectedAccountIds.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var candidates = new Dictionary<string, SpecifiedVisibilityMemberRow>(StringComparer.OrdinalIgnoreCase);

        void Add(string? accountId, string? callsign, string? gameId, string? avatar)
        {
            var id = accountId?.Trim();
            if (string.IsNullOrWhiteSpace(id) ||
                id.Equals(_accountId, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            var normalizedGameId = string.IsNullOrWhiteSpace(gameId) ? id : gameId.Trim();
            var normalizedCallsign = string.IsNullOrWhiteSpace(callsign) ? normalizedGameId : callsign.Trim();
            candidates.TryAdd(id, new SpecifiedVisibilityMemberRow
            {
                AccountId = id,
                Callsign = normalizedCallsign,
                GameId = normalizedGameId,
                AvatarPath = avatar,
                IsSelected = selected.Contains(id)
            });
        }

        foreach (var player in _players.Where(player => !player.IsSelf))
        {
            Add(player.AccountId, player.Callsign, player.Name, player.AvatarPath);
        }

        foreach (var friend in _friendCenterRows.Where(row =>
                     row.User.RelationshipState.Equals(
                         FriendRelationshipStates.Friend,
                         StringComparison.OrdinalIgnoreCase)))
        {
            Add(friend.AccountId, friend.Callsign, friend.GameId, friend.AvatarSource);
        }

        if (_currentPartyRoom is not null)
        {
            foreach (var member in _currentPartyRoom.Members)
            {
                Add(member.AccountId, member.Callsign, member.GameId, member.AvatarImageData);
            }
        }

        foreach (var accountId in selected)
        {
            Add(accountId, accountId, accountId, null);
        }

        _isUpdatingSpecifiedMemberSelection = true;
        try
        {
            _specifiedVisibilityMembers.Clear();
            foreach (var candidate in candidates.Values
                         .OrderBy(row => row.Callsign, StringComparer.CurrentCultureIgnoreCase))
            {
                _specifiedVisibilityMembers.Add(candidate);
            }
        }
        finally
        {
            _isUpdatingSpecifiedMemberSelection = false;
        }

        SpecifiedVisibilityMembersEmptyText.Visibility = _specifiedVisibilityMembers.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private async void VisibilityGroupSaveButton_Click(object sender, RoutedEventArgs e)
    {
        var name = string.Concat(VisibilityGroupNameBox.Text.Trim()
            .EnumerateRunes()
            .Take(DualAxisPrivacySettings.MaxVisibilityGroupNameLength)
            .Select(rune => rune.ToString()));
        if (name.Length == 0)
        {
            DualAxisPrivacyEditor.SetGroupStatus("请填写分组名称。");
            VisibilityGroupNameBox.Focus();
            return;
        }

        if (_privateVisibilityGroupClient is null ||
            _privateVisibilityGroupMutationGate is null ||
            !CanSynchronizeUserData)
        {
            DualAxisPrivacyEditor.SetGroupStatus("当前无法保存私有分组。");
            return;
        }

        var members = PlayerSharedStateVisibility.NormalizeSpecifiedMemberAccountIds(
            _specifiedVisibilityMembers
                .Where(member => member.IsSelected)
                .Select(member => member.AccountId));
        var session = _accountSessionCoordinator.Capture();
        try
        {
            var saved = await _privateVisibilityGroupMutationGate.RunLatestAsync(
                cancellationToken => _privateVisibilityGroupClient.SaveAsync(
                    _editingVisibilityGroupId,
                    name,
                    members,
                    cancellationToken));
            if (saved is null || !_accountSessionCoordinator.IsCurrent(session))
            {
                return;
            }
            if (!string.IsNullOrWhiteSpace(_editingVisibilityGroupLocalReferenceId))
            {
                _dualAxisPrivacySettings = DualAxisPrivacyTakeover.ReplaceGroupReference(
                    _dualAxisPrivacySettings,
                    _editingVisibilityGroupLocalReferenceId,
                    saved.GroupId);
                PersistDualAxisPrivacySettings();
            }

            SpecifiedVisibilityMembersOverlay.Hide();
            await RefreshPrivateVisibilityGroupsAsync();
            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return;
            }
            await CommitDualAxisPrivacyEditorAsync();
        }
        catch (Exception exception)
        {
            DualAxisPrivacyEditor.SetGroupStatus($"分组保存失败：{exception.Message}");
        }
    }

    private async void VisibilityGroupDeleteButton_Click(object sender, RoutedEventArgs e)
    {
        var groupId = _editingVisibilityGroupId ?? _editingVisibilityGroupLocalReferenceId;
        if (string.IsNullOrWhiteSpace(groupId))
        {
            return;
        }

        var confirmed = await ShowAppConfirmationAsync(
            "删除私有分组？",
            $"将删除“{VisibilityGroupNameBox.Text.Trim()}”。",
            "舰队成员与同房间的人对该分组的引用会立即失效，不会保留展开后的成员名单。",
            "删除分组",
            "取消",
            footerText: "分组只影响你发布的共享状态，不影响角色或权限。");
        if (!confirmed)
        {
            return;
        }

        try
        {
            var session = _accountSessionCoordinator.Capture();
            if (!groupId.StartsWith("pending:", StringComparison.OrdinalIgnoreCase))
            {
                if (_privateVisibilityGroupClient is null || _privateVisibilityGroupMutationGate is null)
                {
                    throw new InvalidOperationException("可见性分组服务尚未就绪。");
                }

                var deletedGroupId = await _privateVisibilityGroupMutationGate.RunLatestAsync(
                    async cancellationToken =>
                    {
                        await _privateVisibilityGroupClient.DeleteAsync(groupId, cancellationToken);
                        return groupId;
                    });
                if (deletedGroupId is null || !_accountSessionCoordinator.IsCurrent(session))
                {
                    return;
                }
            }

            _dualAxisPrivacySettings = DualAxisPrivacyTakeover.RemoveGroupReference(
                _dualAxisPrivacySettings,
                groupId);
            PersistDualAxisPrivacySettings();
            SpecifiedVisibilityMembersOverlay.Hide();
            await RefreshPrivateVisibilityGroupsAsync();
            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return;
            }
            await CommitDualAxisPrivacyEditorAsync();
        }
        catch (Exception exception)
        {
            DualAxisPrivacyEditor.SetGroupStatus($"分组删除失败：{exception.Message}");
        }
    }

    private void VisibilityGroupCancelButton_Click(object sender, RoutedEventArgs e)
    {
        SpecifiedVisibilityMembersOverlay.Hide();
    }

    private void SaveSyncPrivacySettingsAndRefreshDualAxis()
    {
        SyncPrivacySettings.Save(_syncPrivacySettings);
        RefreshTrackedDualAxisPrivacyMigration();
    }

    private void SavePlayerEventSharingSettingsAndRefreshDualAxis()
    {
        PlayerEventSharingSettingsStore.Save(_playerEventSharingSettings);
        RefreshTrackedDualAxisPrivacyMigration();
    }

    private void RefreshTrackedDualAxisPrivacyMigration()
    {
        if (!_dualAxisPrivacySettings.TracksLegacySettings)
        {
            return;
        }

        _dualAxisPrivacySettings = DualAxisPrivacySettings.Migrate(
            _syncPrivacySettings,
            _playerEventSharingSettings);
        try
        {
            _dualAxisPrivacySettingsStore.Save(
                CurrentDualAxisPrivacyAccountIdentity,
                _dualAxisPrivacySettings);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            Debug.WriteLine($"Unable to persist dormant dual-axis privacy settings: {exception.Message}");
        }
    }
}
