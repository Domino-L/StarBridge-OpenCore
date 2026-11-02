// Hover hints must not outlive the pointer. Reported on build 10: after a
// click on an organisation avatar (its menu hands focus back to the anchor
// when it closes) the hint stayed up even once the pointer moved away,
// because desktop mouse focus was taken for keyboard focus.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';

import 'interaction_batch3i_test.dart' show scopedApp;

const _anchor = Key('hint-anchor');
final _hint = find.text('hint');

Widget _target(FocusNode node, {VoidCallback? onTap, int revision = 0}) =>
    StarBridgeTooltip(
      key: ValueKey(('tooltip', revision)),
      message: 'hint',
      child: StarBridgeActionRow(
        controlKey: _anchor,
        focusNode: node,
        onActivate: (_, _) => onTap?.call(),
        child: const SizedBox(width: 40, height: 40),
      ),
    );

Future<TestGesture> _hover(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: const Offset(1, 1));
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(find.byKey(_anchor)));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  expect(_hint, findsOneWidget);
  return mouse;
}

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('${suite.name}: click, focus handed back, pointer leaves', (
      tester,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(scopedApp(Center(child: _target(node)), suite));
      await tester.pumpAndSettle();
      final mouse = await _hover(tester);
      await mouse.down(tester.getCenter(find.byKey(_anchor)));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(_hint, findsNothing);
      // A closing menu or dialog restores focus to its anchor.
      node.requestFocus();
      await tester.pumpAndSettle();
      expect(_hint, findsNothing);
      await mouse.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(_hint, findsNothing);
    });

    testWidgets('${suite.name}: menu opened by click, then closed', (
      tester,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      final menu = MenuController();
      await tester.pumpWidget(
        scopedApp(
          Center(
            child: MenuAnchor(
              controller: menu,
              childFocusNode: node,
              menuChildren: [
                MenuItemButton(onPressed: () {}, child: const Text('item')),
              ],
              child: _target(node, onTap: () => menu.open()),
            ),
          ),
          suite,
        ),
      );
      await tester.pumpAndSettle();
      final mouse = await _hover(tester);
      await mouse.down(tester.getCenter(find.byKey(_anchor)));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.text('item'), findsOneWidget);
      expect(_hint, findsNothing);
      final item = tester.getCenter(find.text('item'));
      await mouse.moveTo(item);
      await mouse.down(item);
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.text('item'), findsNothing);
      expect(_hint, findsNothing);
      await mouse.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(_hint, findsNothing);
    });

    testWidgets('${suite.name}: anchor rebuilt or removed while hovered', (
      tester,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      var revision = 0;
      var shown = true;
      late StateSetter set;
      await tester.pumpWidget(
        scopedApp(
          StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return Center(
                child: shown
                    ? _target(node, revision: revision)
                    : const SizedBox(width: 40, height: 40),
              );
            },
          ),
          suite,
        ),
      );
      await tester.pumpAndSettle();
      final mouse = await _hover(tester);
      // A live refresh replaces the row under the pointer.
      set(() => revision++);
      await tester.pumpAndSettle();
      await mouse.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(_hint, findsNothing);
      await mouse.moveTo(tester.getCenter(find.byKey(_anchor)));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(_hint, findsOneWidget);
      set(() => shown = false);
      await tester.pumpAndSettle();
      expect(_hint, findsNothing);
    });

    testWidgets('${suite.name}: Escape and window deactivation', (
      tester,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(scopedApp(Center(child: _target(node)), suite));
      await tester.pumpAndSettle();
      await _hover(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_hint, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      node.requestFocus();
      await tester.pumpAndSettle();
      expect(_hint, findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(_hint, findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    });

    testWidgets('${suite.name}: keyboard focus still shows the hint', (
      tester,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(scopedApp(Center(child: _target(node)), suite));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      node.requestFocus();
      await tester.pumpAndSettle();
      expect(_hint, findsOneWidget);
      node.unfocus();
      await tester.pumpAndSettle();
      expect(_hint, findsNothing);
    });

    testWidgets('${suite.name}: earlier key press, focus handed back, hover', (
      tester,
    ) async {
      // Reported on build 11 for the account button: an earlier key press
      // (such as Alt+Tab) followed by focus being handed back made a later
      // plain hover keep its hint after the pointer left.
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(scopedApp(Center(child: _target(node)), suite));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.alt);
      node.requestFocus();
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byKey(_anchor)));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await mouse.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(_hint, findsNothing);
      // A click while it keeps focus, then hover again and leave.
      final center = tester.getCenter(find.byKey(_anchor));
      await mouse.moveTo(center);
      await mouse.down(center);
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await mouse.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(_hint, findsNothing);
    });
  }
}
