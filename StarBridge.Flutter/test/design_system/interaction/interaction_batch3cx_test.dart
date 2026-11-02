import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_dock.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_exec_hangar_widget.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_controls.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_workspace.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_flutter/platform/window/menu_desktop_widgets.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/menu_overlay/menu_exec_hangar_widget_test.dart'
    show SummaryPort;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import '../../app/menu_overlay/menu_overlay_workspace_test.dart' show Fixture;
import 'interaction_batch3ct_test.dart' show host, detach;
import 'interaction_batch3cw_lifecycle_test.dart' show hover;

Widget fixture(String id, {void Function(String)? record}) => switch (id) {
  'dock' => BridgePreviewDock(
    selected: BridgePreviewPanel.friends,
    openPanels: const {BridgePreviewPanel.friends},
    featuresEnabled: true,
    onToggle: (panel) => record?.call(panel.name),
  ),
  'friends' => SizedBox(
    width: 600,
    child: MenuFriendsControls(
      view: const MenuFriendsView('ready', interactive: true),
      onAction: (action, key, value) => record?.call('$action|$key|$value'),
    ),
  ),
  _ => MenuExecHangarWidget(
    port: SummaryPort(),
    preferences: const MenuDesktopWidgets(),
    editing: false,
    onOpen: () => record?.call('open'),
    onEdit: () {},
    onChanged: (_, _) {},
  ),
};
Finder target(String id) => find.byKey(switch (id) {
  'dock' => const ValueKey('menu-tool-friends'),
  'friends' => const ValueKey('friends-search'),
  _ => const Key('menu-hangar-widget'),
});

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final id in ['dock', 'friends', 'hangar']) {
      for (final stop in ['exit', 'hidden', 'native', 'dispose']) {
        testWidgets(
          '$suite $id hint follows live scope and releases on $stop',
          (t) async {
            t.view.devicePixelRatio = 1;
            t.view.physicalSize = const Size(1200, 900);
            var active = true, shown = true, reduced = false;
            late StateSetter update;
            final baseline = nativeViewportMenus.value;
            final mouse = await t.createGesture(
              kind: ui.PointerDeviceKind.mouse,
            );
            try {
              await t.pumpWidget(
                StatefulBuilder(
                  builder: (_, setState) {
                    update = setState;
                    return host(
                      TooltipVisibility(
                        visible: shown,
                        child: NativeViewportScope(
                          active: active,
                          child: fixture(id),
                        ),
                      ),
                      suite,
                      reduce: reduced,
                    );
                  },
                ),
              );
              await t.pumpAndSettle();
              await mouse.addPointer(location: Offset.zero);
              await hover(t, mouse, target(id));
              final hint = find.ancestor(
                of: target(id),
                matching: find.byType(SuiteTooltip),
              );
              expect(hint, findsOneWidget);
              expect(t.state<SuiteTooltipState>(hint).isShowing, isTrue);
              expect(nativeViewportMenus.value, baseline + 1);
              update(() => reduced = true);
              await t.pump();
              await t.pump();
              expect(InteractionScope.of(t.element(hint)).reduceMotion, isTrue);
              if (stop == 'exit') {
                await mouse.moveTo(Offset.zero);
                await t.pump();
              } else if (stop == 'hidden') {
                update(() => shown = false);
              } else if (stop == 'native') {
                update(() => active = false);
              } else {
                await detach(t);
              }
              await t.pump();
              await t.pump();
              expect(nativeViewportMenus.value, baseline);
              expect(t.takeException(), isNull);
            } finally {
              await mouse.removePointer();
              await detach(t);
              t.view.reset();
              expect(nativeViewportMenus.value, baseline);
            }
          },
        );
      }
    }
    testWidgets('$suite actual hidden panel releases its friends body hint', (
      t,
    ) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1200, 900);
      final f = Fixture();
      f.controller.open('friends');
      final baseline = nativeViewportMenus.value;
      final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await t.pumpWidget(
          host(
            MenuOverlayWorkspace(
              controller: f.controller,
              panels: [
                MenuPanelContent(
                  id: 'friends',
                  title: '好友',
                  icon: f.panels.first.icon,
                  builder: (_, _) => fixture('friends'),
                ),
              ],
              closeLabel: '关闭',
              moveLabel: '移动',
              resizeLabel: '缩放',
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        await mouse.addPointer(location: Offset.zero);
        await hover(t, mouse, target('friends'));
        expect(nativeViewportMenus.value, baseline + 1);
        f.controller.togglePanelsVisibility();
        await t.pump();
        await t.pump();
        expect(nativeViewportMenus.value, baseline);
        expect(t.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await detach(t);
        f.controller.dispose();
        t.view.reset();
      }
    });
  }
  testWidgets('actual dock hint follows approved scan suite', (t) async {
    final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await t.pumpWidget(host(fixture('dock'), InteractionSuite.scan));
      await t.pumpAndSettle();
      expect(target('dock'), findsOneWidget);
      await mouse.addPointer(location: Offset.zero);
      await hover(t, mouse, target('dock'));
      final hint = find.ancestor(
        of: target('dock'),
        matching: find.byType(SuiteTooltip),
      );
      expect(hint, findsOneWidget);
      expect(t.state<SuiteTooltipState>(hint).isShowing, isTrue);
      expect(InteractionScope.of(t.element(hint)).suite, InteractionSuite.scan);
    } finally {
      await mouse.removePointer();
      await detach(t);
    }
  });
}
