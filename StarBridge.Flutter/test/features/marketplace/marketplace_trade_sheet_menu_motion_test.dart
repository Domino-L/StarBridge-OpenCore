import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart'
    show SuiteSurfaceTransition, SurfaceKind;
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_native_icon_action.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_page.dart'
    show MarketplaceTradesPage, TradeRow, TradeSheet;

import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_trade_inner_motion_test.dart'
    show InnerTradePort, namedButton, activate;
import '../../design_system/interaction/interaction_batch3b_test.dart'
    show exposedNodes;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '${suite.name}: original block owner waits rejects and retries without menu command duplication',
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
          final more = find.byKey(
            const Key('market-trade-sheet-more'),
            skipOffstage: false,
          );
          await tester.tap(more);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('market-trade-sheet-block')));
          await tester.pumpAndSettle();
          final cancel = find.byKey(const Key('market-trade-action-cancel'));
          final route = ModalRoute.of(tester.element(cancel))!;
          final submit = find.byKey(const Key('market-trade-action-submit'));
          final submitLabel = find.descendant(
            of: submit,
            matching: find.byType(Text),
          );
          Focus.of(tester.element(submitLabel)).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          expect(controller.trades.pending, isTrue);
          expect(port.commands, hasLength(1));
          expect(port.commands.single.$1, 'block');
          expect(port.commands.single.$2, {
            'transactionNumber': 'T1',
            'rating': 5,
            'reportType': null,
            'content': '',
          });
          expect(
            tester.widget<StarBridgeNativeIconAction>(more).onActivate,
            isNull,
          );
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
          expect(
            controller.trades.writeErrorCode,
            'marketplace.trade_rejected',
          );
          expect(controller.trades.writeUncertain, isFalse);
          expect(route.isCurrent, isTrue);
          expect(
            find.descendant(of: submit, matching: find.text('重试')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('market-success-view')), findsNothing);
          final second = Completer<MarketRow>();
          port.writeGate = second;
          await tester.tap(submit);
          await tester.pump();
          expect(controller.trades.pending, isTrue);
          expect(port.writes, 2);
          second.complete({'transactionNumber': 'T1', 'confirmed': true});
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(route.animation!.value, inExclusiveRange(0, 1));
          await tester.pumpAndSettle();
          expect(cancel, findsNothing);
          expect(sheetRoute.isCurrent, isTrue);
          expect(
            tester.widget<StarBridgeNativeIconAction>(more).onActivate,
            isNotNull,
          );
          expect(port.commands.last.$1, port.commands.first.$1);
          expect(port.commands.last.$2, port.commands.first.$2);
          expect(port.writes, 2);
          expect(find.byKey(const Key('market-success-view')), findsOneWidget);
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
      '${suite.name}: reader menu commands expose one action and retire the old menu semantics',
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
          activate(tester, namedButton(tester, '更多'));
          await tester.pump();
          await tester.pump();
          final surface = find.byWidgetPredicate(
            (w) => w is SuiteSurfaceTransition && w.kind == SurfaceKind.menu,
          );
          expect(
            tester.widget<SuiteSurfaceTransition>(surface).animation.value,
            1,
          );
          activate(tester, namedButton(tester, '拉黑'));
          await tester.pump();
          await tester.pump();
          final cancel = find.byKey(const Key('market-trade-action-cancel'));
          final route = ModalRoute.of(tester.element(cancel))!;
          expect(route.animation!.value, 1);
          expect(
            exposedNodes(tester)
                .where((n) => n.getSemanticsData().label == '拉黑'),
            isEmpty,
          );
          activate(tester, namedButton(tester, '取消'));
          await tester.pump();
          await tester.pump();
          expect(route.animation!.value, 0);
          expect(cancel, findsNothing);
          namedButton(tester, '更多');
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
      '${suite.name}: live reduction settles the real menu and leaving retires its overlay',
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
          final sheetContext = tester.element(find.byType(TradeSheet));
          final sheetRoute = ModalRoute.of(sheetContext)!;
          final more = find.byKey(const Key('market-trade-sheet-more'));
          final surface = find.byWidgetPredicate(
            (w) => w is SuiteSurfaceTransition && w.kind == SurfaceKind.menu,
          );
          await tester.tap(more);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            tester.widget<SuiteSurfaceTransition>(surface).animation.value,
            inExclusiveRange(0, 1),
          );
          reduce.value = true;
          await tester.pump();
          await tester.pump();
          expect(
            tester.widget<SuiteSurfaceTransition>(surface).animation.value,
            1,
            reason:
                'The already-open real trade menu must follow reduced motion.',
          );
          reduce.value = false;
          await tester.pump();
          await tester.pump();
          expect(
            tester.widget<SuiteSurfaceTransition>(surface).animation.value,
            1,
          );
          await tester.tapAt(const Offset(900, 700));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            tester.widget<SuiteSurfaceTransition>(surface).animation.value,
            inExclusiveRange(0, 1),
          );
          reduce.value = true;
          await tester.pump();
          await tester.pump();
          expect(surface, findsNothing);
          expect(sheetRoute.isCurrent, isTrue);
          reduce.value = false;
          await tester.pump();
          await tester.pump();
          await tester.tap(more);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(surface, findsOneWidget);
          Navigator.of(sheetContext).pop();
          await tester.pumpAndSettle();
          expect(surface, findsNothing);
          expect(
            find.byKey(const Key('market-trade-sheet-block')),
            findsNothing,
          );
          expect(port.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          reduce.dispose();
        }
      },
    );
    testWidgets(
      '${suite.name}: outside menu dismissal does not pass through to the parent sheet barrier',
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
          final more = find.byKey(const Key('market-trade-sheet-more'));
          final usesNativeMenu = more.evaluate().isEmpty;
          await tester.tap(
            usesNativeMenu ? find.byType(PopupMenuButton<String>) : more,
          );
          await tester.pumpAndSettle();
          final block = usesNativeMenu
              ? find.byType(PopupMenuItem<String>)
              : find.byKey(const Key('market-trade-sheet-block'));
          expect(block, findsOneWidget);
          await tester.tapAt(const Offset(100, 700));
          await tester.pumpAndSettle();
          expect(block, findsNothing);
          expect(
            find.byType(TradeSheet),
            findsOneWidget,
            reason: 'Dismissing the menu must not activate the underlying trade-sheet barrier.',
          );
          expect(sheetRoute.isCurrent, isTrue);
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
      '${suite.name}: keyboard menu entrance exit and block return restore the actual anchor',
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
          final more = find.byKey(const Key('market-trade-sheet-more'));
          final icon = find.descendant(of: more, matching: find.byType(Icon));
          final surface = find.byWidgetPredicate(
            (w) => w is SuiteSurfaceTransition && w.kind == SurfaceKind.menu,
          );
          final block = find.byKey(const Key('market-trade-sheet-block'));
          Focus.of(tester.element(icon)).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          expect(surface, findsOneWidget);
          expect(
            tester.widget<SuiteSurfaceTransition>(surface).animation.value,
            1,
          );
          expect(Focus.of(tester.element(find.text('拉黑'))).hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          await tester.pump();
          expect(block, findsNothing);
          expect(surface, findsNothing);
          expect(Focus.of(tester.element(icon)).hasFocus, isTrue);
          expect(port.writes, 0);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          expect(block, findsOneWidget);
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
          expect(cancel, findsNothing);
          expect(route.animation!.value, 0);
          expect(
            Focus.of(tester.element(icon)).hasFocus,
            isTrue,
            reason: 'Keyboard block confirmation must return focus to its still-mounted more anchor.',
          );
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
      '${suite.name}: real more menu keyboard command retains the block confirmation',
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
          final more = find.byKey(const Key('market-trade-sheet-more'));
          expect(
            tester.getRect(more),
            const Rect.fromLTRB(1197, 415, 1245, 463),
          );
          await tester.tap(more);
          await tester.pumpAndSettle();
          final label = find.text('拉黑');
          expect(label, findsOneWidget);
          final item = find.byKey(const Key('market-trade-sheet-block'));
          expect(tester.getSize(item), const Size(112, 48));
          expect(tester.getSize(label).width, closeTo(24.2, .001));
          expect(tester.getSize(label).height, 17);
          Focus.of(tester.element(label)).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          final cancel = find.byKey(const Key('market-trade-action-cancel'));
          expect(cancel, findsOneWidget);
          final route = ModalRoute.of(tester.element(cancel))!;
          expect(route, isA<StarBridgeDialogRoute>());
          expect(
            route.animation!.value,
            1,
            reason: 'Keyboard menu command must open the action at its final route frame.',
          );
          expect(find.text('拉黑对方'), findsNWidgets(2));
          expect(port.writes, 0);
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(sheetRoute.isCurrent, isTrue);
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
