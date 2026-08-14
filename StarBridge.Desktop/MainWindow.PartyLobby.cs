using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Net;
using System.Net.Http.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Threading;
using StarBridge.Core.PartyRooms;
using StarBridge.Core.Chat;
using StarBridge.Core.Presence;
using StarBridge.Desktop.Theming;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private const int MaximumLoadedPartyRoomChatMessages = 500;

    private readonly record struct PartyRoomChatOperationLane(
        AccountSessionLease Session,
        string RoomId,
        long ReceiveSessionVersion);

    private static string GetPartyPresenceBrush(PlayerPresenceKind presence) =>
        presence switch
        {
            PlayerPresenceKind.InGame => "#42CF7C",
            PlayerPresenceKind.AppOnline => "#69CCFF",
            PlayerPresenceKind.Away => "#D9A23B",
            _ => "#637A89"
        };

    private readonly ObservableCollection<PartyLobbyRoomCard> _partyLobbyRooms = [];
    private readonly ObservableCollection<PartyRoomSelectedTagChip> _partyRoomCreateSelectedTags = [];
    private readonly ObservableCollection<PartyRoomSelectedTagChip> _partyRoomTagDraftChips = [];
    private readonly ObservableCollection<PartyRoomChatMessageView> _partyRoomChatMessages = [];
    private readonly ObservableCollection<PartyRoomInvitationActionRow> _partyRoomInvitationRows = [];
    private readonly HashSet<string> _partyRoomCreateGameplayIds = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _partyRoomCreateContextIds = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _partyRoomTagDraftGameplayIds = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _partyRoomTagDraftContextIds = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<PartyRoomChatOperationLane> _partyRoomChatRefreshRunningSessions = [];
    private readonly HashSet<PartyRoomChatOperationLane> _partyRoomChatSendRunningSessions = [];
    private readonly HashSet<AccountSessionLease> _partyRoomDirectoryRefreshRunningSessions = [];
    private readonly List<PartyRoomContextTagChoiceGroup> _partyRoomContextTagChoiceGroups = [];
    private readonly OverlayChatReceiveSession _overlayChatReceiveSession = new();
    private ICollectionView? _partyLobbyRoomsView;
    private PartyRoomTagNode? _partyRoomTagCurrentNode;
    private PartyLobbyRoomCard? _currentPartyRoom;
    private PartyLobbyRoomCard? _partyRoomJoinTarget;
    private string? _partyRoomJoinInvitationId;
    private DispatcherTimer? _partyRoomRefreshTimer;
    private bool _isPartyRoomCodeVisible;
    private bool _partyRoomChatHasOlder;
    private bool _isLoadingOlderPartyRoomChat;
    private bool _partyRoomChatFollowLatest = true;
    private bool _isRefreshingPartyLobbyRoomList;
    private bool _isEditingPartyRoom;
    private string? _partyRoomChatRoomId;
    private long _partyRoomChatLastSequence;
    private PartyRoomInvitationSnapshot[] _receivedPartyRoomInvitations = [];
    private PartyRoomInvitationSnapshot[] _sentPartyRoomInvitations = [];
    private bool _partyRoomInvitationPanelShowsHostFriends;
    private bool _isPartyRoomInvitationActionRunning;

    private bool IsPartyRoomChatOperationCurrent(PartyRoomChatOperationLane lane) =>
        _accountSessionCoordinator.IsCurrent(lane.Session) &&
        _currentPartyRoom is { } room &&
        room.RoomId.Equals(lane.RoomId, StringComparison.OrdinalIgnoreCase) &&
        _overlayChatReceiveSession.Version == lane.ReceiveSessionVersion;

    private void InitializePartyLobbyShell()
    {
        PartyLobbyRoomList.ItemsSource = _partyLobbyRooms;
        _partyLobbyRoomsView = CollectionViewSource.GetDefaultView(_partyLobbyRooms);
        _partyLobbyRoomsView.Filter = item => item is PartyLobbyRoomCard room && BuildPartyLobbyFilter().Matches(room);
        PartyRoomCreateSelectedTags.ItemsSource = _partyRoomCreateSelectedTags;
        PartyRoomTagDraftSelectedList.ItemsSource = _partyRoomTagDraftChips;
        PartyRoomTagLevel1List.ItemsSource = PartyRoomTagCatalog.GameplayRoots;
        PartyRoomChatList.ItemsSource = _partyRoomChatMessages;
        ChatHistoryViewport.EnableSmoothScrolling(PartyRoomChatList);
        PartyRoomChatList.AddHandler(
            ScrollViewer.ScrollChangedEvent,
            new ScrollChangedEventHandler(PartyRoomChatList_ScrollChanged));
        PartyRoomInvitationList.ItemsSource = _partyRoomInvitationRows;
        PartyRoomCreateCapacityBox.ItemsSource = Enumerable.Range(2, 15);
        PartyRoomCreateCapacityBox.SelectedItem = 6;
        _partyRoomContextTagChoiceGroups.AddRange(
            PartyRoomTagCatalog.ContextGroups.Select(group => new PartyRoomContextTagChoiceGroup(
                group.Name,
                group.Tags.Select(tag => new PartyRoomContextTagChoice(tag.Id, tag.Name)).ToArray())));
        PartyRoomContextTagGroups.ItemsSource = _partyRoomContextTagChoiceGroups;
        _partyRoomRefreshTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(8) };
        _partyRoomRefreshTimer.Tick += async (_, _) =>
        {
            RefreshPartyRoomCommunicationTimeLabels();
            if (!IsPartyLobbyAcceptanceMode &&
                CanSynchronizeUserData &&
                GetPresenceSharingDecision().CanReceiveRealtime &&
                (PartyLobbyPage.Visibility == Visibility.Visible ||
                 ShouldRefreshPartyRoomForDesktopNotifications()))
            {
                await RefreshPartyRoomsFromServerAsync(showErrors: false);
            }
        };
        _partyRoomRefreshTimer.Start();
        RefreshPartyLobbyShell();
        InitializeDirectoryAcceptanceScenarios();
    }

    private void RefreshPartyRoomCommunicationTimeLabels()
    {
        var now = DateTimeOffset.Now;
        foreach (var row in _partyRoomChatMessages)
        {
            row.RefreshTime(now);
        }
    }

    private PartyLobbyFilter BuildPartyLobbyFilter()
    {
        var activity = (PartyLobbyActivityFilter.SelectedItem as ComboBoxItem)?.Tag as string ?? "";
        var voice = ((PartyLobbyVoiceFilter.SelectedItem as ComboBoxItem)?.Tag as string) switch
        {
            "recommended" => PartyLobbyVoiceRequirement.Recommended,
            "required" => PartyLobbyVoiceRequirement.Required,
            "none" => PartyLobbyVoiceRequirement.None,
            _ => (PartyLobbyVoiceRequirement?)null
        };
        var admission = ((PartyLobbyAdmissionFilter.SelectedItem as ComboBoxItem)?.Tag as string) switch
        {
            "direct" => PartyLobbyAdmissionMode.Direct,
            "approval" => PartyLobbyAdmissionMode.HostApproval,
            _ => (PartyLobbyAdmissionMode?)null
        };

        return new PartyLobbyFilter(PartyLobbySearchBox.Text, activity, voice, admission);
    }

    private void PartyLobbySearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        RefreshPartyLobbyFilter();
    }

    private void PartyLobbyFilter_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        RefreshPartyLobbyFilter();
    }

    private void PartyLobbyClearFilters_Click(object sender, RoutedEventArgs e)
    {
        PartyLobbySearchBox.Clear();
        PartyLobbyActivityFilter.SelectedIndex = 0;
        PartyLobbyVoiceFilter.SelectedIndex = 0;
        PartyLobbyAdmissionFilter.SelectedIndex = 0;
        RefreshPartyLobbyFilter();
    }

    private void RefreshPartyLobbyFilter()
    {
        if (_partyLobbyRoomsView is null || PartyLobbyRoomList is null)
        {
            return;
        }

        _partyLobbyRoomsView.Refresh();
        if (PartyLobbyRoomList.SelectedItem is not null &&
            !_partyLobbyRoomsView.Cast<object>().Contains(PartyLobbyRoomList.SelectedItem))
        {
            PartyLobbyRoomList.SelectedItem = null;
        }

        RefreshPartyLobbyShell();
    }

    private void PartyLobbyRoomList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isRefreshingPartyLobbyRoomList)
        {
            return;
        }

        RefreshPartyLobbyPreview(PartyLobbyRoomList.SelectedItem as PartyLobbyRoomCard);
    }

    private async void PartyLobbyRefresh_Click(object sender, RoutedEventArgs e)
    {
        await RefreshPartyRoomsFromServerAsync(showErrors: true);
    }

    private void PartyLobbyJoin_Click(object sender, RoutedEventArgs e)
    {
        if (PartyLobbyRoomList.SelectedItem is PartyLobbyRoomCard room)
        {
            OpenPartyRoomJoinOverlay(room);
        }
    }

    private void PartyLobbyCode_Click(object sender, RoutedEventArgs e)
    {
        OpenPartyRoomJoinOverlay(null);
    }

    private void PartyLobbyCreate_Click(object sender, RoutedEventArgs e)
    {
        if (_currentPartyRoom is not null)
        {
            ShowCurrentPartyRoom();
            return;
        }

        ResetPartyRoomCreateForm();
        SetPartyRoomCreateMode(isEditing: false);
        PartyRoomCreateOverlay.Visibility = Visibility.Visible;
        PartyRoomCreateNameBox.Focus();
    }

    private async void PartyLobbyInvitations_Click(object sender, RoutedEventArgs e)
    {
        await RefreshPartyRoomsFromServerAsync(showErrors: true);
        OpenPartyRoomInvitationPanel(showHostFriends: false);
    }

    private async void PartyCurrentRoomInviteFriends_Click(object sender, RoutedEventArgs e)
    {
        if (_currentPartyRoom is not { ViewerIsHost: true })
        {
            return;
        }

        await RefreshFriendCenterAsync(showErrors: false);
        await RefreshPartyRoomsFromServerAsync(showErrors: false);
        OpenPartyRoomInvitationPanel(showHostFriends: true);
    }

    private void PartyRoomInvitationClose_Click(object sender, RoutedEventArgs e)
    {
        PartyRoomInvitationOverlay.Visibility = Visibility.Collapsed;
        PartyRoomInvitationStatusText.Text = "邀请会在房间关闭、招募结束或 24 小时后失效。";
    }

    private void OpenPartyRoomInvitationPanel(bool showHostFriends)
    {
        _partyRoomInvitationPanelShowsHostFriends = showHostFriends;
        PartyRoomInvitationTitleText.Text = showHostFriends ? "邀请好友" : "房间邀请";
        PartyRoomInvitationSubtitleText.Text = showHostFriends
            ? "邀请好友直接加入当前房间；已在房间中的好友不会重复显示。"
            : "接受邀请会直接进入对应房间。";
        PartyRoomInvitationStatusText.Text = "邀请会在房间关闭、招募结束或 24 小时后失效。";
        RenderPartyRoomInvitationRows();
        PartyRoomInvitationOverlay.Visibility = Visibility.Visible;
    }

    private void RenderPartyRoomInvitationRows()
    {
        _partyRoomInvitationRows.Clear();
        if (_partyRoomInvitationPanelShowsHostFriends)
        {
            RenderPartyRoomFriendInviteRows();
        }
        else
        {
            foreach (var invitation in _receivedPartyRoomInvitations
                         .OrderByDescending(item => item.CreatedAt))
            {
                _partyRoomInvitationRows.Add(new PartyRoomInvitationActionRow(
                    invitation.InviterAccountId,
                    invitation.InviterCallsign,
                    invitation.InviterGameId,
                    invitation.InviterAvatarImageData,
                    $"邀请你加入「{invitation.RoomTitle}」 · {invitation.ExpiresAt.ToLocalTime():MM-dd HH:mm} 前有效",
                    "加入房间",
                    "join",
                    true,
                    "忽略",
                    "decline",
                    invitation.RoomId,
                    invitation.InvitationId));
            }
        }

        PartyRoomInvitationEmptyText.Text = _partyRoomInvitationPanelShowsHostFriends
            ? "当前没有可邀请的好友。"
            : "当前没有房间邀请。";
        PartyRoomInvitationEmptyText.Visibility = _partyRoomInvitationRows.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        PartyRoomInvitationList.Visibility = _partyRoomInvitationRows.Count == 0
            ? Visibility.Collapsed
            : Visibility.Visible;
    }

    private void RenderPartyRoomFriendInviteRows()
    {
        foreach (var row in BuildPartyRoomFriendInviteRows())
        {
            _partyRoomInvitationRows.Add(row);
        }
    }

    private PartyRoomInvitationActionRow[] BuildPartyRoomFriendInviteRows()
    {
        if (_currentPartyRoom is not { } room)
        {
            return [];
        }

        var rows = new List<PartyRoomInvitationActionRow>();
        var memberIds = room.Members
            .Select(member => member.AccountId)
            .Where(accountId => !string.IsNullOrWhiteSpace(accountId))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var entry in _friendCenterSnapshot?.Friends ?? [])
        {
            var user = FriendCenterUserResolver.Resolve(entry.User, _networkSnapshots.Values);
            if (memberIds.Contains(user.AccountId))
            {
                continue;
            }

            var sent = _sentPartyRoomInvitations.FirstOrDefault(invitation =>
                invitation.RoomId.Equals(room.RoomId, StringComparison.OrdinalIgnoreCase) &&
                invitation.RecipientAccountId.Equals(user.AccountId, StringComparison.OrdinalIgnoreCase));
            rows.Add(new PartyRoomInvitationActionRow(
                user.AccountId,
                user.Callsign,
                user.GameId,
                user.AvatarImageData,
                sent is null
                    ? $"{FriendPresenceText(user.Presence)} · 可发送房间邀请"
                    : $"已邀请 · {sent.ExpiresAt.ToLocalTime():MM-dd HH:mm} 前有效",
                sent is null ? "邀请" : "已邀请",
                "invite",
                sent is null,
                sent is null ? "" : "撤回",
                sent is null ? "" : "revoke",
                room.RoomId,
                sent?.InvitationId));
        }

        return rows.ToArray();
    }

    private static string FriendPresenceText(string? presence) =>
        presence?.Trim().ToLowerInvariant() switch
        {
            "ingame" => "正在游戏",
            "apponline" => "应用在线",
            "away" => "暂离",
            _ => "离线"
        };

    private async void PartyRoomInvitationPrimary_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not PartyRoomInvitationActionRow row ||
            !row.PrimaryEnabled)
        {
            return;
        }

        if (row.PrimaryAction == "join")
        {
            await JoinPartyRoomFromInvitationAsync(row);
            return;
        }

        await CreatePartyRoomInvitationAsync(row);
    }

    private async void PartyRoomInvitationSecondary_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not PartyRoomInvitationActionRow row ||
            string.IsNullOrWhiteSpace(row.SecondaryAction) ||
            string.IsNullOrWhiteSpace(row.RoomId) ||
            string.IsNullOrWhiteSpace(row.InvitationId))
        {
            return;
        }

        if (row.SecondaryAction == "revoke")
        {
            await RevokePartyRoomInvitationAsync(row);
            return;
        }

        if (_isPartyRoomInvitationActionRunning)
        {
            return;
        }

        _isPartyRoomInvitationActionRunning = true;
        try
        {
            using var response = await _relayClient.PostJsonAsync(
                "api/party-rooms/invitations/action",
                new PartyRoomInviteActionRequest(row.RoomId, row.InvitationId, row.SecondaryAction));
            var mutation = await response.Content.ReadFromJsonAsync<PartyRoomInvitationMutationResponse>();
            if (!response.IsSuccessStatusCode)
            {
                PartyRoomInvitationStatusText.Text = mutation?.Error ?? "无法处理这条房间邀请。";
                return;
            }

            PartyRoomInvitationStatusText.Text = row.SecondaryAction == "revoke" ? "邀请已撤回。" : "邀请已忽略。";
            await RefreshPartyRoomsFromServerAsync(showErrors: false);
            RenderPartyRoomInvitationRows();
        }
        catch
        {
            PartyRoomInvitationStatusText.Text = "无法连接房间服务器，请稍后重试。";
        }
        finally
        {
            _isPartyRoomInvitationActionRunning = false;
        }
    }

    private async Task<bool> RevokePartyRoomInvitationAsync(
        PartyRoomInvitationActionRow row,
        TextBlock? statusTarget = null)
    {
        var statusText = statusTarget ?? PartyRoomInvitationStatusText;
        if (_currentPartyRoom is not { ViewerIsHost: true } ||
            string.IsNullOrWhiteSpace(row.RoomId) ||
            string.IsNullOrWhiteSpace(row.InvitationId))
        {
            statusText.Text = "这条房间邀请已失效，请刷新后重试。";
            statusText.Foreground = StatusPalette.WarningBrush;
            return false;
        }

        if (_isPartyRoomInvitationActionRunning)
        {
            return false;
        }

        _isPartyRoomInvitationActionRunning = true;
        try
        {
            using var response = await _relayClient.PostJsonAsync(
                "api/party-rooms/invitations/action",
                new PartyRoomInviteActionRequest(row.RoomId, row.InvitationId, "revoke"));
            var mutation = await response.Content.ReadFromJsonAsync<PartyRoomInvitationMutationResponse>();
            if (!response.IsSuccessStatusCode)
            {
                statusText.Text = mutation?.Error ?? "邀请未能撤回，请稍后重试。";
                statusText.Foreground = StatusPalette.DangerBrush;
                return false;
            }

            statusText.Text = "邀请已撤回。";
            statusText.Foreground = StatusPalette.SuccessBrush;
            await RefreshPartyRoomsFromServerAsync(showErrors: false);
            RenderPartyRoomInvitationRows();
            return true;
        }
        catch (Exception ex)
        {
            statusText.Text = UserFacingError.Describe(ex, "邀请未能撤回，请检查网络后重试。");
            statusText.Foreground = StatusPalette.DangerBrush;
            return false;
        }
        finally
        {
            _isPartyRoomInvitationActionRunning = false;
        }
    }

    private async Task<bool> CreatePartyRoomInvitationAsync(
        PartyRoomInvitationActionRow row,
        TextBlock? statusTarget = null)
    {
        var statusText = statusTarget ?? PartyRoomInvitationStatusText;
        if (_currentPartyRoom is not { ViewerIsHost: true } room)
        {
            statusText.Text = "只有房主可以发送房间邀请。";
            statusText.Foreground = StatusPalette.WarningBrush;
            return false;
        }

        if (_isPartyRoomInvitationActionRunning)
        {
            return false;
        }

        _isPartyRoomInvitationActionRunning = true;
        try
        {
            using var response = await _relayClient.PostJsonAsync(
                "api/party-rooms/invitations",
                new PartyRoomInviteCreateRequest(room.RoomId, row.AccountId));
            var mutation = await response.Content.ReadFromJsonAsync<PartyRoomInvitationMutationResponse>();
            if (!response.IsSuccessStatusCode)
            {
                statusText.Text = mutation?.Error ?? "房间邀请未发送，请稍后重试。";
                statusText.Foreground = StatusPalette.DangerBrush;
                return false;
            }

            statusText.Text = $"已向 {row.Callsign} 发送房间邀请。";
            statusText.Foreground = StatusPalette.SuccessBrush;
            await RefreshPartyRoomsFromServerAsync(showErrors: false);
            RenderPartyRoomInvitationRows();
            return true;
        }
        catch (Exception ex)
        {
            statusText.Text = UserFacingError.Describe(ex, "房间邀请未发送，请检查网络后重试。");
            statusText.Foreground = StatusPalette.DangerBrush;
            return false;
        }
        finally
        {
            _isPartyRoomInvitationActionRunning = false;
        }
    }

    private async Task JoinPartyRoomFromInvitationAsync(PartyRoomInvitationActionRow row)
    {
        if (string.IsNullOrWhiteSpace(row.RoomId) || string.IsNullOrWhiteSpace(row.InvitationId))
        {
            return;
        }

        if (_isPartyRoomInvitationActionRunning)
        {
            return;
        }

        _isPartyRoomInvitationActionRunning = true;
        try
        {
            await PublishCurrentPresenceBeforePartyRoomMutationAsync();
            var joinRequest = new PartyRoomJoinRequest(
                row.RoomId,
                null,
                BuildCurrentPartyRoomMemberState())
            {
                InvitationId = row.InvitationId
            };
            using var response = await _relayClient.PostJsonAsync("api/party-rooms/join", joinRequest);
            var mutation = await response.Content.ReadFromJsonAsync<PartyRoomMutationResponse>();
            if (!response.IsSuccessStatusCode || mutation?.Room is null)
            {
                PartyRoomInvitationStatusText.Text = mutation?.Error ?? "无法加入受邀房间。";
                return;
            }

            ApplyCurrentPartyRoom(ToPartyLobbyRoomCard(mutation.Room));
            PartyRoomInvitationOverlay.Visibility = Visibility.Collapsed;
            await RefreshPartyRoomsFromServerAsync(showErrors: false);
        }
        catch
        {
            PartyRoomInvitationStatusText.Text = "无法连接房间服务器，请稍后重试。";
        }
        finally
        {
            _isPartyRoomInvitationActionRunning = false;
        }
    }

    private void RefreshPartyRoomInvitationBadge()
    {
        var count = _receivedPartyRoomInvitations.Length;
        PartyLobbyInvitationsButton.Content = count > 0 ? $"房间邀请  {count}" : "房间邀请";
        PartyLobbyInvitationsButton.Foreground = count > 0
            ? BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.StatusInfo)
            : BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.Ink);
        RefreshNavigationActivityBadges();
    }

    private void PartyRoomCreateCancel_Click(object sender, RoutedEventArgs e)
    {
        PartyRoomTagPickerOverlay.Visibility = Visibility.Collapsed;
        PartyRoomCreateOverlay.Visibility = Visibility.Collapsed;
    }

    private void OpenPartyRoomJoinOverlay(PartyLobbyRoomCard? room)
    {
        _partyRoomJoinInvitationId = null;
        if (_currentPartyRoom is not null)
        {
            ShowCurrentPartyRoom();
            return;
        }

        _partyRoomJoinTarget = room;
        PartyRoomJoinCodeBox.Clear();
        PartyRoomJoinPasswordBox.Clear();
        PartyRoomJoinValidationText.Text = "";
        RefreshPartyRoomJoinOverlay();
        PartyRoomJoinOverlay.Visibility = Visibility.Visible;
        if (room is null)
        {
            PartyRoomJoinCodeBox.Focus();
        }
        else if (room.PasswordRequired)
        {
            PartyRoomJoinPasswordBox.Focus();
        }
    }

    private void RefreshPartyRoomJoinOverlay()
    {
        var hasTarget = _partyRoomJoinTarget is not null;
        var hasInvitation = !string.IsNullOrWhiteSpace(_partyRoomJoinInvitationId);
        var alreadyInTargetRoom = hasInvitation &&
                                  _currentPartyRoom?.RoomId.Equals(
                                      _partyRoomJoinTarget?.RoomId,
                                      StringComparison.OrdinalIgnoreCase) == true;
        var mustLeaveCurrentRoom = hasInvitation && _currentPartyRoom is not null && !alreadyInTargetRoom;
        PartyRoomJoinCodePanel.Visibility = hasTarget ? Visibility.Collapsed : Visibility.Visible;
        PartyRoomJoinTargetPanel.Visibility = hasTarget ? Visibility.Visible : Visibility.Collapsed;
        PartyRoomJoinPasswordPanel.Visibility = !hasInvitation && _partyRoomJoinTarget?.PasswordRequired == true
            ? Visibility.Visible
            : Visibility.Collapsed;
        PartyRoomJoinTargetPanel.DataContext = _partyRoomJoinTarget;
        PartyRoomJoinConfirmButton.Content = alreadyInTargetRoom
            ? "已在该房间"
            : mustLeaveCurrentRoom
                ? "请先退出当前房间"
                : hasInvitation
                    ? "接受邀请"
                    : !hasTarget
                        ? "查找房间"
                        : _partyRoomJoinTarget!.AdmissionMode == PartyLobbyAdmissionMode.Direct
                            ? "直接加入"
                            : "提交加入申请";
        PartyRoomJoinConfirmButton.IsEnabled = !alreadyInTargetRoom && !mustLeaveCurrentRoom;
    }

    private void PartyRoomJoinCancel_Click(object sender, RoutedEventArgs e)
    {
        PartyRoomJoinOverlay.Visibility = Visibility.Collapsed;
        _partyRoomJoinTarget = null;
        _partyRoomJoinInvitationId = null;
    }

    private async void PartyRoomJoinConfirm_Click(object sender, RoutedEventArgs e)
    {
        if (!CanSynchronizeUserData)
        {
            PartyRoomJoinValidationText.Text = "登录后才能加入临时房间。";
            return;
        }

        if (!string.IsNullOrWhiteSpace(_partyRoomJoinInvitationId) && _currentPartyRoom is not null)
        {
            PartyRoomJoinValidationText.Text = _currentPartyRoom.RoomId.Equals(
                _partyRoomJoinTarget?.RoomId,
                StringComparison.OrdinalIgnoreCase)
                ? "你已经在这个房间中。"
                : "请先退出当前临时房间，再接受新的房间邀请。";
            return;
        }

        PartyRoomJoinConfirmButton.IsEnabled = false;
        PartyRoomJoinValidationText.Text = _partyRoomJoinTarget is null ? "正在查找房间…" : "正在验证加入条件…";
        try
        {
            if (_partyRoomJoinTarget is null)
            {
                var roomCode = PartyRoomJoinCodeBox.Text.Trim();
                if (string.IsNullOrWhiteSpace(roomCode))
                {
                    PartyRoomJoinValidationText.Text = "请输入房间码。";
                    return;
                }

                using var resolveResponse = await _relayClient.PostJsonAsync(
                    "api/party-rooms/resolve-code",
                    new PartyRoomResolveCodeRequest(roomCode));
                var resolved = await resolveResponse.Content.ReadFromJsonAsync<PartyRoomMutationResponse>();
                if (!resolveResponse.IsSuccessStatusCode || resolved?.Room is null)
                {
                    if (HandleAuthorizationFailure(resolveResponse.StatusCode, "查找临时房间"))
                    {
                        return;
                    }

                    PartyRoomJoinValidationText.Text = resolved?.Error ?? "没有找到这个房间码，房间可能已经解散。";
                    return;
                }

                _partyRoomJoinTarget = ToPartyLobbyRoomCard(resolved.Room);
                PartyRoomJoinValidationText.Text = "已找到房间，请确认加入要求。";
                RefreshPartyRoomJoinOverlay();
                if (_partyRoomJoinTarget.PasswordRequired)
                {
                    PartyRoomJoinPasswordBox.Focus();
                }
                return;
            }

            await PublishCurrentPresenceBeforePartyRoomMutationAsync();
            var joinRequest = new PartyRoomJoinRequest(
                _partyRoomJoinTarget.RoomId,
                PartyRoomJoinPasswordBox.Password,
                BuildCurrentPartyRoomMemberState())
            {
                InvitationId = _partyRoomJoinInvitationId
            };
            using var response = await _relayClient.PostJsonAsync("api/party-rooms/join", joinRequest);
            var mutation = await response.Content.ReadFromJsonAsync<PartyRoomMutationResponse>();
            if (!response.IsSuccessStatusCode)
            {
                if (HandleAuthorizationFailure(response.StatusCode, "加入临时房间"))
                {
                    return;
                }

                PartyRoomJoinValidationText.Text = mutation?.Error ?? DescribeResponseFailure(response.StatusCode);
                return;
            }

            if (string.Equals(mutation?.Status, "pending", StringComparison.OrdinalIgnoreCase))
            {
                PartyRoomJoinOverlay.Visibility = Visibility.Collapsed;
                _partyRoomJoinTarget = null;
                _partyRoomJoinInvitationId = null;
                StarBridgeMessageBox.Show(
                    this,
                    "加入申请已提交。房主批准后，你会在组队大厅中自动进入房间。",
                    "等待房主批准",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
                return;
            }

            if (mutation?.Room is null)
            {
                PartyRoomJoinValidationText.Text = mutation?.Error ?? "加入结果无效，请刷新大厅后重试。";
                return;
            }

            ApplyCurrentPartyRoom(ToPartyLobbyRoomCard(mutation.Room));
            PartyRoomJoinOverlay.Visibility = Visibility.Collapsed;
            _partyRoomJoinTarget = null;
            _partyRoomJoinInvitationId = null;
        }
        catch (TaskCanceledException)
        {
            PartyRoomJoinValidationText.Text = "加入请求超时，请检查网络后重试。";
        }
        catch (Exception ex) when (HandleAuthorizationFailure(ex, "加入临时房间"))
        {
        }
        catch
        {
            PartyRoomJoinValidationText.Text = "无法连接房间服务器，请稍后重试。";
        }
        finally
        {
            PartyRoomJoinConfirmButton.IsEnabled = true;
        }
    }

    private void PartyRoomCreatePasswordToggle_Changed(object sender, RoutedEventArgs e)
    {
        if (PartyRoomCreatePasswordBox is null)
        {
            return;
        }

        var enabled = PartyRoomCreatePasswordToggle.IsChecked == true;
        PartyRoomCreatePasswordBox.IsEnabled = enabled;
        if (!enabled)
        {
            PartyRoomCreatePasswordBox.Clear();
        }
    }

    private void PartyRoomCreateOpenTags_Click(object sender, RoutedEventArgs e)
    {
        _partyRoomTagDraftGameplayIds.Clear();
        _partyRoomTagDraftGameplayIds.UnionWith(_partyRoomCreateGameplayIds);
        _partyRoomTagDraftContextIds.Clear();
        _partyRoomTagDraftContextIds.UnionWith(_partyRoomCreateContextIds);
        foreach (var choice in _partyRoomContextTagChoiceGroups.SelectMany(group => group.Tags))
        {
            choice.IsSelected = _partyRoomTagDraftContextIds.Contains(choice.Id);
        }

        PartyRoomTagValidationText.Text = "";
        PartyRoomTagLevel1List.SelectedIndex = -1;
        PartyRoomTagLevel2List.ItemsSource = null;
        PartyRoomTagLevel3List.ItemsSource = null;
        _partyRoomTagCurrentNode = null;
        RefreshPartyRoomTagDraft();
        PartyRoomTagPickerOverlay.Visibility = Visibility.Visible;
        PartyRoomTagLevel1List.Focus();
    }

    private void PartyRoomTagPickerCancel_Click(object sender, RoutedEventArgs e)
    {
        PartyRoomTagPickerOverlay.Visibility = Visibility.Collapsed;
    }

    private void PartyRoomTagPickerSave_Click(object sender, RoutedEventArgs e)
    {
        if (_partyRoomTagDraftGameplayIds.Count is < 1 or > 3)
        {
            PartyRoomTagValidationText.Text = "请选择 1–3 条玩法路径。";
            return;
        }

        if (_partyRoomTagDraftContextIds.Count > 3 ||
            _partyRoomTagDraftGameplayIds.Count + _partyRoomTagDraftContextIds.Count > 5)
        {
            PartyRoomTagValidationText.Text = "附加标签最多 3 个，全部标签合计最多 5 个。";
            return;
        }

        _partyRoomCreateGameplayIds.Clear();
        _partyRoomCreateGameplayIds.UnionWith(_partyRoomTagDraftGameplayIds);
        _partyRoomCreateContextIds.Clear();
        _partyRoomCreateContextIds.UnionWith(_partyRoomTagDraftContextIds);
        RefreshPartyRoomCreateTagSummary();
        PartyRoomCreateValidationText.Text = "";
        PartyRoomTagPickerOverlay.Visibility = Visibility.Collapsed;
    }

    private void PartyRoomTagLevel1List_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        var selected = PartyRoomTagLevel1List.SelectedItem as PartyRoomTagNode;
        PartyRoomTagLevel2List.ItemsSource = selected?.Children;
        PartyRoomTagLevel2List.SelectedIndex = -1;
        PartyRoomTagLevel3List.ItemsSource = null;
        _partyRoomTagCurrentNode = selected;
        RefreshPartyRoomTagCurrentPath();
    }

    private void PartyRoomTagLevel2List_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        var selected = PartyRoomTagLevel2List.SelectedItem as PartyRoomTagNode;
        PartyRoomTagLevel3List.ItemsSource = selected?.Children;
        PartyRoomTagLevel3List.SelectedIndex = -1;
        _partyRoomTagCurrentNode = selected ?? PartyRoomTagLevel1List.SelectedItem as PartyRoomTagNode;
        RefreshPartyRoomTagCurrentPath();
    }

    private void PartyRoomTagLevel3List_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        _partyRoomTagCurrentNode = PartyRoomTagLevel3List.SelectedItem as PartyRoomTagNode ??
                                   PartyRoomTagLevel2List.SelectedItem as PartyRoomTagNode ??
                                   PartyRoomTagLevel1List.SelectedItem as PartyRoomTagNode;
        RefreshPartyRoomTagCurrentPath();
    }

    private void PartyRoomTagAddGameplay_Click(object sender, RoutedEventArgs e)
    {
        if (_partyRoomTagCurrentNode is null)
        {
            PartyRoomTagValidationText.Text = "请先从左侧选择一个玩法层级。";
            return;
        }

        var normalized = PartyRoomTagCatalog.NormalizeGameplaySelection(
            _partyRoomTagDraftGameplayIds,
            _partyRoomTagCurrentNode.Id);
        var nextTotal = normalized.Count + _partyRoomTagDraftContextIds.Count;
        if (normalized.Count > 3)
        {
            PartyRoomTagValidationText.Text = "玩法路径最多选择 3 条。";
            return;
        }

        if (nextTotal > 5)
        {
            PartyRoomTagValidationText.Text = "全部标签合计最多选择 5 个。";
            return;
        }

        _partyRoomTagDraftGameplayIds.Clear();
        _partyRoomTagDraftGameplayIds.UnionWith(normalized);
        PartyRoomTagValidationText.Text = "";
        RefreshPartyRoomTagDraft();
    }

    private void PartyRoomContextTag_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.CheckBox checkBox ||
            checkBox.DataContext is not PartyRoomContextTagChoice choice)
        {
            return;
        }

        if (checkBox.IsChecked == true)
        {
            if (_partyRoomTagDraftContextIds.Count >= 3 ||
                _partyRoomTagDraftGameplayIds.Count + _partyRoomTagDraftContextIds.Count >= 5)
            {
                choice.IsSelected = false;
                PartyRoomTagValidationText.Text = "附加标签最多 3 个，全部标签合计最多 5 个。";
                return;
            }

            _partyRoomTagDraftContextIds.Add(choice.Id);
        }
        else
        {
            _partyRoomTagDraftContextIds.Remove(choice.Id);
        }

        PartyRoomTagValidationText.Text = "";
        RefreshPartyRoomTagDraft();
    }

    private void PartyRoomTagRemoveDraft_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is not PartyRoomSelectedTagChip chip)
        {
            return;
        }

        if (chip.IsGameplay)
        {
            _partyRoomTagDraftGameplayIds.Remove(chip.Id);
        }
        else
        {
            _partyRoomTagDraftContextIds.Remove(chip.Id);
            var choice = _partyRoomContextTagChoiceGroups
                .SelectMany(group => group.Tags)
                .FirstOrDefault(item => item.Id.Equals(chip.Id, StringComparison.OrdinalIgnoreCase));
            if (choice is not null)
            {
                choice.IsSelected = false;
            }
        }

        PartyRoomTagValidationText.Text = "";
        RefreshPartyRoomTagDraft();
    }

    private async void PartyRoomCreateConfirm_Click(object sender, RoutedEventArgs e)
    {
        if (!CanSynchronizeUserData)
        {
            PartyRoomCreateValidationText.Text = "登录后才能创建临时房间。";
            return;
        }

        var draft = new PartyRoomCreateDraft(
            PartyRoomCreateNameBox.Text,
            PartyRoomCreateGoalBox.Text,
            _partyRoomCreateGameplayIds.ToArray(),
            _partyRoomCreateContextIds.ToArray(),
            PartyRoomCreateCapacityBox.SelectedItem is int capacity ? capacity : 6,
            GetSelectedTag(PartyRoomCreateVisibilityBox) != "code",
            GetSelectedTag(PartyRoomCreateEligibilityBox) switch
            {
                "friends" => PartyRoomEligibility.HostFriends,
                "fleet" => PartyRoomEligibility.SameFleet,
                "invite" => PartyRoomEligibility.InviteOnly,
                _ => PartyRoomEligibility.Everyone
            },
            GetSelectedTag(PartyRoomCreateAdmissionBox) == "direct"
                ? PartyLobbyAdmissionMode.Direct
                : PartyLobbyAdmissionMode.HostApproval,
            PartyRoomCreatePasswordToggle.IsChecked == true,
            PartyRoomCreatePasswordBox.Password,
            GetSelectedTag(PartyRoomCreateVoiceBox) switch
            {
                "required" => PartyLobbyVoiceRequirement.Required,
                "recommended" => PartyLobbyVoiceRequirement.Recommended,
                _ => PartyLobbyVoiceRequirement.None
            },
            GetSelectedTag(PartyRoomCreateLanguageBox) switch
            {
                "en" => PartyRoomLanguage.English,
                "bilingual" => PartyRoomLanguage.Bilingual,
                _ => PartyRoomLanguage.Chinese
            },
            int.TryParse(GetSelectedTag(PartyRoomCreateRecruitmentBox), out var recruitmentMinutes)
                ? recruitmentMinutes
                : null,
            int.TryParse(GetSelectedTag(PartyRoomCreateDisbandBox), out var disbandHours)
                ? disbandHours
                : 6);

        var callsign = !string.IsNullOrWhiteSpace(_callsign)
            ? _callsign.Trim()
            : GetPersonalDisplayName();
        var gameId = !string.IsNullOrWhiteSpace(_localPlayer)
            ? _localPlayer.Trim()
            : _localPlayerId ?? "";
        var localMemberState = BuildCurrentPartyRoomMemberState();
        var keepsExistingPassword = _isEditingPartyRoom &&
                                    _currentPartyRoom?.PasswordRequired == true &&
                                    draft.PasswordEnabled &&
                                    string.IsNullOrWhiteSpace(draft.Password);
        var validationDraft = keepsExistingPassword
            ? draft with { PasswordEnabled = false, Password = "" }
            : draft;
        var result = PartyRoomCreation.Create(
            validationDraft,
            new PartyLobbyMemberPreview(callsign, gameId, _avatarPath, true, _accountId)
            {
                PresenceText = PlayerPresencePresentation.Format(GetPartyRoomSharedPresence(), _language),
                PresenceBrush = GetPartyPresenceBrush(GetPartyRoomSharedPresence()),
                LocationText = localMemberState.LocationText ?? "等待位置同步",
                ShipText = localMemberState.ShipText ?? "等待舰船同步",
                ShardText = localMemberState.ShardText ?? "等待服务器同步"
            },
            DateTimeOffset.UtcNow);
        if (!result.IsSuccess || result.Room is null)
        {
            PartyRoomCreateValidationText.Text = string.Join(" ", result.Errors);
            return;
        }

        var localHost = result.Room.Members[0];
        var createRequest = new PartyRoomCreateRequest(
            draft.Title,
            draft.Goal,
            draft.GameplayTagNodeIds.ToArray(),
            draft.ContextTagIds.ToArray(),
            draft.Capacity,
            draft.IsPublic,
            draft.Eligibility switch
            {
                PartyRoomEligibility.HostFriends => "friends",
                PartyRoomEligibility.SameFleet => "fleet",
                PartyRoomEligibility.InviteOnly => "invite",
                _ => "everyone"
            },
            draft.AdmissionMode == PartyLobbyAdmissionMode.Direct ? "direct" : "approval",
            draft.PasswordEnabled,
            draft.Password,
            draft.VoiceRequirement switch
            {
                PartyLobbyVoiceRequirement.Required => "required",
                PartyLobbyVoiceRequirement.Recommended => "recommended",
                _ => "none"
            },
            draft.Language switch
            {
                PartyRoomLanguage.English => "en",
                PartyRoomLanguage.Bilingual => "bilingual",
                _ => "zh"
            },
            draft.RecruitmentDurationMinutes,
            draft.AutoDisbandHours,
            localMemberState with { PresenceText = localHost.PresenceText })
        {
            TagCatalogVersion = PartyRoomTagCatalog.Version
        };

        PartyRoomCreateConfirmButton.IsEnabled = false;
        PartyRoomCreateValidationText.Text = _isEditingPartyRoom ? "正在保存房间设置…" : "正在创建房间…";
        try
        {
            if (!_isEditingPartyRoom)
            {
                await PublishCurrentPresenceBeforePartyRoomMutationAsync();
            }

            using var response = _isEditingPartyRoom && _currentPartyRoom is not null
                ? await _relayClient.PostJsonAsync(
                    "api/party-rooms/update",
                    new PartyRoomUpdateRequest(
                        _currentPartyRoom.RoomId,
                        createRequest.Title,
                        createRequest.Goal,
                        createRequest.GameplayTagNodeIds,
                        createRequest.ContextTagIds,
                        createRequest.Capacity,
                        createRequest.IsPublic,
                        createRequest.Eligibility,
                        createRequest.AdmissionMode,
                        !draft.PasswordEnabled
                            ? "remove"
                            : keepsExistingPassword
                                ? "keep"
                                : "replace",
                        draft.Password,
                        createRequest.VoiceRequirement,
                        createRequest.Language,
                        createRequest.RecruitmentDurationMinutes,
                        createRequest.AutoDisbandHours)
                    {
                        TagCatalogVersion = PartyRoomTagCatalog.Version
                    })
                : await _relayClient.PostJsonAsync("api/party-rooms", createRequest);
            var mutation = await response.Content.ReadFromJsonAsync<PartyRoomMutationResponse>();
            if (!_isEditingPartyRoom && response.StatusCode == HttpStatusCode.Conflict && mutation?.Room is not null)
            {
                ApplyCurrentPartyRoom(ToPartyLobbyRoomCard(mutation.Room));
                PartyRoomCreateOverlay.Visibility = Visibility.Collapsed;
                return;
            }

            if (!response.IsSuccessStatusCode || mutation?.Room is null)
            {
                if (HandleAuthorizationFailure(response.StatusCode, _isEditingPartyRoom ? "保存房间设置" : "创建临时房间"))
                {
                    return;
                }

                PartyRoomCreateValidationText.Text = mutation?.Error ?? DescribeResponseFailure(response.StatusCode);
                return;
            }

            ApplyCurrentPartyRoom(ToPartyLobbyRoomCard(mutation.Room));
            PartyRoomCreateOverlay.Visibility = Visibility.Collapsed;
            await RefreshPartyRoomsFromServerAsync(showErrors: false);
        }
        catch (TaskCanceledException)
        {
            PartyRoomCreateValidationText.Text = $"{(_isEditingPartyRoom ? "保存设置" : "创建房间")}超时，请检查网络后重试。";
        }
        catch (Exception ex) when (HandleAuthorizationFailure(ex, _isEditingPartyRoom ? "保存房间设置" : "创建临时房间"))
        {
        }
        catch
        {
            PartyRoomCreateValidationText.Text = _isEditingPartyRoom
                ? "无法连接房间服务器，设置尚未保存。"
                : "无法连接房间服务器，房间尚未创建。";
        }
        finally
        {
            PartyRoomCreateConfirmButton.IsEnabled = true;
        }
    }

    private void PartyCurrentRoomSettings_Click(object sender, RoutedEventArgs e)
    {
        if (_currentPartyRoom?.ViewerIsHost != true)
        {
            return;
        }

        var room = _currentPartyRoom;
        SetPartyRoomCreateMode(isEditing: true);
        PartyRoomCreateNameBox.Text = room.Title;
        PartyRoomCreateGoalBox.Text = room.Goal;
        PartyRoomCreateCapacityBox.SelectedItem = room.Capacity;
        SelectPartyRoomComboBoxTag(PartyRoomCreateVisibilityBox, room.IsPublic ? "public" : "code");
        SelectPartyRoomComboBoxTag(PartyRoomCreateEligibilityBox, room.Eligibility switch
        {
            PartyRoomEligibility.HostFriends => "friends",
            PartyRoomEligibility.SameFleet => "fleet",
            PartyRoomEligibility.InviteOnly => "invite",
            _ => "everyone"
        });
        SelectPartyRoomComboBoxTag(PartyRoomCreateAdmissionBox,
            room.AdmissionMode == PartyLobbyAdmissionMode.Direct ? "direct" : "approval");
        SelectPartyRoomComboBoxTag(PartyRoomCreateVoiceBox, room.VoiceRequirement switch
        {
            PartyLobbyVoiceRequirement.Required => "required",
            PartyLobbyVoiceRequirement.Recommended => "recommended",
            _ => "none"
        });
        SelectPartyRoomComboBoxTag(PartyRoomCreateLanguageBox, room.Language switch
        {
            PartyRoomLanguage.English => "en",
            PartyRoomLanguage.Bilingual => "bilingual",
            _ => "zh"
        });
        var recruitmentMinutes = room.RecruitmentClosesAt.HasValue
            ? Math.Max(1, (int)Math.Ceiling((room.RecruitmentClosesAt.Value - DateTimeOffset.UtcNow).TotalMinutes))
            : 0;
        SelectClosestDuration(PartyRoomCreateRecruitmentBox, recruitmentMinutes, allowUnlimited: true);
        var disbandHours = Math.Max(1, (int)Math.Ceiling((room.ExpiresAt - DateTimeOffset.UtcNow).TotalHours));
        SelectClosestDuration(PartyRoomCreateDisbandBox, disbandHours, allowUnlimited: false);
        PartyRoomCreatePasswordToggle.IsChecked = room.PasswordRequired;
        PartyRoomCreatePasswordBox.Clear();
        PartyRoomCreatePasswordBox.IsEnabled = room.PasswordRequired;
        _partyRoomCreateGameplayIds.Clear();
        _partyRoomCreateGameplayIds.UnionWith(room.GameplayTagNodeIds);
        _partyRoomCreateContextIds.Clear();
        _partyRoomCreateContextIds.UnionWith(room.ContextTagIds);
        RefreshPartyRoomCreateTagSummary();
        PartyRoomCreateValidationText.Text = room.PasswordRequired
            ? "密码留空将保留原密码；输入新密码会替换原密码。"
            : "";
        PartyRoomCreateOverlay.Visibility = Visibility.Visible;
        PartyRoomCreateNameBox.Focus();
    }

    private async void PartyCurrentRoomLeave_Click(object sender, RoutedEventArgs e)
    {
        if (_currentPartyRoom is null)
        {
            return;
        }

        var isHost = _currentPartyRoom.ViewerIsHost;
        var message = isHost && _currentPartyRoom.MemberCount > 1
            ? "退出后，房主会自动移交给最早加入的成员。"
            : isHost
                ? "你是房间内最后一名成员；退出后房间会自动解散。"
                : "退出后，你需要重新申请或加入才能返回这个房间。";
        if (StarBridgeMessageBox.Show(
                this,
                message,
                "退出临时房间",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning) != MessageBoxResult.Yes)
        {
            return;
        }

        try
        {
            using var response = await _relayClient.PostJsonAsync(
                "api/party-rooms/leave",
                new PartyRoomLeaveRequest(_currentPartyRoom.RoomId));
            var mutation = await response.Content.ReadFromJsonAsync<PartyRoomMutationResponse>();
            if (!response.IsSuccessStatusCode)
            {
                if (HandleAuthorizationFailure(response.StatusCode, "退出临时房间"))
                {
                    return;
                }

                StarBridgeMessageBox.Show(this, mutation?.Error ?? "暂时无法退出房间，请稍后重试。",
                    "退出临时房间", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            ClearCurrentPartyRoom();
            await RefreshPartyRoomsFromServerAsync(showErrors: false);
        }
        catch (Exception ex) when (HandleAuthorizationFailure(ex, "退出临时房间"))
        {
        }
        catch
        {
            StarBridgeMessageBox.Show(this, "无法连接房间服务器；本次没有退出房间。",
                "退出临时房间", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private async void PartyRoomApplicationDecision_Click(object sender, RoutedEventArgs e)
    {
        if (_currentPartyRoom?.ViewerIsHost != true ||
            sender is not System.Windows.Controls.Button element ||
            element.Tag is not string applicationId ||
            string.IsNullOrWhiteSpace(applicationId))
        {
            return;
        }

        var approve = string.Equals(element.CommandParameter as string, "approve", StringComparison.OrdinalIgnoreCase);
        element.IsEnabled = false;
        try
        {
            using var response = await _relayClient.PostJsonAsync(
                "api/party-rooms/applications/decision",
                new PartyRoomApplicationDecisionRequest(_currentPartyRoom.RoomId, applicationId, approve));
            var mutation = await response.Content.ReadFromJsonAsync<PartyRoomMutationResponse>();
            if (!response.IsSuccessStatusCode || mutation?.Room is null)
            {
                if (HandleAuthorizationFailure(response.StatusCode, "处理加入申请"))
                {
                    return;
                }

                StarBridgeMessageBox.Show(this, mutation?.Error ?? "这条申请暂时无法处理，请刷新后重试。",
                    "处理加入申请", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            ApplyCurrentPartyRoom(ToPartyLobbyRoomCard(mutation.Room));
            PartyCurrentRoomStatusText.Text = approve ? "已批准加入申请" : "已拒绝加入申请";
        }
        catch (Exception ex) when (HandleAuthorizationFailure(ex, "处理加入申请"))
        {
        }
        catch
        {
            StarBridgeMessageBox.Show(this, "无法连接房间服务器，请稍后重试。",
                "处理加入申请", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        finally
        {
            element.IsEnabled = true;
        }
    }

    private async Task PublishCurrentPresenceBeforePartyRoomMutationAsync()
    {
        await SendPresenceHeartbeatAsync();
        await PushLocalSnapshotAsync(silent: true, pushFleetDirectory: false);
    }

    private PlayerPresenceKind GetPartyRoomSharedPresence()
    {
        var projection = GetLocalFleetPresencePrivacyProjection();
        return PlayerPresence.Normalize(
            projection.LiveStatus,
            projection.Online);
    }

    private PartyRoomMemberStateRequest BuildCurrentPartyRoomMemberState()
    {
        var sharedState = BuildFleetMemberSnapshots().FirstOrDefault();
        var presence = GetPartyRoomSharedPresence();
        var hasServerSession = presence == PlayerPresenceKind.InGame && IsGameServerRegionCurrent();
        var locationCandidate = IsUnknownPartyRoomState(sharedState?.Location)
            ? null
            : FormatPartyRoomLocation(sharedState!.Location);
        var location = PlayerSessionStatePresentation.ResolveLocation(
            presence,
            hasServerSession,
            locationCandidate);

        var currentShip = !IsUnknownPartyRoomState(sharedState?.Ship)
            ? FormatShipForUser(sharedState!.Ship)
            : PersonalCurrentShipText?.Text;
        currentShip = PlayerSessionStatePresentation.ResolveShip(
            presence,
            hasServerSession,
            currentShip);

        var serverSummary = PlayerSessionStatePresentation.ResolveServer(
            presence,
            hasServerSession,
            sharedState?.ServerRegion);
        return new PartyRoomMemberStateRequest(
            PlayerPresencePresentation.Format(presence, _language),
            location,
            currentShip,
            serverSummary);
    }

    private PartyRoomMemberStateRequest BuildCurrentPartyRoomMemberDisplayState()
    {
        var sharedState = BuildCurrentPartyRoomMemberState();
        var local = _players.FirstOrDefault(player => player.IsSelf) ??
                    _players.FirstOrDefault(player =>
                        !string.IsNullOrWhiteSpace(_localPlayer) &&
                        player.Name.Equals(_localPlayer, StringComparison.OrdinalIgnoreCase));
        if (local is null)
        {
            return sharedState;
        }

        var presence = GetPartyRoomSharedPresence();
        var hasServerSession = presence == PlayerPresenceKind.InGame && IsGameServerRegionCurrent();
        var location = PlayerSessionStatePresentation.ResolveLocation(
            presence,
            hasServerSession,
            string.IsNullOrWhiteSpace(local.Location)
                ? sharedState.LocationText
                : FormatPartyRoomLocation(local.Location));
        var shipSource = !string.IsNullOrWhiteSpace(local.RawShip)
            ? local.RawShip
            : local.Ship;
        var currentShip = PlayerSessionStatePresentation.ResolveShip(
            presence,
            hasServerSession,
            FormatShipForUser(shipSource));
        var serverSummary = PlayerSessionStatePresentation.ResolveServer(
            presence,
            hasServerSession,
            IsGameServerRegionCurrent() && !IsUnknownPartyRoomState(_gameServerRegion)
                ? _gameServerRegion.Trim()
                : !string.IsNullOrWhiteSpace(local.ServerRegion)
                    ? FormatPartyRoomServer(local.ServerRegion)
                    : sharedState.ShardText);

        return new PartyRoomMemberStateRequest(
            PlayerPresencePresentation.Format(presence, _language),
            location,
            currentShip,
            serverSummary);
    }

    private static bool IsUnknownPartyRoomState(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ||
               value.Equals("Unknown", StringComparison.OrdinalIgnoreCase) ||
               value.Equals("None", StringComparison.OrdinalIgnoreCase) ||
               value.Equals("未知", StringComparison.OrdinalIgnoreCase);
    }

    private void PartyCurrentRoomCopyCode_Click(object sender, RoutedEventArgs e)
    {
        if (_currentPartyRoom is null || string.IsNullOrWhiteSpace(_currentPartyRoom.RoomCode))
        {
            return;
        }

        try
        {
            System.Windows.Clipboard.SetText(_currentPartyRoom.RoomCode);
            PartyCurrentRoomStatusText.Text = "房间码已复制";
        }
        catch
        {
            PartyCurrentRoomStatusText.Text = "无法访问剪贴板，请手动记录房间码";
        }
    }

    private void PartyCurrentRoomCodeVisibility_Click(object sender, RoutedEventArgs e)
    {
        if (_currentPartyRoom is null || string.IsNullOrWhiteSpace(_currentPartyRoom.RoomCode))
        {
            return;
        }

        UpdatePartyRoomCodeVisibility(!_isPartyRoomCodeVisible);
    }

    private void UpdatePartyRoomCodeVisibility(bool isVisible)
    {
        _isPartyRoomCodeVisible = isVisible &&
                                  _currentPartyRoom is not null &&
                                  !string.IsNullOrWhiteSpace(_currentPartyRoom.RoomCode);
        PartyCurrentRoomCodeText.Text = _isPartyRoomCodeVisible
            ? $"房间码 {_currentPartyRoom!.RoomCode}"
            : "房间码 ••••••";
        PartyCurrentRoomCodeVisibilityIcon.Text = _isPartyRoomCodeVisible ? "\uED1A" : "\uE890";
        PartyCurrentRoomCodeVisibilityButton.ToolTip = _isPartyRoomCodeVisible
            ? "隐藏房间码"
            : "显示房间码";
    }

    private async void PartyCurrentRoomClose_Click(object sender, RoutedEventArgs e)
    {
        if (_currentPartyRoom is null)
        {
            return;
        }

        if (!await ShowAppConfirmationAsync(
                "关闭临时房间",
                "关闭后，所有成员都会离开当前房间。",
                "临时房间关闭后无法恢复。",
                "关闭房间",
                "取消",
                danger: true,
                footerText: "请确认当前房间已不再需要。"))
        {
            return;
        }

        var roomId = _currentPartyRoom.RoomId;
        try
        {
            using var response = await _relayClient.PostJsonAsync(
                "api/party-rooms/close",
                new PartyRoomCloseRequest(roomId));
            var mutation = await response.Content.ReadFromJsonAsync<PartyRoomMutationResponse>();
            if (!response.IsSuccessStatusCode)
            {
                if (HandleAuthorizationFailure(response.StatusCode, "关闭临时房间"))
                {
                    return;
                }

                await ShowAppNoticeAsync(
                    "关闭临时房间",
                    mutation?.Error ?? "服务器暂时无法关闭房间，请稍后重试。",
                    "房间仍然保留，没有执行关闭。");
                return;
            }

            ClearCurrentPartyRoom();
            await RefreshPartyRoomsFromServerAsync(showErrors: false);
        }
        catch (Exception ex) when (HandleAuthorizationFailure(ex, "关闭临时房间"))
        {
        }
        catch
        {
            await ShowAppNoticeAsync(
                "关闭临时房间",
                "无法连接房间服务器。",
                "房间仍然保留，没有执行关闭。");
        }
    }

    private async Task RefreshPartyRoomsFromServerAsync(bool showErrors = false)
    {
        if (IsPartyLobbyAcceptanceMode)
        {
            return;
        }

        if (!CanSynchronizeUserData)
        {
            ClearPartyRoomState();
            return;
        }

        if (!GetPresenceSharingDecision().CanReceiveRealtime)
        {
            return;
        }

        var session = _accountSessionCoordinator.Capture();
        if (!_partyRoomDirectoryRefreshRunningSessions.Add(session))
        {
            return;
        }

        RefreshPartyLobbyLoadingPresentation();

        try
        {
            using var response = await _relayClient.GetAsync("api/party-rooms");
            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return;
            }

            if (!response.IsSuccessStatusCode)
            {
                if (HandleAuthorizationFailure(response.StatusCode, "同步临时房间", silent: !showErrors))
                {
                    return;
                }

                if (showErrors)
                {
                    StarBridgeMessageBox.Show(
                        this,
                        DescribeResponseFailure(response.StatusCode),
                        "刷新组队大厅",
                        MessageBoxButton.OK,
                        MessageBoxImage.Warning);
                }
                return;
            }

            var directory = await response.Content.ReadFromJsonAsync<PartyRoomDirectoryResponse>();
            if (directory is null || !_accountSessionCoordinator.IsCurrent(session))
            {
                return;
            }

            _receivedPartyRoomInvitations = directory.ReceivedInvitations ?? [];
            _sentPartyRoomInvitations = directory.SentInvitations ?? [];
            RefreshPartyRoomInvitationBadge();
            var cards = directory.Rooms.Select(ToPartyLobbyRoomCard).ToArray();
            var selectedRoomId = (PartyLobbyRoomList.SelectedItem as PartyLobbyRoomCard)?.RoomId;
            _isRefreshingPartyLobbyRoomList = true;
            try
            {
                _partyLobbyRooms.Clear();
                foreach (var card in cards)
                {
                    _partyLobbyRooms.Add(card);
                }

                var previousRoomId = _currentPartyRoom?.RoomId;
                _currentPartyRoom = string.IsNullOrWhiteSpace(directory.CurrentRoomId)
                    ? null
                    : cards.FirstOrDefault(room =>
                        room.RoomId.Equals(directory.CurrentRoomId, StringComparison.OrdinalIgnoreCase));
                if (_currentPartyRoom is null)
                {
                    ResetPartyRoomChat();
                    UpdatePartyRoomCodeVisibility(false);
                    PartyCurrentRoomPanel.DataContext = null;
                    PartyCurrentRoomPanel.Visibility = Visibility.Collapsed;
                }
                else
                {
                    if (!string.Equals(previousRoomId, _currentPartyRoom.RoomId, StringComparison.OrdinalIgnoreCase))
                    {
                        ResetPartyRoomChat(_currentPartyRoom.RoomId);
                    }
                    ShowCurrentPartyRoom(resetRoomCodeVisibility: !string.Equals(
                        previousRoomId,
                        _currentPartyRoom.RoomId,
                        StringComparison.OrdinalIgnoreCase));
                }

                RefreshPartyLobbyFilter();
                var selectedRoom = string.IsNullOrWhiteSpace(selectedRoomId)
                    ? null
                    : cards.FirstOrDefault(room =>
                        room.RoomId.Equals(selectedRoomId, StringComparison.OrdinalIgnoreCase));
                if (selectedRoom is not null &&
                    _partyLobbyRoomsView?.Cast<object>().Contains(selectedRoom) == true)
                {
                    PartyLobbyRoomList.SelectedItem = selectedRoom;
                    PartyLobbyRoomList.ScrollIntoView(selectedRoom);
                }
                else
                {
                    selectedRoom = null;
                    PartyLobbyRoomList.SelectedItem = null;
                }

                RefreshPartyLobbyPreview(selectedRoom);
            }
            finally
            {
                _isRefreshingPartyLobbyRoomList = false;
            }

            RefreshOverlaySceneAfterPartyRoomChanged();
            ProcessPlayerActivityDesktopNotifications();
            await RefreshPartyRoomChatAsync(showErrors: false);
        }
        catch (Exception ex)
        {
            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return;
            }

            if (HandleAuthorizationFailure(ex, "同步临时房间", silent: !showErrors))
            {
                return;
            }

            if (showErrors)
            {
                StarBridgeMessageBox.Show(
                    this,
                    "无法连接房间服务器，请检查网络后重试。",
                    "刷新组队大厅",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
            }
        }
        finally
        {
            _partyRoomDirectoryRefreshRunningSessions.Remove(session);
            RefreshPartyLobbyLoadingPresentation();
        }
    }

    private async Task RefreshPartyRoomChatAsync(bool showErrors = false)
    {
        if (_currentPartyRoom is null || !CanSynchronizeUserData)
        {
            return;
        }

        var session = _accountSessionCoordinator.Capture();
        var roomId = _currentPartyRoom.RoomId;
        var receiveSessionVersion = _overlayChatReceiveSession.Version;
        var lane = new PartyRoomChatOperationLane(session, roomId, receiveSessionVersion);
        if (!_partyRoomChatRefreshRunningSessions.Add(lane))
        {
            return;
        }

        try
        {
            var wasEmpty = _partyRoomChatMessages.Count == 0;
            var previousLatestSequence = _partyRoomChatLastSequence;
            var shouldFollowLatest = wasEmpty || _partyRoomChatFollowLatest;
            using var response = await _relayClient.GetAsync(
                $"api/party-rooms/chat?roomId={Uri.EscapeDataString(roomId)}" +
                     $"&after={_partyRoomChatLastSequence}&limit=50");
            var history = await response.Content.ReadFromJsonAsync<PartyRoomChatResponse>();
            if (!IsPartyRoomChatOperationCurrent(lane))
            {
                return;
            }

            if (!response.IsSuccessStatusCode)
            {
                if (HandleAuthorizationFailure(response.StatusCode, "同步房间聊天", silent: !showErrors))
                {
                    return;
                }

                PartyRoomChatStatusText.Text = history?.Error ?? "聊天同步失败；稍后会自动重试。";
                return;
            }

            if (history is null ||
                !_overlayChatReceiveSession.TryEstablishBaseline(
                    roomId,
                    receiveSessionVersion,
                    history.LatestSequence))
            {
                return;
            }

            if (wasEmpty)
            {
                _partyRoomChatHasOlder = history.HasOlder;
            }

            var isViewingCurrentRoom =
                ReferenceEquals(MainTabs.SelectedItem, MySquadTab) &&
                PartyCurrentRoomPanel.Visibility == Visibility.Visible &&
                WindowState != WindowState.Minimized &&
                IsActive;
            if (!wasEmpty && !isViewingCurrentRoom && history.Messages.Length > 0)
            {
                _partyRoomChatUnreadCount += history.Messages.Count(message =>
                    (string.IsNullOrWhiteSpace(_callsign) ||
                     !message.SenderCallsign.Equals(_callsign, StringComparison.OrdinalIgnoreCase)) &&
                    (string.IsNullOrWhiteSpace(_localPlayer) ||
                     !message.SenderGameId.Equals(_localPlayer, StringComparison.OrdinalIgnoreCase)));
                RefreshNavigationActivityBadges();
            }

            AppendPartyRoomChatMessages(history.Messages, followLatest: shouldFollowLatest);
            if (history.Messages.Length == 0)
            {
                _partyRoomChatLastSequence = Math.Max(_partyRoomChatLastSequence, history.LatestSequence);
            }
            else if (!shouldFollowLatest && history.LatestSequence > previousLatestSequence)
            {
                PartyRoomChatJumpToLatestButton.Visibility = Visibility.Visible;
            }
            PartyRoomChatStatusText.Text = "房间内可见";
        }
        catch (Exception ex)
        {
            if (!IsPartyRoomChatOperationCurrent(lane))
            {
                return;
            }

            if (HandleAuthorizationFailure(ex, "同步房间聊天", silent: !showErrors))
            {
                return;
            }

            PartyRoomChatStatusText.Text = "聊天暂时离线；稍后会自动重试";
        }
        finally
        {
            _partyRoomChatRefreshRunningSessions.Remove(lane);
            if (IsPartyRoomChatOperationCurrent(lane))
            {
                RefreshInGameRoomSnapshot();
            }
        }
    }

    private async void PartyRoomChatSend_Click(object sender, RoutedEventArgs e)
    {
        await SendPartyRoomChatMessageAsync(PartyRoomChatInputBox.Text.Trim(), null);
    }

    private async Task SendPartyRoomChatMessageAsync(string text, ChatAttachmentContract? attachment)
    {
        if (_currentPartyRoom is null || !CanSynchronizeUserData)
        {
            return;
        }

        var session = _accountSessionCoordinator.Capture();
        var roomId = _currentPartyRoom.RoomId;
        var receiveSessionVersion = _overlayChatReceiveSession.Version;
        if (string.IsNullOrWhiteSpace(text) && attachment is null)
        {
            PartyRoomChatStatusText.Text = "输入消息后再发送";
            return;
        }

        var lane = new PartyRoomChatOperationLane(session, roomId, receiveSessionVersion);
        if (!_partyRoomChatSendRunningSessions.Add(lane))
        {
            return;
        }

        PartyRoomChatSendButton.IsEnabled = false;
        PartyRoomChatAttachmentButton.IsEnabled = false;
        PartyRoomChatStatusText.Text = "正在发送…";
        try
        {
            using var response = await _relayClient.PostJsonAsync(
                "api/party-rooms/chat",
                 new PartyRoomChatSendRequest(roomId, text, attachment));
            var mutation = await response.Content.ReadFromJsonAsync<PartyRoomChatMutationResponse>();
            if (!IsPartyRoomChatOperationCurrent(lane))
            {
                return;
            }

            if (!response.IsSuccessStatusCode || mutation?.Message is null)
            {
                if (HandleAuthorizationFailure(response.StatusCode, "发送房间消息"))
                {
                    return;
                }

                PartyRoomChatStatusText.Text = mutation?.Error ?? "消息未发送，请稍后重试。";
                return;
            }

            if (!_overlayChatReceiveSession.TryEstablishBaseline(
                    roomId,
                    receiveSessionVersion,
                    Math.Max(0, mutation.Message.Sequence - 1)))
            {
                return;
            }

            _partyRoomChatFollowLatest = true;
            PartyRoomChatJumpToLatestButton.Visibility = Visibility.Collapsed;
            AppendPartyRoomChatMessages([mutation.Message], followLatest: true);
            PartyRoomChatInputBox.Clear();
            PartyRoomChatStatusText.Text = "已发送";
            PartyRoomChatInputBox.Focus();
        }
        catch (TaskCanceledException)
        {
            if (IsPartyRoomChatOperationCurrent(lane))
            {
                PartyRoomChatStatusText.Text = "发送超时，消息未送达";
            }
        }
        catch (Exception ex)
        {
            if (!IsPartyRoomChatOperationCurrent(lane))
            {
                return;
            }

            if (HandleAuthorizationFailure(ex, "发送房间消息"))
            {
                return;
            }

            PartyRoomChatStatusText.Text = "无法连接聊天服务，消息未发送";
        }
        finally
        {
            _partyRoomChatSendRunningSessions.Remove(lane);
            if (IsPartyRoomChatOperationCurrent(lane))
            {
                PartyRoomChatSendButton.IsEnabled = true;
                PartyRoomChatAttachmentButton.IsEnabled = true;
                RefreshInGameRoomSnapshot();
            }
        }
    }

    private void PartyRoomChatInput_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key != System.Windows.Input.Key.Enter ||
            System.Windows.Input.Keyboard.Modifiers.HasFlag(System.Windows.Input.ModifierKeys.Shift))
        {
            return;
        }

        e.Handled = true;
        PartyRoomChatSend_Click(PartyRoomChatSendButton, new RoutedEventArgs());
    }

    private void AppendPartyRoomChatMessages(
        IEnumerable<PartyRoomChatMessageSnapshot> messages,
        bool prepend = false,
        bool followLatest = true)
    {
        var appended = false;
        var insertIndex = 0;
        foreach (var message in messages.OrderBy(item => item.Sequence))
        {
            if (_partyRoomChatMessages.Any(existing => existing.Sequence == message.Sequence))
            {
                continue;
            }

            var senderMember = _currentPartyRoom?.Members.FirstOrDefault(member =>
                (!string.IsNullOrWhiteSpace(message.SenderGameId) &&
                 member.GameId.Equals(message.SenderGameId, StringComparison.OrdinalIgnoreCase)) ||
                (!string.IsNullOrWhiteSpace(message.SenderCallsign) &&
                 member.Callsign.Equals(message.SenderCallsign, StringComparison.OrdinalIgnoreCase)));
            var isLocal = (!string.IsNullOrWhiteSpace(_callsign) &&
                           message.SenderCallsign.Equals(_callsign, StringComparison.OrdinalIgnoreCase)) ||
                          (!string.IsNullOrWhiteSpace(_localPlayer) &&
                           message.SenderGameId.Equals(_localPlayer, StringComparison.OrdinalIgnoreCase));
            var row = new PartyRoomChatMessageView(
                message.Sequence,
                message.MessageId,
                message.Kind,
                message.SenderCallsign,
                message.SenderGameId,
                message.Text,
                message.CreatedAt,
                message.Attachment,
                ChatPresentationBrushes.ResolveSenderRole(this, isLocal, message.SenderColor),
                ChatPresentationBrushes.ResolveAttachmentStatus(this, message.Attachment))
            {
                SenderColor = message.SenderColor,
                SenderAccountId = message.SenderAccountId ?? senderMember?.AccountId,
                SenderAvatarImageData = isLocal
                    ? BuildAvatarImageData()
                    : message.SenderAvatarImageData ?? senderMember?.AvatarImageData,
                IsLocal = isLocal
            };
            if (prepend)
            {
                _partyRoomChatMessages.Insert(insertIndex++, row);
            }
            else
            {
                _partyRoomChatMessages.Add(row);
            }
            _partyRoomChatLastSequence = Math.Max(_partyRoomChatLastSequence, message.Sequence);
            appended = true;
        }

        while (_partyRoomChatMessages.Count > MaximumLoadedPartyRoomChatMessages)
        {
            _partyRoomChatMessages.RemoveAt(0);
        }

        PartyRoomChatEmptyPanel.Visibility = _partyRoomChatMessages.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        PartyRoomChatList.Visibility = _partyRoomChatMessages.Count == 0
            ? Visibility.Collapsed
            : Visibility.Visible;
        if (appended && _partyRoomChatMessages.Count > 0 && followLatest)
        {
            _partyRoomChatFollowLatest = true;
            PartyRoomChatJumpToLatestButton.Visibility = Visibility.Collapsed;
            ChatHistoryViewport.ScrollToLatest(PartyRoomChatList);
        }

        if (appended)
        {
            RenderOverlayEditor();
            RefreshOverlayInspector();
            RefreshOverlayWindow();
        }
    }

    private async void PartyRoomChatList_ScrollChanged(object sender, ScrollChangedEventArgs e)
    {
        if (e.OriginalSource is not ScrollViewer viewer)
        {
            return;
        }

        _partyRoomChatFollowLatest = ChatHistoryViewport.IsNearBottom(viewer);
        PartyRoomChatJumpToLatestButton.Visibility = _partyRoomChatFollowLatest
            ? Visibility.Collapsed
            : Visibility.Visible;
        UpdatePartyRoomChatHistoryStatus(viewer);
        if (ChatHistoryViewport.ShouldLoadOlder(viewer) && _partyRoomChatHasOlder && !_isLoadingOlderPartyRoomChat)
        {
            await LoadOlderPartyRoomChatMessagesAsync();
        }
    }

    private async Task LoadOlderPartyRoomChatMessagesAsync()
    {
        if (_isLoadingOlderPartyRoomChat || !_partyRoomChatHasOlder || _currentPartyRoom is null ||
            _partyRoomChatMessages.Count == 0 || !CanSynchronizeUserData)
        {
            return;
        }

        var roomId = _currentPartyRoom.RoomId;
        var before = _partyRoomChatMessages.Min(message => message.Sequence);
        _isLoadingOlderPartyRoomChat = true;
        PartyRoomChatHistoryStatusText.Text = "正在加载更早消息…";
        PartyRoomChatHistoryStatusPanel.Visibility = ChatHistoryViewport.Find(PartyRoomChatList) is { } viewer &&
                                                     ChatHistoryViewport.IsNearTop(viewer)
            ? Visibility.Visible
            : Visibility.Collapsed;
        try
        {
            using var response = await _relayClient.GetAsync(
                $"api/party-rooms/chat?roomId={Uri.EscapeDataString(roomId)}&before={before}&limit=50");
            var history = await response.Content.ReadFromJsonAsync<PartyRoomChatResponse>();
            if (!response.IsSuccessStatusCode || history is null || _currentPartyRoom is null ||
                !_currentPartyRoom.RoomId.Equals(roomId, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            var anchor = ChatHistoryViewport.Capture(PartyRoomChatList);
            AppendPartyRoomChatMessages(history.Messages, prepend: true, followLatest: false);
            _partyRoomChatHasOlder = history.HasOlder;
            ChatHistoryViewport.RestoreAfterPrepend(PartyRoomChatList, anchor);
        }
        catch
        {
            PartyRoomChatStatusText.Text = "更早消息加载失败，滚到顶部可重试。";
        }
        finally
        {
            _isLoadingOlderPartyRoomChat = false;
            UpdatePartyRoomChatHistoryStatus(ChatHistoryViewport.Find(PartyRoomChatList));
        }
    }

    private void UpdatePartyRoomChatHistoryStatus(ScrollViewer? viewer)
    {
        var atTop = viewer is not null && ChatHistoryViewport.IsNearTop(viewer);
        if (_isLoadingOlderPartyRoomChat)
        {
            PartyRoomChatHistoryStatusText.Text = "正在加载更早消息…";
            PartyRoomChatHistoryStatusPanel.Visibility = atTop ? Visibility.Visible : Visibility.Collapsed;
            return;
        }

        PartyRoomChatHistoryStatusPanel.Visibility = Visibility.Collapsed;
    }

    private void PartyRoomChatJumpToLatestButton_Click(object sender, RoutedEventArgs e)
    {
        _partyRoomChatFollowLatest = true;
        PartyRoomChatJumpToLatestButton.Visibility = Visibility.Collapsed;
        ChatHistoryViewport.ScrollToLatest(PartyRoomChatList);
    }

    private OverlayChatMessage[] ResolveCurrentOverlayChatMessages(OverlaySceneContext sceneContext)
    {
        if (!IsLoggedIn || sceneContext.IsLocalOnly)
        {
            return [];
        }

        if (sceneContext.Kind == OverlaySceneKind.Fleet)
        {
            return ResolveFleetOverlayChatMessages();
        }

        if (sceneContext.Kind != OverlaySceneKind.PartyRoom ||
            _currentPartyRoom is null ||
            !string.Equals(_partyRoomChatRoomId, _currentPartyRoom.RoomId, StringComparison.OrdinalIgnoreCase))
        {
            return [];
        }

        return _partyRoomChatMessages
            .Where(message => _overlayChatReceiveSession.Accepts(
                _currentPartyRoom.RoomId,
                message.Sequence))
            .Select(message => new OverlayChatMessage(
                message.Sequence,
                _currentPartyRoom.RoomId,
                message.SenderCallsign,
                message.SenderGameId,
                message.Text,
                message.CreatedAt,
                message.IsSystem,
                IsLocalPartyRoomChatSender(message),
                message.SenderColor))
            .ToArray();
    }

    private bool IsLocalPartyRoomChatSender(PartyRoomChatMessageView message)
    {
        return (!string.IsNullOrWhiteSpace(_callsign) &&
                message.SenderCallsign.Equals(_callsign, StringComparison.OrdinalIgnoreCase)) ||
               (!string.IsNullOrWhiteSpace(_localPlayer) &&
                message.SenderGameId.Equals(_localPlayer, StringComparison.OrdinalIgnoreCase));
    }

    private void ResetPartyRoomChat(string? roomId = null)
    {
        _overlayChatReceiveSession.Begin(roomId);
        _partyRoomChatRoomId = roomId;
        _partyRoomChatLastSequence = 0;
        _partyRoomChatUnreadCount = 0;
        _partyRoomChatMessages.Clear();
        _partyRoomChatHasOlder = false;
        _isLoadingOlderPartyRoomChat = false;
        _partyRoomChatFollowLatest = true;
        if (PartyRoomChatEmptyPanel is not null)
        {
            PartyRoomChatEmptyPanel.Visibility = Visibility.Visible;
            PartyRoomChatList.Visibility = Visibility.Collapsed;
            PartyRoomChatStatusText.Text = roomId is null ? "等待进入房间" : "正在同步…";
            PartyRoomChatInputBox.Clear();
            PartyRoomChatHistoryStatusPanel.Visibility = Visibility.Collapsed;
            PartyRoomChatJumpToLatestButton.Visibility = Visibility.Collapsed;
        }
        RefreshNavigationActivityBadges();
    }

    private void ApplyCurrentPartyRoom(PartyLobbyRoomCard room)
    {
        var existing = _partyLobbyRooms.FirstOrDefault(item =>
            item.RoomId.Equals(room.RoomId, StringComparison.OrdinalIgnoreCase));
        if (existing is not null)
        {
            _partyLobbyRooms.Remove(existing);
        }

        _partyLobbyRooms.Insert(0, room);
        _currentPartyRoom = room;
        if (!string.Equals(_partyRoomChatRoomId, room.RoomId, StringComparison.OrdinalIgnoreCase))
        {
            ResetPartyRoomChat(room.RoomId);
        }
        RefreshPartyLobbyFilter();
        ShowCurrentPartyRoom(resetRoomCodeVisibility: true);
        RefreshOverlaySceneAfterPartyRoomChanged();
        RefreshBridgeSceneBandStatus();
        _ = RefreshPartyRoomChatAsync(showErrors: false);
    }

    private void ClearCurrentPartyRoom()
    {
        if (_currentPartyRoom is not null)
        {
            _partyLobbyRooms.Remove(_currentPartyRoom);
        }

        _currentPartyRoom = null;
        RefreshPartyLobbyHeader();
        ResetPartyRoomChat();
        UpdatePartyRoomCodeVisibility(false);
        PartyCurrentRoomPanel.DataContext = null;
        PartyCurrentRoomPanel.Visibility = Visibility.Collapsed;
        RefreshPartyLobbyFilter();
        RefreshOverlaySceneAfterPartyRoomChanged();
        RefreshBridgeSceneBandStatus();
    }

    private void ClearPartyRoomState()
    {
        _partyLobbyRooms.Clear();
        _receivedPartyRoomInvitations = [];
        _sentPartyRoomInvitations = [];
        _partyRoomInvitationRows.Clear();
        RefreshPartyRoomInvitationBadge();
        _currentPartyRoom = null;
        RefreshPartyLobbyHeader();
        ResetPartyRoomChat();
        UpdatePartyRoomCodeVisibility(false);
        PartyCurrentRoomPanel.DataContext = null;
        PartyCurrentRoomPanel.Visibility = Visibility.Collapsed;
        RefreshPartyLobbyFilter();
        RefreshOverlaySceneAfterPartyRoomChanged();
        RefreshBridgeSceneBandStatus();
    }

    private void RefreshOverlaySceneAfterPartyRoomChanged()
    {
        if (_overlaySettings.ScenePreference == OverlayScenePreference.Fleet)
        {
            return;
        }

        RenderOverlayEditor();
        RefreshOverlayInspector();
        RefreshOverlayWindow();
    }

    private PartyLobbyRoomCard ToPartyLobbyRoomCard(PartyRoomSnapshot snapshot)
    {
        var gameplayIds = (snapshot.GameplayTagNodeIds ?? [])
            .Select(PartyRoomTagCatalog.NormalizeGameplayId)
            .Where(id => PartyRoomTagCatalog.TryGetGameplayNode(id, out _))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var contextIds = snapshot.ContextTagIds ?? [];
        var tags = gameplayIds
            .Select(PartyRoomTagCatalog.GetCompactGameplayText)
            .Concat(contextIds.Select(id => PartyRoomTagCatalog.TryGetContextTag(id, out var tag) ? tag.Name : id))
            .ToArray();
        var members = (snapshot.Members ?? [])
            .Select(member =>
            {
                var isLocalMember =
                    !string.IsNullOrWhiteSpace(_accountId) &&
                    string.Equals(
                        member.PublicProfileId,
                        _accountId,
                        StringComparison.OrdinalIgnoreCase) ||
                    !string.IsNullOrWhiteSpace(_localPlayer) &&
                    string.Equals(
                        member.GameId,
                        _localPlayer,
                        StringComparison.OrdinalIgnoreCase);
                var presence = isLocalMember
                    ? GetPartyRoomSharedPresence()
                    : PlayerPresencePresentation.ResolveShared(
                        member.PresenceText,
                        member.PresenceText);
                var localMemberState = isLocalMember
                    ? BuildCurrentPartyRoomMemberDisplayState()
                    : null;
                return new PartyLobbyMemberPreview(
                    member.Callsign,
                    member.GameId,
                    member.AvatarImageData,
                    member.IsHost,
                    member.PublicProfileId)
                {
                    PresenceText = PlayerPresencePresentation.Format(presence, _language),
                    PresenceBrush = GetPartyPresenceBrush(presence),
                    LocationText = localMemberState?.LocationText ?? FormatPartyRoomLocation(member.LocationText),
                    ShipText = localMemberState?.ShipText ??
                               (string.IsNullOrWhiteSpace(member.ShipText) ? "等待舰船同步" : member.ShipText),
                    ShardText = localMemberState?.ShardText ?? FormatPartyRoomServer(member.ShardText)
                };
            })
            .ToArray();
        var host = members.FirstOrDefault(member => member.IsHost) ?? members.FirstOrDefault();
        var hostDisplay = host is null || string.IsNullOrWhiteSpace(host.GameId) ||
                          host.Callsign.Equals(host.GameId, StringComparison.OrdinalIgnoreCase)
            ? host?.Callsign ?? "未知房主"
            : $"{host.Callsign} ({host.GameId})";
        var activity = gameplayIds.Length > 0
            ? PartyRoomTagCatalog.GetGameplayRootName(gameplayIds[0])
            : "其他";
        var card = new PartyLobbyRoomCard(
            snapshot.RoomId,
            snapshot.Title,
            snapshot.Goal,
            hostDisplay,
            activity,
            tags,
            members.Length,
            snapshot.Capacity,
            snapshot.VoiceRequirement switch
            {
                "required" => PartyLobbyVoiceRequirement.Required,
                "recommended" => PartyLobbyVoiceRequirement.Recommended,
                _ => PartyLobbyVoiceRequirement.None
            },
            string.Equals(snapshot.AdmissionMode, "direct", StringComparison.OrdinalIgnoreCase)
                ? PartyLobbyAdmissionMode.Direct
                : PartyLobbyAdmissionMode.HostApproval,
            snapshot.IsPublic,
            snapshot.PasswordRequired,
            members,
            snapshot.UpdatedAt)
        {
            RoomCode = snapshot.RoomCode,
            Eligibility = snapshot.Eligibility switch
            {
                "friends" => PartyRoomEligibility.HostFriends,
                "fleet" => PartyRoomEligibility.SameFleet,
                "invite" => PartyRoomEligibility.InviteOnly,
                _ => PartyRoomEligibility.Everyone
            },
            Language = snapshot.Language switch
            {
                "en" => PartyRoomLanguage.English,
                "bilingual" => PartyRoomLanguage.Bilingual,
                _ => PartyRoomLanguage.Chinese
            },
            RecruitmentClosesAt = snapshot.RecruitmentClosesAt,
            ExpiresAt = snapshot.ExpiresAt,
            GameplayTagNodeIds = gameplayIds,
            ContextTagIds = contextIds,
            TagCatalogVersion = snapshot.TagCatalogVersion,
            ViewerIsHost = snapshot.ViewerIsHost,
            PendingApplications = (snapshot.PendingApplications ?? [])
                .Select(application => new PartyLobbyJoinApplicationView(
                    application.ApplicationId,
                    application.Callsign,
                    application.GameId,
                    application.AvatarImageData,
                    application.CreatedAt)
                {
                    AccountId = application.AccountId
                })
                .ToArray()
        };
        return card;
    }

    private string FormatPartyRoomLocation(string? value)
    {
        if (PlayerSessionStatePresentation.IsSessionStateText(value))
        {
            return value!.Trim();
        }

        if (string.IsNullOrWhiteSpace(value) ||
            value.Contains("等待", StringComparison.OrdinalIgnoreCase))
        {
            return "等待位置同步";
        }

        return FormatLocationForUser(
            value.Trim().Replace("地点：", "", StringComparison.OrdinalIgnoreCase));
    }

    private static string FormatPartyRoomServer(string? value)
    {
        if (PlayerSessionStatePresentation.IsSessionStateText(value))
        {
            return value!.Trim();
        }

        if (string.IsNullOrWhiteSpace(value) ||
            value.Contains("等待", StringComparison.OrdinalIgnoreCase))
        {
            return "等待服务器同步";
        }

        var region = value
            .Split('·', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .FirstOrDefault() ?? value.Trim();
        if (region is "美服" or "欧服" or "澳服" or "亚服")
        {
            return region;
        }

        var mapped = MapGameServerRegion(region);
        return mapped.Equals("未知", StringComparison.OrdinalIgnoreCase)
            ? region
            : mapped;
    }

    private void ShowCurrentPartyRoom(bool resetRoomCodeVisibility = false)
    {
        if (_currentPartyRoom is null)
        {
            return;
        }

        PartyCurrentRoomPanel.DataContext = _currentPartyRoom;
        PartyCurrentRoomStatusText.Text = "房间开放中";
        PartyCurrentRoomSettingsButton.Visibility = _currentPartyRoom.ViewerIsHost
            ? Visibility.Visible
            : Visibility.Collapsed;
        PartyCurrentRoomInviteFriendsButton.Visibility = _currentPartyRoom.ViewerIsHost
            ? Visibility.Visible
            : Visibility.Collapsed;
        PartyCurrentRoomCloseButton.Visibility = _currentPartyRoom.ViewerIsHost
            ? Visibility.Visible
            : Visibility.Collapsed;
        PartyCurrentRoomApplicationsPanel.Visibility = _currentPartyRoom.ViewerIsHost &&
                                                       _currentPartyRoom.HasPendingApplications
            ? Visibility.Visible
            : Visibility.Collapsed;
        UpdatePartyRoomCodeVisibility(resetRoomCodeVisibility ? false : _isPartyRoomCodeVisible);
        PartyCurrentRoomPanel.Visibility = Visibility.Visible;
        RefreshPartyLobbyHeader();
    }

    private void RefreshPartyLobbyHeader()
    {
        RefreshNavigationActivityBadges();
        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var hasCurrentRoom = _currentPartyRoom is not null;
        var entryLabel = hasCurrentRoom
            ? zh ? "当前房间" : "Current Room"
            : zh ? "组队大厅" : "Party Lobby";

        if (MySquadNavText is not null)
        {
            MySquadNavText.Text = entryLabel;
        }

        if (MySquadTab is not null)
        {
            MySquadTab.Header = entryLabel;
        }

        if (PartyLobbyTitleText is null || PartyLobbySubtitleText is null)
        {
            return;
        }

        PartyLobbyTitleText.Text = entryLabel;
        if (hasCurrentRoom)
        {
            PartyLobbySubtitleText.Text = zh
                ? "管理当前临时队伍，也可以继续查看大厅中的其他房间。"
                : "Manage your current party while browsing other available rooms.";
            return;
        }

        PartyLobbySubtitleText.Text = zh
            ? "寻找现在可以一起游玩的队友，或创建一支临时队伍。"
            : "Find players who are ready now, or create a temporary room.";
    }

    private void ResetPartyRoomCreateForm()
    {
        PartyRoomCreateNameBox.Clear();
        PartyRoomCreateGoalBox.Clear();
        PartyRoomCreateValidationText.Text = "";
        PartyRoomCreateCapacityBox.SelectedItem = 6;
        PartyRoomCreateVisibilityBox.SelectedIndex = 0;
        PartyRoomCreateEligibilityBox.SelectedIndex = 0;
        PartyRoomCreateAdmissionBox.SelectedIndex = 1;
        PartyRoomCreatePasswordToggle.IsChecked = false;
        PartyRoomCreatePasswordBox.Clear();
        PartyRoomCreatePasswordBox.IsEnabled = false;
        PartyRoomCreateVoiceBox.SelectedIndex = 1;
        PartyRoomCreateLanguageBox.SelectedIndex = 0;
        PartyRoomCreateRecruitmentBox.SelectedIndex = 0;
        PartyRoomCreateDisbandBox.SelectedIndex = 3;
        _partyRoomCreateGameplayIds.Clear();
        _partyRoomCreateContextIds.Clear();
        RefreshPartyRoomCreateTagSummary();
    }

    private void SetPartyRoomCreateMode(bool isEditing)
    {
        _isEditingPartyRoom = isEditing;
        PartyRoomCreateTitleText.Text = isEditing ? "房间设置" : "创建临时房间";
        PartyRoomCreateSubtitleText.Text = isEditing
            ? "修改后会立即同步给房间内成员与大厅。"
            : "设置本次招募内容。创建后你会直接进入房间。";
        PartyRoomCreateConfirmButton.Content = isEditing ? "保存房间设置" : "创建并进入房间";
    }

    private static void SelectPartyRoomComboBoxTag(System.Windows.Controls.ComboBox comboBox, string tag)
    {
        comboBox.SelectedItem = comboBox.Items
            .OfType<ComboBoxItem>()
            .FirstOrDefault(item => string.Equals(item.Tag as string, tag, StringComparison.OrdinalIgnoreCase));
    }

    private static void SelectClosestDuration(System.Windows.Controls.ComboBox comboBox, int requested, bool allowUnlimited)
    {
        if (allowUnlimited && requested <= 0)
        {
            SelectPartyRoomComboBoxTag(comboBox, "");
            return;
        }

        var candidates = comboBox.Items
            .OfType<ComboBoxItem>()
            .Select(item => new { Item = item, Parsed = int.TryParse(item.Tag as string, out var value), Value = value })
            .Where(candidate => candidate.Parsed)
            .OrderBy(candidate => Math.Abs(candidate.Value - requested))
            .ToArray();
        comboBox.SelectedItem = candidates.FirstOrDefault()?.Item;
    }

    private void RefreshPartyRoomCreateTagSummary()
    {
        _partyRoomCreateSelectedTags.Clear();
        foreach (var id in _partyRoomCreateGameplayIds)
        {
            _partyRoomCreateSelectedTags.Add(new PartyRoomSelectedTagChip(
                id,
                PartyRoomTagCatalog.GetGameplayPathText(id),
                true));
        }

        foreach (var id in _partyRoomCreateContextIds)
        {
            if (PartyRoomTagCatalog.TryGetContextTag(id, out var tag))
            {
                _partyRoomCreateSelectedTags.Add(new PartyRoomSelectedTagChip(id, tag.Name, false));
            }
        }

        PartyRoomCreateTagEmptyText.Visibility = _partyRoomCreateSelectedTags.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        PartyRoomCreateTagCountText.Text = $"{_partyRoomCreateSelectedTags.Count} / 5";
    }

    private void RefreshPartyRoomTagDraft()
    {
        _partyRoomTagDraftChips.Clear();
        foreach (var id in _partyRoomTagDraftGameplayIds)
        {
            _partyRoomTagDraftChips.Add(new PartyRoomSelectedTagChip(
                id,
                PartyRoomTagCatalog.GetGameplayPathText(id),
                true));
        }

        foreach (var id in _partyRoomTagDraftContextIds)
        {
            if (PartyRoomTagCatalog.TryGetContextTag(id, out var tag))
            {
                _partyRoomTagDraftChips.Add(new PartyRoomSelectedTagChip(id, tag.Name, false));
            }
        }

        PartyRoomTagSelectionCountText.Text = $"{_partyRoomTagDraftChips.Count} / 5";
    }

    private void RefreshPartyRoomTagCurrentPath()
    {
        var hasSelection = _partyRoomTagCurrentNode is not null;
        PartyRoomTagCurrentPathText.Text = hasSelection
            ? PartyRoomTagCatalog.GetGameplayPathText(_partyRoomTagCurrentNode!.Id)
            : "从一级玩法开始选择";
        PartyRoomTagAddGameplayButton.IsEnabled = hasSelection;
        PartyRoomTagAddGameplayButton.Content = _partyRoomTagCurrentNode?.HasChildren == true
            ? "选择当前分类"
            : "添加此玩法";
    }

    private static string GetSelectedTag(System.Windows.Controls.ComboBox comboBox) =>
        (comboBox.SelectedItem as ComboBoxItem)?.Tag as string ?? "";

    private void RefreshPartyLobbyShell()
    {
        if (PartyLobbyRoomList is null ||
            PartyLobbyRoomEmptyPanel is null ||
            PartyLobbyResultCountText is null ||
            PartyLobbyRoomLoadingState is null ||
            PartyLobbyRefreshLoadingIndicator is null)
        {
            return;
        }

        RefreshPartyLobbyLoadingPresentation();
    }

    private void RefreshPartyLobbyLoadingPresentation()
    {
        if (PartyLobbyRoomList is null ||
            PartyLobbyRoomEmptyPanel is null ||
            PartyLobbyResultCountText is null ||
            PartyLobbyRoomLoadingState is null ||
            PartyLobbyRefreshLoadingIndicator is null)
        {
            return;
        }

        var visibleCount = _partyLobbyRoomsView?.Cast<object>().Count() ?? 0;
        var isLoading = _partyRoomDirectoryRefreshRunningSessions.Count > 0 ||
                        IsPartyLobbyLoadingAcceptanceMode;
        var showBlockingLoading = isLoading && visibleCount == 0;
        var showInlineLoading = isLoading && visibleCount > 0;

        PartyLobbyRoomLoadingState.Visibility = showBlockingLoading
            ? Visibility.Visible
            : Visibility.Collapsed;
        PartyLobbyRefreshLoadingIndicator.IsActive = showInlineLoading;
        PartyLobbyRefreshLoadingIndicator.Visibility = showInlineLoading
            ? Visibility.Visible
            : Visibility.Collapsed;
        PartyLobbyResultCountText.Text = showBlockingLoading
            ? "正在同步"
            : visibleCount == 0
                ? "暂无可加入房间"
                : $"{visibleCount} 个可加入房间";
        PartyLobbyRoomEmptyPanel.Visibility = !isLoading && visibleCount == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        PartyLobbyRoomList.Visibility = visibleCount > 0
            ? Visibility.Visible
            : Visibility.Collapsed;

        if (!isLoading && visibleCount == 0)
        {
            PartyLobbyRoomList.SelectedItem = null;
            RefreshPartyLobbyPreview(null);
        }
    }

    private void RefreshPartyLobbyPreview(PartyLobbyRoomCard? room)
    {
        if (PartyLobbyPreviewEmptyPanel is null || PartyLobbyPreviewContent is null)
        {
            return;
        }

        PartyLobbyPreviewEmptyPanel.Visibility = room is null ? Visibility.Visible : Visibility.Collapsed;
        PartyLobbyPreviewContent.Visibility = room is null ? Visibility.Collapsed : Visibility.Visible;
        PartyLobbyPreviewContent.DataContext = room;
        if (room is not null)
        {
            PartyLobbyJoinButton.Content = room.AdmissionMode == PartyLobbyAdmissionMode.Direct
                ? "直接加入"
                : "申请加入";
        }
    }

    private void ApplyPartyLobbyLanguage(bool zh)
    {
        if (PartyLobbyTitleText is null)
        {
            return;
        }

        RefreshPartyLobbyHeader();
        PartyLobbyCodeButton.Content = zh ? "输入房间码" : "Enter room code";
        RefreshPartyRoomInvitationBadge();
        PartyLobbyCreateButton.Content = zh ? "创建房间" : "Create room";
        PartyLobbyListTitleText.Text = zh ? "全部房间" : "All rooms";
        PartyLobbyPreviewTitleText.Text = zh ? "房间预览" : "Room preview";
        PartyLobbyPreviewHintText.Text = zh ? "加入后进入房间" : "Enter the room after joining";
        if (PartyLobbyRoomList.SelectedItem is PartyLobbyRoomCard selectedRoom)
        {
            PartyLobbyJoinButton.Content = zh
                ? selectedRoom.AdmissionMode == PartyLobbyAdmissionMode.Direct ? "直接加入" : "申请加入"
                : selectedRoom.AdmissionMode == PartyLobbyAdmissionMode.Direct ? "Join now" : "Request to join";
        }
        PartyLobbyClearFiltersButton.Content = zh ? "清除筛选" : "Clear filters";
        PartyLobbyRefreshButton.Content = zh ? "刷新" : "Refresh";
        RefreshPartyLobbyShell();
    }
}

internal sealed record PartyRoomSelectedTagChip(string Id, string DisplayText, bool IsGameplay);

internal sealed record PartyRoomContextTagChoiceGroup(
    string Name,
    IReadOnlyList<PartyRoomContextTagChoice> Tags);

internal sealed class PartyRoomContextTagChoice : INotifyPropertyChanged
{
    private bool _isSelected;

    public PartyRoomContextTagChoice(string id, string name)
    {
        Id = id;
        Name = name;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string Id { get; }

    public string Name { get; }

    public bool IsSelected
    {
        get => _isSelected;
        set
        {
            if (_isSelected == value)
            {
                return;
            }

            _isSelected = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(IsSelected)));
        }
    }
}
