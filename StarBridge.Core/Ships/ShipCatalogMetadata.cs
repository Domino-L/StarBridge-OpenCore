using System.Globalization;

namespace StarBridge.Core.Ships;

/// <summary>Fills missing display facts from an already resolved exact model. Never resolves ownership or identity.</summary>
public sealed record ShipCatalogMetadata(string? Spec, string? Role, string? Status, string? PriceUsd,
    string? RoleCategory = null)
{
    public ShipCatalogMetadata FillMissing(ShipPresentation catalog) => new(
        Fill(Spec, catalog.SizeClass switch {
            "capital" => "旗舰级", "large" => "大型", "medium" => "中型", "small" => "小型", _ => catalog.SizeClass }),
        Fill(Role, catalog.Category),
        Fill(Status, catalog.DeliveryStatus switch { "flyable" => "可飞", "concept" => "概念", _ => catalog.DeliveryStatus }),
        ValidPrice(PriceUsd) ? PriceUsd : catalog.PriceUsd?.ToString(CultureInfo.InvariantCulture) ?? PriceUsd,
        Fill(RoleCategory, catalog.Category));

    private static string? Fill(string? value, string? fallback) =>
        Missing(value) && !Missing(fallback) ? fallback : value;

    private static bool Missing(string? value) => value?.Trim().ToLowerInvariant() is
        null or "" or "unknown" or "未知" or "未公布" or "未公佈" or "未发布" or "未發布" or
        "待分类" or "待分類" or "未分类" or "未分類" or "暂无数据" or "暫無資料" or
        "n/a" or "tbd" or "unpublished" or "not published" or "-" or "--" or "—";

    private static bool ValidPrice(string? value)
    {
        // Match the existing USD presentation contract, including a trailing USD label.
        var text = value?.Trim();
        if (text?.StartsWith('$') == true) text = text[1..].TrimStart();
        if (text?.EndsWith("USD", StringComparison.OrdinalIgnoreCase) == true) text = text[..^3].TrimEnd();
        return decimal.TryParse(text, NumberStyles.Float | NumberStyles.AllowThousands,
            CultureInfo.InvariantCulture, out var amount) && amount is >= 0 and <= 1_000_000_000m;
    }
}
