namespace StarBridge.HostRuntime.Overlay;

using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.Core.Overlay;

internal sealed partial class OverlayWorkspaceStore : IOverlayWorkspaceStore, IOverlayWorkspaceInspector
{
    private const string SettingsFile = "overlay.settings";
    private const string LayoutFile = "overlay.layout";
    private const string ActivePresetFile = "overlay.active-preset";
    private const string PresetManifestFile = "overlay.presets";
    private const string RenderModeFile = "overlay.render-mode";
    /// <summary>
    /// Written once the 0.7.3 moves are done (the presets' old overall opacity defaults to full; the retired built-in
    /// layouts the user never saved dropped from the preset list); then nothing is moved again.
    /// </summary>
    internal const string MigrationMarkerFile = "overlay.migrated-073";
    /// <summary>
    /// 0.7.3 (11-13 user, "背景可以"): the background opacity became the plate's real opacity. Each preset the user saved
    /// before is read at its old look (InformationOverlayDefaults.ScaleLegacyBackground) and written so with the next
    /// write, together with this marker; files shipped with the client are always read that way and never written.
    /// </summary>
    internal const string BackgroundMarkerFile = "overlay.background-073";
    /// <summary>
    /// The whole write that sets the marker, kept while its files are replaced: after a crash part way through, the next
    /// load finishes it before looking at the marker, so the move is neither lost nor run again (review R3).
    /// </summary>
    internal const string MigrationJournalFile = "overlay.migrated-073.journal";
    private sealed record MigrationJournal(Dictionary<string, string> Writes, Dictionary<string, string> Binary, List<string> Deletes);
    /// <summary>The 0.7.3 moves the last read found, written with the next write (under StorageGate).</summary>
    private Dictionary<string, string>? _pendingOpacityWrites, _pendingBackgroundWrites;
    private const string DesktopConfigFile = "desktop.config";
    private const string BackupDirectory = "overlay.workspace-backup-v1";
    private const string RegisteredHotkeyFile = "desktop.registered-hotkey.json";
    private const string DefaultHotkey = "Alt+O";
    private static readonly IReadOnlySet<string> LayoutKeys = new HashSet<string>(
        ["Notice", "Squads", "Members", "Chat"],
        StringComparer.OrdinalIgnoreCase);

    // _dataRoot holds the overlay files; _sharedRoot holds desktop.config and the registered-hotkey file, which
    // other parts of the app share. Overlay v2 keeps its files in their own folder (V2Folder) under the shared
    // root, so the earlier overlay files are never read, written or deleted.
    private readonly string _dataRoot;
    private readonly string _sharedRoot;
    private readonly string? _fallbackRoot;

    /// <summary>
    /// 0.7.3 overlay v2 (user, 11-07: "我觉得需要把之前浮层存的全部重置掉，这完全是一个新的东西了"): its own
    /// storage that starts from defaults. The earlier overlay.* and preset files stay as they are for 0.7.2.1.
    /// </summary>
    internal const string V2Folder = "overlay-v2";
    // Per-store compatibility selection; product composition supplies the build capability.
    private readonly bool _enableSourcePresets;
    private static readonly object StorageGate = new();

    // 0.7.3 m102 (11-18 user: "0.7.3 做甲"): the visor size a preset the user never saved starts with, from the screen
    // (OverlayScreenProbe in the product; medium when none is given). Saved presets keep their size.
    private readonly Func<OverlayVisorSize> _autoVisorSize;

    internal OverlayWorkspaceStore(string dataRoot, string? fallbackRoot = null, bool enableSourcePresets = false,
        string? overlayFolder = null, Func<OverlayVisorSize>? autoVisorSize = null)
    {
        _autoVisorSize = autoVisorSize ?? (() => OverlayVisorSize.Medium);
        if (string.IsNullOrWhiteSpace(dataRoot))
        {
            throw new ArgumentException("Overlay workspace data root is required.", nameof(dataRoot));
        }

        _sharedRoot = Path.GetFullPath(dataRoot);
        _dataRoot = string.IsNullOrWhiteSpace(overlayFolder) ? _sharedRoot : Path.Combine(_sharedRoot, overlayFolder);
        _fallbackRoot = string.IsNullOrWhiteSpace(fallbackRoot)
            ? null
            : Path.GetFullPath(fallbackRoot);
        _enableSourcePresets = enableSourcePresets;
    }

    public OverlayWorkspaceReadResult Load()
    {
        lock (StorageGate) return LoadCore();
    }

    public OverlayWorkspaceReadResult Inspect()
    {
        lock (StorageGate) return LoadCore(allowMigration: false);
    }

    /// <summary>
    /// A write that set the 0.7.3 marker was cut off part way (its journal is still there): write it again as decided, so
    /// no file stays half moved. A journal that cannot be read is dropped (it was never finished as a whole, and every
    /// file it named still holds its earlier bytes or the decided ones).
    /// </summary>
    private static bool IsMarker(string name) =>
        name.Equals(MigrationMarkerFile, StringComparison.OrdinalIgnoreCase) || name.Equals(BackgroundMarkerFile, StringComparison.OrdinalIgnoreCase);

    private static bool IsMarked<T>(IReadOnlyDictionary<string, T> writes) => writes.Keys.Any(IsMarker);

