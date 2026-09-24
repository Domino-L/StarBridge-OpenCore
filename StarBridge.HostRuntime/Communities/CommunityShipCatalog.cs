using System.Globalization;
using StarBridge.Core.Ships;
using StarBridge.HostRuntime.Hangar;

namespace StarBridge.HostRuntime.Communities;

/// <summary>Local catalog enrichment only, after the server authorized a shared instance.</summary>
internal static class CommunityShipCatalog
{
    private static readonly Lazy<ShipLoanerCatalog> Matrix = new(() =>
        new(HangarShipNames.Resource("StarBridge.ShipLoanerMatrix.tsv")));
    internal static bool Available => Matrix.Value.Available;

    internal static string DisplayName(ShipPresentation? catalog, string fallback, string culture) =>
        (culture switch {
            "zh-CN" => catalog?.ChineseName,
            "zh-TW" => catalog?.TraditionalChineseName ?? catalog?.ChineseName,
            _ => catalog?.EnglishName
        }) ?? fallback;

    internal static object[]? Loaners(string code, string? status, string culture) =>
        Loaners(code, status, culture, Matrix.Value, HangarShipNames.Lookup);

    internal static object[]? Loaners(string code, string? status, string culture,
        ShipLoanerCatalog matrix, Func<string, ShipPresentation> lookup)
    {
        var concept = status?.ToLowerInvariant() is "concept" or "概念";
        if (!concept) return status?.ToLowerInvariant() is "flyable" or "可飞" or "可飛" ? [] : null;
        var source = lookup(code);
        if (!matrix.Available || source.EnglishName is null) return null;
        return matrix.FindForConceptSource(source.EnglishName).Select(entry =>
        {
            var catalog = ShipLoanerCatalog.FindLoanerCatalog(entry.LoanerEnglishName,
                candidate => { var row = lookup(candidate); return row.EnglishName is null ? null : row; });
            return (object)new {
                code = catalog?.EnglishName ?? entry.LoanerEnglishName,
                displayName = DisplayName(catalog, entry.LoanerEnglishName, culture),
                catalogSpec = catalog?.SizeClass, roleCategory = catalog?.Category, display = catalog?.Display,
                catalogIconKey = catalog?.Display is { } display ? display.IconKey : catalog?.IconKey,
                catalogRole = catalog?.Category, catalogStatus = catalog?.DeliveryStatus,
                catalogPriceUsd = catalog?.PriceUsd?.ToString(CultureInfo.InvariantCulture),
                catalogImageAsset = HangarShipNames.Image(catalog?.ImageKey),
                catalogThumbnailAsset = HangarShipNames.Thumbnail(catalog?.ImageKey)
            };
        }).ToArray();
    }
}
