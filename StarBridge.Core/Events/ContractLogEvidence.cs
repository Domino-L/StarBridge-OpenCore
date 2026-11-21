namespace StarBridge.Core.Events;

// Objective IDs can include phase_/pickup_/dropoff_ prefixes. They are scoped to MissionId.
public sealed record ContractLogEvidence(string MissionId, string? ObjectiveId = null,
    string? Contract = null, string? DefinitionId = null, string? State = null,
    bool Created = false, string? Text = null, string? PlayerId = null, bool ObjectiveUpserted = false);
