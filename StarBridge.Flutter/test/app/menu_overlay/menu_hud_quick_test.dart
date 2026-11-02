import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_style.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_hud_quick_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_hud_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_tool_page.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';

import '../../features/overlay_settings/overlay_settings_ux_a_test.dart'
    show settings;
import '../../features/friends/social_layout_test.dart' show app, size;

void main() {
  Future<
    (OverlayWorkspaceModule, _Port, List<Map<String, Object?>>, MenuHudSession)
  >
  start(WidgetTester tester) async {
    final port = _Port();
    final owner = OverlayWorkspaceModule(port);
    await owner.initialize();
    final views = <Map<String, Object?>>[];
    final session = MenuHudSession(owner, null, views.add)..show(true);
    await tester.pump();
    return (owner, port, views, session);
  }

  Map<String, Object?> quick(List<Map<String, Object?>> views) =>
      views.last['quick']! as Map<String, Object?>;

  testWidgets('barrage chat has no box in the quick panel or placement', (
    tester,
  ) async {
    Future<List<Object?>> layoutKeys(String mode) async {
      final port = _Port()
        ..current = settings({
          'showNotice': true,
          'showSquads': true,
          'showMembers': true,
          'showChat': true,
          'showEventNotifications': true,
          'chatDisplayMode': mode,
        });
      final owner = OverlayWorkspaceModule(port);
      await owner.initialize();
      final views = <Map<String, Object?>>[];
      final session = MenuHudSession(owner, null, views.add)..show(true);
      await tester.pump();
      final keys = [
        for (final item in quick(views)['layout']! as List)
          (item as Map)['key'],
      ];
      expect(
        (quick(views)['modules'] as Map)['Chat'],
        true,
        reason: 'the chat toggle stays available in both modes',
      );
      session.dispose();
      owner.dispose();
      return keys;
    }

    expect(await layoutKeys('MessageList'), contains('Chat'));
    expect(
      await layoutKeys('FullScreenBarrage'),
      isNot(contains('Chat')),
      reason: 'no scrim hole and no placeable box for flying barrage chat',
    );
  });

  testWidgets('module toggle saves straight to the preset and can be undone', (
    tester,
  ) async {
    final (owner, port, views, session) = await start(tester);
    expect((quick(views)['modules'] as Map)['Members'], true);
    expect(quick(views)['editable'], true);

    session.act('module', 'Members');
    await tester.pump();
    final save = port.mutations.single;
    expect(save.kind, OverlayWorkspaceMutationKind.saveActive);
    expect(save.settings!['showMembers'], false);
    expect(owner.projection.value.dirty, false);
    expect((quick(views)['modules'] as Map)['Members'], false);
    expect((quick(views)['note'] as Map)['kind'], 'hidden');
    expect((quick(views)['note'] as Map)['undo'], true);

    session.act('undo', '');
    await tester.pump();
    expect(port.mutations.last.settings!['showMembers'], true);
    expect((quick(views)['note'] as Map)['kind'], 'undone');
    expect((quick(views)['note'] as Map)['undo'], false);
    session.act('undo', '');
    await tester.pump();
    expect(port.mutations, hasLength(2));
    session.dispose();
    owner.dispose();
  });

  testWidgets('only a failed client save blocks quick writes and switches', (
    tester,
  ) async {
    final (owner, port, views, session) = await start(tester);
    owner.updateSetting('showChat', true);
    await tester.pump();
    expect(port.mutations.single.settings!['showChat'], true);
    expect(quick(views)['dirty'], false, reason: 'client edits save at once');
    expect(quick(views)['editable'], true);
    port.fail = OverlaySettingsFailure.writeFailed;
    owner.updateSetting('showChat', false);
    await tester.pump();
    expect(quick(views)['dirty'], true);
    expect(quick(views)['editable'], false);
    final count = port.mutations.length;
    session.act('module', 'Members');
    session.act('preset', 'combat');
    await tester.pump();
    expect(port.mutations, hasLength(count));
    expect(owner.projection.value.dirty, true);
    session.dispose();
    owner.dispose();
  });

  testWidgets('switching preset activates it without leaving a draft', (
    tester,
  ) async {
    final (owner, port, views, session) = await start(tester);
    session.act('preset', 'combat');
    await tester.pump();
    expect(
      port.mutations.single.kind,
      OverlayWorkspaceMutationKind.activatePreset,
    );
    expect(port.mutations.single.presetId, 'combat');
    expect(owner.projection.value.dirty, false);
    final presets = (quick(views)['presets'] as List).cast<Map>();
    expect(presets.singleWhere((p) => p['active'] == true)['id'], 'combat');
    expect((quick(views)['note'] as Map)['kind'], 'preset');
    expect(((quick(views)['note'] as Map)['args'] as Map)['name'], '战斗');
    session.dispose();
    owner.dispose();
  });

  testWidgets('wire survives the menu parser and rejects unknown modules', (
    tester,
  ) async {
    final (owner, _, views, session) = await start(tester);
    final view = MenuFeatureView.parse(views.last);
    expect(view.hudQuick, isNotNull);
    expect(view.hudQuick!.presets.map((p) => p.id), ['default', 'combat']);
    expect(view.hudQuick!.modules['Crosshair'], false);
    expect(
      () => MenuHudQuickView.parse({
        ...quick(views),
        'modules': {'Radar': true},
      }),
      throwsFormatException,
    );
    session.dispose();
    owner.dispose();
  });

  testWidgets('dock opens the quick panel; header still switches directly', (
    tester,
  ) async {
    size(tester, const Size(1600, 1100));
    final (owner, port, views, session) = await start(tester);
    final actions = <String>[];
    Widget preview(Map<String, Object?> wire) => app(
      MenuBridgePreview(
        visible: true,
        onDismiss: () {},
        onFeatureVisible: (_, _) {},
        onFeatureAction: (tool, key, value) => actions.add('$tool/$key/$value'),
        features: {'hud': MenuFeatureView.parse(wire)},
      ),
    );
    await tester.pumpWidget(preview(views.last));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-hud-quick')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('menu-tool-overlay')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-hud-quick')), findsOneWidget);
    expect(actions, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey('menu-hud-quick-module-Members')),
    );
    await tester.tap(
      find.byKey(const ValueKey('menu-hud-quick-preset-combat')),
    );
    await tester.tap(find.byKey(const ValueKey('menu-toggle-hud')));
    await tester.pump();
    expect(actions, ['hud/module/Members', 'hud/preset/combat', 'hud/toggle/']);

    port.fail = OverlaySettingsFailure.writeFailed;
    owner.updateSetting('showChat', true);
    await tester.pump();
    await tester.pumpWidget(preview(views.last));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-hud-quick-dirty')), findsOneWidget);
    final members = find.byKey(const ValueKey('menu-hud-quick-module-Members'));
    await tester.ensureVisible(members);
    await tester.pumpAndSettle();
    expect(tester.widget<StarBridgeSwitch>(members).onChanged, isNull);
    final combat = find.byKey(const ValueKey('menu-hud-quick-preset-combat'));
    expect(tester.widget<BridgeMenuAction>(combat).onPressed, isNull);
    session.dispose();
    owner.dispose();
  });

  testWidgets('full settings and the draft notice hand off to the client', (
    tester,
  ) async {
    size(tester, const Size(1600, 1100));
    final (owner, port, views, session) = await start(tester);
    const channel = MethodChannel('starbridge/test-hud-tool-page');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    var accept = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (!accept) throw PlatformException(code: 'menuToolPage.unavailable');
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    const full = ValueKey('menu-hud-quick-full-settings');
    const resolve = ValueKey('menu-hud-quick-resolve-in-client');
    const failed = ValueKey('menu-hud-quick-client-failed');
    // Same tree either way, so the open quick window survives the re-pump.
    Widget preview({bool linked = true}) => app(
      MenuToolPageScope(
        opener: linked ? MenuToolPageOpener(channel, () => 7) : null,
        child: MenuBridgePreview(
          visible: true,
          onDismiss: () {},
          onFeatureVisible: (_, _) {},
          onFeatureAction: (_, _, _) {},
          features: {'hud': MenuFeatureView.parse(views.last)},
        ),
      ),
    );

    // Without an opener (previews, older hosts) only the hint line remains.
    await tester.pumpWidget(preview(linked: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-tool-overlay')));
    await tester.pumpAndSettle();
    expect(find.byKey(full), findsNothing);
    expect(find.text('快调里的改动会同步到主程序的浮层设置。完整设置在主程序的「浮层」页。'), findsOneWidget);

    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    expect(find.text('快调里的改动会同步到主程序的浮层设置。'), findsOneWidget);
    await tester.ensureVisible(find.byKey(full));
    await tester.tap(find.byKey(full));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'openHudSettings');
    expect(calls.single.arguments, {'opening': 7});
    expect(find.byKey(failed), findsNothing);

    port.fail = OverlaySettingsFailure.writeFailed;
    owner.updateSetting('showChat', true);
    await tester.pump();
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-hud-quick-dirty')), findsOneWidget);
    expect(find.text('切到主程序处理 ›'), findsOneWidget);
    accept = false;
    await tester.tap(find.byKey(resolve));
    await tester.pumpAndSettle();
    expect(calls, hasLength(2));
    expect(calls.last.method, 'openHudSettings');
    expect(find.byKey(failed), findsOneWidget);
    // The link stays usable after a refusal so the user can retry.
    expect(
      tester.widget<BridgeMenuAction>(find.byKey(resolve)).onPressed,
      isNotNull,
    );
    session.dispose();
    owner.dispose();
  });

  testWidgets('placement edits stay a draft until Done saves them', (
    tester,
  ) async {
    final (owner, port, views, session) = await start(tester);
    session.act('placeBegin', '');
    await tester.pump();
    expect(quick(views)['placing'], true);
    final members = port.layout.singleWhere((i) => i.key == 'Members');
    for (final (y, first) in [(.55, true), (.56, false), (.57, false)]) {
      session.act(
        'placeItem',
        jsonEncode({'item': members.copyWith(y: y).toMap(), 'first': first}),
      );
    }
    await tester.pump();
    expect(owner.projection.value.dirty, true);
    expect(port.mutations, isEmpty);
    expect(quick(views)['canUndo'], true);
    // One drag is one undo step.
    session.act('placeUndo', '');
    await tester.pump();
    expect(
      owner.projection.value.layout.singleWhere((i) => i.key == 'Members').y,
      members.y,
    );
    session.act('placeRedo', '');
    session.act('module', 'Members');
    await tester.pump();
    expect(port.mutations, isEmpty, reason: 'quick writes wait for placement');
    session.act('placeDone', '');
    await tester.pump();
    expect(port.mutations.single.kind, OverlayWorkspaceMutationKind.saveActive);
    expect(
      port.layout.singleWhere((i) => i.key == 'Members').y,
      closeTo(.57, 1e-9),
    );
    expect(quick(views)['placeResult'], 'saved');
    session.show(false);
    expect(owner.projection.value.dirty, false);
    session.show(true);
    await tester.pump();
    expect(quick(views)['placing'], false);
    session.dispose();
    owner.dispose();
  });

  testWidgets('cancel or leaving the menu discards placement edits', (
    tester,
  ) async {
    final (owner, port, views, session) = await start(tester);
    final chat = port.layout.singleWhere((i) => i.key == 'Chat');
    for (final leave in [false, true]) {
      session.act('placeBegin', '');
      session.act(
        'placeItem',
        jsonEncode({'item': chat.copyWith(x: .3).toMap(), 'first': true}),
      );
      session.act('placeHide', 'Squads');
      await tester.pump();
      expect(owner.projection.value.dirty, true);
      if (!leave) {
        session.act('placeCancel', '');
        await tester.pump();
        expect(quick(views)['placeResult'], 'cancelled');
      }
      session.show(false);
      session.show(true);
      await tester.pump();
      expect(owner.projection.value.dirty, false);
      expect(quick(views)['placing'], false);
    }
    expect(port.mutations, isEmpty);
    session.act(
      'placeItem',
      jsonEncode({'item': chat.copyWith(x: .3).toMap(), 'first': true}),
    );
    await tester.pump();
    expect(owner.projection.value.dirty, false, reason: 'not placing');
    session.dispose();
    owner.dispose();
  });

  testWidgets('arrange mode replaces the menu and returns to the game', (
    tester,
  ) async {
    size(tester, const Size(1920, 1080));
    final (owner, _, views, session) = await start(tester);
    session.act('placeBegin', '');
    await tester.pump();
    final actions = <String>[];
    var dismissed = 0;
    Widget preview() => app(
      MenuBridgePreview(
        visible: true,
        onDismiss: () => dismissed++,
        onFeatureVisible: (_, _) {},
        onFeatureAction: (tool, key, value) {
          actions.add(key);
          session.act(key, value);
        },
        features: {'hud': MenuFeatureView.parse(views.last)},
      ),
    );
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-hud-placement')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-game-scrim')), findsNothing);
    final module = find.byKey(const ValueKey('menu-hud-place-module-Members'));
    expect(module, findsOneWidget);

    await tester.drag(module, const Offset(400, -40));
    await tester.pumpAndSettle();
    expect(actions.where((a) => a == 'placeItem'), isNotEmpty);
    expect(owner.projection.value.dirty, true);
    final moved = owner.projection.value.layout.singleWhere(
      (i) => i.key == 'Members',
    );
    expect(moved.x, greaterThan(.15));

    await tester.pumpWidget(preview());
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(actions.last, 'placeDone');
    await tester.pumpWidget(preview());
    await tester.pump();
    expect(find.byKey(const ValueKey('menu-hud-place-toast')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    expect(dismissed, 1);
    session.dispose();
    owner.dispose();
  });

  testWidgets('escape in arrange mode cancels instead of closing the menu', (
    tester,
  ) async {
    size(tester, const Size(1920, 1080));
    final (owner, _, views, session) = await start(tester);
    session.act('placeBegin', '');
    await tester.pump();
    final actions = <String>[];
    var dismissed = 0;
    await tester.pumpWidget(
      app(
        MenuBridgePreview(
          visible: true,
          onDismiss: () => dismissed++,
          onFeatureVisible: (_, _) {},
          onFeatureAction: (_, key, _) => actions.add(key),
          features: {'hud': MenuFeatureView.parse(views.last)},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(actions, ['placeCancel']);
    expect(dismissed, 0);
    session.dispose();
    owner.dispose();
  });
}

final class _Port implements OverlayWorkspacePort {
  int revision = 1;
  String active = 'default';
  OverlayWorkspaceSettings current = settings({
    'showNotice': true,
    'showSquads': true,
    'showMembers': true,
    'showChat': false,
    'showEventNotifications': true,
  });
  final mutations = <OverlayWorkspaceMutation>[];
  OverlaySettingsFailure? fail;
  List<OverlayWorkspaceLayoutItem> layout = [
    for (final (key, x, y, w, h) in [
      ('Notice', .34, 0.0, .32, .055),
      ('Squads', 0.0, .4211, .1327, .1042),
      ('Members', 0.0, .5253, .1327, .1557),
      ('Chat', 0.0, .681, .1327, .1069),
    ])
      OverlayWorkspaceLayoutItem(
        key: key,
        x: x,
        y: y,
        width: w,
        height: h,
        horizontalAnchor: 'Left',
        verticalAnchor: 'Top',
        isLocked: false,
        textOpacity: 1,
        backgroundOpacity: .5,
      ),
  ];

  OverlayWorkspacePreset _preset(String id, String name) =>
      OverlayWorkspacePreset(
        id: id,
        name: name,
        isActive: id == active,
        storageState: 'ready',
        settings: current,
        layout: const [],
      );

  @override
  Future<OverlayWorkspaceSnapshot> read() async =>
      OverlayWorkspaceSnapshot.available(
        revision: revision,
        storageState: 'ready',
        activePresetId: active,
        renderMode: 'NativeComposition',
        appearances: const [],
        presets: [_preset('default', '默认预设'), _preset('combat', '战斗')],
        settings: current,
        layout: layout,
        hotkey: const OverlayWorkspaceHotkey(
          binding: 'Ctrl+Shift+O',
          enabled: true,
          runtimeState: 'registered',
        ),
      );

  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) async {
    mutations.add(mutation);
    if (fail case final failure?) {
      return OverlayWorkspaceWriteResult.failed(failure);
    }
    if (expectedRevision != revision) {
      return const OverlayWorkspaceWriteResult.failed(
        OverlaySettingsFailure.writeConflict,
      );
    }
    revision++;
    if (mutation.kind == OverlayWorkspaceMutationKind.saveActive) {
      current = mutation.settings!;
      layout = mutation.layout!;
    }
    if (mutation.kind == OverlayWorkspaceMutationKind.activatePreset) {
      active = mutation.presetId!;
    }
    return OverlayWorkspaceWriteResult.completed(await read());
  }

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
    followGameState: 'disabled',
    requestedSkin: 'Default',
    effectiveSkin: 'Default',
    usedFallbackSkin: false,
  );

  @override
  Future<void> close() async {}
}
