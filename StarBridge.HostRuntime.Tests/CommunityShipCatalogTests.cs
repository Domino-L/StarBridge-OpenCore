using System.Text.Json;
using StarBridge.Core.Ships;
using StarBridge.HostRuntime.Communities;

namespace StarBridge.HostRuntime.Tests;
internal static class CommunityShipCatalogTests
{
    internal static void Verify()
    {
        var names = new ShipPresentation("测试舰船", "測試艦船", null, EnglishName: "Test Ship");
        Check(CommunityShipCatalog.DisplayName(names, "original", "zh-CN") == "测试舰船" &&
            CommunityShipCatalog.DisplayName(names, "original", "zh-TW") == "測試艦船" &&
            CommunityShipCatalog.DisplayName(names, "original", "en-US") == "Test Ship" &&
            CommunityShipCatalog.DisplayName(null, "Unlisted Variant", "zh-CN") == "Unlisted Variant",
            "Organization names follow language and keep unknown variants unchanged");
        var bundled = StarBridge.HostRuntime.Hangar.HangarShipNames.Resource("StarBridge.ShipLoanerMatrix.tsv");
        if (bundled is not null) Check(new ShipLoanerCatalog(bundled).Available, "existing private WPF matrix is recognized including comment header");
        var matrix = new ShipLoanerCatalog("源英文飞船名\t中文\t规格\t替代\t规则\t标签\n" +
            "Source Test\t测试\t大型\tArgo Replacement Test\tOnlyWhenSourceIsConcept\t\n");
        ShipPresentation Lookup(string value) => value switch {
            "source-code" => new("源船", "源船", null, EnglishName: "Source Test"),
            "Replacement Test" => new("替代测试", "替代測試", null, Category: "transport",
                SizeClass: "large", DeliveryStatus: "flyable", PriceUsd: 100, EnglishName: "Replacement Test"),
            _ => new(null, null, null)
        };
        var rows = CommunityShipCatalog.Loaners("source-code", "Concept", "zh-TW", matrix, Lookup)!;
        var json = JsonSerializer.SerializeToElement(rows);
        Check(json.GetArrayLength() == 1 && json[0].GetProperty("displayName").GetString() == "替代測試", "local matrix and exact catalog alias");
        Check(json[0].GetProperty("catalogStatus").GetString() == "flyable", "catalog status not invented");
        Check(!json[0].TryGetProperty("ownerMemberRef", out _) && !json[0].TryGetProperty("shipRef", out _), "no synthetic owned instance or authority");
        Check(CommunityShipCatalog.Loaners("source-code", "Flyable", "en-US", matrix, Lookup)!.Length == 0, "flyable source hides concept-only loaners");
        Check(CommunityShipCatalog.Loaners("source-code", "Concept", "en-US", new(null), Lookup) is null, "missing optional matrix is unknown");
        Check(CommunityShipCatalog.Loaners("unknown", "Concept", "en-US", matrix, Lookup) is null, "unknown source is not guessed");
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
