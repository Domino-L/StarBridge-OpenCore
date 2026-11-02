import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_hud_quick_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_hud_session.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_scene_controller.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';

import '../../features/overlay_settings/overlay_settings_ux_a_test.dart'
    show settings;

const _orgs = [OverlaySceneTarget('A', '远航者组织')];

void main() {
  Map<String, Object?> quick(List<Map<String, Object?>> views) =>
      views.last['quick']! as Map<String, Object?>;

  testWidgets(
    'in game, a fixed plan offers follow first and a pick is the remembered choice',
    (tester) async {
      final owner = OverlayWorkspaceModule(_Workspace());
      await owner.initialize();
      final scenes = _Scenes()
        ..state = const OverlaySceneState(
          available: true,
          status: 'ready',
          sourceOwnerKey: 'owner',
          presetBindingId: 'room',
          actualId: 'room',
          targets: _orgs,
        );
      final controller = OverlaySceneController(scenes, autoStart: false);
      await controller.refresh();
      var released = 0;
      controller.followShared = () async {
        released++;
        scenes.state = const OverlaySceneState(
          available: true,
          status: 'ready',
          sourceOwnerKey: 'owner',
          actualId: 'org:A',
          targets: _orgs,
        );
        return true;
      };
      final views = <Map<String, Object?>>[];
      final session = MenuHudSession(owner, controller, views.add)..show(true);
      await tester.pump();

      var source = quick(views)['source']! as Map;
      expect(source['origin'], 'preset');
      final options = (source['options']! as List).cast<Map>();
      expect(options.first['id'], 'followShared');
      expect(options.first['label'], '改为跟随，在这里选择来源');
      expect(
        options.where((o) => o['enabled'] == true).map((o) => o['id']),
        ['followShared'],
      );
      expect(MenuHudQuickView.parse(quick(views))!.source!.origin, 'preset');

      session.act('source', 'org:A');
      await tester.pump();
      expect(scenes.accountWrites, 0, reason: 'disabled while the plan is fixed');

      session.act('source', 'followShared');
      await tester.pumpAndSettle();
      expect(released, 1);
      source = quick(views)['source']! as Map;
      expect(source['origin'], 'auto');
      expect(source['label'], '自动 · 远航者组织');

      session.act('source', 'org:A');
      await tester.pumpAndSettle();
      expect(scenes.accountWrites, 1, reason: 'a pick writes the account choice');
      final note = quick(views)['note']! as Map;
      expect(note['kind'], 'source');
      expect(
        jsonSafe(quick(views)).contains('临时'),
        isFalse,
        reason: 'no session-only source in the panel',
      );
      session.dispose();
      controller.dispose();
      owner.dispose();
    },
  );
}

String jsonSafe(Object? value) => value.toString();

final class _Scenes implements OverlayScenePort {
  final events = StreamController<void>.broadcast();
  OverlaySceneState state = const OverlaySceneState();
  int accountWrites = 0;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<OverlaySceneState> read() async => state;
  @override
  Future<OverlaySceneState> select(int revision, String mode, String? code) async {
    accountWrites++;
    return state = OverlaySceneState(
      revision: revision + 1,
      available: true,
      status: 'ready',
      sourceOwnerKey: 'owner',
      mode: mode,
      code: code,
      actualId: mode == 'community' ? 'org:$code' : 'org:A',
      targets: _orgs,
    );
  }

  @override
  Future<OverlaySceneState> focusCommunity(String code) async => state;
  @override
  Future<OverlaySceneState> focusFleet() => focusCommunity('');
  @override
  void close() {}
}

final class _Workspace implements OverlayWorkspacePort {
  @override
  Future<OverlayWorkspaceSnapshot> read() async =>
      OverlayWorkspaceSnapshot.available(
        revision: 1,
        storageState: 'ready',
        activePresetId: 'default',
        renderMode: 'NativeComposition',
        appearances: const [],
        hotkey: const OverlayWorkspaceHotkey(
          binding: 'Ctrl+Shift+O',
          enabled: true,
          runtimeState: 'registered',
        ),
        settings: settings({'showMembers': true}),
        layout: const [],
        presets: [
          OverlayWorkspacePreset(
            id: 'default',
            name: '默认',
            isActive: true,
            storageState: 'ready',
            settings: settings(),
            layout: const [],
          ),
        ],
      );

  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) async => OverlayWorkspaceWriteResult.completed(await read());

  @override
  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) async => const OverlayRuntimeSnapshot(
    windowState: 'open',
    isVisible: true,
    appliedRevision: 1,
    hotkeyState: 'registered',
    followGameState: 'manual',
    requestedSkin: 'Default',
    effectiveSkin: 'Default',
    usedFallbackSkin: false,
  );

  @override
  Future<void> close() async {}
}
