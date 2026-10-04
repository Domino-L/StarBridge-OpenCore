using System.Text;
using StarBridge.HostRuntime.Presence;

internal static class GameLogLocationCatalogTests
{
    internal static bool HasPack => typeof(GameLogRuntime).Assembly
        .GetManifestResourceNames().Contains("StarBridge.LocationCatalog.json");

    internal static Task SyntheticAndAbsentCatalog()
    {
        const string json = """
            {"schemaVersion":1,"entries":[
              {"canonicalCode":"Synthetic_Test_Port","nameEn":"Test Port","nameZh":"测试港"}
            ]}
            """;
        using var input = new MemoryStream(Encoding.UTF8.GetBytes(json));
        var index = GameLogLocationNameIndex.Load(input);
        if (index.FindDisplay("Test Port") is not { ChineseName: "测试港" } || index.Find("Test Port") is not null)
            throw new Exception("Shared display names localize without broadening log identity parsing.");
        using var ambiguous = new MemoryStream(Encoding.UTF8.GetBytes("""
            {"schemaVersion":1,"entries":[
              {"canonicalCode":"A","nameEn":"Same Port","nameZh":"甲"},
              {"canonicalCode":"B","nameEn":"Same Port","nameZh":"乙"}
            ]}
            """));
        if (GameLogLocationNameIndex.Load(ambiguous).FindDisplay("Same Port") is not null)
            throw new Exception("Ambiguous display names must retain the original label.");
        if (index.Find("LOC_Synthetic_Test_Port [42]") is not { EnglishName: "Test Port", ChineseName: "测试港" })
            throw new Exception("Synthetic catalog must exercise real normalization and localization.");
        if (index.Find("Unmapped_Test_Port") is not null ||
            GameLogLocationNameIndex.Load(null).Find("Synthetic_Test_Port") is not null)
            throw new Exception("Missing entries or optional catalog must remain unknown.");
        using var invalid = new MemoryStream(Encoding.UTF8.GetBytes("{invalid"));
        if (GameLogLocationNameIndex.Load(invalid).Find("Synthetic_Test_Port") is not null)
            throw new Exception("Invalid catalog must not fabricate a location.");
        return Task.CompletedTask;
    }
}
