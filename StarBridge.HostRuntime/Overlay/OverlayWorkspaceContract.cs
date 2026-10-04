namespace StarBridge.HostRuntime.Overlay;

using StarBridge.Core.Overlay;

internal static class OverlayWorkspaceSchema
{
    internal const int Version = 1;
}

internal sealed record OverlayWorkspacePresetSnapshot(
    string Id,
    string Name,
    bool IsActive,
    OverlayDisplaySettings Settings,
    IReadOnlyList<InformationOverlayLayoutItem> Layout,
    string StorageState,
    OverlayPresetSources? Sources = null);

internal sealed record OverlayWorkspaceHotkeySnapshot(
    string Binding,
    bool Enabled,
    string RuntimeState);

internal sealed record OverlayWorkspaceReadResult(
    int SchemaVersion,
    long Revision,
    string StorageState,
    string ActivePresetId,
    string RenderMode,
    OverlayWorkspaceHotkeySnapshot Hotkey,
    OverlayDisplaySettings Settings,
    IReadOnlyList<InformationOverlayLayoutItem> Layout,
    IReadOnlyList<OverlayWorkspacePresetSnapshot> Presets,
    bool RemovedOrganizationBindings = false,
    bool SourcePresetsEnabled = false);

internal enum OverlayWorkspaceMutationKind
{
    SaveActive,
    ActivatePreset,
    CreatePreset,
    DuplicatePreset,
    RenamePreset,
    DeletePreset,
    ResetPreset,
    ImportPreset,
    ConfigurePresetSources
}

internal sealed record OverlayWorkspaceMutation(
    long ExpectedRevision,
    OverlayWorkspaceMutationKind Kind,
    string? PresetId = null,
    string? Name = null,
    OverlayDisplaySettings? Settings = null,
    IReadOnlyList<InformationOverlayLayoutItem>? Layout = null,
    string? RenderMode = null,
    OverlayWorkspaceHotkeySnapshot? Hotkey = null,
    OverlayPresetSources? Sources = null,
    string? ReplaceAutoSwitchPresetId = null);

internal interface IOverlayWorkspaceStore
{
    OverlayWorkspaceReadResult Load();

    OverlayWorkspaceReadResult Apply(OverlayWorkspaceMutation mutation, Func<bool>? isCurrent = null);
}
