namespace StarBridge.Desktop;

public sealed record FleetShipAvailabilityEntry(
    string AssetKey,
    string OwnerKey,
    string OwnerDisplay,
    string ShipName,
    string Detail,
    int DispatchRank,
    decimal DispatchValue);

public sealed record FleetShipAvailabilityOwnerGroup(
    string OwnerKey,
    string OwnerDisplay,
    IReadOnlyList<FleetShipAvailabilityEntry> Ships);

/// <summary>
/// Projects deployable fleet assets into stable owner groups without changing asset identity.
/// </summary>
public static class FleetShipAvailabilityGrouping
{
    public static IReadOnlyList<FleetShipAvailabilityOwnerGroup> Project(
        IEnumerable<FleetShipAvailabilityEntry> entries)
    {
        ArgumentNullException.ThrowIfNull(entries);

        return entries
            .GroupBy(
                entry => NormalizeOwnerKey(entry.OwnerKey, entry.OwnerDisplay),
                StringComparer.OrdinalIgnoreCase)
            .Select(group =>
            {
                var ships = group
                    .OrderBy(entry => entry.DispatchRank)
                    .ThenByDescending(entry => entry.DispatchValue)
                    .ThenBy(entry => entry.ShipName, StringComparer.CurrentCultureIgnoreCase)
                    .ThenBy(entry => entry.AssetKey, StringComparer.OrdinalIgnoreCase)
                    .ToArray();
                return new FleetShipAvailabilityOwnerGroup(
                    group.Key,
                    ships[0].OwnerDisplay,
                    ships);
            })
            .OrderByDescending(group => group.Ships.Count)
            .ThenBy(group => group.OwnerDisplay, StringComparer.CurrentCultureIgnoreCase)
            .ThenBy(group => group.OwnerKey, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private static string NormalizeOwnerKey(string ownerKey, string ownerDisplay)
    {
        return string.IsNullOrWhiteSpace(ownerKey)
            ? ownerDisplay.Trim()
            : ownerKey.Trim();
    }
}
