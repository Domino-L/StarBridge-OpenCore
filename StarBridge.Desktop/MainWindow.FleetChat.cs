using StarBridge.Core.FleetChat;
using StarBridge.Core.Chat;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Net.Http.Json;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;
using ColorConverter = System.Windows.Media.ColorConverter;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private readonly record struct FleetChatDirectoryLane(
        AccountSessionLease Session,
        string FleetCode);

    private readonly record struct FleetChatOperationLane(
        AccountSessionLease Session,
        string FleetCode,
        string ChannelId);

    private const int FleetChatFullHistoryRefreshIntervalTicks = 15;
    private readonly ObservableCollection<FleetChatChannelRow> _fleetChatChannels = [];
    private readonly ObservableCollection<FleetChatMessageRow> _fleetChatMessages = [];
    private readonly List<FleetChatMessageRow> _fleetMemberSidebarChatPreview = [];
    private readonly Dictionary<string, FleetOverlayChatChannelState> _fleetOverlayChatChannels =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly List<OverlayChatMessage> _fleetOverlayChatMessages = [];
    private readonly DispatcherTimer _fleetChatRefreshTimer = new() { Interval = TimeSpan.FromSeconds(2) };
    private readonly HashSet<FleetChatDirectoryLane> _refreshingFleetChatDirectoryLanes = [];
    private readonly HashSet<FleetChatOperationLane> _refreshingFleetChatMessageLanes = [];
    private readonly HashSet<FleetChatOperationLane> _sendingFleetChatMessageLanes = [];
    private FleetChatChannelRow? _activeFleetChatChannel;
    private bool _isRefreshingFleetMemberSidebarChatPreview;
    private bool _fleetMemberSidebarChatPreviewLoaded;
    private bool _isSelectingFleetChatChannel;
    private bool _fleetChatNeedsFullHistoryRefresh = true;
    private bool _fleetChatHasOlder;
    private bool _isLoadingOlderFleetChat;
    private bool _fleetChatFollowLatest = true;
    private int _fleetChatRefreshTick;
    private int _fleetChatTotalUnread;
    private long _fleetChatLatestSequence;
    private long _fleetMemberSidebarChatLatestSequence;
    private long _fleetOverlayChatProjectionSequence;
    private bool _isRefreshingFleetOverlayChat;
    private bool _fleetOverlayChatProjectionActive;
    private string _fleetOverlayChatProjectionSignature = "";

    private bool CanUseFleetChat => CanSynchronizeUserData && _hasFleet && !string.IsNullOrWhiteSpace(_fleetCode);
    private bool _isSendingFleetChatMessage =>
        _activeFleetChatChannel is { } activeChannel &&
        _sendingFleetChatMessageLanes.Contains(CreateFleetChatOperationLane(
            _accountSessionCoordinator.Capture(),
            _fleetCode,
            activeChannel.ChannelId));

    private static FleetChatOperationLane CreateFleetChatOperationLane(
        AccountSessionLease session,
        string fleetCode,
        string channelId) =>
        new(
            session,
            fleetCode.Trim().ToUpperInvariant(),
            channelId.Trim().ToUpperInvariant());

    private bool IsFleetChatOperationCurrent(FleetChatOperationLane lane) =>
        _accountSessionCoordinator.IsCurrent(lane.Session) &&
        CanUseFleetChat &&
        _activeFleetChatChannel is { } activeChannel &&
        CreateFleetChatOperationLane(lane.Session, _fleetCode, activeChannel.ChannelId) is var current &&
        current.FleetCode.Equals(lane.FleetCode, StringComparison.Ordinal) &&
        current.ChannelId.Equals(lane.ChannelId, StringComparison.Ordinal);

    private bool IsFleetChatDirectoryCurrent(FleetChatDirectoryLane lane) =>
        _accountSessionCoordinator.IsCurrent(lane.Session) &&
        CanUseFleetChat &&
        _fleetCode.Trim().Equals(lane.FleetCode, StringComparison.OrdinalIgnoreCase);

    private void InitializeFleetChat()
    {
        InitializeFleetAnnouncements();
        FleetChatChannelList.ItemsSource = _fleetChatChannels;
        FleetChatMessageList.ItemsSource = _fleetChatMessages;
        FleetCommunicationExternalContactsList.ItemsSource = _fleetExternalContacts;
        ChatHistoryViewport.EnableSmoothScrolling(FleetChatMessageList);
        FleetChatMessageList.AddHandler(
            ScrollViewer.ScrollChangedEvent,
            new ScrollChangedEventHandler(FleetChatMessageList_ScrollChanged));
        _fleetChatRefreshTimer.Tick += FleetChatRefreshTimer_Tick;
        _fleetChatRefreshTimer.Start();
        ApplyFleetChatAvailability();
        Loaded += async (_, _) =>
        {
            if (CanUseFleetChat)
            {
                await Task.WhenAll(
                    RefreshFleetChatChannelsAsync(showErrors: false),
                    RefreshFleetAnnouncementsAsync(showErrors: false));
            }
        };
    }

    private void DisposeFleetChat()
    {
        _fleetChatRefreshTimer.Stop();
        _fleetChatRefreshTimer.Tick -= FleetChatRefreshTimer_Tick;
    }

    private async void FleetChatRefreshTimer_Tick(object? sender, EventArgs e)
    {
        RefreshFleetCommunicationTimeLabels();
        ApplyFleetChatAvailability();
        if (!CanUseFleetChat)
        {
            ResetFleetMemberSidebarChatPreview();
            ResetFleetOverlayChatProjection();
            return;
        }

        _fleetChatRefreshTick++;
        if (_fleetChatRefreshTick % 5 == 0 || _fleetChatChannels.Count == 0)
        {
            await RefreshFleetChatChannelsAsync(showErrors: false);
        }

        if (_fleetChatRefreshTick % 5 == 0 || _fleetAnnouncementTimelineRevision == 0)
        {
            await RefreshFleetAnnouncementsAsync(showErrors: false);
        }

        if (IsFleetChatVisible())
        {
            var forceFullHistory = _fleetChatNeedsFullHistoryRefresh ||
                                   _fleetChatRefreshTick % FleetChatFullHistoryRefreshIntervalTicks == 0;
            await RefreshFleetChatMessagesAsync(showErrors: false, forceFullHistory);
        }

        if (ShouldRefreshFleetMemberSidebarChatPreview() &&
            (!_fleetMemberSidebarChatPreviewLoaded || _fleetChatRefreshTick % 3 == 0))
        {
            await RefreshFleetMemberSidebarChatPreviewAsync();
        }

        if (ShouldRefreshFleetOverlayChat())
        {
            await RefreshFleetOverlayChatAsync();
        }
        else if (_fleetOverlayChatProjectionActive)
        {
            ResetFleetOverlayChatProjection();
        }
    }

    private bool IsFleetChatVisible() =>
        FleetSubTabs?.SelectedItem == FleetChatTab &&
        FleetTab?.IsSelected == true;

    private bool ShouldRefreshFleetMemberSidebarChatPreview() =>
        FleetTab?.IsSelected == true &&
        FleetSubTabs?.SelectedItem == AllPlayersTab &&
        _membersPanelMode == MembersPanelMode.Member;

    private async Task RefreshFleetMemberSidebarChatPreviewAsync()
    {
        if (_isRefreshingFleetMemberSidebarChatPreview || !CanUseFleetChat)
        {
            return;
        }

        var fleetChannel = _fleetChatChannels.FirstOrDefault(channel =>
            channel.Type == FleetChatChannelTypes.Fleet);
        if (fleetChannel is null)
        {
            return;
        }

        _isRefreshingFleetMemberSidebarChatPreview = true;
        try
        {
            var history = await _relayClient.GetFromJsonAsync<FleetChatHistoryContract>(
                $"api/fleets/chat/messages?fleetCode={Uri.EscapeDataString(_fleetCode)}" +
                $"&channelId={Uri.EscapeDataString(fleetChannel.ChannelId)}" +
                $"&after={_fleetMemberSidebarChatLatestSequence}");
            if (history is null ||
                !history.ChannelId.Equals(fleetChannel.ChannelId, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            var reconciled = FleetChatMessageReconciler.Reconcile(
                _fleetMemberSidebarChatPreview.Select(row => row.Message),
                history.Messages);
            var next = reconciled
                .OrderByDescending(message => message.Sequence)
                .Take(4)
                .OrderBy(message => message.Sequence)
                .Select(message => new FleetChatMessageRow(message, _accountId))
                .ToArray();
            _fleetMemberSidebarChatLatestSequence = Math.Max(
                _fleetMemberSidebarChatLatestSequence,
                history.LatestSequence);
            var changed = _fleetMemberSidebarChatPreview.Count != next.Length ||
                          _fleetMemberSidebarChatPreview
                              .Select(row => row.Message)
                              .Zip(next.Select(row => row.Message))
                              .Any(pair => pair.First != pair.Second);
            _fleetMemberSidebarChatPreviewLoaded = true;
            if (!changed)
            {
                return;
            }

            _fleetMemberSidebarChatPreview.Clear();
            _fleetMemberSidebarChatPreview.AddRange(next);
            if (ShouldRefreshFleetMemberSidebarChatPreview())
            {
                RefreshFleetRightContextSidebar();
            }
        }
        catch
        {
            // The regular fleet chat poll retries without disturbing the visible member panel.
        }
        finally
        {
            _isRefreshingFleetMemberSidebarChatPreview = false;
        }
    }

    private void ResetFleetMemberSidebarChatPreview()
    {
        _fleetMemberSidebarChatPreview.Clear();
        _fleetMemberSidebarChatPreviewLoaded = false;
        _fleetMemberSidebarChatLatestSequence = 0;
    }

    private void NavigateToFleetChatFromMemberPreview()
    {
        var fleetChannel = _fleetChatChannels.FirstOrDefault(channel =>
            channel.Type == FleetChatChannelTypes.Fleet);
        if (fleetChannel is not null &&
            (_activeFleetChatChannel is null ||
             !_activeFleetChatChannel.ChannelId.Equals(fleetChannel.ChannelId, StringComparison.OrdinalIgnoreCase)))
        {
            _activeFleetChatChannel = fleetChannel;
            _fleetChatLatestSequence = 0;
            _fleetChatMessages.Clear();
            ResetFleetChatPagingState();
            SelectActiveFleetChatChannel();
        }

        FleetSubTabs.SelectedItem = FleetChatTab;
    }

    private async Task OpenFleetChatAsync()
    {
        ApplyFleetChatAvailability();
        if (!CanUseFleetChat)
        {
            return;
        }

        await Task.WhenAll(
            RefreshFleetChatChannelsAsync(showErrors: true),
            RefreshFleetAnnouncementsAsync(showErrors: false));
        await RefreshFleetChatMessagesAsync(showErrors: false, forceFullHistory: true);
    }

    private async Task RefreshFleetChatChannelsAsync(bool showErrors)
    {
        if (!CanUseFleetChat)
        {
            return;
        }

        var session = _accountSessionCoordinator.Capture();
        var fleetCode = _fleetCode;
        var lane = new FleetChatDirectoryLane(session, fleetCode.Trim().ToUpperInvariant());
        if (!_refreshingFleetChatDirectoryLanes.Add(lane))
        {
            return;
        }

        try
        {
            var escapedFleetCode = Uri.EscapeDataString(fleetCode);
            var snapshot = await _relayClient.GetFromJsonAsync<FleetChatChannelListContract>(
                $"api/fleets/chat/channels?fleetCode={escapedFleetCode}");
            if (snapshot is null)
            {
                throw new InvalidDataException("通讯频道数据为空。");
            }

            if (!IsFleetChatDirectoryCurrent(lane))
            {
                return;
            }

            var activeId = _activeFleetChatChannel?.ChannelId;
            _fleetChatChannels.Clear();
            foreach (var channel in snapshot.Channels)
            {
                _fleetChatChannels.Add(new FleetChatChannelRow(channel));
            }

            _fleetChatTotalUnread = snapshot.TotalUnread;
            UpdateFleetChatRailUnreadLabel();
            var next = _fleetChatChannels.FirstOrDefault(channel =>
                           !string.IsNullOrWhiteSpace(activeId) &&
                           channel.ChannelId.Equals(activeId, StringComparison.OrdinalIgnoreCase)) ??
                       _fleetChatChannels.FirstOrDefault();
            if (next is null)
            {
                ResetFleetChat("当前没有可访问的通讯频道。", clearChannels: false);
                return;
            }

            if (_activeFleetChatChannel is null ||
                !_activeFleetChatChannel.ChannelId.Equals(next.ChannelId, StringComparison.OrdinalIgnoreCase))
            {
                _activeFleetChatChannel = next;
                _fleetChatLatestSequence = 0;
                _fleetChatMessages.Clear();
                ResetFleetChatPagingState();
            }
            else
            {
                _activeFleetChatChannel = next;
            }

            SelectActiveFleetChatChannel();
            RenderFleetChat();
            FleetChatSyncStateText.Text = $"已同步 · {snapshot.ServerTime.ToLocalTime():HH:mm:ss}";
            FleetChatSyncStateText.Foreground = StatusPalette.SuccessBrush;
            if (ShouldRefreshFleetOverlayChat())
            {
                RefreshOverlayWindow();
            }
        }
        catch (Exception ex)
        {
            if (!IsFleetChatDirectoryCurrent(lane))
            {
                return;
            }

            if (showErrors)
            {
                FleetChatStatusText.Text = UserFacingError.Describe(ex, "频道暂时无法同步，请稍后重试。");
                FleetChatStatusText.Foreground = StatusPalette.DangerBrush;
            }

            FleetChatSyncStateText.Text = "同步暂不可用";
            FleetChatSyncStateText.Foreground = StatusPalette.WarningBrush;
        }
        finally
        {
            _refreshingFleetChatDirectoryLanes.Remove(lane);
        }
    }

    private void SelectActiveFleetChatChannel()
    {
        _isSelectingFleetChatChannel = true;
        foreach (var channel in _fleetChatChannels)
        {
            channel.IsSelected = ReferenceEquals(channel, _activeFleetChatChannel);
        }

        FleetChatChannelList.SelectedItem = _activeFleetChatChannel;
        _isSelectingFleetChatChannel = false;
    }

    private async void FleetChatChannelList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isSelectingFleetChatChannel || FleetChatChannelList.SelectedItem is not FleetChatChannelRow selected)
        {
            return;
        }

        _activeFleetChatChannel = selected;
        _fleetChatLatestSequence = 0;
        _fleetChatMessages.Clear();
        ResetFleetChatPagingState();
        SelectActiveFleetChatChannel();
        RenderFleetChat();
        await RefreshFleetChatMessagesAsync(showErrors: true);
    }

    private async Task RefreshFleetChatMessagesAsync(bool showErrors, bool forceFullHistory = false)
    {
        var activeChannel = _activeFleetChatChannel;
        if (!CanUseFleetChat || activeChannel is null)
        {
            return;
        }

        var session = _accountSessionCoordinator.Capture();
        var fleetCode = _fleetCode;
        var activeChannelId = activeChannel.ChannelId;
        var lane = CreateFleetChatOperationLane(session, fleetCode, activeChannelId);
        if (!_refreshingFleetChatMessageLanes.Add(lane))
        {
            return;
        }

        try
        {
            var wasEmpty = _fleetChatMessages.Count == 0;
            var previousLatestSequence = _fleetChatLatestSequence;
            var shouldFollowLatest = wasEmpty || _fleetChatFollowLatest;
            var afterSequence = forceFullHistory ? 0 : _fleetChatLatestSequence;
            var history = await _relayClient.GetFromJsonAsync<FleetChatHistoryContract>(
                $"api/fleets/chat/messages?fleetCode={Uri.EscapeDataString(fleetCode)}" +
                $"&channelId={Uri.EscapeDataString(activeChannelId)}&after={afterSequence}&limit=50");
            if (history is null)
            {
                throw new InvalidDataException("通讯消息数据为空。");
            }

            if (!IsFleetChatOperationCurrent(lane) ||
                !activeChannelId.Equals(history.ChannelId, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            ReconcileFleetChatMessages(history.Messages);

            if (wasEmpty)
            {
                _fleetChatHasOlder = history.HasOlder;
            }

            _fleetChatLatestSequence = Math.Max(_fleetChatLatestSequence, history.LatestSequence);
            if (forceFullHistory)
            {
                _fleetChatNeedsFullHistoryRefresh = false;
            }
            FleetChatInputBox.IsEnabled = history.CanSend;
            FleetChatSendButton.IsEnabled = history.CanSend && !_isSendingFleetChatMessage;
            FleetChatStatusText.Text = history.CanSend
                ? activeChannel.Type == FleetChatChannelTypes.Squad
                    ? "仅当前小队成员可见 · Enter 发送，Shift+Enter 换行"
                    : "仅当前舰队成员可见 · Enter 发送，Shift+Enter 换行"
                : history.Error ?? "当前无法发送消息。";
            FleetChatStatusText.Foreground = history.CanSend
                ? StatusPalette.DisabledBrush
                : StatusPalette.WarningBrush;
            RenderFleetChat();
            if (_fleetChatMessages.Count > 0 && shouldFollowLatest)
            {
                _fleetChatFollowLatest = true;
                ChatHistoryViewport.ScrollToLatest(FleetChatMessageList);
            }
            else if (_fleetChatLatestSequence > previousLatestSequence)
            {
                FleetChatJumpToLatestButton.Visibility = Visibility.Visible;
            }

            if (history.CanSend && _fleetChatLatestSequence > 0 && IsFleetChatVisible() && IsActive)
            {
                using var response = await _relayClient.PostJsonAsync(
                    "api/fleets/chat/read",
                    new FleetChatMarkReadRequestContract(fleetCode, activeChannelId, _fleetChatLatestSequence));
                if (response.IsSuccessStatusCode &&
                    IsFleetChatOperationCurrent(lane) &&
                    _activeFleetChatChannel is { } currentChannel)
                {
                    currentChannel.UnreadCount = 0;
                    _fleetChatTotalUnread = _fleetChatChannels.Sum(channel => channel.UnreadCount);
                    UpdateFleetChatRailUnreadLabel();
                }
            }
        }
        catch (Exception ex)
        {
            if (IsFleetChatOperationCurrent(lane) && showErrors)
            {
                FleetChatStatusText.Text = UserFacingError.Describe(ex, "消息暂时无法同步，请稍后重试。");
                FleetChatStatusText.Foreground = StatusPalette.DangerBrush;
            }
        }
        finally
        {
            _refreshingFleetChatMessageLanes.Remove(lane);
        }
    }

    private void ReconcileFleetChatMessages(IEnumerable<FleetChatMessageContract> incoming)
    {
        var reconciled = FleetChatMessageReconciler.Reconcile(
            _fleetChatMessages.Select(row => row.Message),
            incoming);
        for (var index = 0; index < reconciled.Length; index++)
        {
            var message = reconciled[index];
            if (index >= _fleetChatMessages.Count)
            {
                _fleetChatMessages.Add(new FleetChatMessageRow(message, _accountId));
                continue;
            }

            var existing = _fleetChatMessages[index].Message;
            if (existing.MessageId.Equals(message.MessageId, StringComparison.OrdinalIgnoreCase))
            {
                if (existing != message)
                {
                    _fleetChatMessages[index] = new FleetChatMessageRow(message, _accountId);
                }

                continue;
            }

            _fleetChatMessages.Insert(index, new FleetChatMessageRow(message, _accountId));
        }

        while (_fleetChatMessages.Count > reconciled.Length)
        {
            _fleetChatMessages.RemoveAt(_fleetChatMessages.Count - 1);
        }
    }

    private async void FleetChatSendButton_Click(object sender, RoutedEventArgs e)
    {
        await SendFleetChatMessageAsync(FleetChatInputBox.Text.Trim(), null);
    }

    private async Task SendFleetChatMessageAsync(string text, ChatAttachmentContract? attachment)
    {
        var activeChannel = _activeFleetChatChannel;
        if (activeChannel is null || !CanUseFleetChat)
        {
            return;
        }

        if (text.Length == 0 && attachment is null)
        {
            FleetChatStatusText.Text = "输入消息后再发送。";
            FleetChatStatusText.Foreground = StatusPalette.WarningBrush;
            return;
        }

        var session = _accountSessionCoordinator.Capture();
        var fleetCode = _fleetCode;
        var channelId = activeChannel.ChannelId;
        var lane = CreateFleetChatOperationLane(session, fleetCode, channelId);
        if (!_sendingFleetChatMessageLanes.Add(lane))
        {
            return;
        }

        FleetChatSendButton.IsEnabled = false;
        FleetChatAttachmentButton.IsEnabled = false;
        FleetChatStatusText.Text = "正在发送…";
        FleetChatStatusText.Foreground = StatusPalette.InfoBrush;
        try
        {
            using var response = await _relayClient.PostJsonAsync(
                "api/fleets/chat/messages",
                new FleetChatSendRequestContract(
                    fleetCode,
                    channelId,
                    text,
                    Guid.NewGuid().ToString("N"),
                    attachment));
            var mutation = await response.Content.ReadFromJsonAsync<FleetChatMutationResponseContract>();
            if (!IsFleetChatOperationCurrent(lane))
            {
                return;
            }

            if (!response.IsSuccessStatusCode || mutation?.Message is null)
            {
                var error = mutation?.Error ?? await ReadResponseErrorAsync(response);
                if (!IsFleetChatOperationCurrent(lane))
                {
                    return;
                }

                FleetChatStatusText.Text = error;
                FleetChatStatusText.Foreground = StatusPalette.DangerBrush;
                return;
            }

            ReconcileFleetChatMessages([mutation.Message]);

            _fleetChatLatestSequence = Math.Max(_fleetChatLatestSequence, mutation.Message.Sequence);
            FleetChatInputBox.Clear();
            RenderFleetChat();
            _fleetChatFollowLatest = true;
            FleetChatJumpToLatestButton.Visibility = Visibility.Collapsed;
            ChatHistoryViewport.ScrollToLatest(FleetChatMessageList);
            FleetChatStatusText.Text = "已发送";
            FleetChatStatusText.Foreground = StatusPalette.SuccessBrush;
            FleetChatInputBox.Focus();
            await RefreshFleetChatChannelsAsync(showErrors: false);
        }
        catch (Exception ex)
        {
            if (IsFleetChatOperationCurrent(lane))
            {
                FleetChatStatusText.Text = UserFacingError.Describe(ex, "消息未发送，请检查网络后重试。");
                FleetChatStatusText.Foreground = StatusPalette.DangerBrush;
            }
        }
        finally
        {
            _sendingFleetChatMessageLanes.Remove(lane);
            if (IsFleetChatOperationCurrent(lane))
            {
                FleetChatSendButton.IsEnabled = CanUseFleetChat && _activeFleetChatChannel?.CanSend == true;
                FleetChatAttachmentButton.IsEnabled = CanUseFleetChat && _activeFleetChatChannel?.CanSend == true;
            }
        }
    }

    private void FleetChatInputBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter || Keyboard.Modifiers.HasFlag(ModifierKeys.Shift))
        {
            return;
        }

        e.Handled = true;
        FleetChatSendButton_Click(FleetChatSendButton, new RoutedEventArgs());
    }

    private void ApplyFleetChatAvailability()
    {
        var enabled = CanUseFleetChat && _activeFleetChatChannel?.CanSend != false;
        FleetChatInputBox.IsEnabled = enabled;
        FleetChatSendButton.IsEnabled = enabled && !_isSendingFleetChatMessage;
        FleetChatAttachmentButton.IsEnabled = enabled && !_isSendingFleetChatMessage;
        if (CanUseFleetChat)
        {
            return;
        }

        FleetChatStatusText.Text = !_hasFleet
            ? "加入舰队后可以使用通讯。"
            : "完成登录与身份验证后可以使用通讯。";
        FleetChatStatusText.Foreground = StatusPalette.WarningBrush;
        FleetChatSyncStateText.Text = "通讯已暂停";
        FleetChatSyncStateText.Foreground = StatusPalette.WarningBrush;
    }

    private void RenderFleetChat()
    {
        RefreshFleetCommunicationOverview();
        FleetChatActiveChannelTitle.Text = _activeFleetChatChannel?.DisplayName ?? "选择频道";
        FleetChatActiveChannelScope.Text = _activeFleetChatChannel?.Type == FleetChatChannelTypes.Squad
            ? "当前小队成员通讯"
            : "当前舰队成员通讯";
        FleetChatMessageEmptyState.Visibility = _fleetChatMessages.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        FleetChatMessageList.Visibility = _fleetChatMessages.Count == 0
            ? Visibility.Collapsed
            : Visibility.Visible;
        ApplyFleetChatAvailability();
    }

    private void RefreshFleetCommunicationOverview()
    {
        if (FleetCommunicationAnnouncementPanel is null)
        {
            return;
        }

        var current = _fleetCurrentAnnouncement;
        var hasAnnouncement = current is not null ||
                              !string.IsNullOrWhiteSpace(_fleetNoticeTitle) ||
                              !string.IsNullOrWhiteSpace(_fleetNoticeContent);
        var hasAnnouncementAccess = hasAnnouncement ||
                                    _fleetAnnouncementHistory.Count > 0 ||
                                    _fleetAnnouncementCanManage;
        FleetCommunicationAnnouncementPanel.Visibility = hasAnnouncementAccess
            ? Visibility.Visible
            : Visibility.Collapsed;
        if (hasAnnouncement)
        {
            FleetCommunicationAnnouncementTitleText.Text = string.IsNullOrWhiteSpace(current?.Title ?? _fleetNoticeTitle)
                ? "舰队公告"
                : current?.Title ?? _fleetNoticeTitle;
            FleetCommunicationAnnouncementContentText.Text = string.IsNullOrWhiteSpace(current?.Content ?? _fleetNoticeContent)
                ? "指挥官暂未填写公告正文。"
                : current?.Content ?? _fleetNoticeContent;
            var publishedAt = current?.PublishedAt ?? _fleetNoticePublishedAt;
            FleetCommunicationAnnouncementTimeText.Text = publishedAt is { } announcementTime
                ? CommunicationTimeFormatter.Format(announcementTime)
                : "历史公告";
            FleetCommunicationAnnouncementAuthorText.Text = current is null
                ? ""
                : FormatFleetAnnouncementAuthor(current.Author);
        }
        else if (hasAnnouncementAccess)
        {
            FleetCommunicationAnnouncementTitleText.Text = "暂无当前公告";
            FleetCommunicationAnnouncementContentText.Text = _fleetAnnouncementCanManage
                ? "发布一条公告，让舰队成员快速掌握当前安排。"
                : "当前没有正在广播的舰队公告。";
            FleetCommunicationAnnouncementTimeText.Text = _fleetAnnouncementHistory.Count > 0
                ? $"历史 {_fleetAnnouncementHistory.Count} 条"
                : "未发布";
            FleetCommunicationAnnouncementAuthorText.Text = "";
        }

        FleetCommunicationAnnouncementHistoryButton.Visibility = hasAnnouncementAccess
            ? Visibility.Visible
            : Visibility.Collapsed;
        FleetCommunicationAnnouncementHistoryButton.Content = _fleetAnnouncementHistory.Count > 0
            ? $"历史公告 ({_fleetAnnouncementHistory.Count})"
            : "历史公告";
        FleetCommunicationAnnouncementManageButton.Visibility = _fleetAnnouncementCanManage
            ? Visibility.Visible
            : Visibility.Collapsed;
        FleetCommunicationAnnouncementManageButton.Content = current is null
            ? "发布公告"
            : "管理公告";

        FleetCommunicationExternalContactsPanel.Visibility = _fleetExternalContacts.Any(contact =>
            !string.IsNullOrWhiteSpace(contact.Platform) && !string.IsNullOrWhiteSpace(contact.Value))
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void RefreshFleetCommunicationTimeLabels()
    {
        var now = DateTimeOffset.Now;
        foreach (var row in _fleetChatMessages)
        {
            row.RefreshTime(now);
        }

        foreach (var row in _fleetMemberSidebarChatPreview)
        {
            row.RefreshTime(now);
        }

        if (FleetCommunicationAnnouncementPanel?.Visibility == Visibility.Visible &&
            _fleetNoticePublishedAt is { } publishedAt)
        {
            FleetCommunicationAnnouncementTimeText.Text = CommunicationTimeFormatter.Format(publishedAt, now);
        }

        RefreshFleetAnnouncementTimeLabels(now);
    }

    private void FleetCommunicationExternalContactButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: FleetExternalContactRow contact } ||
            string.IsNullOrWhiteSpace(contact.Value))
        {
            return;
        }

        try
        {
            System.Windows.Clipboard.SetText(contact.Value.Trim());
            FleetChatStatusText.Text = $"已复制 {contact.Platform} 联络信息";
            FleetChatStatusText.Foreground = StatusPalette.SuccessBrush;
        }
        catch
        {
            FleetChatStatusText.Text = "暂时无法写入剪贴板，请稍后重试。";
            FleetChatStatusText.Foreground = StatusPalette.WarningBrush;
        }
    }

    private void ResetFleetChat(string status, bool clearChannels = true)
    {
        if (clearChannels)
        {
            _fleetChatChannels.Clear();
        }

        _fleetChatMessages.Clear();
        ResetFleetChatPagingState();
        ResetFleetMemberSidebarChatPreview();
        _activeFleetChatChannel = null;
        _fleetChatLatestSequence = 0;
        _fleetChatTotalUnread = 0;
        ResetFleetAnnouncements();
        ResetFleetOverlayChatProjection();
        UpdateFleetChatRailUnreadLabel();
        FleetChatStatusText.Text = status;
        FleetChatStatusText.Foreground = StatusPalette.WarningBrush;
        RenderFleetChat();
    }

    private async void FleetChatMessageList_ScrollChanged(object sender, ScrollChangedEventArgs e)
    {
        if (e.OriginalSource is not ScrollViewer viewer)
        {
            return;
        }

        _fleetChatFollowLatest = ChatHistoryViewport.IsNearBottom(viewer);
        FleetChatJumpToLatestButton.Visibility = _fleetChatFollowLatest
            ? Visibility.Collapsed
            : Visibility.Visible;
        UpdateFleetChatHistoryStatus(viewer);
        if (ChatHistoryViewport.ShouldLoadOlder(viewer) && _fleetChatHasOlder && !_isLoadingOlderFleetChat)
        {
            await LoadOlderFleetChatMessagesAsync();
        }
    }

    private async Task LoadOlderFleetChatMessagesAsync()
    {
        if (_isLoadingOlderFleetChat || !_fleetChatHasOlder || _activeFleetChatChannel is null ||
            _fleetChatMessages.Count == 0 || !CanUseFleetChat)
        {
            return;
        }

        var channelId = _activeFleetChatChannel.ChannelId;
        var before = _fleetChatMessages.Min(row => row.Message.Sequence);
        _isLoadingOlderFleetChat = true;
        FleetChatHistoryStatusText.Text = "正在加载更早消息…";
        FleetChatHistoryStatusPanel.Visibility = ChatHistoryViewport.Find(FleetChatMessageList) is { } viewer &&
                                                 ChatHistoryViewport.IsNearTop(viewer)
            ? Visibility.Visible
            : Visibility.Collapsed;
        try
        {
            var history = await _relayClient.GetFromJsonAsync<FleetChatHistoryContract>(
                $"api/fleets/chat/messages?fleetCode={Uri.EscapeDataString(_fleetCode)}" +
                $"&channelId={Uri.EscapeDataString(channelId)}&before={before}&limit=50");
            if (history is null || _activeFleetChatChannel is null ||
                !_activeFleetChatChannel.ChannelId.Equals(channelId, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            var anchor = ChatHistoryViewport.Capture(FleetChatMessageList);
            ReconcileFleetChatMessages(history.Messages);
            _fleetChatHasOlder = history.HasOlder;
            ChatHistoryViewport.RestoreAfterPrepend(FleetChatMessageList, anchor);
        }
        catch
        {
            FleetChatStatusText.Text = "更早消息加载失败，滚到顶部可重试。";
            FleetChatStatusText.Foreground = StatusPalette.WarningBrush;
        }
        finally
        {
            _isLoadingOlderFleetChat = false;
            UpdateFleetChatHistoryStatus(ChatHistoryViewport.Find(FleetChatMessageList));
        }
    }

    private void UpdateFleetChatHistoryStatus(ScrollViewer? viewer)
    {
        var atTop = viewer is not null && ChatHistoryViewport.IsNearTop(viewer);
        if (_isLoadingOlderFleetChat)
        {
            FleetChatHistoryStatusText.Text = "正在加载更早消息…";
            FleetChatHistoryStatusPanel.Visibility = atTop ? Visibility.Visible : Visibility.Collapsed;
            return;
        }

        FleetChatHistoryStatusPanel.Visibility = Visibility.Collapsed;
    }

    private void FleetChatJumpToLatestButton_Click(object sender, RoutedEventArgs e)
    {
        _fleetChatFollowLatest = true;
        FleetChatJumpToLatestButton.Visibility = Visibility.Collapsed;
        ChatHistoryViewport.ScrollToLatest(FleetChatMessageList);
    }

    private void ResetFleetChatPagingState()
    {
        _fleetChatHasOlder = false;
        _isLoadingOlderFleetChat = false;
        _fleetChatFollowLatest = true;
        if (FleetChatHistoryStatusPanel is not null)
        {
            FleetChatHistoryStatusPanel.Visibility = Visibility.Collapsed;
            FleetChatJumpToLatestButton.Visibility = Visibility.Collapsed;
        }
    }

    private bool ShouldRefreshFleetOverlayChat() =>
        _overlayWindow is { IsVisible: true } &&
        _overlaySettings.ShowChat &&
        ResolveCurrentOverlayScene().Context.Kind == OverlaySceneKind.Fleet;

    private async Task RefreshFleetOverlayChatAsync()
    {
        if (_isRefreshingFleetOverlayChat || !CanUseFleetChat)
        {
            return;
        }

        var desiredChannels = ResolveFleetOverlayChatChannels();
        var scope = OverlayDisplaySettings.NormalizeFleetChatScope(_overlaySettings.FleetChatScope);
        var signature = $"{_fleetCode}|{scope}|{string.Join('|', desiredChannels.Select(channel => channel.ChannelId))}";
        if (!_fleetOverlayChatProjectionSignature.Equals(signature, StringComparison.OrdinalIgnoreCase))
        {
            ResetFleetOverlayChatProjection();
            _fleetOverlayChatProjectionSignature = signature;
            foreach (var channel in desiredChannels)
            {
                _fleetOverlayChatChannels[channel.ChannelId] = new FleetOverlayChatChannelState(channel);
            }
        }

        _fleetOverlayChatProjectionActive = true;
        if (desiredChannels.Length == 0)
        {
            return;
        }

        _isRefreshingFleetOverlayChat = true;
        var appended = false;
        try
        {
            foreach (var channel in desiredChannels)
            {
                if (!_fleetOverlayChatChannels.TryGetValue(channel.ChannelId, out var state))
                {
                    continue;
                }

                var history = await _relayClient.GetFromJsonAsync<FleetChatHistoryContract>(
                    $"api/fleets/chat/messages?fleetCode={Uri.EscapeDataString(_fleetCode)}" +
                    $"&channelId={Uri.EscapeDataString(channel.ChannelId)}&after={state.LatestSequence}");
                if (history is null ||
                    !history.ChannelId.Equals(channel.ChannelId, StringComparison.OrdinalIgnoreCase) ||
                    !state.ReceiveSession.TryEstablishBaseline(
                        channel.ChannelId,
                        state.ReceiveSessionVersion,
                        history.LatestSequence))
                {
                    continue;
                }

                foreach (var message in history.Messages.OrderBy(message => message.Sequence))
                {
                    state.LatestSequence = Math.Max(state.LatestSequence, message.Sequence);
                    if (!state.ReceiveSession.Accepts(channel.ChannelId, message.Sequence))
                    {
                        continue;
                    }

                    _fleetOverlayChatMessages.Add(CreateFleetOverlayChatMessage(message, channel, scope));
                    appended = true;
                }

                state.LatestSequence = Math.Max(state.LatestSequence, history.LatestSequence);
            }

            while (_fleetOverlayChatMessages.Count > 100)
            {
                _fleetOverlayChatMessages.RemoveAt(0);
            }
        }
        catch
        {
            // The regular two-second poll will retry without disturbing the current projection.
        }
        finally
        {
            _isRefreshingFleetOverlayChat = false;
        }

        if (appended)
        {
            RenderOverlayEditor();
            RefreshOverlayInspector();
            RefreshOverlayWindow();
        }
    }

    private FleetChatChannelRow[] ResolveFleetOverlayChatChannels()
    {
        var scope = OverlayDisplaySettings.NormalizeFleetChatScope(_overlaySettings.FleetChatScope);
        return _fleetChatChannels
            .Where(channel => scope switch
            {
                OverlayFleetChatScope.Squad => channel.Type == FleetChatChannelTypes.Squad,
                OverlayFleetChatScope.All =>
                    channel.Type == FleetChatChannelTypes.Fleet ||
                    channel.Type == FleetChatChannelTypes.Squad,
                _ => channel.Type == FleetChatChannelTypes.Fleet
            })
            .OrderBy(channel => channel.Type == FleetChatChannelTypes.Fleet ? 0 : 1)
            .ToArray();
    }

    private OverlayChatMessage CreateFleetOverlayChatMessage(
        FleetChatMessageContract message,
        FleetChatChannelRow channel,
        OverlayFleetChatScope scope)
    {
        var projectionId = ResolveFleetOverlayChatProjectionId();
        var sourceLabel = scope == OverlayFleetChatScope.All
            ? channel.Type == FleetChatChannelTypes.Squad
                ? _language.Equals("zh", StringComparison.OrdinalIgnoreCase) ? "小队" : "SQUAD"
                : _language.Equals("zh", StringComparison.OrdinalIgnoreCase) ? "舰队" : "FLEET"
            : null;
        return new OverlayChatMessage(
            ++_fleetOverlayChatProjectionSequence,
            projectionId,
            message.SenderCallsign,
            message.SenderGameId,
            message.Text,
            message.CreatedAt,
            false,
            !string.IsNullOrWhiteSpace(_accountId) &&
            message.SenderAccountId.Equals(_accountId, StringComparison.OrdinalIgnoreCase),
            string.IsNullOrWhiteSpace(message.SenderRoleColor) ? "#69CCFF" : message.SenderRoleColor,
            sourceLabel);
    }

    private string ResolveFleetOverlayChatProjectionId()
    {
        var scope = OverlayDisplaySettings.NormalizeFleetChatScope(_overlaySettings.FleetChatScope);
        return string.IsNullOrWhiteSpace(_fleetCode) || ResolveFleetOverlayChatChannels().Length == 0
            ? ""
            : $"overlay-fleet-chat:{_fleetCode.Trim().ToUpperInvariant()}:{scope}";
    }

    private string ResolveFleetOverlayChatTitle()
    {
        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        return OverlayDisplaySettings.NormalizeFleetChatScope(_overlaySettings.FleetChatScope) switch
        {
            OverlayFleetChatScope.Squad => zh ? "小队通讯" : "SQUAD COMMS",
            OverlayFleetChatScope.All => zh ? "综合通讯" : "ALL COMMS",
            _ => zh ? "舰队通讯" : "FLEET COMMS"
        };
    }

    private OverlayChatMessage[] ResolveFleetOverlayChatMessages() =>
        _fleetOverlayChatMessages
            .Where(message => message.ChannelId.Equals(ResolveFleetOverlayChatProjectionId(), StringComparison.OrdinalIgnoreCase))
            .OrderBy(message => message.Sequence)
            .ToArray();

    private void ResetFleetOverlayChatProjection()
    {
        _fleetOverlayChatChannels.Clear();
        _fleetOverlayChatMessages.Clear();
        _fleetOverlayChatProjectionSignature = "";
        _fleetOverlayChatProjectionSequence = 0;
        _fleetOverlayChatProjectionActive = false;
    }

    private void UpdateFleetChatRailUnreadLabel()
    {
        RefreshNavigationActivityBadges();
        if (FleetChatRailButton is null)
        {
            return;
        }

        var label = _language == "zh" ? "通讯" : "Comms";
        FleetChatRailButton.Content = _fleetChatTotalUnread > 0
            ? $"{label}  {(_fleetChatTotalUnread > 99 ? "99+" : _fleetChatTotalUnread.ToString())}"
            : label;
    }

    private sealed class FleetOverlayChatChannelState
    {
        public FleetOverlayChatChannelState(FleetChatChannelRow channel)
        {
            Channel = channel;
            ReceiveSessionVersion = ReceiveSession.Begin(channel.ChannelId);
        }

        public FleetChatChannelRow Channel { get; }
        public OverlayChatReceiveSession ReceiveSession { get; } = new();
        public long ReceiveSessionVersion { get; }
        public long LatestSequence { get; set; }
    }
}

public sealed class FleetChatChannelRow : INotifyPropertyChanged
{
    private bool _isSelected;
    private int _unreadCount;

    public FleetChatChannelRow(FleetChatChannelContract channel)
    {
        Channel = channel;
        _unreadCount = channel.UnreadCount;
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public FleetChatChannelContract Channel { get; }
    public string ChannelId => Channel.ChannelId;
    public string Type => Channel.Type;
    public string DisplayName => Channel.DisplayName;
    public bool CanSend => Channel.CanSend;
    public string IconGlyph => Type == FleetChatChannelTypes.Squad ? "\uE902" : "\uE8BD";
    public Brush AccentBrush => Type == FleetChatChannelTypes.Squad
        ? new SolidColorBrush(Color.FromRgb(132, 158, 255))
        : new SolidColorBrush(Color.FromRgb(79, 201, 255));
    public string PreviewText => string.IsNullOrWhiteSpace(Channel.LastMessagePreview)
        ? Type == FleetChatChannelTypes.Squad ? "小队内部通讯" : "全舰队通讯"
        : Channel.LastMessagePreview;
    public string UnreadText => _unreadCount > 99 ? "99+" : _unreadCount.ToString();
    public Visibility UnreadVisibility => _unreadCount > 0 ? Visibility.Visible : Visibility.Collapsed;

    public int UnreadCount
    {
        get => _unreadCount;
        set
        {
            if (_unreadCount == value) return;
            _unreadCount = value;
            OnChanged();
            OnChanged(nameof(UnreadText));
            OnChanged(nameof(UnreadVisibility));
        }
    }

    public bool IsSelected
    {
        get => _isSelected;
        set
        {
            if (_isSelected == value) return;
            _isSelected = value;
            OnChanged();
        }
    }

    private void OnChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

public sealed class FleetChatMessageRow : INotifyPropertyChanged
{
    private string _timeText;

    public FleetChatMessageRow(FleetChatMessageContract message, string? localAccountId)
    {
        Message = message;
        IsSelf = !string.IsNullOrWhiteSpace(localAccountId) &&
                 message.SenderAccountId.Equals(localAccountId, StringComparison.OrdinalIgnoreCase);
        SenderRoleBrush = TryCreateBrush(message.SenderRoleColor);
        _timeText = CommunicationTimeFormatter.Format(message.CreatedAt);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public FleetChatMessageContract Message { get; }
    public string AccountId => Message.SenderAccountId;
    public string SenderCallsign => Message.SenderCallsign;
    public string SenderGameId => Message.SenderGameId;
    public string SenderGameIdText => $"@ {Message.SenderGameId}";
    public string SenderRoleTitle => Message.SenderRoleTitle;
    public string? SenderAvatarImageData => Message.SenderAvatarImageData;
    public string Text => Message.Text;
    public ChatAttachmentContract? Attachment => Message.Attachment;
    public Visibility TextVisibility => ChatAttachmentPresentation.TextVisibility(Text);
    public Visibility AttachmentVisibility => ChatAttachmentPresentation.AttachmentVisibility(Attachment);
    public string AttachmentTitle => Attachment?.Title ?? "";
    public string AttachmentSummary => Attachment?.Summary ?? "";
    public string AttachmentActionText => ChatAttachmentPresentation.ActionText(Attachment);
    public bool AttachmentActionEnabled => ChatAttachmentPresentation.ActionEnabled(Attachment);
    public string AttachmentTypeText => ChatAttachmentPresentation.TypeText(Attachment);
    public string AttachmentStatusText => ChatAttachmentPresentation.StatusText(Attachment);
    public string AttachmentStatusBrush => ChatAttachmentPresentation.StatusBrush(Attachment);
    public Visibility AttachmentStatusVisibility => ChatAttachmentPresentation.StatusVisibility(Attachment);
    public string AttachmentRoomActivityText => ChatAttachmentPresentation.RoomActivityText(Attachment);
    public string AttachmentRoomFactsText => ChatAttachmentPresentation.RoomFactsText(Attachment);
    public Visibility AttachmentRoomDetailsVisibility => ChatAttachmentPresentation.RoomDetailsVisibility(Attachment);
    public string TimeText => _timeText;
    public string Initials => string.IsNullOrWhiteSpace(SenderCallsign)
        ? "?"
        : string.Concat(SenderCallsign.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Take(2)
            .Select(part => char.ToUpperInvariant(part[0])));
    public Brush SenderRoleBrush { get; }
    public bool IsSelf { get; }
    public bool IsLocal => IsSelf;
    public bool IsSystem => false;
    public Visibility RoleVisibility => string.IsNullOrWhiteSpace(SenderRoleTitle)
        ? Visibility.Collapsed
        : Visibility.Visible;

    public void RefreshTime(DateTimeOffset now)
    {
        var next = CommunicationTimeFormatter.Format(Message.CreatedAt, now);
        if (string.Equals(_timeText, next, StringComparison.Ordinal))
        {
            return;
        }

        _timeText = next;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(TimeText)));
    }

    private static Brush TryCreateBrush(string? value)
    {
        try
        {
            return new SolidColorBrush((Color)ColorConverter.ConvertFromString(value ?? "#72C7F3"));
        }
        catch
        {
            return new SolidColorBrush(Color.FromRgb(114, 199, 243));
        }
    }
}
