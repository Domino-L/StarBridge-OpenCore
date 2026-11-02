using System.Text.Json;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class OverlayAppearanceOptionsTests
{
    // Generic fixture, not a private appearance schema or an entitlement.
    private static readonly OverlayAppearanceOptions Choice = OverlayAppearanceOptions.Parse(
        """{"schemaVersion":1,"profiles":{"example":{"version":1,"values":{"items":[{"module":"Squads","slot":0,"kind":2}]}}}}""");
    internal static async Task Run()
    {
        foreach (var invalid in new[] { "", "{}", "null",
            """{"schemaVersion":2,"profiles":{}}""",
            """{"schemaVersion":1,"profiles":{},"profiles":{}}""",
            """{"schemaVersion":1,"profiles":{"example":{"version":0,"values":{}}}}""",
            """{"schemaVersion":1,"profiles":{"example":{"version":1,"values":{"a":1,"a":2}}}}""",
            """{"schemaVersion":1,"profiles":{"example":{"version":1,"values":{"__proto__":{}}}}}""",
            """{"schemaVersion":1,"profiles":{"example":{"version":1,"values":{"n":1e999}}}}""",
            new string('x', OverlayAppearanceOptions.MaximumBytes + 1),
            "{\"schemaVersion\":1,\"profiles\":{\"example\":{\"version\":1,\"values\":{\"long\":\"" + new string('x',257) + "\"}}}}" })
        {
            try { OverlayAppearanceOptions.Parse(invalid); throw new InvalidOperationException("Accepted invalid options"); }
            catch (FormatException) { }
        }
        Check(!OverlayWorkspaceWireProjection.Settings(OverlayDisplaySettings.Default).ContainsKey("appearanceOptions"), "CSV/wire field list unchanged");
        foreach (var versioned in new[] { false, true }) await Exercise(versioned);
        Console.WriteLine("PASS appearance options: bounded envelope, legacy/v2 owner, lifecycle, transactions, Bridge/draft/runtime projection");
    }

    private static async Task Exercise(bool versioned)
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-appearance-options-" + Guid.NewGuid().ToString("N"));
        try
        {
            var store = new OverlayWorkspaceStore(root, enableSourcePresets: versioned);
            var state = store.Load();
            Check(state.Settings.AppearanceOptions == OverlayAppearanceOptions.Empty && !Directory.Exists(root), "Empty shell without writes");
            var csv = state.Settings.Serialize();
            OverlayWorkspaceReadResult Save(OverlayAppearanceOptions? options = null) => store.Apply(new(
                state.Revision, OverlayWorkspaceMutationKind.SaveActive, Settings: state.Settings,
                Layout: state.Layout, RenderMode: state.RenderMode, Hotkey: state.Hotkey, AppearanceOptions: options));
            state = Save(Choice);
            var original = state.ActivePresetId;
            Check(state.Settings.AppearanceOptions == Choice && state.Settings.Serialize() == csv, "Save is not CSV extension");
            state = new OverlayWorkspaceStore(root, enableSourcePresets: versioned).Load();
            Check(state.Settings.AppearanceOptions == Choice, "New store reopens saved options");
            state = Save();
            Check(state.Settings.AppearanceOptions == Choice, "Old draft omission preserves options");
            var before = state.Revision;
            try { store.Apply(new(before - 1, OverlayWorkspaceMutationKind.SaveActive, AppearanceOptions: OverlayAppearanceOptions.Empty)); throw new InvalidOperationException("Stale save allowed"); }
            catch (OverlaySettingsException error) { Check(error.Code == "overlay.workspace_revision_conflict", "revision guard"); }
            var currentChecks = 0;
            try
            {
                store.Apply(new(before, OverlayWorkspaceMutationKind.SaveActive, Settings: state.Settings, Layout: state.Layout,
                    RenderMode: state.RenderMode, Hotkey: state.Hotkey, AppearanceOptions: OverlayAppearanceOptions.Empty), () => ++currentChecks < 3);
                throw new InvalidOperationException("Stale durable transaction allowed");
            }
            catch (OverlaySettingsException error) { Check(error.Code == "overlay.workspace_revision_conflict", "transaction guard"); }
            Check(store.Load().Revision == before && store.Load().Settings.AppearanceOptions == Choice, "Options rollback with settings/layout");

            state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.DuplicatePreset, Name: "Copy"));
            var copy = state.Presets.Single(p => p.Name == "Copy");
            Check(copy.Settings.AppearanceOptions == Choice, "Duplicate copies independent choices");
            state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.ActivatePreset, PresetId: copy.Id));
            state = Save(OverlayAppearanceOptions.Empty);
            Check(state.Presets.Single(p => p.Id == original).Settings.AppearanceOptions == Choice, "Copy edit leaves original intact");
            state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.ActivatePreset, PresetId: original));
            Check(state.Settings.AppearanceOptions == Choice, "Activation restores owner choices");
            state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.ImportPreset, Name: "Imported", Settings: state.Settings,
                Layout: state.Layout, AppearanceOptions: Choice));
            Check(state.Presets.Single(p => p.Name == "Imported").Settings.AppearanceOptions == Choice, "Explicit import includes options");

            var runtime = new Runtime();
            using var host = new OverlayBridgeDispatcher(new OverlaySettingsStore(root), store, () => 1,
                () => GameLogSessionSnapshot.Empty, runtime);
            async Task<BridgeEnvelope> Send(string request, object payload) =>
                (await host.DispatchAsync(BridgeEnvelope.Request(request, Guid.NewGuid().ToString("N"), 1, payload))).Response;
            await host.InitializeRuntimeAsync();
            Check(runtime.Last?.Settings.AppearanceOptions == Choice, "Initialize runtime receives persisted options");
            var read = await Send("overlay.getWorkspace", new { schemaVersion = 1 });
            Check(read.Payload.GetProperty("appearanceOptions").GetRawText() == Choice.Json, "Read advertises active options");
            Check(read.Payload.GetProperty("appearanceOptionsEnabled").GetBoolean(), "Read advertises option-editing support separately from eligibility");
            var catalog = read.Payload.GetProperty("appearances").GetRawText();
            Check(read.Payload.GetProperty("appearanceConfigurations").GetArrayLength() == 0, "No installed configuration invents a form");
            using (var description = JsonDocument.Parse("""{"schemaVersion":1,"profileId":"example"}"""))
                runtime.Descriptions = [description.RootElement.Clone()];
            read = await Send("overlay.getWorkspace", new { schemaVersion = 1 });
            Check(read.Payload.GetProperty("appearanceConfigurations")[0].GetProperty("profileId").GetString() == "example"
                && read.Payload.GetProperty("appearances").GetRawText() == catalog, "Description travels separately without catalog/eligibility changes");
            JsonElement Element(object value) => JsonSerializer.SerializeToElement(value);
            foreach (var excessive in new JsonElement[][] {
                Enumerable.Repeat(Element(new { slot = 1 }), 9).ToArray(),
                [Element(new { text = new string('x', 49 * 1024) })],
                [Element(new { text = new string('x', 34 * 1024) }), Element(new { text = new string('x', 34 * 1024) })],
                [Element("not a form")] })
            {
                runtime.Descriptions = excessive;
                read = await Send("overlay.getWorkspace", new { schemaVersion = 1 });
                Check(read.Status == "ok" && read.Payload.GetProperty("appearanceConfigurations").GetArrayLength() == 0
                    && read.Payload.GetProperty("appearanceOptions").GetRawText() == Choice.Json, "Invalid metadata cannot disable workspace or overwrite saved values");
            }
            runtime.Descriptions = [];
            var draft = new { expectedRevision = state.Revision, settings = OverlayWorkspaceWireProjection.Settings(state.Settings),
                layout = state.Layout.Select(OverlayWorkspaceWireProjection.Layout), hotkey = new { binding = "Alt+O", enabled = true },
                appearanceOptions = OverlayAppearanceOptions.Empty.ToElement() };
            Check((await Send("overlay.runtime.open", new { schemaVersion = 1, workspace = draft })).Status == "ok" &&
                runtime.Last!.Settings.AppearanceOptions == OverlayAppearanceOptions.Empty && store.Load().Revision == state.Revision,
                "Unsaved preview options reach runtime without persistence");
            Check((await Send("overlay.runtime.open", new { schemaVersion = 1 })).Status == "ok" && runtime.Last!.Settings.AppearanceOptions == Choice,
                "Saved open restores choices after draft");
            var bad = await Send("overlay.updateWorkspace", new { schemaVersion = 1, action = "saveActive", expectedRevision = state.Revision,
                settings = OverlayWorkspaceWireProjection.Settings(state.Settings), layout = state.Layout.Select(OverlayWorkspaceWireProjection.Layout),
                renderMode = state.RenderMode, hotkey = new { binding = "Alt+O", enabled = true }, appearanceOptions = new { schemaVersion = 99, profiles = new { } } });
            Check(bad.Error?.Code == "overlay.workspace_invalid_value" && store.Load().Revision == state.Revision, "Invalid options never save");
            var saved = await Send("overlay.updateWorkspace", new { schemaVersion = 1, action = "saveActive", expectedRevision = state.Revision,
                settings = OverlayWorkspaceWireProjection.Settings(state.Settings), layout = state.Layout.Select(OverlayWorkspaceWireProjection.Layout),
                renderMode = state.RenderMode, hotkey = new { binding = "Alt+O", enabled = true }, appearanceOptions = OverlayAppearanceOptions.Empty.ToElement() });
            Check(saved.Status == "ok" && runtime.Last!.Settings.AppearanceOptions == OverlayAppearanceOptions.Empty &&
                store.Load().Settings.AppearanceOptions == OverlayAppearanceOptions.Empty, "Bridge save synchronizes persisted owner to runtime");
            state = store.Load(); state = Save(Choice);
            var path = Path.Combine(root, $"overlay.{original}.appearance.json");
            File.WriteAllText(path, "{invalid"); // Bounded synthetic fixture, never a product/account file.
            state = store.Load();
            Check(state.StorageState == "corrupt", "Corruption quarantined, no legacy fallback");
            await host.InitializeRuntimeAsync();
            Check(runtime.Last!.IsPresetCorrupt && runtime.Last.HasInvalidConfiguration, "Corrupt legacy/v2 preset sync explicitly disables runtime");
            var renamed = await Send("overlay.updateWorkspace", new { schemaVersion = 1, action = "renamePreset", expectedRevision = state.Revision,
                presetId = original, name = "Damaged" });
            Check(renamed.Status == "ok" && runtime.Last!.HasInvalidConfiguration, "Metadata write succeeds but cannot activate a damaged preset");
            Check((await Send("overlay.runtime.open", new { schemaVersion = 1 })).Error?.Code == "overlay.workspace_invalid_preset", "No draft/open override for corrupt preset");
            state = store.Load();
            state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.ResetPreset, PresetId: original));
            Check(state.Settings.AppearanceOptions == OverlayAppearanceOptions.Empty && state.StorageState != "corrupt" &&
                Directory.GetFiles(root, "overlay.recovered-*.json").Any(p => File.ReadAllText(p) == "{invalid"), "Reset archives damaged config, returns empty shell");
            state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.DeletePreset, PresetId: copy.Id));
            Check(!File.Exists(Path.Combine(root, $"overlay.{copy.Id}.appearance.json")), "Delete removes only deleted preset config");
        }
        finally
        {
            Check(Path.GetDirectoryName(Path.GetFullPath(root)) == Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar)
                && Path.GetFileName(root).StartsWith("starbridge-appearance-options-", StringComparison.Ordinal), "Bounded test cleanup");
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }
    private sealed class Runtime : IInformationOverlayRuntime, IInformationOverlayAppearanceConfigurationCatalog
    {
        internal InformationOverlayRuntimeWorkspace? Last;
        internal IReadOnlyList<JsonElement> Descriptions = [];
        public IReadOnlyList<JsonElement> GetAppearanceConfigurations() => Descriptions;
        public ValueTask<InformationOverlayRuntimeSnapshot> ExecuteAsync(InformationOverlayRuntimeCommand command,
            InformationOverlayRuntimeWorkspace workspace, CancellationToken cancellationToken = default)
        { Last = workspace; return ValueTask.FromResult(InformationOverlayRuntimeSnapshot.Unavailable); }
        public void Dispose() { }
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
