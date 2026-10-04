using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class OverlayStartupIsolationTests
{
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-overlay-startup-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(root);
            File.WriteAllText(Path.Combine(root, "overlay.settings"), OverlayDisplaySettings.Default.Serialize());
            new OverlayWorkspaceStore(root, enableSourcePresets: true).Load();
            var files = Directory.GetFiles(root, "*", SearchOption.AllDirectories).ToDictionary(p => p, File.ReadAllBytes);
            using var runtime = new UnexpectedRuntime();
            using var dispatcher = new OverlayBridgeDispatcher(new OverlaySettingsStore(root),
                new OverlayWorkspaceStore(root), () => 1, () => GameLogSessionSnapshot.Empty, runtime);

            // This is the awaited startup call in NativeHost, before the composite bridge starts.
            await dispatcher.InitializeRuntimeAsync();
            var workspace = (await dispatcher.DispatchAsync(BridgeEnvelope.Request("overlay.getWorkspace", "workspace", 1,
                new { schemaVersion = 1 }))).Response;
            Check(workspace.Error?.Code == "overlay.workspace_version_unsupported", "Workspace must report incompatibility, not use stale legacy data.");
            var state = (await dispatcher.DispatchAsync(BridgeEnvelope.Request("overlay.getState", "state", 1,
                new { schemaVersion = 1 }))).Response;
            Check(state.Status == "ok", "An incompatible workspace must not prevent the bridge from serving other reads.");
            var open = (await dispatcher.DispatchAsync(BridgeEnvelope.Request("overlay.runtime.open", "open", 1,
                new { schemaVersion = 1 }))).Response;
            Check(open.Error?.Code == "overlay.workspace_version_unsupported", "Opening incompatible data must still fail closed.");
            Check(Directory.GetFiles(root, "*", SearchOption.AllDirectories).Length == files.Count &&
                files.All(pair => File.ReadAllBytes(pair.Key).SequenceEqual(pair.Value)), "Startup must not rewrite or roll back migrated files.");
            using var cancelled = new CancellationTokenSource();
            cancelled.Cancel();
            try { await dispatcher.InitializeRuntimeAsync(cancelled.Token); throw new Exception("Startup cancellation was swallowed."); }
            catch (OperationCanceledException) { }
            Console.WriteLine("PASS incompatible overlay workspace is isolated from Host startup without stale fallback or data changes");
        }
        finally
        {
            Check(Path.GetDirectoryName(Path.GetFullPath(root)) == Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) &&
                Path.GetFileName(root).StartsWith("starbridge-overlay-startup-", StringComparison.Ordinal), "Unsafe cleanup");
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    private sealed class UnexpectedRuntime : IInformationOverlayRuntime
    {
        public ValueTask<InformationOverlayRuntimeSnapshot> ExecuteAsync(InformationOverlayRuntimeCommand command,
            InformationOverlayRuntimeWorkspace workspace, CancellationToken cancellationToken = default) =>
            throw new Exception("An incompatible workspace must never reach native rendering.");
        public void Dispose() { }
    }
}
