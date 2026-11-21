using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;

/// <summary>
/// 0.7.3 m102 (11-18 user: "0.7.3 做甲"): a preset the user never saved starts at the visor size the screen calls for;
/// a preset the user saved keeps its own size.
/// </summary>
internal static class OverlayVisorAutoSizeTests
{
    private static void Check(bool value, string name)
    {
        if (!value) throw new InvalidOperationException("FAIL visor auto size: " + name);
        Console.WriteLine("PASS visor auto size: " + name);
    }

    internal static Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-visor-autosize-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            static OverlayWorkspaceStore Store(string root, OverlayVisorSize? screen) =>
                new(root, enableSourcePresets: true, autoVisorSize: screen is { } size ? () => size : null);

            Check(Store(root, null).Load().Settings.VisorSize == OverlayVisorSize.Medium,
                "without a screen pick a preset never saved starts at the medium size, as before");
            Check(Store(root, OverlayVisorSize.Large).Load().Settings.VisorSize == OverlayVisorSize.Large,
                "a preset never saved starts at the size the screen calls for");

            foreach (var chosen in new[] { OverlayVisorSize.Small, OverlayVisorSize.Medium })
            {
                var store = Store(root, OverlayVisorSize.Large);
                var state = store.Load();
                store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.SaveActive,
                    Settings: state.Settings with { VisorSize = chosen }, Layout: state.Layout,
                    RenderMode: state.RenderMode, Hotkey: state.Hotkey));
                Check(Store(root, OverlayVisorSize.Large).Load().Settings.VisorSize == chosen,
                    $"a saved preset keeps its own size ({chosen}), whatever the screen calls for");
            }

            // a shipped preset (the fallback folder, never saved by the user) that names its size keeps it; one that names
            // none takes the screen's (review CX-OVERLAY-M102-R1 P2-6)
            foreach (var (fields, expected) in new[] { (96, OverlayVisorSize.Medium), (80, OverlayVisorSize.Large) })
            {
                var data = Path.Combine(root, "names-" + fields);
                var shipped = Path.Combine(root, "shipped-" + fields);
                Directory.CreateDirectory(data);
                Directory.CreateDirectory(shipped);
                var csv = string.Join(',', OverlayDisplaySettings.Default.Serialize().Split(',').Take(fields));
                File.WriteAllText(Path.Combine(shipped, "overlay.preset1.settings"), csv);
                // as the product store (OverlayBridgeDispatcher): the v2 folder, where a preset only shipped is not moved
                // into a saved document
                var loaded = new OverlayWorkspaceStore(data, shipped, enableSourcePresets: true,
                    overlayFolder: OverlayWorkspaceStore.V2Folder, autoVisorSize: () => OverlayVisorSize.Large).Load();
                Check(loaded.Settings.VisorSize == expected,
                    $"a shipped preset with {fields} fields starts {expected} on a large-size screen");
            }

            // the real probe never throws and picks medium or large
            var facts = OverlayScreenProbe.Read();
            var picked = OverlayVisorAutoSize.Pick(facts);
            Console.WriteLine($"INFO visor auto size: this screen {facts} -> {picked}");
            Check(picked is OverlayVisorSize.Medium or OverlayVisorSize.Large, "the screen probe answers medium or large");
        }
        finally
        {
            try { Directory.Delete(root, recursive: true); } catch (IOException) { }
        }
        return Task.CompletedTask;
    }
}
