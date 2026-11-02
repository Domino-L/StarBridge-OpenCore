import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

Widget host(InteractionSuite suite, Widget child) => InteractionScope(
  data: InteractionData(suite: suite, palette: palette),
  child: MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ),
);

List<SemanticsNode> nodes(WidgetTester tester) {
  final list = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    list.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return list;
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final exclude in [false, true]) {
      testWidgets(
        '$suite hint semantics excluded=$exclude; bubble never repeated',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            await t.pumpWidget(
              host(
                suite,
                SuiteTooltip(
                  message: 'Hint',
                  excludeFromSemantics: exclude,
                  waitDuration: Duration.zero,
                  child: const Text('Target'),
                ),
              ),
            );
            final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
            await mouse.addPointer(location: t.getCenter(find.text('Target')));
            await t.pumpAndSettle();
            expect(find.text('Hint'), findsOneWidget);
            expect(
              nodes(t)
                  .where((node) => node.getSemanticsData().tooltip == 'Hint'),
              hasLength(exclude ? 0 : 1),
            );
            expect(
              nodes(t).where((node) => node.getSemanticsData().label == 'Hint'),
              isEmpty,
            );
            await mouse.removePointer();
            await t.pumpAndSettle();
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    testWidgets('$suite Escape hides focused hint instantly', (t) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await t.pumpWidget(
        host(
          suite,
          SuiteTooltip(
            message: 'Hint',
            child: Focus(focusNode: focus, child: const Text('Target')),
          ),
        ),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      focus.requestFocus();
      await t.pump();
      await t.pump();
      expect(find.text('Hint'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(find.text('Hint'), findsNothing);
      expect(focus.hasFocus, isTrue);
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('$suite touch long press expires without activating target', (
      t,
    ) async {
      var calls = 0;
      await t.pumpWidget(
        host(
          suite,
          SuiteTooltip(
            message: 'Hint',
            showDuration: const Duration(milliseconds: 100),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => calls++,
              child: const SizedBox(
                key: Key('touch-target'),
                width: 50,
                height: 50,
              ),
            ),
          ),
        ),
      );
      final touch = await t.startGesture(
        t.getCenter(find.byKey(const Key('touch-target'))),
      );
      await t.pump(const Duration(milliseconds: 600));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Hint'), findsOneWidget);
      await touch.up();
      await t.pump(const Duration(milliseconds: 150));
      await t.pumpAndSettle();
      expect(find.text('Hint'), findsNothing);
      expect(calls, 0);
    });
  }
}
