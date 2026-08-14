using StarBridge.Core.Presence;

namespace StarBridge.Desktop;

internal enum PlayerActivityNotificationKind
{
    Online,
    Offline,
    StartedGame,
    StoppedGame
}

internal sealed record PlayerActivityMemberState(
    string Key,
    string GameId,
    string Callsign,
    string DisplayName,
    string Initials,
    string? AvatarSource,
    string? AccountId,
    PlayerPresenceKind Presence,
    bool IsSelf,
    bool AllowsPresenceEvents,
    bool IsInPartyRoom);

internal sealed record PlayerActivityNotificationContext(
    bool IsAppBackground,
    bool IsGameRunning,
    bool IsOverlayRunning);

internal sealed record PlayerActivityDesktopNotification(
    PlayerActivityNotificationKind Kind,
    string MemberKey,
    string GameId,
    string Callsign,
    string DisplayName,
    string Initials,
    string? AvatarSource,
    string? AccountId,
    string EventText,
    string AccentColor);

internal sealed class PlayerActivityNotificationTracker
{
    private readonly Dictionary<string, PlayerPresenceKind> _previous = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, DateTimeOffset> _lastNotificationAt = new(StringComparer.OrdinalIgnoreCase);

    public IReadOnlyList<PlayerActivityDesktopNotification> Evaluate(
        IReadOnlyCollection<PlayerActivityMemberState> members,
        NotificationSettings settings,
        PlayerActivityNotificationContext context,
        DateTimeOffset now)
    {
        var normalized = settings.Normalize();
        var currentKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var results = new List<PlayerActivityDesktopNotification>();

        foreach (var member in members)
        {
            if (string.IsNullOrWhiteSpace(member.Key) || !currentKeys.Add(member.Key))
            {
                continue;
            }

            var current = NormalizePresence(member.Presence);
            if (!_previous.TryGetValue(member.Key, out var previous))
            {
                _previous[member.Key] = current;
                continue;
            }

            previous = NormalizePresence(previous);
            _previous[member.Key] = current;
            if (previous == current || !TryResolveKind(previous, current, normalized, out var kind))
            {
                continue;
            }

            if (!CanNotify(member, normalized, context))
            {
                continue;
            }

            var cooldownKey = $"{member.Key}:{kind}";
            var cooldown = TimeSpan.FromSeconds(Math.Max(0, normalized.NotificationCooldownSeconds));
            if (_lastNotificationAt.TryGetValue(cooldownKey, out var lastAt) && now - lastAt < cooldown)
            {
                continue;
            }

            _lastNotificationAt[cooldownKey] = now;
            results.Add(CreateNotification(member, kind));
        }

        foreach (var missingKey in _previous.Keys.Where(key => !currentKeys.Contains(key)).ToArray())
        {
            _previous.Remove(missingKey);
        }

        return results;
    }

    private static bool CanNotify(
        PlayerActivityMemberState member,
        NotificationSettings settings,
        PlayerActivityNotificationContext context)
    {
        if (!settings.EnablePlayerActivityNotifications ||
            member.IsSelf ||
            !member.AllowsPresenceEvents ||
            settings.PlayerActivityBackgroundOnly && !context.IsAppBackground ||
            settings.ReducePlayerActivityNotificationsInGame && context.IsGameRunning && context.IsOverlayRunning)
        {
            return false;
        }

        return settings.PlayerActivityScope switch
        {
            PlayerActivityNotificationScope.PartyRoom => member.IsInPartyRoom,
            _ => true
        };
    }

    private static bool TryResolveKind(
        PlayerPresenceKind previous,
        PlayerPresenceKind current,
        NotificationSettings settings,
        out PlayerActivityNotificationKind kind)
    {
        var wasOnline = PlayerPresence.IsOnline(previous);
        var isOnline = PlayerPresence.IsOnline(current);

        if (current == PlayerPresenceKind.InGame && previous != PlayerPresenceKind.InGame)
        {
            if (settings.NotifyPlayerStartedGame)
            {
                kind = PlayerActivityNotificationKind.StartedGame;
                return true;
            }

            if (!wasOnline && settings.NotifyPlayerOnline)
            {
                kind = PlayerActivityNotificationKind.Online;
                return true;
            }
        }
        else if (previous == PlayerPresenceKind.InGame && current != PlayerPresenceKind.InGame && isOnline &&
                 settings.NotifyPlayerStoppedGame)
        {
            kind = PlayerActivityNotificationKind.StoppedGame;
            return true;
        }
        else if (!wasOnline && isOnline && settings.NotifyPlayerOnline)
        {
            kind = PlayerActivityNotificationKind.Online;
            return true;
        }
        else if (wasOnline && !isOnline && settings.NotifyPlayerOffline)
        {
            kind = PlayerActivityNotificationKind.Offline;
            return true;
        }

        kind = default;
        return false;
    }

    private static PlayerActivityDesktopNotification CreateNotification(
        PlayerActivityMemberState member,
        PlayerActivityNotificationKind kind)
    {
        var (eventText, accent) = kind switch
        {
            PlayerActivityNotificationKind.Online => ("已上线", "#29AFFF"),
            PlayerActivityNotificationKind.Offline => ("已离线", "#5E7283"),
            PlayerActivityNotificationKind.StartedGame => ("开始游戏", "#42CF7C"),
            PlayerActivityNotificationKind.StoppedGame => ("结束游戏", "#91A5B5"),
            _ => ("状态已更新", "#29AFFF")
        };

        return new PlayerActivityDesktopNotification(
            kind,
            member.Key,
            member.GameId,
            member.Callsign,
            member.DisplayName,
            member.Initials,
            member.AvatarSource,
            member.AccountId,
            eventText,
            accent);
    }

    private static PlayerPresenceKind NormalizePresence(PlayerPresenceKind presence) =>
        presence == PlayerPresenceKind.Paused ? PlayerPresenceKind.Offline : presence;
}

internal readonly record struct DesktopToastWorkArea(int Left, int Top, int Width, int Height)
{
    public int Right => Left + Width;
    public int Bottom => Top + Height;
}

internal readonly record struct DesktopToastPoint(int X, int Y);

internal static class DesktopToastPlacement
{
    public static DesktopToastPoint Resolve(
        DesktopToastWorkArea workArea,
        int toastWidth,
        int toastHeight,
        DesktopNotificationPosition position,
        int stackIndex,
        int gap = 8,
        int inset = 12)
    {
        var index = Math.Max(0, stackIndex);
        var left = position is DesktopNotificationPosition.TopLeft or DesktopNotificationPosition.BottomLeft;
        var top = position is DesktopNotificationPosition.TopLeft or DesktopNotificationPosition.TopRight;
        var x = left ? workArea.Left + inset : workArea.Right - inset - toastWidth;
        var y = top
            ? workArea.Top + inset + index * (toastHeight + gap)
            : workArea.Bottom - inset - toastHeight - index * (toastHeight + gap);
        return new DesktopToastPoint(x, y);
    }
}
