using StarBridge.Core.Friends;
using StarBridge.Core.Presence;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using Button = System.Windows.Controls.Button;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using ListBox = System.Windows.Controls.ListBox;

namespace StarBridge.Desktop;

public partial class InGameFriendsWindow : Window
{
    private bool _allowPermanentClose;
    private bool _applyingSnapshot;
    private bool _openingAvatarMenu;
    private InGameMenuFriendSortMode _sortMode =
        InGameMenuFriendSortMode.OnlineFirst;
    private FriendCenterRow? _avatarActionFriend;
    private InGameSocialSnapshot? _snapshot;

    internal event EventHandler? MenuCloseRequested;
    internal event EventHandler? ToolDeactivated;
    internal event EventHandler? ToolHidden;
    internal event EventHandler? RefreshRequested;
    internal event EventHandler<InGameSocialConversationRequestedEventArgs>? ConversationRequested;
    internal event EventHandler<InGameProfileRequestedEventArgs>? ProfileRequested;
    internal event EventHandler<InGameSocialFriendSearchRequestedEventArgs>? FriendSearchRequested;
    internal event EventHandler<InGameSocialFriendActionRequestedEventArgs>? FriendActionRequested;
    internal event EventHandler<InGameFriendPresenceChangedEventArgs>? PresenceChanged;

    internal InGameFriendsWindow()
    {
        InitializeComponent();
        Theming.BridgeSceneContext.ApplyFixed(this, Theming.BridgeSceneKind.Social);
        InGameToolWindowBehavior.PreventSnapMaximize(this);
        LocalPresenceBox.ItemsSource = PlayerPresenceVisibilityCatalog.Options;
    }

    internal void ShowForMenu()
    {
        if (WindowState == WindowState.Minimized)
        {
            WindowState = WindowState.Normal;
        }

        Show();
        Activate();
    }

