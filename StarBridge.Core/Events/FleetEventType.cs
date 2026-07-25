namespace StarBridge.Core.Events;

public enum FleetEventType
{
    Unknown = 0,
    PlayerOnline,
    PlayerOffline,
    PlayerEnteredShip,
    PlayerExitedShip,
    PlayerControllingShip,
    PlayerShipControlSignal,
    PlayerStoppedDrivingShip,
    PlayerLocationChanged,
    PlayerNavigationTargetChanged,
    PlayerDied,
    PlayerRespawned,
    CombatStateChanged,
    NetworkStateChanged,
    PlayerDowned,
    PlayerRevived
}
