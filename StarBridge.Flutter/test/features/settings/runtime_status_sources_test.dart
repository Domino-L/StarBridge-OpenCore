import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/bridge_runtime_overlay_status.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_projection.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_store.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_schema.dart';
import 'package:starbridge_flutter/features/settings/runtime_status_sources.dart';

void main() {
  test('startup uses confirmed values, never disconnected fallback or saving state', () {
    final owner = InMemoryAppPreferences();
    addTearDown(owner.dispose);
    final p = owner.projection.value;
    expect(
      runtimeStartupFacts(p)!.startMinimized,
      p.confirmed!.applicationBehavior.startMinimized,
    );
    for (final state in [
      AppPreferencesPhase.loading,
      AppPreferencesPhase.unavailable,
    ]) {
      expect(runtimeStartupFacts(_projection(p, phase: state)), isNull);
    }
    expect(runtimeStartupFacts(_projection(p, saving: true)), isNull);
    expect(runtimeStartupFacts(_projection(p, missing: true)), isNull);
  });
  test('status uses dedicated read instead of any runtime command', () async {
    final port = _Port();
    final result = await readRuntimeOverlayFacts(
      port,
      readStatus: port.readStatus,
    );
    expect(result!.windowState, 'closed');
    expect(result.hotkeyState, 'conflict');
    expect(result.hotkeyBinding, 'Alt+F10');
    expect(result.presetName, 'Saved preset');
    expect(port.actions, isEmpty);
    expect(port.language, isNull);
    expect(port.writes, 0);
    expect(port.closed, isFalse);
  });
  test('saved hotkey enabled does not imply registered or visible', () async {
    final port = _Port();
    final result = await readRuntimeOverlayFacts(
      port,
      readStatus: port.readStatus,
    );
    expect(result!.windowState, 'closed');
    expect(result.hotkeyState, 'conflict');
  });
  test('revision mismatch suppresses old binding and preset', () async {
    final port = _Port()..revision = 3;
    final result = await readRuntimeOverlayFacts(
      port,
      readStatus: port.readStatus,
    );
    expect(result!.windowState, 'closed');
    expect(result.hotkeyBinding, 'Alt+F10');
    expect(result.presetName, isNull);
  });
  test('workspace failure keeps runtime facts', () async {
    final port = _Port()..failWorkspace = true;
    final result = await readRuntimeOverlayFacts(
      port,
      readStatus: port.readStatus,
    );
    expect(result!.windowState, 'closed');
    expect(result.hotkeyBinding, 'Alt+F10');
  });
  test(
    'runtime failure keeps saved preset without inventing current state',
    () async {
      final port = _Port()..failRuntime = true;
      final result = await readRuntimeOverlayFacts(
        port,
        readStatus: port.readStatus,
      );
      expect(result!.presetName, 'Saved preset');
      expect(result.windowState, isNull);
      expect(result.hotkeyState, isNull);
    },
  );
  test('both unavailable remains unknown', () async {
    final port = _Port()
      ..failWorkspace = true
      ..failRuntime = true;
    expect(
      await readRuntimeOverlayFacts(port, readStatus: port.readStatus),
      isNull,
    );
  });
}

AppPreferencesProjection _projection(
  AppPreferencesProjection p, {
  AppPreferencesPhase phase = AppPreferencesPhase.ready,
  bool saving = false,
  bool missing = false,
}) => AppPreferencesProjection(
  effective: AppPreferences.defaults,
  confirmed: missing ? null : p.confirmed,
  revision: 1,
  phase: phase,
  operation: saving
      ? AppPreferencesOperation.saving
      : AppPreferencesOperation.idle,
  source: AppPreferencesSource.stored,
  failure: null,
);

class _Port implements OverlayWorkspacePort {
  final actions = <OverlayRuntimeAction>[];
  var failWorkspace = false, failRuntime = false, closed = false;
  var writes = 0, revision = 2;
  String? language;
  @override
  Future<OverlayWorkspaceSnapshot> read() async {
    if (failWorkspace) throw StateError('private failure');
    final settings = _settings();
    return OverlayWorkspaceSnapshot.available(
      revision: 2,
      storageState: 'ready',
      activePresetId: 'saved',
      renderMode: 'DirectComposition',
      appearances: const [],
      hotkey: const OverlayWorkspaceHotkey(
        binding: 'Alt+F10',
        enabled: true,
        runtimeState: 'unavailable',
      ),
      settings: settings,
      layout: const [],
      presets: [
        OverlayWorkspacePreset(
          id: 'saved',
          name: 'Saved preset',
          isActive: true,
          storageState: 'ready',
          settings: settings,
          layout: const [],
        ),
      ],
    );
  }

  Future<RuntimeOverlayStatus> readStatus() async => RuntimeOverlayStatus(
    windowState: failRuntime ? 'unavailable' : 'closed',
    hotkeyState: failRuntime ? 'unavailable' : 'conflict',
    hotkeyBinding: 'Alt+F10',
    appliedRevision: revision,
  );
  @override
  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) async {
    expect(draft, isNull);
    actions.add(action);
    this.language = language;
    if (failRuntime) return const OverlayRuntimeSnapshot.unavailable();
    return OverlayRuntimeSnapshot(
      windowState: 'closed',
      isVisible: false,
      appliedRevision: revision,
      hotkeyState: 'conflict',
      followGameState: 'waitingForGame',
      requestedSkin: 'Default',
      effectiveSkin: 'Default',
      usedFallbackSkin: false,
    );
  }

  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) async {
    writes++;
    throw StateError('Status must not write');
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

// Same schema-driven synthetic fixture pattern as the existing overlay suite.
OverlayWorkspaceSettings _settings() {
  final values = <String, Object?>{
    'hideMissionWhenIdle': false,
    'showMission': false,
  };
  for (final f in overlayWorkspaceFieldSpecs) {
    values[f.field] = switch (f.kind) {
      OverlayWorkspaceFieldKind.toggle => false,
      OverlayWorkspaceFieldKind.choice ||
      OverlayWorkspaceFieldKind.readOnlyChoice => f.options.first,
      OverlayWorkspaceFieldKind.numberChoice => f.numberOptions.first,
      OverlayWorkspaceFieldKind.number =>
        f.field == 'eventNotificationMaxVisibleCount' ||
                f.field == 'chatMaxVisibleCount'
            ? f.minimum.round()
            : f.minimum,
      OverlayWorkspaceFieldKind.color => '#FFFFFF',
      OverlayWorkspaceFieldKind.eventTypes => 0,
      OverlayWorkspaceFieldKind.eventDurations => <String, Object?>{},
    };
  }
  values['eventNotificationDurations'] = {
    for (final key in [
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
    ])
      key: 0,
  };
  return OverlayWorkspaceSettings.fromMap(values);
}
