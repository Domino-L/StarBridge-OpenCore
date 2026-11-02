import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

import 'marketplace_trade_confirm_icons_motion_test.dart' show surface, target;
import 'marketplace_diagnostic_toast_motion_test.dart' show toastAnimation;
import 'marketplace_trades_test.dart' show TradesPort;
import '../friends/social_layout_test.dart' show size;
import '../../design_system/interaction/interaction_batch3b_test.dart'
    show exposedNodes;

Finder button(String suffix) => find.byKey(Key('market-confirm-$suffix'));
Finder face(String label, InteractionSuite suite, {bool primary = false}) =>
    find.ancestor(
      of: find.text(label),
      matching: find.byType(
        suite == InteractionSuite.standard
            ? primary
                  ? FilledButton
                  : OutlinedButton
            : SuitePressable,
      ),
    );

FocusNode focusOf(WidgetTester tester, Finder finder, InteractionSuite suite) {
  final widget = tester.widget(finder);
  return suite == InteractionSuite.standard
      ? (widget as ButtonStyleButton).focusNode!
      : (widget as SuitePressable).focusNode!;
}

SemanticsNode buttonNode(WidgetTester tester, String label) {
  final nodes = exposedNodes(tester)
      .where((n) => n.getSemanticsData().label == label)
      .toList();
  expect(
    nodes,
    hasLength(1),
    reason: 'One exposed accessible node for $label.',
  );
  expect(nodes.single.getSemanticsData().flagsCollection.isButton, isTrue);
  return nodes.single;
}

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      'confirmation ${suite.name} preserves native geometry and pointer keyboard reader cancel',
      (tester) async {
        size(tester, const Size(900, 900));
        final semantics = tester.ensureSemantics();
        final port = TradesPort();
        final controller = MarketplaceController(port);
        final trigger = FocusNode();
        try {
          await tester.pumpWidget(surface(controller, suite, trigger));
          await tester.pumpAndSettle();
          trigger.requestFocus();
          await tester.pump();
          Future<void> open() async {
            await tester.tap(find.text('打开确认'));
            await tester.pumpAndSettle();
          }

          await open();
          expect(
            face('取消', suite),
            findsOneWidget,
            reason: 'Trade dialog buttons must participate in the selected interaction suite.',
          );
          expect(face('确认发起', suite, primary: true), findsOneWidget);
          expect(
            tester.getRect(button('cancel')),
            const Rect.fromLTRB(492, 647.5, 564, 695.5),
          );
          expect(
            tester.getRect(button('submit')),
            const Rect.fromLTRB(572, 647.5, 660, 695.5),
          );
          expect(
            tester.getRect(find.text('取消')),
            const Rect.fromLTRB(516, 665.5, 540, 677.5),
          );
          expect(
            tester.getRect(find.text('确认发起')),
            const Rect.fromLTRB(592, 665.5, 640, 677.5),
          );
          final press = await tester.startGesture(
            tester.getCenter(button('cancel')),
          );
          await tester.pump(const Duration(milliseconds: 120));
          EffectHostState? effects;
          if (suite != InteractionSuite.standard) {
            effects = tester.state<EffectHostState>(
              find.descendant(
                of: button('cancel'),
                matching: find.byType(EffectHost),
              ),
            );
            if (suite == InteractionSuite.scan ||
                suite == InteractionSuite.glow) {
              expect(
                effects.isPlaying(
                  suite == InteractionSuite.scan
                      ? TransientEffect.beam
                      : TransientEffect.ring,
                ),
                isTrue,
              );
            } else {
              final transforms = tester.widgetList<Transform>(
                find.descendant(
                  of: button('cancel'),
                  matching: find.byType(Transform),
                ),
              );
              expect(transforms.any((w) => w.transform.storage[0] < 1), isTrue);
            }
          }
          await tester.pumpWidget(
            surface(controller, suite, trigger, reduce: true),
          );
          await tester.pump();
          if (effects != null) {
            expect(TransientEffect.values.any(effects.isPlaying), isFalse);
          }
          await press.up();
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(trigger.hasFocus, isTrue);
          await tester.pumpWidget(surface(controller, suite, trigger));
          await tester.pumpAndSettle();
          await open();
          focusOf(tester, face('取消', suite), suite).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(trigger.hasFocus, isTrue);
          await open();
          final node = buttonNode(tester, '取消');
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(node.id, SemanticsAction.tap);
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(trigger.hasFocus, isTrue);
          expect(port.writes, 0);
          expect(port.reads, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          trigger.dispose();
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'confirmation ${suite.name} keeps pending draft failure retry and confirmed success owner',
      (tester) async {
        size(tester, const Size(900, 900));
        final semantics = tester.ensureSemantics();
        var gate = Completer<MarketRow>();
        final port = TradesPort()..writeGate = gate;
        final controller = MarketplaceController(port);
        final trigger = FocusNode();
        try {
          await tester.pumpWidget(surface(controller, suite, trigger));
          await tester.pumpAndSettle();
          trigger.requestFocus();
          await tester.pump();
          await tester.tap(find.text('打开确认'));
          await tester.pumpAndSettle();
          await tester.tap(target('quantity-add'));
          await tester.pump();
          focusOf(
            tester,
            face('确认发起', suite, primary: true),
            suite,
          ).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(controller.trades.pending, isTrue);
          expect(port.writes, 1);
          for (final suffix in ['cancel', 'submit']) {
            final data = buttonNode(
              tester,
              suffix == 'cancel' ? '取消' : '正在发起…',
            ).getSemanticsData();
            expect(data.flagsCollection.isEnabled, Tristate.isFalse);
            expect(data.hasAction(SemanticsAction.tap), isFalse);
            await tester.tap(button(suffix), warnIfMissed: false);
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(port.writes, 1);
          expect(find.byType(Dialog), findsOneWidget);
          expect(find.text('2'), findsOneWidget);
          gate.completeError(
            const MarketplaceTradeError('marketplace.trade_rejected'),
          );
          await tester.pumpAndSettle();
          expect(controller.trades.pending, isFalse);
          expect(find.byType(Dialog), findsOneWidget);
          expect(find.text('2'), findsOneWidget);
          expect(find.text('重试'), findsOneWidget);
          gate = Completer<MarketRow>();
          port.writeGate = gate;
          final retry = buttonNode(tester, '重试');
          expect(
            retry.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(retry.id, SemanticsAction.tap);
          await tester.pump();
          expect(port.writes, 2);
          expect(controller.trades.pending, isTrue);
          gate.complete({'transactionNumber': 'T1', 'confirmed': true});
          await tester.pump();
          await tester.pump();
          expect(
            toastAnimation(tester).value,
            1,
            reason: 'Reader retry remains a direct response after the server result.',
          );
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(trigger.hasFocus, isTrue);
          expect(port.writes, 2);
          expect(controller.trades.pending, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          if (!gate.isCompleted) {
            gate.complete({'transactionNumber': 'T1', 'confirmed': true});
          }
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          trigger.dispose();
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'confirmation ${suite.name} ignores UI work from success after unmount',
      (tester) async {
        size(tester, const Size(900, 900));
        final gate = Completer<MarketRow>();
        final port = TradesPort()..writeGate = gate;
        final controller = MarketplaceController(port);
        final trigger = FocusNode();
        try {
          await tester.pumpWidget(surface(controller, suite, trigger));
          await tester.pumpAndSettle();
          await tester.tap(find.text('打开确认'));
          await tester.pumpAndSettle();
          await tester.tap(button('submit'));
          await tester.pump();
          expect(controller.trades.pending, isTrue);
          expect(port.writes, 1);
          await tester.pumpWidget(const SizedBox.shrink());
          gate.complete({'transactionNumber': 'T1', 'confirmed': true});
          await tester.pump();
          await tester.pump();
          expect(controller.trades.pending, isFalse);
          expect(find.byType(SnackBar), findsNothing);
          expect(port.writes, 1);
          expect(tester.takeException(), isNull);
        } finally {
          if (!gate.isCompleted) {
            gate.complete({'transactionNumber': 'T1', 'confirmed': true});
          }
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          trigger.dispose();
        }
      },
    );
  }
}
