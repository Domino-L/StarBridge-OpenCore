using StarBridge.Core.Overlay;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.Desktop.Tests;

/// The overview facts: shard labels, grouping, the viewer's own shard and place,
/// and the privacy rule that a shared-fields-only self row never picks up local evidence.
internal static class OverlayOverviewFactsTests
{
    private const string Own = "pub_euw1b_12881860_040";

    internal static void RunAll()
    {
        var tests = new (string Name, Action Run)[]
        {
            ("shard id parsing", ShardIds),
            ("shard labels group by whole id", Grouping),
            ("facts from local evidence", LocalFacts),
            ("facts from a shared-only source", SharedOnlyFacts),
            ("rooms keep their sentence overview", Rooms),
            ("overview height tiers", Tiers),
        };
        var failed = 0;
        foreach (var test in tests)
        {
            try { test.Run(); Console.WriteLine("PASS overview facts " + test.Name); }
            catch (Exception error) { failed++; Console.WriteLine("FAIL overview facts " + test.Name + ": " + error.Message); }
        }
        Console.WriteLine($"Overview facts: {tests.Length - failed} passed, {failed} failed");
        if (failed > 0) throw new Exception($"Overview facts: {failed} failed");
    }

    private static void ShardIds()
    {
        Check(PublicShardId.TryParse(" pub_use1b_12326004_040 ", out var shard) && shard.Region == "use1b" && shard.Instance == "12326004" && shard.Tail == "040",
            "region, instance and tail are read from the id");
        Check(PublicShardId.TryParse("pub_sc_alpha_apse1_123", out var alpha) && alpha.Tail == "123" && alpha.Instance == "alpha_apse1",
            "older ids with more segments still parse");
        foreach (var bad in new[] { null, "", "EU", "pub_use1b", "pub_use1b_12326004_04x", "pub_use1b_12326004_040;rm", "pub_use1b_12326004_040_", "pub__12326004_040", new string('a', 200) })
            Check(!PublicShardId.IsValid(bad), "rejected: " + (bad ?? "null"));
        Check(OverlayShardPresentation.Label(Own, zh: true) == "欧服 #040", "zh label");
        Check(OverlayShardPresentation.Label("pub_use1b_12326004_040", zh: false) == "US #040", "en label");
        Check(OverlayShardPresentation.Label("EU", zh: true) is null, "a bare region is not a shard");
    }

    private static void Grouping()
    {
        var rows = new (string? Shard, string? Region)[]
        {
            (Own, "EU"), (Own, null), ("pub_euw1b_12881860_112", "EU"),
            ("pub_use1b_12881860_040", "US"),           // same number, other region
            ("pub_euw1b_12660092_040", "EU"),           // same region and number, older game version
            (null, "US"), ("pub_bad", "ASIA")            // region only
        };
        var groups = OverlayShardPresentation.Group(rows, Own, zh: true);
        Check(groups[0].IsOwn && groups[0].Count == 2 && groups[0].Label == "欧服 #040 (1860)", "own shard first, counted by whole id, collision shows the version");
        Check(groups.Any(g => g.Label == "欧服 #040 (0092)" && g.Count == 1 && !g.IsOwn), "the older version is a different shard");
        Check(groups.Any(g => g.Label == "美服 #040" && g.Count == 1), "another region keeps its plain label");
        Check(groups.Any(g => g.Id == "region:US" && g.Label == "美服" && g.Count == 1), "rows that shared only a region form a region group");
        Check(groups.Any(g => g.Id == "region:ASIA" && g.Count == 1), "an unparsable shard text counts under its region");
        Check(groups.Count(g => g.Id.StartsWith("region:")) == 2 && groups.TakeWhile(g => !g.Id.StartsWith("region:")).Count() == 4,
            "region groups sort after shard groups");
    }

    private static InformationOverlayCommunityMember M(string id, string presence, string location, string shard, bool self = false) =>
        new(id, id, "成员", presence, "ANVL_Carrack", location, GameServerRegionPresentation.ResolveCode(shard) ?? "", self)
        { ServerShard = PublicShardId.IsValid(shard) ? shard : null };

    private static OverlayOverviewFacts Facts(InformationOverlayCommunityContent content, GameLogSessionSnapshot? local, PlayerPresenceKind presence)
    {
        var source = NativeInformationOverlayRuntime.ProjectSource(null, content, OverlayScenePreference.Auto, "zh", true,
            localSession: local, localPresence: presence);
        var model = new OverlayViewModel(new(source.Scene.Players), OverlayDisplaySettings.Default with { HideSelfMember = false },
            OverlayRosterSelectionSettings.Default, "zh", true, source.Command, presence, local?.Server.Shard ?? "", source.Scene.Context);
        try { return model.OverviewFacts ?? throw new Exception("organization sources expose facts"); }
        finally { model.ClearAuthorizedContent(); }
    }

