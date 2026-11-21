import 'package:flutter/material.dart';

import 'overlay_chat_sources_field.dart';
import 'overlay_scene_controller.dart';
import 'overlay_source_binding_field.dart';
import 'overlay_workspace_controls.dart';
import 'overlay_workspace_global_group.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_module.dart';
import 'overlay_workspace_module_style_controls.dart';
import 'overlay_workspace_schema.dart';

/// A block group's own information source, chosen on the settings page only
/// (11-13 user, 请你定 3: the full-screen editor keeps to position and look);
/// null for a group without one, or while plans carry no sources. The overview has none: it follows
/// the members (D6, 请你定 7).
Widget? overlayWorkspaceModuleSourceField(
  String group,
  OverlayWorkspaceProjection projection,
  OverlayWorkspaceModule module,
  OverlaySceneController? scenes,
) {
  final source = switch (group) {
    'notice' => OverlaySourceModule.notice,
    'members' => OverlaySourceModule.members,
    'chat' => OverlaySourceModule.chat,
    'events' => OverlaySourceModule.events,
    _ => null,
  };
  if (source == null ||
      projection.snapshot?.sourcePresetsEnabled != true ||
      projection.sources == null) {
    return null;
  }
  if (source == OverlaySourceModule.chat) {
    return OverlayChatSourcesField(
      value: projection.sources!,
      scenes: scenes,
      onChanged: projection.busy ? null : module.updateChatSources,
      onSingleChanged: projection.busy
          ? null
          : (value) => module.updateModuleSource(source, value),
    );
  }
  return OverlaySourceBindingField(
    key: Key('overlay-module-source-${source.name}'),
    value: projection.sources!.forModule(source),
    scenes: scenes,
    onChanged: projection.busy
        ? null
        : (value) => module.updateModuleSource(source, value),
  );
}

/// One group's settings in the full-screen editor's tools, laid out as the
/// settings page lays them out (11-13 user, 请你定 3): its settings, then its
/// position, its look (the "外观" heading, the opacities) and lock, and the
/// member picker. Sources are chosen on the settings page only, and the
/// default source is not shown here at all.
class OverlayWorkspaceEditorGroupPanel extends StatelessWidget {
  const OverlayWorkspaceEditorGroupPanel({
    required this.group,
    required this.settings,
    required this.layout,
    required this.selected,
    required this.editOwner,
    required this.onSettingChanged,
    required this.onLayoutChanged,
    required this.position,
    required this.onOpenGlobal,
    this.currentEditOwner,
    this.appearances = const [],
    this.onExperiencePreset,
    this.startupExtra,
    this.footerExtra,
    this.onSizeStep,
    this.layoutLocked = false,
    super.key,
  });

  static const blockGroups = {
    'notice',
    'fleetOverview',
    'members',
    'chat',
    'events',
  };

  final String group;
  final bool layoutLocked;
  final void Function(String field, Object? value)? onSizeStep;
  final OverlayWorkspaceSettings settings;
  final List<OverlayWorkspaceLayoutItem> layout;
  final OverlayWorkspaceLayoutItem? selected;
  final Object? editOwner;
  final Object? Function()? currentEditOwner;
  final List<OverlayWorkspaceAppearance> appearances;
  final void Function(String field, Object? value) onSettingChanged;
  final void Function(OverlayWorkspaceLayoutItem item, bool coalesce)
  onLayoutChanged;
  final ValueChanged<String>? onExperiencePreset;

  /// The selected block's position controls (the editor's inspector).
  final Widget Function(OverlayWorkspaceLayoutItem item) position;
  final VoidCallback onOpenGlobal;
  final Widget? startupExtra, footerExtra;

  @override
  Widget build(BuildContext context) {
    if (group == OverlayWorkspaceGlobalGroup.group) {
      return OverlayWorkspaceGlobalGroup(
        settings: settings,
        onChanged: onSettingChanged,
        onExperiencePreset: onExperiencePreset,
        appearances: appearances,
        editOwner: editOwner,
        currentEditOwner: currentEditOwner,
      );
    }
    final block = blockGroups.contains(group);
    final item = selected;
    return OverlayWorkspaceSettingsGroup(
      group: group,
      editOwner: editOwner,
      currentEditOwner: currentEditOwner,
      fields: [
        for (final spec in overlayWorkspaceFieldSpecs)
          if (spec.group == group && spec.field != 'scenePreference') spec,
      ],
      settings: settings,
      appearances: appearances,
      onChanged: onSettingChanged,
      onExperiencePreset: onExperiencePreset,
      footer: group == 'startup'
          ? startupExtra
          : block
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (item != null && group != 'events') position(item),
                OverlayWorkspaceModuleStyleControls(
                  onSizeStep: onSizeStep,
                  layoutLocked: layoutLocked,
                  group: group,
                  layout: layout,
                  settings: settings,
                  onLayoutChanged: onLayoutChanged,
                  onSettingChanged: onSettingChanged,
                  onOpenGlobal: onOpenGlobal,
                ),
                ?footerExtra,
              ],
            )
          : null,
    );
  }
}
