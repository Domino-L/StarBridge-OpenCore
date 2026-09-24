namespace StarBridge.Core.Profiles;

public sealed record GameplayTimeResetRequest(int SchemaVersion, long ExpectedRevision, string OperationId,
    DateTimeOffset? ExpiresAt = null);
public sealed record GameplayTimeResetState(int SchemaVersion, long Revision, string? LastOperationId,
    long? LastExpectedRevision, long PlayTimeSeconds, long HistoricalPlayTimeSeconds, DateTimeOffset? HistoryImportedAt,
    string? HistoryImportOperationId = null, DateTimeOffset? ObservedAt = null,
    int HistoricalSessionCount = 0, int HistoricalIncompleteSessionCount = 0, bool IsPublic = false);
public sealed record GameplayTimeResetResult(string Outcome, GameplayTimeResetState State);
