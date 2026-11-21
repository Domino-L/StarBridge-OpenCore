using System.Text.Json.Serialization;
using StarBridge.Core.Achievements;

namespace StarBridge.HostRuntime.Achievements;

public sealed record ContractObservation(int SchemaVersion, string HandleHash, string MissionId, string Contract,
    string? DefinitionId, string Outcome, bool Owner, bool CompleteRun, int Deaths,
    DateTimeOffset AcceptedAt, DateTimeOffset? ArrivedAt, DateTimeOffset CompletedAt)
{
    // Same required grammar as Java ContractObservation; unknown templates remain reportable.
    internal static bool IsValidContract(string? value) => value is { Length: > 0 and <= 128 } &&
        (char.IsAsciiLetterOrDigit(value[0]) || value[0] == '_') &&
        value.All(c => char.IsAsciiLetterOrDigit(c) || c is '_' or '-');

    [JsonIgnore]
    public bool IsValid => SchemaVersion == 1 && HandleHash is { Length: 64 } &&
        HandleHash.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f') &&
        Guid.TryParseExact(MissionId, "D", out var mission) && mission != Guid.Empty &&
        IsValidContract(Contract) &&
        (DefinitionId is null || Guid.TryParseExact(DefinitionId, "D", out var definition) && definition != Guid.Empty) &&
        Outcome == "completed" && Deaths is >= 0 and <= 10000 && AcceptedAt > DateTimeOffset.UnixEpoch &&
        AcceptedAt.Offset == TimeSpan.Zero && CompletedAt.Offset == TimeSpan.Zero && AcceptedAt <= CompletedAt &&
        (ArrivedAt is null || ArrivedAt.Value.Offset == TimeSpan.Zero && ArrivedAt >= AcceptedAt && ArrivedAt <= CompletedAt);
}

public sealed record ContractAchievementReceipt(int SchemaVersion, Dictionary<string, DateTimeOffset> EarnedAt,
    string[] NewlyEarned, Dictionary<string, int>? Progress = null)
{
    public AchievementSnapshot Snapshot => new(SchemaVersion, EarnedAt, Progress);
    public void Validate()
    {
        Snapshot.Validate();
        if (NewlyEarned is null || NewlyEarned.Length > 5 || NewlyEarned.Distinct().Count() != NewlyEarned.Length ||
            NewlyEarned.Any(id => !ContractAchievementPolicy.IsAward(id) || !EarnedAt.ContainsKey(id)))
            throw new InvalidDataException("Invalid contract receipt.");
    }
}
