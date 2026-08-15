using StarBridge.Core.Presence;
using System.Windows;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private readonly PlayerActivityNotificationTracker _playerActivityNotificationTracker = new();
    private readonly PlayerActivityToastManager _playerActivityToastManager = new();

    private void InitializePlayerActivityDesktopNotifications()
    {
        _playerActivityToastManager.ProfileRequested += PlayerActivityToastManager_ProfileRequested;
    }

    private void DisposePlayerActivityDesktopNotifications()
    {
        _playerActivityToastManager.ProfileRequested -= PlayerActivityToastManager_ProfileRequested;
        _playerActivityToastManager.Dispose();
    }

    private bool ShouldRefreshPartyRoomForDesktopNotifications() =>
        _notificationSettings.EnablePlayerActivityNotifications &&
        _notificationSettings.PlayerActivityScope.HasFlag(PlayerActivityNotificationScope.PartyRoom);

    private void ProcessPlayerActivityDesktopNotifications()
    {
        var partyIdentityKeys = BuildCurrentPartyIdentityKeys();
        var acceptedFriends = (_friendCenterSnapshot?.Friends ?? [])
            .Select(entry => FriendCenterUserResolver.Resolve(entry.User, _networkSnapshots.Values))
            .ToArray();
        var friendIdentityKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var friend in acceptedFriends)
        {
            friendIdentityKeys.UnionWith(BuildIdentityKeys(friend.AccountId, friend.GameId, friend.Callsign));
        }

        var members = new List<PlayerActivityMemberState>();
        foreach (var player in _players)
        {
            var key = BuildPlayerActivityKey(player.AccountId, player.Name, player.Callsign);
            var isAcceptedFriend = HasAnyPlayerIdentity(
                friendIdentityKeys,
                player.AccountId,
                player.Name,
                player.Callsign);
            members.Add(new PlayerActivityMemberState(
                key,
                player.Name,
                player.Callsign ?? "",
                DisplayCallsign(player.Callsign, player.Name),
                player.Initials,
                player.AvatarPath,
                player.AccountId,
                player.SharedPresence,
                player.IsSelf,
                player.AllowsSharedEvent(PlayerSharedEventTypes.Presence) || isAcceptedFriend,
                IsFleetMember: true,
                IsAcceptedFriend: isAcceptedFriend,
                IsInPartyRoom: HasAnyPlayerIdentity(partyIdentityKeys, player.AccountId, player.Name, player.Callsign)));
        }

        if (_currentPartyRoom is not null)
        {
            foreach (var partyMember in _currentPartyRoom.Members)
            {
                var key = BuildPlayerActivityKey(partyMember.AccountId, partyMember.GameId, partyMember.Callsign);
                if (members.Any(member => member.Key.Equals(key, StringComparison.OrdinalIgnoreCase)))
                {
                    continue;
                }

                var isSelf = HasAnyPlayerIdentity(
                    BuildIdentityKeys(_accountId, _localPlayer, _callsign),
                    partyMember.AccountId,
                    partyMember.GameId,
                    partyMember.Callsign);
                members.Add(new PlayerActivityMemberState(
                    key,
                    partyMember.GameId,
                    partyMember.Callsign,
                    DisplayCallsign(partyMember.Callsign, partyMember.GameId),
                    GetInitials(DisplayCallsign(partyMember.Callsign, partyMember.GameId)),
                    partyMember.AvatarImageData,
                    partyMember.AccountId,
                    PlayerPresencePresentation.ResolveShared(partyMember.PresenceText, partyMember.PresenceText),
                    isSelf,
                    AllowsPresenceEvents: true,
                    IsFleetMember: false,
                    IsAcceptedFriend: HasAnyPlayerIdentity(
                        friendIdentityKeys,
                        partyMember.AccountId,
                        partyMember.GameId,
                        partyMember.Callsign),
                    IsInPartyRoom: true));
            }
        }

        foreach (var friend in acceptedFriends)
        {
            var friendIdentity = BuildIdentityKeys(friend.AccountId, friend.GameId, friend.Callsign);
            if (members.Any(member => HasAnyPlayerIdentity(
                    friendIdentity,
                    member.AccountId,
                    member.GameId,
                    member.Callsign)))
            {
                continue;
            }

            var displayName = DisplayCallsign(friend.Callsign, friend.GameId);
            members.Add(new PlayerActivityMemberState(
                BuildPlayerActivityKey(friend.AccountId, friend.GameId, friend.Callsign),
                friend.GameId,
                friend.Callsign,
                displayName,
                GetInitials(displayName),
                friend.AvatarImageData,
                friend.AccountId,
                PlayerPresencePresentation.ResolveShared(friend.Presence, friend.Presence),
                HasAnyPlayerIdentity(
                    BuildIdentityKeys(_accountId, _localPlayer, _callsign),
                    friend.AccountId,
                    friend.GameId,
                    friend.Callsign),
                AllowsPresenceEvents: true,
                IsFleetMember: false,
                IsAcceptedFriend: true,
                IsInPartyRoom: HasAnyPlayerIdentity(
                    partyIdentityKeys,
                    friend.AccountId,
                    friend.GameId,
                    friend.Callsign)));
        }

        var context = new PlayerActivityNotificationContext(
            IsAppBackground: !IsActive || !IsVisible || WindowState == WindowState.Minimized,
            IsGameRunning: _isGameProcessRunning,
            IsOverlayRunning: IsOverlayRunning);
        var notifications = _playerActivityNotificationTracker.Evaluate(
            members,
            _notificationSettings,
            context,
            DateTimeOffset.UtcNow,
            establishBaselineOnly: _startupDataGate.Current.State != StartupDataGateState.Live);
        foreach (var notification in notifications)
        {
            _playerActivityToastManager.Show(notification, _notificationSettings.PlayerActivityPosition, this);
        }
    }

    private async void PlayerActivityToastManager_ProfileRequested(
        object? sender,
        PlayerActivityDesktopNotification notification)
    {
        (System.Windows.Application.Current as App)?.ShowMainWindowFromBackground();
        var target = _players.FirstOrDefault(player =>
                         !string.IsNullOrWhiteSpace(notification.AccountId) &&
                         !string.IsNullOrWhiteSpace(player.AccountId) &&
                         player.AccountId.Equals(notification.AccountId, StringComparison.OrdinalIgnoreCase))
                     ?? _players.FirstOrDefault(player =>
                         player.Name.Equals(notification.GameId, StringComparison.OrdinalIgnoreCase) ||
                         !string.IsNullOrWhiteSpace(notification.Callsign) &&
                         !string.IsNullOrWhiteSpace(player.Callsign) &&
                         player.Callsign.Equals(notification.Callsign, StringComparison.OrdinalIgnoreCase));
        if (target is not null && !target.IsSelf && !string.IsNullOrWhiteSpace(target.AccountId))
        {
            await OpenPersonalProfileVisitorAsync(target);
            return;
        }

        var friendEntry = _friendCenterSnapshot?.Friends.FirstOrDefault(entry =>
            (!string.IsNullOrWhiteSpace(notification.AccountId) &&
             entry.User.AccountId.Equals(notification.AccountId, StringComparison.OrdinalIgnoreCase)) ||
            (!string.IsNullOrWhiteSpace(notification.GameId) &&
             entry.User.GameId.Equals(notification.GameId, StringComparison.OrdinalIgnoreCase)) ||
            (!string.IsNullOrWhiteSpace(notification.Callsign) &&
             entry.User.Callsign.Equals(notification.Callsign, StringComparison.OrdinalIgnoreCase)));
        if (friendEntry is not null)
        {
            var friend = FriendCenterUserResolver.Resolve(friendEntry.User, _networkSnapshots.Values);
            await OpenFriendProfileAsync(new FriendCenterRow(friend, friendEntry.RelationshipUpdatedAt));
        }
    }

    private void PlayerActivityNotificationPreviewButton_Click(object sender, RoutedEventArgs e)
    {
        var displayName = DisplayCallsign(_callsign, _localPlayer, "星海舰桥用户");
        var preview = new PlayerActivityDesktopNotification(
            PlayerActivityNotificationKind.StartedGame,
            "preview",
            _localPlayer ?? "",
            _callsign ?? "",
            displayName,
            GetInitials(displayName),
            _avatarPath,
            _accountId,
            "测试通知 · 开始游戏",
            DescribeSelectedPlayerActivityAudience(),
            "#42CF7C");
        _playerActivityToastManager.Show(preview, GetSelectedPlayerActivityNotificationPosition(), this);
    }

    private string DescribeSelectedPlayerActivityAudience()
    {
        var scope = GetSelectedPlayerActivityNotificationScope();
        var audiences = new List<string>(3);
        if (scope.HasFlag(PlayerActivityNotificationScope.Fleet))
        {
            audiences.Add("舰队成员");
        }

        if (scope.HasFlag(PlayerActivityNotificationScope.Friends))
        {
            audiences.Add("好友");
        }

        if (scope.HasFlag(PlayerActivityNotificationScope.PartyRoom))
        {
            audiences.Add("同房间成员");
        }

        return audiences.Count == 0 ? "未选择通知对象" : string.Join(" · ", audiences);
    }

    private HashSet<string> BuildCurrentPartyIdentityKeys()
    {
        var result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (_currentPartyRoom is null)
        {
            return result;
        }

        foreach (var member in _currentPartyRoom.Members)
        {
            result.UnionWith(BuildIdentityKeys(member.AccountId, member.GameId, member.Callsign));
        }

        return result;
    }

    private static HashSet<string> BuildIdentityKeys(string? accountId, string? gameId, string? callsign)
    {
        var result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        AddIdentityKey(result, "account", accountId);
        AddIdentityKey(result, "game", gameId);
        AddIdentityKey(result, "callsign", callsign);
        return result;
    }

    private static bool HasAnyPlayerIdentity(
        IReadOnlySet<string> identityKeys,
        string? accountId,
        string? gameId,
        string? callsign) =>
        BuildIdentityKeys(accountId, gameId, callsign).Any(identityKeys.Contains);

    private static string BuildPlayerActivityKey(string? accountId, string? gameId, string? callsign)
    {
        if (!string.IsNullOrWhiteSpace(accountId))
        {
            return $"account:{accountId.Trim()}";
        }

        if (!string.IsNullOrWhiteSpace(gameId))
        {
            return $"game:{gameId.Trim()}";
        }

        return $"callsign:{callsign?.Trim() ?? "unknown"}";
    }

    private static void AddIdentityKey(ISet<string> keys, string prefix, string? value)
    {
        if (!string.IsNullOrWhiteSpace(value))
        {
            keys.Add($"{prefix}:{value.Trim()}");
        }
    }
}
