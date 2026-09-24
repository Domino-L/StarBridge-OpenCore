using StarBridge.Core.Profiles;

namespace StarBridge.Core.Tests;

internal static class GameplayHistoryImportPolicyTests
{
    internal static void RunAll()
    {
        var statistics = new PersonalProfileGameplayStatisticsContract(7200, 0, 0, DateTimeOffset.UnixEpoch);
        Check("unavailable", statistics); // Omitted fields are not an explicit unused state.
        Check("unavailable", null);
        Check("unavailable", null, "completed");
        Check("unavailable", null, "sourceUnavailable");
        Check("unavailable", null, "sourceNotConfigured");
        Check("unavailable", null, "linkRequired");
        Check("available", null, "notStarted");
        Check("available", null, "credentialRequired");
        Check("available", statistics with { HistoryImportState = "unused" }, "completed");
        Check("unavailable", statistics with { HistoryImportState = "unused", HistoricalPlayTimeSeconds = 1 });
        Check("imported", statistics with { HistoryImportState = "imported" });
        var used = statistics with { HistoryImportedAt = DateTimeOffset.UnixEpoch.AddDays(1), HistoryImportState = "unused" };
        Check("imported", used);
        if (GameplayHistoryImportPolicy.Evaluate(used).ImportedAt != used.HistoryImportedAt)
            throw new InvalidOperationException("Consumption timestamp must be retained exactly.");
    }
    private static void Check(string state, PersonalProfileGameplayStatisticsContract? value, string? migration = null)
    {
        if (GameplayHistoryImportPolicy.Evaluate(value, migration).State != state)
            throw new InvalidOperationException("History eligibility must preserve used/unused/unknown evidence.");
    }
}
