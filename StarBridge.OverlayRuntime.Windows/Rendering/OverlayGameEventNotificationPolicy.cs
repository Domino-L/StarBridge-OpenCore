using StarBridge.Core.Events;

namespace StarBridge.Desktop;

public static class OverlayGameEventNotificationPolicy
{
    public static OverlayEventNotificationTypes ResolveNotificationType(FleetEventType eventType)
    {
        return eventType switch
        {
            FleetEventType.PlayerDowned or FleetEventType.PlayerDied or
                FleetEventType.PlayerRevived or FleetEventType.PlayerRespawned =>
                OverlayEventNotificationTypes.DeathAndRespawn,
            _ => OverlayEventNotificationTypes.None
        };
    }

    public static bool ShouldQueue(
        FleetEventType eventType,
        OverlayEventNotificationTypes enabledTypes)
    {
        var notificationType = ResolveNotificationType(eventType);
        return notificationType != OverlayEventNotificationTypes.None &&
               enabledTypes.HasFlag(notificationType);
    }

    public static OverlayGameEventNotification? Create(
        FleetEventType eventType,
        string player,
        bool useChinese,
        LifeEventContext lifeContext = LifeEventContext.Unknown)
    {
        return eventType switch
        {
            FleetEventType.PlayerDowned => CreateDownedNotification(player, useChinese, lifeContext),
            FleetEventType.PlayerDied => new OverlayGameEventNotification(
                OverlayEventNotificationTypes.DeathAndRespawn,
                useChinese ? "玩家死亡" : "Player died",
                useChinese ? $"{player} 已死亡，等待重生" : $"{player} died and is awaiting respawn",
                Important: true,
                Positive: false),
            FleetEventType.PlayerRevived => new OverlayGameEventNotification(
                OverlayEventNotificationTypes.DeathAndRespawn,
                useChinese ? "玩家获救" : "Player revived",
                useChinese ? $"{player} 已被救起，恢复行动" : $"{player} was revived and is back in action",
                Important: false,
                Positive: true),
            FleetEventType.PlayerRespawned => new OverlayGameEventNotification(
                OverlayEventNotificationTypes.DeathAndRespawn,
                useChinese ? "玩家重生" : "Player respawned",
                useChinese ? $"{player} 已重生" : $"{player} respawned",
                Important: false,
                Positive: true),
            _ => null
        };
    }

    private static OverlayGameEventNotification CreateDownedNotification(
        string player,
        bool useChinese,
        LifeEventContext lifeContext)
    {
        var safeZone = lifeContext == LifeEventContext.SafeZoneMedicalResponse;
        return new OverlayGameEventNotification(
            OverlayEventNotificationTypes.DeathAndRespawn,
            useChinese
                ? safeZone ? "安全区倒地" : "玩家倒地"
                : safeZone ? "Downed in safe zone" : "Player downed",
            useChinese
                ? safeZone
                    ? $"{player} 在安全区倒地，本地救援已响应"
                    : $"{player} 已失去行动能力，等待救援"
                : safeZone
                    ? $"{player} is down in a safe zone; local medical response is active"
                    : $"{player} is incapacitated and awaiting rescue",
            Important: true,
            Positive: false);
    }
}

public sealed record OverlayGameEventNotification(
    OverlayEventNotificationTypes EventType,
    string Title,
    string Detail,
    bool Important,
    bool Positive);
