// Same regression runs against both the internal client and the independent renderer.
using StarBridge.Core.Overlay;

namespace StarBridge.Desktop.Tests;

internal static class OverlayStartupFocusPolicyTests
{
    internal static void RunAll()
    {
        var settings = OverlayDisplaySettings.Default with
        { EnableStartupTransition = true, StartupTransitionStyle = OverlayStartupTransitionStyle.BridgeTerminal };
        Check(OverlayStartupFocusPolicy.DelayMs(settings, true) ==
            Math.Ceiling(OverlayCompositionStartupTransitionWindow.PreferredGameFocusDelayMs),
            "Default overlay waits for the WPF progress handoff instead of focusing immediately.");
        Check(OverlayStartupFocusPolicy.DelayMs(settings, true) > 120,
            "Default animated startup must not use the no-transition delay.");
        Check(OverlayStartupFocusPolicy.DelayMs(settings with { EnableStartupTransition = false }, true) == 120 &&
            OverlayStartupFocusPolicy.DelayMs(settings, false) == 120,
            "Disabled/reduced motion retains WPF's short non-animation handoff.");
        var skipped = OverlayStartupTransitionPolicy.ResolveForOpen(settings with
        { SkipStartupTransitionWhenGameForeground = true }, true);
        Check(!skipped.EnableStartupTransition && OverlayStartupFocusPolicy.DelayMs(skipped, true) == 120,
            "Foreground skip is applied before choosing focus timing.");
        Check(OverlayStartupFocusPolicy.DelayMs(settings with
        { StartupTransitionStyle = OverlayStartupTransitionStyle.LagrangeWeaveEquilibrium }, true) == LagrangeWeaveTimeline.FocusHandoffMs,
            "Lagrange keeps its dedicated WPF handoff.");
#if STARBRIDGE_COMMERCIAL_APPEARANCES
        var night = settings with { StartupTransitionStyle = OverlayStartupTransitionStyle.NightShadowFlowField };
        Check(OverlayStartupFocusPolicy.DelayMs(night, true) == NightShadowFlowFieldTimeline.FocusHandoffMs &&
            OverlayStartupFocusPolicy.RetryAtClosedShutter(night, true), "Night Shadow hands off at the closed shutter.");
        var verdict = settings with { Skin = OverlaySkin.Verdict, StartupTransitionStyle = OverlayStartupTransitionStyle.VerdictProtocol };
        Check(OverlayStartupFocusPolicy.DelayMs(verdict, true, 350) > 0,
            "Verdict retains its dedicated or active renderer handoff.");
#endif
        Check(!OverlayStartupFocusPolicy.RetryAtClosedShutter(settings, true) &&
            !OverlayStartupFocusPolicy.RetryAtClosedShutter(settings, false),
            "Shutter-specific retries do not spread to other transitions.");
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
