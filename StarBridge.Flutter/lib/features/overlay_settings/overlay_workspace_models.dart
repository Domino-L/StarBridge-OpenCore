import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'overlay_settings_models.dart';
import 'overlay_workspace_layout_item.dart';
import 'overlay_workspace_schema.dart';

export 'overlay_workspace_layout_item.dart';

enum OverlayWorkspaceAvailability { unavailable, available }

enum OverlayRuntimeAction { getState, open, close, retry }

enum OverlayRuntimeOperation { none, reading, opening, closing, retrying }

@immutable
final class OverlayWorkspaceRuntimeDraft {
  const OverlayWorkspaceRuntimeDraft({
    required this.expectedRevision,
    required this.settings,
    required this.layout,
    required this.hotkey,
  });

  final int expectedRevision;
  final OverlayWorkspaceSettings settings;
  final List<OverlayWorkspaceLayoutItem> layout;
  final OverlayWorkspaceHotkey hotkey;

  Map<String, Object?> toMap() => <String, Object?>{
    'expectedRevision': expectedRevision,
    'settings': settings.toMap(),
    'layout': layout.map((item) => item.toMap()).toList(growable: false),
    'hotkey': hotkey.toUpdateMap(),
  };
}

@immutable
final class OverlayRuntimeSnapshot {
  const OverlayRuntimeSnapshot({
    required this.windowState,
    required this.isVisible,
    required this.appliedRevision,
    required this.hotkeyState,
    required this.followGameState,
    required this.requestedSkin,
    required this.effectiveSkin,
    required this.usedFallbackSkin,
    this.failureCode,
    this.retryable = false,
  });

  const OverlayRuntimeSnapshot.unavailable({
    this.failureCode = 'overlay.runtime_unavailable',
  }) : windowState = 'unavailable',
       isVisible = false,
       appliedRevision = 0,
       hotkeyState = 'unavailable',
       followGameState = 'unavailable',
       requestedSkin = 'Default',
       effectiveSkin = 'Default',
       usedFallbackSkin = false,
       retryable = true;

  final String windowState;
  final bool isVisible;
  final int appliedRevision;
  final String hotkeyState;
  final String followGameState;
  final String requestedSkin;
  final String effectiveSkin;
  final bool usedFallbackSkin;
  final String? failureCode;
  final bool retryable;

  bool get available => windowState != 'unavailable';
  bool get failed => windowState == 'failed';

  factory OverlayRuntimeSnapshot.fromMap(Map<String, Object?> source) {
    const requiredFields = <String>{
      'schemaVersion',
      'windowState',
      'isVisible',
      'appliedRevision',
      'hotkeyState',
      'followGameState',
      'requestedSkin',
      'effectiveSkin',
      'usedFallbackSkin',
      'retryable',
    };
    const optionalFields = <String>{'failureCode'};
    final fields = source.keys.toSet();
    final windowState = source['windowState'];
    final isVisible = source['isVisible'];
    final appliedRevision = source['appliedRevision'];
    final hotkeyState = source['hotkeyState'];
    final followGameState = source['followGameState'];
    final requestedSkin = source['requestedSkin'];
    final effectiveSkin = source['effectiveSkin'];
    final usedFallbackSkin = source['usedFallbackSkin'];
    final failureCode = source['failureCode'];
    final retryable = source['retryable'];
    if (!fields.containsAll(requiredFields) ||
        fields.difference(requiredFields.union(optionalFields)).isNotEmpty ||
        source['schemaVersion'] != 1 ||
        windowState is! String ||
        !const {
          'unavailable',
          'closed',
          'open',
          'failed',
        }.contains(windowState) ||
        isVisible is! bool ||
        appliedRevision is! int ||
        appliedRevision < 0 ||
        hotkeyState is! String ||
        !const {
          'unavailable',
          'disabled',
          'invalid',
          'registered',
          'gameCompatibleOnly',
          'desktopOnly',
          'conflict',
          'failed',
        }.contains(hotkeyState) ||
        followGameState is! String ||
        !const {
          'unavailable',
          'manual',
          'followingGame',
          'gameInBackground',
          'waitingForGame',
        }.contains(followGameState) ||
        requestedSkin is! String ||
        requestedSkin.isEmpty ||
        effectiveSkin is! String ||
        effectiveSkin.isEmpty ||
        usedFallbackSkin is! bool ||
        (failureCode != null && failureCode is! String) ||
        retryable is! bool ||
        isVisible != (windowState == 'open')) {
      throw const FormatException('Invalid overlay runtime response.');
    }
    return OverlayRuntimeSnapshot(
      windowState: windowState,
      isVisible: isVisible,
      appliedRevision: appliedRevision,
      hotkeyState: hotkeyState,
      followGameState: followGameState,
      requestedSkin: requestedSkin,
      effectiveSkin: effectiveSkin,
      usedFallbackSkin: usedFallbackSkin,
      failureCode: failureCode as String?,
      retryable: retryable,
    );
  }
}

