using System.Text.Json;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class OverlayTemporarySourceBridgeTests
{
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-temporary-source-" + Guid.NewGuid().ToString("N"));
        try
        {
            var store = new OverlayWorkspaceStore(root, enableSourcePresets: true);
            var initial = store.Load();
            store.Apply(new(initial.Revision, OverlayWorkspaceMutationKind.ConfigurePresetSources,
                PresetId: initial.ActivePresetId, Sources: new(new(OverlaySourceMode.Room))));
            var runtime = new Runtime();
            (string? OwnerKey, long Generation) scope = ("owner", 1);
            using var host = new OverlayBridgeDispatcher(new OverlaySettingsStore(root), store, () => scope.Generation,
                () => GameLogSessionSnapshot.Empty, runtime, sourceScope: () => scope);
            async Task<BridgeEnvelope> Send(string name, object payload) =>
                (await host.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), scope.Generation, payload))).Response;
            object Wire(OverlaySourceBinding binding) => JsonSerializer.Deserialize<JsonElement>(OverlayPresetSourcesCodec.Serialize(new(binding)));
            async Task<BridgeEnvelope> Select(OverlaySourceBinding binding, string owner = "owner", long? revision = null) =>
                await Send("overlay.updateWorkspace", new { schemaVersion = 1, action = "temporarySource",
                    expectedRevision = revision ?? store.Load().Revision, ownerKey = owner, sources = Wire(binding) });
            var before = store.Load();
            Check((await Select(OverlaySourceBinding.Automatic)).Status == "ok", "Temporary choice accepted.");
            Check(store.Load().Revision == before.Revision && store.Load().Presets.Single().Sources!.Binding.Mode == OverlaySourceMode.Room,
                "Temporary choice writes neither preset policy nor revision.");
            Check(runtime.Last?.TemporarySource?.Choice.Mode == OverlaySourceMode.Auto, "Native runtime receives temporary intent.");
            var identity = new InformationOverlayModuleDemand(runtime.Last!.Sources, [OverlaySourceModule.Events], runtime.Last.TemporarySource).RefreshIdentity;
            Check(identity != new InformationOverlayModuleDemand(runtime.Last.Sources, [OverlaySourceModule.Events]).RefreshIdentity,
                "Temporary intent invalidates the shared refresh and event admission identity.");
            Check((await Select(new(OverlaySourceMode.Community, "ORG", "other"))).Status == "error" &&
                (await Select(OverlaySourceBinding.Automatic, "other")).Status == "error" &&
                (await Select(OverlaySourceBinding.Automatic, revision: before.Revision - 1)).Status == "error",
                "Wrong owner and stale revision cannot change intent.");
            Check(runtime.Last.TemporarySource!.Choice.Mode == OverlaySourceMode.Auto, "Rejected choices retain prior runtime intent.");
            var state = store.Load();
            var draft = new { expectedRevision = state.Revision, settings = OverlayWorkspaceWireProjection.Settings(state.Settings with { CrosshairOpacity = 0.37 }),
                layout = state.Layout.Select(OverlayWorkspaceWireProjection.Layout),
                hotkey = new { binding = state.Hotkey.Binding, enabled = state.Hotkey.Enabled }, sources = Wire(new(OverlaySourceMode.Room)) };
            Check((await Send("overlay.updateWorkspace", new { schemaVersion = 1, action = "temporarySource", expectedRevision = state.Revision,
                ownerKey = "owner", sources = Wire(OverlaySourceBinding.Automatic), workspace = draft })).Status == "ok" &&
                runtime.Last.Settings.CrosshairOpacity == 0.37 && store.Load().Settings.CrosshairOpacity == state.Settings.CrosshairOpacity,
                "Temporary selection carries the existing draft without saving or flashing saved layout.");
            Check((await Send("overlay.updateWorkspace", new { schemaVersion = 1, action = "renamePreset", expectedRevision = state.Revision,
                presetId = state.ActivePresetId, name = "Renamed" })).Status == "ok" && runtime.Last.TemporarySource is not null,
                "Metadata save preserves temporary selection on the same preset.");
            Check((await Select(OverlaySourceBinding.Follow)).Status == "ok" && runtime.Last.TemporarySource is null,
                "Explicit restore clears the temporary choice only.");
            await Select(OverlaySourceBinding.Automatic);
            state = store.Load();
            Check((await Send("overlay.updateWorkspace", new { schemaVersion = 1, action = "activatePreset", expectedRevision = state.Revision,
                presetId = state.ActivePresetId })).Status == "ok" && runtime.Last.TemporarySource is null,
                "An explicit preset activation, even the same preset, restores binding.");
            await Select(OverlaySourceBinding.Automatic);
            var old = runtime.Last.TemporarySource!;
            Check(old.ForScope("owner", 2) is null && old.ForScope("other", 1) is null,
                "Every consumer discards a temporary choice from an old account or generation.");
            scope = ("other", 2);
            await Send("overlay.runtime.getState", new { schemaVersion = 1 });
            Check(runtime.Last.TemporarySource is null, "Runtime synchronization clears old session intent.");
            scope = ("owner", 3);
            await Select(OverlaySourceBinding.Automatic);
            var restartedRuntime = new Runtime();
            using var restarted = new OverlayBridgeDispatcher(new OverlaySettingsStore(root), store, () => scope.Generation,
                () => GameLogSessionSnapshot.Empty, restartedRuntime, sourceScope: () => scope);
            await restarted.InitializeRuntimeAsync();
            Check(restartedRuntime.Last?.TemporarySource is null, "Restart does not restore temporary selection from disk.");
            Console.WriteLine("PASS temporary-source Bridge: draft, storage, owner, generation, revision, restore and restart");
        }
        finally
        {
            Check(Path.GetDirectoryName(Path.GetFullPath(root)) == Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) &&
                Path.GetFileName(root).StartsWith("starbridge-temporary-source-", StringComparison.Ordinal), "bounded cleanup");
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    private sealed class Runtime : IInformationOverlayRuntime
    {
        internal InformationOverlayRuntimeWorkspace? Last;
        public ValueTask<InformationOverlayRuntimeSnapshot> ExecuteAsync(InformationOverlayRuntimeCommand command,
            InformationOverlayRuntimeWorkspace workspace, CancellationToken cancellationToken = default)
        { Last = workspace; return ValueTask.FromResult(InformationOverlayRuntimeSnapshot.Unavailable); }
        public void Dispose() { }
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
