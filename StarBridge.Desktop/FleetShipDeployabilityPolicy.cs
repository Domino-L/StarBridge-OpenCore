namespace StarBridge.Desktop;

public enum FleetShipDeployabilityCategory
{
    Deployable,
    OwnerOffline,
    NotSynchronized,
    NotFlyable
}

/// <summary>
/// Defines whether one synchronized fleet-ship asset can be dispatched now.
/// A concept asset counts once when at least one flyable replacement exists.
/// </summary>
public static class FleetShipDeployabilityPolicy
{
    public static FleetShipDeployabilityCategory Classify(
        bool ownerOnline,
        bool isSynced,
        bool shipFlyable,
        bool hasFlyableLoaner)
    {
        if (!ownerOnline)
        {
            return FleetShipDeployabilityCategory.OwnerOffline;
        }

        if (!isSynced)
        {
            return FleetShipDeployabilityCategory.NotSynchronized;
        }

        return shipFlyable || hasFlyableLoaner
            ? FleetShipDeployabilityCategory.Deployable
            : FleetShipDeployabilityCategory.NotFlyable;
    }

    public static bool IsDeployable(
        bool ownerOnline,
        bool isSynced,
        bool shipFlyable,
        bool hasFlyableLoaner) =>
        Classify(ownerOnline, isSynced, shipFlyable, hasFlyableLoaner) ==
        FleetShipDeployabilityCategory.Deployable;
}
