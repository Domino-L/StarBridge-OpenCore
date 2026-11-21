import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_style.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_hud_quick_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_hud_placement.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_arrange.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_layout_editor.dart';
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
    session.act('preset', 'night');
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
    session.act('preset', 'night');
    await tester.pump();
    expect(
      port.mutations.single.kind,
      OverlayWorkspaceMutationKind.activatePreset,
    );
    expect(port.mutations.single.presetId, 'night');
    expect(owner.projection.value.dirty, false);
    final presets = (quick(views)['presets'] as List).cast<Map>();
    expect(presets.singleWhere((p) => p['active'] == true)['id'], 'night');
    expect((quick(views)['note'] as Map)['kind'], 'preset');
    expect(((quick(views)['note'] as Map)['args'] as Map)['name'], '夜航');
    session.dispose();
    owner.dispose();
  });

  testWidgets('wire survives the menu parser and rejects unknown modules', (
    tester,
  ) async {
    final (owner, _, views, session) = await start(tester);
    final view = MenuFeatureView.parse(views.last);
    expect(view.hudQuick, isNotNull);
    expect(view.hudQuick!.presets.map((p) => p.id), ['default', 'night']);
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
    await tester.tap(find.byKey(const ValueKey('menu-hud-quick-preset-night')));
    await tester.tap(find.byKey(const ValueKey('menu-toggle-hud')));
    await tester.pump();
    expect(actions, ['hud/module/Members', 'hud/preset/night', 'hud/toggle/']);

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
    final night = find.byKey(const ValueKey('menu-hud-quick-preset-night'));
    expect(tester.widget<BridgeMenuAction>(night).onPressed, isNull);
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
    // the panel is taller since the global section (11-11): scroll to it
    await tester.ensureVisible(find.byKey(resolve));
    await tester.pumpAndSettle();
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

  // 11-11 user: "Alt+M 按面罩排布" - placement shows and moves every block
  // where the visor draws it: members at the right middle, no resizing, the
  // rally only at the top or bottom, the events' height as the visor reads
  // it, and the DM badge placeable; module names always shown.
  testWidgets('placement on the visor places blocks as the visor does', (
    tester,
  ) async {
    size(tester, const Size(1920, 1080));
    final (owner, _, views, session) = await start(tester);
    expect(quick(views).containsKey('settings'), false);
    session.act('placeBegin', '');
    await tester.pump();
    expect(MenuHudQuickView.parse(quick(views))!.visor, isNotNull);
    final actions = <String>[];
    Widget preview() => app(
      MenuBridgePreview(
        visible: true,
        onDismiss: () {},
        onFeatureVisible: (_, _) {},
        onFeatureAction: (tool, key, value) {
          actions.add(key);
          session.act(key, value);
        },
        features: {'hud': MenuFeatureView.parse(views.last)},
      ),
    );
    Future<void> refresh() async {
      await tester.pumpWidget(preview());
      await tester.pumpAndSettle();
    }

    await refresh();
    final layer = tester.getRect(
      find.byKey(const ValueKey('menu-hud-placement')),
    );
    final surface = layer.size;
    Rect placed(String key) => OverlayVisorArrange.all(
      owner.projection.value.layout,
      owner.projection.value.settings!,
      surface,
    )[key]!.shift(layer.topLeft);
    Finder module(String key) =>
        find.byKey(ValueKey('menu-hud-place-module-$key'));

    // where the visor draws them: members at the right middle
    expect(
      tester.getRect(module('Members')),
      rectMoreOrLessEquals(placed('Members'), epsilon: 1),
    );
    expect(
      tester.getRect(module('Members')).center.dx,
      greaterThan(layer.center.dx),
    );
    expect(
      tester.getRect(module('Events')),
      rectMoreOrLessEquals(placed('Events'), epsilon: 1),
    );
    // names always shown; no resize grips and no grid; the DM badge is gone
    // (11-13 user: "整个都不要")
    expect(module('Badge'), findsNothing);
    for (final key in ['Members', 'Notice', 'Events']) {
      expect(
        find.descendant(of: module(key), matching: find.byType(Text)),
        findsWidgets,
        reason: '$key shows its name without hovering',
      );
      expect(find.byKey(ValueKey('menu-hud-place-grip-$key')), findsNothing);
    }
    expect(find.byKey(const ValueKey('menu-hud-place-grid')), findsNothing);
    // the main bar and its hint stay clear of the rally (and its name tag)
    final bar = tester.getRect(
      find
          .ancestor(
            of: find.byKey(const ValueKey('menu-hud-place-toolbar')),
            matching: find.byType(Column),
          )
          .first,
    );
    final rally = tester.getRect(module('Notice'));
    expect(
      bar.overlaps(
        Rect.fromLTRB(rally.left, rally.top - 26, rally.right, rally.bottom),
      ),
      isFalse,
    );

    // members move by the visor's rules and are drawn where the visor puts them
    await tester.drag(module('Members'), const Offset(-900, 0));
    await tester.pumpAndSettle();
    final members = owner.projection.value.layout.singleWhere(
      (i) => i.key == 'Members',
    );
    expect(members.horizontalAnchor, 'Left');
    await refresh();
    expect(
      tester.getRect(module('Members')),
      rectMoreOrLessEquals(placed('Members'), epsilon: 1),
    );
    expect(
      tester.getRect(module('Members')).center.dx,
      lessThan(layer.center.dx),
    );

    // the rally docks at the top or the bottom only, always centred
    await tester.drag(module('Notice'), const Offset(-300, 700));
    await tester.pumpAndSettle();
    expect(
      owner.projection.value.layout
          .singleWhere((i) => i.key == 'Notice')
          .verticalAnchor,
      'Bottom',
    );
    await refresh();
    expect(
      tester.getRect(module('Notice')).center.dx,
      moreOrLessEquals(layer.center.dx, epsilon: 1),
    );
    expect(
      tester.getRect(module('Notice')).center.dy,
      greaterThan(layer.center.dy),
    );

    // events: the saved height is the one the visor reads for that top
    final before = tester.getRect(module('Events'));
    await tester.drag(module('Events'), const Offset(0, 300));
    await tester.pumpAndSettle();
    await refresh();
    final after = tester.getRect(module('Events'));
    expect(after, rectMoreOrLessEquals(placed('Events'), epsilon: 1));
    expect(after.top, greaterThan(before.top + 200));
    expect(after.right, moreOrLessEquals(before.right, epsilon: 1));

    expect(actions, containsAll(['placeItem', 'placeEvents']));
    expect(actions, isNot(contains('placeBadge')));

    // the rally docked at the bottom goes back to the top on reset (review R1)
    await refresh();
    await tester.tap(module('Notice'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-hud-place-reset')));
    await tester.pumpAndSettle();
    expect(
      owner.projection.value.layout
          .singleWhere((i) => i.key == 'Notice')
          .verticalAnchor,
      'Top',
    );
    await refresh();
    expect(
      tester.getRect(module('Notice')).center.dy,
      lessThan(layer.center.dy),
    );
    session.dispose();
    owner.dispose();
  });

  // 11-18 user: "还有浮层编辑里的召集", "照真实召集的样子", "框跟着手上下走，松手
  // 吸过去": the rally box shows a sample rally and names its dock; selected,
  // the other dock shows as a slot; held, the box follows the pointer up and
  // down with both docks shown (the nearer brighter) and nothing is saved
  // until it docks on release
  testWidgets('placement shows a sample rally and docks it on release', (
    tester,
  ) async {
    size(tester, const Size(1920, 1080));
    final (owner, _, views, session) = await start(tester);
    session.act('placeBegin', '');
    await tester.pump();
    final actions = <String>[];
    Future<void> refresh() async {
      await tester.pumpWidget(
        app(
          MenuBridgePreview(
            visible: true,
            onDismiss: () {},
            onFeatureVisible: (_, _) {},
            onFeatureAction: (tool, key, value) {
              actions.add(key);
              session.act(key, value);
            },
            features: {'hud': MenuFeatureView.parse(views.last)},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await refresh();
    Finder module(String key) =>
        find.byKey(ValueKey('menu-hud-place-module-$key'));
    Finder slot(String id) => find.byKey(Key('overlay-visor-rally-slot-$id'));
    Finder inRally(Finder matching) =>
        find.descendant(of: module('Notice'), matching: matching);
    String dock() => owner.projection.value.layout
        .singleWhere((i) => i.key == 'Notice')
        .verticalAnchor;
    expect(
      inRally(find.byKey(const Key('overlay-visor-rally-sample'))),
      findsOneWidget,
    );
    expect(inRally(find.text('示例')), findsOneWidget);
    expect(inRally(find.text('召集与提醒 · 顶部')), findsOneWidget);
    expect(slot('bottom'), findsNothing, reason: 'nothing until selected');

    final docked = tester.getRect(module('Notice'));
    await tester.tap(module('Notice'));
    await tester.pumpAndSettle();
    expect(slot('bottom'), findsOneWidget);
    expect(slot('top'), findsNothing);

    // let go above the middle: it stays at the top and nothing is saved
    var gesture = await tester.startGesture(docked.center);
    await gesture.moveBy(const Offset(0, 150));
    await tester.pump();
    expect(tester.getRect(module('Notice')).top, closeTo(docked.top + 150, 1));
    expect(slot('top-near'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(dock(), 'Top');
    expect(actions, isNot(contains('placeItem')));

    // a cancelled drag past the middle changes nothing (review
    // CX-OVERLAY-M102-R1 P2-5)
    gesture = await tester.startGesture(docked.center);
    await gesture.moveBy(const Offset(0, 700));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(dock(), 'Top');
    expect(actions, isNot(contains('placeItem')));

    gesture = await tester.startGesture(docked.center);
    await gesture.moveBy(const Offset(-200, 600));
    await tester.pump();
    final held = tester.getRect(module('Notice'));
    expect(held.left, closeTo(docked.left, 1), reason: 'up and down only');
    expect(held.top, closeTo(docked.top + 600, 1));
    expect(slot('bottom-near'), findsOneWidget);
    expect(slot('top'), findsOneWidget);
    expect(dock(), 'Top', reason: 'nothing saved while held');
    expect(actions, isNot(contains('placeItem')));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(dock(), 'Bottom');
    expect(actions, contains('placeItem'));
    await refresh();
    expect(inRally(find.text('召集与提醒 · 底部')), findsOneWidget);
    expect(
      tester.getRect(module('Notice')).center.dx,
      closeTo(docked.center.dx, 1),
    );
    expect(
      tester.getRect(module('Notice')).bottom,
      greaterThan(docked.top + 600),
    );
    session.dispose();
    owner.dispose();
  });

  // review CX-OVERLAY-M102-R1 P2-5: in the client's layout editor each rally
  // drop is its own undo step, and a cancelled rally drag changes nothing
  testWidgets('the layout editor docks the rally once per drop', (
    tester,
  ) async {
    size(tester, const Size(1920, 1080));
    final owner = OverlayWorkspaceModule(_Port());
    await owner.initialize();
    Future<void> pump() async {
      await tester.pumpWidget(
        app(
          SizedBox(
            width: 1600,
            height: 900,
            child: OverlayWorkspaceLayoutWorkbench(
              layout: owner.projection.value.layout,
              settings: owner.projection.value.settings!,
              canvasOnly: true,
              showHiddenModules: false,
              showGrid: false,
              onSettingChanged: owner.updateSetting,
              onChanged: (item, coalesce) =>
                  owner.updateLayoutItem(item, coalesce: coalesce),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String dock() => owner.projection.value.layout
        .singleWhere((i) => i.key == 'Notice')
        .verticalAnchor;
    final notice = find.byKey(const Key('overlay-runtime-preview-Notice'));
    Future<void> drag(double dy, {bool cancel = false}) async {
      final gesture = await tester.startGesture(tester.getCenter(notice));
      await gesture.moveBy(Offset(0, dy));
      await tester.pump();
      if (cancel) {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      await pump();
    }

    await pump();
    expect(dock(), 'Top');
    await drag(700, cancel: true);
    expect(dock(), 'Top', reason: 'a cancelled drag docks nothing');
    await drag(700);
    expect(dock(), 'Bottom');
    await drag(-700);
    expect(dock(), 'Top');
    owner.undo();
    await pump();
    expect(dock(), 'Bottom', reason: 'one undo step per drop');
    owner.redo();
    await pump();
    expect(dock(), 'Top');
    owner.dispose();
  });

  // 11-13 user: the DM badge is gone ("整个都不要"); the layout editor has no
  // badge to drag and its saved place stays as it was
  testWidgets('the layout editor has no DM badge', (tester) async {
    size(tester, const Size(1920, 1080));
    final owner = OverlayWorkspaceModule(_Port());
    await owner.initialize();
    final before = owner.projection.value.settings!;
    await tester.pumpWidget(
      app(
        SizedBox(
          width: 1600,
          height: 900,
          child: OverlayWorkspaceLayoutWorkbench(
            layout: owner.projection.value.layout,
            settings: before,
            canvasOnly: true,
            showHiddenModules: false,
            showGrid: false,
            onSettingChanged: owner.updateSetting,
            onChanged: (item, coalesce) =>
                owner.updateLayoutItem(item, coalesce: coalesce),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overlay-visor-badge')), findsNothing);
    expect(
      owner.projection.value.settings!['visorBadgeX'],
      before['visorBadgeX'],
    );
    owner.dispose();
  });

  // 11-11 user: "要用同样的3d效果" - over the real visor the side blocks lean
  // as it draws them; a click lands where a block shows and a drag follows the
  // pointer one to one; the events box holds its sample rows
  testWidgets('placement on a tilted visor shows and hits the leaning blocks', (
    tester,
  ) async {
    size(tester, const Size(1920, 1080));
    final port = _Port();
    port.current = port.current
        .withValue('visorTilt', 15.0)
        .withValue('eventNotificationMaxVisibleCount', 3);
    final owner = OverlayWorkspaceModule(port);
    await owner.initialize();
    final views = <Map<String, Object?>>[];
    final session = MenuHudSession(owner, null, views.add)..show(true);
    await tester.pump();
    session.act('placeBegin', '');
    await tester.pump();
    Widget preview() => app(
      MenuBridgePreview(
        visible: true,
        onDismiss: () {},
        onFeatureVisible: (_, _) {},
        onFeatureAction: (tool, key, value) => session.act(key, value),
        features: {'hud': MenuFeatureView.parse(views.last)},
      ),
    );
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    final members = find.byKey(const ValueKey('menu-hud-place-module-Members'));
    final box = tester.renderObject<RenderBox>(members);
    final flat = tester.getRect(
      find.ancestor(of: members, matching: find.byType(Transform)).first,
    );
    // inside the leaning block, left of its flat box: selects it
    final grabbed = Offset(4, box.size.height / 2);
    final inside = box.localToGlobal(grabbed);
    expect(inside.dx, lessThan(flat.left));
    await tester.tapAt(inside);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('menu-hud-place-module-tools')),
      findsOneWidget,
    );
    // the events box holds the most events at once as samples
    for (var i = 0; i < 5; i++) {
      expect(
        find.byKey(Key('overlay-visor-events-sample-row-$i')),
        i < 3 ? findsOneWidget : findsNothing,
      );
    }
    // the shown block follows the pointer one to one on screen, whatever the
    // lean (review CX-VISOR-EVENTS3D-R1): the point grabbed stays under it
    // (globalToLocal is not exact through a perspective: keep the local point)
    final drag = await tester.startGesture(inside);
    await drag.moveBy(const Offset(-20, 0));
    await drag.moveBy(const Offset(-300, 0));
    await drag.up();
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    final moved = tester
        .renderObject<RenderBox>(members)
        .localToGlobal(grabbed);
    // the whole 320 from where it was pressed (the drag starts from the
    // press), give or take the visor's snap reach (12)
    expect(moved.dx - inside.dx, closeTo(-320, 12.5));
    expect((moved.dy - inside.dy).abs(), lessThan(12.5));
    // across the middle the lean turns; the point grabbed still ends under
    // the pointer (review CX-VISOR-EVENTS3D-R2)
    final from = tester.renderObject<RenderBox>(members).localToGlobal(grabbed);
    const to = Offset(500, 500);
    final across = await tester.startGesture(from);
    for (var i = 1; i <= 12; i++) {
      await across.moveTo(Offset.lerp(from, to, i / 12)!);
      await tester.pump();
    }
    await across.up();
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    final landed = tester
        .renderObject<RenderBox>(members)
        .localToGlobal(grabbed);
    expect((landed - to).distance, lessThan(14), reason: '$landed vs $to');
    session.dispose();
    owner.dispose();
  });

  testWidgets('another appearance keeps the free-size placement', (
    tester,
  ) async {
    size(tester, const Size(1920, 1080));
    const view = MenuHudQuickView(
      available: true,
      editable: true,
      dirty: false,
      hotkey: '',
      presetName: 'P',
      presets: [],
      modules: {'Members': true},
      placing: true,
      layout: [
        OverlayWorkspaceLayoutItem(
          key: 'Members',
          x: .2,
          y: .45,
          width: .16,
          height: .2,
          horizontalAnchor: 'Left',
          verticalAnchor: 'Top',
          isLocked: false,
          textOpacity: 1,
          backgroundOpacity: .5,
        ),
      ],
    );
    final actions = <(String, String)>[];
    await tester.pumpWidget(
      app(
        MenuHudPlacementLayer(
          view: view,
          onAction: (key, value) => actions.add((key, value)),
          onDismiss: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('menu-hud-place-grip-Members')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('menu-hud-place-grid')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('menu-hud-place-module-Badge')),
      findsNothing,
    );
    // a resize with a single move after it starts still resizes (review
    // CX-VISOR-EVENTS3D-R1: the grip reports where it starts)
    final grip = find.byKey(const ValueKey('menu-hud-place-grip-Members'));
    final resize = await tester.startGesture(tester.getCenter(grip));
    // the first move starts the resize (past the slop), the second is its
    // only update before the release
    await resize.moveBy(const Offset(40, 0));
    await resize.moveBy(const Offset(30, 0));
    await resize.up();
    await tester.pump(const Duration(milliseconds: 50));
    final widths = [
      for (final (key, value) in actions)
        if (key == 'placeItem')
          ((jsonDecode(value) as Map)['item'] as Map)['width'] as num,
    ];
    expect(widths, isNotEmpty);
    expect(widths.last, greaterThan(.16));
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
        presets: [_preset('default', '默认预设'), _preset('night', '夜航')],
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
