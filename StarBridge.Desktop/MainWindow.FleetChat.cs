using StarBridge.Core.FleetChat;
using StarBridge.Core.Chat;
using StarBridge.Desktop.Theming;
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
        FleetChatMessageList.ItemsSource = _fleetChatMessages;
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
                fleetChannel.ChannelId,
                _fleetMemberSidebarChatPreview.Select(row => row.Message),
                history.Messages);
            var next = reconciled
                .OrderByDescending(message => message.Sequence)
                .Take(4)
                .OrderBy(message => message.Sequence)
                .Select(message => new FleetChatMessageRow(message, _accountId, this))
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
                throw new InvalidDataException("组织聊天数据为空。");
            }

            if (!IsFleetChatDirectoryCurrent(lane))
            {
                return;
            }

            var activeId = _activeFleetChatChannel?.ChannelId;
            _fleetChatChannels.Clear();
            foreach (var channel in snapshot.Channels.Where(channel =>
                         channel.Type == FleetChatChannelTypes.Fleet))
            {
                _fleetChatChannels.Add(new FleetChatChannelRow(channel, this));
            }

            _fleetChatTotalUnread = _fleetChatChannels.Sum(channel => channel.UnreadCount);
            UpdateFleetChatRailUnreadLabel();
            var next = _fleetChatChannels.FirstOrDefault(channel =>
                           !string.IsNullOrWhiteSpace(activeId) &&
                           channel.ChannelId.Equals(activeId, StringComparison.OrdinalIgnoreCase)) ??
                       _fleetChatChannels.FirstOrDefault();
            if (next is null)
            {
                ResetFleetChat("当前没有可访问的组织聊天。", clearChannels: false);
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
                FleetChatStatusText.Text = UserFacingError.Describe(ex, "组织聊天暂时无法同步，请稍后重试。");
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

            ReconcileFleetChatMessages(activeChannelId, history.Messages);

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
                ? "仅当前组织成员可见 · Enter 发送，Shift+Enter 换行"
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

    private void ReconcileFleetChatMessages(
        string channelId,
        IEnumerable<FleetChatMessageContract> incoming)
    {
        var reconciled = FleetChatMessageReconciler.Reconcile(
            channelId,
            _fleetChatMessages.Select(row => row.Message),
            incoming);
        for (var index = 0; index < reconciled.Length; index++)
        {
            var message = reconciled[index];
            if (index >= _fleetChatMessages.Count)
            {
                _fleetChatMessages.Add(new FleetChatMessageRow(message, _accountId, this));
                continue;
            }

            var existing = _fleetChatMessages[index].Message;
            if (existing.MessageId.Equals(message.MessageId, StringComparison.OrdinalIgnoreCase))
            {
                if (existing != message)
                {
                    _fleetChatMessages[index] = new FleetChatMessageRow(message, _accountId, this);
                }

                continue;
            }

            _fleetChatMessages.Insert(index, new FleetChatMessageRow(message, _accountId, this));
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

            ReconcileFleetChatMessages(channelId, [mutation.Message]);

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
        if (MessageComposerKeyboardPolicy.Resolve(e.Key, Keyboard.Modifiers) !=
            MessageComposerKeyAction.Send)
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
            ? "加入组织后可以使用通讯。"
            : "完成登录与身份验证后可以使用通讯。";
        FleetChatStatusText.Foreground = StatusPalette.WarningBrush;
        FleetChatSyncStateText.Text = "通讯已暂停";
        FleetChatSyncStateText.Foreground = StatusPalette.WarningBrush;
    }

    private void RenderFleetChat()
    {
        FleetChatActiveChannelTitle.Text = "组织聊天";
        FleetChatMessageEmptyState.Visibility = _fleetChatMessages.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        FleetChatMessageList.Visibility = _fleetChatMessages.Count == 0
            ? Visibility.Collapsed
            : Visibility.Visible;
        ApplyFleetChatAvailability();
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

        RefreshFleetAnnouncementTimeLabels(now);
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
        FleetChatHistoryLoadingIndicator.IsActive = true;
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
            ReconcileFleetChatMessages(channelId, history.Messages);
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
            FleetChatHistoryLoadingIndicator.IsActive = true;
            FleetChatHistoryStatusText.Text = "正在加载更早消息…";
            FleetChatHistoryStatusPanel.Visibility = atTop ? Visibility.Visible : Visibility.Collapsed;
            return;
        }

        FleetChatHistoryLoadingIndicator.IsActive = false;
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
            FleetChatHistoryLoadingIndicator.IsActive = false;
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
        const OverlayFleetChatScope scope = OverlayFleetChatScope.Fleet;
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

                    _fleetOverlayChatMessages.Add(CreateFleetOverlayChatMessage(message, channel));
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
        return _fleetChatChannels
            .Where(channel => channel.Type == FleetChatChannelTypes.Fleet)
            .ToArray();
    }

    private OverlayChatMessage CreateFleetOverlayChatMessage(
        FleetChatMessageContract message,
        FleetChatChannelRow channel)
    {
        var projectionId = ResolveFleetOverlayChatProjectionId();
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
            string.IsNullOrWhiteSpace(message.SenderRoleColor)
                ? BridgeScenePalette.Resolve(BridgeSceneKind.Fleet).Accent.ToString()
                : message.SenderRoleColor,
            null);
    }

    private string ResolveFleetOverlayChatProjectionId()
    {
        return string.IsNullOrWhiteSpace(_fleetCode) || ResolveFleetOverlayChatChannels().Length == 0
            ? ""
            : $"overlay-fleet-chat:{_fleetCode.Trim().ToUpperInvariant()}:{OverlayFleetChatScope.Fleet}";
    }

    private string ResolveFleetOverlayChatTitle()
    {
        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        return zh ? "组织通讯" : "ORGANIZATION COMMS";
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

        var label = _language == "zh" ? "聊天" : "Chat";
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

    public FleetChatChannelRow(FleetChatChannelContract channel, FrameworkElement resourceScope)
    {
        Channel = channel;
        _unreadCount = channel.UnreadCount;
        AccentBrush = BridgeSceneContext.GetRequiredAccentBrush(resourceScope);
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public FleetChatChannelContract Channel { get; }
    public string ChannelId => Channel.ChannelId;
    public string Type => Channel.Type;
    public string DisplayName => Channel.DisplayName;
    public bool CanSend => Channel.CanSend;
    public string IconGlyph => "\uE8BD";
    public Brush AccentBrush { get; }
    public string PreviewText => string.IsNullOrWhiteSpace(Channel.LastMessagePreview)
        ? "全组织通讯"
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

    public FleetChatMessageRow(
        FleetChatMessageContract message,
        string? localAccountId,
        FrameworkElement resourceScope)
    {
        Message = message;
        IsSelf = !string.IsNullOrWhiteSpace(localAccountId) &&
                 message.SenderAccountId.Equals(localAccountId, StringComparison.OrdinalIgnoreCase);
        SenderRoleBrush = ChatPresentationBrushes.ResolveSenderRole(
            resourceScope,
            IsSelf,
            message.SenderRoleColor);
        AttachmentStatusBrush = ChatPresentationBrushes.ResolveAttachmentStatus(
            resourceScope,
            message.Attachment);
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
    public Brush AttachmentStatusBrush { get; }
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

}
