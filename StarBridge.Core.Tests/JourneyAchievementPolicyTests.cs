using StarBridge.Core.Achievements;

namespace StarBridge.Core.Tests;

internal static class JourneyAchievementPolicyTests
{
    internal static void RunAll()
    {
        foreach (var (root, city) in JourneyAchievementPolicy.Roots)
        {
            Require(JourneyAchievementPolicy.ResolveCity([root.ToUpperInvariant()]) == city, root);
            Require(JourneyAchievementPolicy.ResolveCity(["Synthetic_Hospital", root, "Stanton"]) == city, "ancestor " + root);
            Require(JourneyAchievementPolicy.IsKnown(JourneyAchievementPolicy.Id(city)), "known city");
        }
        Require(JourneyAchievementPolicy.IsKnown("journey-stanton") && JourneyAchievementPolicy.Ids.Count == 5, "server-owned aggregate");
        foreach (var code in new[] { "Everus Harbor", "Port Tressler", "GrimHEX", "Stanton1", "Stanton3", "Stanton1_Lorville_fake" })
            Require(JourneyAchievementPolicy.ResolveCity([code]) is null, "unrelated " + code);
        Require(!JourneyAchievementPolicy.IsKnown("journey-lorville-1") && !JourneyAchievementPolicy.IsKnown(null) &&
            !JourneyAchievementPolicy.IsKnown("JOURNEY-ORISON") && !JourneyAchievementPolicy.IsCity("stanton"), "finite wire identifiers");
        Console.WriteLine("PASS CITYHOST policy: 1 group, 0 failed");
    }
    private static void Require(bool value, string reason) { if (!value) throw new Exception(reason); }
}
