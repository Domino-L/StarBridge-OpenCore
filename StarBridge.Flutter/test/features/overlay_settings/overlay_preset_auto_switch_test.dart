import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_auto_switch.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_scene_controller.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';

import 'overlay_settings_ux_a_test.dart' show settings;

void main() {
  Future<_Fixture> fixture() async {
    final result = _Fixture();
    addTearDown(result.dispose);
    await result.workspace.initialize();
    await result.source('local');
    return result;
  }

  test(
    'room entry switches once and confirmed leave restores previous preset',
    () async {
      final f = await fixture();
      await f.source('room:one');
      expect(f.active, 'room');
      expect(f.workspace.projection.value.dirty, isFalse);
      await f.source('room:one');
      expect(f.port.activations, ['room']);
      await f.source('local');
      expect(f.active, 'base');
      expect(f.port.activations, ['room', 'base']);
    },
  );

  test('entry waits for a pending save, then switches', () async {
    final f = await fixture();
    f.port.hold = Completer<void>();
    f.edit();
    await f.source('room:one');
    expect(f.active, 'base');
    expect(f.port.activations, isEmpty);
    expect(f.workspace.projection.value.dirty, isTrue, reason: 'write pending');
    f.port.hold!.complete();
    await settle();
    expect(f.workspace.projection.value.dirty, isFalse);
    expect(f.active, 'room');
    expect(f.port.activations, ['room']);
    expect(
      f.port.savedDraft?.forModule(OverlaySourceModule.chat).mode,
      OverlaySourceMode.room,
    );
  });

  test(
    'entry followed by leave during a pending save never replays the old room',
    () async {
      final f = await fixture();
      f.port.hold = Completer<void>();
      f.edit();
      await f.source('room:one');
      await f.source('local');
      f.port.hold!.complete();
      await settle();
      expect(f.active, 'base');
      expect(f.port.activations, isEmpty);
    },
  );

  test(
    'a pending save settles against the latest source, not the first',
    () async {
      final f = await fixture();
      f.port.hold = Completer<void>();
      f.edit();
      await f.source('room:one');
      await f.source('org:A');
      f.port.hold!.complete();
      await settle();
      expect(f.active, 'org');
      expect(f.port.activations, ['org']);
      await f.source('local');
      expect(f.active, 'base');
    },
  );

  test('a failed save keeps the edit and blocks automatic activation', () async {
    final f = await fixture();
    f.port.fail = true;
    f.edit();
    await f.source('room:one');
    expect(f.workspace.projection.value.dirty, isTrue);
    expect(
      f.workspace.projection.value.failure,
      OverlaySettingsFailure.writeFailed,
    );
    expect(f.active, 'base');
    expect(f.port.activations, isEmpty);
    f.port.fail = false;
    expect(await f.workspace.save(), isTrue);
    await settle();
    expect(f.active, 'room');
  });

  test(
    'temporary unknown never restores or releases a deferred switch',
    () async {
      final f = await fixture();
      await f.source('room:one');
      f.edit();
      await f.source(null);
      f.workspace.discardChanges();
      await settle();
      expect(f.active, 'room');
      expect(f.port.activations, ['room']);
      await f.source('local');
      expect(f.active, 'base');
    },
  );

  test(
    'manual choice pauses automation until a different confirmed source',
    () async {
      final f = await fixture();
      await f.source('room:one');
      expect(await f.workspace.activatePreset('manual'), isTrue);
      await f.source('room:one');
      await f.source(null);
      await f.source('room:one');
      expect(f.active, 'manual');
      await f.source('room:two');
      expect(f.active, 'room');
      await f.source('local');
      expect(f.active, 'manual');
    },
  );

  test('same-preset manual selection also pauses restoration', () async {
    final f = await fixture();
    await f.source('room:one');
    await f.workspace.activatePreset('room');
    await settle();
    await f.source('local');
    expect(f.active, 'room');
  });

  test('manual selection before first confirmed source is not immediately overridden', () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.workspace.initialize();
    await f.source(null);
    await f.workspace.activatePreset('manual');
    await settle();
    await f.source('room:one');
    expect(f.active, 'manual');
    await f.source('room:two');
    expect(f.active, 'room');
  });

  test(
    'account invalidation cancels a deferred source without dropping a failed edit',
    () async {
      final f = await fixture();
      f.port.fail = true;
      f.edit();
      await f.source('org:A');
      f.scenes.value = const OverlaySceneState();
      await settle();
      expect(f.workspace.projection.value.dirty, isTrue);
      f.port.fail = false;
      f.workspace.discardChanges();
      await f.source('org:A', owner: 'other', generation: 2);
      expect(f.port.activations, isEmpty);
      expect(f.active, 'base');
    },
  );

  test('failed activation is not replayed by repeated source polls', () async {
    final f = await fixture();
    f.port.fail = true;
    await f.source('room:one');
    await f.source('room:one');
    await f.source('room:one');
    expect(f.port.activations, ['room']);
    expect(f.active, 'base');
    f.port.fail = false;
    await f.source('room:two');
    expect(f.active, 'room');
  });

  test(
    'source changes during activation settle against latest source',
    () async {
      final f = await fixture();
      f.port.hold = Completer<void>();
      await f.source('room:one');
      expect(f.workspace.projection.value.busy, isTrue);
      await f.source('local');
      f.port.hold!.complete();
      await settle();
      expect(f.active, 'base');
      expect(f.port.activations, ['room', 'base']);
    },
  );

  test('disabled v2 leaves existing runtime behavior untouched', () async {
    final f = await fixture();
    f.port.enabled = false;
    await f.workspace.refresh();
    await f.source('room:one');
    expect(f.port.activations, isEmpty);
  });
}

