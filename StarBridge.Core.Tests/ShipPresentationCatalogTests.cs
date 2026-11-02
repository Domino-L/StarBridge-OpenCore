using StarBridge.Core.Ships;

namespace StarBridge.Core.Tests;
internal static class ShipPresentationCatalogTests
{
    private static void ApprovedSharedArtworkDoesNotMergeIdentity()
    {
        const string names = """
        {"schemaVersion":1,"entries":[
          {"runtimeId":"ESPR_Blade","englishName":"Blade","chineseName":"复刻刀锋","aliases":[]},
          {"runtimeId":"VNCL_Blade","englishName":"Blade","chineseName":"原版刀锋","aliases":[]},
          {"runtimeId":"ESPR_Glaive","englishName":"Glaive","chineseName":"复刻长刀","aliases":[]},
          {"runtimeId":"VNCL_Glaive","englishName":"Glaive","chineseName":"原版长刀","aliases":[]},
          {"runtimeId":"ESPR_Stinger","englishName":"Stinger","chineseName":"复刻毒刺","aliases":[]},
          {"runtimeId":"VNCL_Stinger","englishName":"Stinger","chineseName":"原版毒刺","aliases":[]}]}
        """;
        var catalog = new ShipPresentationCatalog(names,
            "规格\t英文飞船名\t中文飞船名\t定位\t隐藏标签\t价格USD\t图片路径\n" +
            "小型\tBlade\t图片目录甲\tCombat\t\t275\tData/ShipImages/test-blade.png\n" +
            "中型\tGlaive\t图片目录乙\tCombat\t\t350\tData/ShipImages/test-glaive.jpg\n" +
            "中型\tStinger\t图片目录丙\tCombat\t\t315\tData/ShipImages/test-stinger.jpg\n");
        foreach (var id in new[] { "ESPR_Blade", "VNCL_Blade", "ESPR_Glaive", "VNCL_Glaive", "ESPR_Stinger", "VNCL_Stinger" })
        {
            var item = catalog.Find(id);
            Require(item.ImageKey == "test-" + id.Split('_')[1].ToLowerInvariant(), "Explicit approved artwork reuse: " + id);
            Require(item.CatalogId is null && item.PriceUsd is null && item.SizeClass is null,
                "Artwork reuse cannot copy catalog identity, price or size");
        }
        Require(catalog.Find("VNCL_Blade_Special").ImageKey is null, "No prefix or special-edition inference");
        Require(new ShipPresentationCatalog(names, null).Find("VNCL_Blade").ImageKey is null, "Absent optional catalog stays absent");
        var displayOnly = new ShipPresentationCatalog(null,
            "规格\t英文飞船名\t中文飞船名\t定位\t隐藏标签\t图片路径\n" +
            "大型\tTyilui\t测试显示\tTransport\t\tData/ShipImages/fixture-tyilui.jpg\n");
        Require(displayOnly.Find("Gatac Tyilui").ImageKey == "fixture-tyilui", "Explicit manufacturer display alias resolves without a runtime identity");
        Require(displayOnly.Find("Gatac Tyilui Special").ImageKey is null, "Display alias does not match future variants");
        Require(catalog.Find("ARGO_ATLS_IKTI").ImageKey is null, "IKTI cannot inherit Akuma artwork");
    }

