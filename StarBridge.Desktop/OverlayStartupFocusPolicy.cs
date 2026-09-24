using StarBridge.Core.Overlay;

namespace StarBridge.Desktop;

/// <summary>
/// Mirrors the WPF MainWindow overlay focus handoff, not the animation duration.
/// No timers, activation calls, content refreshes or entitlement decisions here.
/// </summary>
internal static class OverlayStartupFocusPolicy
{
    internal const double WithoutTransitionDelayMs = 120;

    internal static double DelayMs(OverlayDisplaySettings settings, bool motionEnabled,
        double? activeAppearanceRemainingMs = null)
    {
        if (!motionEnabled || !settings.EnableStartupTransition) return WithoutTransitionDelayMs;
        if (settings.StartupTransitionStyle == OverlayStartupTransitionStyle.BridgeTerminal)
            return Math.Ceiling(OverlayCompositionStartupTransitionWindow.PreferredGameFocusDelayMs);
        if (settings.StartupTransitionStyle == OverlayStartupTransitionStyle.LagrangeWeaveEquilibrium)
            return Math.Ceiling(LagrangeWeaveTimeline.FocusHandoffMs);
        return WithoutTransitionDelayMs;
    }

    internal static bool RetryAtClosedShutter(OverlayDisplaySettings settings, bool motionEnabled) =>
        motionEnabled && settings.EnableStartupTransition &&
        settings.StartupTransitionStyle == OverlayStartupTransitionStyle.NightShadowFlowField;
}
