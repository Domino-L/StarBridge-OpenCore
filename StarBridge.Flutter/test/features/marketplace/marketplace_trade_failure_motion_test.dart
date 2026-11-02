import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_feedback.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';

import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;
import 'marketplace_trades_test.dart' show TradesPort;

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      'trade failure ${suite.name} retries retain native geometry and direct input',
      (tester) async {
        size(tester, const Size(800, 600));
        final semantics = tester.ensureSemantics();
        final port = TradesPort();
        final controller = MarketplaceController(port);
        var calls = 0;
        try {
          controller.trades.error = '暂时读不到交易';
          Widget surface({bool reduce = false}) => scopedApp(
            Center(
              child: SizedBox(
                width: 700,
                child: TradeFailure(controller, retry: () => calls++),
              ),
            ),
            suite,
            reduce: reduce,
          );
          await tester.pumpWidget(surface());
          await tester.pumpAndSettle();
          final label = find.text('重试');
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
            reason: 'Trade failure action must participate in the selected interaction suite.',
          );
          expect(
            tester.getRect(
              find.byKey(const Key('market-trade-failure-action')),
            ),
            const Rect.fromLTRB(50, 44, 98, 92),
          );
          expect(tester.getRect(label), const Rect.fromLTRB(62, 62, 86, 74));
          await tester.tap(label);
          await tester.tap(label);
          await tester.tap(label);
          expect(calls, 3);
          await tester.pump();
          final focus = suite == InteractionSuite.standard
              ? tester.widget<TextButton>(face).focusNode!
              : tester.widget<SuitePressable>(face).focusNode!;
          focus.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(calls, 4);
          final node = tester.getSemantics(face);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(node.id, SemanticsAction.tap);
          await tester.pump();
          expect(calls, 5);
          await tester.pumpWidget(surface(reduce: true));
          await tester.pump();
          expect(
            resolveStarBridgeInteraction(tester.element(label)).reduceMotion,
            isTrue,
          );
          expect(find.bySemanticsLabel('重试'), findsOneWidget);
          await tester.tap(label);
          expect(calls, 6);
          expect(port.writes, 0);
          expect(port.reads, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          semantics.dispose();
        }
      },
    );
    testWidgets(
      'trade failure ${suite.name} retains login availability and uncertain refresh meaning',
      (tester) async {
        size(tester, const Size(800, 600));
        final semantics = tester.ensureSemantics();
        final port = TradesPort();
        final controller = MarketplaceController(port);
        var retries = 0, logins = 0;
        try {
          Widget surface() => scopedApp(
            TradeFailure(controller, retry: () => retries++, writing: true),
            suite,
          );
          controller.trades.writeErrorCode = 'marketplace.sign_in_required';
          await tester.pumpWidget(surface());
          await tester.pumpAndSettle();
          final login = find.text('登录 SCM');
          expect(login, findsOneWidget);
          final disabled = tester.getSemantics(login).getSemanticsData();
          expect(disabled.flagsCollection.isEnabled, Tristate.isFalse);
          expect(disabled.hasAction(SemanticsAction.tap), isFalse);
          await tester.tap(login, warnIfMissed: false);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(logins, 0);
          expect(retries, 0);
          controller.login = (_) async {
            logins++;
          };
          await tester.pumpWidget(surface());
          await tester.pumpAndSettle();
          await tester.tap(login);
          expect(logins, 1);
          expect(retries, 0);
          controller.trades.writeErrorCode = 'marketplace.trade_rejected';
          controller.trades.writeUncertain = false;
          await tester.pumpWidget(surface());
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('market-trade-failure-action')),
            findsNothing,
          );
          controller.trades.writeUncertain = true;
          await tester.pumpWidget(surface());
          await tester.pumpAndSettle();
          expect(find.text('刷新交易单'), findsOneWidget);
          expect(find.text('重试'), findsNothing);
          await tester.tap(find.text('刷新交易单'));
          expect(retries, 1);
          expect(controller.trades.writeUncertain, isTrue);
          expect(port.writes, 0);
          expect(port.reads, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          semantics.dispose();
        }
      },
    );
  }
}