    private static void ConfirmedRuntimeCatalogAliasesKeepArtwork()
    {
        using var stream = typeof(ShipNameIndex).Assembly.GetManifestResourceStream("StarBridge.ShipNamePack.json")!;
        using var reader = new StreamReader(stream);
        var pairs = new[] { ("CRUS_Starlifter_C2", "C2 Hercules"), ("CRUS_Starlifter_M2", "M2 Hercules"),
            ("CRUS_Star_Runner", "Mercury"), ("CRUS_Starliner", "Genesis"),
            ("RSI_Aurora_CL", "Aurora Mk I CL"), ("RSI_Aurora_ES", "Aurora Mk I ES"),
            ("RSI_Aurora_LN", "Aurora Mk I LN"), ("RSI_Aurora_LX", "Aurora Mk I LX"), ("RSI_Aurora_MR", "Aurora Mk I MR"),
            ("RSI_Scorpius_Interdiction", "Scorpius Antares") };
        var rows = pairs.Select((p, i) => $"大型\t{p.Item2}\t测试显示{i}\tTransport\t\tData/ShipImages/fixture-{i}.jpg\n");
        var catalog = new ShipPresentationCatalog(reader.ReadToEnd(),
            "规格\t英文飞船名\t中文飞船名\t定位\t隐藏标签\t图片路径\n" + string.Concat(rows));
        for (var i = 0; i < pairs.Length; i++)
            Require(catalog.Find(pairs[i].Item1).ImageKey == $"fixture-{i}", "Confirmed exact catalog alias " + pairs[i].Item1);
        Require(catalog.Find("CRUS_Starlifter_2951_BIS").ImageKey is null, "No automatic BIS artwork reuse");
    }

    private static void A2CatalogArtworkResolvesThroughOfficialHangarName()
    {
        using var stream = typeof(ShipNameIndex).Assembly.GetManifestResourceStream("StarBridge.ShipNamePack.json")!;
        using var reader = new StreamReader(stream);
        var catalog = new ShipPresentationCatalog(reader.ReadToEnd(),
            "规格\t英文飞船名\t中文飞船名\t定位\t隐藏标签\t图片路径\n" +
            "大型\tA2 Hercules\t目录显示名\tCombat\t\tData/ShipImages/fixture-a2.jpg\n");
        foreach (var title in new[] { "A2 Hercules", "Hercules Starlifter A2", "Starlifter A2", "CRUS_Starlifter_A2" })
            Require(catalog.Find(title).ImageKey == "fixture-a2", "A2 exact hangar aliases retain catalog artwork: " + title);
        Require(catalog.Find("CRUS_Starlifter_A2_Collector_Military").ImageKey is null,
            "An A2 special variant must not inherit base-model artwork by guessing");
    }

