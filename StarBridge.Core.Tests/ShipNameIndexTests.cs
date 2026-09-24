using StarBridge.Core.Ships;

namespace StarBridge.Core.Tests;

internal static class ShipNameIndexTests
{
    public static void RunAll()
    {
        const string fixture = """
          {"schemaVersion":1,"entries":[
            {"runtimeId":"TEST_A","englishName":"Test Ship","chineseName":"测试舰船","aliases":["Model Mk I","shared"]},
            {"runtimeId":"TEST_B","englishName":"Test Ship II","chineseName":"测试舰船二型","traditionalChineseName":"測試艦船二型","aliases":["Model Mk II","shared"]},
            {"runtimeId":"TEST_C","englishName":"Third Ship","chineseName":"第三型","aliases":["shared"]},
            {"runtimeId":"ANVL_Arrow","englishName":"Arrow","chineseName":"箭矢","aliases":[]}
          ]}
          """;
        var index = ShipNameIndex.Parse(fixture);
        Require(index.Find("  test-ship  ")?.ChineseName == "测试舰船", "Case/spacing/punctuation normalization");
        Require(index.Find("TEST_A")?.ChineseName == "测试舰船", "Exact runtime ID");
        Require(index.Find("Model Mk I")?.RuntimeId == "TEST_A", "First variant");
        Require(index.Find("Model Mk II")?.RuntimeId == "TEST_B", "Second variant");
        Require(index.Find("TEST_B")?.TraditionalChineseName == "測試艦船二型", "Explicit traditional name preserved");
        Require(index.Find("Anvil Arrow")?.RuntimeId == "ANVL_Arrow",
            "Catalog entries receive the original WPF manufacturer aliases.");
        foreach (var unknown in new[] { "shared", "Test Ship Special Edition", "Other Manufacturer Test Ship", "", "TEST_A\n" })
            Require(index.Find(unknown) is null, "Unknown/ambiguous names must not guess a translation");
        foreach (var malformed in new[] { "broken", "{}", fixture.Replace("\"schemaVersion\":1", "\"schemaVersion\":2"), fixture.Replace("TEST_B", "TEST_A") })
            Require(ShipNameIndex.Parse(malformed).Find("Test Ship") is null, "Invalid catalog falls back without blocking scanning");
    }
    private static void Require(bool result, string message) { if (!result) throw new InvalidOperationException(message); }
}
