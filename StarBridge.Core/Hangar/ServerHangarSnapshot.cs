namespace StarBridge.Core.Hangar;

// Existing server records, not proof of a complete local backup or ownership.
public sealed record ServerHangarSnapshot(int SchemaVersion, string State, string AccountId,
    string LocalCoverage, string? SnapshotSha256, MigrationShip[] Ships);
