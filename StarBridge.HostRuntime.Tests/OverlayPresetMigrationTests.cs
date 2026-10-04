using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static class OverlayPresetMigrationTests
{
    internal static Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-preset-migration-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            foreach (var preference in new[] { OverlayScenePreference.Auto, OverlayScenePreference.PartyRoom, OverlayScenePreference.Fleet })
                Migration(Path.Combine(root, preference.ToString()), preference);
            Lifecycle(Path.Combine(root, "lifecycle"));
            Corruption(Path.Combine(root, "corruption"));
            FallbackAndRollback(Path.Combine(root, "fallback"));
            InterruptedMigrationResumes(Path.Combine(root, "interrupted"));
            RecoveredAndConcurrent(Path.Combine(root, "recovered"));
            AtomicSourceAssignment(Path.Combine(root, "assignment"));
            MultiChatLifecycle(Path.Combine(root, "multi-chat"));
            Console.WriteLine("PASS v2 preset migration, lifecycle, transfer sanitization and fail-closed storage");
            return Task.CompletedTask;
        }
        finally
        {
            Check(Path.GetDirectoryName(Path.GetFullPath(root)) == Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar)
                && Path.GetFileName(root).StartsWith("starbridge-preset-migration-", StringComparison.Ordinal), "bounded test cleanup");
            Directory.Delete(root, true);
        }
    }

    private static OverlayWorkspaceStore Store(string root, string? fallback = null) => new(root, fallback, enableSourcePresets: true);
    private static string DocumentPath(string root, string id) => Path.Combine(root, $"overlay.{id}.workspace.json");
    private static OverlayDisplaySettings Settings(OverlayScenePreference preference)
    {
        var wire = new Dictionary<string, object?>(OverlayWorkspaceWireProjection.Settings(OverlayDisplaySettings.Default))
        {
            ["scenePreference"] = preference.ToString(), ["crosshairOpacity"] = 0.37, ["crosshairOutlineOpacity"] = 0.13
        };
        return OverlayWorkspaceWireProjection.ParseSettings(JsonSerializer.SerializeToElement(wire));
    }
    private static void Seed(string root, OverlayScenePreference preference)
    {
        Directory.CreateDirectory(root);
        File.WriteAllText(Path.Combine(root, "overlay.settings"), Settings(preference).Serialize());
        File.WriteAllText(Path.Combine(root, "overlay.layout"), InformationOverlayLayoutItem.SerializeMany(InformationOverlayDefaults.CreateLayout("preset1")));
        File.WriteAllText(Path.Combine(root, "overlay.scene-choice.fixture"), "account-choice-must-stay-identical");
    }
    private static void Migration(string root, OverlayScenePreference preference)
    {
        Seed(root, preference);
        var originals = Directory.GetFiles(root).ToDictionary(path => Path.GetFileName(path)!, File.ReadAllText);
        var owner = new BridgeAccountContext("test", "scm", "synthetic-migration-owner");
        var otherOwner = owner with { Subject = "synthetic-migration-other" };
        var choices = new OverlaySceneChoiceStore(root);
        choices.Save(owner, 0, "community", "synthetic-community", () => true);
        choices.Save(otherOwner, 0, "room", null, () => true);
        var accountFiles = Directory.GetFiles(Path.Combine(root, "overlay-source-v1")).ToDictionary(path => path, File.ReadAllBytes);
        var legacy = new OverlayWorkspaceStore(root).Load();
        Check(!File.Exists(DocumentPath(root, legacy.ActivePresetId)), "production gate leaves legacy read-only");
        var migrated = Store(root).Load();
        var preset = migrated.Presets.Single();
        Check(preset.Sources!.Binding.Mode == (preference == OverlayScenePreference.PartyRoom ? OverlaySourceMode.Room : OverlaySourceMode.None), "C11 legacy mapping");
        Check(!preset.Sources.AutoSwitch && preset.Sources.Modules.Values.All(binding => binding.Mode == OverlaySourceMode.None), "migration does not enable auto switch or module overrides");
        Check(Math.Abs(preset.Settings.CrosshairOpacity - 0.37) < 0.000001 && Math.Abs(preset.Settings.CrosshairOutlineOpacity - 0.13) < 0.000001, "all numeric settings survive migration");
        Check(InformationOverlayLayoutItem.SerializeMany(preset.Layout) == InformationOverlayLayoutItem.SerializeMany(legacy.Layout), "layout survives migration");
        var path = DocumentPath(root, preset.Id);
        var payload = File.ReadAllText(path);
        Check(!payload.Contains("scenePreference", StringComparison.Ordinal), "v2 has no retired scenePreference field");
        var legacyWire = new Dictionary<string, object?>(OverlayWorkspaceWireProjection.Settings(legacy.Settings));
        var migratedWire = new Dictionary<string, object?>(OverlayWorkspaceWireProjection.Settings(preset.Settings));
        legacyWire.Remove("scenePreference");
        migratedWire.Remove("scenePreference");
        Check(JsonSerializer.Serialize(legacyWire) == JsonSerializer.Serialize(migratedWire), "every non-source settings field survives migration");
        var stamp = File.GetLastWriteTimeUtc(path);
        var again = Store(root).Load();
        Check(again.Revision == migrated.Revision && File.ReadAllText(path) == payload && File.GetLastWriteTimeUtc(path) == stamp, "repeat reads are idempotent and do not rewrite");
        foreach (var (name, text) in originals)
        {
            Check(File.ReadAllText(Path.Combine(root, name!)) == text, "migration never rewrites old source/account files");
            Check(File.ReadAllText(Path.Combine(root, "overlay.workspace-backup-v2", name!)) == text, "migration has original backup");
        }
        foreach (var (accountPath, bytes) in accountFiles)
            Check(File.ReadAllBytes(accountPath).SequenceEqual(bytes), "real account source store bytes remain unchanged for both accounts");
        Check(choices.Read(owner).Code == "synthetic-community" && choices.Read(otherOwner).Mode == "room", "account choices remain isolated");
        ExpectFailure(() => new OverlayWorkspaceStore(root).Load(), "disabled consumer cannot silently read stale legacy after v2 migration");
        var activated = Store(root).Apply(new(again.Revision, OverlayWorkspaceMutationKind.ActivatePreset, PresetId: preset.Id));
        Check(OverlayDisplaySettings.Parse(File.ReadAllText(Path.Combine(root, "overlay.settings"))).ScenePreference ==
            (preference == OverlayScenePreference.PartyRoom ? OverlayScenePreference.PartyRoom : OverlayScenePreference.Auto),
            "legacy compatibility projection preserves room binding");
        var olderDocument = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        olderDocument["settings"]!.AsObject().Remove("crosshairOpacity");
        File.WriteAllText(path, olderDocument.ToJsonString());
        var extended = Store(root).Load();
        Check(extended.StorageState == "recoveredDefaults" && Math.Abs(extended.Settings.CrosshairOutlineOpacity - 0.13) < 0.000001,
            "missing known display field uses default without losing other fields");
    }

    private static OverlayWorkspaceReadResult Save(OverlayWorkspaceStore store, OverlayWorkspaceReadResult state, OverlayPresetSources? sources = null) =>
        store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.SaveActive, Settings: state.Settings,
            Layout: state.Layout, RenderMode: state.RenderMode, Hotkey: state.Hotkey, Sources: sources));

    private static void Lifecycle(string root)
    {
        var store = Store(root);
        var state = store.Load();
        Check(!Directory.Exists(root), "empty reads create nothing");
        var binding = new OverlaySourceBinding(OverlaySourceMode.Community, "test-community", "test-owner");
        var policy = new OverlayPresetSources(binding, true, new Dictionary<OverlaySourceModule, OverlaySourceBinding>
        { [OverlaySourceModule.Chat] = binding, [OverlaySourceModule.Members] = new(OverlaySourceMode.Room) });
        state = Save(store, state, policy);
        var firstId = state.ActivePresetId;
        Check(!File.Exists(Path.Combine(root, $"overlay.{firstId}.settings")), "new presets do not write legacy per-preset CSV");
        state = Save(store, state);
        Check(OverlayPresetSourcesCodec.Serialize(state.Presets.Single().Sources!) == OverlayPresetSourcesCodec.Serialize(policy), "old save callers cannot erase source policy");
        var revision = state.Revision;
        state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.DuplicatePreset, Name: "Copy"));
        var copy = state.Presets.Single(preset => preset.Id != firstId);
        Check(copy.Sources!.Binding == binding && !copy.Sources.AutoSwitch, "copy retains binding but does not duplicate unique auto switch");
        ExpectFailure(() => Save(store, state with { Revision = revision }), "stale revision rejected");
        state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.ActivatePreset, PresetId: copy.Id));
        var beforeConflict = File.ReadAllText(DocumentPath(root, copy.Id));
        ExpectFailure(() => Save(store, state, policy), "auto switch collision rejected without implicit reassignment");
        Check(File.ReadAllText(DocumentPath(root, copy.Id)) == beforeConflict, "rejected policy leaves file intact");
        state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.RenamePreset, PresetId: copy.Id, Name: "Renamed"));
        Check(state.Presets.Single(p => p.Id == copy.Id).Sources!.Binding == binding, "rename preserves policy");
        state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.ImportPreset, Name: "Imported",
            Settings: state.Settings, Layout: state.Layout, Sources: policy));
        var imported = state.Presets.Single(p => p.Name == "Imported");
        Check(state.RemovedOrganizationBindings, "import result preserves the removed-binding notice for its caller");
        Check(state.ActivePresetId == copy.Id, "import is additive and never activates");
        var importedText = File.ReadAllText(DocumentPath(root, imported.Id));
        Check(!importedText.Contains("test-community") && !importedText.Contains("test-owner"), "inbound org identifiers stripped before disk write");
        Check(imported.Sources!.Binding.Mode == OverlaySourceMode.Auto && !imported.Sources.AutoSwitch
            && imported.Sources.Modules[OverlaySourceModule.Chat].Mode == OverlaySourceMode.Auto
            && imported.Sources.Modules[OverlaySourceModule.Members].Mode == OverlaySourceMode.Room, "import sanitizes only org bindings");
        state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.ResetPreset, PresetId: copy.Id));
        Check(state.Presets.Single(p => p.Id == copy.Id).Sources!.Binding.Mode == OverlaySourceMode.None, "reset restores follow-account policy");
        state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.DeletePreset, PresetId: copy.Id));
        Check(!File.Exists(DocumentPath(root, copy.Id)) && state.ActivePresetId != copy.Id, "delete removes v2 document and switches active preset");
        state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.CreatePreset, Name: "New"));
        Check(state.Presets.Single(p => p.IsActive).Sources!.Binding.Mode == OverlaySourceMode.None, "new preset defaults to follow account");
    }

    private static void MultiChatLifecycle(string root)
    {
        var store = Store(root);
        var initial = store.Load();
        var org = new OverlaySourceBinding(OverlaySourceMode.Community, "multi-org", "multi-owner");
        var policy = new OverlayPresetSources(org, true, chatSources: [new(OverlaySourceMode.Room), org]);
        var saved = Save(store, initial, policy);
        var reloaded = Store(root).Load();
        Check(OverlayPresetSourcesCodec.Serialize(reloaded.Presets.Single().Sources!) == OverlayPresetSourcesCodec.Serialize(policy),
            "Multi-chat v3 survives actual save and restart without changing selection.");
        var duplicate = store.Apply(new(saved.Revision, OverlayWorkspaceMutationKind.DuplicatePreset, Name: "Multi copy"));
        Check(duplicate.Presets.Single(p => p.Name == "Multi copy").Sources is { AutoSwitch: false, ChatSources.Count: 2 },
            "Duplicating a preset disables automatic switching without losing chat selection.");
        var imported = store.Apply(new(duplicate.Revision, OverlayWorkspaceMutationKind.ImportPreset, Name: "Multi imported",
            Settings: saved.Settings, Layout: saved.Layout, Sources: policy));
        var safe = imported.Presets.Single(p => p.Name == "Multi imported");
        Check(safe.Sources is { AutoSwitch: false, ChatSources.Count: 0 } && safe.Sources.Modules[OverlaySourceModule.Chat].Mode == OverlaySourceMode.Room,
            "Import strips organization chat bindings and preserves room selection in v2.");
        Check(!File.ReadAllText(DocumentPath(root, safe.Id)).Contains("multi-org") && imported.RemovedOrganizationBindings,
            "No transferred organization identifiers are written to storage and the UI receives a removal notice.");
    }

    private static void Corruption(string root)
    {
        Seed(root, OverlayScenePreference.PartyRoom);
        var state = Store(root).Load();
        var path = DocumentPath(root, state.ActivePresetId);
        var valid = File.ReadAllText(path);
        var oldScene = JsonNode.Parse(valid)!.AsObject();
        oldScene["settings"]!["scenePreference"] = "PartyRoom";
        foreach (var payload in new[] { "", " ", "{", valid.Replace("\"schemaVersion\":2", "\"schemaVersion\":99"),
            valid.Replace("\"schemaVersion\":2", "\"schemaVersion\":2,\"schemaVersion\":2"),
            valid.Replace("\"key\":\"Notice\"", "\"key\":\"Notice\",\"key\":\"Notice\""), oldScene.ToJsonString() })
        {
            File.WriteAllText(path, payload);
            var quarantined = Store(root).Load();
            Check(quarantined.StorageState == "corrupt" && quarantined.Presets.Single().Sources is null,
                "invalid v2 is isolated, without resurrecting old room policy");
            ExpectFailure(() => Save(Store(root), quarantined), "cannot save fallback placeholders over damaged preset");
            ExpectFailure(() => Store(root).Apply(new(quarantined.Revision, OverlayWorkspaceMutationKind.ActivatePreset, PresetId: state.ActivePresetId)),
                "cannot activate corrupt preset");
            Check(File.ReadAllText(path) == payload, "corrupt original remains available for recovery");
        }
        var damagedState = Store(root).Load();
        var damagedText = File.ReadAllText(path);
        var reset = Store(root).Apply(new(damagedState.Revision, OverlayWorkspaceMutationKind.ResetPreset, PresetId: state.ActivePresetId));
        Check(reset.StorageState == "ready" && Directory.GetFiles(root, "overlay.recovered-*.json").Any(file => File.ReadAllText(file) == damagedText),
            "explicit reset preserves damaged original before recovery");
        var second = Store(root).Apply(new(reset.Revision, OverlayWorkspaceMutationKind.CreatePreset, Name: "Healthy"));
        File.WriteAllText(path, "broken-secondary");
        var healthySaved = Save(Store(root), Store(root).Load());
        Check(healthySaved.ActivePresetId == second.ActivePresetId && healthySaved.Presets.Any(p => p.StorageState == "corrupt"),
            "unrelated damaged preset does not block healthy active save");
        ExpectFailure(() => Store(root).Apply(new(healthySaved.Revision, OverlayWorkspaceMutationKind.DeletePreset, PresetId: healthySaved.ActivePresetId)),
            "cannot delete last healthy preset and activate corrupt placeholders");
        var deleted = Store(root).Apply(new(healthySaved.Revision, OverlayWorkspaceMutationKind.DeletePreset, PresetId: state.ActivePresetId));
        Check(deleted.Presets.Count == 1 && !File.Exists(path) && Directory.GetFiles(root, "overlay.recovered-*.json").Any(file => File.ReadAllText(file) == "broken-secondary"),
            "damaged preset can be deleted with recovery copy");
        var activePath = DocumentPath(root, deleted.ActivePresetId);
        byte[] damagedBytes = [0xEF, 0xBB, 0xBF, 0xFF, 0xFE, 0xC3];
        File.WriteAllBytes(activePath, damagedBytes);
        var corruptActive = Store(root).Load();
        ExpectFailure(() => Store(root).Apply(new(corruptActive.Revision, OverlayWorkspaceMutationKind.SaveActive, PresetId: "other",
            Settings: deleted.Settings, Layout: deleted.Layout, RenderMode: deleted.RenderMode, Hotkey: deleted.Hotkey)),
            "fake SaveActive target cannot bypass corrupt active guard");
        Store(root).Apply(new(corruptActive.Revision, OverlayWorkspaceMutationKind.ResetPreset, PresetId: deleted.ActivePresetId));
        Check(Directory.GetFiles(root, "overlay.recovered-*.json").Any(file => File.ReadAllBytes(file).SequenceEqual(damagedBytes)),
            "recovery copy preserves invalid UTF8 and BOM byte for byte");
    }

    private static void FallbackAndRollback(string root)
    {
        var bundled = Path.Combine(root, "bundled");
        var local = Path.Combine(root, "local");
        Seed(bundled, OverlayScenePreference.PartyRoom);
        var originals = Directory.GetFiles(bundled).ToDictionary(path => Path.GetFileName(path)!, File.ReadAllText);
        var state = Store(local, bundled).Load();
        Check(File.Exists(DocumentPath(local, state.ActivePresetId)), "legacy fallback migrates into local root only");
        foreach (var (name, text) in originals) Check(File.ReadAllText(Path.Combine(bundled, name!)) == text, "bundled fallback untouched");
        Store(bundled).Load();
        var localLegacy = Path.Combine(root, "local-legacy");
        Seed(localLegacy, OverlayScenePreference.Auto);
        Check(Store(localLegacy, bundled).Load().Presets.Single().Sources!.Binding.Mode == OverlaySourceMode.None,
            "local legacy choice wins over bundled v2 room default");
        var blocked = Path.Combine(root, "blocked");
        Seed(blocked, OverlayScenePreference.PartyRoom);
        Directory.CreateDirectory(DocumentPath(blocked, "preset1"));
        var pending = Store(blocked).Load();
        Check(pending.StorageState == "migrationPending", "failed migration remains inspectable with an honest pending state");
        ExpectFailure(() => Save(Store(blocked), pending), "pending migration refuses writes instead of splitting formats");
        Check(File.ReadAllText(Path.Combine(blocked, "overlay.settings")) == Settings(OverlayScenePreference.PartyRoom).Serialize(), "failed migration retains original settings");
        Check(!Directory.GetFiles(blocked, ".*.tmp").Any(), "failed migration removes staging files");

        var multiple = Path.Combine(root, "multiple");
        Seed(multiple, OverlayScenePreference.PartyRoom);
        File.WriteAllText(Path.Combine(multiple, "overlay.presets"), InformationOverlayPresetCodec.SerializeManifest(
            [new("preset1", "Default"), new("second", "Second")]));
        File.WriteAllText(Path.Combine(multiple, "overlay.second.settings"), Settings(OverlayScenePreference.Fleet).Serialize());
        Directory.CreateDirectory(DocumentPath(multiple, "second"));
        Check(Store(multiple).Load().StorageState == "migrationPending", "later preset migration failure is pending and read-only");
        Check(!File.Exists(DocumentPath(multiple, "preset1")), "first migrated document rolled back on second failure");
        Check(File.ReadAllText(Path.Combine(multiple, "overlay.second.settings")) == Settings(OverlayScenePreference.Fleet).Serialize(), "all old presets survive batch failure");

        var failedSave = Path.Combine(root, "failed-save");
        var saveStore = Store(failedSave);
        var saved = Save(saveStore, saveStore.Load(), new(new(OverlaySourceMode.Room)));
        var savedDocument = File.ReadAllText(DocumentPath(failedSave, saved.ActivePresetId));
        // A directory at a later transaction target simulates inability to replace a file.
        File.Delete(Path.Combine(failedSave, "desktop.config"));
        Directory.CreateDirectory(Path.Combine(failedSave, "desktop.config"));
        saved = saveStore.Load();
        var originalsBeforeSave = Directory.GetFiles(failedSave).ToDictionary(path => path, File.ReadAllBytes);
        ExpectFailure(() => Save(saveStore, saved, OverlayPresetSources.Default), "save failure rolls back policy and compatibility projection");
        Check(File.ReadAllText(DocumentPath(failedSave, saved.ActivePresetId)) == savedDocument, "failed save keeps old policy");
        Check(originalsBeforeSave.All(pair => File.ReadAllBytes(pair.Key).SequenceEqual(pair.Value)), "failed save keeps every original file");
    }

    private static void InterruptedMigrationResumes(string root)
    {
        // A process may stop between atomic per-preset renames. Reconstruct each
        // durable prefix, including an uncommitted staging file, then reopen via
        // the real store. This tests migration recovery, not general save journaling.
        foreach (var completed in new[] { 0, 1, 2 })
        {
            var candidate = Path.Combine(root, completed.ToString());
            Seed(candidate, OverlayScenePreference.PartyRoom);
            File.WriteAllText(Path.Combine(candidate, "overlay.presets"), InformationOverlayPresetCodec.SerializeManifest(
                [new("preset1", "Default"), new("second", "Second")]));
            File.WriteAllText(Path.Combine(candidate, "overlay.second.settings"), Settings(OverlayScenePreference.Fleet).Serialize());
            var legacy = new OverlayWorkspaceStore(candidate).Load();
            var originals = Directory.GetFiles(candidate).ToDictionary(path => Path.GetFileName(path)!, File.ReadAllBytes);
            var backup = Path.Combine(candidate, "overlay.workspace-backup-v2");
            Directory.CreateDirectory(backup);
            foreach (var (name, bytes) in originals) File.WriteAllBytes(Path.Combine(backup, name), bytes);
            var committed = new Dictionary<string, byte[]>();
            foreach (var preset in legacy.Presets.Take(completed))
            {
                var path = DocumentPath(candidate, preset.Id);
                File.WriteAllText(path, new OverlayPresetDocument(preset.Settings, preset.Layout,
                    OverlayPresetSourcesCodec.FromLegacy(preset.Settings.ScenePreference)).Serialize());
                committed.Add(path, File.ReadAllBytes(path));
            }
            File.WriteAllText(Path.Combine(candidate, ".overlay.second.workspace.json.interrupted.tmp"), "uncommitted-invalid-data");
            var resumed = Store(candidate).Load();
            Check(resumed.StorageState == "ready" && resumed.Presets.Count == 2 && resumed.ActivePresetId == legacy.ActivePresetId,
                "Every interrupted migration prefix resumes without activating a different preset.");
            Check(resumed.Presets.Single(p => p.Id == "preset1").Sources!.Binding.Mode == OverlaySourceMode.Room &&
                resumed.Presets.Single(p => p.Id == "second").Sources!.Binding.Mode == OverlaySourceMode.None,
                "Restart completes only missing documents with the original room/fleet migration mapping.");
            foreach (var (path, bytes) in committed)
                Check(File.ReadAllBytes(path).SequenceEqual(bytes), "Restart never rewrites an already committed v2 document.");
            foreach (var (name, bytes) in originals)
            {
                Check(File.ReadAllBytes(Path.Combine(candidate, name)).SequenceEqual(bytes), "Restart preserves legacy and account files.");
                Check(File.ReadAllBytes(Path.Combine(backup, name)).SequenceEqual(bytes), "Restart preserves the original recovery backup.");
            }
            Check(Store(candidate).Load().Revision == resumed.Revision, "Completed migration is idempotent after restart.");
        }
    }

    private static void RecoveredAndConcurrent(string root)
    {
        Seed(root, OverlayScenePreference.Auto);
        File.WriteAllText(Path.Combine(root, "overlay.layout"), "Chat,0,0,0.2,0.2");
        var state = Store(root).Load();
        Check(state.StorageState == "recoveredDefaults" && Store(root).Load().Presets.Single().StorageState == "recoveredDefaults",
            "migration does not disguise recovered layout as an intact preset");
        var successes = 0;
        var conflicts = 0;
        Parallel.For(0, 2, _ =>
        {
            try { Save(Store(root), state); Interlocked.Increment(ref successes); }
            catch (OverlaySettingsException ex) when (ex.Code == "overlay.workspace_revision_conflict") { Interlocked.Increment(ref conflicts); }
        });
        Check(successes == 1 && conflicts == 1, "different store instances cannot both commit the same revision");
        Check(Store(root).Load().StorageState == "ready", "explicit save acknowledges repaired layout");
    }

    private static void AtomicSourceAssignment(string root)
    {
        var store = Store(root);
        var state = Save(store, store.Load(), new(new(OverlaySourceMode.Room), true));
        var first = state.ActivePresetId;
        state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.DuplicatePreset, Name: "Other"));
        var other = state.Presets.Single(p => p.Id != first).Id;
        var room = new OverlayPresetSources(new(OverlaySourceMode.Room), true);
        ExpectFailure(() => store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.ConfigurePresetSources, PresetId: other, Sources: room)),
            "replacing an automatic assignment requires explicit matching prior preset");
        var before = state.Revision;
        state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.ConfigurePresetSources, PresetId: other,
            Sources: room, ReplaceAutoSwitchPresetId: first));
        Check(state.ActivePresetId == first && state.Presets.Single(p => p.Id == other).Sources!.AutoSwitch &&
            !state.Presets.Single(p => p.Id == first).Sources!.AutoSwitch, "atomic reassignment does not activate the edited preset");
        ExpectFailure(() => store.Apply(new(before, OverlayWorkspaceMutationKind.ConfigurePresetSources, PresetId: first,
            Sources: room, ReplaceAutoSwitchPresetId: other)), "stale confirmation cannot replace new assignment");
        state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.ImportPreset, Name: "Room import",
            Settings: state.Settings, Layout: state.Layout, Sources: room));
        Check(!state.Presets.Single(p => p.Name == "Room import").Sources!.AutoSwitch &&
            state.Presets.Single(p => p.Id == other).Sources!.AutoSwitch, "import never claims or conflicts with existing automatic assignment");
    }

    private static void ExpectFailure(Action action, string message)
    {
        try { action(); } catch (OverlaySettingsException) { return; }
        throw new InvalidOperationException(message);
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
