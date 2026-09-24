namespace StarBridge.Core.Profiles;

public sealed record GameplayHistoryImportAssessment(string State, DateTimeOffset? ImportedAt = null);

/// <summary>Consumes verified account data. Null/missing legacy fields never mean a fresh opportunity.</summary>
public static class GameplayHistoryImportPolicy
{
    public static GameplayHistoryImportAssessment Evaluate(PersonalProfileGameplayStatisticsContract? statistics,
        string? migrationState = null)
    {
        if (statistics?.HistoryImportedAt is { } imported) return new("imported", imported);
        if (statistics?.HistoryImportState == "imported") return new("imported");
        if (statistics is not null)
            return new(statistics.HistoryImportState == "unused" &&
                statistics.HistoricalPlayTimeSeconds == 0 && statistics.HistoricalSessionCount == 0 &&
                statistics.HistoricalIncompleteSessionCount == 0 ? "available" : "unavailable");
        return new(migrationState is "notStarted" or "credentialRequired"
            ? "available" : "unavailable");
    }
}
