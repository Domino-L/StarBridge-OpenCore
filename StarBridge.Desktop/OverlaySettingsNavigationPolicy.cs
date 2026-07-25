namespace StarBridge.Desktop;

internal static class OverlaySettingsNavigationPolicy
{
    public static string ResolveBottomSectionKey(string? currentSectionKey)
    {
        return string.Equals(currentSectionKey, "startup", StringComparison.OrdinalIgnoreCase)
            ? "startup"
            : "background";
    }
}