@immutable
final class OverlayWorkspaceAppearance {
  const OverlayWorkspaceAppearance({
    required this.id,
    required this.displayNameZh,
    required this.displayNameEn,
    required this.summaryZh,
    required this.summaryEn,
    required this.traitsZh,
    required this.traitsEn,
    required this.previewSurface,
    required this.previewPrimary,
    required this.previewSecondary,
    required this.locksTheme,
    required this.supportsBloom,
    required this.startupTransition,
    required this.requiresEntitlement,
    required this.isReleased,
    required this.isAvailable,
    bool? isPreviewAvailable,
  }) : _previewAvailable = isPreviewAvailable;

  final String id;
  final String displayNameZh;
  final String displayNameEn;
  final String summaryZh;
  final String summaryEn;
  final List<String> traitsZh;
  final List<String> traitsEn;
  final String previewSurface;
  final String previewPrimary;
  final String previewSecondary;
  final bool locksTheme;
  final bool supportsBloom;
  final String startupTransition;
  final bool requiresEntitlement;
  final bool isReleased;
  final bool isAvailable;
  final bool? _previewAvailable;

  bool get isPreviewAvailable => _previewAvailable ?? isReleased;

  factory OverlayWorkspaceAppearance.fromMap(Map<String, Object?> source) {
    const fields = <String>{
      'id',
      'displayNameZh',
      'displayNameEn',
      'summaryZh',
      'summaryEn',
      'traitsZh',
      'traitsEn',
      'previewSurface',
      'previewPrimary',
      'previewSecondary',
      'locksTheme',
      'supportsBloom',
      'startupTransition',
      'requiresEntitlement',
      'isReleased',
      'isAvailable',
    };
    if (!setEquals(source.keys.toSet(), fields) &&
        !setEquals(source.keys.toSet(), {...fields, 'isPreviewAvailable'})) {
      throw const FormatException('Invalid overlay appearance fields.');
    }
    final id = source['id'];
    final displayNameZh = source['displayNameZh'];
    final displayNameEn = source['displayNameEn'];
    final summaryZh = source['summaryZh'];
    final summaryEn = source['summaryEn'];
    final traitsZh = _appearanceStrings(source['traitsZh']);
    final traitsEn = _appearanceStrings(source['traitsEn']);
    final previewSurface = source['previewSurface'];
    final previewPrimary = source['previewPrimary'];
    final previewSecondary = source['previewSecondary'];
    final locksTheme = source['locksTheme'];
    final supportsBloom = source['supportsBloom'];
    final startupTransition = source['startupTransition'];
    final requiresEntitlement = source['requiresEntitlement'];
    final isReleased = source['isReleased'];
    final isAvailable = source['isAvailable'];
    final isPreviewAvailable = source['isPreviewAvailable'];
    final color = RegExp(r'^#[0-9A-Fa-f]{6}$');
    if (id is! String ||
        id.isEmpty ||
        displayNameZh is! String ||
        displayNameZh.isEmpty ||
        displayNameEn is! String ||
        displayNameEn.isEmpty ||
        summaryZh is! String ||
        summaryEn is! String ||
        traitsZh.isEmpty ||
        traitsEn.isEmpty ||
        previewSurface is! String ||
        !color.hasMatch(previewSurface) ||
        previewPrimary is! String ||
        !color.hasMatch(previewPrimary) ||
        previewSecondary is! String ||
        !color.hasMatch(previewSecondary) ||
        locksTheme is! bool ||
        supportsBloom is! bool ||
        startupTransition is! String ||
        startupTransition.isEmpty ||
        requiresEntitlement is! bool ||
        isReleased is! bool ||
        isAvailable is! bool ||
        (source.containsKey('isPreviewAvailable') &&
            isPreviewAvailable is! bool) ||
        (isAvailable && !isReleased) ||
        (isReleased && !requiresEntitlement && !isAvailable)) {
      throw const FormatException('Invalid overlay appearance values.');
    }
    return OverlayWorkspaceAppearance(
      id: id,
      displayNameZh: displayNameZh,
      displayNameEn: displayNameEn,
      summaryZh: summaryZh,
      summaryEn: summaryEn,
      traitsZh: traitsZh,
      traitsEn: traitsEn,
      previewSurface: previewSurface.toUpperCase(),
      previewPrimary: previewPrimary.toUpperCase(),
      previewSecondary: previewSecondary.toUpperCase(),
      locksTheme: locksTheme,
      supportsBloom: supportsBloom,
      startupTransition: startupTransition,
      requiresEntitlement: requiresEntitlement,
      isReleased: isReleased,
      isAvailable: isAvailable,
      isPreviewAvailable: isPreviewAvailable as bool?,
    );
  }

