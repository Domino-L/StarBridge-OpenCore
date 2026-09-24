namespace StarBridge.Desktop;

public static class ShipNameLocalizer
{
    private static readonly Lazy<ShipNameCatalogSnapshot> Catalog =
        new(() => ShipNameCatalog.Load(AppContext.BaseDirectory));

    public static string DisplayName(string? shipCode, string language)
    {
        return Catalog.Value.DisplayName(shipCode, language);
    }

    public static IReadOnlyDictionary<string, string> KnownChineseNames =>
        Catalog.Value.ChineseNames;

    public static IReadOnlyCollection<string> KnownShipCodes =>
        Catalog.Value.KnownCodes;

    public static string ResolveCode(string? shipCodeOrName)
    {
        return Catalog.Value.ResolveCode(shipCodeOrName);
    }

    public static IReadOnlyList<string> GetNameAliases(string? shipCode)
    {
        return Catalog.Value.GetNameAliases(shipCode);
    }

    public static string NormalizeCode(string? shipCode)
    {
        return ShipNameCatalog.NormalizeCode(shipCode);
    }
}
