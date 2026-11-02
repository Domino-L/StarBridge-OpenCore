using StarBridge.Core.Achievements;
namespace StarBridge.Core.Tests;
internal static class HangarAchievementPolicyTests
{
    internal static void RunAll()
    {
        if (!HangarAchievementPolicy.Thresholds("hangar-home").SequenceEqual(new[] { 1, 3, 5, 10, 20 }) ||
            !HangarAchievementPolicy.Thresholds("hangar-collection").SequenceEqual(new[] { 3, 5, 8, 12, 20 }) ||
            !HangarAchievementPolicy.Thresholds("hangar-paths").SequenceEqual(new[] { 2, 3, 4, 5, 6 })) throw new Exception("Rank policy changed.");
        var old = new HangarAchievementCounts(10, 8, 4); var next = old.Max(new(3, 3, 2));
        if (next != old || !next.IsValid || new HangarAchievementCounts(1, 2, 1).IsValid ||
            new HangarAchievementCounts(8, 8, 7).IsValid || HangarAchievementPolicy.Roman(4) != "IV") throw new Exception("Invalid count/rank semantics.");
    }
}
