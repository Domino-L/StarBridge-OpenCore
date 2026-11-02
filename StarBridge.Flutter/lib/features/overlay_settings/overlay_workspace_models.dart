import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'overlay_settings_models.dart';
import 'overlay_preset_sources.dart';
import 'overlay_workspace_layout_item.dart';
import 'overlay_workspace_schema.dart';
import 'overlay_workspace_appearance.dart';
import 'overlay_appearance_options.dart';
import 'overlay_appearance_configuration.dart';
import 'overlay_workspace_hotkey_model.dart';

export 'overlay_workspace_appearance.dart';
export 'overlay_appearance_options.dart';

export 'overlay_workspace_layout_item.dart';
export 'overlay_preset_sources.dart';
export 'overlay_workspace_hotkey_model.dart';

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
    this.sources,
    this.appearanceOptions,
  });

  final int expectedRevision;
  final OverlayWorkspaceSettings settings;
  final List<OverlayWorkspaceLayoutItem> layout;
  final OverlayWorkspaceHotkey hotkey;
  final OverlayPresetSources? sources;
  final OverlayAppearanceOptions? appearanceOptions;

  Map<String, Object?> toMap() => <String, Object?>{
    'expectedRevision': expectedRevision,
    'settings': settings.toMap(),
    'layout': layout.map((item) => item.toMap()).toList(growable: false),
    'hotkey': hotkey.toUpdateMap(),
    if (sources != null) 'sources': sources!.toMap(),
    if (appearanceOptions != null)
      'appearanceOptions': appearanceOptions!.toMap(),
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
    this.hotkeyRegistrationFailures,
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
       retryable = true,
       hotkeyRegistrationFailures = null;

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

  /// Shortcuts Windows refused to register; they stay on Raw Input.
  final String? hotkeyRegistrationFailures;

  bool get available => windowState != 'unavailable';
  bool get failed => windowState == 'failed';
  bool get temporarilyHidden => windowState == 'suppressed';
  bool get enabled => isVisible || temporarilyHidden;

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
    const optionalFields = <String>{
      'failureCode',
      'hotkeyRegistrationFailures',
    };
    final registrationFailures = source['hotkeyRegistrationFailures'];
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
          'opening',
          'open',
          'suppressed',
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
        (registrationFailures != null && registrationFailures is! String) ||
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
      hotkeyRegistrationFailures: registrationFailures as String?,
    );
  }
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
    'calmDisplay',
    'calmWaitSeconds',
    'calmIdleOpacity',
    'calmLitOpacity',
    'calmLightWhen',
    'calmPeekHotkey',
  };

  /// A peek key as the native HUD parses it; empty means unbound.
  static final peekHotkeyPattern = RegExp(
    r'^(?:(?:Ctrl|Alt|Shift|Win)\+)*(?:[A-Z0-9]|F(?:[1-9]|1[0-2]))$',
  );

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

  // 归档外观的旧值迁移；整数编号与 C# 的历史序列化值保持一致。
  static const _archivedAppearanceValues = <String, Set<Object>>{
    'skin': {'lagrangeweave', '2', 2},
    'requestedSkin': {'lagrangeweave', '2', 2},
    'theme': {'lagrangeweave', '14', 14},
    'startupTransitionStyle': {'lagrangeweaveequilibrium', '6', 6},
  };
  static const _archivedAppearanceDefaults = <String, String>{
    'skin': 'Default',
    'requestedSkin': 'Default',
    'theme': 'Default',
    'startupTransitionStyle': 'BridgeTerminal',
  };

  factory OverlayWorkspaceSettings.fromMap(Map<String, Object?> source) {
    source = Map<String, Object?>.from(source)
      ..putIfAbsent('eventNotificationDecorationOpacity', () => 1.0)
      // A Host from before calm display: treat it as an older file (Unset).
      ..putIfAbsent('calmDisplay', () => 'Unset')
      ..putIfAbsent('calmWaitSeconds', () => 10)
      ..putIfAbsent('calmIdleOpacity', () => 0.0)
      ..putIfAbsent('calmLitOpacity', () => 0.0)
      ..putIfAbsent('calmLightWhen', () => 'Relevant')
      ..putIfAbsent('calmPeekHotkey', () => '');
    // An archived skin takes its locked theme and transition with it; an archived
    // theme or transition on another, valid appearance is replaced alone.
    final archived = {
      for (final entry in _archivedAppearanceValues.entries)
        if (entry.value.contains(
          source[entry.key] is String
              ? (source[entry.key] as String).trim().toLowerCase()
              : source[entry.key],
        ))
          entry.key,
    };
    final archivedSkin =
        archived.contains('skin') || archived.contains('requestedSkin');
    for (final field
        in archivedSkin ? _archivedAppearanceDefaults.keys : archived) {
      source[field] = _archivedAppearanceDefaults[field];
    }
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
        OverlayWorkspaceFieldKind.hotkey =>
          value is String &&
              (value.isEmpty || peekHotkeyPattern.hasMatch(value)),
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
    this.sources,
    this.appearanceOptions = const OverlayAppearanceOptions.empty(),
  });

  final String id;
  final String name;
  final bool isActive;
  final String storageState;
  final OverlayWorkspaceSettings settings;
  final List<OverlayWorkspaceLayoutItem> layout;
  final OverlayPresetSources? sources;
  final OverlayAppearanceOptions appearanceOptions;

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
      sources: source['sources'] == null
          ? null
          : OverlayPresetSources.fromMap(stringMap(source['sources'])),
      appearanceOptions: source.containsKey('appearanceOptions')
          ? OverlayAppearanceOptions.fromMap(
              stringMap(source['appearanceOptions']),
            )
          : const OverlayAppearanceOptions.empty(),
      settings: OverlayWorkspaceSettings.fromMap(stringMap(source['settings'])),
      layout: objectList(source['layout'])
          .map((item) => OverlayWorkspaceLayoutItem.fromMap(stringMap(item)))
          .toList(growable: false),
    );
  }
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
  configurePresetSources,
  temporarySource,
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
    this.sources,
    this.replaceAutoSwitchPresetId,
    this.automaticSource,
    this.temporaryOwnerKey,
    this.runtimeDraft,
    this.appearanceOptions,
  });

  const OverlayWorkspaceMutation.saveActive({
    required OverlayWorkspaceSettings settings,
    required List<OverlayWorkspaceLayoutItem> layout,
    required String renderMode,
    required OverlayWorkspaceHotkey hotkey,
    OverlayPresetSources? sources,
    OverlayAppearanceOptions? appearanceOptions,
  }) : this._(
         kind: OverlayWorkspaceMutationKind.saveActive,
         settings: settings,
         layout: layout,
         renderMode: renderMode,
         hotkey: hotkey,
         sources: sources,
         appearanceOptions: appearanceOptions,
       );

  const OverlayWorkspaceMutation.activatePreset(String presetId)
    : this._(
        kind: OverlayWorkspaceMutationKind.activatePreset,
        presetId: presetId,
      );

  const OverlayWorkspaceMutation.temporarySource({
    required String ownerKey,
    required OverlayPresetSources sources,
    required OverlayWorkspaceRuntimeDraft draft,
  }) : this._(
         kind: OverlayWorkspaceMutationKind.temporarySource,
         temporaryOwnerKey: ownerKey,
         sources: sources,
         runtimeDraft: draft,
       );

  const OverlayWorkspaceMutation.activatePresetAutomatically(
    String presetId, {
    required String ownerKey,
    required int generation,
    required String source,
  }) : this._(
         kind: OverlayWorkspaceMutationKind.activatePreset,
         presetId: presetId,
         automaticSource: (
           ownerKey: ownerKey,
           generation: generation,
           source: source,
         ),
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
    OverlayPresetSources? sources,
    OverlayAppearanceOptions? appearanceOptions,
  }) : this._(
         kind: OverlayWorkspaceMutationKind.importPreset,
         name: name,
         settings: settings,
         layout: layout,
         sources: sources,
         appearanceOptions: appearanceOptions,
       );

  const OverlayWorkspaceMutation.configurePresetSources(
    String presetId,
    OverlayPresetSources sources, {
    String? replaceAutoSwitchPresetId,
    String? name,
  }) : this._(
         kind: OverlayWorkspaceMutationKind.configurePresetSources,
         presetId: presetId,
         sources: sources,
         replaceAutoSwitchPresetId: replaceAutoSwitchPresetId,
         name: name,
       );

  final OverlayWorkspaceMutationKind kind;
  final String? presetId;
  final String? name;
  final OverlayWorkspaceSettings? settings;
  final List<OverlayWorkspaceLayoutItem>? layout;
  final String? renderMode;
  final OverlayWorkspaceHotkey? hotkey;
  final OverlayPresetSources? sources;
  final String? replaceAutoSwitchPresetId;
  final ({String ownerKey, int generation, String source})? automaticSource;
  final String? temporaryOwnerKey;
  final OverlayWorkspaceRuntimeDraft? runtimeDraft;
  final OverlayAppearanceOptions? appearanceOptions;

  Map<String, Object?> toPayload(int expectedRevision) {
    return <String, Object?>{
      'schemaVersion': 1,
      'expectedRevision': expectedRevision,
      'action': kind.name,
      if (temporaryOwnerKey != null) 'ownerKey': temporaryOwnerKey,
      if (runtimeDraft != null) 'workspace': runtimeDraft!.toMap(),
      if (presetId != null) 'presetId': presetId,
      if (name != null) 'name': name,
      if (settings != null) 'settings': settings!.toMap(),
      if (layout != null)
        'layout': layout!.map((item) => item.toMap()).toList(growable: false),
      if (renderMode != null) 'renderMode': renderMode,
      if (hotkey != null) 'hotkey': hotkey!.toUpdateMap(),
      if (sources != null) 'sources': sources!.toMap(),
      if (appearanceOptions != null)
        'appearanceOptions': appearanceOptions!.toMap(),
      if (replaceAutoSwitchPresetId != null)
        'replaceAutoSwitchPresetId': replaceAutoSwitchPresetId,
      if (automaticSource case final trigger?)
        'automaticSource': {
          'ownerKey': trigger.ownerKey,
          'generation': trigger.generation,
          'source': trigger.source,
        },
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
    this.sourcePresetsEnabled = false,
    this.removedOrganizationBindings = false,
    this.appearanceOptionsEnabled = false,
    this.appearanceOptions = const OverlayAppearanceOptions.empty(),
    this.appearanceConfigurations = const [],
    this.livePreviewAppearanceIds = const {},
    this.appearanceProgressIds = const {},
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
    bool sourcePresetsEnabled = false,
    bool removedOrganizationBindings = false,
    bool appearanceOptionsEnabled = false,
    List<OverlayAppearanceConfiguration> appearanceConfigurations = const [],
    Set<String> livePreviewAppearanceIds = const {},
    Set<String> appearanceProgressIds = const {},
    OverlayAppearanceOptions appearanceOptions =
        const OverlayAppearanceOptions.empty(),
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
         sourcePresetsEnabled: sourcePresetsEnabled,
         removedOrganizationBindings: removedOrganizationBindings,
         appearanceOptionsEnabled: appearanceOptionsEnabled,
         appearanceConfigurations: appearanceConfigurations,
         livePreviewAppearanceIds: livePreviewAppearanceIds,
         appearanceProgressIds: appearanceProgressIds,
         appearanceOptions: appearanceOptions,
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
  final bool sourcePresetsEnabled;
  final bool removedOrganizationBindings;
  final bool appearanceOptionsEnabled;
  final List<OverlayAppearanceConfiguration> appearanceConfigurations;
  final Set<String> livePreviewAppearanceIds;
  final Set<String> appearanceProgressIds;
  final OverlayAppearanceOptions appearanceOptions;
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