  OverlayWorkspaceAppearance copyWith({
    bool? isReleased,
    bool? isAvailable,
    bool? isPreviewAvailable,
  }) => OverlayWorkspaceAppearance(
    id: id,
    displayNameZh: displayNameZh,
    displayNameEn: displayNameEn,
    summaryZh: summaryZh,
    summaryEn: summaryEn,
    traitsZh: traitsZh,
    traitsEn: traitsEn,
    previewSurface: previewSurface,
    previewPrimary: previewPrimary,
    previewSecondary: previewSecondary,
    locksTheme: locksTheme,
    supportsBloom: supportsBloom,
    startupTransition: startupTransition,
    requiresEntitlement: requiresEntitlement,
    isReleased: isReleased ?? this.isReleased,
    isAvailable: isAvailable ?? this.isAvailable,
    isPreviewAvailable: isPreviewAvailable ?? _previewAvailable,
  );
}

List<String> _appearanceStrings(Object? source) {
  if (source is! List ||
      source.isEmpty ||
      source.any((value) => value is! String)) {
    throw const FormatException('Invalid overlay appearance text.');
  }
  return List<String>.unmodifiable(source.cast<String>());
}

@immutable
final class OverlayWorkspaceSettings {
  OverlayWorkspaceSettings._(Map<String, Object?> values)
    : values = UnmodifiableMapView(values);

  static const requiredFields = <String>{
    'hideMissionWhenIdle',
    'memberNameMode',
    'hideOfflineMembers',
    'hideSquadIcons',
    'enableTrayMode',
    'opacity',
    'showNotice',
    'showSquads',
    'showMission',
    'showMembers',
    'skin',
    'theme',
    'autoThemeByShip',
    'showCrosshair',
    'crosshairMode',
    'crosshairUseThemeColor',
    'crosshairColor',
    'crosshairSize',
    'crosshairThickness',
    'crosshairOpacity',
    'crosshairShowCenterMark',
    'crosshairCenterMarkSize',
    'crosshairGap',
    'crosshairOutlineOpacity',
    'enableStartupTransition',
    'startupTransitionStyle',
    'autoFocusGameWindowOnOpen',
    'startupTransitionFollowOverlayTheme',
    'startupTransitionFrameRate',
    'autoOpenOverlayOnGameStart',
    'autoOpenOverlayOnGameForeground',
    'autoCloseOverlayOnGameBackground',
    'showEventNotifications',
    'eventNotificationSide',
    'eventNotificationDurationSeconds',
    'eventNotificationY',
    'hideMemberOnlineStatus',
    'squadStatusDisplayMode',
    'hideSelfMember',
    'memberPriorityMode',
    'memberScopeMode',
    'memberNameColumnRatio',
    'eventNotificationTypes',
    'eventNotificationMaxVisibleCount',
    'eventNotificationPinImportant',
    'eventNotificationAnimationSpeed',
    'eventNotificationDurations',
    'nightShadowBloom',
    'animationFrameRate',
    'scenePreference',
    'showChat',
    'chatDisplayMode',
    'chatSide',
    'chatMaxVisibleCount',
    'chatDurationSeconds',
    'chatShowSender',
    'chatShowTimestamp',
    'chatShowSystemMessages',
    'chatHideSelfMessages',
    'chatBarrageFontSize',
    'chatBarrageRegion',
    'chatBarrageDensity',
    'chatBarrageAvoidCenter',
    'chatTextEdgeStrength',
    'communicationFriendEvents',
    'communicationMessagePreview',
    'communicationEventDurationSeconds',
    'fleetChatScope',
    'eventNotificationTextOpacity',
    'eventNotificationBackgroundOpacity',
    'eventNotificationDecorationOpacity',
    'skipStartupTransitionWhenGameForeground',
    'requestedSkin',
  };

