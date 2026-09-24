namespace StarBridge.HostRuntime.Hangar;

internal sealed record CommunityPublishedShip(string Id, string Code, string DisplayName, DateTimeOffset AddedAt);
internal static class CommunityHangarPublication
{
    internal static CommunityPublishedShip[] Build(LocalHangarSnapshot snapshot)
    {
        if (snapshot.Revision < 1 || snapshot.SavedAt is null || snapshot.Partial)
            throw new LocalHangarStoreException("hangar.complete_scan_required", "A saved complete hangar is required.");
        return snapshot.Ships.Select(ship => new CommunityPublishedShip(ship.Id,
            HangarShipNames.Lookup(ship.Title).CatalogId ?? ship.Title, ship.Title, ship.AddedAt)).ToArray();
    }
}
