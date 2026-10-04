using StarBridge.HostRuntime.Overlay;
using System.Text.Json;
using StarBridge.Core.Ships;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.Desktop.Tests;

internal static class OverlayShipNameTests
{
    internal static void RunAll()
    {
        Check(ShipDisplayNamePresentation.ResolveChinese("Anvil F8C Lightning", "待确认") == "F8C 闪电",
            "Official channel name is translated in the actual renderer.");
        Check(ShipDisplayNamePresentation.ResolveChinese("渡鸦EX", "待确认") == "渡鸦EX", "Mixed Chinese/model labels survive.");
        Check(ShipDisplayNamePresentation.ResolveChinese("Uncatalogued Fixture Ship", "待确认") == "Uncatalogued Fixture Ship",
            "A detected name lacking a translation must not become an unknown ship.");
        foreach (var ship in new[] { "Anvil F8C Lightning", "ANVL_Lightning_F8C", "F8C 闪电" })
        foreach (var roomMode in new[] { true, false })
        {
            var room = new InformationOverlayRoomContent("fixture", "Room", "", 4, "",
                [new("Peer", "Peer", false, "InGame", "", ship, "US")], []);
            var community = new InformationOverlayCommunityContent("fixture", "Community",
                [new("Peer", "Peer", "Member", "InGame", Ship: ship, Location: "", ServerRegion: "US", IsSelf: false)]);
            var source = NativeInformationOverlayRuntime.ProjectSource(roomMode ? room : null,
                roomMode ? null : community, OverlayScenePreference.Auto, "zh");
            Check(source.Scene.Players.Single().SharedShipDisplayText == "F8C 闪电",
                $"Both scenes use the same translated name: room={roomMode}, raw={ship}, actual={source.Scene.Players.Single().SharedShipDisplayText}, ship={source.Scene.Players.Single().Ship}, presence={source.Scene.Players.Single().SharedPresence}");
            Check(OverlayEventShipPresentation.FormatShipChange("Peer", ship, true).EndsWith("F8C 闪电"),
                "Ship events agree with the member row.");
        }
        using var pack = typeof(ShipNameIndex).Assembly.GetManifestResourceStream("StarBridge.ShipNamePack.json")!;
        using var document = JsonDocument.Parse(pack);
        var names = document.RootElement.GetProperty("entries").EnumerateArray()
            .SelectMany(row => new[] { row.GetProperty("runtimeId").GetString()!, row.GetProperty("englishName").GetString()!,
                row.GetProperty("chineseName").GetString()! }.Concat(row.GetProperty("aliases").EnumerateArray().Select(a => a.GetString()!))).ToArray();
        foreach (var raw in names)
        {
            var expected = Chinese(raw) ? raw : GameShipNames.Find(raw)?.ChineseName ?? raw;
            Check(ShipDisplayNamePresentation.ResolveChinese(raw, "待确认") == expected, "Complete renderer vocabulary: " + raw);
            Check(OverlayEventShipPresentation.FormatShipChange("Peer", raw, true).EndsWith(expected), "Complete event vocabulary: " + raw);
            CheckBothScenes(raw, expected);
        }
        Console.WriteLine($"PASS all {names.Length} bundled ship name/alias rendering inputs");
    }

    internal static void FullDisplayCatalog(string path)
    {
        var lines = System.IO.File.ReadAllLines(path);
        var header = lines[0].TrimStart('\uFEFF').Split('\t');
        var en = Array.IndexOf(header, "英文飞船名"); var zh = Array.IndexOf(header, "中文飞船名");
        var maker = Array.IndexOf(header, "制造商");
        var count = 0;
        var displayOnlyChinese = 0;
        var failures = new List<string>();
        foreach (var row in lines.Skip(1).Select(line => line.Split('\t')).Where(row => row.Length > Math.Max(en, zh)))
        {
            var english = row[en].Trim(); var chinese = row[zh].Trim();
            if (english.Length == 0 || chinese.Length == 0) continue;
            var name = GameShipNames.Find(english);
            if (name is null || string.IsNullOrWhiteSpace(name.ChineseName))
            { failures.Add("Untranslated display model: " + english); continue; }
            foreach (var raw in new[] { english, chinese, maker >= 0 && row.Length > maker ? row[maker].Trim() + " " + english : english })
            {
                var match = GameShipNames.Find(raw);
                if (raw == chinese)
                {
                    Check(ShipDisplayNamePresentation.ResolveChinese(raw, "待确认") == raw, "Already translated Chinese labels remain stable.");
                    CheckBothScenes(raw, raw);
                    if (match?.RuntimeId is null) displayOnlyChinese++;
                    else if (name.RuntimeId is not null && match.RuntimeId != name.RuntimeId) failures.Add("Chinese label maps another variant: " + raw);
                    continue;
                }
                if (match?.ChineseName != name.ChineseName) failures.Add("Catalog spelling mismatch: " + raw);
                if (ShipDisplayNamePresentation.ResolveChinese(raw, "待确认") != name.ChineseName) failures.Add("Native rendering mismatch: " + raw);
                if (match is not null) CheckBothScenes(raw, match.ChineseName);
            }
            count++;
        }
        Check(GameShipNames.Find("Sabre Raven EX")?.ChineseName == "渡鸦EX", "Raven EX has its independent translation.");
        Check(failures.Count == 0, string.Join("\n", failures));
        Console.WriteLine($"PASS all {count} complete display-catalog entries and name/manufacturer forms; {displayOnlyChinese} labels translated without assigning a runtime ID");
    }
    private static bool Chinese(string value) => value.Any(c => c is >= '\u3400' and <= '\u9fff');
    private static void CheckBothScenes(string raw, string expected)
    {
        var room = new InformationOverlayRoomContent("fixture", "Room", "", 4, "",
            [new("Peer", "Peer", false, "InGame", "", raw, "US")], []);
        var community = new InformationOverlayCommunityContent("fixture", "Community",
            [new("Peer", "Peer", "Member", "InGame", Ship: raw, Location: "", ServerRegion: "US", IsSelf: false)]);
        foreach (var roomMode in new[] { true, false })
        {
            var projected = NativeInformationOverlayRuntime.ProjectSource(roomMode ? room : null,
                roomMode ? null : community, OverlayScenePreference.Auto, "zh");
            Check(projected.Scene.Players.Single().SharedShipDisplayText == expected, "Complete scene projection: " + raw);
        }
    }
    private static void Check(bool result, string message) { if (!result) throw new Exception(message); }
}
