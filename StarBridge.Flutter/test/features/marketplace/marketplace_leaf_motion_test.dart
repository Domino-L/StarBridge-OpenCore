import 'dart:ui' show CheckedState, SemanticsAction, Tristate;

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
      'market ${suite.name} toggle keeps button role and immediate selected requests',
      (tester) async {
        size(tester, const Size(800, 600));
        final semantics = tester.ensureSemantics();
        try {
          var selected = false;
          final requests = <bool>[];
          Widget surface(bool reduce) => scopedApp(
            Center(
              child: StatefulBuilder(
                builder: (context, update) => MarketToggle(
                  key: const Key('market-toggle-probe'),
                  label: const Text('测试筛选'),
                  selected: selected,
                  onSelected: (value) {
                    requests.add(value);
                    update(() => selected = value);
                  },
                ),
              ),
            ),
            suite,
            reduce: reduce,
          );
          await tester.pumpWidget(surface(false));
          await tester.pumpAndSettle();
          final target = find.byKey(const Key('market-toggle-probe'));
          final originalSize = tester.getSize(target);
          expect(tester.getSize(target).height, 28);
          expect(
            tester
                .renderObject<RenderParagraph>(find.text('测试筛选'))
                .text
                .style
                ?.fontSize,
            12,
          );
          final face = find.descendant(
            of: target,
            matching: find.byType(
              suite == InteractionSuite.standard
                  ? TextButton
                  : SuitePressable,
            ),
          );
          expect(
            face,
            findsOneWidget,
            reason: 'Market toggle must expose the selected suite without changing its button role.',
          );
          for (var i = 0; i < 3; i++) {
            await tester.tap(target);
            await tester.pump(const Duration(milliseconds: 16));
          }
          expect(requests, [true, false, true]);
          final node = tester.getSemantics(target);
          expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
          expect(
            node.getSemanticsData().flagsCollection.isSelected,
            Tristate.isTrue,
          );
          expect(
            node.getSemanticsData().flagsCollection.isChecked,
            CheckedState.none,
          );
          final focus = suite == InteractionSuite.standard
              ? tester.widget<TextButton>(face).focusNode!
              : tester.widget<SuitePressable>(face).focusNode!;
          focus.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pump();
          expect(requests, [true, false, true, false]);
          final current = tester.getSemantics(target);
          expect(
            current.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
            reason:
                'The selected button node must retain the activation action.',
          );
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(current.id, SemanticsAction.tap);
          await tester.pump();
          expect(requests, [true, false, true, false, true]);
          expect(tester.getSize(target), originalSize);
          expect(find.bySemanticsLabel('测试筛选'), findsOneWidget);
          await tester.pumpWidget(surface(true));
          await tester.pump();
          expect(
            resolveStarBridgeInteraction(tester.element(target)).reduceMotion,
            isTrue,
          );
          await tester.tap(target);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(requests, [true, false, true, false, true, false, true]);
          expect(tester.getSize(target), originalSize);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