    public static void RunAll()
    {
        ReviewedDisplayDoesNotRewriteOfficialData();
        PublishedCatalogIdentityRetainsArtworkAndNames();
        ManufacturerComesFromExactMetadata();
        SelectedManufacturerDoesNotRewriteRuntimeIdentity();
        NewVariantsRemainDistinctWithoutRuntimeAliases();
        A2CatalogArtworkResolvesThroughOfficialHangarName();
        ConfirmedRuntimeCatalogAliasesKeepArtwork();
        ApprovedSharedArtworkDoesNotMergeIdentity();
        const string header = "规格\t英文飞船名\t中文飞船名\t定位\t隐藏标签\n";
        var catalog = new ShipPresentationCatalog(null, header +
            "小型\tSmall Combat\t小型战斗\tCombat / Heavy Fighter\t\n" +
            "中型\tMedium Combat\t中型战斗\tCombat / Gunship\t\n" +
            "大型\tLarge Combat\t大型战斗\tCombat / Gunship\t\n" +
            "旗舰级\tCapital Combat\t旗舰战斗\tCombat / Frigate\t\n" +
            "大型\tTransport\t运输舰\tTransport / Heavy Freight\t\n" +
            "小型\tVehicle\t载具\tCombat / Ground\tvehicle\n" +
            "未知\tUnclassified\t未知规格\tCombat / Fighter\t\n");
        foreach (var (title, size) in new[] { ("Small Combat", "small"), ("Medium Combat", "medium"),
            ("Large Combat", "large"), ("Capital Combat", "capital") })
            Require(catalog.Find(title).CombatSize == size, "Physical size comes from the explicit size field");
        foreach (var title in new[] { "Transport", "Vehicle", "Unclassified", "Small Combat Special Edition" })
            Require(catalog.Find(title).CombatSize is null, "No combat glyph for noncombat, vehicle, unknown size or unknown variant");
        Require(catalog.Find("Small Combat").ChineseName == "小型战斗", "Exact full catalog name");
        var ambiguous = new ShipPresentationCatalog(null, header +
            "小型\tDuplicated\t甲\tCombat / Fighter\t\n大型\tDuplicated\t乙\tCombat / Fighter\t\n");
        Require(ambiguous.Find("Duplicated").CombatSize is null, "Ambiguous rows fail closed");
        Require(new ShipPresentationCatalog(null, "broken").Find("Small Combat").ChineseName is null, "Invalid data remains optional");
        const string displayHeader = "规格\t英文飞船名\t中文飞船名\t定位\t隐藏标签\t官网状态\t价格USD\t图片路径\n";
        var display = new ShipPresentationCatalog(null, displayHeader +
            "大型\tCargo Test\t货船测试\tTransport / Freight\t\t可飞\t1200.50\tData\\ShipImages\\cargo-test.jpg\n" +
            "小型\tFree Test\t免费测试\tGround / Racing\tvehicle\t概念\t0\tData/ShipImages/free-test.png\n" +
            "中型\tInvalid Test\t未知测试\tFuture\t\tunknown\t-5\tData/ShipImages/../private.png\n");
        var cargo = display.Find("Cargo Test");
        Require(cargo.CatalogId == "catalog-cargotest" && cargo.Category == "transport" &&
            cargo.CombatSize is null && cargo.SizeClass == "large" && cargo.DeliveryStatus == "flyable" &&
            cargo.PriceUsd == 1200.50m && cargo.ImageKey == "cargo-test", "Full display facts are exact and independent of combat glyphs");
        Require(display.Find("Free Test").PriceUsd == 0 && display.Find("Free Test").Category == "utility", "A catalog zero price is known");
        var invalid = display.Find("Invalid Test");
        Require(invalid.PriceUsd is null && invalid.ImageKey is null && invalid.Category is null &&
            invalid.DeliveryStatus is null, "Unsafe paths and unknown facts must stay unknown");
        Require(display.Find("Cargo Test Special").CatalogId is null, "Never use a base model for an unknown variant");
        Require(catalog.Find("Small Combat").IconKey == "combat-small", "Final icon uses exact catalog classification");
        Require(cargo.IconKey == "logistics-large", "Cargo has the approved logistics icon");
        Require(display.Find("Free Test").IconKey is null && catalog.Find("Vehicle").IconKey is null,
            "Ground vehicles never use spacecraft icons");
        Require(catalog.Find("Small Combat Special Edition").IconKey is null, "Unknown variant has no guessed icon");
        foreach (var kind in new[] { "Combat", "Exploration", "Industrial", "Support", "Competition" })
            Require(ShipCatalogIconKey.Resolve(kind, "", "small") == $"{kind.ToLowerInvariant()}-small",
                "All approved named categories resolve without changing the inventory category");
        Require(ShipCatalogIconKey.Resolve("Competition", "", "capital") is null, "No invented racing capital");
        Require(ShipCatalogIconKey.Resolve("Transport / Passenger", "", "large") is null, "Passenger is not cargo");
        Require(ShipCatalogIconKey.Resolve("Utility", "", "small") is null, "Utility is not MPUV or another guessed shape");
        Require(ShipCatalogIconKey.Resolve("Combat", "", null) is null, "Unknown size stays unknown");
        var duplicates = new ShipPresentationCatalog(null, displayHeader +
            "小型\tDuplicate\t甲\tCombat\t\t可飞\t1\t\n" +
            "大型\tDuplicate\t乙\tCombat\t\t可飞\t2\t\n" +
            "小型\tDuplicate\t甲\tCombat\t\t可飞\t1\t\n");
        Require(duplicates.Find("Duplicate").CatalogId is null && duplicates.Find("Duplicate").PriceUsd is null,
            "Later duplicate rows cannot repair an ambiguous match");
        Require(duplicates.Find("catalog-duplicate").CatalogId is null &&
            duplicates.Find("catalog-duplicate").ImageKey is null,
            "Published identifiers cannot repair an ambiguous catalog row");
    }
    private static void ManufacturerComesFromExactMetadata()
    {
        const string header = "规格\t英文飞船名\t中文飞船名\t定位\t隐藏标签\t制造商\n";
        var catalog = new ShipPresentationCatalog(null, header +
            "小型\tNew Variant\t新型号\tCombat\t\tFixture Manufacturer\n");
        Require(catalog.Find("catalog-newvariant").Manufacturer == "Fixture Manufacturer",
            "New models use explicit manufacturer metadata without fabricating a runtime identity");
        Require(catalog.Find("New Variant Special").Manufacturer is null,
            "Unknown variants must not inherit a manufacturer by fuzzy name");
        var names = System.Text.Json.JsonSerializer.Serialize(new { schemaVersion = 1, entries = new[] {
            new { runtimeId = "AEGS_Fixture", englishName = "Fixture Ship", chineseName = "测试船",
                traditionalChineseName = "測試船", aliases = Array.Empty<string>() }
        }});
        var known = new ShipPresentationCatalog(names,
            header + "小型\tFixture Ship\t测试船\tCombat\t\t\n");
        Require(known.Find("catalog-fixtureship").Manufacturer == "Aegis Dynamics" &&
            new ShipPresentationCatalog(names, null).Find("AEGS_Fixture").EnglishName == "Fixture Ship",
            "Existing exact name-pack identities reuse the established manufacturer vocabulary");
    }

