import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_workspace_controller.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts;

void main() {
  setUpAll(loadFonts);
  test('free geometry survives a smaller display, explicit recovery brings it back', () {
    final desktop = MenuWorkspaceController(
      scope: Object(),
      panels: [
        MenuPanelSpec(
          id: 'friends',
          initialBounds: const Rect.fromLTWH(20, 30, 340, 500),
        ),
      ],
    );
    addTearDown(desktop.dispose);
    desktop.open('friends');
    desktop.moveTo(
      desktop.openPanels.single,
      const Offset(-2400, 1500),
      const Size(2560, 1440),
    );
    expect(
      desktop.boundsFor('friends', const Size(800, 600)).topLeft,
      const Offset(-2400, 1500),
    );
    desktop.recover('friends', const Size(800, 600));
    final rect = desktop.boundsFor('friends', const Size(800, 600));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(600));
  });

  final settings = {
    ...MenuWindowPreferences.defaults.settings,
    'restoreDesktop': true,
  };
  final layout = <String, Object?>{
    'version': 1,
    'panels': [
      {
        'id': 'friends',
        'bounds': [-150.0, 110.0, 340.0, 500.0],
      },
      {
        'id': 'screenshot',
        'bounds': [390.0, 110.0, 800.0, 500.0],
      },
    ],
    'open': ['friends', 'screenshot'],
  };
  test('desktop opt-in validates kinds and order without accepting business targets', () {
    final document = MenuWindowPreferences(2, layout, settings).toMap();
    expect(
      MenuWindowPreferences.parse(jsonDecode(jsonEncode(document))),
      isNotNull,
    );
    for (final open in [
      ['p1'],
      ['friends', 'friends'],
      [123],
    ]) {
      expect(
        MenuWindowPreferences.parse({
          ...document,
          'layout': {...layout, 'open': open},
        }),
        isNull,
      );
    }
    expect(
      MenuWindowPreferences.parse({
        ...document,
        'settings': {...settings, 'restoreDesktop': false},
      }),
      isNull,
    );
  });

  testWidgets(
    'fresh app restores windows and order without replaying capture; closed stays closed',
    (tester) async {
      size(tester, const Size(1600, 1000));
      final calls = <String>[];
      final visibility = <bool>[];
      Map<String, Object?>? saved;
      Widget view(
        Object key,
        Object source, {
        bool visible = true,
        bool remember = true,
      }) => app(
        MenuBridgePreview(
          key: ValueKey(key),
          visible: visible,
          onDismiss: () {},
          initialLayout: source,
          initialSettings: {...settings, 'restoreDesktop': remember},
          localCall: (action, _) async {
            calls.add(action);
            return null;
          },
          onLayoutChanged: (layout) => saved = layout,
          onFriendsVisible: visibility.add,
        ),
      );
      await tester.pumpWidget(view(1, layout));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-panel-friends')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('menu-panel-screenshot')),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('menu-panel-friends'))).left,
        -150,
      );
      expect(saved!['open'], ['friends', 'screenshot']);
      expect(visibility, contains(true));
      expect(calls, isNot(contains('capture')));
      // Closing a window updates the persisted desktop before the menu hides.
      await tester.tap(find.byKey(const ValueKey('menu-close-screenshot')));
      await tester.pumpAndSettle();
      expect(saved!['open'], ['friends']);
      final disk = jsonDecode(jsonEncode(saved));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(view(2, disk));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-panel-friends')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-panel-screenshot')), findsNothing);
      await tester.pumpWidget(view(2, disk, visible: false));
      await tester.pump();
      expect(saved!['open'], ['friends']);
      await tester.pumpWidget(view(2, disk));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-panel-friends')), findsOneWidget);
      await tester.pumpWidget(view(3, disk, remember: false));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-panel-friends')), findsNothing);
      expect(saved!['open'], isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
