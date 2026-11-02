using System.Text.Json;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;

internal static class OverlayArchivedAppearanceMigrationTests
{
    internal static void Run()
    {
        var expected = OverlayDisplaySettings.Default with
        {
            Opacity = 0.63, CrosshairColor = "#34D5FF", CrosshairSize = 117,
            NightShadowBloom = OverlayNightShadowBloom.Strong, AutoThemeByShip = true,
            ShowChat = false, CalmWaitSeconds = 20
        };
        var layout = InformationOverlayDefaults.CreateLayout(InformationOverlayPresetCodec.DefaultPresetId);
        foreach (var (field, legacy) in new (string, object)[]
        {
            ("skin", "LagrangeWeave"), ("requestedSkin", "LagrangeWeave"), ("theme", "LagrangeWeave"),
            ("startupTransitionStyle", "LagrangeWeaveEquilibrium"),
            ("skin", 2), ("requestedSkin", 2), ("theme", 14), ("startupTransitionStyle", 6)
        })
        {
            var wire = new Dictionary<string, object?>(OverlayWorkspaceWireProjection.Settings(expected)) { [field] = legacy };
            var parsed = OverlayWorkspaceWireProjection.ParseSettings(JsonSerializer.SerializeToElement(wire));
            Check(parsed.Serialize() == expected.Serialize(), "Workspace JSON preserves all other fields: " + field);

            // A persisted v2 document uses the same parser and must remain a ready preset.
            wire.Remove("scenePreference");
            var payload = JsonSerializer.Serialize(new
            {
                schemaVersion = 2, recoveredDefaults = false, settings = wire,
                layout = layout.Select(OverlayWorkspaceWireProjection.Layout),
                sources = JsonSerializer.Deserialize<JsonElement>(OverlayPresetSourcesCodec.Serialize(OverlayPresetSources.Default))
            });
            var document = OverlayPresetDocument.Parse(payload);
            Check(document.Settings.Serialize() == expected.Serialize() && !document.RecoveredDefaults,
                "Local v2 preset remains valid: " + field);
            Check(document.Serialize() == new OverlayPresetDocument(expected, layout, OverlayPresetSources.Default).Serialize(),
                "Local v2 layout and source policy are preserved.");
        }

        // An archived transition left on a valid appearance replaces only itself.
        var nightShadow = expected with
        {
            Skin = OverlaySkin.NightShadow, RequestedSkin = OverlaySkin.NightShadow, Theme = OverlayVisualTheme.NightShadow,
            StartupTransitionStyle = OverlayStartupTransitionStyle.NightShadowCrimsonFold
        };
        foreach (var legacy in new object[] { "LagrangeWeaveEquilibrium", 6 })
        {
            var wire = new Dictionary<string, object?>(OverlayWorkspaceWireProjection.Settings(nightShadow)) { ["startupTransitionStyle"] = legacy };
            var parsed = OverlayWorkspaceWireProjection.ParseSettings(JsonSerializer.SerializeToElement(wire));
            Check(parsed.Skin == OverlaySkin.NightShadow && parsed.Theme == OverlayVisualTheme.NightShadow &&
                parsed.StartupTransitionStyle == OverlayStartupTransitionStyle.BridgeTerminal,
                "An archived transition alone keeps a valid Night Shadow appearance: " + legacy);
        }

        var csv = expected.Serialize().Split(',');
        csv[43] = csv[72] = csv[10] = "LagrangeWeave";
        csv[20] = "LagrangeWeaveEquilibrium";
        var oldSettings = string.Join(',', csv);
        var oldPreset = new OverlaySharedPreset(1, "Archived fixture", oldSettings,
            InformationOverlayLayoutItem.SerializeMany(layout));
        var shared = OverlaySharedPreset.Parse(oldPreset.Serialize());
        var normal = OverlaySharedPreset.Parse((oldPreset with { Settings = expected.Serialize() }).Serialize());
        Check(shared == normal, "Shared WPF v1 preset keeps its name and layout while migrating settings.");

        var root = Path.Combine(Environment.GetEnvironmentVariable("STARBRIDGE_DEBUG_DATA_ROOT") is { Length: > 0 } debugRoot ? debugRoot : Path.GetTempPath(), "cx80-migration-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        File.WriteAllText(Path.Combine(root, "overlay.settings"), oldSettings);
        File.WriteAllText(Path.Combine(root, "overlay.layout"), InformationOverlayLayoutItem.SerializeMany(layout));
        var workspace = new OverlayWorkspaceStore(root).Inspect();
        Check(workspace.Settings.Serialize() == expected.Serialize(), "Legacy workspace CSV migrates without changing unrelated settings.");
        Check(File.ReadAllText(Path.Combine(root, "overlay.settings")) == oldSettings, "Inspect never rewrites the old file.");
        Console.WriteLine("PASS CX-80 archived settings, shared presets and workspace JSON migrate without field loss");
    }

    private static void Check(bool value, string message)
    {
        if (!value) throw new InvalidOperationException(message);
    }
}
