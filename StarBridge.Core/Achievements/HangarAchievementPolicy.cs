namespace StarBridge.Core.Achievements;

public sealed record HangarAchievementCounts(int TotalShips, int DistinctModels, int PurposeClasses)
{
    public bool IsValid => TotalShips is >= 0 and <= 10000 && DistinctModels >= 0 &&
        DistinctModels <= TotalShips && PurposeClasses >= 0 && PurposeClasses <= Math.Min(6, DistinctModels);
    public HangarAchievementCounts Max(HangarAchievementCounts other) => new(
        Math.Max(TotalShips, other.TotalShips), Math.Max(DistinctModels, other.DistinctModels),
        Math.Max(PurposeClasses, other.PurposeClasses));
}

// Each peak has a complete simultaneous inventory as its witness. These are
// private collection milestones, not ownership proofs or entitlement grants.
public static class HangarAchievementPolicy
{
    public const int Version = 1;
    public static IReadOnlyList<string> Ids { get; } = Array.AsReadOnly(new[] { "hangar-home", "hangar-collection", "hangar-paths" });
    public static IReadOnlyList<int> Thresholds(string id) => Array.AsReadOnly(id switch
    {
        "hangar-home" => new[] { 1, 3, 5, 10, 20 },
        "hangar-collection" => new[] { 3, 5, 8, 12, 20 },
        "hangar-paths" => new[] { 2, 3, 4, 5, 6 },
        _ => throw new ArgumentException("Unknown achievement series.")
    });
    public static int Progress(string id, HangarAchievementCounts counts) => id switch
    {
        "hangar-home" => counts.TotalShips, "hangar-collection" => counts.DistinctModels,
        "hangar-paths" => counts.PurposeClasses, _ => throw new ArgumentException("Unknown achievement series.")
    };
    public static string Roman(int rank) => rank switch { 1 => "I", 2 => "II", 3 => "III", 4 => "IV", 5 => "V", _ => "" };
    public static bool Known(string id) => id == FirstEntryAchievementPolicy.Id || Ids.Contains(id);
}
