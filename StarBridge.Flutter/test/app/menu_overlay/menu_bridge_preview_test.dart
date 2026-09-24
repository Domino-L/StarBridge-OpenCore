import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_panels.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_style.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, capture, loadFonts;

void expectFlatMenuSurfaces(WidgetTester tester) {
  final surfaces = tester
      .widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(MenuBridgePreview),
          matching: find.byType(DecoratedBox),
        ),
      )
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .toList();
  expect(surfaces.any((surface) => surface.color == BridgeInk.panel), isTrue);
  for (final surface in surfaces) {
    expect(surface.gradient, isNull);
  }
  expect(BridgeInk.panel.a, inExclusiveRange(.5, 1));
}

void main() {
  setUp(
    () =>
        TestWidgetsFlutterBinding
            .instance
            .platformDispatcher
            .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
          disableAnimations: true,
        ),
  );
  tearDown(
    () => TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearAccessibilityFeaturesTestValue(),
  );
  setUpAll(loadFonts);
  testWidgets(
    'V1 windows coexist, move, resize, refocus and retain geometry without rereading',
    (tester) async {
      size(tester, const Size(1600, 1100));
      final friendsVisible = <bool>[], commsVisible = <bool>[];
      Map<String, Object?>? layout;
      await tester.pumpWidget(
        app(
          MenuBridgePreview(
            visible: true,
            onDismiss: () {},
            friends: MenuFriendsView.parse(
              '{"state":"ready","incoming":0,"rows":[{"name":"Fixture","presence":"unknown"}]}',
            ),
            comms: const MenuCommsView('idle'),
            onCommsAction: (_, _) {},
            onFriendsVisible: friendsVisible.add,
            onCommsVisible: commsVisible.add,
            onLayoutChanged: (value) => layout = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-tool-friends')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('menu-friends-filter')),
        'Fix',
      );
      final friend = find.byKey(const ValueKey('menu-panel-friends'));
      final original = tester.getRect(friend);
      await tester.tap(find.byKey(const ValueKey('menu-tool-chat')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-panel-comms')), findsOneWidget);
      expect(friend, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('menu-tool-friends')));
      await tester.pumpAndSettle();
      expect(find.text('Fix'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('menu-move-friends')),
        const Offset(35, 38),
      );
      await tester.pumpAndSettle();
      final moved = tester.getRect(friend);
      expect(moved.left, greaterThan(original.left));
      expect(moved.top, greaterThan(original.top));
      await tester.drag(
        find.byKey(const ValueKey('menu-resize-friends')),
        const Offset(-10, -110),
      );
      await tester.pumpAndSettle();
      final resized = tester.getRect(friend);
      expect(resized.height, lessThan(moved.height));
      expect(friendsVisible, [true]);
      expect(commsVisible, [true]);
      expect(layout!['open'], isEmpty);
      expect(layout.toString(), isNot(contains('Fixture')));
      await tester.tap(find.byKey(const ValueKey('menu-close-friends')));
      await tester.pumpAndSettle();
      expect(friendsVisible, [true, false]);
      expect(find.byKey(const ValueKey('menu-panel-comms')), findsOneWidget);
      expect(commsVisible, [true]);
      await tester.tap(find.byKey(const ValueKey('menu-tool-friends')));
      await tester.pumpAndSettle();
      expect(tester.getRect(friend), resized);
      expect(friendsVisible, [true, false, true]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final viewport in [
    const Size(2560, 1440),
    const Size(1600, 900),
    const Size(1280, 720),
    const Size(960, 720),
  ]) {
    testWidgets('complete Flutter menu at $viewport', (tester) async {
      size(tester, viewport);
      final key = GlobalKey();
      var dismissals = 0;
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: key,
            child: MenuBridgePreview(
              visible: true,
              onDismiss: () => dismissals++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in [
        '信息浮层',
        '组织',
        '好友',
        '通讯',
        '房间',
        '全屏截屏',
        '参考图',
        '浏览器',
      ]) {
        expect(find.text(label), findsWidgets);
      }
      expect(find.byKey(const ValueKey('menu-local-clock')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('menu-selected-indicator')),
        findsNothing,
      );
      expect(find.byType(BridgeFriendsPreview), findsNothing);
      expect(find.byType(BridgeCommsPreview), findsNothing);
      expect(find.text('当前飞船'), findsOneWidget);
      expect(find.text('所在位置'), findsOneWidget);
      expect(find.text('服务器'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BridgeContextPreview),
          matching: find.byType(MenuGlyphView),
        ),
        findsNothing,
      );
      expect(find.text('当前协作'), findsOneWidget);
      expect(find.text('成员'), findsOneWidget);
      expect(
        tester
            .widget<ColoredBox>(find.byKey(const ValueKey('menu-game-scrim')))
            .color,
        const Color(0x85000000),
      );
      expect(tester.takeException(), isNull);
      expectFlatMenuSurfaces(tester);
      await capture(tester, key, 'menu-bridge-${viewport.width.toInt()}');
      await tester.tap(find.byKey(const ValueKey('menu-tool-friends')));
      await tester.pumpAndSettle();
      expect(find.byType(BridgeFriendsPreview), findsOneWidget);
      expect(find.byType(BridgeCommsPreview), findsNothing);
      expect(tester.takeException(), isNull);
      expectFlatMenuSurfaces(tester);
      if (viewport.width == 1600) {
        await capture(tester, key, 'menu-bridge-friends');
      }
      await tester.tap(find.byKey(const ValueKey('menu-tool-chat')));
      await tester.pumpAndSettle();
      expect(find.byType(BridgeFriendsPreview), findsOneWidget);
      expect(find.text('21:45'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expectFlatMenuSurfaces(tester);
      if (viewport.width == 1600) {
        await capture(tester, key, 'menu-bridge-comms');
      }
      if (tester
          .getRect(find.byKey(const ValueKey('menu-panel-comms')))
          .contains(
            tester.getCenter(find.byKey(const ValueKey('menu-tool-chat'))),
          )) {
        await tester.drag(
          find.byKey(const ValueKey('menu-move-comms')),
          const Offset(0, -100),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('menu-tool-chat')));
      await tester.pumpAndSettle();
      expect(find.byType(BridgeCommsPreview), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('menu-close-comms')));
      await tester.pumpAndSettle();
      expect(find.byType(BridgeCommsPreview), findsNothing);
      expect(find.byType(BridgeFriendsPreview), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(dismissals, 1);
      await tester.tap(find.byKey(const ValueKey('menu-return')));
      expect(dismissals, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('200 percent text remains scrollable with no overflow', (
    tester,
  ) async {
    size(tester, const Size(960, 720));
    await tester.pumpWidget(
      app(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MenuBridgePreview(visible: true, onDismiss: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('menu-tool-friends')));
    await tester.pumpAndSettle();
    // The desktop chrome floats above windows; scroll an exposed part rather
    // than assuming that the geometric center is not covered by the dock.
    await tester.dragFrom(
      tester.getTopLeft(find.byKey(const ValueKey('menu-scroll-friends'))) +
          const Offset(80, 90),
      const Offset(0, -1400),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('hidden preview has no contents or clock timer', (tester) async {
    await tester.pumpWidget(
      app(MenuBridgePreview(visible: false, onDismiss: () {})),
    );
    await tester.pump(const Duration(minutes: 5));
    expect(find.byKey(const ValueKey('menu-local-clock')), findsNothing);
    expect(find.byKey(const ValueKey('menu-game-scrim')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('keyboard toggle, close, and reopen start without panels', (
    tester,
  ) async {
    size(tester, const Size(1280, 720));
    Widget preview(bool visible) => app(
      MenuBridgePreview(
        key: const ValueKey('preview'),
        visible: visible,
        onDismiss: () {},
      ),
    );
    await tester.pumpWidget(preview(true));
    await tester.pumpAndSettle();
    final action = find.byKey(const ValueKey('menu-tool-friends'));
    final detector = find.descendant(
      of: action,
      matching: find.byType(FocusableActionDetector),
    );
    final focus = find
        .descendant(of: detector, matching: find.byType(Focus))
        .first;
    Focus.of(
      tester.element(
        find
            .descendant(of: focus, matching: find.byType(GestureDetector))
            .first,
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(BridgeFriendsPreview), findsOneWidget);
    expect(tester.widget<BridgeMenuAction>(action).selected, isTrue);
    await tester.tap(find.byKey(const ValueKey('menu-close-friends')));
    await tester.pumpAndSettle();
    expect(find.byType(BridgeFriendsPreview), findsNothing);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.pumpWidget(preview(false));
    await tester.pump(const Duration(minutes: 2));
    await tester.pumpWidget(preview(true));
    await tester.pumpAndSettle();
    expect(find.byType(BridgeFriendsPreview), findsNothing);
    expect(find.byType(BridgeCommsPreview), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
