// Shared sorting/filtering only; callers must supply an authorized projection.
using System.Globalization;
#if STARBRIDGE_HOST_RUNTIME
using CommunitySharedShip = StarBridge.HostRuntime.Communities.WpfS2SharedShip;
#endif

internal sealed record CommunityShipQuery(string Text = "", string Filter = "all", string Sort = "spec",
    bool Descending = true, string Culture = "zh-CN")
{
    internal bool Valid => Text.Length <= 128 && !Text.Any(char.IsControl) &&
        Filter is "all" or "capital" or "large" or "medium" or "small" or "flyable" or "concept" or "unknown" &&
        Sort is "name" or "spec" or "status" or "price" or "role" or "owner" && Culture is "zh-CN" or "zh-TW" or "en-US";

    // Apply only AFTER the viewer's sharing and identity projection. Counts and search must not reveal hidden fields.
    internal CommunitySharedShip[] Apply(IEnumerable<CommunitySharedShip> source)
    {
        var text = Text.Trim();
        var rows = source.Where(row => Matches(row) && (text.Length == 0 || new[]
            { row.Code, row.DisplayName, row.OwnerGameName, row.OwnerCallsign, row.CatalogSpec,
                row.CatalogRole, row.CatalogStatus, row.CatalogPriceUsd }
            .Any(value => value?.Contains(text, StringComparison.OrdinalIgnoreCase) == true)));
        var comparer = StringComparer.Create(CultureInfo.GetCultureInfo(Culture), true);
        IOrderedEnumerable<CommunitySharedShip> ordered = Sort switch
        {
            "price" => Descending
                ? rows.OrderByDescending(row => Price(row) ?? -1m)
                : rows.OrderBy(row => Price(row) ?? decimal.MaxValue),
            "spec" => rows.OrderBy(row => SpecRank(row.CatalogSpec, Descending)),
            "status" => rows.OrderBy(row => StatusRank(row.CatalogStatus, Descending)),
            _ => OrderText(rows, row => Sort switch
                { "name" => row.DisplayName, "role" => row.CatalogRole, _ => Owner(row) }, comparer)
        };
        return ordered.ThenBy(row => row.DisplayName, comparer).ThenBy(row => row.Code, comparer)
            .ThenBy(row => row.Id, StringComparer.Ordinal).ToArray();
    }

    private IOrderedEnumerable<CommunitySharedShip> OrderText(IEnumerable<CommunitySharedShip> rows,
        Func<CommunitySharedShip, string?> selector, StringComparer comparer) => Descending
        ? rows.OrderBy(row => string.IsNullOrWhiteSpace(selector(row))).ThenByDescending(selector, comparer)
        : rows.OrderBy(row => string.IsNullOrWhiteSpace(selector(row))).ThenBy(selector, comparer);
    private bool Matches(CommunitySharedShip row) => Filter switch
    {
        "capital" => Equal(row.CatalogSpec, "旗舰级"), "large" => Equal(row.CatalogSpec, "大型"),
        "medium" => Equal(row.CatalogSpec, "中型"), "small" => Equal(row.CatalogSpec, "小型"),
        "flyable" => Equal(row.CatalogStatus, "可飞") || Equal(row.CatalogStatus, "Flyable"),
        "concept" => Contains(row.CatalogStatus, "概念") || Contains(row.CatalogStatus, "Concept"),
        "unknown" => string.IsNullOrWhiteSpace(row.CatalogSpec) || Equal(row.CatalogSpec, "待分类") ||
            string.IsNullOrWhiteSpace(row.CatalogRole) || Price(row) is null ||
            string.IsNullOrWhiteSpace(row.CatalogStatus) || Contains(row.CatalogStatus, "未知") || Contains(row.CatalogStatus, "unknown"),
        _ => true
    };
    internal static decimal? Price(CommunitySharedShip row) =>
        decimal.TryParse(row.CatalogPriceUsd?.Replace("$", "").Trim(), NumberStyles.Number, CultureInfo.InvariantCulture, out var value)
            && value >= 0 ? value : null;
    private static string Owner(CommunitySharedShip row) => string.IsNullOrWhiteSpace(row.OwnerCallsign)
        ? row.OwnerGameName : row.OwnerCallsign;
    private static bool Equal(string? value, string other) => value?.Trim().Equals(other, StringComparison.OrdinalIgnoreCase) == true;
    private static bool Contains(string? value, string other) => value?.Contains(other, StringComparison.OrdinalIgnoreCase) == true;
    private static int SpecRank(string? spec, bool descending)
    {
        var rank = spec?.Trim() switch { "旗舰级" => 0, "大型" => 1, "中型" => 2, "小型" => 3, _ => 4 };
        return descending || rank == 4 ? rank : 3 - rank;
    }
    private static int StatusRank(string? status, bool conceptFirst) =>
        Equal(status, "概念") || Equal(status, "Concept") ? conceptFirst ? 0 : 1 :
        Equal(status, "可飞") || Equal(status, "Flyable") ? conceptFirst ? 1 : 0 : 2;
}
