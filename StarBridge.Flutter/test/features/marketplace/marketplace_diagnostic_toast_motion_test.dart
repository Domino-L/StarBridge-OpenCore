import 'dart:async';
import 'dart:ui' show SemanticsAction;

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

AnimationController toastAnimation(WidgetTester tester) =>
    tester
            .widget<SuiteSurfaceTransition>(
              find.byWidgetPredicate(
                (w) =>
                    w is SuiteSurfaceTransition && w.kind == SurfaceKind.toast,
              ),
            )
            .animation
        as AnimationController;

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      'diagnostic ${suite.name} preserves clipboard await and input source',
      (tester) async {
        size(tester, const Size(800, 600));
        final semantics = tester.ensureSemantics();
        var gate = Completer<void>();
        final port = TradesPort();
        final controller = MarketplaceController(port);
        String? copied;
        var copies = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copies++;
              copied = (call.arguments as Map)['text'] as String;
              await gate.future;
            }
            return null;
          },
        );
        try {
          controller.trades.errorCode = 'marketplace.forbidden';
          controller.trades.error = '交易暂时不可用';
          Widget surface({bool reduce = false}) => scopedApp(
            TradeFailure(controller, retry: () {}),
            suite,
            reduce: reduce,
          );
          await tester.pumpWidget(surface());
          await tester.pumpAndSettle();
          final label = find.text('复制诊断信息');
          final face = find.ancestor(
            of: label,
            matching: find.byType(
              suite == InteractionSuite.standard ? TextButton : SuitePressable,
            ),
          );
          final messenger = ScaffoldMessenger.of(tester.element(label));
          await tester.tap(label);
          await tester.pump();
          expect(copied, contains('code=403'));
          expect(copies, 1);
          expect(find.text('诊断信息已复制'), findsNothing);
          gate.complete();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.text('诊断信息已复制'), findsOneWidget);
          expect(
            find.byWidgetPredicate(
              (w) => w is SuiteSurfaceTransition && w.kind == SurfaceKind.toast,
            ),
            findsOneWidget,
            reason: 'Diagnostic confirmation must participate in the selected interaction suite.',
          );
          expect(toastAnimation(tester).value, lessThan(1));
          await tester.pumpAndSettle();
          expect(
            tester.widget<SnackBar>(find.byType(SnackBar)).duration,
            const Duration(seconds: 4),
          );
          messenger.hideCurrentSnackBar();
          await tester.pumpAndSettle();
          gate = Completer<void>();
          final focus = suite == InteractionSuite.standard
              ? tester.widget<TextButton>(face).focusNode!
              : tester.widget<SuitePressable>(face).focusNode!;
          focus.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(copies, 2);
          expect(find.text('诊断信息已复制'), findsNothing);
          gate.complete();
          await tester.pump();
          await tester.pump();
          expect(
            toastAnimation(tester).value,
            1,
            reason: 'Keyboard origin must survive the awaited clipboard call.',
          );
          messenger.hideCurrentSnackBar();
          await tester.pumpAndSettle();
          gate = Completer<void>();
          final node = tester.getSemantics(face);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(node.id, SemanticsAction.tap);
          await tester.pump();
          expect(copies, 3);
          gate.complete();
          await tester.pump();
          await tester.pump();
          expect(toastAnimation(tester).value, 1);
          messenger.hideCurrentSnackBar();
          await tester.pumpAndSettle();
          gate = Completer<void>();
          await tester.tap(label);
          await tester.pump();
          expect(copies, 4);
          await tester.pumpWidget(surface(reduce: true));
          await tester.pump();
          gate.complete();
          await tester.pump();
          await tester.pump();
          expect(toastAnimation(tester).value, 1);
          expect(
            resolveStarBridgeInteraction(tester.element(find.text('诊断信息已复制')))
                .reduceMotion,
            isTrue,
          );
          expect(controller.trades.errorCode, 'marketplace.forbidden');
          expect(port.writes, 0);
          expect(port.reads, 0);
          expect(tester.takeException(), isNull);
        } finally {
          if (!gate.isCompleted) gate.complete();
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          semantics.dispose();
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        }
      },
    );
  }
  testWidgets(
    'diagnostic completion after unmount cannot open a confirmation',
    (tester) async {
      final gate = Completer<void>();
      final controller = MarketplaceController(TradesPort());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') await gate.future;
          return null;
        },
      );
      try {
        controller.trades.errorCode = 'marketplace.forbidden';
        await tester.pumpWidget(
          scopedApp(
            TradeFailure(controller, retry: () {}),
            InteractionSuite.scan,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('复制诊断信息'));
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        gate.complete();
        await tester.pump();
        expect(find.text('诊断信息已复制'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      }
    },
  );
}
