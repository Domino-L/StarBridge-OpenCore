namespace StarBridge.Core.Events;

/// <summary>Minimal event payload; deliberately excludes log text and local identifiers.</summary>
public sealed record SharedActivityEvent(string Id, string Type, DateTimeOffset OccurredAt)
{
    public static SharedActivityEventTypes Category(string type) => type switch
    {
        "GameStarted" or "GameStopped" => SharedActivityEventTypes.Presence,
        "ServerJoined" or "ServerLeft" => SharedActivityEventTypes.Server,
        "PlayerEnteredShip" or "PlayerExitedShip" or "PlayerControllingShip" or
            "PlayerStoppedDrivingShip" => SharedActivityEventTypes.Ship,
        "PlayerLocationChanged" => SharedActivityEventTypes.Location,
        "PlayerDowned" or "PlayerDied" or "PlayerRevived" or "PlayerRespawned" => SharedActivityEventTypes.Life,
        _ => SharedActivityEventTypes.None
    };

    // Match the S2 event age window, without treating a future timestamp as fresh.
    public bool IsFresh(DateTimeOffset now) => OccurredAt >= now.AddMinutes(-2) &&
        OccurredAt <= now.AddSeconds(15);
}
