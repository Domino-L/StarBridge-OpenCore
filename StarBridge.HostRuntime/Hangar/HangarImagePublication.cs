using StarBridge.Core.ShipMedia;

namespace StarBridge.HostRuntime.Hangar;

internal static partial class HangarImagePublication
{
    internal static async Task<CommunityPublishedShip[]> PrepareAsync(LocalHangarSnapshot snapshot, string owner,
        Func<string, string?> readImage, Func<ShipMediaUploadRequestContract, CancellationToken, Task<ShipMediaSummaryContract>> upload,
        Action current, CancellationToken token)
    {
        var ships = CommunityHangarPublication.Build(snapshot);
        var requests = new List<ShipMediaUploadRequestContract>();
        // Validate/read the whole version before any remote write. No arbitrary
        // local path comes from the caller or crosses the publication boundary.
        foreach (var ship in ships)
        {
            current(); token.ThrowIfCancellationRequested();
            var data = readImage(ship.Id);
            if (data is null) continue;
            const string prefix = "data:image/png;base64,";
            if (!data.StartsWith(prefix, StringComparison.Ordinal) || data.Length > 700000)
                throw new LocalHangarStoreException("hangar.image_read_failed", "Invalid local image.");
            if (requests.Count >= ShipMediaPolicy.MaximumUploadsPerHour)
                throw new LocalHangarStoreException("hangar.image_rate_limited", "Too many images for one publication.");
            requests.Add(new(ship.Id, ship.Code, ship.DisplayName, data[prefix.Length..], Guid.NewGuid().ToString("N")));
        }
        var receipts = new List<ShipMediaSummaryContract>();
        foreach (var request in requests)
        {
            current(); token.ThrowIfCancellationRequested();
            var receipt = await upload(request, token);
            current(); token.ThrowIfCancellationRequested();
            // Validate each receipt before starting another upload.
            CommunityHangarPublication.WithImages(snapshot, owner, [receipt]);
            if (receipt.ShipInstanceId != request.ShipInstanceId)
                throw new LocalHangarStoreException("hangar.image_not_allowed", "Unexpected upload receipt.");
            receipts.Add(receipt);
        }
        current(); token.ThrowIfCancellationRequested();
        return CommunityHangarPublication.WithImages(snapshot, owner, receipts);
    }
}
