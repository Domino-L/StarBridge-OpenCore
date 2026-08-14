using System.Globalization;
using System.Windows;
using System.Windows.Controls;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private int _partyRoomChatUnreadCount;

    private void RefreshNavigationActivityBadges()
    {
        var incomingFriendRequests = _friendCenterSnapshot?.IncomingRequests.Length ?? 0;
        var unreadDirectMessages = _friendChatConversations.Sum(
            conversation => Math.Max(0, conversation.Conversation.UnreadCount));
        SetNavigationActivityBadge(
            HeaderFriendRequestBadge,
            HeaderFriendRequestBadgeText,
            incomingFriendRequests + unreadDirectMessages);
        SetNavigationActivityBadge(
            BridgeFriendActivityBadge,
            BridgeFriendActivityBadgeText,
            incomingFriendRequests + unreadDirectMessages);

        var startupFleetDataIsLive = _startupDataGate.Current.State == StartupDataGateState.Live;
        var pendingFleetApplications = startupFleetDataIsLive && _hasFleet && CanCurrentUserManageFleetInfo()
            ? CountPendingFleetApplications()
            : 0;
        SetNavigationActivityBadge(
            MyFleetActivityBadge,
            MyFleetActivityBadgeText,
            (startupFleetDataIsLive ? Math.Max(0, _fleetChatTotalUnread) : 0) + pendingFleetApplications);
        SetNavigationActivityBadge(
            BridgeFleetActivityBadge,
            BridgeFleetActivityBadgeText,
            (startupFleetDataIsLive ? Math.Max(0, _fleetChatTotalUnread) : 0) + pendingFleetApplications);

        var pendingRoomApplications = _currentPartyRoom is { ViewerIsHost: true }
            ? _currentPartyRoom.PendingApplications.Length
            : 0;
        SetNavigationActivityBadge(
            PartyLobbyActivityBadge,
            PartyLobbyActivityBadgeText,
            _receivedPartyRoomInvitations.Length +
            pendingRoomApplications +
            Math.Max(0, _partyRoomChatUnreadCount));
        SetNavigationActivityBadge(
            BridgePartyActivityBadge,
            BridgePartyActivityBadgeText,
            _receivedPartyRoomInvitations.Length +
            pendingRoomApplications +
            Math.Max(0, _partyRoomChatUnreadCount));
    }

    private static void SetNavigationActivityBadge(Border? badge, TextBlock? text, int count)
    {
        if (badge is null || text is null)
        {
            return;
        }

        var normalizedCount = Math.Max(0, count);
        text.Text = normalizedCount > 99
            ? "99+"
            : normalizedCount.ToString(CultureInfo.InvariantCulture);
        badge.Visibility = normalizedCount > 0
            ? Visibility.Visible
            : Visibility.Collapsed;
    }
}
