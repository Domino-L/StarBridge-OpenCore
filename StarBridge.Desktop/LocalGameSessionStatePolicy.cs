using StarBridge.Core.Presence;
using StarBridge.Core.State;

namespace StarBridge.Desktop;

internal static class LocalGameSessionStatePolicy
{
    internal static bool IsActive(
        bool gameProcessRunning,
        PlayerPresenceKind applicationPresence)
    {
        // Application authentication/presence can briefly transition while tokens
        // refresh. Game.log state belongs to the process session and must only be
        // cleared by an actual game-session boundary.
        _ = applicationPresence;
        return gameProcessRunning;
    }

    internal static void MarkActiveIfRunning(
        FleetState state,
        string? localPlayer,
        bool gameProcessRunning,
        PlayerPresenceKind applicationPresence,
        DateTimeOffset timestamp)
    {
        ArgumentNullException.ThrowIfNull(state);
        if (string.IsNullOrWhiteSpace(localPlayer) ||
            !IsActive(gameProcessRunning, applicationPresence))
        {
            // A negative process poll is not an authoritative session boundary.
            // The process transition observer or a parsed offline event owns clearing.
            return;
        }

        state.SetPlayerOnlineState(localPlayer, online: true, timestamp);
    }
}