    private static void SelectedManufacturerDoesNotRewriteRuntimeIdentity()
    {
        const string names = """
        {"schemaVersion":1,"entries":[
          {"runtimeId":"VNCL_Collector","englishName":"Collector Fighter","chineseName":"收藏战机","aliases":[]},
          {"runtimeId":"VNCL_Enemy","englishName":"Enemy Fighter","chineseName":"敌方战机","aliases":[]}]}
        """;
        const string data = "规格\t英文飞船名\t中文飞船名\t定位\t隐藏标签\t官网状态\t价格USD\t图片路径\t制造商\n" +
            "小型\tCollector Fighter\t收藏战机\tCombat\t\t可飞\t300\tData/ShipImages/collector.jpg\tEsperia\n";
        var catalog = new ShipPresentationCatalog(names, data);
        var runtime = catalog.Find("VNCL_Collector");
        var published = catalog.Find("catalog-collectorfighter", "Collector Fighter");
        Require(runtime.Manufacturer == "Esperia" && published == runtime,
            "Explicit player-model manufacturer wins over the runtime prefix and survives organization publication");
        Require(ShipNameIndex.Parse(names).Find("Collector Fighter")?.RuntimeId == "VNCL_Collector" &&
            runtime.PriceUsd == 300 && runtime.ImageKey == "collector" && runtime.DeliveryStatus == "flyable",
            "Manufacturer presentation keeps the original runtime identity and other catalog facts");
        Require(catalog.Find("VNCL_Enemy").Manufacturer == "Vanduul" &&
            catalog.Find("VNCL_Enemy").CatalogId is null,
            "Player presentation policy must not relabel unrelated enemy identities");
        Require(catalog.Find("Collector Fighter Special").Manufacturer is null,
            "An unreviewed edition cannot inherit the corrected manufacturer by fuzzy matching");
    }

