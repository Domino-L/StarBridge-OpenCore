using StarBridge.Core.Presence;

namespace StarBridge.Desktop;

internal static class PartyRoomPresencePolicy
{
    internal static PlayerPresenceKind Resolve(
        PlayerPresenceKind localPresence,
        PlayerPresenceVisibilityMode visibilityMode) =>
        PlayerPresence.DecideSharing(localPresence, visibilityMode).PublicPresence;
}
