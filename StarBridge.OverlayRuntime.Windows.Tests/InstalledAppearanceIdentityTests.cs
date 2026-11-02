using System.Reflection;
using StarBridge.OverlayRuntime.Windows;

internal static class InstalledAppearanceIdentityTests
{
    internal static void Run()
    {
        // Public build: a stable wire ID must not invent an installed profile or
        // grant use. Private-pack registration is tested outside this repository.
        var catalog = typeof(WindowsInformationOverlayRuntimeFactory).Assembly
            .GetType("StarBridge.Desktop.OverlaySkinCatalog", throwOnError: true)!;
        var flags = BindingFlags.Static | BindingFlags.Public;
        var listed = (System.Collections.IEnumerable)catalog.GetProperty("Listed", flags)!.GetValue(null)!;
        foreach (var profile in listed)
            Check((OverlaySkin)profile.GetType().GetProperty("Id")!.GetValue(profile)! != OverlaySkin.HajiCitizen,
                "Public build invented an uninstalled profile");
        var canUse = (bool)catalog.GetMethod("CanUse", flags)!.Invoke(null,
            [OverlaySkin.HajiCitizen, new[] { "overlay.skin.night-shadow", "overlay.skin.verdict" }])!;
        Check(!canUse, "Known identity or unrelated entitlement granted use");
        var settings = OverlayDisplaySettings.Default with { Skin = OverlaySkin.HajiCitizen, RequestedSkin = OverlaySkin.HajiCitizen };
        var result = catalog.GetMethod("Resolve", flags)!.Invoke(null, [settings, Array.Empty<string>()])!;
        Check((OverlaySkin)result.GetType().GetProperty("EffectiveSkin")!.GetValue(result)! == OverlaySkin.Default,
            "Uninstalled requested identity did not fall back safely");
        var ordinary = catalog.GetMethod("Resolve", flags)!.Invoke(null, [OverlayDisplaySettings.Default, Array.Empty<string>()])!;
        Check((bool)ordinary.GetType().GetProperty("IsAvailable")!.GetValue(ordinary)!, "Ordinary appearance became unavailable");
        using var runtime = WindowsInformationOverlayRuntimeFactory.Create(() => StarBridge.HostRuntime.Presence.GameLogSessionSnapshot.Empty);
        var preview = (StarBridge.HostRuntime.Overlay.IInformationOverlayAppearancePreviewRuntime)runtime;
        Check(preview.GetLivePreviewAppearanceIds().Count == 0, "Public runtime invented a live preview extension");
        Check(preview.OpenAppearancePreviewAsync("HajiCitizen", StarBridge.Core.Overlay.OverlayAppearanceOptions.Empty).GetAwaiter().GetResult() is null,
            "Known ID opened an uninstalled private preview");
        Console.WriteLine("PASS installed identity requires actual registration and cannot grant use");
    }
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
