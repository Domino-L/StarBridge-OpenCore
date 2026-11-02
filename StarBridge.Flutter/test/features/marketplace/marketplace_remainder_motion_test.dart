import 'dart:ui' show CheckedState, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_widgets.dart';

import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      'market ${suite.name} remainder forwards each open once with stable geometry',
      (tester) async {
        size(tester, const Size(800, 600));
        final semantics = tester.ensureSemantics();
        try {
          var opens = 0;
          Widget surface(bool reduce) => scopedApp(
            Center(
              child: SizedBox(
                width: 700,
                child: MarketRemainder(
                  count: 4,
                  total: 42,
                  open: () => opens++,
                ),
              ),
            ),
            suite,
            reduce: reduce,
          );
          await tester.pumpWidget(surface(false));
          await tester.pumpAndSettle();
          final label = find.text('显示全部 42 种');
          expect(label, findsOneWidget);
          expect(find.text('其余 4 种暂时没有挂单'), findsOneWidget);
          expect(opens, 0);
          final slot = find.ancestor(
            of: label,
            matching: find.byWidgetPredicate(
              (widget) => widget is SizedBox && widget.height == 28,
            ),
          );
          expect(slot, findsOneWidget);
          final originalSize = tester.getSize(slot);
          expect(tester.getSize(slot).height, 28);
          expect(
            tester.renderObject<RenderParagraph>(label).text.style?.fontSize,
            12,
          );
          final face = find.ancestor(
            of: label,
            matching: find.byType(
              suite == InteractionSuite.standard
                  ? OutlinedButton
                  : SuitePressable,
            ),
          );
          expect(
            face,
            findsOneWidget,
            reason:
                'Show all must participate in the selected interaction suite.',
          );
          for (var i = 0; i < 3; i++) {
            await tester.tap(label);
            expect(opens, i + 1);
            await tester.pump(const Duration(milliseconds: 16));
          }
          final focus = suite == InteractionSuite.standard
              ? tester.widget<OutlinedButton>(face).focusNode!
              : tester.widget<SuitePressable>(face).focusNode!;
          focus.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pump();
          expect(opens, 4);
          final node = tester.getSemantics(face);
          expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
          expect(
            node.getSemanticsData().flagsCollection.isChecked,
            CheckedState.none,
          );
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(node.id, SemanticsAction.tap);
          await tester.pump();
          expect(opens, 5);
          expect(tester.getSize(slot), originalSize);
          expect(find.bySemanticsLabel('显示全部 42 种'), findsOneWidget);
          await tester.pumpWidget(surface(true));
          await tester.pump();
          expect(
            resolveStarBridgeInteraction(tester.element(face)).reduceMotion,
            isTrue,
          );
          await tester.tap(label);
          expect(opens, 6);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(opens, 7);
          expect(tester.getSize(slot), originalSize);
          expect(find.text('其余 4 种暂时没有挂单'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
