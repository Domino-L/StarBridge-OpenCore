import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_frame.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_workspace.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/menu_overlay/menu_overlay_workspace_test.dart' show Fixture;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_test.dart' show host, detach;
import 'interaction_batch3cw_test.dart' show workbench, focusTarget;

Finder hintOf(Finder child) =>
    find.ancestor(of: child, matching: find.byType(SuiteTooltip));

Future<void> hover(WidgetTester t, TestGesture mouse, Finder target) async {
  await mouse.moveTo(t.getCenter(target));
  await t.pump();
  await t.pump(const Duration(milliseconds: 700));
  await t.pump(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite unavailable tool retains reason and cannot activate or focus',
      (t) async {
        final semantics = t.ensureSemantics();
        try {
          await t.pumpWidget(
            host(
              MenuOverlayFrame(
                contextLabel: '工作区',
                returnLabel: '返回游戏',
                settingsLabel: '设置',
                onReturn: () {},
                tools: const [
                  MenuOverlayTool(
                    id: 'locked',
                    label: '尚未接入',
                    icon: StarBridgeIconSemantic.tools,
                    unavailableReason: '不可用原因',
                  ),
                ],
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          final target = find.byKey(const ValueKey('menu-tool-locked'));
          final node = t.getSemantics(target).getSemanticsData();
          expect(node.hasAction(ui.SemanticsAction.tap), isFalse);
          expect(node.flagsCollection.isEnabled, ui.Tristate.isFalse);
          expect(node.flagsCollection.isFocused, ui.Tristate.none);
          await t.tapAt(t.getCenter(target));
          await t.pump();
          expect(
            find.byWidgetPredicate(
              (w) => w is SuiteTooltip && w.message == '不可用原因',
            ),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
        } finally {
          semantics.dispose();
          await detach(t);
        }
      },
    );
    testWidgets(
      '$suite live suite and reduced motion retain focus draft and lease',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(1200, 850);
        final f = Fixture();
        f.controller.open('friends');
        late StateSetter update;
        var style = suite;
        var reduce = false;
        try {
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return host(workbench(f), style, reduce: reduce);
              },
            ),
          );
          await t.pumpAndSettle();
          final field = find.byKey(const ValueKey('input-friends'));
          final edit = t.widget<TextField>(field).controller!;
          const draft = TextEditingValue(
            text: '舰桥草稿',
            selection: TextSelection(baseOffset: 1, extentOffset: 3),
            composing: TextRange(start: 1, end: 3),
          );
          edit.value = draft;
          final lease = f.controller.openPanels.single;
          final target = find.byKey(const ValueKey('menu-close-friends'));
          final focus = focusTarget(t, target);
          focus.requestFocus();
          await t.pump();
          update(() {
            style = InteractionSuite.values[(suite.index + 1) % 4];
            reduce = true;
          });
          await t.pump();
          await t.pump();
          expect(focusTarget(t, target), same(focus));
          expect(focus.hasFocus, isTrue);
          expect(edit.value, draft);
          expect(f.controller.openPanels.single, same(lease));
          expect(f.probes['friends']!.mounted, 1);
          f.controller.setVisible(false);
          await t.pump();
          expect(focus.hasFocus, isFalse);
          f.controller.setVisible(true);
          await t.pumpAndSettle();
          expect(edit.value, draft);
          expect(f.controller.openPanels.single, same(lease));
          expect(t.takeException(), isNull);
        } finally {
          await detach(t);
          f.controller.dispose();
          t.view.reset();
        }
      },
    );
    testWidgets(
      '$suite direct drag resize and arrow keys retain layout owner',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(1200, 850);
        final f = Fixture();
        f.controller.open('friends');
        try {
          await t.pumpWidget(host(workbench(f), suite));
          await t.pumpAndSettle();
          final panel = find.byKey(const ValueKey('menu-panel-friends'));
          final move = find.byKey(const ValueKey('menu-move-friends'));
          final resize = find.byKey(const ValueKey('menu-resize-friends'));
          final builds = f.probes['friends']!.builds;
          final before = t.getRect(panel);
          await t.drag(move, const Offset(90, 60));
          await t.pumpAndSettle();
          final moved = t.getRect(panel);
          expect(moved.left, greaterThan(before.left + 40));
          expect(moved.top, greaterThan(before.top + 20));
          await t.drag(resize, const Offset(80, 60));
          await t.pumpAndSettle();
          final resized = t.getRect(panel);
          expect(resized.width, greaterThan(moved.width + 30));
          expect(resized.height, greaterThan(moved.height + 20));
          focusTarget(t, move).requestFocus();
          await t.pump();
          await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await t.pump();
          expect(t.getRect(panel).left, resized.left + 10);
          focusTarget(t, resize).requestFocus();
          await t.pump();
          await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await t.pump();
          expect(t.getRect(panel).height, resized.height + 10);
          expect(f.probes['friends']!.builds, builds);
          expect(t.takeException(), isNull);
        } finally {
          await detach(t);
          f.controller.dispose();
          t.view.reset();
        }
      },
    );
    testWidgets('$suite old held close cannot close a reopened lease', (
      t,
    ) async {
      final f = Fixture();
      f.controller.open('friends');
      try {
        await t.pumpWidget(host(workbench(f), suite));
        await t.pumpAndSettle();
        final old = f.controller.openPanels.single;
        final pointer = await t.startGesture(
          t.getCenter(find.byKey(const ValueKey('menu-close-friends'))),
        );
        f.controller.close('friends');
        await t.pump();
        f.controller.open('friends');
        await t.pump();
        final next = f.controller.openPanels.single;
        expect(next, isNot(same(old)));
        await pointer.up();
        await t.pumpAndSettle();
        expect(f.controller.openPanels.single, same(next));
        expect(f.probes['friends']!.mounted, 2);
        expect(f.probes['friends']!.disposed, 1);
        expect(t.takeException(), isNull);
      } finally {
        await detach(t);
        f.controller.dispose();
      }
    });
    for (final hiddenBy in ['workbench', 'panels', 'chrome']) {
      testWidgets('$suite shown hint releases when hidden by $hiddenBy', (
        t,
      ) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(1200, 850);
        final f = Fixture();
        f.controller.open('friends');
        final chrome = ValueNotifier(false);
        final baseline = nativeViewportMenus.value;
        final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          final child = hiddenBy == 'workbench'
              ? workbench(f)
              : MenuOverlayWorkspace(
                  controller: f.controller,
                  panels: [
                    MenuPanelContent(
                      id: f.panels.first.id,
                      title: f.panels.first.title,
                      icon: f.panels.first.icon,
                      builder: f.panels.first.builder,
                      chromeHidden: chrome,
                    ),
                  ],
                  closeLabel: '关闭',
                  moveLabel: '移动',
                  resizeLabel: '缩放',
                );
          await t.pumpWidget(host(child, suite));
          await t.pumpAndSettle();
          await mouse.addPointer(location: Offset.zero);
          final target = find.byKey(const ValueKey('menu-move-friends'));
          await hover(t, mouse, target);
          final hint = t.state<SuiteTooltipState>(hintOf(target));
          expect(hint.isShowing, isTrue);
          expect(nativeViewportMenus.value, baseline + 1);
          if (hiddenBy == 'workbench') {
            f.controller.setVisible(false);
          } else if (hiddenBy == 'panels') {
            f.controller.togglePanelsVisibility();
          } else {
            chrome.value = true;
          }
          await t.pump();
          await t.pump();
          expect(nativeViewportMenus.value, baseline);
          expect(hint.mounted, isTrue);
          expect(hint.isShowing, isFalse);
          expect(f.probes['friends']!.disposed, 0);
          expect(t.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await detach(t);
          f.controller.dispose();
          chrome.dispose();
          t.view.reset();
          expect(nativeViewportMenus.value, baseline);
        }
      });
    }
  }
}
