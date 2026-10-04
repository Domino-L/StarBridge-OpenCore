using System.Text.Json;
using StarBridge.Core.Events;
using StarBridge.Core.Ships;
using StarBridge.Core.State;

namespace StarBridge.Core.Tests;

internal static class ShipCatalogCoverageTests
{
    public static void RunAll()
    {
        using var stream = typeof(ShipNameIndex).Assembly.GetManifestResourceStream("StarBridge.ShipNamePack.json")!;
        using var document = JsonDocument.Parse(stream);
        var rows = document.RootElement.GetProperty("entries").EnumerateArray().ToArray();
        var checkedAliases = 0;
        var ambiguous = 0;
        foreach (var row in rows)
        {
            var runtime = row.GetProperty("runtimeId").GetString()!;
            var chinese = row.GetProperty("chineseName").GetString()!;
            Require(ShipNameIndex.Bundled.Find(runtime)?.ChineseName == chinese, "Every runtime ID translates: " + runtime);
            var aliases = new[] { runtime, row.GetProperty("englishName").GetString()!, chinese }
                .Concat(row.GetProperty("aliases").EnumerateArray().Select(a => a.GetString()!)).Distinct();
            foreach (var alias in aliases)
            {
                var resolved = ShipNameIndex.Bundled.Find(alias);
                if (resolved is null) { ambiguous++; continue; } // Exact collisions intentionally remain unresolved.
                Require(resolved.RuntimeId == runtime, "Alias must not resolve to another model: " + alias);
                var time = DateTimeOffset.Parse("2026-09-30T12:00:00Z");
                var state = new FleetState();
                state.Apply(new(FleetEventType.PlayerEnteredShip, "Fixture", Ship: alias, Timestamp: time));
                state.Apply(new(FleetEventType.PlayerExitedShip, "Fixture", Ship: runtime, Timestamp: time.AddSeconds(1)));
                Require(state.Players.Single().Ship == "Unknown", "Every exact alias clears on the corresponding exit: " + alias);
                state.SetPlayerOnlineState("Fixture", true, time.AddSeconds(2));
                Require(state.Players.Single().Ship == "Unknown", "No released alias resurrects on refresh: " + alias);
                checkedAliases++;
            }
        }
        Require(rows.Length > 100 && checkedAliases > rows.Length, "Coverage uses the complete bundled catalog.");
        const string tsv = "英文飞船名\t中文飞船名\t制造商\nFixture Display EX\t测试展示EX\tAegis Dynamics\nSabre Raven\t渡鸦\tAegis Dynamics\n";
        using var namesStream = typeof(ShipNameIndex).Assembly.GetManifestResourceStream("StarBridge.ShipNamePack.json")!;
        using var reader = new StreamReader(namesStream);
        var index = ShipNameIndex.Parse(reader.ReadToEnd(), tsv);
        Require(index.Find("Aegis Fixture Display EX") is { RuntimeId: null, ChineseName: "测试展示EX" },
            "Display-only EX is translated without inventing a runtime ID.");
        Require(index.Find("Aegis Sabre Raven")?.RuntimeId == "AEGS_Sabre_Raven", "EX never replaces the existing Raven.");
        Require(index.Find("AEGS_Fixture_Display_EX") is null, "Unobserved runtime spelling is not fabricated from a display row.");
        var sharedModel = ShipNameIndex.Parse("""
            {"schemaVersion":1,"entries":[
              {"runtimeId":"TEST_A","englishName":"Shared Model","chineseName":"测试甲","aliases":[]},
              {"runtimeId":"TEST_B","englishName":"Shared Model","chineseName":"测试乙","aliases":[]}]}
            """, "英文飞船名\t中文飞船名\t制造商\nShared Model\t测试型号\tFixture\n");
        Require(sharedModel.Find("Shared Model") is null && sharedModel.FindDisplay("Shared Model") is { RuntimeId: null, ChineseName: "测试型号" },
            "A display translation must never manufacture identity for two runtimes sharing a model label.");
        Console.WriteLine($"PASS complete ship catalog: {rows.Length} runtime entries, {checkedAliases} alias acquisition/exit pairs, {ambiguous} ambiguous alias occurrences kept unresolved");
    }
    private static void Require(bool value, string message) { if (!value) throw new Exception(message); }
}