    private static void LocalFacts()
    {
        // Place names outside the location catalog, so the result does not depend on whether this build has it.
        var local = new GameLogSessionSnapshot(new("connected", "EU", Own), new("confirmed", "Fixture Alpha", "Fixture Alpha"), new("confirmed", "ANVL_Carrack", "Anvil Carrack", "卡拉克"));
        var content = new InformationOverlayCommunityContent("org", "Fixture",
        [
            M("Self", "AppOnline", "", "", self: true),          // stale shared row; local evidence wins
            M("A", "InGame", "Fixture Alpha", Own), M("B", "InGame", "Fixture Beta", "pub_use1b_12881860_007"),
            M("C", "InGame", "", ""), M("D", "AppOnline", "", ""), M("E", "Away", "", ""), M("F", "Offline", "", ""),
        ]);
        var facts = Facts(content, local, PlayerPresenceKind.InGame);
        Check(facts.Total == 7 && facts.Online == 6 && facts.InGame == 4 && facts.AppOnline == 1 && facts.Away == 1 && facts.Offline == 1,
            $"counts use local presence for self: {facts}");
        Check(facts.OwnShard is { Label: "欧服 #040", Count: 2, IsOwn: true }, "own shard comes from the local shard and counts the viewer");
        Check(facts.OwnPlace == "Fixture Alpha", $"own place comes from local evidence: {facts.OwnPlace}");
        Check(facts.Places[0] is { Name: "Fixture Alpha", Count: 2, IsOwn: true }, "places count everyone there, the viewer included, own first");
        Check(facts.Shards.Count == 2 && facts.Shards[1].Label == "美服 #007", "shards: own first, then the rest");
    }

    private static void SharedOnlyFacts()
    {
        var local = new GameLogSessionSnapshot(new("connected", "US", "pub_use1b_12881860_999"), new("confirmed", "Lorville", "罗威尔"), new("confirmed", "x", "Local ship", "本机舰船"));
        var content = new InformationOverlayCommunityContent("fleet", "Fleet",
        [
            M("Self", "InGame", "Fixture Alpha", Own, self: true),
            M("A", "InGame", "Fixture Alpha", Own), M("B", "InGame", "", "pub_use1b_12881860_007"),
        ]) { SharedFieldsOnly = true };
        var facts = Facts(content, local, PlayerPresenceKind.InGame);
        Check(facts.OwnShard is { Label: "美服 #999", Count: 1, IsOwn: true }, "the viewer's own line uses local evidence on their own screen");
        Check(facts.OwnPlace == "罗威尔", "the viewer's own place is local too");
        Check(facts.InGame == 3 && facts.Online == 3 && facts.Total == 3, "organization totals stay projected");
        Check(facts.Shards.Any(shard => shard.Label == "欧服 #040" && shard.Count == 1), "other members stay on the shard they shared; the viewer moved away counts only on their own");
        var hidden = Facts(content with { Members = [M("Self", "InGame", "", "", self: true), M("A", "InGame", "Fixture Alpha", Own)] },
            local with { Server = new("connected", "EU", Own) }, PlayerPresenceKind.InGame);
        Check(hidden.OwnShard is { Label: "欧服 #040", Count: 2 }, "a self row hidden from the organization still counts once on the viewer's own shard");
        Check(hidden.Places.Count(place => place.IsOwn) == 1 && hidden.Places.Single(place => place.IsOwn).Count == 1, "the own place counts the viewer once");
        var moved = Facts(content with { Members = [M("Self", "InGame", "Fixture Alpha", "pub_euw1b_12881860_001", self: true), M("A", "InGame", "Fixture Alpha", Own)] },
            local with { Server = new("connected", "EU", Own) }, PlayerPresenceKind.InGame);
        Check(moved.Shards.All(shard => shard.Label != "欧服 #001") && moved.OwnShard is { Count: 2 }, "a stale shared self row does not count the viewer on a second shard");
        var noEvidence = Facts(content, local with { Server = new("connected", "", ""), Location = new("unknown", null, null) }, PlayerPresenceKind.InGame);
        Check(noEvidence.OwnShard is null && noEvidence.OwnPlace is null && noEvidence.ViewerInGame, "without local evidence the own line stays empty; the shared row is not shown as the viewer's place");
        var offline = Facts(content, local, PlayerPresenceKind.AppOnline);
        Check(offline.OwnShard is null && offline.OwnPlace is null, "not in game: no own line, even if the shared row is stale");
    }

    private static void Rooms()
    {
        var room = new InformationOverlayRoomContent("room", "Room", "Goal", 4, "Self",
            [new("Self", "Self", true, "InGame", "Fixture Alpha", "ANVL_Carrack", "EU") { IsSelf = true, ServerShard = Own }], []);
        var source = NativeInformationOverlayRuntime.ProjectSource(room, null, OverlayScenePreference.PartyRoom, "zh");
        var model = new OverlayViewModel(new(source.Scene.Players), OverlayDisplaySettings.Default, OverlayRosterSelectionSettings.Default,
            "zh", true, source.Command, PlayerPresenceKind.InGame, Own, source.Scene.Context);
        try
        {
            Check(model.OverviewFacts is null, "rooms keep the sentence overview");
            Check(source.Scene.Players.Single().ServerShard == Own, "room members carry the shard they already shared");
        }
        finally { model.ClearAuthorizedContent(); }
    }

    private static void Tiers()
    {
        // The overview may be dragged down to one line; other modules keep their floors.
        var small = InformationOverlayLayoutGeometry.ResolveItemRect(new InformationOverlayLayoutItem("Squads", 0, 0, 340d / 2560, 20d / 1440), 2560, 1440);
        Check(small.Height < 100, $"the overview accepts a one-line height; actual {small.Height}");
        var members = InformationOverlayLayoutGeometry.ResolveItemRect(new InformationOverlayLayoutItem("Members", 0, 0, 340d / 2560, 20d / 1440), 2560, 1440);
        Check(members.Height >= 140, "the member list keeps its minimum height");
        var tall = InformationOverlayLayoutGeometry.ResolveItemRect(new InformationOverlayLayoutItem("Squads", 0, 0, 340d / 3840, 20d / 2160), 3840, 2160);
        Check(tall.Height >= 108, $"a tall screen keeps the 5% a saved item can hold; actual {tall.Height}");
    }

    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
