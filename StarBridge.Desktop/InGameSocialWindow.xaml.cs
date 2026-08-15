using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace StarBridge.Desktop;

public partial class InGameSocialWindow : Window
{
    private bool _allowPermanentClose;
    private bool _applyingSnapshot;
    private InGameSocialSection _section = InGameSocialSection.DirectMessages;
    private InGameSocialSnapshot? _snapshot;

    internal event EventHandler? MenuCloseRequested;
    internal event EventHandler? ToolDeactivated;
    internal event EventHandler? ToolHidden;
    internal event EventHandler? RefreshRequested;
    internal event EventHandler<InGameSocialConversationRequestedEventArgs>? ConversationRequested;
    internal event EventHandler<InGameSocialChannelRequestedEventArgs>? ChannelRequested;
    internal event EventHandler<InGameSocialMessageRequestedEventArgs>? MessageRequested;
    internal event EventHandler<InGameSocialAttachmentRequestedEventArgs>? AttachmentRequested;
    internal event EventHandler<InGameChatAttachmentActionRequestedEventArgs>? AttachmentActionRequested;
    internal event EventHandler<InGameSocialFriendSearchRequestedEventArgs>? FriendSearchRequested;
    internal event EventHandler<InGameSocialFriendActionRequestedEventArgs>? FriendActionRequested;

    internal string? ActiveConversationAccountId =>
        _section == InGameSocialSection.DirectMessages
            ? _snapshot?.DirectMessages.ActiveUser?.AccountId
            : null;
    internal bool IsShowingConversation =>
        IsVisible &&
        _section is InGameSocialSection.DirectMessages or InGameSocialSection.Channels &&
        ActivePane?.ActiveConversation is not null;

    private InGameConversationPaneSnapshot? ActivePane => _snapshot is null
        ? null
        : _section == InGameSocialSection.Channels
            ? _snapshot.Channels
            : _snapshot.DirectMessages;

    internal InGameSocialWindow()
    {
        InitializeComponent();
        Theming.BridgeSceneContext.ApplyFixed(this, Theming.BridgeSceneKind.Social);
        InGameToolWindowBehavior.PreventSnapMaximize(this);
    }

    internal void ShowForMenu(InGameSocialSection section)
    {
        SetSection(section);
        if (WindowState == WindowState.Minimized)
        {
            WindowState = WindowState.Normal;
        }

        Show();
        Activate();
    }

    internal void ApplySnapshot(InGameSocialSnapshot snapshot)
    {
        _snapshot = snapshot;
        _applyingSnapshot = true;
        try
        {
            UnavailablePanel.Visibility = snapshot.IsAvailable
                ? Visibility.Collapsed
                : Visibility.Visible;
            SocialContentPanel.Visibility = snapshot.IsAvailable
                ? Visibility.Visible
                : Visibility.Collapsed;
            Controls.InGameLoadingPresentation.Apply(
                UnavailableLoadingIndicator,
                !snapshot.IsAvailable &&
                snapshot.FriendDirectoryState == InGameFriendDirectoryState.Loading);

            FriendList.ItemsSource = InGameSnapshotItemIdentity.PreserveEqualInstances(
                FriendList.ItemsSource as IEnumerable<FriendCenterRow>,
                snapshot.Friends);
            IncomingRequestList.ItemsSource = InGameSnapshotItemIdentity.PreserveEqualInstances(
                IncomingRequestList.ItemsSource as IEnumerable<FriendCenterRow>,
                snapshot.IncomingRequests);
            FriendSearchResultList.ItemsSource = InGameSnapshotItemIdentity.PreserveEqualInstances(
                FriendSearchResultList.ItemsSource as IEnumerable<FriendCenterRow>,
                snapshot.SearchResults);
            IncomingRequestsPanel.Visibility = snapshot.IncomingRequests.Length > 0
                ? Visibility.Visible
                : Visibility.Collapsed;
            SearchResultsPanel.Visibility = snapshot.IsSearchActive
                ? Visibility.Visible
                : Visibility.Collapsed;
            FriendCollectionPanel.Visibility = snapshot.IsSearchActive
                ? Visibility.Collapsed
                : Visibility.Visible;
            Controls.InGameLoadingPresentation.Apply(
                FriendDirectoryStatusText,
                FriendDirectoryLoadingIndicator,
                snapshot.FriendStatusText,
                snapshot.FriendDirectoryState == InGameFriendDirectoryState.Loading);
            Controls.InGameLoadingPresentation.Apply(
                FriendSearchStatusText,
                FriendSearchLoadingIndicator,
                snapshot.SearchStatusText,
                snapshot.IsSearchLoading);
            FriendsEmptyState.Visibility =
                snapshot.FriendDirectoryState == InGameFriendDirectoryState.Ready &&
                snapshot.Friends.Length == 0
                ? Visibility.Visible
                : Visibility.Collapsed;
            ApplyCommunicationPane(snapshot);
        }
        finally
        {
            _applyingSnapshot = false;
        }

        if (ActivePane is { Messages.Length: > 0 } pane)
        {
            MessageList.Dispatcher.BeginInvoke(
                System.Windows.Threading.DispatcherPriority.Loaded,
                new Action(() => MessageList.ScrollIntoView(pane.Messages[^1])));
        }
    }

