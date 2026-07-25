namespace StarBridge.Core.Events;

public sealed record FleetEvent(
    FleetEventType Type,
    string Player,
    string? Ship = null,
    string? Location = null,
    string? CombatState = null,
    string? NetworkState = null,
    DateTimeOffset? Timestamp = null,
    string? SourceLine = null,
    string? PlayerId = null,
    string? ShipOwner = null,
    string? ShipInstanceId = null,
    string? NavigationTarget = null,
    int LocationEvidenceScore = 0,
    string? LocationEvidence = null,
    DateTimeOffset? NavigationTargetSelectedAt = null,
    string? NavigationOriginLocation = null,
    LifeEventContext LifeContext = LifeEventContext.Unknown);
