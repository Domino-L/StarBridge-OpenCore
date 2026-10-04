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