    private void ApplyCommunicationPane(InGameSocialSnapshot snapshot)
    {
        var isChannels = _section == InGameSocialSection.Channels;
        var pane = isChannels ? snapshot.Channels : snapshot.DirectMessages;
        var conversations = InGameSnapshotItemIdentity.PreserveEqualInstances(
            ConversationList.ItemsSource as IEnumerable<InGameChatChannelRow>,
            pane.Conversations);
        ConversationList.ItemsSource = conversations;
        MessageList.ItemsSource = pane.Messages;
        ConversationEmptyState.Visibility = pane.Conversations.Length == 0
            ? Visibility.Visible
            : Visibility.Collapsed;

        CommunicationDirectoryTitleText.Text = isChannels ? "频道" : "私聊";
        CommunicationDirectoryDetailText.Text = isChannels
            ? "查看组织和房间中的消息"
            : "只显示你和好友的一对一消息";
        ConversationEmptyState.TitleOverride = isChannels ? "还没有可用频道" : "还没有私聊会话";
        ConversationEmptyState.DescriptionOverride = isChannels
            ? "加入组织或房间后，频道会显示在这里。"
            : "从好友列表选择一位好友，即可开始私聊。";
        ChatNoSelectionTitleText.Text = isChannels ? "选择一个频道" : "选择一位好友";
        ChatNoSelectionDetailText.Text = isChannels
            ? "选择组织或房间频道查看消息。"
            : "从左侧选择一位好友开始私聊。";

        var activeKey = pane.ActiveConversation?.Key;
        ConversationList.SelectedItem = conversations.FirstOrDefault(row =>
            row.Key.Equals(activeKey, StringComparison.OrdinalIgnoreCase));
        var hasActiveConversation = pane.ActiveConversation is not null;
        ChatNoSelectionState.Visibility = hasActiveConversation
            ? Visibility.Collapsed
            : Visibility.Visible;
        ChatActivePanel.Visibility = hasActiveConversation
            ? Visibility.Visible
            : Visibility.Collapsed;
        ActiveUserHeader.DataContext = pane.ActiveConversation;
        MessageEmptyState.Visibility = hasActiveConversation && pane.Messages.Length == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        ActiveUserNameText.Text = pane.ActiveConversation?.Callsign ??
                                  (isChannels ? "选择一个频道" : "选择一位好友");
        ActiveUserDetailText.Text = pane.ActiveConversation?.ContextText ??
                                    (isChannels
                                        ? "从左侧选择组织或房间频道"
                                        : "从左侧选择一位好友");
        if (pane.ActiveConversation is { Kind: InGameChatChannelKind.Private } &&
            pane.ActiveUser is { } activeUser)
        {
            var presence = PlayerPresencePresentation.ResolveShared(
                activeUser.Presence,
                activeUser.Presence);
            ActiveUserPresenceText.Text = PlayerPresencePresentation.Format(presence);
            ActiveUserPresenceText.Foreground = PlayerPresencePresentation.Brush(presence);
            ActiveUserRelationText.Text = activeUser.RelationshipState switch
            {
                StarBridge.Core.Friends.FriendRelationshipStates.Friend => "好友",
                StarBridge.Core.Friends.FriendRelationshipStates.Incoming => "待处理好友申请",
                StarBridge.Core.Friends.FriendRelationshipStates.Outgoing => "等待对方接受",
                _ => "私聊"
            };
        }
        else if (pane.ActiveConversation is { } activeConversation)
        {
            ActiveUserPresenceText.Text = string.Empty;
            ActiveUserRelationText.Text = activeConversation.Kind switch
            {
                InGameChatChannelKind.Fleet => "组织频道",
                InGameChatChannelKind.Room => "房间频道",
                _ => string.Empty
            };
        }
        else
        {
            ActiveUserPresenceText.Text = string.Empty;
            ActiveUserRelationText.Text = string.Empty;
        }

        MessageInputBox.IsEnabled = pane.CanSend;
        SendButton.IsEnabled = pane.CanSend;
        ChatAttachmentButton.IsEnabled = pane.CanSend;
        StatusText.Text = string.IsNullOrWhiteSpace(pane.StatusText)
            ? pane.CanSend ? "可以发送消息" : "选择好友或频道后即可发送消息"
            : pane.StatusText;
    }

