using StarBridge.Core.State;

namespace StarBridge.Desktop;

public readonly record struct FleetShipOwnerPresenceState(
    string OnlineStatus,
    string? LiveStatus);

public static class FleetShipOwnerPresenceProjection
{
    public static FleetShipOwnerPresenceState Resolve(
        PlayerRow? rosterMember,
        NetworkPlayerSnapshot? networkSnapshot)
    {
        if (rosterMember is not null)
        {
            return new FleetShipOwnerPresenceState(
                rosterMember.SharedOnlineStatusValue,
                rosterMember.SharedLiveStatusValue);
        }

        return new FleetShipOwnerPresenceState(
            networkSnapshot?.Online == true ? "Online" : "Offline",
            networkSnapshot?.LiveStatus);
    }
}
