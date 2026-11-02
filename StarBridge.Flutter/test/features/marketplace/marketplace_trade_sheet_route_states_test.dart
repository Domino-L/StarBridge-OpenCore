// Slice15 remaining states for the real trade-details route: reader close,
// live reduced motion (entering and leaving), live theme, pending-disabled
// close, a late detail read after closing, exit and reopen, narrow window.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_page.dart'
    show MarketplaceTradesPage, TradeRow, TradeSheet;

import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_trade_inner_motion_test.dart' show namedButton, activate;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

class _DetailPort extends TradesPort {
  int detailReads = 0;
  @override
  Future<MarketRow> trade(String operation, [MarketRow input = const {}]) {
    if (operation == 'detail') detailReads++;
    return super.trade(operation, input);
  }
}

final _close = find.byKey(const Key('market-trade-sheet-close'));

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '${suite.name}: reader close is one action and exits within two frames',
      (tester) async {
        size(tester, const Size(1280, 900));
        final semantics = tester.ensureSemantics();
        final port = _DetailPort();
        final controller = MarketplaceController(port);
        try {
          await controller.trades.refresh();
          await tester.pumpWidget(
            scopedApp(MarketplaceTradesPage(controller), suite),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(TradeRow));
          await tester.pumpAndSettle();
          final route = ModalRoute.of(tester.element(find.byType(TradeSheet)))!;
          activate(tester, namedButton(tester, '关闭'));
          await tester.pump();
          await tester.pump();
          expect(
            route.animation!.value,
            0,
            reason: 'Reader activation takes the static path.',
          );
          expect(find.byType(TradeSheet), findsNothing);
          expect(port.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          semantics.dispose();
        }
      },
    );

    testWidgets(
      '${suite.name}: live reduced motion settles the details route entering and leaving',
      (tester) async {
        size(tester, const Size(1280, 900));
        final reduce = ValueNotifier(false);
        final port = _DetailPort();
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
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          final route = ModalRoute.of(tester.element(find.byType(TradeSheet)))!;
          expect(
            route.animation!.value,
            lessThan(1),
            reason: 'Pointer opening keeps its entrance.',
          );
          reduce.value = true;
          await tester.pump();
          await tester.pump();
          expect(
            route.animation!.value,
            1,
            reason: 'An entering details route follows reduced motion.',
          );
          reduce.value = false;
          await tester.pump();
          await tester.pump();
          await tester.tap(_close);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            route.animation!.value,
            inExclusiveRange(0, 1),
            reason: 'Pointer close keeps its exit.',
          );
          reduce.value = true;
          await tester.pump();
          await tester.pump();
          expect(
            find.byType(TradeSheet),
            findsNothing,
            reason: 'A leaving details route follows reduced motion.',
          );
          expect(port.detailReads, 1);
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
      '${suite.name}: live theme reaches the open details within two frames',
      (tester) async {
        size(tester, const Size(1280, 900));
        final light = ValueNotifier(false);
        final port = _DetailPort();
        final controller = MarketplaceController(port);
        try {
          await controller.trades.refresh();
          await tester.pumpWidget(
            ValueListenableBuilder<bool>(
              valueListenable: light,
              builder: (context, value, _) => scopedApp(
                MarketplaceTradesPage(controller),
                suite,
                light: value,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(TradeRow));
          await tester.pumpAndSettle();
          Brightness sheetBrightness() =>
              Theme.of(tester.element(find.byType(TradeSheet))).brightness;
          final before = sheetBrightness();
          light.value = true;
          await tester.pump();
          await tester.pump();
          expect(sheetBrightness(), isNot(before));
          expect(find.byType(TradeSheet), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          light.dispose();
        }
      },
    );

    testWidgets(
      '${suite.name}: close is disabled while a write is pending and returns after',
      (tester) async {
        size(tester, const Size(1280, 900));
        final gate = Completer<MarketRow>();
        final port = _DetailPort()..writeGate = gate;
        final controller = MarketplaceController(port);
        try {
          await controller.trades.refresh();
          await tester.pumpWidget(
            scopedApp(MarketplaceTradesPage(controller), suite),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(TradeRow));
          await tester.pumpAndSettle();
          final route = ModalRoute.of(tester.element(find.byType(TradeSheet)))!;
          unawaited(
            controller.trades.submit('ship', {'transactionNumber': 'T1'}),
          );
          await tester.pump();
          expect(controller.trades.pending, isTrue);
          expect(tester.widget<IconButton>(_close).onPressed, isNull);
          await tester.tap(_close, warnIfMissed: false);
          await tester.pump();
          await tester.pump();
          expect(
            route.isCurrent,
            isTrue,
            reason: 'Pending write keeps the details open.',
          );
          gate.complete({'transactionNumber': 'T1', 'confirmed': true});
          await tester.pumpAndSettle();
          expect(controller.trades.pending, isFalse);
          expect(tester.widget<IconButton>(_close).onPressed, isNotNull);
          expect(port.writes, 1);
          await tester.tap(_close);
          await tester.pumpAndSettle();
          expect(find.byType(TradeSheet), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      },
    );

    testWidgets(
      '${suite.name}: a late detail read after closing reopens nothing; reopening reads again',
      (tester) async {
        size(tester, const Size(1280, 900));
        final port = _DetailPort();
        final late = Completer<MarketRow>();
        port.details['T1'] = late;
        final controller = MarketplaceController(port);
        try {
          await controller.trades.refresh();
          await tester.pumpWidget(
            scopedApp(MarketplaceTradesPage(controller), suite),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(TradeRow));
          await tester.pumpAndSettle();
          expect(find.byType(TradeSheet), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(TradeSheet), findsNothing);
          late.complete({...port.row, 'deliveryStatus': 2});
          await tester.pumpAndSettle();
          expect(
            find.byType(TradeSheet),
            findsNothing,
            reason: 'A late read never reopens the details.',
          );
          port.details.remove('T1');
          await tester.tap(find.byType(TradeRow));
          await tester.pumpAndSettle();
          expect(find.byType(TradeSheet), findsOneWidget);
          expect(port.detailReads, 2, reason: 'Each opening reads once.');
          await tester.tap(_close);
          await tester.pumpAndSettle();
          expect(find.byType(TradeSheet), findsNothing);
          expect(port.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      },
    );
  }

  testWidgets(
    'narrow window: details take the full width under the 64 px top',
    (tester) async {
      size(tester, const Size(900, 700));
      final port = _DetailPort();
      final controller = MarketplaceController(port);
      try {
        await controller.trades.refresh();
        await tester.pumpWidget(
          scopedApp(MarketplaceTradesPage(controller), InteractionSuite.glow),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(TradeRow));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byType(TradeSheet)),
          const Rect.fromLTRB(0, 64, 900, 700),
        );
        expect(tester.getSize(_close), const Size(48, 48));
        await tester.tap(_close);
        await tester.pumpAndSettle();
        expect(find.byType(TradeSheet), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    },
  );
}
