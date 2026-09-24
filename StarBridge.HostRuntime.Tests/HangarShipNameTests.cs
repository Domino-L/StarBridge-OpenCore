using System.Text.Json.Nodes;

internal static class HangarShipNameTests
{
    public static Task FullRsiTitles()
    {
        using var resource = System.Reflection.Assembly.Load("StarBridge.HostRuntime").GetManifestResourceStream("StarBridge.ShipDisplayCatalog.tsv");
        var fullCatalog = resource is not null;
        string?[] combatSizes = ["small", "small", "capital", null, "large", null];
        var examples = new[] {
            ("F7C-M Super Hornet Mk II", "大黄蜂"),
            ("F8C Lightning", "闪电"),
            ("Idris-P Frigate", "伊德里斯"),
            ("Dragonfly Black", "蜻蜓"),
            ("Ironclad Assault", "铁甲"),
            ("Nox", "NOX")
        };
        using var test = new HangarLockedScanTests.Harness();
        test.Send("verify", test.Initial());
        var observed = 0;
        foreach (var (page, doc) in new[] { (1, 1), (1, 1), (2, 2), (2, 2), (1, 3), (1, 3) })
        {
            var body = test.Page(page, doc);
            body["observation"]!["page"]!["pledges"]![0]!["items"] = new JsonArray(
                examples.Select(pair => (JsonNode)new JsonObject {
                    ["title"] = pair.Item1, ["kind"] = "Ship"
                }).ToArray());
            var response = test.Send("observe", body);
            if (response.Error is not null) throw new Exception("Presentation scan unexpectedly rejected");
            var ships = response.Payload.GetProperty("ships");
            if (ships.GetArrayLength() == 0) continue;
            observed++;
            for (var index = 0; index < examples.Length; index++)
            {
                var ship = ships[index];
                var translated = ship.GetProperty("names").TryGetProperty("zhHans", out var name) ? name.GetString() : null;
                if (!fullCatalog && examples[index].Item1 == "Dragonfly Black")
                {
                    if (translated is not null) throw new Exception("Absent optional full catalog must not invent a translation");
                    continue;
                }
                if (ship.GetProperty("title").GetString() != examples[index].Item1 ||
                    translated?.Contains(examples[index].Item2, StringComparison.OrdinalIgnoreCase) != true)
                    throw new Exception($"Missing Chinese model name: {examples[index].Item1} -> {translated ?? "(none)"}");
                var combatSize = ship.TryGetProperty("combatSize", out var size) ? size.GetString() : null;
                if (combatSize != (fullCatalog ? combatSizes[index] : null))
                    throw new Exception($"Wrong combat size for {examples[index].Item1}: {combatSize}");
                if (ship.GetProperty("rowId").GetString() != $"ship-{index}") throw new Exception("Unstable scan row identity");
            }
        }
        if (observed == 0) throw new Exception("No scan results exercised");
        if (fullCatalog)
        {
            using var reader = new StreamReader(resource!);
            var tsv = reader.ReadToEnd();
            var catalog = new StarBridge.Core.Ships.ShipPresentationCatalog(null, tsv);
            var rows = tsv.Split('\n').Skip(1).Where(line => !string.IsNullOrWhiteSpace(line)).ToArray();
            if (rows.Length < 200) throw new Exception("Original catalog unexpectedly incomplete");
            foreach (var row in rows)
                if (string.IsNullOrWhiteSpace(catalog.Find(row.Split('\t')[1]).ChineseName))
                    throw new Exception($"Original catalog name not covered: {row.Split('\t')[1]}");
            Console.WriteLine($"PASS Original catalog display coverage {rows.Length}/{rows.Length}");
        }
        Console.WriteLine($"PASS Full RSI title projection; optional catalog={fullCatalog}");
        return Task.CompletedTask;
    }

    public static Task Verify()
    {
        // The live reader and saved inventory must expose the same exact catalog
        // presentation, including the optional reviewed category/icon overlay.
        foreach (var title in new[] { "Vulture", "Nox", "Unknown Test Ship" })
        {
            var scan = System.Text.Json.JsonSerializer.SerializeToElement(
                StarBridge.HostRuntime.Hangar.HangarShipNames.Present(title, "Fixture", 0));
            var expected = StarBridge.HostRuntime.Hangar.HangarShipNames.Lookup(title);
            if (!scan.TryGetProperty("display", out var display) ||
                display.GetRawText() != System.Text.Json.JsonSerializer.Serialize(expected.Display) ||
                !scan.TryGetProperty("catalogId", out var catalogId) ||
                catalogId.GetString() != expected.CatalogId)
                throw new Exception("Live scan omitted the saved hangar's exact catalog presentation");
        }
        using var test = new HangarLockedScanTests.Harness();
        test.Send("verify", test.Initial());
        JsonObject Page(int page, int doc) {
            var body = test.Page(page, doc);
            body["observation"]!["page"]!["pledges"]![0]!["items"] = new JsonArray(
                new JsonObject { ["title"] = "Carrack", ["kind"] = "Ship", ["liner"] = "Anvil" },
                new JsonObject { ["title"] = "Vulture", ["kind"] = "Ship", ["liner"] = "Drake" },
                new JsonObject { ["title"] = "F7C-M Mk II", ["kind"] = "Ship" },
                new JsonObject { ["title"] = "Unknown Test Ship", ["kind"] = "Ship" });
            return body;
        }
        foreach (var (page, doc) in new[] { (1, 1), (1, 1), (2, 2), (2, 2), (1, 3), (1, 3) }) {
            var response = test.Send("observe", Page(page, doc));
            if (response.Error is not null) throw new Exception("Localized preview rejected a valid scan");
            var ships = response.Payload.GetProperty("ships");
            if (ships.GetArrayLength() == 0) continue;
            if (ships[0].GetProperty("title").GetString() != "Carrack" ||
                ships[0].GetProperty("names").GetProperty("zhHans").GetString() != "克拉克" ||
                ships[1].GetProperty("names").GetProperty("zhHans").GetString() != "秃鹫" ||
                ships[2].GetProperty("names").GetProperty("zhHans").GetString() != "F7C-M 超级大黄蜂 MK II" ||
                ships[3].GetProperty("names").TryGetProperty("zhHans", out var unknown) &&
                    unknown.ValueKind != System.Text.Json.JsonValueKind.Null)
                throw new Exception("Bundled name pack must translate known models, preserve originals and leave unknowns untranslated");
            if (response.Payload.GetProperty("canSave").GetBoolean()) throw new Exception("Translation must not grant save permission");
        }
        return Task.CompletedTask;
    }
}
