import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_prefetch.dart';

import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      'market ${suite.name} page retry preserves geometry and caller busy state',
      (tester) async {
        size(tester, const Size(800, 600));
        final semantics = tester.ensureSemantics();
        var pending = Completer<void>();
        var calls = 0, loading = false;
        try {
          Widget surface(bool reduce) => scopedApp(
            Center(
              child: SizedBox(
                width: 700,
                height: 100,
                child: StatefulBuilder(
                  builder: (context, update) => MarketPageStatus(
                    read: MarketRead({
                      'rows': <MarketRow>[],
                      'total': 1,
                    }, DateTime.utc(2026, 10, 19)),
                    failed: true,
                    loading: loading,
                    load: () async {
                      calls++;
                      update(() => loading = true);
                      await pending.future;
                      update(() => loading = false);
                    },
                  ),
                ),
              ),
            ),
            suite,
            reduce: reduce,
          );
          await tester.pumpWidget(surface(false));
          await tester.pumpAndSettle();
          final label = find.text('重试');
          expect(label, findsOneWidget);
          expect(calls, 0);
          final face = find.ancestor(
            of: label,
            matching: find.byType(
              suite == InteractionSuite.standard ? TextButton : SuitePressable,
            ),
          );
          expect(
            face,
            findsOneWidget,
            reason: 'Page retry must participate in the selected interaction suite.',
          );
          final target = find.byKey(const Key('market-page-status-retry'));
          expect(
            tester.getRect(target),
            const Rect.fromLTRB(376, 276, 424, 324),
          );
          expect(
            tester.getRect(label),
            const Rect.fromLTRB(388, 294, 412, 306),
          );
          await tester.tap(label);
          expect(calls, 1);
          await tester.pump();
          final disabled = tester.getSemantics(face).getSemanticsData();
          expect(disabled.flagsCollection.isEnabled, Tristate.isFalse);
          expect(disabled.hasAction(SemanticsAction.tap), isFalse);
          expect(
            tester.getRect(target),
            const Rect.fromLTRB(376, 276, 424, 324),
          );
          await tester.tap(label, warnIfMissed: false);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pump();
          expect(calls, 1);
          await tester.pumpWidget(surface(true));
          await tester.pump();
          expect(
            resolveStarBridgeInteraction(tester.element(target)).reduceMotion,
            isTrue,
          );
          expect(
            tester
                .getSemantics(face)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isFalse,
          );
          pending.complete();
          await tester.pumpAndSettle();
          expect(
            tester
                .getSemantics(face)
                .getSemanticsData()
                .flagsCollection
                .isEnabled,
            Tristate.isTrue,
          );
          expect(
            calls,
            1,
            reason: 'Owner completion and rebuild cannot start another retry.',
          );
          expect(find.text('重试'), findsOneWidget);
          expect(find.bySemanticsLabel('重试'), findsOneWidget);
          pending = Completer<void>();
          final focus = suite == InteractionSuite.standard
              ? tester.widget<TextButton>(face).focusNode!
              : tester.widget<SuitePressable>(face).focusNode!;
          focus.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(calls, 2);
          expect(
            tester
                .getSemantics(face)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isFalse,
          );
          pending.complete();
          await tester.pumpAndSettle();
          pending = Completer<void>();
          final node = tester.getSemantics(face);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(node.id, SemanticsAction.tap);
          await tester.pump();
          expect(calls, 3);
          expect(
            tester
                .getSemantics(face)
                .getSemanticsData()
                .flagsCollection
                .isEnabled,
            Tristate.isFalse,
          );
          pending.complete();
          await tester.pumpAndSettle();
          expect(calls, 3);
          expect(
            tester.getRect(target),
            const Rect.fromLTRB(376, 276, 424, 324),
          );
          expect(
            tester.getRect(label),
            const Rect.fromLTRB(388, 294, 412, 306),
          );
          expect(tester.takeException(), isNull);
        } finally {
          if (!pending.isCompleted) pending.complete();
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
        }
      },
    );
  }
}