Future<void> settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Fixture {
  final port = _Port();
  final scenes = ValueNotifier(const OverlaySceneState());
  late final workspace = OverlayWorkspaceModule(port);
  late final coordinator = OverlayPresetAutoSwitch(workspace, scenes);
  String? get active => workspace.projection.value.snapshot?.activePresetId;
  void edit() => workspace.updateModuleSource(
    OverlaySourceModule.chat,
    const OverlaySourceBinding.room(),
  );
  Future<void> source(
    String? id, {
    String owner = 'owner',
    int generation = 1,
  }) async {
    coordinator;
    scenes.value = OverlaySceneState(
      available: true,
      sourceOwnerKey: owner,
      contextGeneration: generation,
      automaticPresetSourceId: id,
    );
    await settle();
  }

  void dispose() {
    coordinator.dispose();
    workspace.dispose();
    scenes.dispose();
  }
}

final class _Port implements OverlayWorkspacePort {
  String active = 'base';
  int revision = 1;
  bool fail = false, enabled = true;
  Completer<void>? hold;
  final activations = <String>[];
  OverlayPresetSources? savedDraft;
  final policies = <String, OverlayPresetSources>{
    'base': OverlayPresetSources(),
    'manual': OverlayPresetSources(),
    'room': OverlayPresetSources(
      binding: const OverlaySourceBinding.room(),
      autoSwitch: true,
    ),
    'org': OverlayPresetSources(
      binding: OverlaySourceBinding.community('A', 'owner'),
      autoSwitch: true,
    ),
  };
  OverlayWorkspaceSnapshot get snapshot => OverlayWorkspaceSnapshot.available(
    revision: revision,
    storageState: 'ready',
    activePresetId: active,
    renderMode: 'NativeComposition',
    appearances: [],
    sourcePresetsEnabled: enabled,
    settings: settings(),
    layout: [],
    hotkey: const OverlayWorkspaceHotkey(
      binding: 'Alt+O',
      enabled: true,
      runtimeState: 'registered',
    ),
    presets: [
      for (final entry in policies.entries)
        OverlayWorkspacePreset(
          id: entry.key,
          name: entry.key,
          isActive: active == entry.key,
          storageState: 'ready',
          settings: settings(),
          layout: [],
          sources: entry.value,
        ),
    ],
  );
  @override
  Future<OverlayWorkspaceSnapshot> read() async => snapshot;
  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) async {
    if (mutation.kind == OverlayWorkspaceMutationKind.activatePreset) {
      activations.add(mutation.presetId!);
    }
    if (hold != null) await hold!.future;
    if (fail || expectedRevision != revision) {
      return const OverlayWorkspaceWriteResult.failed(
        OverlaySettingsFailure.writeFailed,
      );
    }
    if (mutation.kind == OverlayWorkspaceMutationKind.activatePreset) {
      active = mutation.presetId!;
    }
    if (mutation.kind == OverlayWorkspaceMutationKind.saveActive) {
      savedDraft = mutation.sources;
      policies[active] = mutation.sources!;
    }
    revision++;
    return OverlayWorkspaceWriteResult.completed(snapshot);
  }

  @override
  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) async => const OverlayRuntimeSnapshot.unavailable();
  @override
  Future<void> close() async {}
}
