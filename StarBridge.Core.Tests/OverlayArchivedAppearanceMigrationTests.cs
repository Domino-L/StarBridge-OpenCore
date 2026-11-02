using StarBridge.Core.Overlay;

namespace StarBridge.Core.Tests;

internal static class OverlayArchivedAppearanceMigrationTests
{
    internal static void RunAll()
    {
        var expected = OverlayDisplaySettings.Default with
        {
            Opacity = 0.63, CrosshairColor = "#34D5FF", CrosshairSize = 117,
            NightShadowBloom = OverlayNightShadowBloom.Strong, AutoThemeByShip = true,
            ShowChat = false, CalmWaitSeconds = 20
        };
        foreach (var (index, legacy) in new[]
        {
            (43, "LagrangeWeave"), (72, "LagrangeWeave"), (10, "LagrangeWeave"),
            (20, "LagrangeWeaveEquilibrium"), (43, "2"), (72, "2"), (10, "14"), (20, "6")
        })
        {
            var parts = expected.Serialize().Split(',');
            parts[index] = legacy;
            var parsed = OverlayDisplaySettings.Parse(string.Join(',', parts));
            if (parsed.Serialize() != expected.Serialize())
                throw new InvalidOperationException($"Archived CSV slot {index} must migrate without losing other fields.");
        }

        var old = expected.Serialize().Split(',');
        old[43] = old[72] = old[10] = "LagrangeWeave";
        old[20] = "LagrangeWeaveEquilibrium";
        var shortened = string.Join(',', old.Take(72));
        var migrated = OverlayDisplaySettings.Parse(shortened);
        if (migrated.Skin != OverlaySkin.Default || migrated.RequestedSkin != OverlaySkin.Default ||
            migrated.Theme != OverlayVisualTheme.Default || migrated.StartupTransitionStyle != OverlayStartupTransitionStyle.BridgeTerminal ||
            migrated.CrosshairColor != expected.CrosshairColor || migrated.NightShadowBloom != expected.NightShadowBloom)
            throw new InvalidOperationException("Old settings without requestedSkin must migrate too.");

        // A stray archived theme or transition on a valid appearance replaces only itself.
        var nightShadow = expected with
        {
            Skin = OverlaySkin.NightShadow, RequestedSkin = OverlaySkin.NightShadow, Theme = OverlayVisualTheme.NightShadow,
            StartupTransitionStyle = OverlayStartupTransitionStyle.NightShadowCrimsonFold
        };
        foreach (var (index, legacy) in new[] { (20, "LagrangeWeaveEquilibrium"), (20, "6"), (10, "LagrangeWeave"), (10, "14") })
        {
            var parts = nightShadow.Serialize().Split(',');
            parts[index] = legacy;
            var parsed = OverlayDisplaySettings.Parse(string.Join(',', parts));
            if (parsed.Skin != OverlaySkin.NightShadow || parsed.RequestedSkin != OverlaySkin.NightShadow ||
                (index == 20 ? parsed.StartupTransitionStyle != OverlayStartupTransitionStyle.BridgeTerminal || parsed.Theme != OverlayVisualTheme.NightShadow
                    : parsed.StartupTransitionStyle != OverlayStartupTransitionStyle.NightShadowCrimsonFold))
                throw new InvalidOperationException($"Archived slot {index} alone must not reset a valid appearance.");
        }

        if (Enum.IsDefined(typeof(OverlaySkin), 2) || Enum.IsDefined(typeof(OverlayVisualTheme), 14) ||
            Enum.IsDefined(typeof(OverlayStartupTransitionStyle), 6) || (int)OverlaySkin.Verdict != 3 ||
            (int)OverlaySkin.HajiCitizen != 4 || (int)OverlayVisualTheme.Verdict != 15 ||
            (int)OverlayStartupTransitionStyle.VerdictProtocol != 7)
            throw new InvalidOperationException("Archived IDs must stay reserved without shifting later enum values.");
    }
}
