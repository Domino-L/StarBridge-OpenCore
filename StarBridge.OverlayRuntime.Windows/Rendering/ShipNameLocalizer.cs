namespace StarBridge.Desktop;

public static class ShipNameLocalizer
{
    private static readonly Lazy<ShipNameCatalogSnapshot> Catalog =
        new(() => ShipNameCatalog.Load(AppContext.BaseDirectory));

    public static string DisplayName(string? shipCode, string language)
    {
        if (StarBridge.HostRuntime.Presence.GameShipNames.Find(shipCode) is { } name)
            return language.StartsWith("zh", StringComparison.OrdinalIgnoreCase)
                ? (language.Equals("zh-Hant", StringComparison.OrdinalIgnoreCase) ? name.TraditionalChineseName : null)
                    ?? (string.IsNullOrWhiteSpace(name.ChineseName) ? name.EnglishName : name.ChineseName)
                : name.EnglishName;
        return Catalog.Value.DisplayName(shipCode, language);
    }

    public static IReadOnlyDictionary<string, string> KnownChineseNames =>
        Catalog.Value.ChineseNames;

    public static IReadOnlyCollection<string> KnownShipCodes =>
        Catalog.Value.KnownCodes;

    public static string ResolveCode(string? shipCodeOrName)
    {
        if (StarBridge.HostRuntime.Presence.GameShipNames.Find(shipCodeOrName)?.RuntimeId is { } id) return id;
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
