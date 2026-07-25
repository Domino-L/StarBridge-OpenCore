using System.Windows;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private PlayerRow? _userAvatarProfileTarget;
    private bool _userAvatarTargetIsSelf;
    private string _userAvatarFriendAction = "";
    private string _userAvatarMessageOrigin = StarBridge.Core.Friends.DirectMessageOrigins.Unknown;

    private void UserAvatarButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement anchor ||
            UserAvatarProfileTargetResolver.Resolve(anchor.DataContext) is not { } identity)
        {
            return;
        }

        _userAvatarTargetIsSelf = IsCurrentUserAvatarTarget(identity);
        _userAvatarProfileTarget = ResolveUserAvatarPlayer(identity, _userAvatarTargetIsSelf);
        _userAvatarMessageOrigin = identity.MessageOrigin;

        var canOpenProfile = _userAvatarTargetIsSelf ||
                             !string.IsNullOrWhiteSpace(_userAvatarProfileTarget.AccountId);
        UserAvatarProfileActionButton.IsEnabled = canOpenProfile;
        UserAvatarProfileActionButton.ToolTip = canOpenProfile
            ? "打开该用户的个人资料"
            : "该用户的账户身份尚未同步";
        UserAvatarActionUnavailableText.Visibility = canOpenProfile
            ? Visibility.Collapsed
            : Visibility.Visible;
        ApplyUserAvatarFriendAction(identity.AccountId, _userAvatarTargetIsSelf);
        ApplyUserAvatarMessageAction(identity.AccountId, _userAvatarTargetIsSelf);

        UserAvatarActionPopup.PlacementTarget = anchor;
        UserAvatarActionPopup.IsOpen = true;
        e.Handled = true;
    }

    private async void UserAvatarProfileActionButton_Click(object sender, RoutedEventArgs e)
    {
        UserAvatarActionPopup.IsOpen = false;

        if (_userAvatarTargetIsSelf)
        {
            PersonalNav_Click(PersonalNavButton, new RoutedEventArgs());
            return;
        }

        if (_userAvatarProfileTarget is { AccountId: not null } target)
        {
            await OpenPersonalProfileVisitorAsync(target);
        }
    }

    private async void UserAvatarFriendActionButton_Click(object sender, RoutedEventArgs e)
    {
        UserAvatarActionPopup.IsOpen = false;
        if (_userAvatarProfileTarget?.AccountId is not { Length: > 0 } accountId)
        {
            return;
        }

        if (_userAvatarFriendAction == "manage")
        {
            HeaderFriendCenterButton_Click(HeaderFriendCenterButton, new RoutedEventArgs());
            return;
        }

        await MutateFriendRelationshipAsync(accountId, _userAvatarFriendAction);
    }

    private async void UserAvatarMessageActionButton_Click(object sender, RoutedEventArgs e)
    {
        UserAvatarActionPopup.IsOpen = false;
        if (_userAvatarProfileTarget is null)
        {
            return;
        }

        await OpenDirectMessageAsync(_userAvatarProfileTarget, _userAvatarMessageOrigin);
    }

    private void ApplyUserAvatarMessageAction(string? accountId, bool isSelf)
    {
        var canMessage = !isSelf &&
                         !string.IsNullOrWhiteSpace(accountId) &&
                         ResolveFriendRelationshipState(accountId) != StarBridge.Core.Friends.FriendRelationshipStates.Blocked;
        UserAvatarMessageActionButton.Visibility = canMessage ? Visibility.Visible : Visibility.Collapsed;
        UserAvatarMessageActionButton.IsEnabled = canMessage && CanSynchronizeUserData;
        UserAvatarMessageActionButton.ToolTip = !canMessage
            ? null
            : CanSynchronizeUserData
                ? "打开与该用户的私信"
                : "完成登录和身份验证后可以发送消息";
    }

    private void ApplyUserAvatarFriendAction(string? accountId, bool isSelf)
    {
        if (isSelf || string.IsNullOrWhiteSpace(accountId))
        {
            UserAvatarFriendActionButton.Visibility = Visibility.Collapsed;
            _userAvatarFriendAction = "";
            return;
        }

        var relationship = ResolveFriendRelationshipState(accountId);
        (_userAvatarFriendAction, UserAvatarFriendActionButton.Content) = relationship switch
        {
            StarBridge.Core.Friends.FriendRelationshipStates.Friend => ("manage", "好友 · 管理关系"),
            StarBridge.Core.Friends.FriendRelationshipStates.Incoming => (StarBridge.Core.Friends.FriendActions.Accept, "接受好友申请"),
            StarBridge.Core.Friends.FriendRelationshipStates.Outgoing => (StarBridge.Core.Friends.FriendActions.Cancel, "撤回好友申请"),
            StarBridge.Core.Friends.FriendRelationshipStates.Blocked => (StarBridge.Core.Friends.FriendActions.Unblock, "解除屏蔽"),
            _ => (StarBridge.Core.Friends.FriendActions.Send, "添加好友")
        };
        UserAvatarFriendActionButton.Visibility = Visibility.Visible;
        UserAvatarFriendActionButton.IsEnabled = IsLoggedIn;
        UserAvatarFriendActionButton.ToolTip = IsLoggedIn ? null : "登录后可以使用好友功能";
    }

    private string ResolveFriendRelationshipState(string accountId)
    {
        static bool Contains(IEnumerable<StarBridge.Core.Friends.FriendEntryContract> entries, string id) =>
            entries.Any(entry => entry.User.AccountId.Equals(id, StringComparison.OrdinalIgnoreCase));

        if (_friendCenterSnapshot is not null)
        {
            if (Contains(_friendCenterSnapshot.Friends, accountId)) return StarBridge.Core.Friends.FriendRelationshipStates.Friend;
            if (Contains(_friendCenterSnapshot.IncomingRequests, accountId)) return StarBridge.Core.Friends.FriendRelationshipStates.Incoming;
            if (Contains(_friendCenterSnapshot.OutgoingRequests, accountId)) return StarBridge.Core.Friends.FriendRelationshipStates.Outgoing;
            if (Contains(_friendCenterSnapshot.BlockedUsers, accountId)) return StarBridge.Core.Friends.FriendRelationshipStates.Blocked;
        }

        return _friendSearchResults.FirstOrDefault(user =>
                   user.AccountId.Equals(accountId, StringComparison.OrdinalIgnoreCase))?.RelationshipState
               ?? StarBridge.Core.Friends.FriendRelationshipStates.None;
    }

    private bool IsCurrentUserAvatarTarget(UserAvatarProfileTarget identity)
    {
        if (identity.IsSelf)
        {
            return true;
        }

        if (!string.IsNullOrWhiteSpace(identity.AccountId) &&
            !string.IsNullOrWhiteSpace(_accountId) &&
            identity.AccountId.Equals(_accountId, StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return IsLocalPlayerIdentity(identity.GameId, identity.Callsign);
    }

    private PlayerRow ResolveUserAvatarPlayer(UserAvatarProfileTarget identity, bool isSelf)
    {
        var matched = _players.FirstOrDefault(player =>
                          !string.IsNullOrWhiteSpace(identity.AccountId) &&
                          !string.IsNullOrWhiteSpace(player.AccountId) &&
                          player.AccountId.Equals(identity.AccountId, StringComparison.OrdinalIgnoreCase))
                      ?? _players.FirstOrDefault(player =>
                          (!string.IsNullOrWhiteSpace(identity.GameId) &&
                           player.Name.Equals(identity.GameId, StringComparison.OrdinalIgnoreCase)) ||
                          (!string.IsNullOrWhiteSpace(identity.Callsign) &&
                           !string.IsNullOrWhiteSpace(player.Callsign) &&
                           player.Callsign.Equals(identity.Callsign, StringComparison.OrdinalIgnoreCase)));

        if (matched is not null)
        {
            return matched with { IsSelf = isSelf };
        }

        var gameId = string.IsNullOrWhiteSpace(identity.GameId)
            ? identity.Callsign ?? "Unknown"
            : identity.GameId;
        return new PlayerRow(
            gameId,
            identity.Status,
            "Unknown",
            "飞船：未知",
            "地点：未知星域",
            identity.Callsign,
            identity.AvatarPath,
            GetInitials(gameId),
            IsSelf: isSelf,
            ShowMemberActions: false,
            AccountId: identity.AccountId);
    }
}
