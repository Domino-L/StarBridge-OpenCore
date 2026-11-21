import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_members_size.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_layout.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';

import 'overlay_visor_layout_test.dart' show visor, shipped, surface;
import 'overlay_saved_snapshot.dart';

class _Port implements OverlayWorkspacePort {
  OverlayWorkspaceSnapshot snapshot = OverlayWorkspaceSnapshot.available(
    revision: 1,
    storageState: 'ready',
    activePresetId: 'p',
    renderMode: 'DirectComposition',
    appearances: const [],
    settings: visor(),
    layout: [shipped('Members')],
    hotkey: const OverlayWorkspaceHotkey(
      binding: 'Alt+O',
      enabled: true,
      runtimeState: 'registered',
    ),
    presets: [
      OverlayWorkspacePreset(
        id: 'p',
        name: 'Fixture',
        isActive: true,
        storageState: 'ready',
        settings: visor(),
        layout: [shipped('Members')],
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
    snapshot = savedOverlaySnapshot(snapshot, mutation);
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

void main() {
  test('a drag atomically undoes size and position; consecutive drags stay separate', () async {
    final module = OverlayWorkspaceModule(_Port());
    addTearDown(module.dispose);
    await module.initialize();
    final initial = module.projection.value;
    void drag(double dy) {
      final before = module.projection.value;
      final item = before.layout.single;
      final start = OverlayMembersResize(
        item,
        before.settings!,
        OverlayVisorLayout.boxOf(item, before.settings!, surface),
        surface,
        OverlayMembersHandle.bottom,
      );
      module.beginEventNotificationGesture();
      for (final delta in [dy / 2, dy]) {
        final next = start.at(Offset(0, delta));
        module.updateMembersSize(next.width, next.height, next.item);
      }
      module.endEventNotificationGesture();
    }

    drag(20);
    final first = module.projection.value;
    drag(10);
    module.undo();
    expect(module.projection.value.settings!.toMap(), first.settings!.toMap());
    expect(
      module.projection.value.layout.single.toMap(),
      first.layout.single.toMap(),
    );
    module.undo();
    expect(
      module.projection.value.settings!.toMap(),
      initial.settings!.toMap(),
    );
    expect(
      module.projection.value.layout.single.toMap(),
      initial.layout.single.toMap(),
    );
    expect(module.canUndo, isFalse);
  });

  test(
    'each size button is one undo step, independent of prior slider edits',
    () async {
      final module = OverlayWorkspaceModule(_Port());
      addTearDown(module.dispose);
      await module.initialize();
      module.updateSetting('visorMembersWidth', 370);
      module.stepMembersSize('visorMembersWidth', 380);
      module.stepMembersSize('visorMembersWidth', 390);
      module.undo();
      expect(module.projection.value.settings!['visorMembersWidth'], 380);
      module.undo();
      expect(module.projection.value.settings!['visorMembersWidth'], 370);
      module.undo();
      expect(module.projection.value.settings!['visorMembersWidth'], 364);
      expect(module.canUndo, isFalse);
    },
  );
}
