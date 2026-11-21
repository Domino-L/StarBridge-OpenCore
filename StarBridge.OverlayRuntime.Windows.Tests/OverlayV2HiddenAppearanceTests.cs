using StarBridge.Core.Overlay;
using StarBridge.Desktop;
using StarBridge.OverlayRuntime.Windows;

// 0.7.3 overlay v2 (user, 11-07: "之前的外观都暂时隐藏 只留面罩这一个"; "藏，等之后做v2"): every other
// appearance stays listed, qualified and saved, but the overlay draws the visor. Off screen, no window.
internal static class OverlayV2HiddenAppearanceTests
{
    private static void Check(bool value, string name)
    {
        if (!value) throw new InvalidOperationException("FAIL " + name);
    }

    internal static void Run()
    {
        // Listing and qualification are unchanged (the private catalog gate reads them).
        var listed = OverlaySkinCatalog.Listed.Select(profile => profile.Id).ToArray();
        // Night Shadow is registered only in builds with the optional appearances; when it is, it stays listed.
        var nightShadowBuilt = OverlaySkinCatalog.All.Any(profile => profile.Id == OverlaySkin.NightShadow);
        Check(listed.Contains(OverlaySkin.Visor) && listed.Contains(OverlaySkin.Default) && (!nightShadowBuilt || listed.Contains(OverlaySkin.NightShadow)),
            "hidden appearances stay listed");
        Check(!OverlaySkinCatalog.IsHiddenUntilV2(OverlaySkin.Visor), "the visor is not hidden");
        var grantsAll = new[] { OverlaySkinCatalog.NightShadowEntitlement, OverlaySkinCatalog.VerdictEntitlement };
        foreach (var skin in new[] { OverlaySkin.Default, OverlaySkin.NightShadow, OverlaySkin.Verdict, OverlaySkin.HajiCitizen })
        {
            Check(OverlaySkinCatalog.IsHiddenUntilV2(skin), skin + " is put away until v2");
            var saved = OverlayDisplaySettings.Default with { Skin = skin, RequestedSkin = skin };
            foreach (var grants in new[] { Array.Empty<string>(), grantsAll })
            {
                var tag = $"{skin} ({(grants.Length == 0 ? "no" : "with")} qualification)";
                // Drawing: the visor, its own drawing path and startup.
                var drawn = OverlaySkinCatalog.ResolveForDrawing(saved, grants);
                Check(drawn.EffectiveSkin == OverlaySkin.Visor, tag + ": drawn as the visor");
                Check(drawn.Profile.RenderKind == OverlaySkinRenderKind.Visor, tag + ": the visor drawing path");
                Check(drawn.Settings.Skin == OverlaySkin.Visor, tag + ": the window gets the visor");
                Check(drawn.Settings.StartupTransitionStyle == OverlayStartupTransitionStyle.BridgeTerminal, tag + ": the visor's startup");
                // Saving: Resolve is what it was before 0.7.3, so a saved or imported preset never becomes the visor.
                var kept = OverlaySkinCatalog.Resolve(saved, grants);
                Check(kept.EffectiveSkin != OverlaySkin.Visor && kept.Settings.Skin != OverlaySkin.Visor, tag + ": what can be saved is not the visor");
                Check(drawn.IsAvailable == kept.IsAvailable && drawn.RequestedSkin == kept.RequestedSkin, tag + ": qualification and request reported as before");
                // Resolving what would be saved again still finds the same request.
                var again = OverlaySkinCatalog.Resolve(OverlayDisplaySettings.Parse(kept.Settings.Serialize()), grants);
                Check(again.RequestedSkin == kept.RequestedSkin, tag + ": a second resolve keeps the request");
                Check(saved.Skin == skin && saved.RequestedSkin == skin, tag + ": the saved settings are unchanged");
            }
        }

        // A hidden appearance's locked palette would start that appearance's own startup and colours: the visor
        // draws with its own palette instead. An ordinary palette the user chose stays.
        var nightShadow = OverlayDisplaySettings.Default with
        {
            Skin = OverlaySkin.NightShadow, RequestedSkin = OverlaySkin.NightShadow, Theme = OverlayVisualTheme.NightShadow,
        };
        var palette = OverlaySkinCatalog.ResolveForDrawing(nightShadow, grantsAll).Settings;
        Check(palette.Theme != OverlayVisualTheme.NightShadow && palette.Skin == OverlaySkin.Visor, "a locked palette is not drawn on the visor");
        var drake = OverlaySkinCatalog.ResolveForDrawing(nightShadow with { Theme = OverlayVisualTheme.Drake }, grantsAll).Settings;
        Check(drake.Theme == OverlayVisualTheme.Drake, "a palette the user chose is drawn on the visor");
        // The hidden locked palettes are fixed, not read from the registered profiles: a build without the optional
        // appearances (where the saved request already fell back) still does not draw the old palette.
        Check(OverlaySkinCatalog.HiddenLockedThemes.SetEquals(new[] { OverlayVisualTheme.NightShadow, OverlayVisualTheme.Verdict }), "hidden locked palettes are fixed");
        var fallenBack = OverlayDisplaySettings.Default with { Skin = OverlaySkin.Default, RequestedSkin = OverlaySkin.NightShadow };
        Check(OverlaySkinCatalog.ForDrawing(fallenBack, nightShadow).Theme != OverlayVisualTheme.NightShadow, "without the optional appearances the old palette is not drawn");
        Check(OverlaySkinCatalog.DrawnTheme(OverlayVisualTheme.NightShadow) != OverlayVisualTheme.NightShadow
            && OverlaySkinCatalog.DrawnTheme(OverlayVisualTheme.Verdict) != OverlayVisualTheme.Verdict
            && OverlaySkinCatalog.DrawnTheme(OverlayVisualTheme.Drake) == OverlayVisualTheme.Drake, "previews drop only the hidden locked palettes");
        // The legacy window path draws through ForDrawing without changing its own settings.
        var legacy = OverlaySkinCatalog.ApplyLocks(nightShadow, OverlaySkin.NightShadow);
        var legacyBefore = legacy;
        Check(OverlaySkinCatalog.ForDrawing(legacy).Skin == OverlaySkin.Visor && legacy == legacyBefore && OverlaySkinCatalog.IsHiddenUntilV2(legacy.Skin),
            "the legacy window draws the visor and keeps its settings");

        var visor = OverlaySkinCatalog.ResolveForDrawing(OverlayDisplaySettings.Default with { Skin = OverlaySkin.Visor, RequestedSkin = OverlaySkin.Visor }, []);
        Check(visor.EffectiveSkin == OverlaySkin.Visor && visor.IsAvailable, "the visor itself resolves to the visor");

        // No preview of a hidden appearance through the native preview entry points.
        using (var runtime = WindowsInformationOverlayRuntimeFactory.Create(() => StarBridge.HostRuntime.Presence.GameLogSessionSnapshot.Empty))
        {
            var preview = (StarBridge.HostRuntime.Overlay.IInformationOverlayAppearancePreviewRuntime)runtime;
            Check(!preview.GetLivePreviewAppearanceIds().Any(id => Enum.TryParse<OverlaySkin>(id, out var s) && OverlaySkinCatalog.IsHiddenUntilV2(s)),
                "no preview is offered for a hidden appearance");
            Check(preview.OpenAppearancePreviewAsync(nameof(OverlaySkin.NightShadow), OverlayAppearanceOptions.Empty).GetAwaiter().GetResult() is null,
                "a hidden appearance's preview does not open");
        }
        Console.WriteLine("PASS 0.7.3 overlay v2: hidden appearances draw the visor, stay listed, qualified and saved, and offer no preview");
    }
}
