import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/marketplace_icon.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_page.dart'
    show MarketplaceTradesPage, TradeRow, TradeSheet;

import 'marketplace_trades_test.dart' show TradesPort;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

class PanelTradePort extends TradesPort {
  final detailReads = <Object?>[];
  @override
  Future<MarketRow> trade(String operation, [MarketRow input = const {}]) {
    if (operation == 'detail') detailReads.add(input['transactionNumber']);
    return super.trade(operation, input);
  }
}

void main() {
  testWidgets('keyboard header close immediately returns to the original row', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    final port = PanelTradePort();
    final controller = MarketplaceController(port);
    try {
      await controller.trades.refresh();
      await tester.pumpWidget(
        scopedApp(MarketplaceTradesPage(controller), InteractionSuite.scan),
      );
      await tester.pumpAndSettle();
      final row = find.byType(TradeRow);
      final title = find.descendant(of: row, matching: find.text('科力晶'));
      Focus.of(tester.element(title)).requestFocus();
      await tester.pump();
      await tester.tap(title);
      await tester.pumpAndSettle();
      final sheet = find.byType(TradeSheet);
      final route = ModalRoute.of(tester.element(sheet))!;
      // Match the real original glyph, not an adapter-only key: the same
      // tracer must exercise the saved native-close baseline as well.
      final close = find.descendant(
        of: sheet,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is IconButton &&
              widget.icon is MarketplaceIcon &&
              (widget.icon as MarketplaceIcon).glyph == MarketplaceGlyph.close,
        ),
      );
      final closeIcon = find.descendant(
        of: close,
        matching: find.byType(MarketplaceIcon),
      );
      expect(close, findsOneWidget);
      expect(tester.getSize(close), const Size(48, 48));
      expect(tester.widget<MarketplaceIcon>(closeIcon).size, 18);
      Focus.of(tester.element(closeIcon)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      expect(
        route.animation!.value,
        0,
        reason: 'Keyboard header close must finish within two frames.',
      );
      expect(sheet, findsNothing);
      expect(Focus.of(tester.element(title)).hasFocus, isTrue);
      expect(port.detailReads, ['T1']);
      expect(port.writes, 0);
      expect(controller.trades.detail?['transactionNumber'], 'T1');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });
  testWidgets('keyboard inline trade-row button opens the same detail once', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    final port = PanelTradePort();
    final controller = MarketplaceController(port);
    try {
      await controller.trades.refresh();
      await tester.pumpWidget(
        scopedApp(MarketplaceTradesPage(controller), InteractionSuite.scan),
      );
      await tester.pumpAndSettle();
      final row = find.byType(TradeRow);
      final label = find.descendant(of: row, matching: find.text('去发货'));
      final button = find.byKey(
        const ValueKey<(String, Object?)>(('market-trade-row-action', 'T1')),
      );
      // Original inline button 56.3×22 and label 36.3×17, measured within
      // the 64 px row; the row's own top follows the page heading.
      final rowTop = tester.getRect(row).top;
      final buttonRect = tester.getRect(button);
      final labelRect = tester.getRect(label);
      expect(buttonRect.left, closeTo(1211.7, .001));
      expect(buttonRect.top - rowTop, 21);
      expect(buttonRect.right, 1268);
      expect(buttonRect.bottom - rowTop, 43);
      expect(labelRect.left, closeTo(1221.7, .001));
      expect(labelRect.top - rowTop, 23.5);
      expect(labelRect.right, 1258);
      expect(labelRect.bottom - rowTop, 40.5);
      Focus.of(tester.element(label)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      final sheet = find.byType(TradeSheet);
      final route = ModalRoute.of(tester.element(sheet))!;
      expect(route, isA<StarBridgeDialogRoute>());
      expect(
        route.animation!.value,
        1,
        reason:
            'Keyboard inline trade action must open details within two frames.',
      );
      expect(port.detailReads, ['T1']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();
      expect(route.animation!.value, 0);
      expect(sheet, findsNothing);
      expect(Focus.of(tester.element(label)).hasFocus, isTrue);
      expect(port.writes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });
  testWidgets(
    'keyboard activation of the original trade row opens details instantly',
    (tester) async {
      size(tester, const Size(1280, 900));
      final port = PanelTradePort();
      final controller = MarketplaceController(port);
      try {
        await controller.trades.refresh();
        await tester.pumpWidget(
          scopedApp(MarketplaceTradesPage(controller), InteractionSuite.scan),
        );
        await tester.pumpAndSettle();
        final row = find.byType(TradeRow);
        final title = find.descendant(of: row, matching: find.text('科力晶'));
        Focus.of(tester.element(title)).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump();
        final sheet = find.byType(TradeSheet);
        final route = ModalRoute.of(tester.element(sheet))!;
        expect(route, isA<StarBridgeDialogRoute>());
        expect(
          route.animation!.value,
          1,
          reason: 'Keyboard trade-row activation must open details within two frames.',
        );
        expect(port.detailReads, ['T1']);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump();
        expect(route.animation!.value, 0);
        expect(sheet, findsNothing);
        expect(Focus.of(tester.element(title)).hasFocus, isTrue);
        expect(port.writes, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    },
  );
  testWidgets('actual trades row opens the selected right-side detail route', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    final port = PanelTradePort();
    final controller = MarketplaceController(port);
    try {
      await controller.trades.refresh();
      await tester.pumpWidget(
        scopedApp(MarketplaceTradesPage(controller), InteractionSuite.scan),
      );
      await tester.pumpAndSettle();
      final row = find.byType(TradeRow);
      // Original full-width 64 px row; its top follows the page heading.
      final rowRect = tester.getRect(row);
      expect(rowRect.left, 0);
      expect(rowRect.right, 1280);
      expect(rowRect.height, 64);
      await tester.tap(row);
      await tester.pumpAndSettle();
      final sheet = find.byType(TradeSheet);
      expect(sheet, findsOneWidget);
      final route = ModalRoute.of(tester.element(sheet))!;
      expect(tester.getRect(sheet), const Rect.fromLTRB(860, 64, 1280, 900));
      expect(route.barrierDismissible, isTrue);
      expect(port.detailReads, ['T1']);
      expect(
        route,
        isA<StarBridgeDialogRoute>(),
        reason: 'Real trade details must use the selected client route.',
      );
      await tester.tapAt(const Offset(100, 700));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(port.writes, 0);
      expect(controller.trades.detail?['transactionNumber'], 'T1');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });
}