    internal void ResetAccountState(string statusText, bool isLoading = false)
    {
        FriendSearchBox.Clear();
        MessageInputBox.Clear();
        ApplySnapshot(new InGameSocialSnapshot(
            false,
            [],
            [],
            [],
            new InGameConversationPaneSnapshot([], [], null, null, false, statusText),
            new InGameConversationPaneSnapshot([], [], null, null, false, statusText),
            isLoading
                ? InGameFriendDirectoryState.Loading
                : InGameFriendDirectoryState.Unavailable,
            statusText,
            "输入呼号或游戏 ID 查找用户",
            false,
            false,
            "",
            "",
            null,
            "?",
            StarBridge.Core.Presence.PlayerPresenceVisibilityMode.Online,
            statusText,
            StatusPalette.DisabledBrush));
        SocialUnavailableDetailText.Text = statusText;
    }

    internal void HideForMenu()
    {
        if (IsVisible)
        {
            Hide();
        }
    }

    internal void CloseForApplication()
    {
        _allowPermanentClose = true;
        Close();
    }

    private void SetSection(InGameSocialSection section)
    {
        _section = section;
        FriendsPanel.Visibility = section == InGameSocialSection.Friends
            ? Visibility.Visible
            : Visibility.Collapsed;
        ChatPanel.Visibility = section is
            InGameSocialSection.DirectMessages or InGameSocialSection.Channels
            ? Visibility.Visible
            : Visibility.Collapsed;
        DirectMessagesSectionButton.Style = (Style)FindResource(
            section == InGameSocialSection.DirectMessages
                ? "PrimaryButton"
                : "SecondaryButton");
        ChannelsSectionButton.Style = (Style)FindResource(
            section == InGameSocialSection.Channels
                ? "PrimaryButton"
                : "SecondaryButton");
        HeaderDetailText.Text = section switch
        {
            InGameSocialSection.Friends => "添加好友、处理申请并直接开始私聊",
            InGameSocialSection.DirectMessages => "只显示你和好友的一对一消息",
            _ => "查看组织和房间中的消息"
        };
        if (_snapshot is not null)
        {
            _applyingSnapshot = true;
            try
            {
                ApplyCommunicationPane(_snapshot);
            }
            finally
            {
                _applyingSnapshot = false;
            }
        }
    }

    private void DirectMessagesSectionButton_Click(object sender, RoutedEventArgs e) =>
        SetSection(InGameSocialSection.DirectMessages);

    private void ChannelsSectionButton_Click(object sender, RoutedEventArgs e) =>
        SetSection(InGameSocialSection.Channels);