    private static void PublishedCatalogIdentityRetainsArtworkAndNames()
    {
        const string data = "规格\t英文飞船名\t中文飞船名\t定位\t隐藏标签\t图片路径\n" +
            "旗舰级\tTest Frigate\t测试护卫舰\tCombat\t\tData/ShipImages/test-frigate.jpg\n";
        var review = System.Text.Json.JsonSerializer.Serialize(new { schemaVersion = 1, records = new[] {
            new { catalogId = "catalog-testfrigate", englishName = "Test Frigate", chineseName = "测试护卫舰", runtimeId = (string?)null,
                category = "combat", sizeClass = "capital", domain = "spacecraft", iconKey = "combat-capital" }
        }});
        var names = System.Text.Json.JsonSerializer.Serialize(new { schemaVersion = 1, entries = new[] {
            new { runtimeId = "TEST_Frigate", englishName = "Test Frigate", chineseName = "测试护卫舰",
                traditionalChineseName = "測試護衛艦", aliases = Array.Empty<string>() }
        }});
        var catalog = new ShipPresentationCatalog(names, data, review);
        var local = catalog.Find("Test Frigate");
        // Publication sends CatalogId as code. Community reads use this exact
        // two-key lookup; display-review metadata must not hide artwork/names.
        var shared = catalog.Find(local.CatalogId!, "Test Frigate");
        Require(shared.ImageKey == "test-frigate" && shared.ChineseName == "测试护卫舰" && shared == local,
            "Published catalog identity must retain local artwork and localized names on organization readback");
        Require(catalog.Find(local.CatalogId!) == local,
            "Catalog-only lookup must round-trip the same complete presentation");
        Require(shared.TraditionalChineseName == "測試護衛艦",
            "Catalog identity must retain traditional Chinese names as well");
        Require(catalog.Find("catalog-testfrigate-special").CatalogId is null,
            "Unknown catalog variants must not inherit another ship's artwork");
    }

    private static void NewVariantsRemainDistinctWithoutRuntimeAliases()
    {
        const string data = "规格\t英文飞船名\t中文飞船名\t定位\t隐藏标签\t官网状态\t价格USD\n" +
            "小型\tTest Raven\t测试渡鸦\tCombat / Interdiction\t\t可飞\t200\n" +
            "小型\tTest Raven EX\t测试渡鸦EX\tCombat / Medium Fighter\t\t可飞\t185\n" +
            "小型\tTest Akuma\t测试恶魔\tCombat / Ground Mech\tvehicle\t可飞\t50\n";
        var catalog = new ShipPresentationCatalog(null, data);
        var variant = catalog.Find("Test Raven EX");
        Require(variant.CatalogId == "catalog-testravenex" && variant.PriceUsd == 185 &&
            variant.CombatSize == "small" && variant.DeliveryStatus == "flyable",
            "A translated new variant matches independently and uses physical size, not fighter role");
        Require(variant.ChineseName == "测试渡鸦EX" && catalog.Find("测试渡鸦EX") == variant,
            "Reviewed Chinese and English names select the same exact variant");
        Require(catalog.Find("Test Raven").PriceUsd == 200 &&
            catalog.Find("Test Raven").CatalogId != variant.CatalogId,
            "Adding a variant preserves the original model");
        Require(catalog.Find("UNKNOWN_Runtime", "Test Raven EX") == variant &&
            catalog.Find("UNKNOWN_Runtime").CatalogId is null,
            "Exact display-name fallback does not fabricate a runtime alias");
        var mech = catalog.Find("Test Akuma");
        Require(mech.Category == "combat" && mech.PriceUsd == 50 &&
            mech.CombatSize is null && mech.IconKey is null,
            "A combat mech must not inherit a spacecraft silhouette");
    }

