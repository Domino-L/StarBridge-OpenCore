using System.Text.Json;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class OverlayPresetSourceBridgeTests
{
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-source-bridge-" + Guid.NewGuid().ToString("N"));
        try
        {
            var store = new OverlayWorkspaceStore(root, enableSourcePresets: true);
            var runtime = new Runtime();
            OverlayPresetTrigger? trigger = new("owner", 1, "room:one");
            Func<OverlayPresetTrigger?> readTrigger = () => trigger;
            using var host = new OverlayBridgeDispatcher(new OverlaySettingsStore(root), store, () => 1,
                () => GameLogSessionSnapshot.Empty, runtime, () => readTrigger());
            async Task<BridgeEnvelope> Send(string name, object payload) =>
                (await host.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), 1, payload))).Response;
            var initial = await Send("overlay.getWorkspace", new { schemaVersion = 1 });
            Check(initial.Status == "ok" && initial.Payload.TryGetProperty("sourcePresetsEnabled", out var enabled) && enabled.GetBoolean(),
                "Bridge advertises the enabled source contract rather than silently dropping its policy.");
            var state = store.Load();
            var sources = new OverlayPresetSources(new(OverlaySourceMode.Room), false,
                new Dictionary<OverlaySourceModule, OverlaySourceBinding> { [OverlaySourceModule.Chat] = OverlaySourceBinding.Automatic });
            var wire = JsonSerializer.Deserialize<JsonElement>(OverlayPresetSourcesCodec.Serialize(sources));
            var changed = await Send("overlay.updateWorkspace", new { schemaVersion = 1, expectedRevision = state.Revision,
                action = "configurePresetSources", presetId = state.ActivePresetId, sources = wire, name = "Configured" });
            Check(changed.Status == "ok", "Preset-source edits cross the real Bridge dispatcher.");
            var stored = store.Load();
            Check(stored.Presets.Single().Name == "Configured", "Name and source are stored in one settings transaction.");
            Check(stored.Presets.Single().Sources!.Binding.Mode == OverlaySourceMode.Room &&
                runtime.Last?.Sources?.Modules[OverlaySourceModule.Chat].Mode == OverlaySourceMode.Auto,
                "A successful edit stores and synchronizes exactly the same source policy.");
            var sourceResponse = changed.Payload.GetProperty("presets")[0].GetProperty("sources");
            Check(OverlayPresetSourcesCodec.Parse(sourceResponse.GetRawText()).Binding == sources.Binding, "Wire response round trips policy.");
            var draft = new { expectedRevision = stored.Revision, settings = OverlayWorkspaceWireProjection.Settings(stored.Settings),
                layout = stored.Layout.Select(OverlayWorkspaceWireProjection.Layout),
                hotkey = new { binding = stored.Hotkey.Binding, enabled = stored.Hotkey.Enabled },
                sources = JsonSerializer.Deserialize<JsonElement>(OverlayPresetSourcesCodec.Serialize(OverlayPresetSources.Default)) };
            var preview = await Send("overlay.runtime.getState", new { schemaVersion = 1, workspace = draft });
            Check(preview.Status == "ok" && runtime.Last?.Sources?.Binding.Mode == OverlaySourceMode.None &&
                store.Load().Revision == stored.Revision && store.Load().Presets.Single().Sources!.Binding.Mode == OverlaySourceMode.Room,
                "Unsaved source preview is runtime-only; it never writes or grants membership.");
            var malformed = await Send("overlay.updateWorkspace", new { schemaVersion = 1, expectedRevision = stored.Revision,
                action = "configurePresetSources", presetId = stored.ActivePresetId, sources = new { schemaVersion = 2 } });
            Check(malformed.Status == "error" && malformed.Error?.Code == "overlay.workspace_invalid_value" && store.Load().Revision == stored.Revision,
                "Malformed sources are rejected before writes with a validation error, not a retryable read failure.");
            var invalidName = await Send("overlay.updateWorkspace", new { schemaVersion = 1, expectedRevision = stored.Revision,
                action = "configurePresetSources", presetId = stored.ActivePresetId, sources = wire, name = "" });
            Check(invalidName.Status == "error" && store.Load().Revision == stored.Revision,
                "Invalid name cannot partially commit a source edit.");
            var stale = await Send("overlay.updateWorkspace", new { schemaVersion = 1, expectedRevision = state.Revision,
                action = "configurePresetSources", presetId = state.ActivePresetId, sources = wire });
            Check(stale.Status == "error" && stale.Error?.Code == "overlay.workspace_revision_conflict", "Stale source save cannot overwrite newer policy.");
            async Task<BridgeEnvelope> Auto(string owner, long generation, string source) => await Send("overlay.updateWorkspace",
                new { schemaVersion = 1, expectedRevision = store.Load().Revision, action = "activatePreset",
                    presetId = stored.ActivePresetId, automaticSource = new { ownerKey = owner, generation, source } });
            var beforeAuto = store.Load().Revision;
            foreach (var guard in new[] { ("other", 1L, "room:one"), ("owner", 2L, "room:one"), ("owner", 1L, "room:old") })
                Check((await Auto(guard.Item1, guard.Item2, guard.Item3)).Error?.Code == "overlay.workspace_revision_conflict",
                    "Automatic activation rechecks owner, generation and current source at the Host write boundary.");
            trigger = null;
            Check((await Auto("owner", 1, "room:one")).Status == "error" && store.Load().Revision == beforeAuto,
                "Expired/unknown trigger cannot activate a preset or modify the workspace.");
            trigger = new("owner", 1, "room:one");
            Check((await Auto("owner", 1, "room:one")).Status == "ok", "A current trigger uses the ordinary atomic preset activation.");
            store.Apply(new(store.Load().Revision, OverlayWorkspaceMutationKind.CreatePreset, Name: "Another"));
            foreach (var invalidAt in new[] { 3, 4 })
            {
                var before = store.Load();
                var checks = 0;
                readTrigger = () => ++checks >= invalidAt ? null : trigger;
                var rejectedActivation = await Auto("owner", 1, "room:one");
                Check(rejectedActivation.Error?.Code == "overlay.workspace_revision_conflict" && checks == invalidAt &&
                    store.Load().Revision == before.Revision && store.Load().ActivePresetId == before.ActivePresetId,
                    "Source changes during staged/durable writes roll back before runtime publication.");
            }
            readTrigger = () => trigger;
            var disabledRoot = Path.Combine(root, "disabled");
            using var disabled = new OverlayBridgeDispatcher(new OverlaySettingsStore(disabledRoot),
                new OverlayWorkspaceStore(disabledRoot), () => 1, () => GameLogSessionSnapshot.Empty);
            var disabledState = new OverlayWorkspaceStore(disabledRoot).Load();
            var rejected = (await disabled.DispatchAsync(BridgeEnvelope.Request("overlay.updateWorkspace", Guid.NewGuid().ToString("N"), 1,
                new { schemaVersion = 1, expectedRevision = disabledState.Revision, action = "configurePresetSources",
                    presetId = disabledState.ActivePresetId, sources = wire }))).Response;
            Check(rejected.Status == "error" && !Directory.Exists(disabledRoot), "Wire input cannot enable the production migration gate.");
            Console.WriteLine("PASS preset-source Bridge read, save, runtime-only draft, validation, revision and disabled gate");
        }
        finally
        {
            Check(Path.GetDirectoryName(Path.GetFullPath(root)) == Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar)
                && Path.GetFileName(root).StartsWith("starbridge-source-bridge-", StringComparison.Ordinal), "bounded cleanup");
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