    private void FinishInterruptedMigration()
    {
        MigrationJournal? journal = null;
        try { journal = JsonSerializer.Deserialize<MigrationJournal>(File.ReadAllText(FilePath(MigrationJournalFile))); }
        catch (Exception error) when (error is JsonException or IOException or UnauthorizedAccessException) { }
        Dictionary<string, byte[]>? binary = null;
        try { binary = (journal?.Binary ?? []).ToDictionary(pair => pair.Key, pair => Convert.FromBase64String(pair.Value), StringComparer.OrdinalIgnoreCase); }
        catch (Exception error) when (error is FormatException or ArgumentNullException) { } // a null value is broken too (review R5)
        // checked whole before any file is touched: anything that does not read back is a broken journal, dropped
        // a journal carries the 0.7.3 marker, the background marker (11-13), or both (review CX-OVERLAY-TIDY-R3)
        if (journal?.Writes is null || !IsMarked(journal.Writes) || binary is null ||
            journal.Writes.Any(pair => pair.Key is null || pair.Value is null))
        {
            try { File.Delete(FilePath(MigrationJournalFile)); } catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
            return;
        }
        try
        {
            ApplyFileTransaction(journal.Writes, new HashSet<string>(journal.Deletes ?? [], StringComparer.OrdinalIgnoreCase),
                binary, replayingJournal: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // still not finished: the journal stays and the next load tries again; until then the marker is not trusted
        }
    }

    /// <summary>Whether the user saved anything under this preset (settings, layout or its v2 document).</summary>
    private bool SavedPreset(string id) =>
        new[] { "settings", "layout", "workspace.json" }.Any(kind =>
            File.Exists(FilePath(PresetFile(id, kind))) ||
            _fallbackRoot is not null && File.Exists(Path.Combine(_fallbackRoot, PresetFile(id, kind))));

    private OverlayWorkspaceReadResult LoadCore(bool allowMigration = true)
    {
        try
        {
            if (allowMigration && File.Exists(FilePath(MigrationJournalFile))) FinishInterruptedMigration();
            // a journal still there (its replay failed): nothing else is written until it is finished (review R4)
            var journalPending = File.Exists(FilePath(MigrationJournalFile));
            var observed = new SortedDictionary<string, string>(StringComparer.Ordinal);
            // part of the revision: a snapshot taken while the journal was pending is stale once it is finished (review R5)
            if (journalPending) observed["pending/" + MigrationJournalFile] = "1";
            var recovered = false;
            var manifestText = ReadOptional(PresetManifestFile, observed);
            var entries = InformationOverlayPresetCodec.ParseManifest(manifestText, out var manifestRecovered)
                .ToList();
            recovered |= manifestRecovered;
            // 0.7.3 (user, 11-10: "3套预设布局只是之前遗留下来的废弃代码"): an earlier built-in layout the user never saved
            // is no longer a preset; one they saved stays as their own. Read only; the list is written with the next write.
            // read through observed, so the marker is part of the revision: a save from a snapshot taken before another
            // instance wrote it is refused as stale (review CX-VISOR-SETTINGS-B87-R2)
            // while a journal is pending the files are shown as they are, nothing moved in memory: they may already hold the
            // decided values (a user's chosen 85% among them), and nothing is written until the journal is finished (review R5)
            var migrated073 = ReadOptional(MigrationMarkerFile, observed) is not null || journalPending;
            // the preset in use may have saved only into the global files (the active preset reads them): that counts
            var activeBefore = InformationOverlayPresetCodec.SanitizeId(ReadOptional(ActivePresetFile, observed));
            var globalSaved = ReadOptional(SettingsFile, observed) is not null || ReadOptional(LayoutFile, observed) is not null;
            var retired = migrated073 ? [] : entries
                .Where(entry => InformationOverlayPresetCodec.RetiredBuiltInIds.Contains(entry.Id) && !SavedPreset(entry.Id) &&
                    !(globalSaved && entry.Id.Equals(activeBefore, StringComparison.OrdinalIgnoreCase)))
                .Select(entry => entry.Id).ToHashSet(StringComparer.OrdinalIgnoreCase);
            if (retired.Count > 0) entries.RemoveAll(entry => retired.Contains(entry.Id));
            if (entries.Count == 0)
            {
                entries.Add(new InformationOverlayPresetEntry(
                    InformationOverlayPresetCodec.DefaultPresetId,
                    "默认预设"));
            }

            var activePresetText = ReadOptional(ActivePresetFile, observed);
            var requestedActive = InformationOverlayPresetCodec.SanitizeId(activePresetText);
            // a dropped built-in that was in use: the first preset (the default) takes over, not a recovery
            var activeRetired = retired.Contains(requestedActive);
            if (activeRetired) requestedActive = entries.FirstOrDefault()?.Id ?? InformationOverlayPresetCodec.DefaultPresetId;
            var active = entries.FirstOrDefault(entry =>
                    entry.Id.Equals(requestedActive, StringComparison.OrdinalIgnoreCase))?.Id ??
                entries[0].Id;
            recovered |= !active.Equals(requestedActive, StringComparison.OrdinalIgnoreCase) &&
                         activePresetText is not null && !activeRetired;

            var globalSettings = ReadOptional(SettingsFile, observed);
            var globalLayout = ReadOptional(LayoutFile, observed);
            var hotkey = ReadHotkey(observed);
            var presets = new List<OverlayWorkspacePresetSnapshot>(entries.Count);
            var migrations = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var migrationDeletes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            // 0.7.3: the overall opacity takes effect; each preset still at its old default moves to full, once
            var opacityMoved = migrated073;
            var opacityWrites = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var backgroundScaled = ReadOptional(BackgroundMarkerFile, observed) is not null || journalPending;
            var backgroundWrites = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            // a value saved before the marker, or shipped with the client, is read at its old look (11-13)
            bool ScaleBackground(string file) => !observed.ContainsKey($"primary/{file}") || !backgroundScaled;
            var anyStored = false; // nothing stored yet: nothing to move, and a read writes nothing
            // Overlay v2: a preset the user never saved (built-in or shipped defaults) starts on the visor; what the
            // user saved is read as it is. Nothing is switched or rewritten on read or on write.
            // m102: it also starts at the visor size the screen calls for, unless its own file names a size (CSV 81;
            // review CX-OVERLAY-M102-R1 P2-6: a shipped file that says medium keeps medium).
            OverlayDisplaySettings Visor(OverlayDisplaySettings value, bool savedByUser, bool namesSize) =>
                savedByUser || value.EffectiveRequestedSkin != OverlaySkin.Default
                    ? value
                    : value with
                    {
                        Skin = OverlaySkin.Visor, RequestedSkin = OverlaySkin.Visor,
                        VisorSize = namesSize ? value.VisorSize : _autoVisorSize(),
                    };
            var carried = ReadCarried();
            foreach (var entry in entries)
            {
                var isActive = entry.Id.Equals(active, StringComparison.OrdinalIgnoreCase);
                if (!_enableSourcePresets && (File.Exists(Path.Combine(_dataRoot, PresetFile(entry.Id, "workspace.json"))) ||
                    _fallbackRoot is not null && File.Exists(Path.Combine(_fallbackRoot, PresetFile(entry.Id, "workspace.json")))))
                    throw new OverlaySettingsException("overlay.workspace_version_unsupported");
                OverlayPresetDocument? document = null;
                OverlayAppearanceOptions appearanceOptions;
                try
                {
                    appearanceOptions = ReadAppearanceOptions(entry.Id, observed);
                    if (_enableSourcePresets) document = ReadPresetDocument(entry.Id, isActive, observed);
                }
                catch (OverlaySettingsException error) when (error.Code == "overlay.workspace_invalid_preset")
                {
                    // Quarantine this preset only. These placeholders must never be activated or projected.
                    presets.Add(new(entry.Id, entry.Name, isActive, InformationOverlayDefaults.CreateSettings(entry.Id),
                        InformationOverlayDefaults.CreateLayout(entry.Id), "corrupt"));
                    continue;
                }
                anyStored |= document is not null;
                var documentScaled = document is not null && ScaleBackground(PresetFile(entry.Id, "workspace.json"));
                if (documentScaled)
                    document = document! with
                    {
                        Settings = InformationOverlayDefaults.ScaleLegacyBackground(document.Settings),
                        Layout = InformationOverlayDefaults.ScaleLegacyBackground(document.Layout)
                    };
                if (document is not null && !opacityMoved &&
                    InformationOverlayDefaults.MigrateLegacyOpacity(entry.Id, document.Settings) is var movedDocument &&
                    movedDocument.Opacity != document.Settings.Opacity)
                {
                    document = document with { Settings = movedDocument };
                    AddPresetDocument(opacityWrites, entry.Id, document);
                }
                if (documentScaled && observed.ContainsKey($"primary/{PresetFile(entry.Id, "workspace.json")}"))
                    AddPresetDocument(backgroundWrites, entry.Id, document!, document!.WrittenWithVisor);
                if (document is not null)
                {
                    recovered |= document.RecoveredDefaults;
                    presets.Add(new(entry.Id, entry.Name, isActive,
                        Carry(document.Settings, carried, entry.Id, isActive) with { AppearanceOptions = appearanceOptions }, document.Layout,
                        document.RecoveredDefaults ? "recoveredDefaults" : "ready", document.Sources));
                    continue;
                }
                var settingsPayload = ReadOptional(PresetFile(entry.Id, "settings"), observed);
                var layoutPayload = ReadOptional(PresetFile(entry.Id, "layout"), observed);
                if (isActive)
                {
                    settingsPayload ??= globalSettings;
                    layoutPayload ??= globalLayout;
                }

                var settings = settingsPayload is null
                    ? InformationOverlayDefaults.CreateSettings(entry.Id)
                    : OverlayDisplaySettings.Parse(settingsPayload);
                anyStored |= settingsPayload is not null;
                // where this preset's settings and layout were read from (its own file, or the global one it fell back to)
                var settingsFile = ReferenceEquals(settingsPayload, globalSettings) &&
                    !observed.ContainsKey($"primary/{PresetFile(entry.Id, "settings")}") ? SettingsFile : PresetFile(entry.Id, "settings");
                var layoutFile = ReferenceEquals(layoutPayload, globalLayout) &&
                    !observed.ContainsKey($"primary/{PresetFile(entry.Id, "layout")}") ? LayoutFile : PresetFile(entry.Id, "layout");
                var settingsScaled = settingsPayload is not null && ScaleBackground(settingsFile);
                if (settingsScaled) settings = InformationOverlayDefaults.ScaleLegacyBackground(settings);
                if (settingsPayload is not null && !opacityMoved &&
                    InformationOverlayDefaults.MigrateLegacyOpacity(entry.Id, settings) is var movedSettings &&
                    movedSettings.Opacity != settings.Opacity)
                {
                    settings = movedSettings;
                    // back where it was read from: the preset's own file, or the global one it fell back to
                    opacityWrites[ReferenceEquals(settingsPayload, globalSettings) && !observed.ContainsKey($"primary/{PresetFile(entry.Id, "settings")}")
                        ? SettingsFile : PresetFile(entry.Id, "settings")] = NormalizeSettings(settings).Serialize();
                }
                settings = settings with { AppearanceOptions = appearanceOptions };
                var fileSettings = settings;
                // A preset the user never saved (built-in or shipped defaults) simply starts on the visor.
                var savedByUser = observed.ContainsKey($"primary/{PresetFile(entry.Id, "settings")}") ||
                    isActive && ReferenceEquals(settingsPayload, globalSettings) && observed.ContainsKey($"primary/{SettingsFile}");
                var namesSize = settingsPayload is not null && settingsPayload.Split(',').Length > 81;
                settings = Carry(Visor(settings, savedByUser, namesSize), carried, entry.Id, isActive);
                var parsedLayout = layoutPayload is null
                    ? InformationOverlayDefaults.CreateLayout(entry.Id)
                    : InformationOverlayLayoutItem.ParseMany(layoutPayload).ToArray();
                if (layoutPayload is not null && ScaleBackground(layoutFile))
                {
                    parsedLayout = [.. InformationOverlayDefaults.ScaleLegacyBackground(parsedLayout)];
                    if (!backgroundScaled && observed.ContainsKey($"primary/{layoutFile}"))
                        backgroundWrites[layoutFile] = InformationOverlayLayoutItem.SerializeMany(parsedLayout);
                }
                if (settingsScaled && !backgroundScaled && observed.ContainsKey($"primary/{settingsFile}"))
                    backgroundWrites[settingsFile] = NormalizeSettings(fileSettings).Serialize();
                var layoutRecovered = layoutPayload is not null &&
                    (parsedLayout.Count != LayoutKeys.Count ||
                     parsedLayout.Select(item => item.Key).Distinct(StringComparer.OrdinalIgnoreCase).Count() != LayoutKeys.Count ||
                     parsedLayout.Any(item => !LayoutKeys.Contains(item.Key)));
                var layout = CompleteLayout(parsedLayout, entry.Id);
                var storageState = settingsPayload is null && layoutPayload is null
                    ? "defaulted"
                    : layoutRecovered ? "recoveredDefaults" : "ready";
                recovered |= layoutRecovered;
                var sources = OverlayPresetSourcesCodec.FromLegacy(settings.ScenePreference);
                presets.Add(new OverlayWorkspacePresetSnapshot(
                    entry.Id,
                    entry.Name,
                    isActive,
                    settings,
                    layout,
                    storageState,
                    sources));
                // Overlay v2: a preset that only comes from the shipped defaults is not migrated into the v2 folder; it would
                // be written with the plain defaults and then count as saved, skipping the v2 defaults.
                var fromUser = savedByUser || observed.ContainsKey($"primary/{PresetFile(entry.Id, "layout")}") ||
                    isActive && ReferenceEquals(layoutPayload, globalLayout) && observed.ContainsKey($"primary/{LayoutFile}");
                if (_enableSourcePresets && (settingsPayload is not null || layoutPayload is not null) && (fromUser || !V2Mode))
                {
                    var since073 = WrittenSince073(settingsPayload);
                    AddPresetDocument(migrations, entry.Id, new OverlayPresetDocument(fileSettings, layout, sources, layoutRecovered), since073);
                    // A sidecar left from before a rollback does not belong to this older CSV.
                    if (!since073) migrationDeletes.Add(PresetFile(entry.Id, VisorSidecar));
                }
            }

            // A read writes nothing (0.7.2.1 reads the same files): the moved values are only shown, and written with the
            // next write: the v2 move below, or the user's next change (ApplyCore), together with the marker.
            if (retired.Count > 0)
            {
                opacityWrites[PresetManifestFile] = InformationOverlayPresetCodec.SerializeManifest(entries);
                if (activeRetired) opacityWrites[ActivePresetFile] = active;
                anyStored = true;
            }
            // The v2 move never rewrites the earlier CSV files (0.7.2.1 reads them, as they were): the v2 documents it writes
            // (with their visor sidecars) carry the moved opacity and the background scaling (review CX-OVERLAY-M94-MIGRATION-R1)
            static bool IsLegacyCsv(string name) =>
                name.StartsWith("overlay.", StringComparison.OrdinalIgnoreCase) &&
                (name.EndsWith(".settings", StringComparison.OrdinalIgnoreCase) || name.EndsWith(".layout", StringComparison.OrdinalIgnoreCase));
            _pendingOpacityWrites = opacityMoved ? null : opacityWrites;
            if (!opacityMoved && allowMigration && !journalPending && anyStored && migrations.Count > 0)
            {
                foreach (var (name, payload) in opacityWrites)
                    if (!IsLegacyCsv(name)) migrations.TryAdd(name, payload);
                migrations[MigrationMarkerFile] = "1";
            }
            // whatever is written now carries the read-time scaling, so the marker goes with it (never scaled twice)
            _pendingBackgroundWrites = backgroundScaled ? null : backgroundWrites;
            if (!backgroundScaled && allowMigration && !journalPending && migrations.Count > 0)
            {
                foreach (var (name, payload) in backgroundWrites)
                    if (!IsLegacyCsv(name)) migrations.TryAdd(name, payload);
                migrations[BackgroundMarkerFile] = "1";
            }

            if (migrations.Count > 0 && allowMigration && !journalPending)
            {
                try
                {
                    EnsureFirstWriteBackup("overlay.workspace-backup-v2");
                    AddCarriedWrite(migrations); // a v2 first write: the kept choices go with it (then the earlier file is not read again)
                    ApplyFileTransaction(migrations, migrationDeletes);
                    return LoadCore();
                }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException)
                {
                    return LoadCore(allowMigration: false); // Still inspectable, but not writable until migration succeeds.
                }
            }

            var current = presets.First(preset => preset.IsActive);
            var storedRenderMode = ReadOptional(RenderModeFile, observed)?.Trim();
            const string renderMode = "DirectComposition";
            if (!string.Equals(storedRenderMode, renderMode, StringComparison.OrdinalIgnoreCase))
            {
                recovered |= !string.IsNullOrWhiteSpace(storedRenderMode);
            }

            return new OverlayWorkspaceReadResult(
                OverlayWorkspaceSchema.Version,
                ComputeRevision(observed),
                migrations.Count > 0 || journalPending ? "migrationPending" : current.StorageState == "corrupt" ? "corrupt" :
                    observed.Count == 0 ? "defaulted" : recovered ? "recoveredDefaults" : "ready",
                active,
                renderMode,
                hotkey,
                current.Settings,
                current.Layout,
                presets,
                SourcePresetsEnabled: _enableSourcePresets,
                VisorSwitchNotice: UpgradeNoticePending());
        }
        catch (OverlaySettingsException)
        {
            throw;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            throw new OverlaySettingsException("overlay.workspace_read_failed", true, exception);
        }
    }

