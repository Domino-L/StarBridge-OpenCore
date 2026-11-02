// Slice16: trades-page history/role segments, list retry, todo "all trades"
// and the todo card with its inner action. Native geometry measured before
// the adaptation is pinned for the standard suite; every suite keeps a single
// reader action per control, pointer and keyboard activation, and the
// original owners (setState selection, refresh, tab, openTradeSheet).
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_page.dart'
    show MarketplaceTradesPage, TradeSheet, TradeTodo, TradeTodoCard;

import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_trade_inner_motion_test.dart' show namedButton, activate;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

Future<void> _failRead(MarketplaceController c, TradesPort port) async {
  final gate = Completer<MarketRow>();
  port.tradeReadGate = gate;
  final reading = c.trades.refresh();
  gate.completeError(const MarketplaceTradeError('marketplace.unavailable'));
  await reading;
  port.tradeReadGate = null;
}

/// Tabs (as a keyboard user would) until focus is on [target] itself, not
/// on a focusable descendant such as an inner button.
Future<void> _tabTo(WidgetTester tester, Finder target) async {
  final key = tester.widget(target).key;
  for (var i = 0; i < 12; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) continue;
    var hops = 0, onTarget = false;
    (focused as Element).visitAncestorElements((e) {
      if (e.widget.key == key) {
        onTarget = true;
        return false;
      }
      if (e.widget is ButtonStyleButton) return false;
      return ++hops < 40;
    });
    if (onTarget) return;
  }
  fail('Tab never reached $target');
}

void main() {
  testWidgets('standard suite keeps the measured native geometry', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    final port = TradesPort();
    final c = MarketplaceController(port);
    try {
      await c.trades.refresh();
      await tester.pumpWidget(
        scopedApp(MarketplaceTradesPage(c), InteractionSuite.standard),
      );
      await tester.pumpAndSettle();
      Rect segment(String label) => tester.getRect(
        find
            .ancestor(
              of: find.textContaining(label).first,
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            )
            .first,
      );
      // Hall-style sub tabs (2026-10-20 unification): native text buttons,
      // 32 high, separated by slanted dividers; since layout A (2026-10-23)
      // they follow the section title "交易" on one row.
      expect(segment('进行中'), const Rect.fromLTRB(48.5, 0, 134.5, 32));
      expect(
        segment('已结束'),
        within(distance: .05, from: const Rect.fromLTRB(142.73, 0, 205.73, 32)),
      );
      expect(segment('全部').width, closeTo(50, .05));
      expect(segment('我买的').width, closeTo(63, .05));
      expect(
        segment('我卖的'),
        within(distance: .05, from: const Rect.fromLTRB(349.2, 0, 412.2, 32)),
      );
      await _failRead(c, port);
      await tester.pumpAndSettle();
      final retry = find.byKey(const Key('market-trades-retry'));
      expect(tester.getSize(retry), const Size(1232, 48));
      await c.trades.refresh();
      await tester.pumpWidget(
        scopedApp(Material(child: TradeTodo(c)), InteractionSuite.standard),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('market-trade-todo-all'))),
        const Size(92, 48),
      );
      expect(tester.getSize(find.byType(TradeTodoCard)), const Size(1280, 86));
      final inner = find.byKey(
        const ValueKey<(String, Object?)>(('market-trade-todo-action', 'T1')),
      );
      // The native OutlinedButton inside the feedback wrapper, as measured
      // before the adaptation (56.3×22; the probe printed 1-decimal edges).
      final native = find.descendant(
        of: inner,
        matching: find.byType(OutlinedButton),
      );
      expect(tester.getSize(native).width, closeTo(56.3, .01));
      expect(tester.getSize(native).height, 22);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    }
  });

  for (final suite in InteractionSuite.values) {
    testWidgets(
      '${suite.name}: segments switch by pointer, keyboard and reader, one action each',
      (tester) async {
        size(tester, const Size(1280, 900));
        final semantics = tester.ensureSemantics();
        final port = TradesPort();
        final c = MarketplaceController(port);
        try {
          await c.trades.refresh();
          await tester.pumpWidget(scopedApp(MarketplaceTradesPage(c), suite));
          await tester.pumpAndSettle();
          bool selected(String label) =>
              namedButton(
                tester,
                label,
              ).getSemanticsData().flagsCollection.isSelected ==
              ui.Tristate.isTrue;
          expect(selected('已结束'), isFalse);
          await tester.tap(find.text('已结束'));
          await tester.pumpAndSettle();
          expect(selected('已结束'), isTrue);
          activate(tester, namedButton(tester, '我卖的'));
          await tester.pumpAndSettle();
          expect(selected('我卖的'), isTrue);
          Focus.of(tester.element(find.text('我买的'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(selected('我买的'), isTrue);
          expect(selected('我卖的'), isFalse);
          expect(port.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          semantics.dispose();
        }
      },
    );

    testWidgets('${suite.name}: list retry refreshes once per activation', (
      tester,
    ) async {
      size(tester, const Size(1280, 900));
      final semantics = tester.ensureSemantics();
      final port = TradesPort();
      final c = MarketplaceController(port);
      try {
        await c.trades.refresh();
        await tester.pumpWidget(scopedApp(MarketplaceTradesPage(c), suite));
        await tester.pumpAndSettle();
        await _failRead(c, port);
        await tester.pumpAndSettle();
        final before = port.reads;
        activate(tester, namedButton(tester, '加载失败 · 重试'));
        await tester.pumpAndSettle();
        expect(port.reads, before + 1);
        expect(c.trades.error, isNull);
        expect(find.byKey(const Key('market-trades-retry')), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });

    testWidgets(
      '${suite.name}: todo card and its action open the details; all trades switches tab',
      (tester) async {
        size(tester, const Size(1280, 900));
        final semantics = tester.ensureSemantics();
        final port = TradesPort();
        final c = MarketplaceController(port);
        try {
          await c.trades.refresh();
          await tester.pumpWidget(
            scopedApp(Material(child: TradeTodo(c)), suite),
          );
          await tester.pumpAndSettle();
          // Keyboard on the card: the details are complete within two frames.
          final card = find.byKey(
            const ValueKey<(String, Object?)>(('market-trade-todo', 'T1')),
          );
          await _tabTo(tester, card);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          final route = ModalRoute.of(tester.element(find.byType(TradeSheet)))!;
          expect(route.animation!.value, 1);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(TradeSheet), findsNothing);
          // Pointer on the inner action opens the same details once.
          await tester.tap(
            find.byKey(
              const ValueKey<(String, Object?)>((
                'market-trade-todo-action',
                'T1',
              )),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(TradeSheet), findsOneWidget);
          Navigator.of(tester.element(find.byType(TradeSheet))).pop();
          await tester.pumpAndSettle();
          // Reader on "all trades".
          activate(tester, namedButton(tester, '全部交易 →'));
          await tester.pumpAndSettle();
          expect(c.mainTab, 3);
          expect(port.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          semantics.dispose();
        }
      },
    );
  }
}
