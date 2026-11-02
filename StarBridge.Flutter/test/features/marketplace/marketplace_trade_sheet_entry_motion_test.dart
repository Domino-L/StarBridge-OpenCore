import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_page.dart'
    show MarketplaceTradesPage, TradeRow, TradeSheet;

import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_trade_inner_motion_test.dart'
    show InnerTradePort, namedButton, activate;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '${suite.name}: reader main and report entry keep single actionable nodes',
      (tester) async {
        size(tester, const Size(1280, 900));
        final semantics = tester.ensureSemantics();
        final port = TradesPort()..row['canReport'] = true;
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
          for (final label in ['发货', '举报']) {
            activate(tester, namedButton(tester, label));
            await tester.pump();
            await tester.pump();
            final cancel = find.byKey(const Key('market-trade-action-cancel'));
            final route = ModalRoute.of(tester.element(cancel))!;
            expect(route, isA<StarBridgeDialogRoute>());
            expect(route.animation!.value, 1);
            activate(tester, namedButton(tester, '取消'));
            await tester.pump();
            await tester.pump();
            expect(route.animation!.value, 0);
            expect(cancel, findsNothing);
            expect(sheetRoute.isCurrent, isTrue);
            namedButton(tester, label);
            expect(port.writes, 0);
          }
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
      '${suite.name}: pointer main and report retain feedback and native proportions',
      (tester) async {
        size(tester, const Size(1280, 900));
        final port = TradesPort()..row['canReport'] = true;
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
          for (final (suffix, label, rect, textRect) in [
            (
              'main',
              '发货',
              const Rect.fromLTRB(1172, 832, 1260, 880),
              const Rect.fromLTRB(1204, 850, 1228, 862),
            ),
            (
              'report',
              '举报',
              const Rect.fromLTRB(948, 832, 996, 880),
              const Rect.fromLTRB(960, 850, 984, 862),
            ),
          ]) {
            final entry = find.byKey(Key('market-trade-sheet-$suffix'));
            final entryLabel = find.descendant(
              of: entry,
              matching: find.text(label),
            );
            expect(tester.getRect(entry), rect);
            expect(tester.getRect(entryLabel), textRect);
            // The original presenter restores pre-open focus; a mouse click
            // does not promise to move focus onto its target first.
            Focus.of(tester.element(entryLabel)).requestFocus();
            await tester.pump();
            expect(Focus.of(tester.element(entryLabel)).hasFocus, isTrue);
            await tester.tap(entry);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 16));
            final cancel = find.byKey(const Key('market-trade-action-cancel'));
            final route = ModalRoute.of(tester.element(cancel))!;
            expect(route.animation!.value, inExclusiveRange(0, 1));
            await tester.pumpAndSettle();
            final cancelLabel = find.descendant(
              of: cancel,
              matching: find.text('取消'),
            );
            Focus.of(tester.element(cancelLabel)).requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pump();
            await tester.pump();
            expect(route.animation!.value, 0);
            expect(sheetRoute.isCurrent, isTrue);
            expect(Focus.of(tester.element(entryLabel)).hasFocus, isTrue);
            expect(port.writes, 0);
          }
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
      '${suite.name}: actual shipment rejection retains its gate and keyboard retry waits for receipt',
      (tester) async {
        size(tester, const Size(1280, 900));
        final first = Completer<MarketRow>();
        final port = InnerTradePort()..writeGate = first;
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
          final mainLabel = find.descendant(
            of: find.byKey(const Key('market-trade-sheet-main')),
            matching: find.text('发货'),
          );
          Focus.of(tester.element(mainLabel)).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          final cancel = find.byKey(const Key('market-trade-action-cancel'));
          final route = ModalRoute.of(tester.element(cancel))!;
          expect(route.animation!.value, 1);
          await tester.tap(find.byType(StarBridgeCheckboxTile));
          await tester.pumpAndSettle();
          final submit = find.byKey(const Key('market-trade-action-submit'));
          Future<void> keyboardSubmit() async {
            final label = find.descendant(
              of: submit,
              matching: find.byType(Text),
            );
            Focus.of(tester.element(label)).requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pump();
            await tester.pump();
          }

          await keyboardSubmit();
          expect(controller.trades.pending, isTrue);
          expect(port.commands, hasLength(1));
          expect(port.commands.single.$1, 'ship');
          expect(port.commands.single.$2, <String, Object?>{
            'transactionNumber': 'T1',
            'rating': 5,
            'reportType': null,
            'content': '',
          });
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          await tester.pump();
          expect(port.writes, 1);
          expect(route.isCurrent, isTrue);
          first.completeError(
            const MarketplaceTradeError('marketplace.trade_rejected'),
          );
          await tester.pumpAndSettle();
          expect(controller.trades.pending, isFalse);
          expect(controller.trades.writeUncertain, isFalse);
          expect(
            controller.trades.writeErrorCode,
            'marketplace.trade_rejected',
          );
          expect(route.isCurrent, isTrue);
          expect(
            tester
                .widget<StarBridgeCheckboxTile>(find.byType(StarBridgeCheckboxTile))
                .value,
            isTrue,
          );
          expect(
            find.descendant(of: submit, matching: find.text('重试')),
            findsOneWidget,
          );
          final second = Completer<MarketRow>();
          port.writeGate = second;
          await keyboardSubmit();
          expect(port.writes, 2);
          expect(controller.trades.pending, isTrue);
          second.complete({'transactionNumber': 'T1', 'confirmed': true});
          await tester.pump();
          await tester.pump();
          expect(route.animation!.value, 0);
          expect(cancel, findsNothing);
          expect(sheetRoute.isCurrent, isTrue);
          expect(controller.trades.pending, isFalse);
          expect(port.commands.last.$1, port.commands.first.$1);
          expect(port.commands.last.$2, port.commands.first.$2);
          expect(port.writes, 2);
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
      '${suite.name}: keyboard report entry preserves original invalid-submit feedback',
      (tester) async {
        size(tester, const Size(1280, 900));
        final port = TradesPort()..row['canReport'] = true;
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
            matching: find.text('举报'),
          );
          final entry = find.byKey(const Key('market-trade-sheet-report'));
          expect(
            tester.getRect(entry),
            const Rect.fromLTRB(948, 832, 996, 880),
          );
          expect(
            tester.getRect(label),
            const Rect.fromLTRB(960, 850, 984, 862),
          );
          Focus.of(tester.element(label)).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          final cancel = find.byKey(const Key('market-trade-action-cancel'));
          final route = ModalRoute.of(tester.element(cancel))!;
          expect(route, isA<StarBridgeDialogRoute>());
          expect(
            route.animation!.value,
            1,
            reason: 'Keyboard report entry must be complete within two frames.',
          );
          expect(find.text('举报交易'), findsOneWidget);
          await tester.tap(find.byKey(const Key('market-trade-action-submit')));
          await tester.pump();
          expect(find.text('请选择举报类型'), findsOneWidget);
          expect(find.text('请描述发生了什么'), findsOneWidget);
          expect(port.writes, 0);
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(sheetRoute.isCurrent, isTrue);
          expect(Focus.of(tester.element(label)).hasFocus, isTrue);
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
      '${suite.name}: keyboard main trade-sheet action keeps the original delivery gate',
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
            matching: find.text('发货'),
          );
          expect(label, findsOneWidget);
          final entry = find.byKey(const Key('market-trade-sheet-main'));
          expect(
            tester.getRect(entry),
            const Rect.fromLTRB(1172, 832, 1260, 880),
          );
          expect(
            tester.getRect(label),
            const Rect.fromLTRB(1204, 850, 1228, 862),
          );
          Focus.of(tester.element(label)).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          final cancel = find.byKey(const Key('market-trade-action-cancel'));
          final route = ModalRoute.of(tester.element(cancel))!;
          expect(route, isA<StarBridgeDialogRoute>());
          expect(
            route.animation!.value,
            1,
            reason: 'Keyboard main trade-sheet action must be complete within two frames.',
          );
          expect(find.text('请先勾选已交付'), findsOneWidget);
          expect(find.byType(StarBridgeCheckboxTile), findsOneWidget);
          expect(
            tester
                .widget<StarBridgeCheckboxTile>(find.byType(StarBridgeCheckboxTile))
                .value,
            isFalse,
          );
          await tester.tap(find.byKey(const Key('market-trade-action-submit')));
          await tester.pump();
          expect(port.writes, 0);
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(sheetRoute.isCurrent, isTrue);
          expect(Focus.of(tester.element(label)).hasFocus, isTrue);
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
