namespace StarBridge.Desktop;

public static class NetworkFleetShipSnapshotChangeDetector
{
    public static bool AreEquivalent(
        IEnumerable<NetworkFleetShipSnapshot>? current,
        IEnumerable<NetworkFleetShipSnapshot>? incoming)
    {
        var currentByKey = BuildSnapshotMap(current);
        var incomingByKey = BuildSnapshotMap(incoming);
        if (currentByKey.Count != incomingByKey.Count)
        {
            return false;
        }

        foreach (var pair in currentByKey)
        {
            if (!incomingByKey.TryGetValue(pair.Key, out var incomingShip) ||
                !EqualityComparer<NetworkFleetShipSnapshot>.Default.Equals(pair.Value, incomingShip))
            {
                return false;
            }
        }

        return true;
    }

    private static Dictionary<string, NetworkFleetShipSnapshot> BuildSnapshotMap(
        IEnumerable<NetworkFleetShipSnapshot>? ships)
    {
        var result = new Dictionary<string, NetworkFleetShipSnapshot>(StringComparer.OrdinalIgnoreCase);
        foreach (var ship in ships ?? [])
        {
            if (string.IsNullOrWhiteSpace(ship.Code) || string.IsNullOrWhiteSpace(ship.OwnerGameName))
            {
                continue;
            }

            var owner = string.IsNullOrWhiteSpace(ship.OwnerAccountId)
                ? ship.OwnerGameName
                : $"account:{ship.OwnerAccountId}";
            var shipIdentity = string.IsNullOrWhiteSpace(ship.InstanceId)
                ? NormalizeKey(ship.Code)
                : $"instance:{NormalizeKey(ship.InstanceId)}";
            result[$"{NormalizeKey(owner)}::{shipIdentity}"] = ship;
        }

        return result;
    }

    private static string NormalizeKey(string? value) =>
        string.IsNullOrWhiteSpace(value) ? "unknown" : value.Trim();
}
