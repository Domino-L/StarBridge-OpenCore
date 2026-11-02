using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Serialization;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Achievements;

public sealed record FirstEntryObservation(int SchemaVersion, string HandleHash, string Channel, string ServerState = "connected")
{
    public static string HashHandle(string handle) => Convert.ToHexString(SHA256.HashData(
        Encoding.UTF8.GetBytes(handle.Trim().ToLowerInvariant()))).ToLowerInvariant();
    [JsonIgnore]
    public bool IsValid => SchemaVersion == 1 && HandleHash is { Length: 64 } &&
        HandleHash.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f') &&
        StarBridge.Core.Achievements.FirstEntryAchievementPolicy.CanUnlock(true, true, Channel, ServerState);
}
internal sealed record FirstEntryEvidence(BridgeAccountContext Owner, long Generation, FirstEntryObservation Observation);
public sealed record AchievementSnapshot(int SchemaVersion, Dictionary<string, DateTimeOffset> EarnedAt,
    Dictionary<string, int>? Progress = null)
{
    internal AchievementSnapshot MergeConfirmed(AchievementSnapshot next)
    {
        var earned = new Dictionary<string, DateTimeOffset>(next.EarnedAt);
        foreach (var entry in EarnedAt) earned[entry.Key] = entry.Value;
        Dictionary<string, int>? progress = Progress is null && next.Progress is null ? null : new(Progress ?? []);
        if (next.Progress is not null)
            foreach (var entry in next.Progress)
                progress![entry.Key] = Math.Max(progress.GetValueOrDefault(entry.Key), entry.Value);
        var merged = new AchievementSnapshot(1, earned, progress);
        merged.Validate();
        return merged;
    }

    public void Validate()
    {
        if (SchemaVersion != 1 || EarnedAt is null || EarnedAt.Count > 256 || EarnedAt.Any(p =>
            p.Key.Length is < 1 or > 64 || p.Key.Any(c => !(char.IsAsciiLetterOrDigit(c) || c == '-')) ||
            p.Value <= DateTimeOffset.UnixEpoch || p.Value > DateTimeOffset.UtcNow.AddMinutes(5)))
            throw new InvalidDataException("Invalid achievement response.");
        if (Progress is not null && (Progress.Count > 4 || Progress.Any(p =>
            (!Core.Achievements.HangarAchievementPolicy.Ids.Contains(p.Key) && p.Key != Core.Achievements.JourneyAchievementPolicy.StantonId) ||
            p.Value is < 0 or > 10000 || p.Key == Core.Achievements.JourneyAchievementPolicy.StantonId && p.Value > 4 ||
            p.Key == "hangar-paths" && p.Value > 6))) throw new InvalidDataException("Invalid achievement progress.");
        foreach (var id in Core.Achievements.HangarAchievementPolicy.Ids)
        {
            var gap = false;
            for (var rank = 1; rank <= 5; rank++)
            {
                if (!EarnedAt.ContainsKey($"{id}-{rank}")) { gap = true; continue; }
                if (gap || Progress is not null && Progress.TryGetValue(id, out var peak) &&
                    peak < Core.Achievements.HangarAchievementPolicy.Thresholds(id)[rank - 1])
                    throw new InvalidDataException("Inconsistent achievement ranks.");
            }
        }
    }
}
public sealed record AchievementReceipt(int SchemaVersion, Dictionary<string, DateTimeOffset> EarnedAt, bool NewlyEarned,
    Dictionary<string, int>? Progress = null);
public sealed record HangarAchievementReceipt(int SchemaVersion, Dictionary<string, DateTimeOffset> EarnedAt,
    Dictionary<string, int> Progress, string[] NewlyEarned)
{
    public AchievementSnapshot Snapshot => new(SchemaVersion, EarnedAt, Progress);
    public void Validate()
    {
        Snapshot.Validate();
        if (NewlyEarned is null || NewlyEarned.Length > 15 || NewlyEarned.Distinct().Count() != NewlyEarned.Length ||
            NewlyEarned.Any(id => !EarnedAt.ContainsKey(id) || !Core.Achievements.HangarAchievementPolicy.Ids.Any(series =>
                Enumerable.Range(1, 5).Any(rank => id == $"{series}-{rank}")))) throw new InvalidDataException();
    }
}
internal interface IAchievementRemote
{
    Task<AchievementSnapshot> ReadAchievementsAsync(BridgeAccountContext owner, long generation, CancellationToken token);
    Task<AchievementReceipt> ObserveFirstEntryAsync(BridgeAccountContext owner, long generation, FirstEntryObservation observation, CancellationToken token);
    Task<CityAchievementReceipt> ObserveCityAsync(BridgeAccountContext owner, long generation,
        CityObservation observation, CancellationToken token) => throw new NotSupportedException();
    Task<HangarAchievementReceipt> ObserveHangarAsync(BridgeAccountContext owner, long generation,
        HangarAchievementObservation observation, CancellationToken token) => throw new NotSupportedException();
}