    private void RefreshButton_Click(object sender, RoutedEventArgs e) =>
        RefreshRequested?.Invoke(this, EventArgs.Empty);

    private void FriendSearchButton_Click(object sender, RoutedEventArgs e)
    {
        FriendSearchRequested?.Invoke(
            this,
            new InGameSocialFriendSearchRequestedEventArgs(
                FriendSearchBox.Text));
    }

    private void FriendSearchBox_KeyDown(
        object sender,
        System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key != Key.Enter)
        {
            return;
        }

        e.Handled = true;
        FriendSearchButton_Click(sender, new RoutedEventArgs());
    }

    private void FriendActionButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.Button
            {
                DataContext: FriendCenterRow row,
                Tag: string action
            } ||
            string.IsNullOrWhiteSpace(action))
        {
            return;
        }

        FriendActionRequested?.Invoke(
            this,
            new InGameSocialFriendActionRequestedEventArgs(row, action));
    }

    private void FriendList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_applyingSnapshot || FriendList.SelectedItem is not FriendCenterRow row)
        {
            return;
        }

        if (!row.User.RelationshipState.Equals(
                StarBridge.Core.Friends.FriendRelationshipStates.Friend,
                StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        SetSection(InGameSocialSection.DirectMessages);
        ConversationRequested?.Invoke(
            this,
            new InGameSocialConversationRequestedEventArgs(row.User));
    }

    private void ConversationList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_applyingSnapshot ||
            ConversationList.SelectedItem is not InGameChatChannelRow row)
        {
            return;
        }

        ChannelRequested?.Invoke(
            this,
            new InGameSocialChannelRequestedEventArgs(row));
    }

    private void SendButton_Click(object sender, RoutedEventArgs e)
    {
        var text = MessageInputBox.Text.Trim();
        if (text.Length == 0)
        {
            StatusText.Text = "请输入消息。";
            return;
        }

        var channel = ActivePane?.ActiveConversation;
        if (channel is null)
        {
            StatusText.Text = "这个聊天已不可用，请重新选择。";
            return;
        }

        MessageInputBox.Clear();
        MessageRequested?.Invoke(
            this,
            new InGameSocialMessageRequestedEventArgs(
                text,
                channel.Kind,
                channel.Key));
    }

    private void ChatAttachmentButton_Click(object sender, RoutedEventArgs e)
    {
        var channel = ActivePane?.ActiveConversation;
        if (channel is null || sender is not System.Windows.Controls.Button anchor)
        {
            StatusText.Text = "请先选择一个聊天。";
            return;
        }

        AttachmentRequested?.Invoke(
            this,
            new InGameSocialAttachmentRequestedEventArgs(
                anchor,
                channel.Kind,
                channel.Key));
    }

    private void ChatAttachmentActionButton_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is StarBridge.Core.Chat.ChatAttachmentContract attachment)
        {
            AttachmentActionRequested?.Invoke(
                this,
                new InGameChatAttachmentActionRequestedEventArgs(attachment));
        }
    }

    private void MessageInputBox_KeyDown(
        object sender,
        System.Windows.Input.KeyEventArgs e)
    {
        if (MessageComposerKeyboardPolicy.Resolve(e.Key, Keyboard.Modifiers) !=
            MessageComposerKeyAction.Send)
        {
            return;
        }

        e.Handled = true;
        SendButton_Click(SendButton, new RoutedEventArgs());
    }

    private void Window_PreviewKeyDown(
        object sender,
        System.Windows.Input.KeyEventArgs e)
    {
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key != Key.Escape)
        {
            return;
        }

        e.Handled = true;
        MenuCloseRequested?.Invoke(this, EventArgs.Empty);
    }

    private void Window_Deactivated(object? sender, EventArgs e) =>
        ToolDeactivated?.Invoke(this, EventArgs.Empty);

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!_allowPermanentClose)
        {
            e.Cancel = true;
            HideForMenu();
            ToolHidden?.Invoke(this, EventArgs.Empty);
            return;
        }

        base.OnClosing(e);
    }

    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) =>
        Close();
}
