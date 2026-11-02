import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_schema.dart';

// Reuses the complete schema fixture pattern from overlay_settings_test.dart.
// Test data only; this is not a user account or a preview acceptance path.
Map<String, Object?> loadingWorkspacePayload() {
  final settings = <String, Object?>{
    'hideMissionWhenIdle': false,
    'showMission': false,
  };
  for (final field in overlayWorkspaceFieldSpecs) {
    settings[field.field] = switch (field.kind) {
      OverlayWorkspaceFieldKind.toggle => false,
      OverlayWorkspaceFieldKind.choice ||
      OverlayWorkspaceFieldKind.readOnlyChoice => field.options.first,
      OverlayWorkspaceFieldKind.numberChoice => field.numberOptions.first,
      OverlayWorkspaceFieldKind.number =>
        field.field == 'eventNotificationMaxVisibleCount' ||
                field.field == 'chatMaxVisibleCount'
            ? field.minimum.round()
            : field.minimum,
      OverlayWorkspaceFieldKind.color => '#FFFFFF',
      OverlayWorkspaceFieldKind.hotkey => '',
      OverlayWorkspaceFieldKind.eventTypes => 0,
      OverlayWorkspaceFieldKind.eventDurations => <String, Object?>{},
    };
  }
  settings['eventNotificationDurations'] = <String, Object?>{
    for (final name in const [
      'memberPresence', 'memberServer', 'sameServer', 'shipChange',
      'locationChange', 'squadChange', 'commanderChange', 'onlineSummary',
      'primaryServer', 'deathAndRespawn', 'localPlayReminder',
    ]) name: 0,
  };
  final layout = List.generate(4, (i) => <String, Object?>{
        'key': ['Notice', 'Squads', 'Members', 'Chat'][i],
        'x': i * .1, 'y': i * .1, 'width': .2, 'height': .1,
        'horizontalAnchor': 'Center', 'verticalAnchor': 'Middle',
        'isLocked': false, 'textOpacity': 1.0, 'backgroundOpacity': .5,
      });
  return {
    'schemaVersion': 1, 'revision': 1, 'storageState': 'ready',
    'activePresetId': 'fixture', 'renderMode': 'DirectComposition',
    'appearances': [
      {
        'id': 'Default', 'displayNameZh': '默认', 'displayNameEn': 'Default',
        'summaryZh': '测试', 'summaryEn': 'Fixture',
        'traitsZh': ['默认'], 'traitsEn': ['Default'],
        'previewSurface': '#081722', 'previewPrimary': '#29AFFF',
        'previewSecondary': '#69CCFF', 'locksTheme': false,
        'supportsBloom': false, 'startupTransition': 'BridgeTerminal',
        'requiresEntitlement': false, 'isReleased': true, 'isAvailable': true,
      },
    ],
    'hotkey': {'binding': 'Ctrl+Shift+O', 'enabled': false, 'runtimeState': 'unavailable'},
    'settings': settings, 'layout': layout,
    'presets': [
      {'id': 'fixture', 'name': 'Fixture', 'isActive': true,
       'storageState': 'ready', 'settings': settings, 'layout': layout},
    ],
  };
}

const loadingRuntimePayload = <String, Object?>{
  'schemaVersion': 1, 'windowState': 'closed', 'isVisible': false,
  'appliedRevision': 1, 'hotkeyState': 'disabled', 'followGameState': 'manual',
  'requestedSkin': 'Default', 'effectiveSkin': 'Default',
  'usedFallbackSkin': false, 'retryable': false,
};
