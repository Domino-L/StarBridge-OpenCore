using StarBridge.Core.Ships;

namespace StarBridge.Core.Tests;

internal static class ShipCatalogMetadataTests
{
    internal static void RunAll()
    {
        var catalog = new ShipPresentationCatalog(null,
            "规格\t英文飞船名\t中文飞船名\t定位\t官网状态\t价格USD\t隐藏标签\n" +
            "小型\tRecovery Test\t回填测试\tCombat\t可飞\t50\t\n" +
            "大型\tConcept Test\t概念测试\tTransport\t概念\t\t\n");
        var model = catalog.Find("catalog-recoverytest");
        foreach (var placeholder in new string?[] { null, "", "  ", "unknown", " UNKNOWN ", "未知", "未公布", "未公佈", "待分类", "n/a", "—" })
        {
            var result = new ShipCatalogMetadata(placeholder, placeholder, placeholder, placeholder, placeholder).FillMissing(model);
            Require(result == new ShipCatalogMetadata("小型", "combat", "可飞", "50", "combat"),
                "Every missing field is recovered independently: " + placeholder);
        }
        var partial = new ShipCatalogMetadata("大型", "运输", "可飞", null, "Transport").FillMissing(model);
        Require(partial == new ShipCatalogMetadata("大型", "运输", "可飞", "50", "Transport"),
            "A known status must not prevent recovery of an unpublished price");
        foreach (var price in new[] { "0", "$0", "700", "$1,234.50", "700 USD", "$ 700 usd", "7e2" })
        {
            var known = new ShipCatalogMetadata("大型", "运输", "概念", price, "Transport");
            Require(known.FillMissing(model) == known, "Known remote facts, including zero, remain authoritative");
        }
        foreach (var price in new[] { "-1", "not-a-price", "未公布", "1,000,000,001", "700$" })
            Require(new ShipCatalogMetadata(null, null, null, price).FillMissing(model).PriceUsd == "50", "Invalid price can use exact catalog");
        var unknown = new ShipCatalogMetadata("未知", null, "unknown", null);
        Require(unknown.FillMissing(catalog.Find("Recovery Test EX")) == unknown, "An unknown variant cannot inherit base model facts");
        var concept = new ShipCatalogMetadata(null, null, "未知", null).FillMissing(catalog.Find("Concept Test"));
        Require(concept.Status == "概念" && concept.PriceUsd is null, "Concept remains concept; a genuinely unpublished price stays missing");
        Require(new ShipCatalogMetadata(null, null, null, null).FillMissing(new(null, null, null)).PriceUsd is null,
            "Missing optional catalog never becomes zero");
    }

    private static void Require(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
