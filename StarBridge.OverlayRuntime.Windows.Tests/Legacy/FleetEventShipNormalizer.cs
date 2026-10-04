using StarBridge.Core.Events;

namespace StarBridge.Desktop;

public static class FleetEventShipNormalizer
{
    public static FleetEvent Normalize(FleetEvent fleetEvent)
    {
        if (string.IsNullOrWhiteSpace(fleetEvent.Ship))
        {
            return fleetEvent;
        }

        var resolvedShip = ShipNameLocalizer.ResolveCode(fleetEvent.Ship);
        return resolvedShip.Equals(fleetEvent.Ship, StringComparison.Ordinal)
            ? fleetEvent
            : fleetEvent with { Ship = resolvedShip };
    }
}