  static const _durationFields = <String>{
    'memberPresence',
    'memberServer',
    'sameServer',
    'shipChange',
    'locationChange',
    'squadChange',
    'commanderChange',
    'onlineSummary',
    'primaryServer',
    'deathAndRespawn',
    'localPlayReminder',
  };

  final Map<String, Object?> values;

  factory OverlayWorkspaceSettings.fromMap(Map<String, Object?> source) {
    source = Map<String, Object?>.from(source)
      ..putIfAbsent('eventNotificationDecorationOpacity', () => 1.0);
    if (!setEquals(source.keys.toSet(), requiredFields)) {
      throw const FormatException('Incomplete overlay workspace settings.');
    }
    final durations = stringMap(source['eventNotificationDurations']);
    if (!setEquals(durations.keys.toSet(), _durationFields) ||
        durations.values.any(
          (value) =>
              value is! num || !value.isFinite || value < 0 || value > 30,
        )) {
      throw const FormatException('Invalid overlay event durations.');
    }
    for (final field in overlayWorkspaceFieldSpecs) {
      final value = source[field.field];
      final valid = switch (field.kind) {
        OverlayWorkspaceFieldKind.toggle => value is bool,
        OverlayWorkspaceFieldKind.choice ||
        OverlayWorkspaceFieldKind.readOnlyChoice =>
          value is String && field.options.contains(value),
        OverlayWorkspaceFieldKind.numberChoice =>
          value is num &&
              value.isFinite &&
              field.numberOptions.any(
                (option) => option.toDouble() == value.toDouble(),
              ),
        OverlayWorkspaceFieldKind.number =>
          value is num &&
              value.isFinite &&
              value >= field.minimum &&
              value <= field.maximum &&
              (!_integerFields.contains(field.field) || value is int),
        OverlayWorkspaceFieldKind.color =>
          value is String && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value),
        OverlayWorkspaceFieldKind.eventTypes =>
          value is int && value >= 0 && (value & ~_eventTypeMask) == 0,
        OverlayWorkspaceFieldKind.eventDurations => true,
      };
      if (!valid) {
        throw FormatException('Invalid overlay setting: ${field.field}.');
      }
    }
    if (source['hideMissionWhenIdle'] is! bool ||
        source['showMission'] is! bool) {
      throw const FormatException(
        'Invalid retired overlay compatibility state.',
      );
    }
    final copy = Map<String, Object?>.from(source);
    copy['eventNotificationDurations'] = UnmodifiableMapView(durations);
    return OverlayWorkspaceSettings._(copy);
  }

  Object? operator [](String field) => values[field];

  static const _integerFields = <String>{
    'eventNotificationMaxVisibleCount',
    'chatMaxVisibleCount',
  };

  static const _eventTypeMask = 1 | 2 | 4 | 8 | 16 | 128 | 256 | 512 | 1024;

  OverlayWorkspaceSettings withValue(String field, Object? value) {
    if (!requiredFields.contains(field)) {
      throw ArgumentError.value(field, 'field', 'Unknown overlay setting.');
    }
    return OverlayWorkspaceSettings.fromMap(
      Map<String, Object?>.from(values)..[field] = value,
    );
  }

  Map<String, Object?> toMap() => Map<String, Object?>.from(values);
}

