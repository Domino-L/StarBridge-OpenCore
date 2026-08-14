namespace StarBridge.Desktop;

using System.Text;

public static class NetworkPlayerSnapshotChangeDetector
{
    public static string BuildFingerprint(IEnumerable<NetworkPlayerSnapshot>? snapshots, string? fleetCode)
    {
        var builder = new StringBuilder(fleetCode?.Trim() ?? "");
        foreach (var player in (snapshots ?? []).OrderBy(player => player.AccountId ?? player.Name, StringComparer.OrdinalIgnoreCase))
        {
            Append(builder, player.AccountId);
            Append(builder, player.Name);
            Append(builder, player.Callsign);
            Append(builder, player.Fleet);
            Append(builder, player.Online ? "1" : "0");
            Append(builder, player.Ship);
            Append(builder, player.ShipConfidence);
            Append(builder, player.Location);
            Append(builder, player.LocationConfidence);
            Append(builder, player.VisibilityScope);
            Append(builder, player.PersonalHangarSharedWithFleet ? "1" : "0");
            Append(builder, player.ServerShard);
            Append(builder, player.ServerRegion);
            Append(builder, player.LiveStatus);
            Append(builder, player.SharedEventTypes.ToString());
            foreach (var sharedEvent in (player.SharedEvents ?? [])
                         .OrderBy(sharedEvent => sharedEvent.OccurredAt)
                         .ThenBy(sharedEvent => sharedEvent.Id, StringComparer.Ordinal))
            {
                Append(builder, sharedEvent.Id);
                Append(builder, sharedEvent.Type);
                Append(builder, sharedEvent.OccurredAt.UtcTicks.ToString());
            }
            Append(builder, ImageMarker(player.AvatarImageData));
            foreach (var ship in (player.OwnedShips ?? [])
                         .OrderBy(ship => ship.InstanceId ?? ship.Code, StringComparer.OrdinalIgnoreCase))
            {
                Append(builder, ship.InstanceId);
                Append(builder, ship.Code);
                Append(builder, ship.DisplayName);
                Append(builder, ship.Source);
                Append(builder, ship.ImportedAt.UtcTicks.ToString());
                Append(builder, ship.RoleCategory);
                Append(builder, ship.CustomImageMediaId);
                Append(builder, ship.CustomImageCropFocusX.ToString("R", System.Globalization.CultureInfo.InvariantCulture));
                Append(builder, ship.CustomImageCropFocusY.ToString("R", System.Globalization.CultureInfo.InvariantCulture));
                Append(builder, ship.CustomImageCropZoom.ToString("R", System.Globalization.CultureInfo.InvariantCulture));
            }
        }

        return builder.ToString();
    }

    private static void Append(StringBuilder builder, string? value) =>
        builder.Append(value?.Trim()).Append('\u001f');

    private static string ImageMarker(string? value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return "";
        }

        return value.Length <= 32
            ? value
            : $"{value.Length}:{value[..16]}:{value[^16..]}";
    }
}
