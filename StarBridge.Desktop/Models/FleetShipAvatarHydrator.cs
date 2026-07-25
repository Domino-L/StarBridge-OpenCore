namespace StarBridge.Desktop;

public static class FleetShipAvatarHydrator
{
    public static NetworkFleetShipSnapshot[] Hydrate(
        IEnumerable<NetworkFleetShipSnapshot>? ships,
        IEnumerable<NetworkFleetMemberSnapshot>? members)
    {
        var memberRows = (members ?? []).ToArray();
        return (ships ?? []).Select(ship =>
        {
            if (!string.IsNullOrWhiteSpace(ship.OwnerAvatarImageData))
            {
                return ship;
            }

            var owner = memberRows.FirstOrDefault(member =>
                !string.IsNullOrWhiteSpace(ship.OwnerAccountId) &&
                !string.IsNullOrWhiteSpace(member.AccountId)
                    ? ship.OwnerAccountId.Equals(member.AccountId, StringComparison.OrdinalIgnoreCase)
                    : member.GameName.Equals(ship.OwnerGameName, StringComparison.OrdinalIgnoreCase) ||
                      !string.IsNullOrWhiteSpace(ship.OwnerCallsign) &&
                      !string.IsNullOrWhiteSpace(member.Callsign) &&
                      member.Callsign.Equals(ship.OwnerCallsign, StringComparison.OrdinalIgnoreCase));
            return owner is null
                ? ship
                : ship with { OwnerAvatarImageData = owner.AvatarImageData };
        }).ToArray();
    }
}
