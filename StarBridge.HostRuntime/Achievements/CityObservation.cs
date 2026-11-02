using System.Text.Json.Serialization;
using StarBridge.Core.Achievements;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Achievements;

public sealed record CityObservation(int SchemaVersion, string HandleHash, string City, string Evidence)
{
    [JsonIgnore]
    public bool IsValid => SchemaVersion == 1 && HandleHash is { Length: 64 } &&
        HandleHash.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f') &&
        JourneyAchievementPolicy.IsCity(City) && Evidence is "RequestLocationInventory" or "PLAYER_LOCATION";
}
internal sealed record CityArrivalEvidence(BridgeAccountContext Owner, long Generation, CityObservation Observation);

public sealed record CityAchievementReceipt(int SchemaVersion, Dictionary<string, DateTimeOffset> EarnedAt,
    string[] NewlyEarned, Dictionary<string, int>? Progress = null)
{
    public AchievementSnapshot Snapshot => new(SchemaVersion, EarnedAt, Progress);
    public void Validate()
    {
        Snapshot.Validate();
        if (NewlyEarned is null || NewlyEarned.Length > 5 || NewlyEarned.Distinct().Count() != NewlyEarned.Length ||
            NewlyEarned.Any(id => !JourneyAchievementPolicy.IsKnown(id) || !EarnedAt.ContainsKey(id)))
            throw new InvalidDataException("Invalid city receipt.");
    }
}