    public OverlayWorkspaceReadResult Apply(OverlayWorkspaceMutation mutation, Func<bool>? isCurrent = null)
    {
        lock (StorageGate) return ApplyCore(mutation, isCurrent);
    }

    private OverlayWorkspaceReadResult ApplyCore(OverlayWorkspaceMutation mutation, Func<bool>? isCurrent)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        try
        {
            RequireCurrentMutation(isCurrent);
            var current = Load();
            if (current.StorageState == "migrationPending")
                throw new OverlaySettingsException("overlay.workspace_migration_pending", true);
            if (!_enableSourcePresets && mutation.Sources is not null)
                throw new OverlaySettingsException("overlay.workspace_invalid_value");
            if (mutation.Sources is not null && mutation.Kind is not
                (OverlayWorkspaceMutationKind.SaveActive or OverlayWorkspaceMutationKind.ImportPreset or OverlayWorkspaceMutationKind.ConfigurePresetSources))
                throw new OverlaySettingsException("overlay.workspace_invalid_value");
            if (mutation.ReplaceAutoSwitchPresetId is not null && mutation.Kind != OverlayWorkspaceMutationKind.ConfigurePresetSources)
                throw new OverlaySettingsException("overlay.workspace_invalid_value");
            if (mutation.AppearanceOptions is not null && mutation.Kind is not
                (OverlayWorkspaceMutationKind.SaveActive or OverlayWorkspaceMutationKind.ImportPreset))
                throw new OverlaySettingsException("overlay.workspace_invalid_value");
            if (current.Revision != mutation.ExpectedRevision)
            {
                throw new OverlaySettingsException("overlay.workspace_revision_conflict", true);
            }
            if (mutation.Kind == OverlayWorkspaceMutationKind.SaveActive && mutation.PresetId is not null)
                throw new OverlaySettingsException("overlay.workspace_invalid_value");
            var targetId = mutation.PresetId ?? current.ActivePresetId;
            if (current.Presets.Any(p => p.Id.Equals(targetId, StringComparison.OrdinalIgnoreCase) && p.StorageState == "corrupt") &&
                mutation.Kind is OverlayWorkspaceMutationKind.SaveActive or OverlayWorkspaceMutationKind.ActivatePreset or
                    OverlayWorkspaceMutationKind.DuplicatePreset or OverlayWorkspaceMutationKind.ConfigurePresetSources)
                throw new OverlaySettingsException("overlay.workspace_invalid_preset");

            var entries = current.Presets
                .Select(preset => new InformationOverlayPresetEntry(preset.Id, preset.Name))
                .ToList();
            var writes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var deletes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var recoveryCopies = new Dictionary<string, byte[]>(StringComparer.OrdinalIgnoreCase);
            if (mutation.Kind is OverlayWorkspaceMutationKind.DeletePreset or OverlayWorkspaceMutationKind.ResetPreset)
            {
                var damaged = current.Presets.FirstOrDefault(p => p.Id.Equals(targetId, StringComparison.OrdinalIgnoreCase) && p.StorageState == "corrupt");
                if (damaged is not null)
                {
                    foreach (var kind in new[] { "workspace.json", "appearance.json" })
                    {
                        var name = PresetFile(damaged.Id, kind);
                        var original = Path.Combine(_dataRoot, name);
                        if (kind == "workspace.json" && !File.Exists(original) && _fallbackRoot is not null)
                            original = Path.Combine(_fallbackRoot, name);
                        if (File.Exists(original))
                            recoveryCopies[$"overlay.recovered-{damaged.Id}-{kind}-{Guid.NewGuid():N}.json"] = File.ReadAllBytes(original);
                    }
                }
            }

            switch (mutation.Kind)
            {
                case OverlayWorkspaceMutationKind.SaveActive:
                    SaveActive(current, mutation, entries, writes);
                    break;
                case OverlayWorkspaceMutationKind.ActivatePreset:
                    Activate(current, RequiredPreset(current, mutation.PresetId), entries, writes);
                    break;
                case OverlayWorkspaceMutationKind.CreatePreset:
                    Create(entries, mutation, writes);
                    break;
                case OverlayWorkspaceMutationKind.DuplicatePreset:
                    Duplicate(current, mutation, entries, writes);
                    break;
                case OverlayWorkspaceMutationKind.RenamePreset:
                    Rename(current, mutation, entries, writes);
                    break;
                case OverlayWorkspaceMutationKind.DeletePreset:
                    Delete(current, mutation, entries, writes, deletes);
                    break;
                case OverlayWorkspaceMutationKind.ResetPreset:
                    Reset(current, mutation, entries, writes);
                    break;
                case OverlayWorkspaceMutationKind.ImportPreset:
                    Import(current, mutation, entries, writes);
                    break;
                case OverlayWorkspaceMutationKind.ConfigurePresetSources:
                    if (!_enableSourcePresets) throw new OverlaySettingsException("overlay.workspace_invalid_action");
                    ConfigureSources(current, mutation, writes);
                    if (mutation.Name is not null) Rename(current, mutation, entries, writes);
                    break;
                default:
                    throw new OverlaySettingsException("overlay.workspace_invalid_action");
            }

            if (_enableSourcePresets) PrepareVersionedWrites(current, mutation, entries, writes, deletes);
            PrepareAppearanceWrites(current, mutation, entries, writes, deletes);
            AddCarriedWrite(writes);
            EnsureFirstWriteBackup();
            // the first write after 0.7.3 also writes the moved old defaults (the user's own change wins) and the marker;
            // from then on nothing is moved, so what the user chooses stays
            if (!File.Exists(FilePath(MigrationMarkerFile)))
            {
                foreach (var (name, payload) in _pendingOpacityWrites ?? []) writes.TryAdd(name, payload);
                writes[MigrationMarkerFile] = "1";
            }
            // the same for the background scaling (11-13): the user's change wins, the rest is written as it was shown
            if (!File.Exists(FilePath(BackgroundMarkerFile)))
            {
                foreach (var (name, payload) in _pendingBackgroundWrites ?? []) writes.TryAdd(name, payload);
                writes[BackgroundMarkerFile] = "1";
            }
            ApplyFileTransaction(writes, deletes, recoveryCopies, isCurrent);
            return Load() with
            {
                RemovedOrganizationBindings = mutation.Kind == OverlayWorkspaceMutationKind.ImportPreset && mutation.Sources is not null &&
                    OverlayPresetSourcesCodec.ForTransfer(mutation.Sources).RemovedOrganizationBindings
            };
        }
        catch (OverlaySettingsException)
        {
            throw;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            throw new OverlaySettingsException("overlay.workspace_write_failed", true, exception);
        }
    }

    private OverlayAppearanceOptions ReadAppearanceOptions(string id, IDictionary<string, string> observed)
    {
        // User choices are local to this workspace owner. Bundled defaults never inject decorations.
        var name = PresetFile(id, "appearance.json");
        var path = Path.Combine(_dataRoot, name);
        if (!File.Exists(path)) return OverlayAppearanceOptions.Empty;
        if (new FileInfo(path).Length > OverlayAppearanceOptions.MaximumBytes)
            throw new OverlaySettingsException("overlay.workspace_invalid_preset");
        var payload = File.ReadAllText(path, Encoding.UTF8);
        observed[$"primary/{name}"] = payload;
        try { return OverlayAppearanceOptions.Parse(payload); }
        catch (FormatException error) { throw new OverlaySettingsException("overlay.workspace_invalid_preset", false, error); }
    }

    private static void PrepareAppearanceWrites(OverlayWorkspaceReadResult current, OverlayWorkspaceMutation mutation,
        IReadOnlyList<InformationOverlayPresetEntry> entries, IDictionary<string, string> writes, ISet<string> deletes)
    {
        foreach (var removed in current.Presets.Where(preset => !entries.Any(entry => entry.Id == preset.Id)))
            deletes.Add(PresetFile(removed.Id, "appearance.json"));
        foreach (var entry in entries)
        {
            var previous = current.Presets.FirstOrDefault(preset => preset.Id == entry.Id);
            OverlayAppearanceOptions? options = mutation.Kind switch
            {
                OverlayWorkspaceMutationKind.SaveActive when entry.Id == current.ActivePresetId => mutation.AppearanceOptions,
                OverlayWorkspaceMutationKind.DuplicatePreset when previous is null =>
                    RequiredPreset(current, mutation.PresetId ?? current.ActivePresetId).Settings.AppearanceOptions,
                OverlayWorkspaceMutationKind.ImportPreset when previous is null => mutation.AppearanceOptions ?? OverlayAppearanceOptions.Empty,
                OverlayWorkspaceMutationKind.ResetPreset when entry.Id == (mutation.PresetId ?? current.ActivePresetId) => OverlayAppearanceOptions.Empty,
                _ => null
            };
            // Omission means preserve, explicit Empty means clear. Same atomic transaction and revision as layout/settings.
            if (options is not null) writes[PresetFile(entry.Id, "appearance.json")] = options.Json;
        }
    }

    private OverlayPresetDocument? ReadPresetDocument(string id, bool isActive, IDictionary<string, string> observed)
    {
        var name = PresetFile(id, "workspace.json");
        foreach (var root in new[] { _dataRoot, _fallbackRoot }.Where(root => root is not null))
        {
            var path = Path.Combine(root!, name);
            if (!File.Exists(path))
            {
                // A bundled v2 default cannot take priority over the user's local legacy preset.
                if (root == _dataRoot && (File.Exists(Path.Combine(root, PresetFile(id, "settings"))) ||
                    File.Exists(Path.Combine(root, PresetFile(id, "layout"))) ||
                    isActive && (File.Exists(Path.Combine(root, SettingsFile)) || File.Exists(Path.Combine(root, LayoutFile)))))
                    return null;
                continue;
            }
            if (new FileInfo(path).Length > 512 * 1024)
                throw new OverlaySettingsException("overlay.workspace_invalid_preset");
            var payload = File.ReadAllText(path, Encoding.UTF8);
            observed[$"{(root == _dataRoot ? "primary" : "fallback")}/{name}"] = payload;
            // Empty/corrupt v2 is not absence and must not fall through to bundled/legacy data.
            return OverlayPresetDocument.Parse(payload, ReadVisorSidecar(root!, id, root == _dataRoot, observed));
        }
        return null;
    }

    private static void PrepareVersionedWrites(
        OverlayWorkspaceReadResult current,
        OverlayWorkspaceMutation mutation,
        IReadOnlyList<InformationOverlayPresetEntry> entries,
        IDictionary<string, string> writes,
        ISet<string> deletes)
    {
        foreach (var removed in current.Presets.Where(preset => !entries.Any(entry => entry.Id == preset.Id)))
        {
            deletes.Add(PresetFile(removed.Id, "workspace.json"));
            deletes.Add(PresetFile(removed.Id, VisorSidecar));
        }

        foreach (var entry in entries)
        {
            var settingsKey = PresetFile(entry.Id, "settings");
            var layoutKey = PresetFile(entry.Id, "layout");
            if (!writes.TryGetValue(settingsKey, out var settings) || !writes.TryGetValue(layoutKey, out var layout))
                continue;
            var previous = current.Presets.FirstOrDefault(preset => preset.Id == entry.Id);
            OverlayPresetSources sources;
            switch (mutation.Kind)
            {
                case OverlayWorkspaceMutationKind.SaveActive:
                    sources = mutation.Sources ?? previous?.Sources ?? OverlayPresetSources.Default;
                    break;
                case OverlayWorkspaceMutationKind.DuplicatePreset:
                    var original = RequiredPreset(current, mutation.PresetId ?? current.ActivePresetId).Sources ?? OverlayPresetSources.Default;
                    // Copy bindings/layout, not the unique automatic-switch assignment.
                    sources = new OverlayPresetSources(original.Binding, false, original.Modules, original.ChatSources);
                    break;
                case OverlayWorkspaceMutationKind.ImportPreset:
                    sources = OverlayPresetSourcesCodec.ForTransfer(mutation.Sources ??
                        OverlayPresetSourcesCodec.FromLegacy(mutation.Settings!.ScenePreference)).Sources;
                    break;
                default:
                    sources = OverlayPresetSources.Default;
                    break;
            }
            var changesAutomaticAssignment = previous?.Sources is not { } previousSources ||
                previousSources.Binding != sources.Binding || previousSources.AutoSwitch != sources.AutoSwitch;
            if (sources.AutoSwitch && changesAutomaticAssignment && current.Presets.Any(preset => preset.Id != entry.Id &&
                preset.Sources is { AutoSwitch: true } other && other.Binding == sources.Binding))
                throw new OverlaySettingsException("overlay.workspace_auto_switch_conflict");
            var compatible = OverlayDisplaySettings.Parse(settings) with
            { ScenePreference = sources.Binding.Mode == OverlaySourceMode.Room ? OverlayScenePreference.PartyRoom : OverlayScenePreference.Auto };
            AddPresetDocument(writes, entry.Id, new OverlayPresetDocument(
                compatible, InformationOverlayLayoutItem.ParseMany(layout).ToArray(), sources));
            if (writes.ContainsKey(SettingsFile)) writes[SettingsFile] = compatible.Serialize();
            // Global CSV is still a legacy-runtime projection. Per-preset authoritative writes are v2 only.
            writes.Remove(settingsKey);
            writes.Remove(layoutKey);
        }
    }

    private static void ConfigureSources(OverlayWorkspaceReadResult current, OverlayWorkspaceMutation mutation,
        IDictionary<string, string> writes)
    {
        var target = RequiredPreset(current, mutation.PresetId);
        var sources = mutation.Sources ?? throw new OverlaySettingsException("overlay.workspace_invalid_value");
        var conflicts = current.Presets.Where(preset => preset.Id != target.Id && sources.AutoSwitch &&
            preset.Sources is { AutoSwitch: true } other && other.Binding == sources.Binding).ToArray();
        if (conflicts.Length > 1 || conflicts.Length == 1 && conflicts[0].Id != mutation.ReplaceAutoSwitchPresetId ||
            conflicts.Length == 0 && mutation.ReplaceAutoSwitchPresetId is not null)
            throw new OverlaySettingsException("overlay.workspace_auto_switch_conflict");
        if (conflicts.Length == 1)
        {
            var prior = conflicts[0];
            var disabled = new OverlayPresetSources(prior.Sources!.Binding, false, prior.Sources.Modules, prior.Sources.ChatSources);
            AddPresetDocument(writes, prior.Id, new OverlayPresetDocument(prior.Settings, prior.Layout, disabled,
                prior.StorageState == "recoveredDefaults"));
        }
        var compatible = target.Settings with
        { ScenePreference = sources.Binding.Mode == OverlaySourceMode.Room ? OverlayScenePreference.PartyRoom : OverlayScenePreference.Auto };
        AddPresetDocument(writes, target.Id, new OverlayPresetDocument(compatible, target.Layout, sources,
            target.StorageState == "recoveredDefaults"));
        if (target.IsActive) writes[SettingsFile] = compatible.Serialize();
    }

    private void SaveActive(
        OverlayWorkspaceReadResult current,
        OverlayWorkspaceMutation mutation,
        IReadOnlyList<InformationOverlayPresetEntry> entries,
        IDictionary<string, string> writes)
    {
        if (mutation.Settings is null || mutation.Layout is null || mutation.Hotkey is null)
        {
            throw new OverlaySettingsException("overlay.workspace_invalid_value");
        }

        var layout = ValidateLayout(mutation.Layout);
        var renderMode = NormalizeRenderMode(mutation.RenderMode);
        var hotkey = NormalizeHotkey(mutation.Hotkey);
        var settingsPayload = NormalizeSettings(mutation.Settings).Serialize();
        var layoutPayload = InformationOverlayLayoutItem.SerializeMany(layout);
        writes[PresetFile(current.ActivePresetId, "settings")] = settingsPayload;
        writes[PresetFile(current.ActivePresetId, "layout")] = layoutPayload;
        writes[SettingsFile] = settingsPayload;
        writes[LayoutFile] = layoutPayload;
        writes[RenderModeFile] = renderMode;
        writes[ActivePresetFile] = current.ActivePresetId;
        writes[PresetManifestFile] = InformationOverlayPresetCodec.SerializeManifest(entries);
        writes[DesktopConfigFile] = BuildDesktopConfig(hotkey);
        writes[RegisteredHotkeyFile] = JsonSerializer.Serialize(new { registerHotKey = hotkey.UseRegisteredHotkey ?? current.Hotkey.UseRegisteredHotkey ?? false });
    }

    private static void Activate(
        OverlayWorkspaceReadResult current,
        OverlayWorkspacePresetSnapshot target,
        IReadOnlyList<InformationOverlayPresetEntry> entries,
        IDictionary<string, string> writes)
    {
        _ = current;
        var settingsPayload = NormalizeSettings(target.Settings).Serialize();
        var layoutPayload = InformationOverlayLayoutItem.SerializeMany(ValidateLayout(target.Layout));
        writes[ActivePresetFile] = target.Id;
        writes[SettingsFile] = settingsPayload;
        writes[LayoutFile] = layoutPayload;
        writes[PresetManifestFile] = InformationOverlayPresetCodec.SerializeManifest(entries);
    }

    private static void Duplicate(
        OverlayWorkspaceReadResult current,
        OverlayWorkspaceMutation mutation,
        IList<InformationOverlayPresetEntry> entries,
        IDictionary<string, string> writes)
    {
        var source = RequiredPreset(current, mutation.PresetId ?? current.ActivePresetId);
        var name = UniqueName(entries, RequiredName(mutation.Name));
        var id = CreatePresetId(entries);
        entries.Add(new InformationOverlayPresetEntry(id, name));
        writes[PresetFile(id, "settings")] = NormalizeSettings(source.Settings).Serialize();
        writes[PresetFile(id, "layout")] =
            InformationOverlayLayoutItem.SerializeMany(ValidateLayout(source.Layout));
        writes[PresetManifestFile] = InformationOverlayPresetCodec.SerializeManifest(entries);
    }

    private void Create(
        IList<InformationOverlayPresetEntry> entries,
        OverlayWorkspaceMutation mutation,
        IDictionary<string, string> writes)
    {
        var name = UniqueName(entries, RequiredName(mutation.Name));
        var id = CreatePresetId(entries);
        var settingsPayload = NormalizeSettings(PresetDefaults(id)).Serialize();
        var layoutPayload = InformationOverlayLayoutItem.SerializeMany(
            ValidateLayout(InformationOverlayDefaults.CreateLayout(id)));
        entries.Add(new InformationOverlayPresetEntry(id, name));
        writes[PresetFile(id, "settings")] = settingsPayload;
        writes[PresetFile(id, "layout")] = layoutPayload;
        writes[SettingsFile] = settingsPayload;
        writes[LayoutFile] = layoutPayload;
        writes[ActivePresetFile] = id;
        writes[PresetManifestFile] = InformationOverlayPresetCodec.SerializeManifest(entries);
    }

    private static void Rename(
        OverlayWorkspaceReadResult current,
        OverlayWorkspaceMutation mutation,
        IList<InformationOverlayPresetEntry> entries,
        IDictionary<string, string> writes)
    {
        var target = RequiredPreset(current, mutation.PresetId);
        var name = RequiredName(mutation.Name);
        if (entries.Any(entry => !entry.Id.Equals(target.Id, StringComparison.OrdinalIgnoreCase) &&
                                 entry.Name.Equals(name, StringComparison.OrdinalIgnoreCase)))
        {
            throw new OverlaySettingsException("overlay.workspace_duplicate_name");
        }

        var index = entries.ToList().FindIndex(entry =>
            entry.Id.Equals(target.Id, StringComparison.OrdinalIgnoreCase));
        entries[index] = new InformationOverlayPresetEntry(target.Id, name);
        writes[PresetManifestFile] = InformationOverlayPresetCodec.SerializeManifest(entries);
    }

    private static void Delete(
        OverlayWorkspaceReadResult current,
        OverlayWorkspaceMutation mutation,
        IList<InformationOverlayPresetEntry> entries,
        IDictionary<string, string> writes,
        ISet<string> deletes)
    {
        if (entries.Count <= 1)
        {
            throw new OverlaySettingsException("overlay.workspace_last_preset");
        }

        var target = RequiredPreset(current, mutation.PresetId);
        entries.Remove(entries.First(entry => entry.Id.Equals(target.Id, StringComparison.OrdinalIgnoreCase)));
        deletes.Add(PresetFile(target.Id, "settings"));
        deletes.Add(PresetFile(target.Id, "layout"));
        writes[PresetManifestFile] = InformationOverlayPresetCodec.SerializeManifest(entries);
        if (target.IsActive)
        {
            var next = current.Presets.FirstOrDefault(preset =>
                !preset.Id.Equals(target.Id, StringComparison.OrdinalIgnoreCase) && preset.StorageState != "corrupt")
                ?? throw new OverlaySettingsException("overlay.workspace_no_usable_preset");
            writes[ActivePresetFile] = next.Id;
            writes[SettingsFile] = NormalizeSettings(next.Settings).Serialize();
            writes[LayoutFile] = InformationOverlayLayoutItem.SerializeMany(ValidateLayout(next.Layout));
        }
    }

    private void Reset(
        OverlayWorkspaceReadResult current,
        OverlayWorkspaceMutation mutation,
        IReadOnlyList<InformationOverlayPresetEntry> entries,
        IDictionary<string, string> writes)
    {
        var target = RequiredPreset(current, mutation.PresetId ?? current.ActivePresetId);
        // 11-14: continuous play left the overlay event types; its retired flag and duration stay as the user had them, so
        // 0.7.2.1 reads them back after a reset too (review CX-CPLAY-CARD-073-R1).
        var defaults = PresetDefaults(target.Id);
        const OverlayEventNotificationTypes retired = OverlayEventNotificationTypes.LocalPlayReminder;
        var settingsPayload = (defaults with
        {
            EventNotificationTypes = (defaults.EventNotificationTypes & ~retired) | (target.Settings.EventNotificationTypes & retired),
            EventNotificationDurations = defaults.EventNotificationDurations.Set(retired,
                target.Settings.EventNotificationDurations.LocalPlayReminder),
        }).Serialize();
        var layoutPayload = InformationOverlayLayoutItem.SerializeMany(
            ValidateLayout(InformationOverlayDefaults.CreateLayout(target.Id)));
        writes[PresetFile(target.Id, "settings")] = settingsPayload;
        writes[PresetFile(target.Id, "layout")] = layoutPayload;
        writes[PresetManifestFile] = InformationOverlayPresetCodec.SerializeManifest(entries);
        if (target.IsActive)
        {
            writes[SettingsFile] = settingsPayload;
            writes[LayoutFile] = layoutPayload;
        }
    }

    private static void Import(
        OverlayWorkspaceReadResult current,
        OverlayWorkspaceMutation mutation,
        IList<InformationOverlayPresetEntry> entries,
        IDictionary<string, string> writes)
    {
        _ = current;
        if (mutation.Settings is null || mutation.Layout is null)
        {
            throw new OverlaySettingsException("overlay.workspace_invalid_value");
        }

        var id = CreatePresetId(entries);
        var name = UniqueName(entries, RequiredName(mutation.Name));
        entries.Add(new InformationOverlayPresetEntry(id, name));
        writes[PresetFile(id, "settings")] = NormalizeSettings(mutation.Settings).Serialize();
        writes[PresetFile(id, "layout")] =
            InformationOverlayLayoutItem.SerializeMany(ValidateLayout(mutation.Layout));
        writes[PresetManifestFile] = InformationOverlayPresetCodec.SerializeManifest(entries);
    }

    private static OverlayWorkspacePresetSnapshot RequiredPreset(
        OverlayWorkspaceReadResult current,
        string? presetId)
    {
        var id = InformationOverlayPresetCodec.SanitizeId(presetId);
        return current.Presets.FirstOrDefault(preset =>
                   preset.Id.Equals(id, StringComparison.OrdinalIgnoreCase)) ??
               throw new OverlaySettingsException("overlay.workspace_preset_not_found");
    }

    private static string RequiredName(string? value) =>
        InformationOverlayPresetCodec.CleanName(value) ??
        throw new OverlaySettingsException("overlay.workspace_invalid_name");

    private static string UniqueName(IEnumerable<InformationOverlayPresetEntry> entries, string value)
    {
        if (!entries.Any(entry => entry.Name.Equals(value, StringComparison.OrdinalIgnoreCase)))
        {
            return value;
        }

        for (var index = 2; index < 1000; index++)
        {
            var suffix = $" {index}";
            var stem = value.Length + suffix.Length <= 24
                ? value
                : value[..Math.Max(1, 24 - suffix.Length)];
            var candidate = stem + suffix;
            if (!entries.Any(entry => entry.Name.Equals(candidate, StringComparison.OrdinalIgnoreCase)))
            {
                return candidate;
            }
        }

        throw new OverlaySettingsException("overlay.workspace_duplicate_name");
    }

    private static string CreatePresetId(IEnumerable<InformationOverlayPresetEntry> entries)
    {
        string id;
        do
        {
            id = "preset-" + Guid.NewGuid().ToString("N")[..12];
        } while (entries.Any(entry => entry.Id.Equals(id, StringComparison.OrdinalIgnoreCase)));
        return id;
    }

    internal static OverlayDisplaySettings NormalizeSettings(OverlayDisplaySettings settings) =>
        OverlayDisplaySettings.Parse(settings.Serialize()) with { AppearanceOptions = settings.AppearanceOptions };

    internal static IReadOnlyList<InformationOverlayLayoutItem> ValidateLayout(
        IReadOnlyList<InformationOverlayLayoutItem> layout)
    {
        var normalized = InformationOverlayLayoutItem.ParseMany(
            InformationOverlayLayoutItem.SerializeMany(layout)).ToArray();
        var keys = normalized.Select(item => item.Key).ToArray();
        if (normalized.Length != LayoutKeys.Count ||
            keys.Distinct(StringComparer.OrdinalIgnoreCase).Count() != LayoutKeys.Count ||
            keys.Any(key => !LayoutKeys.Contains(key)))
        {
            throw new OverlaySettingsException("overlay.workspace_invalid_layout");
        }

        return normalized;
    }

    private static string NormalizeRenderMode(string? value) =>
        value?.Trim().Equals("DirectComposition", StringComparison.OrdinalIgnoreCase) == true
            ? "DirectComposition"
            : throw new OverlaySettingsException("overlay.workspace_invalid_render_mode");

    internal static OverlayWorkspaceHotkeySnapshot NormalizeHotkey(OverlayWorkspaceHotkeySnapshot hotkey)
    {
        var parts = hotkey.Binding.Split(
            '+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var primary = parts.Where(part => !part.Equals("Ctrl", StringComparison.OrdinalIgnoreCase) &&
                                          !part.Equals("Control", StringComparison.OrdinalIgnoreCase) &&
                                          !part.Equals("Alt", StringComparison.OrdinalIgnoreCase) &&
                                          !part.Equals("Shift", StringComparison.OrdinalIgnoreCase) &&
                                          !part.Equals("Win", StringComparison.OrdinalIgnoreCase) &&
                                          !part.Equals("Windows", StringComparison.OrdinalIgnoreCase)).ToArray();
        if (parts.Length == 0 || primary.Length != 1 || primary[0].Length > 24 ||
            primary[0].Any(character => !char.IsLetterOrDigit(character)))
        {
            throw new OverlaySettingsException("overlay.workspace_invalid_hotkey");
        }

        return hotkey with { Binding = string.Join('+', parts), RuntimeState = "unavailable" };
    }

    private string BuildDesktopConfig(OverlayWorkspaceHotkeySnapshot hotkey)
    {
        var primary = Path.Combine(_sharedRoot, DesktopConfigFile);
        var fallback = _fallbackRoot is null ? null : Path.Combine(_fallbackRoot, DesktopConfigFile);
        var source = File.Exists(primary) ? primary : fallback is not null && File.Exists(fallback) ? fallback : null;
        var original = source is null ? null : File.ReadAllText(source);
        var newLine = original?.Contains("\r\n", StringComparison.Ordinal) == true ? "\r\n" : "\n";
        var hadFinalNewLine = original?.EndsWith("\n", StringComparison.Ordinal) == true;
        var lines = original is null
            ? new List<string>()
            : original.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n').ToList();
        if (hadFinalNewLine && lines.Count > 0 && lines[^1].Length == 0)
        {
            lines.RemoveAt(lines.Count - 1);
        }
        while (lines.Count < 16)
        {
            lines.Add(string.Empty);
        }
        lines[4] = hotkey.Binding;
        lines[15] = hotkey.Enabled.ToString();
        return string.Join(newLine, lines) + (original is null || hadFinalNewLine ? newLine : string.Empty);
    }

    private void EnsureFirstWriteBackup(string directoryName = BackupDirectory)
    {
        var backup = Path.Combine(_dataRoot, directoryName);
        if (Directory.Exists(backup))
        {
            return;
        }

        Directory.CreateDirectory(_dataRoot);
        var temporary = backup + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            Directory.CreateDirectory(temporary);
            var files = Directory.EnumerateFiles(_dataRoot, "overlay.*", SearchOption.TopDirectoryOnly)
                .Concat(File.Exists(FilePath(DesktopConfigFile))
                    ? [FilePath(DesktopConfigFile)]
                    : [])
                .Concat(File.Exists(FilePath(RegisteredHotkeyFile)) ? [FilePath(RegisteredHotkeyFile)] : [])
                .Where(path => !Path.GetFileName(path).Contains(".tmp", StringComparison.OrdinalIgnoreCase))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();
            foreach (var source in files)
            {
                File.Copy(source, Path.Combine(temporary, Path.GetFileName(source)), overwrite: false);
            }
            File.WriteAllText(
                Path.Combine(temporary, "manifest.json"),
                JsonSerializer.Serialize(new
                {
                    schemaVersion = 1,
                    createdAtUtc = DateTimeOffset.UtcNow,
                    files = files.Select(Path.GetFileName).Order(StringComparer.Ordinal).ToArray()
                }),
                new UTF8Encoding(false));
            Directory.Move(temporary, backup);
        }
        catch
        {
            try { if (Directory.Exists(temporary)) Directory.Delete(temporary, recursive: true); }
            catch { }
            throw;
        }
    }

    private void ApplyFileTransaction(
        IReadOnlyDictionary<string, string> writes,
        IReadOnlySet<string> deletes,
        IReadOnlyDictionary<string, byte[]>? recoveryCopies = null,
        Func<bool>? isCurrent = null,
        bool replayingJournal = false)
    {
        Directory.CreateDirectory(_dataRoot);
        Directory.CreateDirectory(_sharedRoot);
        var bytesToWrite = writes.ToDictionary(pair => pair.Key, pair => new UTF8Encoding(false).GetBytes(pair.Value), StringComparer.OrdinalIgnoreCase);
        foreach (var (name, bytes) in recoveryCopies ?? new Dictionary<string, byte[]>()) bytesToWrite.Add(name, bytes);
        var targetNames = bytesToWrite.Keys.Concat(deletes).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        var originals = targetNames.ToDictionary(
            name => name,
            name => File.Exists(FilePath(name))
                ? File.ReadAllBytes(FilePath(name))
                : null,
            StringComparer.OrdinalIgnoreCase);
        var staged = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        // targets this transaction actually replaced or deleted; only these need restoring on failure
        var changed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var journaled = false;
        var rolledBackWhole = true;
        string? temporaryJournal = null;
        try
        {
            foreach (var (name, bytes) in bytesToWrite)
            {
                var temporary = Beside(name, $".{name}.{Guid.NewGuid():N}.tmp");
                using var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write,
                    FileShare.None, 4096, FileOptions.WriteThrough);
                stream.Write(bytes);
                stream.Flush(true);
                staged[name] = temporary;
            }

            RequireCurrentMutation(isCurrent);
            // a replay keeps the journal it is replaying until it has finished (review R4)
            // the background scaling journals too: interrupted, it is finished on the next load, never scaled twice
            // (review CX-OVERLAY-TIDY-R3)
            if (IsMarked(bytesToWrite) && !replayingJournal)
            {
                // the decided write, kept until every file is in place (finished on the next load after a crash)
                var journal = JsonSerializer.Serialize(new MigrationJournal(
                    writes.ToDictionary(pair => pair.Key, pair => pair.Value),
                    (recoveryCopies ?? new Dictionary<string, byte[]>()).ToDictionary(pair => pair.Key, pair => Convert.ToBase64String(pair.Value)),
                    [.. deletes]));
                temporaryJournal = Beside(MigrationJournalFile, $".{MigrationJournalFile}.{Guid.NewGuid():N}.tmp");
                using (var stream = new FileStream(temporaryJournal, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
                {
                    stream.Write(new UTF8Encoding(false).GetBytes(journal));
                    stream.Flush(true);
                }
                File.Move(temporaryJournal, FilePath(MigrationJournalFile), overwrite: true);
                journaled = true;
            }
            // the 0.7.3 marker goes first: a crash part way through can then leave an old value unmoved (shown as saved),
            // never move again a value the user chose in this same write (review CX-VISOR-SETTINGS-B87-R2)
            foreach (var (name, temporary) in staged.OrderBy(pair => IsMarker(pair.Key) ? 0 : 1))
            {
                File.Move(temporary, FilePath(name), overwrite: true);
                changed.Add(name);
            }
            foreach (var name in deletes)
            {
                var target = FilePath(name);
                if (File.Exists(target)) { File.Delete(target); changed.Add(name); }
            }
            // A source change during durable writes invalidates the activation;
            // rollback happens under the same storage gate before publishing.
            RequireCurrentMutation(isCurrent);
            // done: nothing left to finish (the replay drops the journal it finished)
            if (journaled || replayingJournal) File.Delete(FilePath(MigrationJournalFile));
        }
        catch
        {
            foreach (var (name, bytes) in originals)
            {
                // a target the transaction never replaced still holds its original bytes
                if (!changed.Contains(name)) continue;
                var target = FilePath(name);
                if (bytes is null)
                {
                    try { if (File.Exists(target)) File.Delete(target); } catch { rolledBackWhole = false; }
                    continue;
                }
                try
                {
                    // if restoring fails, the rollback copy stays on disk: it holds the bytes from before the transaction
                    var rollback = Beside(name, $".{name}.{Guid.NewGuid():N}.rollback");
                    File.WriteAllBytes(rollback, bytes);
                    File.Move(rollback, target, overwrite: true);
                }
                catch { rolledBackWhole = false; }
            }
            // rolled back whole: the decided write did not happen, so there is nothing to finish. A partial rollback keeps
            // the journal, which the next load finishes; a failed replay keeps its journal too (review R4)
            if (journaled && rolledBackWhole) { try { File.Delete(FilePath(MigrationJournalFile)); } catch { } }
            throw;
        }
        finally
        {
            if (temporaryJournal is not null) { try { if (File.Exists(temporaryJournal)) File.Delete(temporaryJournal); } catch { } }
            foreach (var temporary in staged.Values)
            {
                try { if (File.Exists(temporary)) File.Delete(temporary); } catch { }
            }
        }
    }

    /// <summary>Where a stored file lives: desktop.config and the registered-hotkey file are shared, the rest are overlay files.</summary>
    private string FilePath(string name) =>
        name.Equals(DesktopConfigFile, StringComparison.OrdinalIgnoreCase) || name.Equals(RegisteredHotkeyFile, StringComparison.OrdinalIgnoreCase)
            ? Path.Combine(_sharedRoot, name)
            : Path.Combine(_dataRoot, name);

    /// <summary>A temporary or rollback file next to the file it stands in for.</summary>
    private string Beside(string name, string fileName) => Path.Combine(Path.GetDirectoryName(FilePath(name))!, fileName);

    private static void RequireCurrentMutation(Func<bool>? isCurrent)
    {
        if (isCurrent is not null && !isCurrent())
            throw new OverlaySettingsException("overlay.workspace_revision_conflict", true);
    }

    private IReadOnlyList<InformationOverlayLayoutItem> CompleteLayout(
        IReadOnlyList<InformationOverlayLayoutItem> source,
        string presetId)
    {
        var result = source.Where(item => LayoutKeys.Contains(item.Key))
            .GroupBy(item => item.Key, StringComparer.OrdinalIgnoreCase).Select(group => group.First()).ToList();
        foreach (var fallback in InformationOverlayDefaults.CreateLayout(presetId))
            if (!result.Any(item => item.Key.Equals(fallback.Key, StringComparison.OrdinalIgnoreCase))) result.Add(fallback);
        return result;
    }

    private string? ReadOptional(string fileName, IDictionary<string, string> observed)
    {
        var primary = FilePath(fileName);
        if (File.Exists(primary))
        {
            var value = File.ReadAllText(primary);
            observed[$"primary/{fileName}"] = value;
            return EmptyToNull(value);
        }

        if (_fallbackRoot is null)
        {
            return null;
        }

        var fallback = Path.Combine(_fallbackRoot, fileName);
        if (!File.Exists(fallback))
        {
            return null;
        }

        var fallbackValue = File.ReadAllText(fallback);
        observed[$"fallback/{fileName}"] = fallbackValue;
        return EmptyToNull(fallbackValue);
    }

    // Anything but an explicit true means off: a damaged file must not block the
    // workspace or turn a registration on.
    private bool ReadRegisterHotKey(IDictionary<string, string> observed)
    {
        var payload = ReadOptional(RegisteredHotkeyFile, observed);
        if (payload is null) return false;
        try
        {
            using var document = JsonDocument.Parse(payload);
            return document.RootElement.ValueKind == JsonValueKind.Object &&
                document.RootElement.TryGetProperty("registerHotKey", out var value) &&
                value.ValueKind == JsonValueKind.True;
        }
        catch (JsonException) { return false; }
    }

    private OverlayWorkspaceHotkeySnapshot ReadHotkey(IDictionary<string, string> observed)
    {
        var registered = ReadRegisterHotKey(observed);
        var primary = Path.Combine(_sharedRoot, DesktopConfigFile);
        var source = File.Exists(primary)
            ? primary
            : _fallbackRoot is null ? null : Path.Combine(_fallbackRoot, DesktopConfigFile);
        if (source is null || !File.Exists(source))
        {
            return new OverlayWorkspaceHotkeySnapshot(DefaultHotkey, true, "unavailable", registered);
        }

        var lines = File.ReadAllLines(source);
        var binding = lines.Length > 4 && !string.IsNullOrWhiteSpace(lines[4])
            ? lines[4].Trim()
            : DefaultHotkey;
        var enabled = lines.Length <= 15 || !bool.TryParse(lines[15], out var parsedEnabled) ||
                      parsedEnabled;
        var prefix = source.Equals(primary, StringComparison.OrdinalIgnoreCase) ? "primary" : "fallback";
        observed[$"{prefix}/{DesktopConfigFile}#overlayHotkey"] = binding;
        observed[$"{prefix}/{DesktopConfigFile}#enableOverlayGlobalHotkey"] = enabled.ToString();
        return new OverlayWorkspaceHotkeySnapshot(binding, enabled, "unavailable", registered);
    }

    private static string PresetFile(string presetId, string kind) =>
        $"overlay.{InformationOverlayPresetCodec.SanitizeId(presetId)}.{kind}";

    private static string? EmptyToNull(string value) =>
        string.IsNullOrWhiteSpace(value) ? null : value;

    private static long ComputeRevision(IReadOnlyDictionary<string, string> observed)
    {
        if (observed.Count == 0)
        {
            return 0;
        }

        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        foreach (var (path, value) in observed)
        {
            hash.AppendData(Encoding.UTF8.GetBytes(path));
            hash.AppendData([0]);
            hash.AppendData(Encoding.UTF8.GetBytes(value));
            hash.AppendData([0]);
        }

        var revision = BinaryPrimitives.ReadInt64LittleEndian(hash.GetHashAndReset()) & long.MaxValue;
        return revision == 0 ? 1 : revision;
    }
}
