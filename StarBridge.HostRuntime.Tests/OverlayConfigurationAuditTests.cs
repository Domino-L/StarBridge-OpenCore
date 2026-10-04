using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;

internal static class OverlayConfigurationAuditTests
{
    internal static Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-overlay-audit-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            CrosshairOpacityRoundTrip(Path.Combine(root, "fractional-opacity"));
            var store = new OverlayWorkspaceStore(root);
            foreach (var payload in new[] {
                "Notice,NaN,0,0.2,0.2;Squads,0,0,0.2,0.2;Members,0,0,0.2,0.2;Chat,0,0,0.2,0.2",
                "Notice,0,0,0.2,0.2;Squads,0,0,0.2,0.2;Members,0,0,NaN,0.2;Chat,0,0,0.2,0.2",
                "Notice,0,0,0.2,0.2;Members,0,0,0.2,0.2;Members,0,0,0.3,0.3;UnknownModule,0,0,0.2,0.2",
                " ,0,0,0.2,0.2;Members,0,0,0.2,0.2" })
            {
                var path = Path.Combine(root, "overlay.layout");
                File.WriteAllText(path, payload);
                var loaded = store.Load();
                Check(loaded.Layout.Count == 4 && loaded.Layout.Select(x => x.Key).Distinct(StringComparer.OrdinalIgnoreCase).Count() == 4,
                    "damaged legacy layout must restore all four known modules without duplicates/unknown keys");
                foreach (var item in loaded.Layout)
                {
                    var rect = InformationOverlayLayoutGeometry.ResolveItemRect(item, 1920, 1080);
                    Check(double.IsFinite(rect.Left) && double.IsFinite(rect.Top) && double.IsFinite(rect.Width) && double.IsFinite(rect.Height),
                        "legacy NaN must never reach the actual rendering geometry");
                }
                Check(loaded.StorageState == "recoveredDefaults", "repaired layout is reported honestly");
                Check(File.ReadAllText(path) == payload, "read-only recovery must preserve the original legacy file");
            }
            return Task.CompletedTask;
        }
        finally
        {
            var resolved = Path.GetFullPath(root);
            Check(Path.GetDirectoryName(resolved) == Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) &&
                Path.GetFileName(resolved).StartsWith("starbridge-overlay-audit-", StringComparison.Ordinal), "cleanup remains inside the exact test fixture directory");
            Directory.Delete(resolved, true);
        }
    }
    private static void CrosshairOpacityRoundTrip(string root)
    {
        var store = new OverlayWorkspaceStore(root);
        foreach (var pair in new[] { (0.6, 0.4), (1.0, 0.0), (0.37, 0.13) })
        {
            var loaded = store.Load();
            var wire = new Dictionary<string, object?>(OverlayWorkspaceWireProjection.Settings(loaded.Settings))
            {
                ["showCrosshair"] = true,
                ["crosshairOpacity"] = pair.Item1,
                ["crosshairOutlineOpacity"] = pair.Item2,
            };
            var parsed = OverlayWorkspaceWireProjection.ParseSettings(System.Text.Json.JsonSerializer.SerializeToElement(wire));
            store.Apply(new OverlayWorkspaceMutation(loaded.Revision, OverlayWorkspaceMutationKind.SaveActive,
                Settings: parsed, Layout: loaded.Layout, RenderMode: loaded.RenderMode, Hotkey: loaded.Hotkey));
            var restored = new OverlayWorkspaceStore(root).Load().Settings;
            Check(Math.Abs(restored.CrosshairOpacity - pair.Item1) < 0.00001 &&
                Math.Abs(restored.CrosshairOutlineOpacity - pair.Item2) < 0.00001,
                "wire validation, save and fresh reload preserve fractional crosshair opacities");
        }
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
