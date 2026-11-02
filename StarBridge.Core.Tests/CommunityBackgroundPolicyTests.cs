#if STARBRIDGE_SERVER_POLICY
using StarBridge.Server;
#endif

internal static class CommunityBackgroundPolicyTests
{
    internal static void Run()
    {
#if STARBRIDGE_SERVER_POLICY
        var background = FleetProfileUpdateSelection.From(["background"]);
        if (!background.Background || background.Banner || background.Profile || background.Logo ||
            background.RequestsUnauthorizedSection(false, false, true) ||
            !background.RequestsUnauthorizedSection(true, true, false))
            throw new Exception("Background must be independent and require banner authority.");
        var banner = FleetProfileUpdateSelection.From(["banner"]);
        if (banner.Background || !banner.Banner) throw new Exception("Banner selection must not select background.");
        var legacy = FleetProfileUpdateSelection.From(null);
        if (legacy.IsTargeted || !legacy.Background) throw new Exception("Legacy updates retain optional background fields.");
#endif
    }
}
