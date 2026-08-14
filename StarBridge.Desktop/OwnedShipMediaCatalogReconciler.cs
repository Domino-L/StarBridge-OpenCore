using StarBridge.Core.ShipMedia;

namespace StarBridge.Desktop;

internal static class OwnedShipMediaCatalogReconciler
{
    public static bool Reconcile(
        IList<OwnedShipRecord> ships,
        IReadOnlyCollection<ShipMediaSummaryContract> catalogItems)
    {
        var mediaByInstance = catalogItems
            .Where(item => !string.IsNullOrWhiteSpace(item.ShipInstanceId))
            .GroupBy(item => item.ShipInstanceId, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(
                group => group.Key,
                group => group.OrderByDescending(item => item.UpdatedAt).First(),
                StringComparer.OrdinalIgnoreCase);
        var mediaById = catalogItems
            .Where(item => !string.IsNullOrWhiteSpace(item.MediaId))
            .GroupBy(item => item.MediaId, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(
                group => group.Key,
                group => group.OrderByDescending(item => item.UpdatedAt).First(),
                StringComparer.OrdinalIgnoreCase);

        var changed = false;
        for (var index = 0; index < ships.Count; index++)
        {
            var ship = ships[index];
            ShipMediaSummaryContract? media = null;
            if (!string.IsNullOrWhiteSpace(ship.InstanceId))
            {
                mediaByInstance.TryGetValue(ship.InstanceId, out media);
            }

            if (media is null && !string.IsNullOrWhiteSpace(ship.CustomImageMediaId))
            {
                mediaById.TryGetValue(ship.CustomImageMediaId, out media);
            }

            var mediaId = media?.MediaId;
            var cropFrame = media?.CropFrame ?? ShipImageCropFrame.Default;
            if (string.Equals(ship.CustomImageMediaId, mediaId, StringComparison.OrdinalIgnoreCase) &&
                ship.CustomImageCropFrame == cropFrame)
            {
                continue;
            }

            ships[index] = ship with
            {
                CustomImageMediaId = mediaId,
                CustomImageCropFocusX = cropFrame.FocusX,
                CustomImageCropFocusY = cropFrame.FocusY,
                CustomImageCropZoom = cropFrame.Zoom
            };
            changed = true;
        }

        return changed;
    }
}
