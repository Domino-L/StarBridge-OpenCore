using StarBridge.Core.Friends;
using StarBridge.Core.Chat;
using StarBridge.Core.Presence;
using System.Collections.ObjectModel;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private enum FriendCenterViewState
    {
        Content,
        Loading,
        Error,
        NoPermission
    }

    private readonly record struct FriendChatOperationLane(
        AccountSessionLease Session,
        string TargetAccountId);

    private readonly ObservableCollection<FriendCenterRow> _friendCenterRows = [];
    private readonly ObservableCollection<FriendChatConversationRow> _friendChatConversations = [];
    private readonly ObservableCollection<FriendChatMessageRow> _friendChatMessages = [];
    private readonly FriendOverlayNotificationTracker _friendOverlayNotificationTracker = new();
    private readonly DispatcherTimer _friendCenterRefreshTimer = new() { Interval = TimeSpan.FromSeconds(20) };
    private readonly DispatcherTimer _friendChatRefreshTimer = new() { Interval = TimeSpan.FromSeconds(5) };
    private readonly HashSet<AccountSessionLease> _refreshingFriendCenterSessions = [];
    private readonly HashSet<AccountSessionLease> _refreshingFriendChatSessions = [];
    private readonly HashSet<FriendChatOperationLane> _sendingFriendChatMessageLanes = [];
    private CancellationTokenSource? _socialActivityCts;
    private Task? _socialActivityLoopTask;
    private string _socialActivityInstanceId = "";
    private long _socialActivityVersion = -1;
    private FriendCenterSnapshotContract? _friendCenterSnapshot;
    private FriendUserContract[] _friendSearchResults = [];
    private FriendCenterSection _friendCenterSection = FriendCenterSection.Friends;
    private readonly HashSet<AccountSessionLease> _mutatingFriendRelationshipSessions = [];
    private bool _isSelectingFriendChatConversation;
    private string? _pendingFriendChatConversationAccountId;
    private System.Windows.Point _friendChatConversationPressPoint;
    private bool _isApplyingDirectMessagePrivacy;
    private bool _isUpdatingDirectMessagePrivacy;
    private bool _friendChatHasOlder;
    private bool _isLoadingOlderFriendChat;
    private bool _friendChatFollowLatest = true;
    private FriendUserContract? _activeFriendChatUser;
    private FriendChatConversationContract? _activeFriendChatConversation;
    private DirectMessagePrivacyContract _directMessagePrivacy = new(true, default);
    private string _activeFriendChatOrigin = DirectMessageOrigins.Unknown;
    private long _friendChatLatestSequence;
    private bool _isSendingFriendChatMessage =>
        _activeFriendChatUser is { } activeUser &&
        !string.IsNullOrWhiteSpace(activeUser.AccountId) &&
        _sendingFriendChatMessageLanes.Contains(CreateFriendChatOperationLane(
            _accountSessionCoordinator.Capture(),
            activeUser.AccountId));
    private bool CanConfigureDirectMessagePrivacy =>
        DirectMessagePrivacyAvailabilityPolicy.CanConfigure(IsLoggedIn, CanSynchronizeUserData);

    private static FriendChatOperationLane CreateFriendChatOperationLane(
        AccountSessionLease session,
        string targetAccountId) =>
        new(session, targetAccountId.Trim().ToUpperInvariant());

    private bool IsFriendChatOperationCurrent(FriendChatOperationLane lane) =>
        _accountSessionCoordinator.IsCurrent(lane.Session) &&
        _activeFriendChatUser is { } activeUser &&
        CreateFriendChatOperationLane(lane.Session, activeUser.AccountId).TargetAccountId
            .Equals(lane.TargetAccountId, StringComparison.Ordinal);

    private void RefreshDirectMessagePrivacyAuthenticationState()
    {
        ApplyDirectMessagePrivacyToControls();
        if (CanConfigureDirectMessagePrivacy && IsLoaded)
        {
            _ = RefreshDirectMessagePrivacyAsync(showErrors: false);
        }
    }

    private void InitializeFriendCenter()
    {
        FriendCenterResultsList.ItemsSource = _friendCenterRows;
        FriendChatConversationList.ItemsSource = _friendChatConversations;
        FriendChatMessageList.ItemsSource = _friendChatMessages;
        InitializeFriendCenterAcceptanceScenarios();
        ChatHistoryViewport.EnableSmoothScrolling(FriendChatMessageList);
        FriendChatMessageList.AddHandler(
            ScrollViewer.ScrollChangedEvent,
            new ScrollChangedEventHandler(FriendChatMessageList_ScrollChanged));
        _friendCenterRefreshTimer.Tick += FriendCenterRefreshTimer_Tick;
        _friendChatRefreshTimer.Tick += FriendChatRefreshTimer_Tick;
        _friendCenterRefreshTimer.Start();
        _friendChatRefreshTimer.Start();
        SetFriendCenterSection(FriendCenterSection.Friends);
        ApplyDirectMessagePrivacyToControls();
        Loaded += async (_, _) =>
        {
            StartSocialActivityLoop();
            await RefreshFriendCenterAsync(showErrors: false);
            await RefreshFriendChatAsync(showErrors: false);
            await RefreshDirectMessagePrivacyAsync(showErrors: false);
            await RefreshNotificationCenterAsync(showErrors: false);
        };
    }

    private void DisposeFriendCenter()
    {
        _socialActivityCts?.Cancel();
        _socialActivityCts?.Dispose();
        _socialActivityCts = null;
        _friendCenterRefreshTimer.Stop();
        _friendCenterRefreshTimer.Tick -= FriendCenterRefreshTimer_Tick;
        _friendChatRefreshTimer.Stop();
        _friendChatRefreshTimer.Tick -= FriendChatRefreshTimer_Tick;
    }

    private void ResetFriendCenterAccountState()
    {
        _friendOverlayNotificationTracker.Reset();
        _friendCenterSnapshot = null;
        _friendSearchResults = [];
        _friendCenterRows.Clear();
        _friendChatConversations.Clear();
        _friendChatMessages.Clear();
        _activeFriendChatUser = null;
        _activeFriendChatConversation = null;
        _activeFriendChatOrigin = DirectMessageOrigins.Unknown;
        _directMessagePrivacy = new DirectMessagePrivacyContract(true, default);
        _friendChatLatestSequence = 0;
        _socialActivityInstanceId = "";
        _socialActivityVersion = -1;
        ResetFriendChatPagingState();

        FriendCenterFriendsCountText.Text = "0";
        FriendCenterIncomingCountText.Text = "0";
        FriendCenterOutgoingCountText.Text = "0";
        FriendCenterBlockedCountText.Text = "0";
        FriendCenterConversationUnreadText.Text = "0";
        FriendCenterConversationUnreadBadge.Visibility = Visibility.Collapsed;
        ApplyFriendCenterCountVisuals(0, 0, 0, 0);
        SetFriendCenterViewState(FriendCenterViewState.NoPermission);
        SetFriendCenterDegradedState(false);
        RefreshNavigationActivityBadges();
        RenderFriendCenterSection();
        RenderActiveFriendChat();
        RefreshPersonalProfileFriendAction();
        ClearNotificationCenterState();
        ApplyDirectMessagePrivacyToControls();
        SetFriendCenterStatus("登录后即可同步好友与私聊。", StatusPalette.DisabledBrush);
        RefreshInGameSocialSnapshot();
    }

    private void StartSocialActivityLoop()
    {
        if (_socialActivityLoopTask is { IsCompleted: false })
        {
            return;
        }

        _socialActivityCts?.Dispose();
        _socialActivityCts = new CancellationTokenSource();
        _socialActivityLoopTask = RunSocialActivityLoopAsync(_socialActivityCts.Token);
    }

    private async Task RunSocialActivityLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            if (!CanSynchronizeUserData)
            {
                await Task.Delay(TimeSpan.FromSeconds(1), cancellationToken);
                continue;
            }

            var session = _accountSessionCoordinator.Capture();
            try
            {
                using var request = new HttpRequestMessage(
                    HttpMethod.Get,
                    _relayClient.BuildUri(
                        $"api/social/activity?after={_socialActivityVersion}" +
                        $"&instance={Uri.EscapeDataString(_socialActivityInstanceId)}" +
                        "&waitSeconds=20"));
                using var response = await _relayClient.SendAsync(request, cancellationToken);
                if (response.StatusCode is HttpStatusCode.NotFound or HttpStatusCode.MethodNotAllowed)
                {
                    await Task.Delay(TimeSpan.FromSeconds(5), cancellationToken);
                    continue;
                }

                response.EnsureSuccessStatusCode();
                var activity = await response.Content.ReadFromJsonAsync<RealtimeActivityContract>(
                    cancellationToken: cancellationToken);
                if (activity is null || !_accountSessionCoordinator.IsCurrent(session))
                {
                    continue;
                }

                var instanceChanged =
                    _socialActivityInstanceId.Length > 0 &&
                    !string.Equals(
                        _socialActivityInstanceId,
                        activity.InstanceId,
                        StringComparison.Ordinal);
                var previousVersion = instanceChanged ? -1 : _socialActivityVersion;
                _socialActivityInstanceId = activity.InstanceId;
                _socialActivityVersion = activity.Version;
                if (instanceChanged || previousVersion >= 0 && activity.Version > previousVersion)
                {
                    await Task.WhenAll(
                        RefreshFriendCenterAsync(showErrors: false),
                        RefreshFriendChatAsync(showErrors: false),
                        RefreshNotificationCenterAsync(showErrors: false));
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch
            {
                await Task.Delay(TimeSpan.FromSeconds(2), cancellationToken);
            }
        }
    }

    private async void FriendChatRefreshTimer_Tick(object? sender, EventArgs e)
    {
        RefreshFriendCommunicationTimeLabels();
        if (CanSynchronizeUserData)
        {
            await RefreshFriendChatAsync(showErrors: false);
        }
    }

    private void RefreshFriendCommunicationTimeLabels()
    {
        var now = DateTimeOffset.Now;
        foreach (var row in _friendChatConversations)
        {
            row.RefreshTime(now);
        }

        foreach (var row in _friendChatMessages)
        {
            row.RefreshTime(now);
        }
    }

    private async void FriendCenterRefreshTimer_Tick(object? sender, EventArgs e)
    {
        if (CanSynchronizeUserData)
        {
            await RefreshFriendCenterAsync(showErrors: false);
        }
    }

    private async void HeaderFriendCenterButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryLeaveOverlayEditorTab())
        {
            return;
        }

        if (_isPersonalProfileVisitorMode)
        {
            ExitPersonalProfileVisitorMode(restoreReturnTab: false);
        }

        var previousTab = MainTabs.SelectedItem;
        MainTabs.SelectedItem = FriendCenterTab;
        SetActiveNav(HeaderFriendCenterButton);
        QueueMainPageReveal(previousTab);
        await RefreshFriendCenterAsync(showErrors: true);
        await RefreshFriendChatAsync(showErrors: false);
        await RefreshDirectMessagePrivacyAsync(showErrors: false);
    }

    private async Task RefreshDirectMessagePrivacyAsync(bool showErrors)
    {
        if (IsFriendCenterAcceptanceMode)
        {
            return;
        }

        if (!CanConfigureDirectMessagePrivacy)
        {
            ApplyDirectMessagePrivacyToControls();
            return;
        }

        var session = _accountSessionCoordinator.Capture();
        try
        {
            var privacy = await _relayClient.GetFromJsonAsync<DirectMessagePrivacyContract>(
                "api/friends/chat/privacy");
            if (privacy is null)
            {
                throw new InvalidDataException("私信接收设置数据为空。");
            }

            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return;
            }

            _directMessagePrivacy = privacy;
            ApplyDirectMessagePrivacyToControls();
        }
        catch (Exception ex)
        {
            if (showErrors)
            {
                DirectMessagePrivacyStatusText.Text = UserFacingError.Describe(ex, "私信设置暂时无法读取，请稍后重试。");
                DirectMessagePrivacyStatusText.Foreground = StatusPalette.DangerBrush;
            }
        }
    }

    private void ApplyDirectMessagePrivacyToControls()
    {
        if (DirectMessageFriendsOnlyCheck is null || DirectMessagePrivacyStatusText is null)
        {
            return;
        }

        _isApplyingDirectMessagePrivacy = true;
        DirectMessageFriendsOnlyCheck.IsChecked = _directMessagePrivacy.FriendsOnly;
        DirectMessageFriendsOnlyCheck.IsEnabled = CanConfigureDirectMessagePrivacy && !_isUpdatingDirectMessagePrivacy;
        DirectMessagePrivacyStatusText.Text = !CanConfigureDirectMessagePrivacy
            ? "登录后可修改"
            : _directMessagePrivacy.FriendsOnly
                ? "新的陌生人消息请求已关闭"
                : "允许陌生人发起一条消息请求";
        DirectMessagePrivacyStatusText.Foreground = !CanConfigureDirectMessagePrivacy
            ? StatusPalette.DisabledBrush
            : StatusPalette.InfoBrush;
        _isApplyingDirectMessagePrivacy = false;
    }

    private async void DirectMessageFriendsOnlyCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isApplyingDirectMessagePrivacy || _isUpdatingDirectMessagePrivacy)
        {
            return;
        }

        if (IsFriendCenterAcceptanceMode)
        {
            ApplyDirectMessagePrivacyToControls();
            DirectMessagePrivacyStatusText.Text = "模拟场景不会修改私信设置。";
            DirectMessagePrivacyStatusText.Foreground = StatusPalette.InfoBrush;
            return;
        }

        if (!CanConfigureDirectMessagePrivacy)
        {
            ApplyDirectMessagePrivacyToControls();
            return;
        }

        var previous = _directMessagePrivacy;
        var friendsOnly = DirectMessageFriendsOnlyCheck.IsChecked == true;
        string? failure = null;
        _isUpdatingDirectMessagePrivacy = true;
        ApplyDirectMessagePrivacyToControls();
        try
        {
            using var response = await _relayClient.PostJsonAsync(
                "api/friends/chat/privacy",
                new DirectMessagePrivacyUpdateRequestContract(friendsOnly));
            if (!response.IsSuccessStatusCode)
            {
                throw new InvalidOperationException(await ReadResponseErrorAsync(response));
            }

            _directMessagePrivacy = await response.Content.ReadFromJsonAsync<DirectMessagePrivacyContract>()
                ?? throw new InvalidDataException("私信接收设置保存结果为空。");
        }
        catch (Exception ex)
        {
            _directMessagePrivacy = previous;
            failure = UserFacingError.Describe(ex, "私信设置未保存，请稍后重试。");
        }
        finally
        {
            _isUpdatingDirectMessagePrivacy = false;
            ApplyDirectMessagePrivacyToControls();
            if (failure is not null)
            {
                DirectMessagePrivacyStatusText.Text = $"保存失败：{failure}";
                DirectMessagePrivacyStatusText.Foreground = StatusPalette.DangerBrush;
            }
        }
    }

    private async Task RefreshFriendCenterAsync(bool showErrors)
    {
        if (IsFriendCenterAcceptanceMode)
        {
            SetFriendCenterStatus("模拟场景 · 选择“返回实际数据”后恢复同步", StatusPalette.InfoBrush);
            return;
        }

        if (!CanSynchronizeUserData)
        {
            SetFriendCenterViewState(FriendCenterViewState.NoPermission);
            SetFriendCenterDegradedState(false);
            SetFriendCenterStatus("登录后即可同步好友与申请。", StatusPalette.DisabledBrush);
            _inGameFriendDirectoryState = InGameFriendDirectoryState.Unavailable;
            _inGameFriendCollectionStatus = "登录后即可同步好友与申请。";
            RefreshInGameSocialSnapshot();
            return;
        }

        var session = _accountSessionCoordinator.Capture();
        if (!_refreshingFriendCenterSessions.Add(session))
        {
            return;
        }

        var hasCachedSnapshot = _friendCenterSnapshot is not null;
        SetFriendCenterDegradedState(false);
        if (!hasCachedSnapshot)
        {
            SetFriendCenterViewState(FriendCenterViewState.Loading);
        }

        _inGameFriendDirectoryState = InGameFriendDirectoryState.Loading;
        _inGameFriendCollectionStatus = "正在同步好友与申请…";
        RefreshInGameSocialSnapshot();
        try
        {
            var includePresence = GetPresenceSharingDecision().CanReceiveRealtime.ToString().ToLowerInvariant();
            var snapshot = await _relayClient.GetFromJsonAsync<FriendCenterSnapshotContract>(
                $"api/friends?includePresence={includePresence}");
            if (snapshot is null)
            {
                throw new InvalidDataException("好友数据为空。");
            }

            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return;
            }

            _inGameFriendDirectoryState = InGameFriendDirectoryState.Ready;
            _inGameFriendCollectionStatus = snapshot.Friends.Length == 0
                ? "好友列表为空，可以通过上方搜索添加好友。"
                : $"已加载 {snapshot.Friends.Length} 位好友";
            ApplyFriendCenterSnapshot(snapshot);
            SetFriendCenterViewState(FriendCenterViewState.Content);
            SetFriendCenterDegradedState(false);
            SetFriendCenterStatus($"已同步 · {snapshot.RefreshedAt.ToLocalTime():HH:mm:ss}", StatusPalette.SuccessBrush);
        }
        catch (Exception ex)
        {
            if (_accountSessionCoordinator.IsCurrent(session))
            {
                var failure = UserFacingError.Describe(
                    ex,
                    "好友数据暂时无法同步，请稍后重试。");
                _inGameFriendDirectoryState = InGameFriendDirectoryState.Failed;
                _inGameFriendCollectionStatus = failure;
                if (hasCachedSnapshot)
                {
                    SetFriendCenterViewState(FriendCenterViewState.Content);
                    SetFriendCenterDegradedState(true, "连接暂时不可用，当前显示上次同步的好友数据。");
                }
                else
                {
                    SetFriendCenterViewState(FriendCenterViewState.Error, failure);
                }
                RefreshInGameSocialSnapshot();
                if (showErrors)
                {
                    SetFriendCenterStatus(failure, StatusPalette.DangerBrush);
                }
            }
        }
        finally
        {
            _refreshingFriendCenterSessions.Remove(session);
        }
    }

    private void ApplyFriendCenterSnapshot(FriendCenterSnapshotContract snapshot)
    {
        var communicationEvents = _friendOverlayNotificationTracker.ObserveFriends(
            snapshot,
            CanSynchronizeUserData,
            _language);
        _friendCenterSnapshot = snapshot;
        FriendCenterFriendsCountText.Text = snapshot.Friends.Length.ToString();
        FriendCenterIncomingCountText.Text = snapshot.IncomingRequests.Length.ToString();
        FriendCenterOutgoingCountText.Text = snapshot.OutgoingRequests.Length.ToString();
        FriendCenterBlockedCountText.Text = snapshot.BlockedUsers.Length.ToString();
        ApplyFriendCenterCountVisuals(
            snapshot.Friends.Length,
            snapshot.IncomingRequests.Length,
            snapshot.OutgoingRequests.Length,
            snapshot.BlockedUsers.Length);
        RefreshNavigationActivityBadges();
        RenderFriendCenterSection();
        RefreshPersonalProfileFriendAction();
        QueueFriendCommunicationEvents(communicationEvents);
        RefreshInGameSocialSnapshot();
    }

    private void FriendCenterSectionButton_Click(object sender, RoutedEventArgs e)
    {
        var section = sender switch
        {
            _ when ReferenceEquals(sender, FriendCenterConversationsButton) => FriendCenterSection.Conversations,
            _ when ReferenceEquals(sender, FriendCenterIncomingButton) => FriendCenterSection.Incoming,
            _ when ReferenceEquals(sender, FriendCenterOutgoingButton) => FriendCenterSection.Outgoing,
            _ when ReferenceEquals(sender, FriendCenterBlockedButton) => FriendCenterSection.Blocked,
            _ => FriendCenterSection.Friends
        };
        SetFriendCenterSection(section);
    }

    private void SetFriendCenterSection(FriendCenterSection section)
    {
        _friendCenterSection = section;
        var activeButton = section switch
        {
            FriendCenterSection.Conversations => FriendCenterConversationsButton,
            FriendCenterSection.Incoming => FriendCenterIncomingButton,
            FriendCenterSection.Outgoing => FriendCenterOutgoingButton,
            FriendCenterSection.Blocked => FriendCenterBlockedButton,
            _ => FriendCenterFriendsButton
        };
        UiMotion.ApplyNavigationSelection(
            [
                FriendCenterConversationsButton,
                FriendCenterFriendsButton,
                FriendCenterIncomingButton,
                FriendCenterOutgoingButton,
                FriendCenterBlockedButton
            ],
            activeButton);
        ApplyFriendCenterSectionVisibility();
        if (section == FriendCenterSection.Conversations)
        {
            if (!IsFriendCenterAcceptanceMode)
            {
                _ = RefreshFriendChatAsync(showErrors: true);
            }
        }
        else
        {
            RenderFriendCenterSection();
        }

    }

    private void RenderFriendCenterSection()
    {
        if (FriendCenterResultsList is null)
        {
            return;
        }

        var entries = _friendCenterSection switch
        {
            FriendCenterSection.Incoming => _friendCenterSnapshot?.IncomingRequests ?? [],
            FriendCenterSection.Outgoing => _friendCenterSnapshot?.OutgoingRequests ?? [],
            FriendCenterSection.Blocked => _friendCenterSnapshot?.BlockedUsers ?? [],
            FriendCenterSection.Search => _friendSearchResults
                .Select(user => new FriendEntryContract(user, default))
                .ToArray(),
            _ => _friendCenterSnapshot?.Friends ?? []
        };
        _friendCenterRows.Clear();
        foreach (var entry in entries)
        {
            var user = FriendCenterUserResolver.Resolve(entry.User, _networkSnapshots.Values);
            _friendCenterRows.Add(new FriendCenterRow(user, entry.RelationshipUpdatedAt));
        }

        var (title, emptyTitle, emptyDescription) = _friendCenterSection switch
        {
            FriendCenterSection.Incoming => ("收到的申请", "没有待处理申请", "新的好友申请会显示在这里。"),
            FriendCenterSection.Outgoing => ("已发送的申请", "没有等待中的申请", "你发送但尚未处理的申请会显示在这里。"),
            FriendCenterSection.Blocked => ("已屏蔽用户", "没有屏蔽用户", "被屏蔽的用户无法向你发送好友申请。"),
            FriendCenterSection.Search => ("查找用户", "没有找到用户", "尝试输入完整呼号或游戏 ID。"),
            _ => ("好友", "还没有好友", "使用上方搜索框查找呼号或游戏 ID，发送第一条好友申请。")
        };
        FriendCenterResultsTitleText.Text = title;
        FriendCenterResultsMetaText.Text = $"{_friendCenterRows.Count} 位用户";
        FriendCenterEmptyTitleText.Text = emptyTitle;
        FriendCenterEmptyDescriptionText.Text = emptyDescription;
        FriendCenterEmptyState.Visibility = _friendCenterRows.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private async void FriendCenterRefreshButton_Click(object sender, RoutedEventArgs e) =>
        await RefreshFriendCenterAsync(showErrors: true);

    private async void FriendSearchButton_Click(object sender, RoutedEventArgs e) =>
        await SearchFriendsAsync();

    private async void FriendSearchBox_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key != Key.Enter)
        {
            return;
        }

        e.Handled = true;
        await SearchFriendsAsync();
    }

    private async Task SearchFriendsAsync()
    {
        if (IsFriendCenterAcceptanceMode)
        {
            SetFriendCenterStatus("模拟场景不会发起搜索；可在“验收场景”中切换到“搜索结果”。", StatusPalette.InfoBrush);
            return;
        }

        var query = FriendSearchBox.Text.Trim();
        if (query.Length < 2)
        {
            SetFriendCenterStatus("请输入至少 2 个字符搜索呼号或游戏 ID。", StatusPalette.WarningBrush);
            return;
        }

        if (!CanSynchronizeUserData)
        {
            SetFriendCenterViewState(FriendCenterViewState.NoPermission);
            SetFriendCenterStatus("请先登录，再查找用户。", StatusPalette.WarningBrush);
            return;
        }

        try
        {
            var response = await _relayClient.GetFromJsonAsync<FriendSearchResponseContract>(
                $"api/friends/search?q={Uri.EscapeDataString(query)}&includePresence={GetPresenceSharingDecision().CanReceiveRealtime.ToString().ToLowerInvariant()}");
            _friendSearchResults = response?.Results ?? [];
            SetFriendCenterViewState(FriendCenterViewState.Content);
            SetFriendCenterDegradedState(false);
            SetFriendCenterSection(FriendCenterSection.Search);
            SetFriendCenterStatus(
                _friendSearchResults.Length == 0 ? "没有找到匹配用户。" : $"找到 {_friendSearchResults.Length} 位用户。",
                _friendSearchResults.Length == 0 ? StatusPalette.DisabledBrush : StatusPalette.InfoBrush);
        }
        catch (Exception ex)
        {
            var failure = UserFacingError.Describe(ex, "暂时无法查找用户，请稍后重试。");
            if (_friendCenterSnapshot is null)
            {
                SetFriendCenterViewState(FriendCenterViewState.Error, failure);
            }
            SetFriendCenterStatus(failure, StatusPalette.DangerBrush);
        }
    }

    private async void FriendCenterRowActionButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.Button { DataContext: FriendCenterRow row } button ||
            button.Tag is not string action ||
            string.IsNullOrWhiteSpace(action))
        {
            return;
        }

        if (IsFriendCenterAcceptanceMode)
        {
            SetFriendCenterStatus("模拟场景不会修改好友关系，也不会打开真实资料或会话。", StatusPalette.InfoBrush);
            return;
        }

        if (action == "profile")
        {
            await OpenFriendProfileAsync(row);
            return;
        }

        if (action == "chat")
        {
            await OpenFriendChatAsync(row.User);
            return;
        }

        if (!await ConfirmFriendActionIfRequiredAsync(row, action))
        {
            return;
        }

        await MutateFriendRelationshipAsync(row.AccountId, action);
    }

    private Task<bool> ConfirmFriendActionIfRequiredAsync(FriendCenterRow row, string action) => action switch
    {
        FriendActions.Remove => ShowAppConfirmationAsync(
            "删除好友",
            $"删除好友 {row.Callsign}？",
            "删除后双方将不再出现在好友列表中；之后仍可重新发送申请。",
            "删除好友",
            "保留好友",
            footerText: "不会改变对方的个人资料或舰队关系。"),
        FriendActions.Block => ShowAppConfirmationAsync(
            "屏蔽用户",
            $"屏蔽 {row.Callsign}？",
            "现有好友或申请关系会被移除，对方无法再向你发送好友申请。",
            "屏蔽用户",
            "取消",
            footerText: "你可以稍后在好友中心解除屏蔽。"),
        _ => Task.FromResult(true)
    };

    private async Task<bool> MutateFriendRelationshipAsync(string targetAccountId, string action)
    {
        if (IsFriendCenterAcceptanceMode)
        {
            SetFriendCenterStatus("模拟场景不会修改好友关系。", StatusPalette.InfoBrush);
            return false;
        }

        var session = _accountSessionCoordinator.Capture();
        if (!_mutatingFriendRelationshipSessions.Add(session))
        {
            return false;
        }

        try
        {
            using var response = await _relayClient.PostJsonAsync(
                "api/friends/actions",
                new FriendActionRequestContract(
                     action,
                     targetAccountId,
                     GetPresenceSharingDecision().CanReceiveRealtime));
            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return false;
            }

            if (!response.IsSuccessStatusCode)
            {
                var error = await ReadResponseErrorAsync(response);
                if (_accountSessionCoordinator.IsCurrent(session))
                {
                    SetFriendCenterStatus(error, StatusPalette.DangerBrush);
                }

                return false;
            }

            var snapshot = await response.Content.ReadFromJsonAsync<FriendCenterSnapshotContract>();
            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return false;
            }

            if (snapshot is not null)
            {
                ApplyFriendCenterSnapshot(snapshot);
            }

            var nextSection = action switch
            {
                FriendActions.Accept => FriendCenterSection.Friends,
                FriendActions.Send or FriendActions.Cancel => FriendCenterSection.Outgoing,
                FriendActions.Block or FriendActions.Unblock => FriendCenterSection.Blocked,
                FriendActions.Reject => FriendCenterSection.Incoming,
                _ => _friendCenterSection
            };
            SetFriendCenterSection(nextSection);
            SetFriendCenterStatus(GetFriendActionSuccessCopy(action), StatusPalette.SuccessBrush);
            return true;
        }
        catch (Exception ex)
        {
            if (_accountSessionCoordinator.IsCurrent(session))
            {
                SetFriendCenterStatus(
                    UserFacingError.Describe(ex, "好友操作未完成，请稍后重试。"),
                    StatusPalette.DangerBrush);
            }

            return false;
        }
        finally
        {
            _mutatingFriendRelationshipSessions.Remove(session);
        }
    }

    private async Task OpenFriendProfileAsync(FriendCenterRow row)
    {
        var target = new PlayerRow(
            row.GameId,
            PlayerPresence.IsOnline(row.Presence) ? "Online" : "Offline",
            "Unknown",
            "飞船：未知",
            "地点：未知星域",
            row.Callsign,
            row.AvatarSource,
            row.Initials,
            ShowMemberActions: false,
            LiveStatus: PlayerPresence.ToWireValue(row.Presence),
            AccountId: row.AccountId);
        await OpenPersonalProfileVisitorAsync(target);
    }

    private async Task OpenFriendChatAsync(
        FriendUserContract user,
        string origin = DirectMessageOrigins.FriendCenter)
    {
        if (_isPersonalProfileVisitorMode)
        {
            ExitPersonalProfileVisitorMode(restoreReturnTab: false);
        }

        var previousTab = MainTabs.SelectedItem;
        MainTabs.SelectedItem = FriendCenterTab;
        SetActiveNav(HeaderFriendCenterButton);
        QueueMainPageReveal(previousTab);
        _activeFriendChatUser = FriendCenterUserResolver.Resolve(user, _networkSnapshots.Values);
        _activeFriendChatOrigin = DirectMessageOrigins.Normalize(origin);
        _activeFriendChatConversation = new FriendChatConversationContract(
            _activeFriendChatUser,
            "",
            default,
            "",
            0,
            0,
            user.RelationshipState == FriendRelationshipStates.Friend
                ? DirectMessageConversationStates.Friend
                : DirectMessageConversationStates.None,
            new DirectMessageContextContract(_activeFriendChatOrigin));
        _friendChatLatestSequence = 0;
        _friendChatMessages.Clear();
        ResetFriendChatPagingState();
        SetFriendCenterSection(FriendCenterSection.Conversations);
        RenderActiveFriendChat();
        EnsureActiveFriendChatConversationRow();
        SelectActiveFriendChatConversation();
        await RefreshFriendChatMessagesAsync(showErrors: true);
    }

    private async Task OpenDirectMessageAsync(PlayerRow target, string origin)
    {
        if (!CanSynchronizeUserData || string.IsNullOrWhiteSpace(target.AccountId))
        {
            return;
        }

        var relationship = ResolveFriendRelationshipState(target.AccountId);
        if (relationship == FriendRelationshipStates.Blocked)
        {
            SetFriendCenterStatus("请先解除屏蔽，再与该用户对话。", StatusPalette.WarningBrush);
            return;
        }

        var callsign = string.IsNullOrWhiteSpace(target.Callsign) ? target.Name : target.Callsign;
        var user = new FriendUserContract(
            target.AccountId,
            callsign ?? target.Name,
            target.Name,
            target.AvatarPath,
            PlayerPresence.ToWireValue(target.SharedPresence),
            relationship,
            DateTimeOffset.UtcNow);
        await OpenFriendChatAsync(user, origin);
    }

    private async Task RefreshFriendChatAsync(bool showErrors)
    {
        if (IsFriendCenterAcceptanceMode)
        {
            return;
        }

        if (!CanSynchronizeUserData)
        {
            return;
        }

        var session = _accountSessionCoordinator.Capture();
        if (!_refreshingFriendChatSessions.Add(session))
        {
            return;
        }

        try
        {
            var includePresence = GetPresenceSharingDecision().CanReceiveRealtime.ToString().ToLowerInvariant();
            var snapshot = await _relayClient.GetFromJsonAsync<FriendChatConversationListContract>(
                $"api/friends/chat/conversations?includePresence={includePresence}");
            if (snapshot is null)
            {
                throw new InvalidDataException("私聊会话数据为空。");
            }

            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return;
            }

            var activeId = _activeFriendChatUser?.AccountId;
            var visibleConversationId =
                ReferenceEquals(MainTabs.SelectedItem, FriendCenterTab) &&
                _friendCenterSection == FriendCenterSection.Conversations &&
                IsActive ||
                _inGameMenuCoordinator.IsSocialConversationVisible(activeId)
                ? activeId
                : null;
            var communicationEvents = _friendOverlayNotificationTracker.ObserveConversations(
                snapshot,
                _accountId,
                visibleConversationId,
                CanSynchronizeUserData,
                _overlaySettings.CommunicationMessagePreview,
                _language);
            _friendChatConversations.Clear();
            foreach (var conversation in snapshot.Conversations)
            {
                var resolved = conversation with
                {
                    User = FriendCenterUserResolver.Resolve(conversation.User, _networkSnapshots.Values)
                };
                _friendChatConversations.Add(new FriendChatConversationRow(resolved));
                if (!string.IsNullOrWhiteSpace(activeId) &&
                    resolved.User.AccountId.Equals(activeId, StringComparison.OrdinalIgnoreCase))
                {
                    _activeFriendChatUser = resolved.User;
                    _activeFriendChatConversation = resolved;
                    _activeFriendChatOrigin = DirectMessageOrigins.Normalize(resolved.Context?.Origin);
                }
            }

            FriendCenterConversationUnreadText.Text = snapshot.TotalUnread > 99 ? "99+" : snapshot.TotalUnread.ToString();
            FriendCenterConversationUnreadBadge.Visibility = snapshot.TotalUnread > 0
                ? Visibility.Visible
                : Visibility.Collapsed;
            RefreshNavigationActivityBadges();
            EnsureActiveFriendChatConversationRow();
            SelectActiveFriendChatConversation();
            FriendChatConversationEmptyState.Visibility = _friendChatConversations.Count == 0
                ? Visibility.Visible
                : Visibility.Collapsed;
            RenderActiveFriendChat();
            if (_activeFriendChatUser is not null)
            {
                await RefreshFriendChatMessagesAsync(showErrors);
            }

            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return;
            }

            QueueFriendCommunicationEvents(communicationEvents);
        }
        catch (Exception ex)
        {
            if (_accountSessionCoordinator.IsCurrent(session) && showErrors)
            {
                FriendChatStatusText.Text = UserFacingError.Describe(ex, "私聊暂时无法同步，请稍后重试。");
                FriendChatStatusText.Foreground = StatusPalette.DangerBrush;
            }
        }
        finally
        {
            _refreshingFriendChatSessions.Remove(session);
            if (_accountSessionCoordinator.IsCurrent(session))
            {
                RefreshInGameSocialSnapshot();
            }
        }
    }

    private void QueueFriendCommunicationEvents(IEnumerable<FriendCommunicationEvent> communicationEvents)
    {
        var events = communicationEvents.ToArray();
        if (_inGameMenuCoordinator.IsOpen &&
            _inGameMenuSettings.ShowSocialNotifications &&
            events.Length > 0)
        {
            foreach (var communicationEvent in events)
            {
                var detail = _inGameMenuSettings.InvitationPreviewMode switch
                {
                    InGameMenuInvitationPreviewMode.Hidden => null,
                    InGameMenuInvitationPreviewMode.SenderOnly =>
                        communicationEvent.Detail
                            .Split('·', 2, StringSplitOptions.TrimEntries)[0],
                    _ => communicationEvent.Detail
                };
                _inGameMenuCoordinator.ShowNotice(
                    communicationEvent.Title,
                    detail);
            }

            if (_inGameMenuSettings.SocialNotificationSound)
            {
                System.Media.SystemSounds.Asterisk.Play();
            }
        }

        if (!_overlaySettings.ShowNotice ||
            !_overlaySettings.CommunicationFriendEvents ||
            _overlayWindow is not { IsVisible: true })
        {
            return;
        }

        foreach (var communicationEvent in events)
        {
            _overlayWindow.QueueCommunicationEvent(communicationEvent.Title, communicationEvent.Detail);
        }
    }

    private void EnsureActiveFriendChatConversationRow()
    {
        if (_activeFriendChatUser is null || _friendChatConversations.Any(row =>
                row.AccountId.Equals(_activeFriendChatUser.AccountId, StringComparison.OrdinalIgnoreCase)))
        {
            return;
        }

        _friendChatConversations.Insert(0, new FriendChatConversationRow(
            _activeFriendChatConversation ?? new FriendChatConversationContract(
                _activeFriendChatUser,
                "",
                default,
                "",
                0,
                0,
                _activeFriendChatUser.RelationshipState == FriendRelationshipStates.Friend
                    ? DirectMessageConversationStates.Friend
                    : DirectMessageConversationStates.None,
                new DirectMessageContextContract(_activeFriendChatOrigin))));
    }

    private void SelectActiveFriendChatConversation()
    {
        if (_activeFriendChatUser is null)
        {
            return;
        }

        var row = _friendChatConversations.FirstOrDefault(candidate =>
            candidate.AccountId.Equals(_activeFriendChatUser.AccountId, StringComparison.OrdinalIgnoreCase));
        if (row is null)
        {
            return;
        }

        _isSelectingFriendChatConversation = true;
        FriendChatConversationList.SelectedItem = row;
        _isSelectingFriendChatConversation = false;
    }

    private void FriendChatConversationList_PreviewMouseLeftButtonDown(
        object sender,
        MouseButtonEventArgs e)
    {
        _pendingFriendChatConversationAccountId = null;
        if (e.ChangedButton != MouseButton.Left ||
            FindVisualParent<ListBoxItem>(e.OriginalSource as DependencyObject) is not
            { DataContext: FriendChatConversationRow row })
        {
            return;
        }

        _pendingFriendChatConversationAccountId = row.AccountId;
        _friendChatConversationPressPoint = e.GetPosition(FriendChatConversationList);
        e.Handled = true;
        if (!Mouse.Capture(FriendChatConversationList, CaptureMode.SubTree))
        {
            _pendingFriendChatConversationAccountId = null;
        }
    }

    private async void FriendChatConversationList_PreviewMouseLeftButtonUp(
        object sender,
        MouseButtonEventArgs e)
    {
        var pendingAccountId = _pendingFriendChatConversationAccountId;
        _pendingFriendChatConversationAccountId = null;
        try
        {
            if (e.ChangedButton != MouseButton.Left || string.IsNullOrWhiteSpace(pendingAccountId))
            {
                return;
            }

            e.Handled = true;
            var releasePoint = e.GetPosition(FriendChatConversationList);
            if (FindVisualParent<ListBoxItem>(FriendChatConversationList.InputHitTest(releasePoint) as DependencyObject) is not
                { DataContext: FriendChatConversationRow row } ||
                !row.AccountId.Equals(pendingAccountId, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            if (Math.Abs(releasePoint.X - _friendChatConversationPressPoint.X) >
                    SystemParameters.MinimumHorizontalDragDistance ||
                Math.Abs(releasePoint.Y - _friendChatConversationPressPoint.Y) >
                    SystemParameters.MinimumVerticalDragDistance)
            {
                return;
            }

            await CommitFriendChatConversationSelectionAsync(row);
        }
        finally
        {
            if (ReferenceEquals(Mouse.Captured, FriendChatConversationList))
            {
                FriendChatConversationList.ReleaseMouseCapture();
            }
        }
    }

    private void FriendChatConversationList_LostMouseCapture(
        object sender,
        System.Windows.Input.MouseEventArgs e)
    {
        _pendingFriendChatConversationAccountId = null;
    }

    private async Task CommitFriendChatConversationSelectionAsync(FriendChatConversationRow row)
    {
        var selectionMatches = FriendChatConversationList.SelectedItem is FriendChatConversationRow selected &&
                               selected.AccountId.Equals(row.AccountId, StringComparison.OrdinalIgnoreCase);
        var activeConversationMatches = _activeFriendChatUser?.AccountId.Equals(
            row.AccountId,
            StringComparison.OrdinalIgnoreCase) == true;
        if (selectionMatches && activeConversationMatches)
        {
            return;
        }

        _isSelectingFriendChatConversation = true;
        try
        {
            FriendChatConversationList.SelectedItem = row;
        }
        finally
        {
            _isSelectingFriendChatConversation = false;
        }

        FriendChatConversationList.ScrollIntoView(row);
        await ActivateFriendChatConversationAsync(row);
    }

    private async void FriendChatConversationList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isSelectingFriendChatConversation || FriendChatConversationList.SelectedItem is not FriendChatConversationRow row)
        {
            return;
        }

        await ActivateFriendChatConversationAsync(row);
    }

    private async Task ActivateFriendChatConversationAsync(FriendChatConversationRow row)
    {
        _activeFriendChatUser = row.User;
        _activeFriendChatConversation = row.Conversation;
        _activeFriendChatOrigin = DirectMessageOrigins.Normalize(row.Conversation.Context?.Origin);
        _friendChatLatestSequence = 0;
        _friendChatMessages.Clear();
        ResetFriendChatPagingState();
        RenderActiveFriendChat();
        if (IsFriendCenterAcceptanceMode)
        {
            SelectFriendAcceptanceConversation(row);
            return;
        }

        await RefreshFriendChatMessagesAsync(showErrors: true);
    }

    private async Task RefreshFriendChatMessagesAsync(bool showErrors)
    {
        if (IsFriendCenterAcceptanceMode)
        {
            return;
        }

        if (_activeFriendChatUser is null || !CanSynchronizeUserData)
        {
            return;
        }

        var session = _accountSessionCoordinator.Capture();
        var targetId = _activeFriendChatUser.AccountId;
        var lane = CreateFriendChatOperationLane(session, targetId);
        try
        {
            var wasEmpty = _friendChatMessages.Count == 0;
            var previousLatestSequence = _friendChatLatestSequence;
            var shouldFollowLatest = wasEmpty || _friendChatFollowLatest;
            var history = await _relayClient.GetFromJsonAsync<FriendChatHistoryContract>(
                $"api/friends/chat/messages?targetAccountId={Uri.EscapeDataString(targetId)}" +
                $"&after={_friendChatLatestSequence}&limit=50");
            if (history is null)
            {
                throw new InvalidDataException("私聊消息数据为空。");
            }

            if (!_accountSessionCoordinator.IsCurrent(session) ||
                _activeFriendChatUser is null ||
                !_activeFriendChatUser.AccountId.Equals(targetId, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            _activeFriendChatConversation = (_activeFriendChatConversation ?? new FriendChatConversationContract(
                _activeFriendChatUser,
                "",
                default,
                "",
                0,
                history.LatestSequence)) with
            {
                User = _activeFriendChatUser,
                LatestSequence = history.LatestSequence,
                ConversationState = history.ConversationState,
                Context = history.Context ?? _activeFriendChatConversation?.Context
            };
            _activeFriendChatOrigin = DirectMessageOrigins.Normalize(_activeFriendChatConversation.Context?.Origin);

            if (wasEmpty)
            {
                _friendChatHasOlder = history.HasOlder;
            }

            foreach (var message in history.Messages.OrderBy(message => message.Sequence))
            {
                if (_friendChatMessages.Any(row => row.Message.MessageId.Equals(message.MessageId, StringComparison.OrdinalIgnoreCase)))
                {
                    continue;
                }

                _friendChatMessages.Add(CreateFriendChatMessageRow(message, targetId));
                _friendChatLatestSequence = Math.Max(_friendChatLatestSequence, message.Sequence);
            }

            _friendChatLatestSequence = Math.Max(_friendChatLatestSequence, history.LatestSequence);
            FriendChatMessageEmptyState.Visibility = _friendChatMessages.Count == 0
                ? Visibility.Visible
                : Visibility.Collapsed;
            FriendChatMessageList.Visibility = _friendChatMessages.Count == 0
                ? Visibility.Collapsed
                : Visibility.Visible;
            FriendChatInputBox.IsEnabled = history.CanSend;
            FriendChatSendButton.IsEnabled = history.CanSend && !_isSendingFriendChatMessage;
            FriendChatAttachmentButton.IsEnabled = history.CanSend && !_isSendingFriendChatMessage;
            FriendChatStatusText.Text = history.CanSend ? "仅你与该好友可见" : history.Error ?? "当前无法发送";
            FriendChatStatusText.Foreground = history.CanSend ? StatusPalette.DisabledBrush : StatusPalette.WarningBrush;
            if (history.CanSend)
            {
                FriendChatStatusText.Text = "仅你与对方可见";
            }
            RenderActiveFriendChat();
            if (_friendChatMessages.Count > 0 && shouldFollowLatest)
            {
                _friendChatFollowLatest = true;
                ChatHistoryViewport.ScrollToLatest(FriendChatMessageList);
            }
            else if (_friendChatLatestSequence > previousLatestSequence)
            {
                FriendChatJumpToLatestButton.Visibility = Visibility.Visible;
            }

            if (history.CanSend && _friendChatLatestSequence > 0 &&
                (ReferenceEquals(MainTabs.SelectedItem, FriendCenterTab) &&
                 _friendCenterSection == FriendCenterSection.Conversations &&
                 IsActive ||
                 _inGameMenuCoordinator.IsSocialConversationVisible(targetId)))
            {
                using var readResponse = await _relayClient.PostJsonAsync(
                    "api/friends/chat/read",
                    new FriendChatMarkReadRequestContract(targetId, _friendChatLatestSequence));
            }
        }
        catch (Exception ex)
        {
            if (IsFriendChatOperationCurrent(lane) && showErrors)
            {
                FriendChatStatusText.Text = UserFacingError.Describe(ex, "消息暂时无法同步，请稍后重试。");
                FriendChatStatusText.Foreground = StatusPalette.DangerBrush;
            }
        }
        finally
        {
            if (IsFriendChatOperationCurrent(lane))
            {
                RefreshInGameSocialSnapshot();
            }
        }
    }

    private async void FriendChatMessageList_ScrollChanged(object sender, ScrollChangedEventArgs e)
    {
        if (e.OriginalSource is not ScrollViewer viewer)
        {
            return;
        }

        _friendChatFollowLatest = ChatHistoryViewport.IsNearBottom(viewer);
        FriendChatJumpToLatestButton.Visibility = _friendChatFollowLatest
            ? Visibility.Collapsed
            : Visibility.Visible;
        UpdateFriendChatHistoryStatus(viewer);
        if (ChatHistoryViewport.ShouldLoadOlder(viewer) && _friendChatHasOlder && !_isLoadingOlderFriendChat)
        {
            await LoadOlderFriendChatMessagesAsync();
        }
    }

    private async Task LoadOlderFriendChatMessagesAsync()
    {
        if (IsFriendCenterAcceptanceMode)
        {
            return;
        }

        if (_isLoadingOlderFriendChat || !_friendChatHasOlder || _activeFriendChatUser is null ||
            _friendChatMessages.Count == 0 || !CanSynchronizeUserData)
        {
            return;
        }

        var targetId = _activeFriendChatUser.AccountId;
        var before = _friendChatMessages.Min(row => row.Message.Sequence);
        _isLoadingOlderFriendChat = true;
        FriendChatHistoryStatusText.Text = "正在加载更早消息…";
        FriendChatHistoryStatusPanel.Visibility = ChatHistoryViewport.Find(FriendChatMessageList) is { } viewer &&
                                                  ChatHistoryViewport.IsNearTop(viewer)
            ? Visibility.Visible
            : Visibility.Collapsed;
        try
        {
            var history = await _relayClient.GetFromJsonAsync<FriendChatHistoryContract>(
                $"api/friends/chat/messages?targetAccountId={Uri.EscapeDataString(targetId)}" +
                $"&before={before}&limit=50");
            if (history is null || _activeFriendChatUser is null ||
                !_activeFriendChatUser.AccountId.Equals(targetId, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            var anchor = ChatHistoryViewport.Capture(FriendChatMessageList);
            var existingIds = _friendChatMessages
                .Select(row => row.Message.MessageId)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            var insertIndex = 0;
            foreach (var message in history.Messages.OrderBy(message => message.Sequence))
            {
                if (existingIds.Add(message.MessageId))
                {
                    _friendChatMessages.Insert(insertIndex++, CreateFriendChatMessageRow(message, targetId));
                }
            }

            _friendChatHasOlder = history.HasOlder;
            ChatHistoryViewport.RestoreAfterPrepend(FriendChatMessageList, anchor);
        }
        catch
        {
            FriendChatStatusText.Text = "更早消息加载失败，滚到顶部可重试。";
            FriendChatStatusText.Foreground = StatusPalette.WarningBrush;
        }
        finally
        {
            _isLoadingOlderFriendChat = false;
            UpdateFriendChatHistoryStatus(ChatHistoryViewport.Find(FriendChatMessageList));
        }
    }

    private void UpdateFriendChatHistoryStatus(ScrollViewer? viewer)
    {
        var atTop = viewer is not null && ChatHistoryViewport.IsNearTop(viewer);
        if (_isLoadingOlderFriendChat)
        {
            FriendChatHistoryStatusText.Text = "正在加载更早消息…";
            FriendChatHistoryStatusPanel.Visibility = atTop ? Visibility.Visible : Visibility.Collapsed;
            return;
        }

        FriendChatHistoryStatusPanel.Visibility = Visibility.Collapsed;
    }

    private void FriendChatJumpToLatestButton_Click(object sender, RoutedEventArgs e)
    {
        _friendChatFollowLatest = true;
        FriendChatJumpToLatestButton.Visibility = Visibility.Collapsed;
        ChatHistoryViewport.ScrollToLatest(FriendChatMessageList);
    }

    private void ResetFriendChatPagingState()
    {
        _friendChatHasOlder = false;
        _isLoadingOlderFriendChat = false;
        _friendChatFollowLatest = true;
        if (FriendChatHistoryStatusPanel is not null)
        {
            FriendChatHistoryStatusPanel.Visibility = Visibility.Collapsed;
            FriendChatJumpToLatestButton.Visibility = Visibility.Collapsed;
        }
    }

    private async void FriendChatSendButton_Click(object sender, RoutedEventArgs e)
    {
        await SendFriendChatMessageAsync(FriendChatInputBox.Text.Trim(), null);
    }

    private async Task SendFriendChatMessageAsync(string text, ChatAttachmentContract? attachment)
    {
        if (IsFriendCenterAcceptanceMode)
        {
            FriendChatStatusText.Text = "模拟场景不会发送消息。";
            FriendChatStatusText.Foreground = StatusPalette.InfoBrush;
            return;
        }

        var activeUser = _activeFriendChatUser;
        if (activeUser is null || !CanSynchronizeUserData)
        {
            return;
        }

        if (text.Length == 0 && attachment is null)
        {
            FriendChatStatusText.Text = "输入消息后再发送";
            FriendChatStatusText.Foreground = StatusPalette.WarningBrush;
            return;
        }

        var session = _accountSessionCoordinator.Capture();
        var targetAccountId = activeUser.AccountId;
        var origin = _activeFriendChatOrigin;
        var lane = CreateFriendChatOperationLane(session, targetAccountId);
        if (!_sendingFriendChatMessageLanes.Add(lane))
        {
            return;
        }

        FriendChatSendButton.IsEnabled = false;
        FriendChatAttachmentButton.IsEnabled = false;
        try
        {
            using var response = await _relayClient.PostJsonAsync(
                "api/friends/chat/messages",
                new FriendChatSendRequestContract(
                    targetAccountId,
                    text,
                    Guid.NewGuid().ToString("N"),
                    origin,
                    attachment));
            var mutation = await response.Content.ReadFromJsonAsync<FriendChatMutationResponseContract>();
            if (!IsFriendChatOperationCurrent(lane))
            {
                return;
            }

            if (!response.IsSuccessStatusCode || mutation?.Message is null)
            {
                var error = mutation?.Error ?? await ReadResponseErrorAsync(response);
                if (!IsFriendChatOperationCurrent(lane))
                {
                    return;
                }

                FriendChatStatusText.Text = error;
                FriendChatStatusText.Foreground = StatusPalette.DangerBrush;
                return;
            }

            if (!_friendChatMessages.Any(row => row.Message.MessageId.Equals(mutation.Message.MessageId, StringComparison.OrdinalIgnoreCase)))
            {
                _friendChatMessages.Add(CreateFriendChatMessageRow(
                    mutation.Message,
                    targetAccountId));
            }
            _friendChatLatestSequence = Math.Max(_friendChatLatestSequence, mutation.Message.Sequence);
            FriendChatInputBox.Clear();
            FriendChatMessageEmptyState.Visibility = Visibility.Collapsed;
            FriendChatMessageList.Visibility = Visibility.Visible;
            _friendChatFollowLatest = true;
            FriendChatJumpToLatestButton.Visibility = Visibility.Collapsed;
            ChatHistoryViewport.ScrollToLatest(FriendChatMessageList);
            FriendChatStatusText.Text = "已发送";
            FriendChatStatusText.Foreground = StatusPalette.SuccessBrush;
            await RefreshFriendChatAsync(showErrors: false);
            if (!IsFriendChatOperationCurrent(lane))
            {
                return;
            }

            if (mutation.Status == "request_sent")
            {
                FriendChatStatusText.Text = "消息请求已发送，接受前不能继续发送。";
                FriendChatStatusText.Foreground = StatusPalette.InfoBrush;
            }
            if (FriendChatInputBox.IsEnabled)
            {
                FriendChatInputBox.Focus();
            }
        }
        catch (Exception ex)
        {
            if (IsFriendChatOperationCurrent(lane))
            {
                FriendChatStatusText.Text = UserFacingError.Describe(ex, "消息未发送，请检查网络后重试。");
                FriendChatStatusText.Foreground = StatusPalette.DangerBrush;
            }
        }
        finally
        {
            _sendingFriendChatMessageLanes.Remove(lane);
            if (IsFriendChatOperationCurrent(lane))
            {
                RenderActiveFriendChat();
                RefreshInGameSocialSnapshot();
            }
        }
    }

    private void FriendChatInputBox_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key != Key.Enter || Keyboard.Modifiers.HasFlag(ModifierKeys.Shift))
        {
            return;
        }

        e.Handled = true;
        FriendChatSendButton_Click(FriendChatSendButton, new RoutedEventArgs());
    }

    private FriendChatMessageRow CreateFriendChatMessageRow(
        FriendChatMessageContract message,
        string targetAccountId)
    {
        var isLocal = !message.SenderAccountId.Equals(targetAccountId, StringComparison.OrdinalIgnoreCase);
        var senderCallsign = isLocal
            ? string.IsNullOrWhiteSpace(_callsign) ? _localPlayer ?? "我" : _callsign
            : _activeFriendChatUser?.Callsign ?? "未知用户";
        var senderGameId = isLocal
            ? _localPlayer ?? ""
            : _activeFriendChatUser?.GameId ?? "";
        var senderAvatar = isLocal
            ? BuildAvatarImageData()
            : _activeFriendChatUser?.AvatarImageData;

        return new FriendChatMessageRow(
            message,
            isLocal,
            senderCallsign,
            senderGameId,
            senderAvatar,
            ChatPresentationBrushes.ResolveSenderRole(this, isLocal, publishedColor: null),
            ChatPresentationBrushes.ResolveAttachmentStatus(this, message.Attachment));
    }

    private async void FriendChatSelectedProfileButton_Click(object sender, RoutedEventArgs e)
    {
        if (IsFriendCenterAcceptanceMode)
        {
            FriendChatStatusText.Text = "模拟场景不会打开真实个人资料。";
            FriendChatStatusText.Foreground = StatusPalette.InfoBrush;
            return;
        }

        if (_activeFriendChatUser is not null)
        {
            await OpenFriendProfileAsync(new FriendCenterRow(_activeFriendChatUser, default));
        }
    }

    private async void FriendChatRequestActionButton_Click(object sender, RoutedEventArgs e)
    {
        if (IsFriendCenterAcceptanceMode)
        {
            FriendChatStatusText.Text = "模拟场景不会处理真实消息请求。";
            FriendChatStatusText.Foreground = StatusPalette.InfoBrush;
            return;
        }

        if (_activeFriendChatUser is null ||
            sender is not System.Windows.Controls.Button { Tag: string action } ||
            action is not (DirectMessageRequestActions.Accept or DirectMessageRequestActions.Reject or DirectMessageRequestActions.Block))
        {
            return;
        }

        if (action == DirectMessageRequestActions.Block &&
            !await ShowAppConfirmationAsync(
                "屏蔽用户",
                $"屏蔽 {_activeFriendChatUser.Callsign}？",
                "该消息请求会被移除，对方也无法继续向你发送好友申请或私信。",
                "屏蔽用户",
                "取消",
                footerText: "你之后可以在好友中心的“已屏蔽”中解除屏蔽。"))
        {
            return;
        }

        FriendChatRequestActionsPanel.IsEnabled = false;
        try
        {
            using var response = await _relayClient.PostJsonAsync(
                "api/friends/chat/requests",
                new DirectMessageRequestActionContract(_activeFriendChatUser.AccountId, action));
            if (!response.IsSuccessStatusCode)
            {
                FriendChatStatusText.Text = await ReadResponseErrorAsync(response);
                FriendChatStatusText.Foreground = StatusPalette.DangerBrush;
                return;
            }

            var result = await response.Content.ReadFromJsonAsync<DirectMessageRequestActionResponseContract>();
            if (action == DirectMessageRequestActions.Accept)
            {
                _activeFriendChatConversation = _activeFriendChatConversation is null
                    ? null
                    : _activeFriendChatConversation with { ConversationState = result?.ConversationState ?? DirectMessageConversationStates.Accepted };
                await RefreshFriendChatAsync(showErrors: true);
                FriendChatStatusText.Text = "已接受消息请求，可以开始回复。";
                FriendChatStatusText.Foreground = StatusPalette.SuccessBrush;
                return;
            }

            _activeFriendChatUser = null;
            _activeFriendChatConversation = null;
            _friendChatMessages.Clear();
            ResetFriendChatPagingState();
            await RefreshFriendCenterAsync(showErrors: false);
            await RefreshFriendChatAsync(showErrors: true);
            RenderActiveFriendChat();
        }
        catch (Exception ex)
        {
            FriendChatStatusText.Text = UserFacingError.Describe(ex, "消息请求未能处理，请稍后重试。");
            FriendChatStatusText.Foreground = StatusPalette.DangerBrush;
        }
        finally
        {
            FriendChatRequestActionsPanel.IsEnabled = true;
        }
    }

    private void RenderActiveFriendChat()
    {
        var hasActive = _activeFriendChatUser is not null;
        FriendChatNoSelectionState.Visibility = hasActive ? Visibility.Collapsed : Visibility.Visible;
        FriendChatActivePanel.Visibility = hasActive ? Visibility.Visible : Visibility.Collapsed;
        if (!hasActive)
        {
            return;
        }

        var user = _activeFriendChatUser!;
        var presence = PlayerPresencePresentation.ResolveShared(user.Presence, user.Presence);
        FriendChatSelectedCallsignText.Text = user.Callsign;
        FriendChatSelectedGameIdText.Text = user.GameId;
        FriendChatSelectedPresenceText.Text = PlayerPresencePresentation.Format(presence);
        FriendChatSelectedPresenceText.Foreground = PlayerPresencePresentation.Brush(presence);
        var conversationState = _activeFriendChatConversation?.ConversationState ??
                                (user.RelationshipState == FriendRelationshipStates.Friend
                                    ? DirectMessageConversationStates.Friend
                                    : DirectMessageConversationStates.None);
        FriendChatSelectedRelationText.Text = DirectMessagePresentation.FormatState(conversationState);
        FriendChatSelectedContextText.Text = DirectMessagePresentation.FormatContext(_activeFriendChatConversation?.Context);
        FriendChatSelectedContextText.Visibility = string.IsNullOrWhiteSpace(FriendChatSelectedContextText.Text)
            ? Visibility.Collapsed
            : Visibility.Visible;
        FriendChatRequestActionsPanel.Visibility = conversationState == DirectMessageConversationStates.RequestIncoming
            ? Visibility.Visible
            : Visibility.Collapsed;
        FriendChatSelectedAvatarImage.Source = new ImageDataConverter().Convert(
            user.AvatarImageData ?? "",
            typeof(System.Windows.Media.ImageSource),
            96,
            System.Globalization.CultureInfo.CurrentCulture) as System.Windows.Media.ImageSource;
        FriendChatSelectedInitialsText.Visibility = FriendChatSelectedAvatarImage.Source is null
            ? Visibility.Visible
            : Visibility.Collapsed;
        FriendChatSelectedInitialsText.Content = new FriendChatConversationRow(new FriendChatConversationContract(
            user, "", default, "", 0, 0)).Initials;
        var canCompose = conversationState is DirectMessageConversationStates.None or
            DirectMessageConversationStates.Friend or DirectMessageConversationStates.Accepted;
        FriendChatInputBox.IsEnabled = CanSynchronizeUserData && canCompose;
        FriendChatSendButton.IsEnabled = CanSynchronizeUserData && canCompose && !_isSendingFriendChatMessage;
        FriendChatAttachmentButton.IsEnabled = CanSynchronizeUserData && canCompose && !_isSendingFriendChatMessage;
    }

    private void RefreshFriendPresenceFromFleetSnapshots()
    {
        var presenceChanged = false;
        for (var index = 0; index < _friendCenterRows.Count; index++)
        {
            var row = _friendCenterRows[index];
            var resolved = FriendCenterUserResolver.Resolve(row.User, _networkSnapshots.Values);
            if (!HasFriendPresenceProjectionChanged(row.User, resolved))
            {
                continue;
            }

            _friendCenterRows[index] = row with { User = resolved };
            presenceChanged = true;
        }

        for (var index = 0; index < _friendChatConversations.Count; index++)
        {
            var row = _friendChatConversations[index];
            var resolved = FriendCenterUserResolver.Resolve(row.User, _networkSnapshots.Values);
            if (!HasFriendPresenceProjectionChanged(row.User, resolved))
            {
                continue;
            }

            var conversation = row.Conversation with { User = resolved };
            _friendChatConversations[index] = new FriendChatConversationRow(conversation);
            if (_activeFriendChatConversation?.User.AccountId.Equals(
                    resolved.AccountId,
                    StringComparison.OrdinalIgnoreCase) == true)
            {
                _activeFriendChatConversation = conversation;
            }

            presenceChanged = true;
        }

        if (_activeFriendChatUser is not null)
        {
            var resolved = FriendCenterUserResolver.Resolve(
                _activeFriendChatUser,
                _networkSnapshots.Values);
            if (HasFriendPresenceProjectionChanged(_activeFriendChatUser, resolved))
            {
                _activeFriendChatUser = resolved;
                presenceChanged = true;
            }
        }

        if (!presenceChanged)
        {
            return;
        }

        RenderActiveFriendChat();
        RefreshInGameSocialSnapshot();
    }

    private static bool HasFriendPresenceProjectionChanged(
        FriendUserContract current,
        FriendUserContract resolved) =>
        !string.Equals(current.Presence, resolved.Presence, StringComparison.OrdinalIgnoreCase) ||
        !string.Equals(current.AvatarImageData, resolved.AvatarImageData, StringComparison.Ordinal);

    private void RefreshPersonalProfileFriendAction()
    {
        RefreshPersonalProfileReportAction();
        if (PersonalProfileFriendActionButton is null || PersonalProfileMessageButton is null)
        {
            return;
        }

        var accountId = _personalProfileVisitorTarget?.AccountId;
        if (!_isPersonalProfileVisitorMode || string.IsNullOrWhiteSpace(accountId))
        {
            PersonalProfileFriendActionButton.Visibility = Visibility.Collapsed;
            PersonalProfileMessageButton.Visibility = Visibility.Collapsed;
            return;
        }

        var state = ResolveFriendRelationshipState(accountId);
        PersonalProfileFriendActionButton.Tag = state switch
        {
            FriendRelationshipStates.Friend => "manage",
            FriendRelationshipStates.Incoming => FriendActions.Accept,
            FriendRelationshipStates.Outgoing => FriendActions.Cancel,
            FriendRelationshipStates.Blocked => FriendActions.Unblock,
            _ => FriendActions.Send
        };
        PersonalProfileFriendActionButton.Content = state switch
        {
            FriendRelationshipStates.Friend => "好友 · 管理",
            FriendRelationshipStates.Incoming => "接受好友申请",
            FriendRelationshipStates.Outgoing => "撤回好友申请",
            FriendRelationshipStates.Blocked => "解除屏蔽",
            _ => "添加好友"
        };
        PersonalProfileFriendActionButton.Visibility = Visibility.Visible;
        PersonalProfileFriendActionButton.IsEnabled = CanSynchronizeUserData;
        PersonalProfileMessageButton.Visibility = state == FriendRelationshipStates.Blocked
            ? Visibility.Collapsed
            : Visibility.Visible;
        PersonalProfileMessageButton.IsEnabled = CanSynchronizeUserData;
        PersonalProfileMessageButton.ToolTip = CanSynchronizeUserData
            ? "打开与该用户的私信"
            : "完成登录与身份验证后可以发送消息";
    }

    private async void PersonalProfileMessageButton_Click(object sender, RoutedEventArgs e)
    {
        if (_personalProfileVisitorTarget is not null)
        {
            await OpenDirectMessageAsync(_personalProfileVisitorTarget, DirectMessageOrigins.PersonalProfile);
        }
    }

    private async void PersonalProfileFriendActionButton_Click(object sender, RoutedEventArgs e)
    {
        if (_personalProfileVisitorTarget?.AccountId is not { Length: > 0 } accountId ||
            PersonalProfileFriendActionButton.Tag is not string action)
        {
            return;
        }

        if (action == "manage")
        {
            HeaderFriendCenterButton_Click(HeaderFriendCenterButton, new RoutedEventArgs());
            return;
        }

        await MutateFriendRelationshipAsync(accountId, action);
        RefreshPersonalProfileFriendAction();
    }

    private static string GetFriendActionSuccessCopy(string action) => action switch
    {
        FriendActions.Send => "好友申请已发送。",
        FriendActions.Accept => "已添加为好友。",
        FriendActions.Reject => "已拒绝好友申请。",
        FriendActions.Cancel => "好友申请已撤回。",
        FriendActions.Remove => "好友已删除。",
        FriendActions.Block => "用户已屏蔽。",
        FriendActions.Unblock => "已解除屏蔽。",
        _ => "好友关系已更新。"
    };

    private void ApplyFriendCenterSectionVisibility()
    {
        var systemStateVisible = FriendCenterSystemStatePanel.Visibility == Visibility.Visible;
        var showConversations = _friendCenterSection == FriendCenterSection.Conversations && !systemStateVisible;
        FriendCenterRelationshipPanel.Visibility = showConversations ? Visibility.Collapsed : Visibility.Visible;
        FriendChatWorkspace.Visibility = showConversations ? Visibility.Visible : Visibility.Collapsed;
    }

    private void SetFriendCenterViewState(FriendCenterViewState state, string? description = null)
    {
        if (state == FriendCenterViewState.Content)
        {
            FriendCenterSystemStatePanel.Visibility = Visibility.Collapsed;
            ApplyFriendCenterSectionVisibility();
            return;
        }

        var presentation = state switch
        {
            FriendCenterViewState.Loading => (
                Controls.BridgeStateKind.Loading,
                "正在同步好友",
                "正在读取好友、申请与在线状态。",
                string.Empty),
            FriendCenterViewState.NoPermission => (
                Controls.BridgeStateKind.AccessDenied,
                "登录后查看好友",
                "登录并完成账号识别后，即可同步好友、申请与私信。",
                string.Empty),
            _ => (
                Controls.BridgeStateKind.Error,
                "暂时无法同步好友",
                description ?? "请检查网络连接后重试。",
                "重试")
        };

        FriendCenterSystemStatePanel.State = presentation.Item1;
        FriendCenterSystemStatePanel.TitleOverride = presentation.Item2;
        FriendCenterSystemStatePanel.DescriptionOverride = presentation.Item3;
        FriendCenterSystemStatePanel.ActionTextOverride = presentation.Item4;
        FriendCenterSystemStatePanel.Visibility = Visibility.Visible;
        ApplyFriendCenterSectionVisibility();
    }

    private void SetFriendCenterDegradedState(bool visible, string? message = null)
    {
        if (!string.IsNullOrWhiteSpace(message))
        {
            FriendCenterDegradedText.Text = message;
        }

        FriendCenterDegradedBanner.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
    }

    private void ApplyFriendCenterCountVisuals(int friends, int incoming, int outgoing, int blocked)
    {
        ApplyFriendCenterCountVisual(FriendCenterFriendsCountText, friends, "BridgeInk2");
        ApplyFriendCenterCountVisual(FriendCenterIncomingCountText, incoming, "BridgeStatusWarn");
        ApplyFriendCenterCountVisual(FriendCenterOutgoingCountText, outgoing, "BridgeInk2");
        ApplyFriendCenterCountVisual(FriendCenterBlockedCountText, blocked, "BridgeInk2");
    }

    private void ApplyFriendCenterCountVisual(TextBlock target, int count, string activeBrushKey)
    {
        var brushKey = count == 0 ? "BridgeInk3" : activeBrushKey;
        if (TryFindResource(brushKey) is System.Windows.Media.Brush brush)
        {
            target.Foreground = brush;
        }
    }

    private void SetFriendCenterStatus(string text, System.Windows.Media.Brush brush)
    {
        FriendCenterStatusText.Text = text;
        FriendCenterStatusText.Foreground = brush;
    }
}
