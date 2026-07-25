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
    private readonly ObservableCollection<FriendCenterRow> _friendCenterRows = [];
    private readonly ObservableCollection<FriendChatConversationRow> _friendChatConversations = [];
    private readonly ObservableCollection<FriendChatMessageRow> _friendChatMessages = [];
    private readonly FriendOverlayNotificationTracker _friendOverlayNotificationTracker = new();
    private readonly DispatcherTimer _friendCenterRefreshTimer = new() { Interval = TimeSpan.FromSeconds(20) };
    private readonly DispatcherTimer _friendChatRefreshTimer = new() { Interval = TimeSpan.FromSeconds(5) };
    private CancellationTokenSource? _socialActivityCts;
    private Task? _socialActivityLoopTask;
    private string _socialActivityInstanceId = "";
    private long _socialActivityVersion = -1;
    private FriendCenterSnapshotContract? _friendCenterSnapshot;
    private FriendUserContract[] _friendSearchResults = [];
    private FriendCenterSection _friendCenterSection = FriendCenterSection.Friends;
    private bool _isRefreshingFriendCenter;
    private bool _isMutatingFriendRelationship;
    private bool _isRefreshingFriendChat;
    private bool _isSendingFriendChatMessage;
    private bool _isSelectingFriendChatConversation;
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
    private bool CanConfigureDirectMessagePrivacy =>
        DirectMessagePrivacyAvailabilityPolicy.CanConfigure(IsLoggedIn, CanSynchronizeUserData);

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
        RefreshNavigationActivityBadges();
        RenderFriendCenterSection();
        RenderActiveFriendChat();
        RefreshPersonalProfileFriendAction();
        ApplyDirectMessagePrivacyToControls();
        SetFriendCenterStatus("登录后即可同步好友与私聊。", StatusPalette.DisabledBrush);
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
                        RefreshFriendChatAsync(showErrors: false));
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
        if (_isRefreshingFriendCenter)
        {
            return;
        }

        if (!CanSynchronizeUserData)
        {
            SetFriendCenterStatus("登录后即可同步好友与申请。", StatusPalette.DisabledBrush);
            return;
        }

        var session = _accountSessionCoordinator.Capture();
        _isRefreshingFriendCenter = true;
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

            ApplyFriendCenterSnapshot(snapshot);
            SetFriendCenterStatus($"已同步 · {snapshot.RefreshedAt.ToLocalTime():HH:mm:ss}", StatusPalette.SuccessBrush);
        }
        catch (Exception ex)
        {
            if (showErrors)
            {
                SetFriendCenterStatus(UserFacingError.Describe(ex, "好友数据暂时无法同步，请稍后重试。"), StatusPalette.DangerBrush);
            }
        }
        finally
        {
            _isRefreshingFriendCenter = false;
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
        RefreshNavigationActivityBadges();
        RenderFriendCenterSection();
        RefreshPersonalProfileFriendAction();
        QueueFriendCommunicationEvents(communicationEvents);
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
        FriendCenterRelationshipPanel.Visibility = section == FriendCenterSection.Conversations
            ? Visibility.Collapsed
            : Visibility.Visible;
        FriendChatWorkspace.Visibility = section == FriendCenterSection.Conversations
            ? Visibility.Visible
            : Visibility.Collapsed;
        if (section == FriendCenterSection.Conversations)
        {
            _ = RefreshFriendChatAsync(showErrors: true);
        }
        else
        {
            RenderFriendCenterSection();
        }

        var activePanel = section == FriendCenterSection.Conversations
            ? FriendChatWorkspace
            : FriendCenterRelationshipPanel;
        activePanel.Dispatcher.BeginInvoke(
            DispatcherPriority.Loaded,
            new Action(() => UiMotion.RevealContent(activePanel, UiMotionRevealDirection.FromRight)));
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
            var user = FriendCenterAvatarResolver.Resolve(entry.User, _networkSnapshots.Values);
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
        var query = FriendSearchBox.Text.Trim();
        if (query.Length < 2)
        {
            SetFriendCenterStatus("请输入至少 2 个字符搜索呼号或游戏 ID。", StatusPalette.WarningBrush);
            return;
        }

        if (!CanSynchronizeUserData)
        {
            SetFriendCenterStatus("请先登录，再查找用户。", StatusPalette.WarningBrush);
            return;
        }

        try
        {
            var response = await _relayClient.GetFromJsonAsync<FriendSearchResponseContract>(
                $"api/friends/search?q={Uri.EscapeDataString(query)}&includePresence={GetPresenceSharingDecision().CanReceiveRealtime.ToString().ToLowerInvariant()}");
            _friendSearchResults = response?.Results ?? [];
            SetFriendCenterSection(FriendCenterSection.Search);
            SetFriendCenterStatus(
                _friendSearchResults.Length == 0 ? "没有找到匹配用户。" : $"找到 {_friendSearchResults.Length} 位用户。",
                _friendSearchResults.Length == 0 ? StatusPalette.DisabledBrush : StatusPalette.InfoBrush);
        }
        catch (Exception ex)
        {
            SetFriendCenterStatus(UserFacingError.Describe(ex, "暂时无法查找用户，请稍后重试。"), StatusPalette.DangerBrush);
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

    private async Task MutateFriendRelationshipAsync(string targetAccountId, string action)
    {
        if (_isMutatingFriendRelationship)
        {
            return;
        }

        _isMutatingFriendRelationship = true;
        try
        {
            using var response = await _relayClient.PostJsonAsync(
                "api/friends/actions",
                new FriendActionRequestContract(
                    action,
                    targetAccountId,
                    GetPresenceSharingDecision().CanReceiveRealtime));
            if (!response.IsSuccessStatusCode)
            {
                SetFriendCenterStatus(await ReadResponseErrorAsync(response), StatusPalette.DangerBrush);
                return;
            }

            var snapshot = await response.Content.ReadFromJsonAsync<FriendCenterSnapshotContract>();
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
        }
        catch (Exception ex)
        {
            SetFriendCenterStatus(UserFacingError.Describe(ex, "好友操作未完成，请稍后重试。"), StatusPalette.DangerBrush);
        }
        finally
        {
            _isMutatingFriendRelationship = false;
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
        _activeFriendChatUser = FriendCenterAvatarResolver.Resolve(user, _networkSnapshots.Values);
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
        if (_isRefreshingFriendChat || !CanSynchronizeUserData)
        {
            return;
        }

        var session = _accountSessionCoordinator.Capture();
        _isRefreshingFriendChat = true;
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
            var visibleConversationId = ReferenceEquals(MainTabs.SelectedItem, FriendCenterTab) &&
                                        _friendCenterSection == FriendCenterSection.Conversations &&
                                        IsActive
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
                    User = FriendCenterAvatarResolver.Resolve(conversation.User, _networkSnapshots.Values)
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

            QueueFriendCommunicationEvents(communicationEvents);
        }
        catch (Exception ex)
        {
            if (showErrors)
            {
                FriendChatStatusText.Text = UserFacingError.Describe(ex, "私聊暂时无法同步，请稍后重试。");
                FriendChatStatusText.Foreground = StatusPalette.DangerBrush;
            }
        }
        finally
        {
            _isRefreshingFriendChat = false;
        }
    }

    private void QueueFriendCommunicationEvents(IEnumerable<FriendCommunicationEvent> communicationEvents)
    {
        if (!_overlaySettings.ShowNotice ||
            !_overlaySettings.CommunicationFriendEvents ||
            _overlayWindow is not { IsVisible: true })
        {
            return;
        }

        foreach (var communicationEvent in communicationEvents)
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

    private async void FriendChatConversationList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isSelectingFriendChatConversation || FriendChatConversationList.SelectedItem is not FriendChatConversationRow row)
        {
            return;
        }

        _activeFriendChatUser = row.User;
        _activeFriendChatConversation = row.Conversation;
        _activeFriendChatOrigin = DirectMessageOrigins.Normalize(row.Conversation.Context?.Origin);
        _friendChatLatestSequence = 0;
        _friendChatMessages.Clear();
        ResetFriendChatPagingState();
        RenderActiveFriendChat();
        await RefreshFriendChatMessagesAsync(showErrors: true);
    }

    private async Task RefreshFriendChatMessagesAsync(bool showErrors)
    {
        if (_activeFriendChatUser is null || !CanSynchronizeUserData)
        {
            return;
        }

        var session = _accountSessionCoordinator.Capture();
        try
        {
            var targetId = _activeFriendChatUser.AccountId;
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
                ReferenceEquals(MainTabs.SelectedItem, FriendCenterTab) &&
                _friendCenterSection == FriendCenterSection.Conversations && IsActive)
            {
                using var readResponse = await _relayClient.PostJsonAsync(
                    "api/friends/chat/read",
                    new FriendChatMarkReadRequestContract(targetId, _friendChatLatestSequence));
            }
        }
        catch (Exception ex)
        {
            if (showErrors)
            {
                FriendChatStatusText.Text = UserFacingError.Describe(ex, "消息暂时无法同步，请稍后重试。");
                FriendChatStatusText.Foreground = StatusPalette.DangerBrush;
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
        if (_activeFriendChatUser is null || _isSendingFriendChatMessage)
        {
            return;
        }

        if (text.Length == 0 && attachment is null)
        {
            FriendChatStatusText.Text = "输入消息后再发送";
            FriendChatStatusText.Foreground = StatusPalette.WarningBrush;
            return;
        }

        _isSendingFriendChatMessage = true;
        FriendChatSendButton.IsEnabled = false;
        FriendChatAttachmentButton.IsEnabled = false;
        try
        {
            using var response = await _relayClient.PostJsonAsync(
                "api/friends/chat/messages",
                new FriendChatSendRequestContract(
                    _activeFriendChatUser.AccountId,
                    text,
                    Guid.NewGuid().ToString("N"),
                    _activeFriendChatOrigin,
                    attachment));
            var mutation = await response.Content.ReadFromJsonAsync<FriendChatMutationResponseContract>();
            if (!response.IsSuccessStatusCode || mutation?.Message is null)
            {
                FriendChatStatusText.Text = mutation?.Error ?? await ReadResponseErrorAsync(response);
                FriendChatStatusText.Foreground = StatusPalette.DangerBrush;
                return;
            }

            if (!_friendChatMessages.Any(row => row.Message.MessageId.Equals(mutation.Message.MessageId, StringComparison.OrdinalIgnoreCase)))
            {
                _friendChatMessages.Add(CreateFriendChatMessageRow(
                    mutation.Message,
                    _activeFriendChatUser.AccountId));
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
            FriendChatStatusText.Text = UserFacingError.Describe(ex, "消息未发送，请检查网络后重试。");
            FriendChatStatusText.Foreground = StatusPalette.DangerBrush;
        }
        finally
        {
            _isSendingFriendChatMessage = false;
            RenderActiveFriendChat();
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
            senderAvatar);
    }

    private async void FriendChatSelectedProfileButton_Click(object sender, RoutedEventArgs e)
    {
        if (_activeFriendChatUser is not null)
        {
            await OpenFriendProfileAsync(new FriendCenterRow(_activeFriendChatUser, default));
        }
    }

    private async void FriendChatRequestActionButton_Click(object sender, RoutedEventArgs e)
    {
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

    private void RefreshPersonalProfileFriendAction()
    {
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

    private void SetFriendCenterStatus(string text, System.Windows.Media.Brush brush)
    {
        FriendCenterStatusText.Text = text;
        FriendCenterStatusText.Foreground = brush;
    }
}
