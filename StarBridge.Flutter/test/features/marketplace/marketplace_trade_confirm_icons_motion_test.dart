import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_native_icon_action.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_confirm.dart';

import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;
import 'marketplace_trades_test.dart' show TradesPort;

Finder target(String suffix) => find.byKey(Key('market-confirm-$suffix'));
Finder nativeIcon(String suffix) =>
    find.descendant(of: target(suffix), matching: find.byType(IconButton));
Finder quantityText() => find.descendant(
  of: find.byWidgetPredicate((w) => w is SizedBox && w.width == 36),
  matching: find.byType(Text),
);

Widget surface(
  MarketplaceController controller,
  InteractionSuite suite,
  FocusNode trigger, {
  bool reduce = false,
}) => scopedApp(
  Builder(
    builder: (context) => TextButton(
      focusNode: trigger,
      onPressed: () => confirmMarketTrade(context, controller, {
        'availableQuantity': 3,
        'locationId': 1,
        'creatorType': 1,
        'unitPrice': 10,
      }),
      child: const Text('打开确认'),
    ),
  ),
  suite,
  reduce: reduce,
);

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      'trade confirm ${suite.name} icons preserve compact targets limits and input',
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
          await tester.tap(find.text('打开确认'));
          await tester.pumpAndSettle();
          expect(
            find.byType(StarBridgeNativeIconAction),
            findsNWidgets(3),
            reason: 'Trade confirmation icons must participate in the selected interaction suite.',
          );
          expect(
            tester.getRect(target('quantity-add')),
            const Rect.fromLTRB(619, 271.5, 659, 309.5),
          );
          expect(
            tester.getRect(target('quantity-remove')),
            const Rect.fromLTRB(543, 271.5, 583, 309.5),
          );
          expect(
            tester.getRect(target('close')),
            const Rect.fromLTRB(612, 204.5, 660, 252.5),
          );
          expect(
            tester
                .widget<IconButton>(nativeIcon('quantity-add'))
                .focusNode!
                .hasFocus,
            isTrue,
          );
          expect(
            tester
                .getSemantics(target('quantity-remove'))
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isFalse,
          );
          await tester.tap(target('quantity-add'));
          await tester.pump();
          expect(tester.widget<Text>(quantityText()).data, '2');
          await tester.tap(target('quantity-add'));
          await tester.pump();
          expect(tester.widget<Text>(quantityText()).data, '3');
          expect(
            tester
                .getSemantics(target('quantity-add'))
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isFalse,
          );
          await tester.tap(target('quantity-add'), warnIfMissed: false);
          await tester.pump();
          expect(tester.widget<Text>(quantityText()).data, '3');
          tester
              .widget<IconButton>(nativeIcon('quantity-remove'))
              .focusNode!
              .requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(tester.widget<Text>(quantityText()).data, '2');
          final node = tester.getSemantics(target('quantity-remove'));
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(node.id, SemanticsAction.tap);
          await tester.pump();
          expect(tester.widget<Text>(quantityText()).data, '1');
          await tester.pumpWidget(
            surface(controller, suite, trigger, reduce: true),
          );
          await tester.pump();
          expect(
            resolveStarBridgeInteraction(tester.element(target('quantity-add')))
                .reduceMotion,
            isTrue,
          );
          await tester.tap(target('quantity-add'));
          await tester.pump();
          expect(tester.widget<Text>(quantityText()).data, '2');
          expect(port.writes, 0);
          expect(port.reads, 0);
          await tester.tap(target('close'));
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(trigger.hasFocus, isTrue);
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
      'trade confirm ${suite.name} pending owner disables icons without changing draft',
      (tester) async {
        size(tester, const Size(900, 900));
        final semantics = tester.ensureSemantics();
        final gate = Completer<MarketRow>();
        final port = TradesPort()..writeGate = gate;
        final controller = MarketplaceController(port);
        final trigger = FocusNode();
        Future<String?>? pending;
        try {
          await tester.pumpWidget(surface(controller, suite, trigger));
          await tester.pumpAndSettle();
          trigger.requestFocus();
          await tester.pump();
          await tester.tap(find.text('打开确认'));
          await tester.pumpAndSettle();
          await tester.tap(target('quantity-add'));
          await tester.pump();
          expect(tester.widget<Text>(quantityText()).data, '2');
          pending = controller.trades.submit('create', {
            'orderNumber': 'SYNTHETIC',
            'number': 2,
          });
          await tester.pump();
          expect(controller.trades.pending, isTrue);
          for (final suffix in ['quantity-add', 'quantity-remove', 'close']) {
            final data = tester.getSemantics(target(suffix)).getSemanticsData();
            expect(data.flagsCollection.isEnabled, Tristate.isFalse);
            expect(data.hasAction(SemanticsAction.tap), isFalse);
            await tester.tap(target(suffix), warnIfMissed: false);
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(find.byType(Dialog), findsOneWidget);
          expect(tester.widget<Text>(quantityText()).data, '2');
          expect(port.writes, 1);
          gate.complete({'transactionNumber': 'T1', 'confirmed': true});
          expect(await pending, 'T1');
          await tester.pumpAndSettle();
          expect(controller.trades.pending, isFalse);
          expect(tester.widget<Text>(quantityText()).data, '2');
          expect(
            tester
                .getSemantics(target('quantity-add'))
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue,
          );
          expect(port.writes, 1);
          await tester.tap(target('close'));
          await tester.pumpAndSettle();
          expect(trigger.hasFocus, isTrue);
          expect(tester.takeException(), isNull);
        } finally {
          if (!gate.isCompleted) {
            gate.complete({'transactionNumber': 'T1', 'confirmed': true});
          }
          await pending;
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          trigger.dispose();
          semantics.dispose();
        }
      },
    );
  }
}
