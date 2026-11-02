import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_dock.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_style.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_test.dart' show host, detach;
import 'interaction_batch3cy_test.dart' show dock, friend;
import 'interaction_batch3cx_actions_test.dart' show bridgeFocus;
import 'interaction_batch3cy_visual_test.dart' show menuSurface;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final initiallyEnabled in [false, true]) {
      testWidgets(
        '$suite live primary enabled=$initiallyEnabled reverses without losing context focus',
        (t) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = const Size(1200, 900);
          late StateSetter update;
          var enabled = initiallyEnabled, primary = 0, recovered = 0;
          final target = find.byKey(const ValueKey('menu-tool-ship'));
          FocusNode anchor() => enabled
              ? bridgeFocus(t, target)
              : t
                    .widget<Focus>(
                      find
                          .descendant(
                            of: find.byKey(
                              const ValueKey('menu-context-focus-execHangar'),
                            ),
                            matching: find.byType(Focus),
                          )
                          .first,
                    )
                    .focusNode!;
          try {
            await t.pumpWidget(
              StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  return host(
                    BridgePreviewDock(
                      selected: BridgePreviewPanel.execHangar,
                      openPanels: const {BridgePreviewPanel.execHangar},
                      execHangarEnabled: enabled,
                      onToggle: (_) => primary++,
                      onRecover: (_) => recovered++,
                    ),
                    suite,
                  );
                },
              ),
            );
            await t.pumpAndSettle();
            await t.ensureVisible(target);
            await t.pumpAndSettle();
            final original = anchor();
            original.requestFocus();
            await t.pump();
            for (final next in [!initiallyEnabled, initiallyEnabled]) {
              update(() => enabled = next);
              await t.pump();
              await t.pump();
              expect(anchor(), same(original));
              expect(original.hasFocus, isTrue);
              expect(
                t.widget<BridgeMenuAction>(target).onPressed == null,
                !enabled,
              );
              final before = primary;
              await t.sendKeyEvent(LogicalKeyboardKey.enter);
              await t.pump();
              expect(primary, before + (enabled ? 1 : 0));
              await t.sendKeyEvent(LogicalKeyboardKey.contextMenu);
              await t.pump();
              await t.pump();
              expect(menuSurface(), findsOneWidget);
              await t.sendKeyEvent(LogicalKeyboardKey.enter);
              await t.pumpAndSettle();
              expect(recovered, greaterThan(0));
              expect(menuSurface(), findsNothing);
            }
            expect(recovered, 2);
            expect(t.takeException(), isNull);
          } finally {
            await detach(t);
            t.view.reset();
          }
        },
      );
    }
    for (final reopen in [false, true]) {
      testWidgets(
        '$suite real mouse exit/reopen=$reopen retains only its live menu',
        (t) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = const Size(1200, 900);
          final mouse = await t.createGesture(
            kind: ui.PointerDeviceKind.mouse,
            pointer: 100,
          );
          final baseline = nativeViewportMenus.value;
          var primary = 0, recovered = 0;
          try {
            await t.pumpWidget(
              host(
                dock(toggle: (_) => primary++, recover: (_) => recovered++),
                suite,
              ),
            );
            await t.pumpAndSettle();
            await mouse.addPointer(location: Offset.zero);
            await mouse.moveTo(t.getCenter(friend));
            await t.pump();
            await t.pump(const Duration(milliseconds: 600));
            await t.pumpAndSettle();
            expect(nativeViewportMenus.value, greaterThan(baseline));
            await mouse.downWithCustomEvent(
              t.getCenter(friend),
              PointerDownEvent(
                pointer: 100,
                device: 1,
                kind: ui.PointerDeviceKind.mouse,
                position: t.getCenter(friend),
                buttons: kSecondaryMouseButton,
              ),
            );
            await mouse.up();
            await t.pumpAndSettle();
            expect(menuSurface(), findsOneWidget);
            expect(primary, 0);
            await mouse.moveTo(const Offset(10, 10));
            await t.pumpAndSettle();
            expect(
              t
                  .stateList<SuiteTooltipState>(find.byType(SuiteTooltip))
                  .where((s) => s.isShowing),
              isEmpty,
            );
            expect(nativeViewportMenus.value, baseline + 1);
            await mouse.down(const Offset(10, 10));
            await mouse.up();
            await t.pump();
            await t.pump(const Duration(milliseconds: 20));
            expect(menuSurface(), findsOneWidget);
            expect(
              t.widget<SuiteSurfaceTransition>(menuSurface()).animation.value,
              inExclusiveRange(0, 1),
            );
            expect(nativeViewportMenus.value, baseline + 1);
            expect(recovered, 0);
            if (reopen) {
              await mouse.moveTo(t.getCenter(friend));
              await mouse.downWithCustomEvent(
                t.getCenter(friend),
                PointerDownEvent(
                  pointer: 100,
                  device: 1,
                  kind: ui.PointerDeviceKind.mouse,
                  position: t.getCenter(friend),
                  buttons: kSecondaryMouseButton,
                ),
              );
              await mouse.up();
              await t.pumpAndSettle();
              expect(menuSurface(), findsOneWidget);
              expect(
                t.widget<SuiteSurfaceTransition>(menuSurface()).animation.value,
                1,
              );
              await mouse.moveTo(t.getCenter(find.text('移回当前屏幕')));
              await mouse.down(t.getCenter(find.text('移回当前屏幕')));
              await mouse.up();
              await t.pump();
              expect(recovered, 1);
            }
            await t.pumpAndSettle();
            expect(menuSurface(), findsNothing);
            expect(primary, 0);
            FocusManager.instance.primaryFocus?.unfocus();
            await mouse.moveTo(const Offset(10, 10));
            await t.pumpAndSettle();
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
}
