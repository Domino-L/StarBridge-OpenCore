import 'dart:ui';

import '../../features/overlay_settings/overlay_preset_name.dart';
import '../../features/overlay_settings/overlay_preset_sources.dart';
import '../../features/overlay_settings/overlay_scene_controller.dart';
import '../../features/overlay_settings/overlay_scene_projection.dart';
import '../../features/overlay_settings/overlay_workspace_module.dart';
import '../localization/app_strings.dart';
import '../shell/chrome/overlay_source_labels.dart';

/// Quick-panel module key → the workspace setting that shows it.
const menuHudQuickFields = {
  'Notice': 'showNotice',
  'Squads': 'showSquads',
  'Members': 'showMembers',
  'Chat': 'showChat',
  'Events': 'showEventNotifications',
  'Crosshair': 'showCrosshair',
};

Locale menuHudLocale(String language) {
  final value = language.toLowerCase();
  if (!value.startsWith('zh')) return const Locale('en', 'US');
  return value.contains('tw') || value.contains('hk') || value.contains('hant')
      ? const Locale('zh', 'TW')
      : const Locale('zh', 'CN');
}

/// Pure projection of the primary engine's workspace and source state into
/// the menu wire. Nothing here reads remote content or grants access.
Map<String, Object?> menuHudQuickWire({
  required OverlayWorkspaceProjection workspace,
  required OverlaySceneState? scene,
  required AppStrings strings,
  required bool working,
  Map<String, Object?>? note,
  bool placing = false,
  String placeResult = '',
  bool canUndo = false,
  bool canRedo = false,
}) {
  final available = workspace.available;
  final snapshot = workspace.snapshot;
  final corrupt =
      snapshot?.storageState == 'corrupt' ||
      (snapshot?.presets.any(
            (p) => p.isActive && p.storageState == 'corrupt',
          ) ??
          false);
  final editable =
      available && !workspace.busy && !workspace.dirty && !working && !corrupt;
  String targetName(String? code) =>
      scene?.targets.where((t) => t.code == code).firstOrNull?.name ??
      strings.text('overlay.source.organization');
  String bound(OverlaySourceBinding? binding) => switch (binding?.mode) {
    OverlaySourceMode.auto => strings.text('overlay.source.auto'),
    OverlaySourceMode.room => strings.text('overlay.source.room'),
    OverlaySourceMode.fleet =>
      scene?.fleetLabel(strings.text) ?? strings.text('overlay.source.fleet'),
    OverlaySourceMode.community => targetName(binding!.communityCode),
    _ => '',
  };
  final active = snapshot?.presets.where((p) => p.isActive).firstOrNull;
  // Barrage chat flies across the screen and has no box: the menu must not
  // leave a scrim hole for it or offer it as a placeable module. Placement
  // updates items one by one, so the saved list-mode box is kept as it is.
  final barrage =
      available &&
      workspace.settings!['chatDisplayMode'] == 'FullScreenBarrage';
  return {
    'available': available,
    'editable': editable,
    // Edits save on their own; only a failed save is an unsaved draft here.
    'dirty': available && workspace.dirty && workspace.failure != null,
    'hotkey': workspace.hotkey?.enabled == true
        ? workspace.hotkey!.binding
        : '',
    'presetName': active?.shownName(strings) ?? '',
    'presets': [
      if (available)
        for (final preset in snapshot!.presets.take(64))
          {
            'id': preset.id,
            'name': preset.shownName(strings),
            'bound': bound(preset.sources?.binding),
            'active': preset.isActive,
          },
    ],
    'modules': {
      if (available)
        for (final entry in menuHudQuickFields.entries)
          if (workspace.settings![entry.value] case final bool visible)
            entry.key: visible,
    },
    if (scene != null) 'source': _source(scene, strings, working),
    'note': ?note,
    'placing': placing,
    'placeResult': placeResult,
    'presetId': active?.id ?? '',
    'canUndo': placing && canUndo,
    'canRedo': placing && canRedo,
    'layout': [
      if (available)
        for (final item in workspace.layout.take(8))
          if (!(barrage && item.key == 'Chat')) item.toMap(),
    ],
    if (available)
      'events': {
        'side': workspace.settings!['eventNotificationSide'],
        'y': workspace.settings!['eventNotificationY'],
      },
  };
}

Map<String, Object?> _source(
  OverlaySceneState scene,
  AppStrings strings,
  bool working,
) {
  final view = projectOverlayScene(scene);
  String label(String id) {
    for (final option in view.options) {
      if (option.id == id) {
        return overlaySourceOptionLabel(view, option, strings);
      }
    }
    return id == 'local'
        ? strings.text('overlay.source.localName')
        : strings.text('overlay.source.missing');
  }

  final current = view.preferredSceneId ?? 'auto';
  final actual = view.actualSceneId;
  var text = label(current);
  if (current == 'auto' && actual != null && actual != 'auto') {
    text = '$text · ${label(actual)}';
  }
  return {
    'current': current,
    'label': text,
    'origin': view.selectionOrigin == 'preset'
        ? 'preset'
        : current == 'auto'
        ? 'auto'
        : 'account',
    'canChange': view.canChange && !working,
    'options': [
      for (final option in view.options.take(80))
        {
          'id': option.id,
          'label': overlaySourceOptionLabel(view, option, strings),
          'enabled': option.enabled,
        },
    ],
  };
}
