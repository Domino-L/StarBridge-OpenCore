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

        var pendingFleetApplications = _hasFleet && CanCurrentUserManageFleetInfo()
            ? CountPendingFleetApplications()
            : 0;
        SetNavigationActivityBadge(
            MyFleetActivityBadge,
            MyFleetActivityBadgeText,
            Math.Max(0, _fleetChatTotalUnread) + pendingFleetApplications);

        var pendingRoomApplications = _currentPartyRoom is { ViewerIsHost: true }
            ? _currentPartyRoom.PendingApplications.Length
            : 0;
        SetNavigationActivityBadge(
            PartyLobbyActivityBadge,
            PartyLobbyActivityBadgeText,
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
