import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';

/// What a real Host returns after `saveActive`: the written draft becomes the
/// active plan's saved state and the revision advances. Test ports use this so
/// direct save sees the same facts as with the Host.
OverlayWorkspaceSnapshot savedOverlaySnapshot(
  OverlayWorkspaceSnapshot current,
  OverlayWorkspaceMutation save,
) => OverlayWorkspaceSnapshot.available(
  revision: current.revision! + 1,
  storageState: current.storageState!,
  activePresetId: current.activePresetId!,
  renderMode: save.renderMode ?? current.renderMode!,
  appearances: current.appearances,
  hotkey: save.hotkey == null
      ? current.hotkey!
      : OverlayWorkspaceHotkey(
          binding: save.hotkey!.binding,
          enabled: save.hotkey!.enabled,
          runtimeState: current.hotkey!.runtimeState,
        ),
  settings: save.settings ?? current.settings!,
  layout: save.layout ?? current.layout,
  presets: [
    for (final preset in current.presets)
      preset.isActive
          ? OverlayWorkspacePreset(
              id: preset.id,
              name: preset.name,
              isActive: true,
              storageState: preset.storageState,
              settings: save.settings ?? preset.settings,
              layout: save.layout ?? preset.layout,
              sources: save.sources ?? preset.sources,
              appearanceOptions:
                  save.appearanceOptions ?? preset.appearanceOptions,
            )
          : preset,
  ],
  sourcePresetsEnabled: current.sourcePresetsEnabled,
  removedOrganizationBindings: current.removedOrganizationBindings,
  appearanceOptionsEnabled: current.appearanceOptionsEnabled,
  appearanceConfigurations: current.appearanceConfigurations,
  livePreviewAppearanceIds: current.livePreviewAppearanceIds,
  appearanceProgressIds: current.appearanceProgressIds,
  appearanceOptions: save.appearanceOptions ?? current.appearanceOptions,
);
