using StarBridge.Core.Overlay;
namespace StarBridge.Core.Tests;
internal static class OverlayCalmDisplaySettingsTests
{
    internal static void RunAll()
    {
        // New installs start calm; files written before calm display stay as they were.
        Check(OverlayDisplaySettings.Default.CalmDisplay == OverlayCalmDisplay.On, "new settings start calm");
        Check(InformationOverlayDefaults.DefaultSettings.CalmDisplay == OverlayCalmDisplay.On, "the built-in default preset starts calm");
        var legacy = OverlayDisplaySettings.Default.Serialize().Split(',').Take(74);
        var upgraded = OverlayDisplaySettings.Parse(string.Join(',', legacy));
        Check(upgraded.CalmDisplay == OverlayCalmDisplay.Unset && !OverlayCalmDisplayLevels.Resolve(upgraded).Enabled,
            "an older file reads as Unset and stays off");
        Check(upgraded.CalmWaitSeconds == 10 && upgraded.CalmIdleOpacity == 0 && upgraded.CalmLitOpacity == 0 &&
              upgraded.CalmLightWhen == OverlayCalmLightWhen.Relevant && upgraded.CalmPeekHotkey == "",
            "missing calm fields take the documented defaults");
        Check(upgraded with { CalmDisplay = OverlayCalmDisplay.Unset } == OverlayDisplaySettings.Parse(upgraded.Serialize()),
            "Unset round-trips, so the one-time introduction is not lost");

        var custom = OverlayDisplaySettings.Default with
        {
            CalmDisplay = OverlayCalmDisplay.Off, CalmWaitSeconds = 20, CalmIdleOpacity = 0.4, CalmLitOpacity = 0.9,
            CalmLightWhen = OverlayCalmLightWhen.Any, CalmPeekHotkey = "Ctrl+Space"
        };
        Check(OverlayDisplaySettings.Parse(custom.Serialize()) == custom, "every calm field round-trips");
        var invalid = OverlayDisplaySettings.Parse((OverlayDisplaySettings.Default with
        {
            CalmWaitSeconds = 7, CalmIdleOpacity = 0.05, CalmLitOpacity = 3, CalmPeekHotkey = "Ctrl+,"
        }).Serialize());
        Check(invalid.CalmWaitSeconds == 10 && invalid.CalmIdleOpacity == 0.15 && invalid.CalmLitOpacity == 1 && invalid.CalmPeekHotkey == "",
            "out-of-range values are normalized, never written raw");

        // Levels follow the existing opacity until the user picks their own.
        var full = OverlayCalmDisplayLevels.Resolve(OverlayDisplaySettings.Default with { Opacity = 1 });
        Check(full.Enabled && full.Idle == 0.35 && full.Lit == 1 && full.Wait == TimeSpan.FromSeconds(10), "full opacity rests at 35% and lights to 100%");
        var low = OverlayCalmDisplayLevels.Resolve(OverlayDisplaySettings.Default with { Opacity = 0.25 });
        Check(low.Idle == 0.25 && low.Lit == 0.85, "a low opacity never rests darker, and lights to a readable 85%");
        var floor = OverlayCalmDisplayLevels.Resolve(OverlayDisplaySettings.Default with { Opacity = 0.15, CalmIdleOpacity = 0.15 });
        Check(floor.Idle >= OverlayCalmDisplayLevels.MinimumOpacity, "nothing goes below the readable floor");
        var crossed = OverlayCalmDisplayLevels.Resolve(OverlayDisplaySettings.Default with { CalmIdleOpacity = 0.9, CalmLitOpacity = 0.5 });
        Check(crossed.Idle == 0.5 && crossed.Lit == 0.5, "resting is never brighter than lit");
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
