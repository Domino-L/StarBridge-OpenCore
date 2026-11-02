import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_style.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';

import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      'success toast ${suite.name} preserves view and close ownership',
      (tester) async {
        size(tester, const Size(800, 600));
        late BuildContext opener;
        var opened = 0;
        Widget surface({bool reduce = false}) => scopedApp(
          Builder(
            builder: (context) {
              opener = context;
              return const Text('交易页面');
            },
          ),
          suite,
          reduce: reduce,
        );
        await tester.pumpWidget(surface());
        await tester.pumpAndSettle();
        showTradeSuccess(opener, message: '提交成功', open: () => opened++);
        await tester.pumpAndSettle();
        final view = find.text('查看交易单');
        final action = find.ancestor(
          of: view,
          matching: find.byType(
            suite == InteractionSuite.standard ? TextButton : SuitePressable,
          ),
        );
        expect(
          action,
          findsOneWidget,
          reason: 'Trade success view must participate in the selected interaction suite.',
        );
        expect(
          tester.getRect(find.byKey(const Key('market-success-view'))),
          const Rect.fromLTRB(538, 534, 618, 582),
        );
        expect(tester.getRect(view), const Rect.fromLTRB(548, 552, 608, 564));
        expect(
          tester.getRect(find.byKey(const Key('market-success-close'))),
          const Rect.fromLTRB(618, 534, 666, 582),
        );
        expect(opened, 0);
        await tester.pumpWidget(surface(reduce: true));
        await tester.pump();
        await tester.pump();
        expect(
          resolveStarBridgeInteraction(tester.element(view)).reduceMotion,
          isTrue,
        );
        await tester.tap(view);
        expect(opened, 1);
        await tester.pumpAndSettle();
        expect(find.text('提交成功'), findsNothing);
        showTradeSuccess(opener, message: '再次提交成功', open: () => opened++);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('market-success-close')));
        await tester.pumpAndSettle();
        expect(opened, 1);
        expect(find.text('再次提交成功'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets(
      'success toast ${suite.name} preserves messenger queue and keyboard reader actions',
      (tester) async {
        size(tester, const Size(800, 600));
        final semantics = tester.ensureSemantics();
        late BuildContext opener;
        var opened = 0;
        try {
          await tester.pumpWidget(
            scopedApp(
              Builder(
                builder: (context) {
                  opener = context;
                  return const Text('交易页面');
                },
              ),
              suite,
            ),
          );
          await tester.pumpAndSettle();
          final messenger = ScaffoldMessenger.of(opener);
          final old = messenger.showSnackBar(
            const SnackBar(content: Text('原通知')),
          );
          await tester.pumpAndSettle();
          showTradeSuccess(opener, message: '提交成功', open: () => opened++);
          await tester.pumpAndSettle();
          expect(await old.closed, SnackBarClosedReason.hide);
          final next = messenger.showSnackBar(
            const SnackBar(
              content: Text('队列后继'),
              duration: Duration(seconds: 2),
            ),
          );
          final face = find.ancestor(
            of: find.text('查看交易单'),
            matching: find.byType(
              suite == InteractionSuite.standard ? TextButton : SuitePressable,
            ),
          );
          final focus = suite == InteractionSuite.standard
              ? tester.widget<TextButton>(face).focusNode!
              : tester.widget<SuitePressable>(face).focusNode!;
          focus.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(opened, 1);
          await tester.pumpAndSettle();
          expect(find.text('提交成功'), findsNothing);
          expect(find.text('队列后继'), findsOneWidget);
          await tester.pump(const Duration(seconds: 3));
          await tester.pumpAndSettle();
          expect(await next.closed, SnackBarClosedReason.timeout);
          expect(find.text('队列后继'), findsNothing);
          showTradeSuccess(opener, message: '只关闭', open: () => opened++);
          await tester.pumpAndSettle();
          final close = tester.getSemantics(find.bySemanticsLabel('关闭'));
          expect(
            close.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(close.id, SemanticsAction.tap);
          await tester.pumpAndSettle();
          expect(opened, 1);
          expect(find.text('只关闭'), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
        }
      },
    );
  }
}