@immutable
final class OverlayWorkspacePreset {
  const OverlayWorkspacePreset({
    required this.id,
    required this.name,
    required this.isActive,
    required this.storageState,
    required this.settings,
    required this.layout,
  });

  final String id;
  final String name;
  final bool isActive;
  final String storageState;
  final OverlayWorkspaceSettings settings;
  final List<OverlayWorkspaceLayoutItem> layout;

  factory OverlayWorkspacePreset.fromMap(Map<String, Object?> source) {
    final id = source['id'];
    final name = source['name'];
    final isActive = source['isActive'];
    final storageState = source['storageState'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.isEmpty ||
        isActive is! bool ||
        storageState is! String) {
      throw const FormatException('Invalid overlay preset.');
    }
    return OverlayWorkspacePreset(
      id: id,
      name: name,
      isActive: isActive,
      storageState: storageState,
      settings: OverlayWorkspaceSettings.fromMap(stringMap(source['settings'])),
      layout: objectList(source['layout'])
          .map((item) => OverlayWorkspaceLayoutItem.fromMap(stringMap(item)))
          .toList(growable: false),
    );
  }
}

@immutable
final class OverlayWorkspaceHotkey {
  const OverlayWorkspaceHotkey({
    required this.binding,
    required this.enabled,
    required this.runtimeState,
  });

  final String binding;
  final bool enabled;
  final String runtimeState;

  factory OverlayWorkspaceHotkey.fromMap(Map<String, Object?> source) {
    const fields = <String>{'binding', 'enabled', 'runtimeState'};
    final binding = source['binding'];
    final enabled = source['enabled'];
    final runtimeState = source['runtimeState'];
    if (!setEquals(source.keys.toSet(), fields) ||
        binding is! String ||
        binding.isEmpty ||
        enabled is! bool ||
        runtimeState is! String ||
        runtimeState.isEmpty) {
      throw const FormatException('Invalid overlay hotkey state.');
    }
    return OverlayWorkspaceHotkey(
      binding: binding,
      enabled: enabled,
      runtimeState: runtimeState,
    );
  }

  Map<String, Object?> toUpdateMap() => {
    'binding': binding,
    'enabled': enabled,
  };
}

enum OverlayWorkspaceMutationKind {
  saveActive,
  activatePreset,
  createPreset,
  duplicatePreset,
  renamePreset,
  deletePreset,
  resetPreset,
  importPreset,
}

@immutable
final class OverlayWorkspaceMutation {
  const OverlayWorkspaceMutation._({
    required this.kind,
    this.presetId,
    this.name,
    this.settings,
    this.layout,
    this.renderMode,
    this.hotkey,
  });

  const OverlayWorkspaceMutation.saveActive({
    required OverlayWorkspaceSettings settings,
    required List<OverlayWorkspaceLayoutItem> layout,
    required String renderMode,
    required OverlayWorkspaceHotkey hotkey,
  }) : this._(
         kind: OverlayWorkspaceMutationKind.saveActive,
         settings: settings,
         layout: layout,
         renderMode: renderMode,
         hotkey: hotkey,
       );

  const OverlayWorkspaceMutation.activatePreset(String presetId)
    : this._(
        kind: OverlayWorkspaceMutationKind.activatePreset,
        presetId: presetId,
      );

  const OverlayWorkspaceMutation.createPreset(String name)
    : this._(kind: OverlayWorkspaceMutationKind.createPreset, name: name);

  const OverlayWorkspaceMutation.duplicatePreset(String presetId, String name)
    : this._(
        kind: OverlayWorkspaceMutationKind.duplicatePreset,
        presetId: presetId,
        name: name,
      );

  const OverlayWorkspaceMutation.renamePreset(String presetId, String name)
    : this._(
        kind: OverlayWorkspaceMutationKind.renamePreset,
        presetId: presetId,
        name: name,
      );

