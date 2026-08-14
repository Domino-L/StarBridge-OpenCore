using StarBridge.Core.Events;
using StarBridge.Core.FleetChat;
using StarBridge.Core.Fleets;
using StarBridge.Core.State;
using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Windows;
using System.Windows.Controls;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private async void RefreshFleetDirectory_Click(object sender, RoutedEventArgs e)
    {
        await PushLocalSnapshotAsync(silent: true, pushFleetDirectory: false);
        await PullNetworkFleetsAsync();
    }

    private async void JoinNetworkFleet_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("加入舰队需要先登录星海舰桥账号。"))
        {
            return;
        }

        if (!EnsureIdentityInitialized("加入舰队"))
        {
            return;
        }

        if ((sender as FrameworkElement)?.Tag is not NetworkFleetCard card)
        {
            return;
        }

        if (IsSameFleet(card.Snapshot.Name) || IsSameFleet(card.Snapshot.Code))
        {
            NetworkStatusText.Text = "你已经在该舰队中。";
            await ShowFleetDirectoryActionNoticeAsync(
                "你已在该舰队中",
                $"当前账号已经是“{card.Name}”的成员。",
                "无需再次加入，可以前往“我的舰队”查看成员、聊天和舰船。");
            return;
        }

        if (!card.CanJoin)
        {
            NetworkStatusText.Text = "当前舰队暂不支持从目录直接加入。";
            await ShowFleetDirectoryActionNoticeAsync(
                "暂时无法加入",
                $"“{card.Name}”当前不支持从舰队目录直接加入。",
                "请查看舰队的加入方式；仅限邀请的舰队需要使用有效邀请码。");
            return;
        }

        if (card.HasPendingApplication)
        {
            await WithdrawFleetApplicationAsync(card);
            return;
        }

        if (_hasFleet)
        {
            var isCommander = IsCurrentUserFleetCommander();
            var message = isCommander
                ? "舰队指挥官不能直接切换舰队。"
                : $"需要先离开当前舰队“{_fleetName}”。";
            var detail = isCommander
                ? "请先在舰队管理中转移指挥权或解散当前舰队，再返回这里加入其他舰队。"
                : $"为避免成员身份和内部数据发生冲突，请先在“我的舰队”中退出，再加入“{card.Name}”。";
            NetworkStatusText.Text = message;
            await ShowFleetDirectoryActionNoticeAsync(
                "无法切换舰队",
                message,
                detail);
            return;
        }

        var fleetCode = card.Snapshot.Code.Trim();
        if (!_findFleetJoinInProgressCodes.Add(fleetCode))
        {
            NetworkStatusText.Text = "正在处理这支舰队的加入操作，请稍候。";
            await ShowFleetDirectoryActionNoticeAsync(
                "操作正在进行",
                $"正在处理“{card.Name}”的加入操作。",
                "请等待当前请求完成，不需要重复点击。");
            return;
        }

        try
        {

        if (card.RequiresApplication)
        {
            if (!await ChooseSyncScopeForFleetEntryAsync(card.Name, isApplication: true))
            {
                return;
            }

            try
            {
                var response = await PostNetworkJsonAsync(
                    "api/fleets/apply",
                    new FleetJoinApplicationRequest(card.Snapshot.Code, ""));
                if (!response.IsSuccessStatusCode)
                {
                    var error = await ReadResponseErrorAsync(response);
                    NetworkStatusText.Text = $"申请失败：{error}";
                    await ShowFleetDirectoryActionNoticeAsync(
                        "申请未提交",
                        $"未能向“{card.Name}”提交加入申请。",
                        error);
                    return;
                }

                var snapshot = await response.Content.ReadFromJsonAsync<NetworkFleetSnapshot>();
                _pendingFleetApplicationCodes.Add(card.Snapshot.Code);
                if (snapshot is not null)
                {
                    var existingIndex = _allNetworkFleets.IndexOf(card);
                    if (existingIndex >= 0)
                    {
                        _allNetworkFleets[existingIndex] = NetworkFleetCard.FromSnapshot(
                            snapshot,
                            _fleetName,
                            _fleetCode,
                            _hasFleet,
                            _pendingFleetApplicationCodes);
                    }
                }

                await PullNetworkFleetsAsync(silent: true);
                NetworkStatusText.Text = $"已提交加入申请：{card.Name}";
                await ShowFleetDirectoryActionNoticeAsync(
                    "申请已提交",
                    $"已向“{card.Name}”提交加入申请。",
                    "舰队审核后，申请状态会在目录中自动更新。");
            }
            catch (Exception ex)
            {
                var error = UserFacingError.Describe(ex, "加入申请未提交，请稍后重试。");
                NetworkStatusText.Text = error;
                await ShowFleetDirectoryActionNoticeAsync(
                    "申请未提交",
                    $"未能向“{card.Name}”提交加入申请。",
                    error);
            }

            return;
        }

        if (!await ChooseSyncScopeForFleetEntryAsync(card.Name, isApplication: false))
        {
            return;
        }

        try
        {
            var response = await PostNetworkJsonAsync(
                "api/fleets/apply",
                new FleetJoinApplicationRequest(card.Snapshot.Code, ""));
            if (!response.IsSuccessStatusCode)
            {
                var error = await ReadResponseErrorAsync(response);
                NetworkStatusText.Text = $"加入失败：{error}";
                await ShowFleetDirectoryActionNoticeAsync(
                    "加入舰队失败",
                    $"暂时无法加入“{card.Name}”。",
                    error);
                return;
            }

            var snapshot = await response.Content.ReadFromJsonAsync<NetworkFleetSnapshot>() ?? card.Snapshot;
            JoinNetworkFleet(snapshot);
            await PushLocalSnapshotAsync(silent: true, pushFleetDirectory: false);
            await PullNetworkFleetsAsync(silent: true);
            await PullNetworkSnapshotsAsync(silent: true);
            NetworkStatusText.Text = $"已加入舰队：{card.Name}";
            NavigateToMyFleet();
            ShowOneTimeGuideHint(
                "fleet-joined-member",
                "舰队成员引导",
                "你已经加入舰队。可以先查看成员的飞船、地点与所在服务器，并在“个人”页面完善呼号、头像和舰船数据库。");
        }
        catch (Exception ex)
        {
            var error = UserFacingError.Describe(ex, "暂时无法加入舰队，请稍后重试。");
            NetworkStatusText.Text = error;
            await ShowFleetDirectoryActionNoticeAsync(
                "加入舰队失败",
                $"暂时无法加入“{card.Name}”。",
                error);
        }
        }
        finally
        {
            _findFleetJoinInProgressCodes.Remove(fleetCode);
        }
    }

    private Task<bool> ShowFleetDirectoryActionNoticeAsync(
        string title,
        string message,
        string detail)
    {
        return ShowAppConfirmationAsync(
            title,
            message,
            detail,
            "知道了",
            "",
            danger: false,
            showCancel: false,
            footerText: "关闭提示后可以继续浏览舰队目录。");
    }

    private void RestoreAccountAvatarFromServer(string? avatarImageData)
    {
        // The authenticated account is the avatar authority. Clear any path and
        // encoded image left by the previous account before reading this response,
        // including the valid "no avatar" response.
        ResetAccountAvatarState();

        if (!TryDecodeImageData(avatarImageData, 512 * 1024, out var bytes))
        {
            return;
        }

        try
        {
            var accountToken = BuildSafeImageToken(_accountName, "account");
            var hash = Convert.ToHexString(SHA256.HashData(bytes))[..12].ToLowerInvariant();
            var prefix = $"account-{accountToken}-avatar";
            var path = BuildImagePath(prefix, hash);
            WriteImageFileIfChanged(path, bytes);
            CleanupImageVariants(prefix, path);
            _avatarPath = path;
            _cachedAvatarImagePath = null;
            _cachedAvatarImageData = null;
        }
        catch
        {
            // Keep the account on its placeholder instead of leaking another
            // account's cached avatar when the server copy cannot be cached.
        }
    }

    private void ResetAccountAvatarState()
    {
        _avatarPath = null;
        _cachedAvatarImagePath = null;
        _cachedAvatarImageWriteTimeUtc = default;
        _cachedAvatarImageData = null;
    }

    private async Task WithdrawFleetApplicationAsync(NetworkFleetCard card)
    {
        var result = StarBridgeMessageBox.Show(
            this,
            $"确认撤回向 {card.Name} 的加入申请？",
            "撤回加入申请",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);
        if (result != MessageBoxResult.Yes)
        {
            return;
        }

        try
        {
            var response = await PostNetworkJsonAsync(
                "api/fleets/applications/withdraw",
                new FleetJoinApplicationWithdrawRequest(card.Snapshot.Code));
            if (!response.IsSuccessStatusCode)
            {
                NetworkStatusText.Text = $"撤回失败：{await ReadResponseErrorAsync(response)}";
                return;
            }

            _pendingFleetApplicationCodes.Remove(card.Snapshot.Code);
            await PullNetworkFleetsAsync(silent: true);
            NetworkStatusText.Text = $"已撤回加入申请：{card.Name}";
        }
        catch (Exception ex)
        {
            NetworkStatusText.Text = UserFacingError.Describe(ex, "申请未能撤回，请稍后重试。");
        }
    }

    private void JoinNetworkFleet(NetworkFleetSnapshot snapshot)
    {
        ClearFleetScopedCollectionsForJoin();
        _hasFleet = true;
        _isCreatingFleet = false;
        _fleetName = snapshot.Name;
        _fleetCode = snapshot.Code;
        _fleetProfileRevision = snapshot.ProfileRevision;
        _latestFleetSnapshotCode = snapshot.Code;
        _latestFleetSnapshotUpdatedAtUtc = snapshot.LastUpdated;
        _latestFleetMemberPresenceFingerprint =
            FleetPassiveRefreshPolicy.BuildMemberPresenceFingerprint(snapshot.Members);
        MarkFleetMembershipChanged();
        _fleetDirectorySyncPending = false;
        _lastFleetDirectorySyncAttemptAtUtc = DateTimeOffset.MinValue;
        _fleetChiefCommander = string.IsNullOrWhiteSpace(snapshot.Commander) ? "Unassigned" : snapshot.Commander!;
        _fleetDeputyCommander = "Unassigned";
        _fleetDescription = NormalizeFleetDescription(snapshot.Description);
        _fleetType = string.IsNullOrWhiteSpace(snapshot.Type) ? "Combat" : snapshot.Type!;
        _fleetJoinPolicy = string.IsNullOrWhiteSpace(snapshot.JoinPolicy) ? "Open" : snapshot.JoinPolicy!;
        _fleetRecruitingEnabled = snapshot.RecruitingEnabled;
        _fleetRecruitingTarget = NormalizeFleetRecruitingTarget(snapshot.RecruitingTarget);
        _fleetInviteCodeCreationPolicy = FleetInvitationAccessPolicy.Normalize(snapshot.InviteCodeCreationPolicy);
        _fleetInvitationCardPolicy = FleetInvitationAccessPolicy.Normalize(snapshot.FleetInvitationCardPolicy);
        _fleetActiveTime = string.IsNullOrWhiteSpace(snapshot.ActiveTime) ? DefaultFleetActiveTimeText : snapshot.ActiveTime!;
        _fleetEmailNotificationsEnabled = snapshot.EmailNotificationsEnabled;
        _fleetPublicListingEnabled = snapshot.PublicListingEnabled;
        _fleetPublicMemberScaleMode = NormalizeFleetPublicMemberScaleMode(snapshot.PublicMemberScaleMode);
        _fleetPublicShipScaleMode = NormalizeFleetPublicShipScaleMode(snapshot.PublicShipScaleMode);
        _manageAllowPublicProfileView = true;
        _manageShowDescriptionPublic = snapshot.PublicShowDescription;
        _fleetPublicShowTags = snapshot.PublicShowTags;
        _fleetPublicShowActiveSystems = snapshot.PublicShowActiveSystems;
        _fleetPublicShowActivityTime = snapshot.PublicShowActivityTime;
        _fleetPublicShowExternalContacts = snapshot.PublicShowExternalContacts;
        _fleetLogoPath = SaveNetworkFleetLogo(snapshot);
        LocalFleetText.Text = $"{_fleetName} [{_fleetCode}]";

        MergeNetworkFleetState(snapshot);
        UpdateFleetEntryPanels();
        RefreshFleetHeader();
        SaveCurrentConfig();
        RefreshOverlayWindow();
    }

    private async void LeaveFleetButton_Click(object sender, RoutedEventArgs e)
    {
        await LeaveCurrentFleetAsync();
    }

    private async Task LeaveCurrentFleetAsync()
    {
        if (!EnsureLoggedIn("离开舰队需要先登录星海舰桥账号。"))
        {
            return;
        }

        if (!_hasFleet || string.IsNullOrWhiteSpace(_fleetCode))
        {
            NetworkStatusText.Text = "当前没有可离开的舰队。";
            return;
        }

        string? transferCommanderTo = null;
        if (IsCurrentUserFleetCommander())
        {
            var candidates = GetFleetCommanderTransferCandidates();
            if (candidates.Count == 0)
            {
                await ShowAppNoticeAsync(
                    "无法直接退出舰队",
                    "你是当前舰队指挥官，退出前需要先选择接手成员。",
                    "当前没有可接手的舰队成员。请先邀请成员并完成交接，或前往“解散舰队”执行解散操作。");
                return;
            }

            var recommended = PickRecommendedFleetSuccessor(candidates);
            if (recommended is null)
            {
                NetworkStatusText.Text = "没有可移交的舰队成员。";
                return;
            }

            var selection = await ShowFleetSuccessorDialogAsync(candidates, recommended);
            if (selection is null)
            {
                return;
            }

            transferCommanderTo = selection.Player.Name;
        }
        else if (!await ShowAppConfirmationAsync(
                     "离开舰队",
                     $"确认离开舰队“{_fleetName}”？",
                     "离开后你将失去该舰队的成员身份、成员同步和舰队内部数据访问。之后如需回来，需要重新申请或使用邀请码加入。",
                     "离开舰队",
                     "取消"))
        {
            return;
        }

        try
        {
            var response = await PostNetworkJsonAsync(
                "api/fleets/leave",
                new FleetLeaveRequest(_fleetCode, transferCommanderTo));
            if (!response.IsSuccessStatusCode)
            {
                NetworkStatusText.Text = $"离开舰队失败：{await ReadResponseErrorAsync(response)}";
                return;
            }

            ClearFleetState();
            ConfirmAuthoritativeNoFleetState();
            SaveCurrentConfig();
            await PushLocalSnapshotAsync(silent: true, pushFleetDirectory: false);
            await PullNetworkFleetsAsync(silent: true);
            await PullNetworkSnapshotsAsync(silent: true);
            NetworkStatusText.Text = "已离开舰队。";
            NavigateToMyFleet();
        }
        catch (Exception ex)
        {
            NetworkStatusText.Text = UserFacingError.Describe(ex, "暂时无法离开舰队，请稍后重试。");
        }
    }

    private async void DisbandFleetButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("解散舰队需要先登录星海舰桥账号。"))
        {
            return;
        }

        if (!_hasFleet || string.IsNullOrWhiteSpace(_fleetCode))
        {
            DisbandFleetStatusText.Text = "当前没有可解散的舰队。";
            return;
        }

        var password = DisbandFleetPasswordBox.Password;
        if (string.IsNullOrWhiteSpace(password))
        {
            DisbandFleetStatusText.Text = "请输入账号密码后再解散舰队。";
            return;
        }

        try
        {
            var request = new FleetDisbandRequest(_fleetCode, password);
            var response = await PostNetworkJsonAsync("api/fleets/disband", request);
            if (!response.IsSuccessStatusCode)
            {
                DisbandFleetStatusText.Text = $"解散失败：{await ReadResponseErrorAsync(response)}";
                return;
            }

            ClearFleetState();
            ConfirmAuthoritativeNoFleetState();
            DisbandFleetPasswordBox.Password = "";
            DisbandFleetStatusText.Text = "舰队已解散。";
            NetworkStatusText.Text = "舰队已从服务器移除";
            SaveCurrentConfig();
            await PullNetworkFleetsAsync(silent: true);
            await PullNetworkSnapshotsAsync(silent: true);
            await ShowAppNoticeAsync(
                "舰队已解散",
                "服务器已确认舰队解散。",
                "本地舰队状态已清理，旧同步数据不会重新创建该舰队。如需继续使用，请创建或加入新的舰队。");
        }
        catch (Exception ex)
        {
            DisbandFleetStatusText.Text = UserFacingError.Describe(ex, "舰队未能解散，请稍后重试。");
        }
    }

    private void ClearFleetScopedCollectionsForJoin()
    {
        _fleetNoticeTitle = "";
        _fleetNoticeContent = "";
        _fleetNoticePublishedAt = null;
        _fleetCurrentTaskTitle = "";
        _fleetCurrentTaskBrief = "";
        _fleetCurrentTaskParticipants = "";
        _fleetCurrentTaskRally = "";
        _fleetCurrentTaskShip = "";
        _fleetCurrentTaskEmailCall = false;
        _fleetCurrentTaskTime = null;
        _fleetCurrentTaskHistoryKey = "";
        _fleetCurrentTaskNoticeRevision = 0;
        _fleetActionTitle = "";
        _fleetActionContent = "";
        _fleetActionStartTime = null;
        _fleetActionNotifyMembers = false;
        _fleetEmailNotificationsEnabled = true;
        _selectedActionPlanId = "";
        _editingActionPlanId = "";
        _joinActionNotifyMe = false;
        _fleetTaskHistory.Clear();
        _fleetActionPlans.Clear();
        _joinedActionPlanIds.Clear();
        _allFleetEventLogs.Clear();
        _fleetEventLogs.Clear();
        _fleetEventTimelineRows.Clear();
        _fleetEventActionPlanRows.Clear();
        _fleetNotificationCenterItems.Clear();
        _fleetApplicationSnapshots = [];
        _fleetApplications.Clear();
        _fleetInviteRows.Clear();
        _fleetMemberPermissions.Clear();
        _fleetMemberRows.Clear();
        _fleetSystemRoleGroups.Clear();
        _fleetCustomRoleGroups.Clear();
        _fleetSelectedRolePermissionGroups.Clear();
        _fleetRoleGroupDefinitions.Clear();
        FleetRoleSelectionOptions.Clear();
        _fleetExternalContacts.Clear();
        _remoteFleetShips.Clear();
        _fleetShipInventory.Clear();
        _fleetShipDatabaseRows.Clear();
        _localFleetShipSharedAtCache.Clear();
        _acknowledgedFleetOrderKeys.Clear();
        _fleetInstantTaskResponses.Clear();
        _networkSnapshots.Clear();
        ClearOverlayRosterAuthorizedIdentityKeys();
        var retainedPlayerNames = string.IsNullOrWhiteSpace(_localPlayer)
            ? Array.Empty<string?>()
            : new string?[] { _localPlayer };
        _fleetState.RemovePlayersExcept(retainedPlayerNames);
    }

    private void ClearFleetState()
    {
        _hasFleet = false;
        _isCreatingFleet = false;
        _fleetProfileRevision = 0;
        _latestFleetSnapshotCode = "";
        _latestFleetSnapshotUpdatedAtUtc = DateTimeOffset.MinValue;
        _latestFleetMemberPresenceFingerprint = "";
        _fleetDirectorySyncPending = false;
        _fleetMembershipChangedAtUtc = DateTimeOffset.MinValue;
        _fleetJoinedAtUtc = DateTimeOffset.MinValue;
        _lastFleetDirectorySyncAttemptAtUtc = DateTimeOffset.MinValue;
        _fleetName = "No Fleet";
        _fleetCode = "N/A";
        _fleetChiefCommander = "Unassigned";
        _fleetDeputyCommander = "Unassigned";
        _fleetDescription = "";
        _fleetType = "Combat";
        _fleetJoinPolicy = "Open";
        _fleetRecruitingEnabled = false;
        _fleetRecruitingTarget = "所有玩家";
        _fleetInviteCodeCreationPolicy = FleetInvitationAccessPolicy.AllMembers;
        _fleetInvitationCardPolicy = FleetInvitationAccessPolicy.AllMembers;
        _fleetPublicListingEnabled = true;
        _fleetPublicMemberScaleMode = FleetPublicMemberScaleExact;
        _fleetPublicShipScaleMode = FleetPublicShipScaleTypeSummary;
        _manageAllowPublicProfileView = true;
        _manageShowDescriptionPublic = true;
        _fleetPublicShowTags = true;
        _fleetPublicShowActiveSystems = true;
        _fleetPublicShowActivityTime = true;
        _fleetPublicShowExternalContacts = false;
        _fleetExternalContactPublicationMode = FleetExternalContactPublicationMode.Empty;
        _legacyExternalContactPublicationConfirmed = false;
        _fleetActiveTime = DefaultFleetActiveTimeText;
        _fleetLogoPath = null;
        _fleetBannerPath = null;
        _fleetBannerSourcePath = null;
        _createFleetLogoPath = null;
        ClearFleetScopedCollectionsForJoin();
        LocalFleetText.Text = "未加入舰队";
        LeaveFleetButton.Visibility = Visibility.Collapsed;
        RefreshFleetHeader();
        UpdateFleetEntryPanels();
        RefreshFleetApplications();
        RefreshFleetInfoPanel();
        RefreshFleetMemberManagement();
        RenderState();
        RefreshOverlayWindow();
        RefreshNavigationActivityBadges();
    }
}
