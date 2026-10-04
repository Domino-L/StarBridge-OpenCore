namespace StarBridge.HostRuntime.Overlay;

using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.Core.Overlay;

internal sealed class OverlayWorkspaceStore : IOverlayWorkspaceStore
{
    private const string SettingsFile = "overlay.settings";
    private const string LayoutFile = "overlay.layout";
    private const string ActivePresetFile = "overlay.active-preset";
    private const string PresetManifestFile = "overlay.presets";
    private const string RenderModeFile = "overlay.render-mode";
    private const string DesktopConfigFile = "desktop.config";
    private const string BackupDirectory = "overlay.workspace-backup-v1";
    private const string DefaultHotkey = "Alt+O";
    private static readonly IReadOnlySet<string> LayoutKeys = new HashSet<string>(
        ["Notice", "Squads", "Members", "Chat"],
        StringComparer.OrdinalIgnoreCase);

    private readonly string _dataRoot;
    private readonly string? _fallbackRoot;
    // Explicit build opt-in; ordinary builds keep the legacy workspace contract.
    private readonly bool _enableSourcePresets;
    private static readonly object StorageGate = new();

    internal OverlayWorkspaceStore(string dataRoot, string? fallbackRoot = null, bool enableSourcePresets = false)
    {
        if (string.IsNullOrWhiteSpace(dataRoot))
        {
            throw new ArgumentException("Overlay workspace data root is required.", nameof(dataRoot));
        }

        _dataRoot = Path.GetFullPath(dataRoot);
        _fallbackRoot = string.IsNullOrWhiteSpace(fallbackRoot)
            ? null
            : Path.GetFullPath(fallbackRoot);
        _enableSourcePresets = enableSourcePresets;
    }

    public OverlayWorkspaceReadResult Load()
    {
        lock (StorageGate) return LoadCore();
    }

