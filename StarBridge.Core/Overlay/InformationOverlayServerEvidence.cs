namespace StarBridge.Core.Overlay;

/// <summary>Unknown peer servers cannot be presented as a confirmed zero count.
/// Region-only data is not exact server evidence.</summary>
public static class InformationOverlayServerEvidence
{
    public static bool CanReportPeerCount(bool localInGame, bool localServerKnown,
        int peersInGame, int peersWithExactServer) =>
        localInGame && localServerKnown && peersInGame >= 0 &&
        peersWithExactServer == peersInGame;
}
