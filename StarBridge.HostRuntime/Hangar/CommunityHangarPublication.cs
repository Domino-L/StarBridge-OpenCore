namespace StarBridge.HostRuntime.Hangar;

internal sealed record CommunityPublishedShip(string Id, string Code, string DisplayName, DateTimeOffset AddedAt,
    [property: System.Text.Json.Serialization.JsonIgnore(Condition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull)] string? ImageMediaId = null);
internal static class CommunityHangarPublication
{
    internal static CommunityPublishedShip[] Build(LocalHangarSnapshot snapshot)
    {
        if (snapshot.Revision < 1 || snapshot.SavedAt is null || snapshot.Partial)
            throw new LocalHangarStoreException("hangar.complete_scan_required", "A saved complete hangar is required.");
        return snapshot.Ships.Select(ship => new CommunityPublishedShip(ship.Id,
            HangarShipNames.Lookup(ship.Title).CatalogId ?? ship.Title, ship.Title, ship.AddedAt)).ToArray();
    }

    // Only explicitly approved upload receipts belong here, never the whole media
    // catalog: an older remote image must not silently reappear after local restore.
    internal static CommunityPublishedShip[] WithImages(LocalHangarSnapshot snapshot, string owner,
        IReadOnlyList<StarBridge.Core.ShipMedia.ShipMediaSummaryContract> approvedImages)
    {
        var ships = Build(snapshot);
        if (string.IsNullOrWhiteSpace(owner) || approvedImages.Select(row => row.ShipInstanceId).Distinct(StringComparer.Ordinal).Count() != approvedImages.Count)
            throw new LocalHangarStoreException("hangar.image_not_allowed", "Ambiguous image publication.");
        var images = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var image in approvedImages)
        {
            var ship = ships.SingleOrDefault(row => row.Id == image.ShipInstanceId);
            if (image.OwnerAccountId != owner || ship is null || ship.Code != image.ShipCode ||
                !Guid.TryParseExact(image.MediaId, "N", out _) && !Guid.TryParseExact(image.MediaId, "D", out _))
                throw new LocalHangarStoreException("hangar.image_not_allowed", "Image does not belong to this publication.");
            images.Add(ship.Id, image.MediaId);
        }
        return ships.Select(ship => images.TryGetValue(ship.Id, out var id) ? ship with { ImageMediaId = id } : ship).ToArray();
    }
}
