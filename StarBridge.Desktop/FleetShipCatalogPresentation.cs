namespace StarBridge.Desktop;

internal sealed record FleetShipCatalogPresentation(
    string Spec,
    string Role,
    string RawRole,
    string Status,
    string Price);

internal static class FleetShipCatalogProjection
{
    public static FleetShipCatalogPresentation Resolve(
        NetworkFleetShipSnapshot ship,
        ShipCatalogEntry? localCatalog,
        string language)
    {
        if (ship.CatalogStatus is not null)
        {
            var rawRole = ship.CatalogRole?.Trim() ?? "";
            return new FleetShipCatalogPresentation(
                DisplayOrFallback(ship.CatalogSpec, "待分类"),
                language.Equals("zh", StringComparison.OrdinalIgnoreCase)
                    ? ShipRoleLocalizer.DisplayName(rawRole)
                    : rawRole,
                rawRole,
                ShipCatalog.ResolveStatusValue(ship.CatalogStatus),
                FormatPrice(ship.CatalogPriceUsd));
        }

        var localRole = localCatalog?.Role ?? "";
        return new FleetShipCatalogPresentation(
            DisplayOrFallback(localCatalog?.Spec, "待分类"),
            localCatalog?.RoleDisplay(language) ?? "",
            localRole,
            ShipCatalog.ResolveStatus(localCatalog),
            localCatalog?.PriceDisplay ?? "未公布");
    }

    public static NetworkFleetShipSnapshot InheritAuthoritativeMetadata(
        NetworkFleetShipSnapshot ship,
        NetworkFleetShipSnapshot fallback)
    {
        if (ship.CatalogStatus is not null || fallback.CatalogStatus is null)
        {
            return ship;
        }

        return ship with
        {
            CatalogSpec = fallback.CatalogSpec,
            CatalogRole = fallback.CatalogRole,
            CatalogStatus = fallback.CatalogStatus,
            CatalogPriceUsd = fallback.CatalogPriceUsd
        };
    }

    private static string DisplayOrFallback(string? value, string fallback) =>
        string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();

    private static string FormatPrice(string? value)
    {
        var price = value?.Trim() ?? "";
        if (string.IsNullOrWhiteSpace(price))
        {
            return "未公布";
        }

        return price.StartsWith('$') ? price : $"${price}";
    }
}
