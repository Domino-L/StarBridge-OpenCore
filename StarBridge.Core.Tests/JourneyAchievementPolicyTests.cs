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
        Require(JourneyAchievementPolicy.IsKnown("journey-stanton") && JourneyAchievementPolicy.AwardIds.Count == 9, "server-owned aggregate");
        foreach (var code in new[] { "Everus Harbor", "Port Tressler", "Kareah", "Stanton1", "Stanton3", "Stanton1_Lorville_fake" })
            Require(JourneyAchievementPolicy.ResolveCity([code]) is null, "unrelated " + code);
        Require(!JourneyAchievementPolicy.IsKnown("journey-lorville-1") && !JourneyAchievementPolicy.IsKnown(null) &&
            !JourneyAchievementPolicy.IsKnown("JOURNEY-ORISON") && !JourneyAchievementPolicy.IsCity("stanton"), "finite wire identifiers");
        Require(JourneyAchievementPolicy.Tokens.Count == 29 && JourneyAchievementPolicy.Tokens.Distinct().Count() == 29 &&
            JourneyAchievementPolicy.Tokens.Last() == "grimhex", "finite observations");
        Require(JourneyAchievementPolicy.AwardIds.SequenceEqual(JourneyAchievementPolicy.Cities.Select(JourneyAchievementPolicy.Id)
            .Concat(["journey-stanton", "journey-levski", "journey-pyro-majors", "journey-pyro-all", "journey-grimhex"])), "visible award order");
        foreach (var token in JourneyAchievementPolicy.Tokens)
        {
            var id = JourneyAchievementPolicy.Id(token);
            Require(JourneyAchievementPolicy.IsToken(token) && JourneyAchievementPolicy.IsKnown(id), "known token " + token);
            Require(JourneyAchievementPolicy.IsStationMarker(id) == token.StartsWith("station-", StringComparison.Ordinal), "hidden marker " + id);
            Require(JourneyAchievementPolicy.IsAward(id) != JourneyAchievementPolicy.IsStationMarker(id), "award/marker separation");
        }
        foreach (var (leaf, root, token) in new[] {
            ("RR_P2_L4_CLINIC", "RR_P2_L4", "station-rr-p2-l4"),
            ("Hospital_Pyro_Pyro6_L1", "RR_P6_L1", "station-rr-p6-l1"),
            ("Pyro6_L1_Habs", "RR_P6_L1", "station-rr-p6-l1"),
            ("ContestedZone_RR_P3_LEO", "RR_P3_LEO", "station-rr-p3-leo"),
            ("Hospital_Nyx_Levski", "Nyx_Levski", "levski"),
            ("Stanton2_housing_grimhex_clinic", "GrimHEX", "grimhex") })
        {
            Require(JourneyAchievementPolicy.ResolveCity([leaf, root]) == token, "catalog ancestor " + leaf);
            Require(JourneyAchievementPolicy.ResolveCity([leaf]) is null, "no substring inference " + leaf);
        }
        foreach (var invalid in new[] { "RR_JP_PyroStanton", "RR_P1_L1", "RR_P4_LEO", "RR_P2_L4_FAKE" })
            Require(JourneyAchievementPolicy.ResolveCity([invalid]) is null, "unlisted station " + invalid);
        Require(!JourneyAchievementPolicy.IsKnown("journey-station-rr-p1-l1") &&
            !JourneyAchievementPolicy.IsToken("pyro-all") && !JourneyAchievementPolicy.IsToken("pyro-majors") &&
            !JourneyAchievementPolicy.IsCity("levski") && !JourneyAchievementPolicy.IsCity("grimhex"), "collections are not observation tokens; cities remain four");
        Console.WriteLine("PASS CITYHOST policy: 1 group, 0 failed");
    }
    private static void Require(bool value, string reason) { if (!value) throw new Exception(reason); }
}
