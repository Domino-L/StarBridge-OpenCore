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
        _notificationSettings.PlayerActivityScope == PlayerActivityNotificationScope.PartyRoom;

    private void ProcessPlayerActivityDesktopNotifications()
    {
        var partyIdentityKeys = BuildCurrentPartyIdentityKeys();
        var members = new List<PlayerActivityMemberState>();
        foreach (var player in _players)
        {
            var key = BuildPlayerActivityKey(player.AccountId, player.Name, player.Callsign);
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
                player.AllowsSharedEvent(PlayerSharedEventTypes.Presence),
                HasAnyPlayerIdentity(partyIdentityKeys, player.AccountId, player.Name, player.Callsign)));
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
                    IsInPartyRoom: true));
            }
        }

        var context = new PlayerActivityNotificationContext(
            IsAppBackground: !IsActive || !IsVisible || WindowState == WindowState.Minimized,
            IsGameRunning: _isGameProcessRunning,
            IsOverlayRunning: IsOverlayRunning);
        var notifications = _playerActivityNotificationTracker.Evaluate(
            members,
            _notificationSettings,
            context,
            DateTimeOffset.UtcNow);
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
            "#42CF7C");
        _playerActivityToastManager.Show(preview, GetSelectedPlayerActivityNotificationPosition(), this);
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
