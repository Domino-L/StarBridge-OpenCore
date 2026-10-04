using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.PartyRooms;

internal static class NavigationStationDisplayTests
{
    internal static Task Run()
    {
        if (!GameLogLocationCatalogTests.HasPack) return Task.CompletedTask;
        var index = GameLogLocationNameIndex.Load();
        var routes = new (string Outer, string Inner, string Station)[]
        {
            ("pyro2_l4", "p2l4", "RR_P2_L4"), ("pyro3_l1", "p3l1", "RR_P3_L1"),
            ("pyro3_l3", "p3l3", "RR_P3_L3"), ("pyro3_leo", "p3leo", "RR_P3_LEO"),
            ("pyro5_l2", "p5l2", "RR_P5_L2"), ("pyro5_l4", "p5l4", "RR_P5_L4"),
            ("pyro5_l5", "p5l5", "RR_P5_L5"), ("pyro6_l3", "p6l3", "RR_P6_L3"),
            ("pyro6_l4", "p6l4", "RR_P6_L4"), ("pyro6_l5", "p6l5", "RR_P6_L5"),
            ("pyro6_leo", "p6leo_ruinstation", "RR_P6_LEO")
        };
        var cases = 0;
        foreach (var (outer, inner, station) in routes)
        foreach (var route in new[] { "rs_ext_" + outer, "rs_int_" + inner })
        foreach (var input in new[] { route, "LOC_" + route, route.ToUpperInvariant() + " [12345]", "LOC_" + route + " [12345]" })
        {
            Check(index.Find(input) == index.Find(station), "Navigation target must use actual station names: " + input);
            Check(RoomLocationLabels.From(input) == RoomLocationLabels.From(station), "Room/community bridge labels must match station: " + input);
            cases++;
        }
        Check(index.Find("rs_ext_arc-l001") is { ChineseName: "弧-L1 广袤森林站", EnglishName: "ARC-L1 Wide Forest Station" }, "ARC navigation uses full station name");
        Check(index.Find("RR_ARC_L1") == index.Find("rs_ext_arc-l001"), "Legacy override cannot turn the station back into a code label");
        Check(index.Find("rs_ext_cru-leo1") == index.Find("RR_CRU_LEO"), "Correct Seraphim target remains correct");
        foreach (var (route, station, name) in new[] {
            ("rs_ext_pyro-stan_jp1", "RR_JP_PyroStanton", "斯坦顿星门（派罗）"),
            ("rs_ext_stan-pyro_jp1", "RR_JP_StantonPyro", "派罗星门（斯坦顿）"),
            ("rs_ext_stan-terra_jp1", "RR_JP_StantonTerra", "泰拉星门（斯坦顿）"),
            ("rs_ext_stan-magnus_jp1", "RR_JP_StantonMagnus", "尼克斯星门（斯坦顿）") })
        {
            Check(index.Find("LOC_" + route + " [123]")?.ChineseName == name, "Gateway caption includes its host system");
            Check(index.Find(station) == index.Find(route), "Gateway route and actual station use the same contextual name");
            Check(RoomLocationLabels.From(route) == RoomLocationLabels.From(station), "Gateway bridge labels stay aligned");
            Check(RoomLocationLabels.From(index.Find(station)!.EnglishName) == RoomLocationLabels.From(station),
                "Gateway names from a remote shared snapshot retain the same translated labels");
        }
        Check(index.Find("Pyro3_L1")?.EnglishName == "PYR3 L1", "Display pairing must not rewrite independent canonical facts");
        Check(index.Find("rs_ext_pyro3_l2") is null, "No unobserved route can be synthesized");
        Check(index.Find("rs_ext_stan-pyro_jp1") != index.Find("rs_ext_pyro-stan_jp1"), "Jump directions remain independent");
        Console.WriteLine($"PASS navigation station labels: {cases} Pyro forms through actual resolver and bridge, ARC/Seraphim and identity boundaries");
        return Task.CompletedTask;
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
