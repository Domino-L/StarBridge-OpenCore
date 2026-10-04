using System.Text;
using StarBridge.HostRuntime.Presence;

internal static class LocationDisplayCompatibilityTests
{
    internal static Task Run()
    {
        const string catalog = """
        {"schemaVersion":1,"entries":[
          {"canonicalCode":"Station","nameEn":"Station Name","nameZh":"原始空间站"},
          {"canonicalCode":"Point","nameEn":"L1 Point","nameZh":"参照点"},
          {"canonicalCode":"Area18","nameEn":"Area18","nameZh":"区域"},
          {"canonicalCode":"QV","nameEn":"QV Logistics","nameZh":"旧物流站"}],
         "aliases":[{"code":"LOC_route","normalizedCode":"route","canonicalCode":"Point","nameEn":"L1 Point","nameZh":"参照点"}]}
        """;
        static MemoryStream Stream(string text) => new(Encoding.UTF8.GetBytes(text));
        using var original = Stream(catalog);
        using var missing = Stream(catalog);
        using var compatibility = Stream("# optional field-confirmed display names\nStation=已确认空间站\nroute=导航空间站\nField_LOC=现场别名\nArea18=18区\nQV=QV物流空间站\n");
        var full = GameLogLocationNameIndex.Load(original, compatibility);
        var fallback = GameLogLocationNameIndex.Load(missing);
        Check(full.Find("Station") is { EnglishName: "Station Name", ChineseName: "已确认空间站" }, "Chinese override must leave English name untouched");
        Check(full.Find("LOC_route [123]") is { EnglishName: "L1 Point", ChineseName: "导航空间站" }, "exact route override precedes canonical fallback with prefix/instance normalization");
        Check(full.Find("Point")?.ChineseName == "参照点", "route display pairing cannot merge or replace the independently confirmed location");
        Check(full.Find("Field_LOC") is { EnglishName: "Field_LOC", ChineseName: "现场别名" }, "explicit old field alias has no invented canonical/English identity");
        Check(full.Find("Area18")?.ChineseName == "18区" && full.Find("QV")?.ChineseName == "QV物流空间站", "model/numeric labels survive compatibility parsing");
        Check(fallback.Find("Station")?.ChineseName == "原始空间站" && fallback.Find("Field_LOC") is null, "public/missing optional data preserves the original catalog safely");
        Check(GameLogLocationNameIndex.Load(null).Find("Station") is null, "missing base data remains a supported empty index");
        Check(full.Find("unobserved_route") is null, "no fuzzy or synthetic location pairing");
        return Task.CompletedTask;
    }
    internal static void CheckResource(bool expected)
    {
        var present = typeof(GameLogRuntime).Assembly.GetManifestResourceNames().Contains("StarBridge.LocationCompatibilityNames.txt");
        Check(present == expected, "restricted compatibility names follow the actual build flag, expected=" + expected + ", actual=" + present);
        if (expected)
        {
            var actual = GameLogLocationNameIndex.Load();
            Check(actual.Find("rs_ext_pyro2_l4")?.ChineseName == "死局空间站" && actual.Find("NewBabbage_LOC")?.ChineseName == "新巴贝奇",
                "actual private Host load consumes the embedded compatibility resource");
            Check(actual.Find("LOC_rs_ext_pyro3_l1") is { ChineseName: "星光服务站", EnglishName: "Starlight Service Station" } &&
                actual.Find("RR_P3_L1") is { ChineseName: "星光服务站", EnglishName: "Starlight Service Station" },
                "actual Host pairs station display names without altering location state");
        }
        Console.WriteLine("PASS restricted location compatibility resource presence=" + present);
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
