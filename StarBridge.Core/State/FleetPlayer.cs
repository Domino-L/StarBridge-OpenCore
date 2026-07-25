namespace StarBridge.Core.State;

public sealed class FleetPlayer
{
    public required string Name { get; init; }
    public string Ship { get; set; } = "Unknown";
    public string ShipConfidence { get; set; } = "None";
    public string ShipEvidence { get; set; } = "No ship evidence";
    public int ShipInferenceScore { get; set; }
    public string? ShipInstanceId { get; set; }
    public bool ShipChannelMembershipConfirmed { get; set; }
    public DateTimeOffset? LastShipEvidenceAt { get; set; }
    public DateTimeOffset? LastShipScoreUpdatedAt { get; set; }
    public DateTimeOffset? LastShipInstanceSeenAt { get; set; }
    public DateTimeOffset? LastShipChannelEventAt { get; set; }
    public DateTimeOffset? LastControlSeatLeftAt { get; set; }
    public string? LastKnownShip { get; set; }
    public string? LastKnownShipInstanceId { get; set; }
    public string Location { get; set; } = "Unknown";
    public string LocationConfidence { get; set; } = "None";
    public string LocationEvidence { get; set; } = "No location evidence";
    public int LocationInferenceScore { get; set; }
    public DateTimeOffset? LastLocationEvidenceAt { get; set; }
    public DateTimeOffset? LastLocationScoreUpdatedAt { get; set; }
    public string? LastKnownLocation { get; set; }
    public string NavigationTarget { get; set; } = "None";
    public DateTimeOffset? NavigationTargetSelectedAt { get; set; }
    public string? NavigationOriginLocation { get; set; }
    public DateTimeOffset? LastQuantumArrivalAt { get; set; }
    public string Role { get; set; } = "Unassigned";
    public string CombatState { get; set; } = "Idle";
    public string NetworkState { get; set; } = "Unknown";
    public bool Online { get; set; }
    public bool IsIdle { get; set; }
    public DateTimeOffset LastSeen { get; set; } = DateTimeOffset.Now;
}
