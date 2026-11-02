import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_page.dart'
    show MarketplaceTradesPage, TradeRow, TradeSheet;

import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_trade_inner_motion_test.dart'
    show InnerTradePort, namedButton, activate;
import 'marketplace_diagnostic_toast_motion_test.dart' show toastAnimation;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '${suite.name}: global reduction settles the active action route without replay',
      (tester) async {
        size(tester, const Size(1280, 900));
        final reduce = ValueNotifier(false);
        final port = TradesPort();
        final controller = MarketplaceController(port);
        try {
          await controller.trades.refresh();
          await tester.pumpWidget(
            ValueListenableBuilder<bool>(
              valueListenable: reduce,
              builder: (context, value, _) => scopedApp(
                MarketplaceTradesPage(controller),
                suite,
                reduce: value,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(TradeRow));
          await tester.pumpAndSettle();
          final sheetRoute = ModalRoute.of(
            tester.element(find.byType(TradeSheet)),
          )!;
          await tester.tap(find.byKey(const Key('market-trade-sheet-cancel')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          final cancel = find.byKey(const Key('market-trade-action-cancel'));
          final route = ModalRoute.of(tester.element(cancel))!;
          expect(route.animation!.value, inExclusiveRange(0, 1));
          reduce.value = true;
          await tester.pump();
          await tester.pump();
          expect(route.animation!.value, 1);
          reduce.value = false;
          await tester.pump();
          await tester.pump();
          expect(route.animation!.value, 1);
          await tester.tap(cancel);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(route.animation!.value, inExclusiveRange(0, 1));
          reduce.value = true;
          await tester.pump();
          await tester.pump();
          expect(route.animation!.value, 0);
          expect(cancel, findsNothing);
          expect(sheetRoute.isCurrent, isTrue);
          expect(port.writes, 0);
          Navigator.of(tester.element(find.byType(TradeSheet))).pop();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          reduce.dispose();
        }
      },
    );
    testWidgets(
      '${suite.name}: reader entry and cancellation activate actual accessible route actions',
      (tester) async {
        size(tester, const Size(1280, 900));
        final semantics = tester.ensureSemantics();
        final port = TradesPort();
        final controller = MarketplaceController(port);
        try {
          await controller.trades.refresh();
          await tester.pumpWidget(
            scopedApp(MarketplaceTradesPage(controller), suite),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(TradeRow));
          await tester.pumpAndSettle();
          final sheetRoute = ModalRoute.of(
            tester.element(find.byType(TradeSheet)),
          )!;
          activate(tester, namedButton(tester, '取消交易'));
          await tester.pump();
          await tester.pump();
          final cancel = find.byKey(const Key('market-trade-action-cancel'));
          final route = ModalRoute.of(tester.element(cancel))!;
          expect(route.animation!.value, 1);
          activate(tester, namedButton(tester, '取消'));
          await tester.pump();
          await tester.pump();
          expect(route.animation!.value, 0);
          expect(cancel, findsNothing);
          expect(sheetRoute.isCurrent, isTrue);
          namedButton(tester, '取消交易');
          expect(port.writes, 0);
          Navigator.of(tester.element(find.byType(TradeSheet))).pop();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          semantics.dispose();
        }
      },
    );
    testWidgets(
      '${suite.name}: late inspection during child exit cannot dismiss the parent trade sheet',
      (tester) async {
        size(tester, const Size(1280, 900));
        final write = Completer<MarketRow>();
        final read = Completer<MarketRow>();
        final port = InnerTradePort()..writeGate = write;
        final controller = MarketplaceController(port);
        try {
          await controller.trades.refresh();
          await tester.pumpWidget(
            scopedApp(MarketplaceTradesPage(controller), suite),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(TradeRow));
          await tester.pumpAndSettle();
          final sheetRoute = ModalRoute.of(
            tester.element(find.byType(TradeSheet)),
          )!;
          await tester.tap(find.byKey(const Key('market-trade-sheet-cancel')));
          await tester.pumpAndSettle();
          final cancel = find.byKey(const Key('market-trade-action-cancel'));
          final childContext = tester.element(cancel);
          final childRoute = ModalRoute.of(childContext)!;
          await tester.tap(find.byKey(const Key('market-trade-action-submit')));
          await tester.pump();
          write.completeError(TimeoutException('fixture lost receipt'));
          await tester.pumpAndSettle();
          expect(controller.trades.writeUncertain, isTrue);
          port.tradeReadGate = read;
          await tester.tap(find.text('刷新交易单'));
          await tester.pump();
          expect(controller.trades.loading, isTrue);
          await tester.tap(cancel);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(childContext.mounted, isTrue);
          expect(childRoute.animation!.value, inExclusiveRange(0, 1));
          expect(sheetRoute.isCurrent, isTrue);
          read.complete({
            'rows': [port.row],
            'total': 1,
          });
          await tester.pump();
          await tester.pump();
          expect(controller.trades.writeUncertain, isFalse);
          expect(controller.trades.detail?['transactionNumber'], 'T1');
          expect(
            sheetRoute.isCurrent,
            isTrue,
            reason: 'Late inspection must not dismiss the parent trade sheet during child exit.',
          );
          expect(port.writes, 1);
          await tester.pumpAndSettle();
          expect(find.byType(TradeSheet), findsOneWidget);
          expect(cancel, findsNothing);
          Navigator.of(tester.element(find.byType(TradeSheet))).pop();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          if (!write.isCompleted) {
            write.complete({'transactionNumber': 'T1', 'confirmed': true});
          }
          if (!read.isCompleted) {
            read.complete({
              'rows': [port.row],
              'total': 1,
            });
          }
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      },
    );
    testWidgets(
      '${suite.name}: keyboard action inspection closes after readback without another mutation',
      (tester) async {
        size(tester, const Size(1280, 900));
        final write = Completer<MarketRow>();
        final read = Completer<MarketRow>();
        final port = InnerTradePort()..writeGate = write;
        final controller = MarketplaceController(port);
        try {
          await controller.trades.refresh();
          await tester.pumpWidget(
            scopedApp(MarketplaceTradesPage(controller), suite),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(TradeRow));
          await tester.pumpAndSettle();
          final sheetRoute = ModalRoute.of(
            tester.element(find.byType(TradeSheet)),
          )!;
          await tester.tap(find.byKey(const Key('market-trade-sheet-cancel')));
          await tester.pumpAndSettle();
          final cancel = find.byKey(const Key('market-trade-action-cancel'));
          final route = ModalRoute.of(tester.element(cancel))!;
          await tester.tap(find.byKey(const Key('market-trade-action-submit')));
          await tester.pump();
          expect(port.writes, 1);
          write.completeError(TimeoutException('fixture lost receipt'));
          await tester.pumpAndSettle();
          expect(controller.trades.writeUncertain, isTrue);
          port.tradeReadGate = read;
          Focus.of(tester.element(find.text('刷新交易单'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(controller.trades.loading, isTrue);
          expect(route.isCurrent, isTrue);
          read.complete({
            'rows': [port.row],
            'total': 1,
          });
          await tester.pump();
          await tester.pump();
          expect(controller.trades.writeUncertain, isFalse);
          expect(controller.trades.detail?['transactionNumber'], 'T1');
          expect(controller.mainTab, 0);
          expect(port.writes, 1);
          expect(port.commands.single.$1, 'cancel');
          expect(
            route.animation!.value,
            0,
            reason: 'Keyboard action inspection must retire within two readback frames.',
          );
          expect(cancel, findsNothing);
          expect(sheetRoute.isCurrent, isTrue);
          await tester.pumpAndSettle();
          Navigator.of(tester.element(find.byType(TradeSheet))).pop();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          if (!write.isCompleted) {
            write.complete({'transactionNumber': 'T1', 'confirmed': true});
          }
          if (!read.isCompleted) {
            read.complete({
              'rows': [port.row],
              'total': 1,
            });
          }
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      },
    );
    testWidgets(
      '${suite.name}: keyboard accepted action keeps its source through the awaited receipt',
      (tester) async {
        size(tester, const Size(1280, 900));
        final gate = Completer<MarketRow>();
        final port = InnerTradePort()..writeGate = gate;
        final controller = MarketplaceController(port);
        try {
          await controller.trades.refresh();
          await tester.pumpWidget(
            scopedApp(MarketplaceTradesPage(controller), suite),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(TradeRow));
          await tester.pumpAndSettle();
          final sheetRoute = ModalRoute.of(
            tester.element(find.byType(TradeSheet)),
          )!;
          final entryLabel = find.descendant(
            of: find.byType(TradeSheet),
            matching: find.text('取消交易'),
          );
          Focus.of(tester.element(entryLabel)).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          final submit = find.byKey(const Key('market-trade-action-submit'));
          final route = ModalRoute.of(tester.element(submit))!;
          final submitLabel = find.descendant(
            of: submit,
            matching: find.text('取消交易'),
          );
          Focus.of(tester.element(submitLabel)).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(controller.trades.pending, isTrue);
          expect(port.commands.single.$1, 'cancel');
          expect(port.commands.single.$2, {
            'transactionNumber': 'T1',
            'rating': 5,
            'reportType': null,
            'content': '',
          });
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.tapAt(const Offset(10, 10));
          await tester.pump();
          expect(route.isCurrent, isTrue);
          expect(port.writes, 1);
          gate.complete({'transactionNumber': 'T1', 'confirmed': true});
          await tester.pump();
          await tester.pump();
          expect(controller.trades.pending, isFalse);
          expect(
            route.animation!.value,
            0,
            reason: 'Keyboard accepted action must retire within two receipt frames.',
          );
          expect(
            find.byKey(const Key('market-trade-action-cancel')),
            findsNothing,
          );
          expect(sheetRoute.isCurrent, isTrue);
          expect(find.byKey(const Key('market-success-view')), findsOneWidget);
          expect(toastAnimation(tester).value, 1);
          expect(port.writes, 1);
          await tester.pumpAndSettle();
          Navigator.of(tester.element(find.byType(TradeSheet))).pop();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          if (!gate.isCompleted) {
            gate.complete({'transactionNumber': 'T1', 'confirmed': true});
          }
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      },
    );
    testWidgets(
      '${suite.name}: keyboard action cancel retires the nested route within two frames',
      (tester) async {
        size(tester, const Size(1280, 900));
        final port = TradesPort();
        final controller = MarketplaceController(port);
        try {
          await controller.trades.refresh();
          await tester.pumpWidget(
            scopedApp(MarketplaceTradesPage(controller), suite),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(TradeRow));
          await tester.pumpAndSettle();
          final sheetRoute = ModalRoute.of(
            tester.element(find.byType(TradeSheet)),
          )!;
          final entryLabel = find.descendant(
            of: find.byType(TradeSheet),
            matching: find.text('取消交易'),
          );
          Focus.of(tester.element(entryLabel)).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          final cancel = find.byKey(const Key('market-trade-action-cancel'));
          final route = ModalRoute.of(tester.element(cancel))!;
          expect(route.animation!.value, 1);
          final cancelLabel = find.descendant(
            of: cancel,
            matching: find.text('取消'),
          );
          Focus.of(tester.element(cancelLabel)).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          expect(
            route.animation!.value,
            0,
            reason: 'Keyboard action cancellation must retire its route within two frames.',
          );
          expect(cancel, findsNothing);
          expect(sheetRoute.isCurrent, isTrue);
          expect(Focus.of(tester.element(entryLabel)).hasFocus, isTrue);
          expect(port.writes, 0);
          Navigator.of(tester.element(find.byType(TradeSheet))).pop();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      },
    );
    testWidgets(
      '${suite.name}: keyboard trade-sheet cancel entry opens at the final route frame',
      (tester) async {
        size(tester, const Size(1280, 900));
        final port = TradesPort();
        final controller = MarketplaceController(port);
        try {
          await controller.trades.refresh();
          await tester.pumpWidget(
            scopedApp(MarketplaceTradesPage(controller), suite),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(TradeRow));
          await tester.pumpAndSettle();
          final sheetRoute = ModalRoute.of(
            tester.element(find.byType(TradeSheet)),
          )!;
          final label = find.descendant(
            of: find.byType(TradeSheet),
            matching: find.text('取消交易'),
          );
          Focus.of(tester.element(label)).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          final cancel = find.byKey(const Key('market-trade-action-cancel'));
          final actionRoute = ModalRoute.of(tester.element(cancel))!;
          expect(actionRoute, isA<StarBridgeDialogRoute>());
          expect(
            actionRoute.animation!.value,
            1,
            reason: 'Keyboard trade-sheet action entry must be complete within two frames.',
          );
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(sheetRoute.isCurrent, isTrue);
          expect(Focus.of(tester.element(label)).hasFocus, isTrue);
          expect(port.writes, 0);
          Navigator.of(tester.element(find.byType(TradeSheet))).pop();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      },
    );
    testWidgets(
      '${suite.name}: real trades row and sheet cancellation opens the selected action route',
      (tester) async {
        size(tester, const Size(1280, 900));
        final port = TradesPort();
        final controller = MarketplaceController(port);
        try {
          await controller.trades.refresh();
          await tester.pumpWidget(
            scopedApp(MarketplaceTradesPage(controller), suite),
          );
          await tester.pumpAndSettle();
          expect(find.byType(TradeRow), findsOneWidget);
          await tester.tap(find.byType(TradeRow));
          await tester.pumpAndSettle();
          expect(find.byType(TradeSheet), findsOneWidget);
          final sheetRoute = ModalRoute.of(
            tester.element(find.byType(TradeSheet)),
          )!;
          final entry = find.byKey(const Key('market-trade-sheet-cancel'));
          expect(entry, findsOneWidget);
          final entryLabel = find.descendant(
            of: entry,
            matching: find.text('取消交易'),
          );
          expect(
            tester.getRect(entry),
            const Rect.fromLTRB(880, 832, 948, 880),
          );
          expect(
            tester.getRect(entryLabel),
            const Rect.fromLTRB(890, 850, 938, 862),
          );
          await tester.tap(entry);
          await tester.pump();
          final cancel = find.byKey(const Key('market-trade-action-cancel'));
          expect(cancel, findsOneWidget);
          final actionRoute = ModalRoute.of(tester.element(cancel))!;
          expect(
            actionRoute,
            isA<StarBridgeDialogRoute>(),
            reason:
                'Real trade-sheet action must use the selected dialog route.',
          );
          expect(actionRoute.barrierDismissible, isFalse);
          expect(actionRoute.animation!.value, lessThan(1));
          await tester.pump(const Duration(milliseconds: 16));
          expect(actionRoute.animation!.value, inExclusiveRange(0, 1));
          await tester.pumpAndSettle();
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('market-trade-action-cancel')),
            findsNothing,
          );
          expect(sheetRoute.isCurrent, isTrue);
          expect(find.byType(TradeSheet), findsOneWidget);
          expect(port.writes, 0);
          Navigator.of(tester.element(find.byType(TradeSheet))).pop();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      },
    );
  }
}
