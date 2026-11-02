import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_scene_controller.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_source_binding_field.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_source_card.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_source_selection_coordinator.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_group_navigation.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_rules.dart';

import 'overlay_settings_ux_a_test.dart' show settings;
import '../friends/social_layout_test.dart' show app, size;
import 'overlay_saved_snapshot.dart';

const _owner = 'owner-key';
const _orgs = [OverlaySceneTarget('A', '远航者组织'), OverlaySceneTarget('B', '黑曜工业')];

OverlaySceneState _scene({String? bound, String actual = 'org:A', String mode = 'auto', String? code}) =>
    OverlaySceneState(
      available: true,
      status: 'ready',
      sourceOwnerKey: _owner,
      mode: mode,
      code: code,
      presetBindingId: bound,
      actualId: bound ?? actual,
      targets: _orgs,
    );

void main() {
  test('follow releases only the plan\'s fixed source and automatic use', () async {
    final port = _Workspace(binding: const OverlaySourceBinding.room(), autoSwitch: true);
    final module = OverlayWorkspaceModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    final scenes = _Scenes()..state = _scene(bound: 'room');
    final controller = OverlaySceneController(scenes, autoStart: false);
    addTearDown(controller.dispose);
    final coordinator = OverlaySourceSelectionCoordinator(module, controller);
    addTearDown(coordinator.dispose);
    await controller.refresh();
    scenes.afterRelease = _scene();

    expect(await controller.select('org:B'), isFalse, reason: 'a fixed source is released first');
    expect(await controller.select('followShared'), isTrue);
    final write = port.writes.single;
    expect(write.kind, OverlayWorkspaceMutationKind.configurePresetSources);
    expect(write.name, 'Fixture');
    expect(write.sources!.binding, const OverlaySourceBinding.follow());
    expect(write.sources!.autoSwitch, isFalse);
    expect(write.sources!.forModule(OverlaySourceModule.chat), const OverlaySourceBinding.room(),
        reason: 'module sources are kept');
    expect(scenes.accountWrites, 0);
    expect(controller.projection.value.presetBindingId, isNull);
  });

  group('source card', () {
    Future<(OverlayWorkspaceModule, _Scenes, OverlaySceneController)> pump(
      WidgetTester tester, {
      OverlaySceneState? scene,
      OverlaySourceBinding binding = const OverlaySourceBinding.follow(),
    }) async {
      size(tester, const Size(1200, 700));
      final port = _Workspace(binding: binding, chat: false);
      final module = OverlayWorkspaceModule(port);
      addTearDown(module.dispose);
      await module.refresh();
      final scenes = _Scenes()..state = scene ?? _scene();
      final controller = OverlaySceneController(scenes, autoStart: false);
      addTearDown(controller.dispose);
      await controller.refresh();
      await tester.pumpWidget(app(SingleChildScrollView(
        child: OverlaySourceCard(scenes: controller, workspace: module),
      )));
      await tester.pumpAndSettle();
      return (module, scenes, controller);
    }

    String text(WidgetTester tester, String key) =>
        tester.widget<Text>(find.byKey(Key(key))).data!;

    testWidgets('says what is shown and why, and edits the remembered choice', (tester) async {
      final (_, scenes, controller) = await pump(tester);
      expect(find.text('自动（现在是 远航者组织）'), findsOneWidget);
      expect(text(tester, 'overlay-source-card-actual'), '远航者组织');
      expect(text(tester, 'overlay-source-card-reason'), contains('你不在房间里'));
      expect(find.textContaining('所有模块都显示这里选的来源'), findsOneWidget);
      expect(find.byKey(const Key('overlay-source-card-follow')), findsNothing);

      await tester.tap(find.text('黑曜工业'));
      await tester.pumpAndSettle();
      expect(scenes.accountWrites, 1);
      expect(controller.projection.value.preferredId, 'org:B');
      expect(text(tester, 'overlay-source-card-reason'), '固定显示这个来源，直到你改选。');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a plan-fixed source is flagged and released only on request', (tester) async {
      final (_, scenes, _) = await pump(
        tester,
        scene: _scene(bound: 'room'),
        binding: const OverlaySourceBinding.room(),
      );
      expect(text(tester, 'overlay-source-card-actual'), '方案固定：当前房间');
      expect(text(tester, 'overlay-source-card-reason'), contains('改为跟随后'));
      await tester.tap(find.text('黑曜工业'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(scenes.accountWrites, 0, reason: 'choices are disabled while fixed');
      expect(find.byKey(const Key('overlay-source-card-follow')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('modules with their own source are listed and can follow again', (tester) async {
      final (module, _, _) = await pump(tester);
      module.updateModuleSource(OverlaySourceModule.chat, const OverlaySourceBinding.room());
      module.updateModuleSource(
        OverlaySourceModule.members,
        OverlaySourceBinding.community('B', _owner),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 个模块改了来源：'), findsOneWidget);
      expect(find.text('成员 → 黑曜工业'), findsOneWidget);
      expect(find.text('聊天 → 当前房间'), findsOneWidget);
      await tester.tap(find.byKey(const Key('overlay-source-card-clear-overrides')));
      await tester.pumpAndSettle();
      expect(module.projection.value.sources!.modules.values
          .every((b) => b.mode == OverlaySourceMode.none), isTrue);
      expect(find.textContaining('所有模块都显示这里选的来源'), findsOneWidget);
      module.undo();
      await tester.pumpAndSettle();
      expect(find.text('2 个模块改了来源：'), findsOneWidget, reason: 'one undo step');
    });
  });

  test('group marks show closed modules and modules with their own source', () async {
    final module = OverlayWorkspaceModule(_Workspace(binding: const OverlaySourceBinding.follow(), chat: true));
    addTearDown(module.dispose);
    await module.refresh();
    module.updateSetting('showMembers', false);
    final p = module.projection.value;
    expect(overlayWorkspaceGroupMark(p, 'members'), (off: true, ownSource: false));
    expect(overlayWorkspaceGroupMark(p, 'chat'), (off: false, ownSource: true));
    expect(overlayWorkspaceGroupMark(p, 'crosshair'), (off: false, ownSource: false));
  });

  testWidgets('module source row follows the shared choice by name', (tester) async {
    size(tester, const Size(600, 300));
    final scenes = _Scenes()..state = _scene();
    final controller = OverlaySceneController(scenes, autoStart: false);
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(app(Column(children: [
      OverlaySourceBindingField(
        value: const OverlaySourceBinding.follow(), scenes: controller, onChanged: (_) {}),
      OverlaySourceBindingField(
        value: const OverlaySourceBinding.room(), scenes: controller, onChanged: (_) {}),
      OverlaySourceBindingField(
        value: const OverlaySourceBinding.follow(), scenes: controller, presetBinding: true, onChanged: (_) {}),
    ])));
    await tester.pumpAndSettle();
    expect(find.text('跟随上方（远航者组织）'), findsOneWidget);
    expect(find.text('默认跟随上方的“显示谁的信息”。'), findsOneWidget);
    expect(find.text('只影响这个模块；其他模块仍跟随上方。'), findsOneWidget);
    expect(find.text('不固定（跟随“显示谁的信息”）'), findsOneWidget);
    expect(find.text('固定来源（可选）'), findsOneWidget);
    expect(find.textContaining('预设'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('mode-specific settings stay visible and explain when they apply', () {
    final list = settings({'showChat': true, 'chatDisplayMode': 'MessageList', 'skin': 'Default'});
    for (final field in ['chatBarrageFontSize', 'chatBarrageRegion', 'chatDurationSeconds', 'nightShadowBloom']) {
      expect(overlayWorkspaceFieldVisible(field, list), isTrue, reason: field);
    }
    expect(overlayWorkspaceFieldDisabledReason('chatBarrageRegion', list), 'overlay.workspace.disabled.barrage');
    expect(overlayWorkspaceFieldDisabledReason('nightShadowBloom', list), 'overlay.workspace.disabled.bloom');
    final barrage = settings({'showChat': true, 'chatDisplayMode': 'FullScreenBarrage'});
    expect(overlayWorkspaceFieldDisabledReason('chatBarrageRegion', barrage), isNull);
    expect(overlayWorkspaceFieldVisible('requestedSkin', list), isFalse, reason: 'internal fields stay hidden');
  });
}

final class _Scenes implements OverlayScenePort {
  final events = StreamController<void>.broadcast();
  OverlaySceneState state = const OverlaySceneState();
  OverlaySceneState? afterRelease;
  int accountWrites = 0;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<OverlaySceneState> read() async {
    if (afterRelease case final next?) {
      state = next;
      afterRelease = null;
    }
    return state;
  }

  @override
  Future<OverlaySceneState> select(int revision, String mode, String? code) async {
    accountWrites++;
    return state = _scene(mode: mode, code: code, actual: mode == 'community' ? 'org:$code' : 'org:A');
  }

  @override
  Future<OverlaySceneState> focusCommunity(String code) async => state;
  @override
  Future<OverlaySceneState> focusFleet() => focusCommunity('');
  @override
  void close() {}
}

final class _Workspace implements OverlayWorkspacePort {
  _Workspace({required OverlaySourceBinding binding, bool autoSwitch = false, bool chat = true})
    : snapshot = _snapshot(
        1,
        OverlayPresetSources(
          binding: binding,
          autoSwitch: autoSwitch,
          modules: {if (chat) OverlaySourceModule.chat: const OverlaySourceBinding.room()},
        ),
      );
  OverlayWorkspaceSnapshot snapshot;
  final writes = <OverlayWorkspaceMutation>[];

  static OverlayWorkspaceSnapshot _snapshot(int revision, OverlayPresetSources sources) =>
      OverlayWorkspaceSnapshot.available(
        revision: revision,
        storageState: 'ready',
        activePresetId: 'fixture',
        renderMode: 'NativeComposition',
        appearances: const [],
        hotkey: const OverlayWorkspaceHotkey(binding: 'Alt+O', enabled: true, runtimeState: 'registered'),
        settings: settings({'showChat': true, 'showMembers': true}),
        layout: const [],
        sourcePresetsEnabled: true,
        presets: [
          OverlayWorkspacePreset(
            id: 'fixture',
            name: 'Fixture',
            isActive: true,
            storageState: 'ready',
            settings: settings(),
            layout: const [],
            sources: sources,
          ),
        ],
      );

  @override
  Future<OverlayWorkspaceSnapshot> read() async => snapshot;
  @override
  Future<OverlayWorkspaceWriteResult> apply(OverlayWorkspaceMutation mutation, {required int expectedRevision}) async {
    writes.add(mutation);
    if (mutation.kind == OverlayWorkspaceMutationKind.configurePresetSources) {
      snapshot = _snapshot(snapshot.revision! + 1, mutation.sources!);
    }
    if (mutation.kind == OverlayWorkspaceMutationKind.saveActive) {
      snapshot = savedOverlaySnapshot(snapshot, mutation);
    }
    return OverlayWorkspaceWriteResult.completed(snapshot);
  }

  @override
  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) async => const OverlayRuntimeSnapshot(
    windowState: 'closed',
    isVisible: false,
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
