using StarBridge.Core.Ships;

namespace StarBridge.HostRuntime.Hangar;

internal static class HangarShipNames
{
    private static readonly Lazy<ShipPresentationCatalog> Catalog = new(() => new(
        Resource("StarBridge.ShipNamePack.json"), Resource("StarBridge.ShipDisplayCatalog.tsv"),
        Resource("StarBridge.ShipDisplayReview.json")));
    private static readonly Lazy<ShipBundledMediaCatalog> Media = new(() => new(
        Resource("StarBridge.ShipMedia.json"),
        Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "data", "flutter_assets", "assets", "ships"))));

    internal static ShipPresentation Lookup(string title) => Catalog.Value.Find(title);
    internal static ShipPresentation Lookup(string code, string displayName) => Catalog.Value.Find(code, displayName);
    internal static string? Image(string? key) => Media.Value.Find(key);
    internal static string? Thumbnail(string? key) => Media.Value.FindThumbnail(key);

    internal static string? Resource(string name)
    {
        using var stream = typeof(HangarShipNames).Assembly.GetManifestResourceStream(name);
        if (stream is null) return null;
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }

    public static object Present(string title, string? liner, int ordinal)
    {
        var name = Catalog.Value.Find(title);
        return new { title, liner, rowId = $"ship-{ordinal}",
            catalogId = name.CatalogId, category = name.Category, sizeClass = name.SizeClass,
            display = name.Display, deliveryStatus = name.DeliveryStatus, priceUsd = name.PriceUsd,
            combatSize = name.CombatSize, names = new {
            zhHans = name.ChineseName, zhHant = name.TraditionalChineseName
        }};
    }

    public static object PresentSaved(LocalHangarShip ship)
    {
        var name = Catalog.Value.Find(ship.Title);
        return new { id = ship.Id, title = ship.Title, liner = ship.Liner, addedAt = ship.AddedAt, removedAt = ship.RemovedAt,
            catalogId = name.CatalogId, category = name.Category, sizeClass = name.SizeClass, display = name.Display,
            deliveryStatus = name.DeliveryStatus, priceUsd = name.PriceUsd, imageAsset = Media.Value.Find(name.ImageKey),
            thumbnailAsset = Media.Value.FindThumbnail(name.ImageKey),
            combatSize = name.CombatSize, names = new {
                zhHans = name.ChineseName, zhHant = name.TraditionalChineseName
            }};
    }

    internal static object PresentProfile(StarBridge.Core.Profiles.PersonalProfileHangarShipContract ship)
    {
        var name = Lookup(ship.Code);
        if (name.CatalogId is null) name = Lookup(ship.DisplayName);
        return new { ship.Code, ship.DisplayName, ship.ImportedAt, ship.SyncedAt,
            roleCategory = name.Category ?? ship.RoleCategory,
            presentation = new { title = name.EnglishName ?? ship.DisplayName, display = name.Display,
                catalogId = name.CatalogId,
                cn = name.ChineseName, tw = name.TraditionalChineseName,
                category = name.Category, sizeClass = name.SizeClass, deliveryStatus = name.DeliveryStatus, priceUsd = name.PriceUsd,
                imageAsset = Image(name.ImageKey), thumbnailAsset = Thumbnail(name.ImageKey) } };
    }
}
