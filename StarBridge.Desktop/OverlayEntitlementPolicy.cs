namespace StarBridge.Desktop;

public static class OverlayEntitlementPolicy
{
    public const string NightShadowEntitlement = OverlaySkinCatalog.NightShadowEntitlement;
    public const string VerdictEntitlement = OverlaySkinCatalog.VerdictEntitlement;

    public static bool CanUseNightShadow(IEnumerable<string>? entitlements)
    {
        return OverlaySkinCatalog.CanUse(OverlaySkin.NightShadow, entitlements);
    }

    public static bool RequestsNightShadow(OverlayDisplaySettings settings)
    {
        return settings.Skin == OverlaySkin.NightShadow ||
               settings.Theme == OverlayVisualTheme.NightShadow;
    }

    public static OverlayDisplaySettings RemoveNightShadow(OverlayDisplaySettings settings)
    {
        return OverlaySkinCatalog.ApplyLocks(settings with
        {
            Skin = OverlaySkin.Default,
            RequestedSkin = OverlaySkin.NightShadow,
            Theme = settings.Theme == OverlayVisualTheme.NightShadow
                ? OverlayVisualTheme.Default
                : settings.Theme
        }, OverlaySkin.Default);
    }
}
