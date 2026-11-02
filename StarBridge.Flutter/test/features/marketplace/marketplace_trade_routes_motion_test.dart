import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_item_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_profile.dart';

import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_trade_inner_motion_test.dart' show InnerProfilePort;
import 'marketplace_trade_button_motion_test.dart' show buttonNode;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

const offer = <String, Object?>{
  'orderNumber': 'O1',
  'itemId': 1,
  'itemName': 'Fixture item',
  'availableQuantity': 3,
  'locationId': 1,
  'creatorType': 1,
  'unitPrice': 10,
  'seller': 'Fixture',
};

void seed(MarketplaceController c) {
  c.itemId = 1;
  c.blocks['item'] = MarketRead({
    'id': 1,
    'itemName': 'Fixture item',
  }, DateTime.utc(2026, 10, 19));
  c.blocks['sell'] = MarketRead({
    'rows': [offer],
    'total': 1,
  }, DateTime.utc(2026, 10, 19));
  c.blocks['buy'] = MarketRead({
    'rows': <MarketRow>[],
    'total': 0,
  }, DateTime.utc(2026, 10, 19));
}

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '${suite.name}: reader quote and cancel actions complete routes within two frames',
      (tester) async {
        size(tester, const Size(1280, 900));
        final semantics = tester.ensureSemantics();
        final port = TradesPort();
        final c = MarketplaceController(port);
        seed(c);
        try {
          await tester.pumpWidget(scopedApp(MarketplaceItemPage(c), suite));
          await tester.pumpAndSettle();
          final quote = buttonNode(tester, '购买');
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(quote.id, SemanticsAction.tap);
          await tester.pump();
          await tester.pump();
          final route = ModalRoute.of(tester.element(find.byType(Dialog)))!;
          expect(route.animation!.value, 1);
          final cancel = buttonNode(tester, '取消');
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(cancel.id, SemanticsAction.tap);
          await tester.pump();
          await tester.pump();
          expect(route.animation!.value, 0);
          expect(find.byType(Dialog), findsNothing);
          expect(port.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          semantics.dispose();
        }
      },
    );
    testWidgets(
      '${suite.name}: local reduced motion settles entrance and exit without replay',
      (tester) async {
        size(tester, const Size(1280, 900));
        final setting = ValueNotifier(false);
        final port = TradesPort();
        final c = MarketplaceController(port);
        seed(c);
        try {
          await tester.pumpWidget(
            scopedApp(
              ValueListenableBuilder<bool>(
                valueListenable: setting,
                builder: (context, reduce, _) =>
                    StarBridgeInteractionConfiguration(
                      suite: suite,
                      reduceMotion: reduce,
                      child: MarketplaceItemPage(c),
                    ),
              ),
              InteractionSuite.standard,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('购买'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          final route = ModalRoute.of(tester.element(find.byType(Dialog)))!;
          expect(route.animation!.value, inExclusiveRange(0, 1));
          setting.value = true;
          await tester.pump();
          await tester.pump();
          expect(route.animation!.value, 1);
          expect(
            resolveStarBridgeInteraction(tester.element(find.text('确认发起')))
                .reduceMotion,
            isTrue,
          );
          setting.value = false;
          await tester.pump();
          await tester.pump();
          expect(route.animation!.value, 1);
          await tester.tap(find.text('取消'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(route.animation!.value, inExclusiveRange(0, 1));
          setting.value = true;
          await tester.pump();
          await tester.pump();
          expect(route.animation!.value, 0);
          expect(find.byType(Dialog), findsNothing);
          expect(port.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          setting.dispose();
        }
      },
    );
    testWidgets(
      '${suite.name}: keyboard order panel purchase preserves the native stretched button face',
      (tester) async {
        size(tester, const Size(1280, 900));
        final port = TradesPort();
        final c = MarketplaceController(port);
        seed(c);
        try {
          await tester.pumpWidget(scopedApp(MarketplaceItemPage(c), suite));
          await tester.pumpAndSettle();
          final row = find.byKey(
            const ValueKey<(String, Object)>(('market-offer-row', 'O1')),
          );
          expect(row, findsOneWidget);
          final rowBounds = tester.getRect(row);
          await tester.tapAt(Offset(rowBounds.left + 120, rowBounds.center.dy));
          await tester.pumpAndSettle();
          expect(find.text('订单详情'), findsOneWidget);
          final purchase = find.byKey(const Key('market-order-confirm'));
          final label = find.descendant(
            of: purchase,
            matching: find.text('购买'),
          );
          expect(
            tester.getRect(purchase),
            const Rect.fromLTRB(820, 832, 1260, 880),
          );
          final face = suite == InteractionSuite.standard
              ? find.descendant(of: purchase, matching: find.byType(Material))
              : find
                    .descendant(
                      of: purchase,
                      matching: find.byWidgetPredicate(
                        (w) =>
                            w is DecoratedBox &&
                            w.decoration is ShapeDecoration,
                      ),
                    )
                    .first;
          expect(
            tester.getRect(face),
            const Rect.fromLTRB(820, 836, 1260, 876),
            reason: 'Order-panel purchase must retain its full native painted width.',
          );
          expect(
            tester.getRect(label),
            const Rect.fromLTRB(1028, 850, 1052, 862),
          );
          Focus.of(tester.element(label)).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          final route = ModalRoute.of(tester.element(find.byType(Dialog).last))!;
          expect(
            route.animation!.value,
            1,
            reason: 'Keyboard order-panel purchase must open confirmation within two frames.',
          );
          await tester.tap(find.byKey(const Key('market-confirm-cancel')));
          await tester.pumpAndSettle();
          expect(find.text('订单详情'), findsOneWidget);
          Navigator.of(tester.element(find.text('订单详情'))).pop();
          await tester.pumpAndSettle();
          expect(port.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
        }
      },
    );
    testWidgets(
      '${suite.name}: open trade dialog follows local suite changes below the navigator',
      (tester) async {
        size(tester, const Size(1280, 900));
        final setting = ValueNotifier(suite);
        final next = suite == InteractionSuite.glow
            ? InteractionSuite.rail
            : InteractionSuite.glow;
        final c = MarketplaceController(TradesPort());
        seed(c);
        try {
          await tester.pumpWidget(
            scopedApp(
              ValueListenableBuilder<InteractionSuite>(
                valueListenable: setting,
                builder: (context, value, _) =>
                    StarBridgeInteractionConfiguration(
                      suite: value,
                      child: MarketplaceItemPage(c),
                    ),
              ),
              InteractionSuite.standard,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('购买'));
          await tester.pumpAndSettle();
          expect(
            resolveStarBridgeInteraction(tester.element(find.text('确认发起')))
                .suite,
            suite,
          );
          setting.value = next;
          await tester.pump();
          await tester.pump();
          expect(
            resolveStarBridgeInteraction(tester.element(find.text('确认发起')))
                .suite,
            next,
            reason: 'Open trade controls must follow the live local suite, not captured themes.',
          );
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          setting.dispose();
        }
      },
    );
    testWidgets(
      '${suite.name}: keyboard detail link retires confirmation before opening the order panel',
      (tester) async {
        size(tester, const Size(1280, 900));
        final port = TradesPort();
        final c = MarketplaceController(port);
        seed(c);
        try {
          await tester.pumpWidget(scopedApp(MarketplaceItemPage(c), suite));
          await tester.pumpAndSettle();
          await tester.tap(find.text('购买'));
          await tester.pumpAndSettle();
          final route = ModalRoute.of(tester.element(find.byType(Dialog)))!;
          final label = find.text('查看订单详情');
          expect(
            tester.getRect(find.byKey(const Key('market-confirm-details'))),
            const Rect.fromLTRB(430, 647.5, 522, 695.5),
          );
          expect(
            tester.getRect(label),
            const Rect.fromLTRB(440, 665.5, 512, 677.5),
          );
          Focus.of(tester.element(label)).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          expect(
            route.animation!.value,
            0,
            reason: 'Keyboard detail link must retire confirmation within two frames.',
          );
          await tester.pumpAndSettle();
          expect(find.text('订单详情'), findsOneWidget);
          expect(find.byKey(const Key('market-confirm-details')), findsNothing);
          expect(port.writes, 0);
          Navigator.of(tester.element(find.text('订单详情'))).pop();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
        }
      },
    );
    testWidgets(
      '${suite.name}: keyboard inspection closes only after readback without resubmitting',
      (tester) async {
        size(tester, const Size(1280, 900));
        final write = Completer<MarketRow>();
        final read = Completer<MarketRow>();
        final port = TradesPort()..writeGate = write;
        final c = MarketplaceController(port);
        seed(c);
        try {
          await tester.pumpWidget(scopedApp(MarketplaceItemPage(c), suite));
          await tester.pumpAndSettle();
          await tester.tap(find.text('购买'));
          await tester.pumpAndSettle();
          final route = ModalRoute.of(tester.element(find.byType(Dialog)))!;
          await tester.tap(find.byKey(const Key('market-confirm-submit')));
          await tester.pump();
          write.completeError(TimeoutException('fixture write receipt lost'));
          await tester.pumpAndSettle();
          expect(c.trades.writeUncertain, isTrue);
          expect(port.writes, 1);
          port.tradeReadGate = read;
          Focus.of(tester.element(find.text('刷新交易单'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(route.isCurrent, isTrue);
          expect(c.mainTab, 0);
          read.complete({
            'rows': [port.row],
            'total': 1,
          });
          await tester.pump();
          await tester.pump();
          expect(c.trades.writeUncertain, isFalse);
          expect(c.mainTab, 3);
          expect(port.writes, 1);
          expect(
            route.animation!.value,
            0,
            reason: 'Keyboard inspection must complete route exit within two readback frames.',
          );
          expect(find.byType(Dialog), findsNothing);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          if (!write.isCompleted) {
            write.completeError(TimeoutException('fixture cleanup'));
          }
          if (!read.isCompleted) {
            read.complete({
              'rows': [port.row],
              'total': 1,
            });
          }
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
        }
      },
    );
    testWidgets(
      '${suite.name}: keyboard accepted submit completes route exit after the awaited receipt',
      (tester) async {
        size(tester, const Size(1280, 900));
        final gate = Completer<MarketRow>();
        final port = TradesPort()..writeGate = gate;
        final c = MarketplaceController(port);
        seed(c);
        try {
          await tester.pumpWidget(scopedApp(MarketplaceItemPage(c), suite));
          await tester.pumpAndSettle();
          Focus.of(tester.element(find.text('购买'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          final route = ModalRoute.of(tester.element(find.byType(Dialog)))!;
          Focus.of(tester.element(find.text('确认发起'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(port.writes, 1);
          expect(c.trades.pending, isTrue);
          expect(route.isCurrent, isTrue);
          gate.complete({'transactionNumber': 'T1', 'confirmed': true});
          await tester.pump();
          await tester.pump();
          expect(c.trades.pending, isFalse);
          expect(
            route.animation!.value,
            0,
            reason: 'Keyboard accepted submit must complete route exit within two receipt frames.',
          );
          expect(find.byType(Dialog), findsNothing);
          expect(find.text('交易已发起，等待卖家发货'), findsOneWidget);
          expect(port.writes, 1);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          if (!gate.isCompleted) {
            gate.complete({'transactionNumber': 'T1', 'confirmed': true});
          }
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
        }
      },
    );
    testWidgets(
      '${suite.name}: keyboard Done returns accepted profile and completes its route within two frames',
      (tester) async {
        size(tester, const Size(1280, 900));
        final gate = Completer<MarketRow>();
        final port = InnerProfilePort()..profileGate = gate;
        final c = MarketplaceController(port);
        seed(c);
        try {
          await tester.pumpWidget(scopedApp(MarketplaceItemPage(c), suite));
          await tester.pumpAndSettle();
          Focus.of(tester.element(find.text('购买'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          await tester.tap(
            find.byKey(const Key('market-confirm-quantity-add')),
          );
          await tester.pump();
          await tester.tap(find.byKey(const Key('market-confirm-submit')));
          await tester.pumpAndSettle();
          Focus.of(tester.element(find.text('完善交易资料'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          final nested = ModalRoute.of(
            tester.element(find.byType(TradeProfileForm)),
          )!;
          await tester.enterText(
            find.byKey(const ValueKey('trade-profile-contact')),
            'route-fixture-contact',
          );
          Focus.of(tester.element(find.text('保存'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(port.saves, 1);
          gate.complete(port.accepted);
          await tester.pumpAndSettle();
          Focus.of(tester.element(find.text('完成'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          expect(
            nested.animation!.value,
            0,
            reason: 'Keyboard profile Done must complete route exit within two frames.',
          );
          expect(find.byType(TradeProfileForm), findsNothing);
          expect(find.text('2'), findsOneWidget);
          expect(find.text('完善交易资料'), findsNothing);
          expect(port.saves, 1);
          expect(port.writes, 1);
          await tester.tap(find.byKey(const Key('market-confirm-cancel')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          if (!gate.isCompleted) {
            gate.complete(port.accepted);
          }
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
        }
      },
    );
    testWidgets(
      '${suite.name}: keyboard preparation opens a live suite profile without submitting another trade',
      (tester) async {
        size(tester, const Size(1280, 900));
        final port = InnerProfilePort();
        final c = MarketplaceController(port);
        seed(c);
        try {
          await tester.pumpWidget(scopedApp(MarketplaceItemPage(c), suite));
          await tester.pumpAndSettle();
          Focus.of(tester.element(find.text('购买'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          await tester.tap(
            find.byKey(const Key('market-confirm-quantity-add')),
          );
          await tester.pump();
          await tester.tap(find.byKey(const Key('market-confirm-submit')));
          await tester.pumpAndSettle();
          expect(port.writes, 1);
          Focus.of(tester.element(find.text('完善交易资料'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          final nested = ModalRoute.of(
            tester.element(find.byType(TradeProfileForm)),
          )!;
          expect(
            nested,
            isA<StarBridgeDialogRoute>(),
            reason: 'Nested trade profile must use the selected suite route.',
          );
          expect(
            nested.animation!.value,
            1,
            reason:
                'Keyboard preparation must open the profile within two frames.',
          );
          expect(port.writes, 1);
          expect(port.saves, 0);
          await tester.tap(find.byKey(const Key('market-trade-profile-close')));
          await tester.pumpAndSettle();
          expect(find.byType(TradeProfileForm), findsNothing);
          expect(find.text('2'), findsOneWidget);
          expect(
            Focus.of(tester.element(find.text('完善交易资料'))).hasFocus,
            isTrue,
          );
          await tester.tap(find.byKey(const Key('market-confirm-cancel')));
          await tester.pumpAndSettle();
          expect(port.writes, 1);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
        }
      },
    );
    testWidgets(
      '${suite.name}: keyboard cancel removes the real confirmation route within two frames',
      (tester) async {
        size(tester, const Size(1280, 900));
        final c = MarketplaceController(TradesPort());
        seed(c);
        try {
          await tester.pumpWidget(scopedApp(MarketplaceItemPage(c), suite));
          await tester.pumpAndSettle();
          Focus.of(tester.element(find.text('购买'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          final route = ModalRoute.of(tester.element(find.byType(Dialog)))!;
          Focus.of(tester.element(find.text('取消'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          expect(
            route.animation!.value,
            0,
            reason: 'Keyboard trade cancellation must complete route exit within two frames.',
          );
          expect(find.byType(Dialog), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
        }
      },
    );
    testWidgets(
      '${suite.name}: keyboard real quote entry starts the confirmation at its final frame',
      (tester) async {
        size(tester, const Size(1280, 900));
        final port = TradesPort();
        final c = MarketplaceController(port);
        seed(c);
        try {
          await tester.pumpWidget(scopedApp(MarketplaceItemPage(c), suite));
          await tester.pumpAndSettle();
          Focus.of(tester.element(find.text('购买'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          final route = ModalRoute.of(tester.element(find.byType(Dialog)))!;
          expect(
            route.animation!.value,
            1,
            reason:
                'Keyboard quote opening must be complete within two frames.',
          );
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(port.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
        }
      },
    );
    testWidgets(
      '${suite.name}: real quote entry opens the selected trade dialog route',
      (tester) async {
        size(tester, const Size(1280, 900));
        final port = TradesPort();
        final c = MarketplaceController(port);
        seed(c);
        try {
          await tester.pumpWidget(scopedApp(MarketplaceItemPage(c), suite));
          await tester.pumpAndSettle();
          final entry = find.byKey(
            const ValueKey<(String, Object)>(('market-quote-confirm', 'O1')),
          );
          // Original quote button geometry (measured 44.2×22, label 24.2×17
          // inset 10/2.5). Vertical position follows the page heading above
          // it, so it is asserted relative to the button, not the viewport.
          final bounds = tester.getRect(entry);
          expect(bounds.left, closeTo(1224.8, .000001));
          expect(bounds.right, 1269);
          expect(bounds.height, 22);
          final label = tester.getRect(find.text('购买'));
          expect(label.left, closeTo(1234.8, .000001));
          expect(label.right, 1259);
          expect(label.top - bounds.top, 2.5);
          expect(label.bottom - bounds.top, 19.5);
          await tester.tap(find.text('购买'));
          await tester.pump();
          final route = ModalRoute.of(tester.element(find.byType(Dialog)));
          expect(
            route,
            isA<StarBridgeDialogRoute>(),
            reason: 'Trade confirmation must use the selected suite route from its real quote entry.',
          );
          expect(route!.barrierDismissible, isFalse);
          expect(route.animation!.value, lessThan(1));
          await tester.pump(const Duration(milliseconds: 16));
          expect(route.animation!.value, greaterThan(0));
          expect(route.animation!.value, lessThan(1));
          await tester.pumpAndSettle();
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(port.writes, 0);
          expect(find.byType(Dialog), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
        }
      },
    );
  }
}
