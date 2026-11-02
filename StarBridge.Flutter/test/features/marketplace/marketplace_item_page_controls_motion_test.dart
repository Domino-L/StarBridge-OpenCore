// Slice20: the item page's own controls — offer rows, back, refresh and the
// "also sell / also buy" buttons. Native geometry measured before the change
// is pinned for the standard suite; every suite keeps one reader action per
// control, pointer and keyboard activation and the existing availability.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_item_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_publish.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'marketplace_bridge_trade_test.dart' show Online;
import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_trade_routes_motion_test.dart' show seed;
import 'marketplace_trade_inner_motion_test.dart' show namedButton, activate;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

final _row = find.byKey(
  const ValueKey<(String, Object)>(('market-offer-row', 'O1')),
);
final _back = find.byKey(const Key('marketplace-back'));
final _refresh = find.byKey(const Key('market-item-refresh'));
Finder _also(String side) => find.byKey(Key('item-also-$side'));

/// A listing-capable Bridge port whose Host never answers, so the item page
/// shows the publish shortcuts while reads stay pending.
Future<MarketplaceController> _bridgeController(WidgetTester tester) async {
  final pair = InMemoryBridgeConnection.createPair();
  final session = BridgeClientSession(
    connection: pair.client,
    sessionGeneration: 1,
  );
  session.acceptHostCapabilities(['marketplace.read', 'marketplace.listings']);
  final sub = pair.host.incoming.listen((_) {});
  final mode = Online();
  final c = MarketplaceController(BridgeMarketplacePort(session, mode));
  addTearDown(() async {
    mode.dispose();
    await tester.runAsync(() async {
      await sub.cancel();
      await session.close().timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
      await pair.host.close().timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
    });
  });
  return c;
}

bool _focusedWithin(Finder target) {
  final focus = FocusManager.instance.primaryFocus?.context;
  if (focus == null) return false;
  bool inside(Element e) {
    var hit = false;
    e.visitAncestorElements((a) => !(hit = target.evaluate().contains(a)));
    return hit || target.evaluate().contains(e);
  }

  return inside(focus as Element) ||
      find
          .descendant(
            of: target,
            matching: find.byElementPredicate((e) => e == focus),
          )
          .evaluate()
          .isNotEmpty;
}

Future<void> _tabTo(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 40 && !_focusedWithin(target); i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  expect(_focusedWithin(target), isTrue, reason: 'Tab reaches the control');
}

void main() {
  for (final (width, rowRect, refreshRect, sell, buy) in [
    (
      1280.0,
      const Rect.fromLTRB(301, 292, 1279, 349),
      const Rect.fromLTRB(1227, 69, 1267, 109),
      const Rect.fromLTRB(83.2, 383, 161.6, 415),
      const Rect.fromLTRB(167.6, 383, 246, 415),
    ),
    (
      800.0,
      const Rect.fromLTRB(1, 428, 799, 485),
      const Rect.fromLTRB(747, 205, 787, 245),
      const Rect.fromLTRB(249.2, 146, 327.6, 178),
      const Rect.fromLTRB(333.6, 146, 412, 178),
    ),
  ]) {
    testWidgets('standard suite keeps the measured native geometry at $width', (
      tester,
    ) async {
      size(tester, Size(width, 900));
      final c = await _bridgeController(tester);
      seed(c);
      try {
        await tester.pumpWidget(
          scopedApp(MarketplaceItemPage(c), InteractionSuite.standard),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.getRect(_row), rowRect);
        expect(tester.getRect(_back), const Rect.fromLTRB(0, 0, 104, 48));
        expect(
          tester.getRect(
            find.descendant(of: _back, matching: find.byType(Text)),
          ),
          const Rect.fromLTRB(10, 18, 94, 30),
        );
        expect(tester.getRect(_refresh), refreshRect);
        expect(
          tester.getSize(
            find.descendant(of: _refresh, matching: find.byType(Icon)),
          ),
          const Size(16, 16),
        );
        expect(
          tester.getRect(_also('sell')),
          within(distance: .001, from: sell),
        );
        expect(tester.getRect(_also('buy')), within(distance: .001, from: buy));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        await tester.pump(const Duration(minutes: 2));
      }
    });
  }

  for (final suite in InteractionSuite.values) {
    testWidgets(
      '${suite.name}: offer row opens the order by pointer, key and reader',
      (tester) async {
        size(tester, const Size(1280, 900));
        final semantics = tester.ensureSemantics();
        final c = MarketplaceController(TradesPort());
        seed(c);
        try {
          await tester.pumpWidget(scopedApp(MarketplaceItemPage(c), suite));
          await tester.pumpAndSettle();
          final b = tester.getRect(_row);
          await tester.tapAt(Offset(b.left + 120, b.center.dy));
          await tester.pumpAndSettle();
          expect(find.text('订单详情'), findsOneWidget);
          await tester.tap(find.byKey(const Key('market-order-close')));
          await tester.pumpAndSettle();
          expect(find.text('订单详情'), findsNothing);
          await _tabTo(tester, _row);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(find.text('订单详情'), findsOneWidget);
          activate(tester, namedButton(tester, '关闭'));
          await tester.pumpAndSettle();
          expect(find.text('订单详情'), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          semantics.dispose();
        }
      },
    );

    testWidgets('${suite.name}: back and refresh keep one reader action each', (
      tester,
    ) async {
      size(tester, const Size(1280, 900));
      final semantics = tester.ensureSemantics();
      final port = TradesPort();
      final c = MarketplaceController(port);
      seed(c);
      try {
        await tester.pumpWidget(scopedApp(MarketplaceItemPage(c), suite));
        await tester.pumpAndSettle();
        final before = c.blocks['sell']!.readAt;
        activate(tester, namedButton(tester, '刷新'));
        await tester.pumpAndSettle();
        expect(c.blocks['sell']!.readAt, isNot(before));
        expect(c.itemId, 1);
        activate(tester, namedButton(tester, '← 返回 大厅'));
        await tester.pumpAndSettle();
        expect(c.itemId, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });

    testWidgets(
      '${suite.name}: also-buy opens the publish wizard on that side',
      (tester) async {
        size(tester, const Size(1280, 900));
        final c = await _bridgeController(tester);
        seed(c);
        try {
          await tester.pumpWidget(scopedApp(MarketplaceItemPage(c), suite));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          await tester.tap(_also('buy'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          final dialog = tester.widget<ListingPublishDialog>(
            find.byType(ListingPublishDialog),
          );
          expect(dialog.initialStep, 2);
          expect(dialog.draft.side, 'buy');
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          await tester.pump(const Duration(minutes: 2));
        }
      },
    );
  }
}