  const OverlayWorkspaceMutation.deletePreset(String presetId)
    : this._(
        kind: OverlayWorkspaceMutationKind.deletePreset,
        presetId: presetId,
      );

  const OverlayWorkspaceMutation.resetPreset(String presetId)
    : this._(
        kind: OverlayWorkspaceMutationKind.resetPreset,
        presetId: presetId,
      );

  const OverlayWorkspaceMutation.importPreset({
    required String name,
    required OverlayWorkspaceSettings settings,
    required List<OverlayWorkspaceLayoutItem> layout,
  }) : this._(
         kind: OverlayWorkspaceMutationKind.importPreset,
         name: name,
         settings: settings,
         layout: layout,
       );

  final OverlayWorkspaceMutationKind kind;
  final String? presetId;
  final String? name;
  final OverlayWorkspaceSettings? settings;
  final List<OverlayWorkspaceLayoutItem>? layout;
  final String? renderMode;
  final OverlayWorkspaceHotkey? hotkey;

  Map<String, Object?> toPayload(int expectedRevision) {
    return <String, Object?>{
      'schemaVersion': 1,
      'expectedRevision': expectedRevision,
      'action': kind.name,
      if (presetId != null) 'presetId': presetId,
      if (name != null) 'name': name,
      if (settings != null) 'settings': settings!.toMap(),
      if (layout != null)
        'layout': layout!.map((item) => item.toMap()).toList(growable: false),
      if (renderMode != null) 'renderMode': renderMode,
      if (hotkey != null) 'hotkey': hotkey!.toUpdateMap(),
    };
  }
}

@immutable
final class OverlayWorkspaceWriteResult {
  const OverlayWorkspaceWriteResult.completed(this.snapshot) : failure = null;
  const OverlayWorkspaceWriteResult.failed(this.failure) : snapshot = null;

  final OverlayWorkspaceSnapshot? snapshot;
  final OverlaySettingsFailure? failure;
  bool get completed => snapshot != null;
}

@immutable
final class OverlayWorkspaceSnapshot {
  const OverlayWorkspaceSnapshot._({
    required this.availability,
    this.revision,
    this.storageState,
    this.activePresetId,
    this.renderMode,
    this.appearances = const [],
    this.hotkey,
    this.settings,
    this.layout = const [],
    this.presets = const [],
    this.failure,
  });

  const OverlayWorkspaceSnapshot.unavailable({
    OverlaySettingsFailure failure = OverlaySettingsFailure.hostUnavailable,
  }) : this._(
         availability: OverlayWorkspaceAvailability.unavailable,
         failure: failure,
       );

  const OverlayWorkspaceSnapshot.available({
    required int revision,
    required String storageState,
    required String activePresetId,
    required String renderMode,
    required List<OverlayWorkspaceAppearance> appearances,
    required OverlayWorkspaceHotkey hotkey,
    required OverlayWorkspaceSettings settings,
    required List<OverlayWorkspaceLayoutItem> layout,
    required List<OverlayWorkspacePreset> presets,
  }) : this._(
         availability: OverlayWorkspaceAvailability.available,
         revision: revision,
         storageState: storageState,
         activePresetId: activePresetId,
         renderMode: renderMode,
         appearances: appearances,
         hotkey: hotkey,
         settings: settings,
         layout: layout,
         presets: presets,
       );

  final OverlayWorkspaceAvailability availability;
  final int? revision;
  final String? storageState;
  final String? activePresetId;
  final String? renderMode;
  final List<OverlayWorkspaceAppearance> appearances;
  final OverlayWorkspaceHotkey? hotkey;
  final OverlayWorkspaceSettings? settings;
  final List<OverlayWorkspaceLayoutItem> layout;
  final List<OverlayWorkspacePreset> presets;
  final OverlaySettingsFailure? failure;
}

Map<String, Object?> stringMap(Object? value) {
  if (value is! Map) {
    throw const FormatException('Expected an object.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException('Expected string object keys.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

List<Object?> objectList(Object? value) {
  if (value is! List) {
    throw const FormatException('Expected a list.');
  }
  return List<Object?>.from(value);
}