    private OverlayWorkspaceReadResult LoadCore(bool allowMigration = true)
    {
        try
        {
            var observed = new SortedDictionary<string, string>(StringComparer.Ordinal);
            var recovered = false;
            var manifestText = ReadOptional(PresetManifestFile, observed);
            var entries = InformationOverlayPresetCodec.ParseManifest(manifestText, out var manifestRecovered)
                .ToList();
            recovered |= manifestRecovered;
            if (entries.Count == 0)
            {
                entries.Add(new InformationOverlayPresetEntry(
                    InformationOverlayPresetCodec.DefaultPresetId,
                    "默认预设"));
            }

            var activePresetText = ReadOptional(ActivePresetFile, observed);
            var requestedActive = InformationOverlayPresetCodec.SanitizeId(activePresetText);
            var active = entries.FirstOrDefault(entry =>
                    entry.Id.Equals(requestedActive, StringComparison.OrdinalIgnoreCase))?.Id ??
                entries[0].Id;
            recovered |= !active.Equals(requestedActive, StringComparison.OrdinalIgnoreCase) &&
                         activePresetText is not null;

            var globalSettings = ReadOptional(SettingsFile, observed);
            var globalLayout = ReadOptional(LayoutFile, observed);
            var hotkey = ReadHotkey(observed);
            var presets = new List<OverlayWorkspacePresetSnapshot>(entries.Count);
            var migrations = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var entry in entries)
            {
                var isActive = entry.Id.Equals(active, StringComparison.OrdinalIgnoreCase);
                if (!_enableSourcePresets && (File.Exists(Path.Combine(_dataRoot, PresetFile(entry.Id, "workspace.json"))) ||
                    _fallbackRoot is not null && File.Exists(Path.Combine(_fallbackRoot, PresetFile(entry.Id, "workspace.json")))))
                    throw new OverlaySettingsException("overlay.workspace_version_unsupported");
                OverlayPresetDocument? document = null;
                try { if (_enableSourcePresets) document = ReadPresetDocument(entry.Id, isActive, observed); }
                catch (OverlaySettingsException error) when (error.Code == "overlay.workspace_invalid_preset")
                {
                    // Quarantine this preset only. These placeholders must never be activated or projected.
                    presets.Add(new(entry.Id, entry.Name, isActive, InformationOverlayDefaults.CreateSettings(entry.Id),
                        InformationOverlayDefaults.CreateLayout(entry.Id), "corrupt"));
                    continue;
                }
                if (document is not null)
                {
                    recovered |= document.RecoveredDefaults;
                    presets.Add(new(entry.Id, entry.Name, isActive, document.Settings, document.Layout,
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
                var parsedLayout = layoutPayload is null
                    ? InformationOverlayDefaults.CreateLayout(entry.Id)
                    : InformationOverlayLayoutItem.ParseMany(layoutPayload).ToArray();
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
                if (_enableSourcePresets && (settingsPayload is not null || layoutPayload is not null))
                    migrations[PresetFile(entry.Id, "workspace.json")] = new OverlayPresetDocument(settings, layout, sources, layoutRecovered).Serialize();
            }

            if (migrations.Count > 0 && allowMigration)
            {
                try
                {
                    EnsureFirstWriteBackup("overlay.workspace-backup-v2");
                    ApplyFileTransaction(migrations, new HashSet<string>());
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
                migrations.Count > 0 ? "migrationPending" : current.StorageState == "corrupt" ? "corrupt" :
                    observed.Count == 0 ? "defaulted" : recovered ? "recoveredDefaults" : "ready",
                active,
                renderMode,
                hotkey,
                current.Settings,
                current.Layout,
                presets,
                SourcePresetsEnabled: _enableSourcePresets);
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
            if (_enableSourcePresets && mutation.Kind is OverlayWorkspaceMutationKind.DeletePreset or OverlayWorkspaceMutationKind.ResetPreset)
            {
                var damaged = current.Presets.FirstOrDefault(p => p.Id.Equals(targetId, StringComparison.OrdinalIgnoreCase) && p.StorageState == "corrupt");
                if (damaged is not null)
                {
                    var name = PresetFile(damaged.Id, "workspace.json");
                    var original = Path.Combine(_dataRoot, name);
                    if (!File.Exists(original) && _fallbackRoot is not null) original = Path.Combine(_fallbackRoot, name);
                    recoveryCopies[$"overlay.recovered-{damaged.Id}-{Guid.NewGuid():N}.json"] = File.ReadAllBytes(original);
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
            EnsureFirstWriteBackup();
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
            return OverlayPresetDocument.Parse(payload);
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
            deletes.Add(PresetFile(removed.Id, "workspace.json"));

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
            writes[PresetFile(entry.Id, "workspace.json")] = new OverlayPresetDocument(
                compatible, InformationOverlayLayoutItem.ParseMany(layout).ToArray(), sources).Serialize();
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
            writes[PresetFile(prior.Id, "workspace.json")] = new OverlayPresetDocument(prior.Settings, prior.Layout, disabled,
                prior.StorageState == "recoveredDefaults").Serialize();
        }
        var compatible = target.Settings with
        { ScenePreference = sources.Binding.Mode == OverlaySourceMode.Room ? OverlayScenePreference.PartyRoom : OverlayScenePreference.Auto };
        writes[PresetFile(target.Id, "workspace.json")] = new OverlayPresetDocument(compatible, target.Layout, sources,
            target.StorageState == "recoveredDefaults").Serialize();
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

    private static void Create(
        IList<InformationOverlayPresetEntry> entries,
        OverlayWorkspaceMutation mutation,
        IDictionary<string, string> writes)
    {
        var name = UniqueName(entries, RequiredName(mutation.Name));
        var id = CreatePresetId(entries);
        var settingsPayload = NormalizeSettings(
            InformationOverlayDefaults.CreateSettings(id)).Serialize();
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

    private static void Reset(
        OverlayWorkspaceReadResult current,
        OverlayWorkspaceMutation mutation,
        IReadOnlyList<InformationOverlayPresetEntry> entries,
        IDictionary<string, string> writes)
    {
        var target = RequiredPreset(current, mutation.PresetId ?? current.ActivePresetId);
        var settingsPayload = InformationOverlayDefaults.CreateSettings(target.Id).Serialize();
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
        OverlayDisplaySettings.Parse(settings.Serialize());

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
        var primary = Path.Combine(_dataRoot, DesktopConfigFile);
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
                .Concat(File.Exists(Path.Combine(_dataRoot, DesktopConfigFile))
                    ? [Path.Combine(_dataRoot, DesktopConfigFile)]
                    : [])
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
        Func<bool>? isCurrent = null)
    {
        Directory.CreateDirectory(_dataRoot);
        var bytesToWrite = writes.ToDictionary(pair => pair.Key, pair => new UTF8Encoding(false).GetBytes(pair.Value), StringComparer.OrdinalIgnoreCase);
        foreach (var (name, bytes) in recoveryCopies ?? new Dictionary<string, byte[]>()) bytesToWrite.Add(name, bytes);
        var targetNames = bytesToWrite.Keys.Concat(deletes).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        var originals = targetNames.ToDictionary(
            name => name,
            name => File.Exists(Path.Combine(_dataRoot, name))
                ? File.ReadAllBytes(Path.Combine(_dataRoot, name))
                : null,
            StringComparer.OrdinalIgnoreCase);
        var staged = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            foreach (var (name, bytes) in bytesToWrite)
            {
                var temporary = Path.Combine(_dataRoot, $".{name}.{Guid.NewGuid():N}.tmp");
                using var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write,
                    FileShare.None, 4096, FileOptions.WriteThrough);
                stream.Write(bytes);
                stream.Flush(true);
                staged[name] = temporary;
            }

            RequireCurrentMutation(isCurrent);
            foreach (var (name, temporary) in staged)
            {
                File.Move(temporary, Path.Combine(_dataRoot, name), overwrite: true);
            }
            foreach (var name in deletes)
            {
                var target = Path.Combine(_dataRoot, name);
                if (File.Exists(target)) File.Delete(target);
            }
            // A source change during durable writes invalidates the activation;
            // rollback happens under the same storage gate before publishing.
            RequireCurrentMutation(isCurrent);
        }
        catch
        {
            foreach (var (name, bytes) in originals)
            {
                var target = Path.Combine(_dataRoot, name);
                if (bytes is null)
                {
                    try { if (File.Exists(target)) File.Delete(target); } catch { }
                    continue;
                }
                try
                {
                    var rollback = Path.Combine(_dataRoot, $".{name}.{Guid.NewGuid():N}.rollback");
                    File.WriteAllBytes(rollback, bytes);
                    File.Move(rollback, target, overwrite: true);
                }
                catch { }
            }
            throw;
        }
        finally
        {
            foreach (var temporary in staged.Values)
            {
                try { if (File.Exists(temporary)) File.Delete(temporary); } catch { }
            }
        }
    }

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
        var primary = Path.Combine(_dataRoot, fileName);
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

    private OverlayWorkspaceHotkeySnapshot ReadHotkey(IDictionary<string, string> observed)
    {
        var primary = Path.Combine(_dataRoot, DesktopConfigFile);
        var source = File.Exists(primary)
            ? primary
            : _fallbackRoot is null ? null : Path.Combine(_fallbackRoot, DesktopConfigFile);
        if (source is null || !File.Exists(source))
        {
            return new OverlayWorkspaceHotkeySnapshot(DefaultHotkey, true, "unavailable");
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
        return new OverlayWorkspaceHotkeySnapshot(binding, enabled, "unavailable");
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