    internal void ApplySettings(InGameMenuSettings settings)
    {
        _sortMode = settings.Normalize().FriendSortMode;
        if (_snapshot is not null)
        {
            ApplyFriendGroups(_snapshot.Friends);
        }
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
            FriendContentPanel.Visibility = snapshot.IsAvailable
                ? Visibility.Visible
                : Visibility.Collapsed;
            UnavailableDetailText.Text = snapshot.FriendStatusText;
            Controls.InGameLoadingPresentation.Apply(
                UnavailableLoadingIndicator,
                !snapshot.IsAvailable &&
                snapshot.FriendDirectoryState == InGameFriendDirectoryState.Loading);

            LocalCallsignText.Text = string.IsNullOrWhiteSpace(snapshot.LocalCallsign)
                ? "我的账号"
                : snapshot.LocalCallsign;
            LocalGameIdText.Text = string.IsNullOrWhiteSpace(snapshot.LocalGameId)
                ? snapshot.LocalPresenceText
                : $"{snapshot.LocalGameId} · {snapshot.LocalPresenceText}";
            LocalGameIdText.Foreground = snapshot.LocalPresenceBrush;
            LocalAvatarFallbackText.Text = snapshot.LocalAvatarFallbackText;
            LocalAvatarImage.Source = string.IsNullOrWhiteSpace(snapshot.LocalAvatarSource)
                ? null
                : ImageDecodeCache.Load(snapshot.LocalAvatarSource, 100);
            LocalPresenceBox.SelectedItem =
                PlayerPresenceVisibilityCatalog.Find(snapshot.LocalVisibilityMode);

            ApplyFriendGroups(snapshot.Friends);

            IncomingRequestList.ItemsSource = InGameSnapshotItemIdentity.PreserveEqualInstances(
                IncomingRequestList.ItemsSource as IEnumerable<FriendCenterRow>,
                snapshot.IncomingRequests);
            IncomingRequestsPanel.Visibility = snapshot.IncomingRequests.Length > 0
                ? Visibility.Visible
                : Visibility.Collapsed;
            FriendSearchResultList.ItemsSource = InGameSnapshotItemIdentity.PreserveEqualInstances(
                FriendSearchResultList.ItemsSource as IEnumerable<FriendCenterRow>,
                snapshot.SearchResults);
            SearchResultsPanel.Visibility = snapshot.IsSearchActive
                ? Visibility.Visible
                : Visibility.Collapsed;
            Controls.InGameLoadingPresentation.Apply(
                FriendSearchStatusText,
                FriendSearchLoadingIndicator,
                snapshot.SearchStatusText,
                snapshot.IsSearchLoading);
            Controls.InGameLoadingPresentation.Apply(
                FriendDirectoryStatusText,
                FriendDirectoryLoadingIndicator,
                snapshot.FriendStatusText,
                snapshot.FriendDirectoryState == InGameFriendDirectoryState.Loading);
        }
        finally
        {
            _applyingSnapshot = false;
        }
    }

    internal void ResetAccountState(string statusText, bool isLoading = false)
    {
        FriendSearchBox.Clear();
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
            PlayerPresenceVisibilityMode.Online,
            statusText,
            StatusPalette.DisabledBrush));
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

    private static int PresenceRank(PlayerPresenceKind presence) =>
        presence switch
        {
            PlayerPresenceKind.InGame => 0,
            PlayerPresenceKind.AppOnline => 1,
            PlayerPresenceKind.Away => 2,
            _ => 3
        };

    private void ApplyFriendGroups(IEnumerable<FriendCenterRow> friends)
    {
        var onlineSource = friends
            .Where(row => PlayerPresence.IsOnline(row.Presence));
        var online = (_sortMode == InGameMenuFriendSortMode.Alphabetical
                ? onlineSource.OrderBy(
                    row => row.Callsign,
                    StringComparer.CurrentCultureIgnoreCase)
                : onlineSource
                    .OrderBy(row => PresenceRank(row.Presence))
                    .ThenBy(
                        row => row.Callsign,
                        StringComparer.CurrentCultureIgnoreCase))
            .ToArray();
        var offline = friends
            .Where(row => !PlayerPresence.IsOnline(row.Presence))
            .OrderBy(row => row.Callsign, StringComparer.CurrentCultureIgnoreCase)
            .ToArray();
        OnlineFriendsList.ItemsSource = InGameSnapshotItemIdentity.PreserveEqualInstances(
            OnlineFriendsList.ItemsSource as IEnumerable<FriendCenterRow>,
            online);
        OfflineFriendsList.ItemsSource = InGameSnapshotItemIdentity.PreserveEqualInstances(
            OfflineFriendsList.ItemsSource as IEnumerable<FriendCenterRow>,
            offline);
        OnlineFriendCountText.Text = online.Length.ToString();
        OfflineFriendCountText.Text = offline.Length.ToString();
    }

    private void LocalPresenceBox_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e)
    {
        if (_applyingSnapshot ||
            LocalPresenceBox.SelectedItem is not PlayerPresenceVisibilityOption option)
        {
            return;
        }

        PresenceChanged?.Invoke(
            this,
            new InGameFriendPresenceChangedEventArgs(option.Mode));
    }

    private void FriendList_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e)
    {
        if (_applyingSnapshot ||
            _openingAvatarMenu ||
            sender is not ListBox { SelectedItem: FriendCenterRow row } list)
        {
            return;
        }

        list.SelectedItem = null;
        if (row.User.RelationshipState.Equals(
                FriendRelationshipStates.Friend,
                StringComparison.OrdinalIgnoreCase))
        {
            ConversationRequested?.Invoke(
                this,
                new InGameSocialConversationRequestedEventArgs(row.User));
        }
    }

    private void SearchResultList_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e)
    {
        if (_applyingSnapshot ||
            _openingAvatarMenu ||
            FriendSearchResultList.SelectedItem is not FriendCenterRow row)
        {
            return;
        }

        FriendSearchResultList.SelectedItem = null;
        if (row.User.RelationshipState.Equals(
                FriendRelationshipStates.Friend,
                StringComparison.OrdinalIgnoreCase))
        {
            ConversationRequested?.Invoke(
                this,
                new InGameSocialConversationRequestedEventArgs(row.User));
        }
    }

    private void FriendActionButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button
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

    private void FriendSearchButton_Click(object sender, RoutedEventArgs e) =>
        FriendSearchRequested?.Invoke(
            this,
            new InGameSocialFriendSearchRequestedEventArgs(FriendSearchBox.Text));

    private void FriendSearchBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter)
        {
            return;
        }

        e.Handled = true;
        FriendSearchButton_Click(sender, new RoutedEventArgs());
    }

    private void RefreshButton_Click(object sender, RoutedEventArgs e) =>
        RefreshRequested?.Invoke(this, EventArgs.Empty);

    private void AvatarButton_PreviewMouseLeftButtonDown(
        object sender,
        MouseButtonEventArgs e)
    {
        _openingAvatarMenu = true;
        Dispatcher.BeginInvoke(
            () => _openingAvatarMenu = false,
            DispatcherPriority.Input);
    }

    private void LocalAvatarButton_Click(object sender, RoutedEventArgs e)
    {
        _avatarActionFriend = null;
        AvatarMessageButton.Visibility = Visibility.Collapsed;
        AvatarActionPopup.PlacementTarget = LocalAvatarButton;
        AvatarActionPopup.IsOpen = true;
    }

    private void FriendAvatarButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button
            {
                DataContext: FriendCenterRow row
            } button)
        {
            return;
        }

        _avatarActionFriend = row;
        AvatarMessageButton.Visibility = row.User.RelationshipState.Equals(
            FriendRelationshipStates.Friend,
            StringComparison.OrdinalIgnoreCase)
            ? Visibility.Visible
            : Visibility.Collapsed;
        AvatarActionPopup.PlacementTarget = button;
        AvatarActionPopup.IsOpen = true;
    }

    private void AvatarMessageButton_Click(object sender, RoutedEventArgs e)
    {
        AvatarActionPopup.IsOpen = false;
        if (_avatarActionFriend?.User is { } user)
        {
            ConversationRequested?.Invoke(
                this,
                new InGameSocialConversationRequestedEventArgs(user));
        }
    }

    private void AvatarProfileButton_Click(object sender, RoutedEventArgs e)
    {
        AvatarActionPopup.IsOpen = false;
        if (_avatarActionFriend is { } row)
        {
            ProfileRequested?.Invoke(
                this,
                new InGameProfileRequestedEventArgs(new InGameProfileTarget(
                    row.AccountId,
                    false,
                    string.IsNullOrWhiteSpace(row.Callsign) ? row.GameId : row.Callsign,
                    row.GameId,
                    row.AvatarSource,
                    row.Initials,
                    row.PresenceText,
                    row.PresenceBrush,
                    row.User)));
            return;
        }

        if (_snapshot is not { } snapshot)
        {
            return;
        }

        ProfileRequested?.Invoke(
            this,
            new InGameProfileRequestedEventArgs(new InGameProfileTarget(
                "self",
                true,
                snapshot.LocalCallsign,
                snapshot.LocalGameId,
                snapshot.LocalAvatarSource,
                snapshot.LocalAvatarFallbackText,
                snapshot.LocalPresenceText,
                snapshot.LocalPresenceBrush)));
    }

    private void Header_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) =>
        HideForUser();

    private void Window_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Escape)
        {
            return;
        }

        e.Handled = true;
        MenuCloseRequested?.Invoke(this, EventArgs.Empty);
    }

    private void Window_Deactivated(object? sender, EventArgs e) =>
        ToolDeactivated?.Invoke(this, EventArgs.Empty);

    private void HideForUser()
    {
        HideForMenu();
        ToolHidden?.Invoke(this, EventArgs.Empty);
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!_allowPermanentClose)
        {
            e.Cancel = true;
            HideForUser();
        }

        base.OnClosing(e);
    }
}