    private static void ReviewedDisplayDoesNotRewriteOfficialData()
    {
        const string original = "规格\t英文飞船名\t中文飞船名\t定位\t隐藏标签\t价格USD\n小型\tRover Test\t测试载具\tCombat / Ground\tvehicle\t45\n";
        var entry = new { catalogId = "catalog-rovertest", englishName = "Rover Test", chineseName = "测试载具",
            runtimeId = "TEST_Rover", category = "transport", sizeClass = "medium", domain = "ground", iconKey = "ground-transport-flatbed" };
        string Json(object[] rows) => System.Text.Json.JsonSerializer.Serialize(new { schemaVersion = 1, records = rows });
        var catalog = new ShipPresentationCatalog(null, original, Json([entry]));
        var result = catalog.Find("Rover Test");
        Require(result.Category == "combat" && result.SizeClass == "small" && result.PriceUsd == 45,
            "Reviewed labels do not rewrite original size, business classification or price");
        Require(result.Display == new ShipDisplayReview("transport", "medium", "ground", "ground-transport-flatbed"),
            "Explicit medium vehicle/small artwork exception is preserved as authored");
        Require(catalog.Find("TEST_Rover").Display == result.Display, "Only explicitly vetted runtime IDs join");
        Require(catalog.Find("Rover Test Variant").Display is null, "No fuzzy variant matching");
        Require(catalog.Find("OLD_Unknown_Rover_Code", "Rover Test").Display == result.Display,
            "Legacy unknown codes can display the exact authorized catalog name without adding an alias");
        Require(catalog.Find("OLD_Unknown_Rover_Code").Display is null,
            "Presentation fallback does not teach a new runtime identity");
        Require(catalog.Find("OLD_Unknown_Rover_Code", "Rover Test Variant").Display is null,
            "Unknown variants still never fall back to a base model");
        Require(catalog.Find("catalog-rovertest").Display == result.Display, "Stable catalog identity supported");
        Require(new ShipPresentationCatalog(null, original, Json([entry, entry])).Find("TEST_Rover").Display is null,
            "Duplicate runtime identities stay ambiguous even when labels happen to agree");
        Require(new ShipPresentationCatalog(null, original, "{bad").Find("Rover Test").Display is null,
            "Missing or invalid optional review leaves original catalog usable");
        var deferred = new { catalogId = "catalog-pending", englishName = "Pending", chineseName = "待定",
            runtimeId = (string?)null, category = "multi-role", sizeClass = "small", domain = "spacecraft", iconKey = (string?)null };
        var pending = new ShipPresentationCatalog(null, original, Json([deferred]));
        Require(pending.Find("Pending").Display is { Category: "multi-role", IconKey: null },
            "Deferred multi-role artwork never becomes an unclassified glyph");
        Require(pending.Find("TEST_Pending").Display is null, "Missing identity is not synthesized");
        var sameName = new { catalogId = "catalog-same", englishName = "Same", chineseName = "Same",
            runtimeId = "TEST_Same", category = "transport", sizeClass = "small", domain = "ground", iconKey = "ground-transport-flatbed" };
        var same = new ShipPresentationCatalog(null, null, Json([sameName]));
        Require(same.Find("Same").Display is not null && same.Find("Same").Display == same.Find("TEST_Same").Display,
            "Identical bilingual names within one record are not duplicate ship identities");
        var combatBike = new { catalogId = "catalog-testbike", englishName = "Test Bike", chineseName = "测试摩托",
            runtimeId = "TEST_Bike", category = "combat", sizeClass = "small", domain = "ground", iconKey = "ground-combat-small-gravlev" };
        var bike = new ShipPresentationCatalog(null,
            "规格\t英文飞船名\t中文飞船名\t定位\t隐藏标签\n小型\tTest Bike\t测试摩托\tCompetition / Racing\tvehicle\n", Json([combatBike]));
        Require(bike.Find("Test Bike").Display == new ShipDisplayReview("combat", "small", "ground", "ground-combat-small-gravlev") &&
            bike.Find("测试摩托").Display == bike.Find("TEST_Bike").Display && bike.Find("Test Bike").CombatSize is null,
            "An explicit reviewed combat gravlev overrides presentation without becoming a spacecraft or changing ownership");
    }

    private static void Require(bool result, string message) { if (!result) throw new InvalidOperationException(message); }
}
