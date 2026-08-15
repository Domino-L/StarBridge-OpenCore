using StarBridge.Core.Friends;
using StarBridge.Core.TrustSafety;
using System.IO;
using System.Net.Http.Json;
using System.Threading;
using System.Windows;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private readonly SemaphoreSlim _notificationRefreshGate = new(1, 1);
    private NotificationInboxContract? _notificationInbox;
    private NotificationCenterView? _notificationCenterView;
    private ReportModerationView? _reportModerationView;
    private AccountSafetyView? _accountSafetyView;
    private AppealModerationView? _appealModerationView;

    private async void PersonalAccountSafetyButton_Click(object sender, RoutedEventArgs e) =>
        await ShowAccountSafetyWorkspaceAsync();

    private async Task ShowAccountSafetyWorkspaceAsync()
    {
        if (!CanSynchronizeUserData)
        {
            await ShowAppNoticeAsync(
                "账号状态暂不可用",
                "完成登录与身份验证后即可查看账号状态。",
                "登录后可以查看限制记录、恢复时间和申诉进度。");
            return;
        }

        if (_accountSafetyView is not null && ApplicationLayerHost.IsShowing(_accountSafetyView))
        {
            await _accountSafetyView.RefreshAsync();
            return;
        }

        var view = new AccountSafetyView(
            LoadTrustSafetyAccountStatusAsync,
            LoadMySanctionAppealsAsync,
            SubmitSanctionAppealAsync,
            ShowSanctionAppealDialogAsync);
        _accountSafetyView = view;
        ApplicationLayerHost.ShowWorkspace(
            "账号状态与申诉",
            "账号安全 · 处理记录与申诉进度",
            view,
            () =>
            {
                if (ReferenceEquals(_accountSafetyView, view))
                {
                    _accountSafetyView = null;
                }

                RefreshBridgeShellForSelectedTab();
            });
        await view.RefreshAsync();
    }

    private Task<string?> ShowSanctionAppealDialogAsync(string sanctionLabel) =>
        ApplicationLayerHost.ShowModalAsync<string>(
            "提交申诉",
            "说明需要复核的事实",
            complete => new SanctionAppealView(sanctionLabel, complete),
            maxWidth: 620,
            maxHeight: 480);

    private Task<TrustSafetyAccountStatusContract?> LoadTrustSafetyAccountStatusAsync() =>
        _relayClient.GetFromJsonAsync<TrustSafetyAccountStatusContract>("api/trust-safety/status");

    private Task<MySanctionAppealsContract?> LoadMySanctionAppealsAsync() =>
        _relayClient.GetFromJsonAsync<MySanctionAppealsContract>("api/appeals/mine");

    private async Task<SanctionAppealRecordContract?> SubmitSanctionAppealAsync(
        CreateSanctionAppealRequestContract request)
    {
        using var response = await _relayClient.PostJsonAsync("api/appeals", request);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(await ReadResponseErrorAsync(response));
        }

        return await response.Content.ReadFromJsonAsync<SanctionAppealRecordContract>();
    }

    private async void OpenReportModerationWorkspace_Click(object sender, RoutedEventArgs e)
    {
        if (!IsLoggedIn || !_accountEntitlements.Contains(TrustSafetyEntitlements.ModerateReports))
        {
            return;
        }

        SetBridgeReviewWorkspaceState("举报审核", "查看待处理举报与证据");

        if (_reportModerationView is not null && ApplicationLayerHost.IsShowing(_reportModerationView))
        {
            await _reportModerationView.RefreshAsync();
            return;
        }

        var view = new ReportModerationView(
            LoadReportModerationQueueAsync,
            LoadReportModerationDetailAsync,
            ReviewReportAsync,
            LoadShipMediaForModerationAsync,
            string.IsNullOrWhiteSpace(_callsign) ? _accountName ?? "审核人员" : _callsign);
        _reportModerationView = view;
        ApplicationLayerHost.ShowWorkspace(
            "举报审核",
            "信任与安全 · 举报队列",
            view,
            () =>
            {
                if (ReferenceEquals(_reportModerationView, view))
                {
                    _reportModerationView = null;
                }

                RefreshBridgeShellForSelectedTab();
            },
            actions: CreateModerationWorkspaceActions(reportSelected: true));
        await view.RefreshAsync();
    }

    private async void OpenAppealModerationWorkspace_Click(object sender, RoutedEventArgs e)
    {
        if (!IsLoggedIn || !_accountEntitlements.Contains(TrustSafetyEntitlements.ModerateReports))
        {
            return;
        }

        SetBridgeReviewWorkspaceState("申诉审核", "查看处罚申诉与处理记录");

        if (_appealModerationView is not null && ApplicationLayerHost.IsShowing(_appealModerationView))
        {
            await _appealModerationView.RefreshAsync();
            return;
        }

        var view = new AppealModerationView(
            LoadAppealModerationQueueAsync,
            LoadAppealModerationDetailAsync,
            ReviewSanctionAppealAsync,
            string.IsNullOrWhiteSpace(_callsign) ? _accountName ?? "审核人员" : _callsign);
        _appealModerationView = view;
        ApplicationLayerHost.ShowWorkspace(
            "申诉审核",
            "信任与安全 · 申诉队列",
            view,
            () =>
            {
                if (ReferenceEquals(_appealModerationView, view))
                {
                    _appealModerationView = null;
                }

                RefreshBridgeShellForSelectedTab();
            },
            actions: CreateModerationWorkspaceActions(reportSelected: false));
        await view.RefreshAsync();
    }

    private IReadOnlyList<ApplicationLayerWorkspaceAction> CreateModerationWorkspaceActions(
        bool reportSelected) =>
        [
            new(
                "举报审核",
                () => OpenReportModerationWorkspace_Click(this, new RoutedEventArgs()),
                reportSelected),
            new(
                "申诉审核",
                () => OpenAppealModerationWorkspace_Click(this, new RoutedEventArgs()),
                !reportSelected)
        ];

    private Task<AdminSanctionAppealQueueContract?> LoadAppealModerationQueueAsync(string? status)
    {
        var route = string.IsNullOrWhiteSpace(status)
            ? "api/admin/appeals"
            : $"api/admin/appeals?status={Uri.EscapeDataString(status)}";
        return _relayClient.GetFromJsonAsync<AdminSanctionAppealQueueContract>(route);
    }

    private Task<AdminSanctionAppealDetailContract?> LoadAppealModerationDetailAsync(string appealId) =>
        _relayClient.GetFromJsonAsync<AdminSanctionAppealDetailContract>(
            $"api/admin/appeals/{Uri.EscapeDataString(appealId)}");

    private async Task<AdminSanctionAppealDetailContract?> ReviewSanctionAppealAsync(
        string appealId,
        ReviewSanctionAppealRequestContract request)
    {
        using var response = await _relayClient.PostJsonAsync(
            $"api/admin/appeals/{Uri.EscapeDataString(appealId)}/review",
            request);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(await ReadResponseErrorAsync(response));
        }

        return await response.Content.ReadFromJsonAsync<AdminSanctionAppealDetailContract>();
    }

    private Task<AdminReportQueueContract?> LoadReportModerationQueueAsync(string? status)
    {
        var route = string.IsNullOrWhiteSpace(status)
            ? "api/admin/reports"
            : $"api/admin/reports?status={Uri.EscapeDataString(status)}";
        return _relayClient.GetFromJsonAsync<AdminReportQueueContract>(route);
    }

    private Task<AdminReportDetailContract?> LoadReportModerationDetailAsync(string reportId) =>
        _relayClient.GetFromJsonAsync<AdminReportDetailContract>(
            $"api/admin/reports/{Uri.EscapeDataString(reportId)}");

    private async Task<AdminReportDetailContract?> ReviewReportAsync(
        string reportId,
        ReviewReportRequestContract request)
    {
        using var response = await _relayClient.PostJsonAsync(
            $"api/admin/reports/{Uri.EscapeDataString(reportId)}/review",
            request);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(await ReadResponseErrorAsync(response));
        }

        return await response.Content.ReadFromJsonAsync<AdminReportDetailContract>();
    }

    private async Task<NotificationInboxContract?> RefreshNotificationCenterAsync(bool showErrors)
    {
        if (!CanSynchronizeUserData)
        {
            ClearNotificationCenterState();
            return null;
        }

        var session = _accountSessionCoordinator.Capture();
        await _notificationRefreshGate.WaitAsync();
        try
        {
            var inbox = await _relayClient.GetFromJsonAsync<NotificationInboxContract>("api/notifications");
            if (inbox is null)
            {
                throw new InvalidDataException("通知数据为空。");
            }

            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return null;
            }

            var visibleInbox = ExcludePrivateMessages(inbox);
            _notificationInbox = visibleInbox;
            UpdateNotificationHeader();
            return visibleInbox;
        }
        catch (Exception ex)
        {
            if (showErrors && _accountSessionCoordinator.IsCurrent(session))
            {
                await ShowAppNoticeAsync(
                    "暂时无法读取通知",
                    "通知中心暂时无法连接，请稍后重试。",
                    UserFacingError.Describe(ex, "请检查网络连接后重试。"));
            }

            return _notificationInbox;
        }
        finally
        {
            _notificationRefreshGate.Release();
        }
    }

    private static NotificationInboxContract ExcludePrivateMessages(NotificationInboxContract inbox)
    {
        var visibleItems = inbox.Items
            .Where(item => !item.ActionTarget.Equals(
                NotificationActionTargets.FriendChat,
                StringComparison.OrdinalIgnoreCase))
            .ToArray();
        if (visibleItems.Length == inbox.Items.Length)
        {
            return inbox;
        }

        return inbox with
        {
            Items = visibleItems,
            UnreadCount = visibleItems.Count(item => item.ReadAt is null),
            ActionRequiredCount = visibleItems.Count(item =>
                item.ReadAt is null &&
                item.Priority.Equals(
                    NotificationPriorities.ActionRequired,
                    StringComparison.OrdinalIgnoreCase))
        };
    }

    private void UpdateNotificationHeader()
    {
        if (HeaderInboxUnreadBadge is null || HeaderInboxUnreadBadgeText is null)
        {
            return;
        }

        var inbox = _notificationInbox;
        var count = inbox is { ActionRequiredCount: > 0 }
            ? inbox.ActionRequiredCount
            : inbox?.UnreadCount ?? 0;
        HeaderInboxUnreadBadgeText.Text = count > 99 ? "99+" : count.ToString();
        HeaderInboxUnreadBadge.Visibility = CanSynchronizeUserData && count > 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        HeaderInboxButton.ToolTip = inbox is { ActionRequiredCount: > 0 }
            ? $"通知中心 · {inbox.ActionRequiredCount} 项需要处理"
            : inbox is { UnreadCount: > 0 }
                ? $"通知中心 · {inbox.UnreadCount} 条未读"
                : "通知中心";
        RefreshBridgeNotificationBadge();
    }

    private void ClearNotificationCenterState()
    {
        _notificationInbox = null;
        if (HeaderInboxUnreadBadge is not null)
        {
            HeaderInboxUnreadBadge.Visibility = Visibility.Collapsed;
        }

        if (HeaderInboxButton is not null)
        {
            HeaderInboxButton.ToolTip = "通知中心";
        }

        RefreshBridgeNotificationBadge();

        ApplicationLayerHost.CloseWorkspace();
        _notificationCenterView = null;
        _accountSafetyView = null;
        _reportModerationView = null;
        _appealModerationView = null;
    }

    private async Task ShowNotificationCenterAsync()
    {
        if (!CanSynchronizeUserData)
        {
            await ShowAppNoticeAsync(
                "通知中心暂不可用",
                "完成登录与身份验证后即可查看通知。",
                "好友、舰队和房间的原有入口不会受到影响。");
            return;
        }

        if (_notificationCenterView is not null && ApplicationLayerHost.IsShowing(_notificationCenterView))
        {
            await _notificationCenterView.ReloadAsync();
            return;
        }

        var view = new NotificationCenterView(
            () => RefreshNotificationCenterAsync(showErrors: false),
            MarkNotificationsReadAndReloadAsync,
            LoadMyReportsAsync,
            NavigateNotificationAsync);
        _notificationCenterView = view;
        ApplicationLayerHost.ShowWorkspace(
            "通知中心",
            "好友、舰队、房间与账号安全",
            view,
            () =>
            {
                if (ReferenceEquals(_notificationCenterView, view))
                {
                    _notificationCenterView = null;
                }
            });
        await view.ReloadAsync();
    }

    private async void HeaderMyReportsMenuItem_Click(object sender, RoutedEventArgs e) =>
        await ShowMyReportsAsync();

    private async Task ShowMyReportsAsync()
    {
        await ShowNotificationCenterAsync();
        if (_notificationCenterView is not null)
        {
            await _notificationCenterView.ShowReportsAsync();
        }
    }

    private async Task<NotificationInboxContract?> MarkNotificationsReadAndReloadAsync(string[] notificationIds)
    {
        if (!CanSynchronizeUserData || notificationIds.Length == 0)
        {
            return _notificationInbox;
        }

        var session = _accountSessionCoordinator.Capture();
        using var response = await _relayClient.PostJsonAsync(
            "api/notifications/read",
            new NotificationReadRequestContract(notificationIds));
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(await ReadResponseErrorAsync(response));
        }

        if (!_accountSessionCoordinator.IsCurrent(session))
        {
            return null;
        }

        return await RefreshNotificationCenterAsync(showErrors: false);
    }

    private async Task<MyReportsContract?> LoadMyReportsAsync()
    {
        if (!CanSynchronizeUserData)
        {
            return null;
        }

        var session = _accountSessionCoordinator.Capture();
        var reports = await _relayClient.GetFromJsonAsync<MyReportsContract>("api/reports/mine");
        return _accountSessionCoordinator.IsCurrent(session) ? reports : null;
    }

    private async Task NavigateNotificationAsync(NotificationItemContract item)
    {
        switch (item.ActionTarget)
        {
            case NotificationActionTargets.FriendRequests:
                await NavigateToFriendRequestAsync(item.ActionEntityId);
                ApplicationLayerHost.CloseWorkspace();
                return;
            case NotificationActionTargets.FriendChat:
                await NavigateToFriendChatAsync(item.ActionEntityId);
                ApplicationLayerHost.CloseWorkspace();
                return;
            case NotificationActionTargets.FleetApplications:
                await NavigateToFleetApplicationsAsync(item.ActionEntityId);
                ApplicationLayerHost.CloseWorkspace();
                return;
            case NotificationActionTargets.RoomInvitations:
                await NavigateToRoomInvitationsAsync(item.ActionEntityId);
                ApplicationLayerHost.CloseWorkspace();
                return;
            case NotificationActionTargets.RoomApplications:
                await NavigateToRoomApplicationsAsync(item.ActionEntityId);
                ApplicationLayerHost.CloseWorkspace();
                return;
            case NotificationActionTargets.MyReports:
                await ShowMyReportsAsync();
                return;
            case NotificationActionTargets.AccountSafety:
                await ShowAccountSafetyWorkspaceAsync();
                return;
            case NotificationActionTargets.OverlaySettings:
                ApplicationLayerHost.CloseWorkspace();
                OpenOverlayAppearanceSettings();
                return;
            default:
                await ShowNotificationUnavailableAsync();
                ApplicationLayerHost.CloseWorkspace();
                return;
        }
    }

    private async Task NavigateToFriendRequestAsync(string? accountId)
    {
        HeaderFriendCenterButton_Click(HeaderFriendCenterButton, new RoutedEventArgs());
        await RefreshFriendCenterAsync(showErrors: false);
        var available = !string.IsNullOrWhiteSpace(accountId) &&
                        _friendCenterSnapshot?.IncomingRequests.Any(entry =>
                            entry.User.AccountId.Equals(accountId, StringComparison.OrdinalIgnoreCase)) == true;
        if (!available)
        {
            await ShowNotificationUnavailableAsync();
            return;
        }

        SetFriendCenterSection(FriendCenterSection.Incoming);
    }

    private async Task NavigateToFriendChatAsync(string? accountId)
    {
        HeaderFriendCenterButton_Click(HeaderFriendCenterButton, new RoutedEventArgs());
        await RefreshFriendChatAsync(showErrors: false);
        var conversation = _friendChatConversations.FirstOrDefault(row =>
            !string.IsNullOrWhiteSpace(accountId) &&
            row.AccountId.Equals(accountId, StringComparison.OrdinalIgnoreCase));
        if (conversation is null)
        {
            await ShowNotificationUnavailableAsync();
            return;
        }

        await OpenFriendChatAsync(conversation.User, DirectMessageOrigins.FriendCenter);
    }

    private async Task NavigateToFleetApplicationsAsync(string? fleetCode)
    {
        var permissionRefreshCompleted = await PullNetworkFleetsAsync(silent: true);
        if (!permissionRefreshCompleted || !CanCurrentUserReviewFleetApplications())
        {
            await ShowAppNoticeAsync(
                "无法打开审核队列",
                "你当前没有审核舰队申请的权限。",
                "可以联系舰队管理者，或在舰队原页面查看你有权访问的内容。");
            return;
        }

        if (string.IsNullOrWhiteSpace(fleetCode) ||
            !_fleetCode.Equals(fleetCode, StringComparison.OrdinalIgnoreCase))
        {
            await ShowNotificationUnavailableAsync();
            return;
        }

        NavigateToMyFleet();
        OpenFleetApplicationReviewQueue();
    }

    private async Task NavigateToRoomInvitationsAsync(string? roomId)
    {
        NavigateToPartyLobby(animate: true, showGuideHint: false);
        await RefreshPartyRoomsFromServerAsync(showErrors: false);
        var available = !string.IsNullOrWhiteSpace(roomId) &&
                        _receivedPartyRoomInvitations.Any(invitation =>
                            invitation.RoomId.Equals(roomId, StringComparison.OrdinalIgnoreCase));
        if (!available)
        {
            await ShowNotificationUnavailableAsync();
            return;
        }

        OpenPartyRoomInvitationPanel(showHostFriends: false);
    }

    private async Task NavigateToRoomApplicationsAsync(string? roomId)
    {
        NavigateToPartyLobby(animate: true, showGuideHint: false);
        await RefreshPartyRoomsFromServerAsync(showErrors: false);
        if (_currentPartyRoom is null ||
            !_currentPartyRoom.ViewerIsHost ||
            !_currentPartyRoom.HasPendingApplications ||
            string.IsNullOrWhiteSpace(roomId) ||
            !_currentPartyRoom.RoomId.Equals(roomId, StringComparison.OrdinalIgnoreCase))
        {
            await ShowNotificationUnavailableAsync();
            return;
        }

        ShowCurrentPartyRoom();
        _ = Dispatcher.BeginInvoke(
            System.Windows.Threading.DispatcherPriority.Loaded,
            new Action(() => PartyCurrentRoomApplicationsPanel.BringIntoView()));
    }

    private Task<bool> ShowNotificationUnavailableAsync() => ShowAppNoticeAsync(
        "内容已失效",
        "这项内容已处理或不再可用。",
        "你仍可在对应的好友、舰队或房间页面查看最新状态。");

    private void RefreshPersonalProfileReportAction()
    {
        if (PersonalProfileReportButton is null)
        {
            return;
        }

        var targetAccountId = _personalProfileVisitorTarget?.AccountId;
        var canReport = _isPersonalProfileVisitorMode &&
                        !string.IsNullOrWhiteSpace(targetAccountId) &&
                        !string.Equals(targetAccountId, _accountId, StringComparison.OrdinalIgnoreCase);
        PersonalProfileReportButton.Visibility = canReport ? Visibility.Visible : Visibility.Collapsed;
        PersonalProfileReportButton.IsEnabled = canReport && CanSynchronizeUserData;
        PersonalProfileReportButton.ToolTip = CanSynchronizeUserData
            ? "举报此用户"
            : "完成登录与身份验证后可以提交举报";
    }

    private async void PersonalProfileReportButton_Click(object sender, RoutedEventArgs e)
    {
        if (_personalProfileVisitorTarget is { } target)
        {
            await SubmitUserReportAsync(target);
        }
    }

    private async Task SubmitUserReportAsync(PlayerRow target)
    {
        if (!CanSynchronizeUserData || string.IsNullOrWhiteSpace(target.AccountId))
        {
            await ShowAppNoticeAsync(
                "暂时无法举报",
                "完成登录与身份验证后可以提交举报。",
                "举报记录会保存在你的账号中，便于后续查看进度。");
            return;
        }

        if (target.AccountId.Equals(_accountId, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        var displayName = string.IsNullOrWhiteSpace(target.Callsign) ? target.Name : target.Callsign;
        var submission = await ApplicationLayerHost.ShowModalAsync<ReportUserSubmission>(
            "举报用户",
            "选择原因并补充说明",
            complete => new ReportUserView(displayName ?? target.Name, complete),
            maxWidth: 620,
            maxHeight: 640);
        if (submission is null)
        {
            return;
        }

        var session = _accountSessionCoordinator.Capture();
        var request = new CreateReportRequestContract(
            ReportTargetTypes.User,
            target.AccountId,
            displayName ?? target.Name,
            "personal_profile",
            null,
            submission.Reason,
            submission.Details,
            Guid.NewGuid().ToString("N"));
        try
        {
            using var response = await _relayClient.PostJsonAsync("api/reports", request);
            if (!response.IsSuccessStatusCode)
            {
                throw new InvalidOperationException(await ReadResponseErrorAsync(response));
            }

            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return;
            }

            await RefreshNotificationCenterAsync(showErrors: false);
            await ShowAppNoticeAsync(
                "举报已提交",
                "我们已收到你的举报。",
                "可以在通知中心的“我的举报”中查看记录；请勿重复提交同一问题。");
        }
        catch (Exception ex)
        {
            await ShowAppNoticeAsync(
                "举报未提交",
                "暂时无法提交这份举报，请稍后重试。",
                UserFacingError.Describe(ex, "请检查网络连接后重试。"));
        }
    }
}
