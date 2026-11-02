using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class OverlaySourceBuildGateTests
{
    internal static async Task Run(bool expectedEnabled)
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-source-build-" + Guid.NewGuid().ToString("N"));
        try
        {
            using var dispatcher = new OverlayBridgeDispatcher(root, () => 1, () => GameLogSessionSnapshot.Empty);
            var read = (await dispatcher.DispatchAsync(BridgeEnvelope.Request("overlay.getWorkspace", "build-gate", 1,
                new { schemaVersion = 1 }))).Response;
            if (read.Status != "ok" || read.Payload.GetProperty("sourcePresetsEnabled").GetBoolean() != expectedEnabled)
                throw new Exception("Public composition source-presets gate does not match the requested build.");
            var savedRoot = Path.Combine(root, "saved-source-workspace");
            Directory.CreateDirectory(savedRoot);
            File.WriteAllText(Path.Combine(savedRoot, "overlay.settings"),
                StarBridge.Core.Overlay.OverlayDisplaySettings.Default.Serialize());
            new OverlayWorkspaceStore(savedRoot, enableSourcePresets: true).Load();
            var files = Directory.GetFiles(savedRoot, "*", SearchOption.AllDirectories)
                .ToDictionary(path => path, File.ReadAllBytes);
            if (!files.Keys.Any(path => path.EndsWith(".workspace.json", StringComparison.Ordinal)))
                throw new Exception("Regression fixture must contain a saved source-preset workspace.");
            using var saved = new OverlayBridgeDispatcher(savedRoot, () => 1, () => GameLogSessionSnapshot.Empty);
            var retained = (await saved.DispatchAsync(BridgeEnvelope.Request("overlay.getWorkspace", "saved-build-gate", 1,
                new { schemaVersion = 1 }))).Response;
            if (expectedEnabled ? retained.Status != "ok" ||
                    !retained.Payload.GetProperty("sourcePresetsEnabled").GetBoolean() :
                    retained.Error?.Code != "overlay.workspace_version_unsupported")
                throw new Exception("Compiled product composition must read saved presets or explicitly reject a diagnostic downgrade.");
            if (Directory.GetFiles(savedRoot, "*", SearchOption.AllDirectories).Length != files.Count ||
                files.Any(pair => !File.ReadAllBytes(pair.Key).SequenceEqual(pair.Value)))
                throw new Exception("Capability checks must not rewrite, delete or downgrade saved presets.");
            Console.WriteLine("PASS compiled product reads saved source workspaces without changing retained files");
            Console.WriteLine($"PASS public overlay composition source-presets build gate: {expectedEnabled}");
        }
        finally
        {
            if (Path.GetDirectoryName(Path.GetFullPath(root)) != Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) ||
                !Path.GetFileName(root).StartsWith("starbridge-source-build-", StringComparison.Ordinal)) throw new Exception("Unsafe test cleanup");
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }
}
