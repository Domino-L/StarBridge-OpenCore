namespace StarBridge.Desktop;

public static class FleetShipInventoryRowChangeDetector
{
    public static bool AreEquivalent(
        IReadOnlyList<FleetShipInventoryRow> current,
        IReadOnlyList<FleetShipInventoryRow> incoming)
    {
        if (ReferenceEquals(current, incoming))
        {
            return true;
        }

        if (current.Count != incoming.Count)
        {
            return false;
        }

        for (var index = 0; index < current.Count; index++)
        {
            if (!AreEquivalent(current[index], incoming[index]))
            {
                return false;
            }
        }

        return true;
    }

    private static bool AreEquivalent(FleetShipInventoryRow current, FleetShipInventoryRow incoming)
    {
        return current.Number == incoming.Number
               && current.ShipName == incoming.ShipName
               && current.ShipCode == incoming.ShipCode
               && current.OwnerDisplay == incoming.OwnerDisplay
               && current.OwnerCallsign == incoming.OwnerCallsign
               && current.OwnerGameId == incoming.OwnerGameId
               && current.OwnerAvatarPath == incoming.OwnerAvatarPath
               && current.OwnerInitials == incoming.OwnerInitials
               && current.ImportedAtText == incoming.ImportedAtText
               && current.FleetSharedAtText == incoming.FleetSharedAtText
               && current.ShipSpec == incoming.ShipSpec
               && current.ShipRole == incoming.ShipRole
               && current.ShipStatus == incoming.ShipStatus
               && current.ShipPrice == incoming.ShipPrice
               && current.ShipImagePath == incoming.ShipImagePath
               && current.ShipInstanceId == incoming.ShipInstanceId
               && current.ShipRoleColorHex == incoming.ShipRoleColorHex
               && current.OwnerAccountId == incoming.OwnerAccountId
               && current.CustomImageMediaId == incoming.CustomImageMediaId
               && current.CanReportCustomImage == incoming.CanReportCustomImage
               && current.CustomImageCropFocusX.Equals(incoming.CustomImageCropFocusX)
               && current.CustomImageCropFocusY.Equals(incoming.CustomImageCropFocusY)
               && current.CustomImageCropZoom.Equals(incoming.CustomImageCropZoom)
               && current.OwnerOnlineStatus == incoming.OwnerOnlineStatus
               && current.OwnerLiveStatus == incoming.OwnerLiveStatus
               && AreEquivalent(current.LoanerRows, incoming.LoanerRows);
    }
}
