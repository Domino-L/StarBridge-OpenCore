// Slice27: the market browse page's controls — items/orders switch, layout
// toggles, overview retry, clear filters, the narrow filters drawer (open and
// close) and the order cards / order rows. Native geometry measured before the
// change is pinned for the standard suite; every suite keeps one reader action
// per control and pointer activation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_market_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_trade_routes_motion_test.dart' show offer;
import 'marketplace_trade_inner_motion_test.dart' show namedButton, activate;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

class _OrdersPort extends TradesPort {
  bool failOverview = false;
  @override
  Future<MarketRead> read(
    String operation, {
    int id = 0,
    String keyword = '',
    int category = 0,
    int side = 1,
    int page = 1,
    String language = 'CN',
    Map<String, String> options = const {},
  }) {
    if (operation == 'latest' && failOverview) {
      return Future.error(StateError('fixture'));
    }
    if (operation == 'marketOrders' || operation == 'latest') {
      return Future.value(
        MarketRead({
          'rows': [
            for (final n in ['O1', 'O2'])
              {
                ...offer,
                'orderNumber': n,
                'items': [
                  {'itemId': 1, 'itemName': 'Fixture item'},
                ],
              },
          ],
          'total': 2,
          'pageEnd': true,
        }, DateTime.utc(2026, 10, 20)),
      );
    }
    return super.read(
      operation,
      id: id,
      keyword: keyword,
      category: category,
      side: side,
      page: page,
      language: language,
      options: options,
    );
  }
}

Finder _kind(String k) =>
    find.byKey(ValueKey<(String, String)>(('market-kind', k)));
Finder _layout(String m) =>
    find.byKey(ValueKey<(String, String)>(('market-layout', m)));
Finder _card(String n) =>
    find.byKey(ValueKey<(String, Object)>(('market-order-card', n)));
Finder _row(String n) =>
    find.byKey(ValueKey<(String, Object?)>(('market-order-row', n)));
final _clear = find.byKey(const Key('market-clear-filters'));
final _retry = find.byKey(const Key('market-overview-retry'));
final _open = find.byKey(const Key('market-filters-open'));
final _drawerClose = find.byKey(const Key('market-drawer-close'));

Future<(MarketplaceController, _OrdersPort)> _page(
  WidgetTester tester,
  InteractionSuite suite, {
  double width = 1280,
  String kind = 'orders',
  bool failOverview = false,
}) async {
  size(tester, Size(width, 900));
  final port = _OrdersPort()..failOverview = failOverview;
  final c = MarketplaceController(port);
  await tester.pumpWidget(scopedApp(MarketplaceMarketPage(c), suite));
  await tester.pumpAndSettle();
  await c.browser.choose(kind: kind);
  // Orders open as hall cards by default (build 11); these checks start
  // from the table and switch to cards themselves.
  if (kind == 'orders') c.browser.setLayout('rows');
  await tester.pumpAndSettle();
  return (c, port);
}

void main() {
  testWidgets('standard suite keeps the measured native geometry', (
    tester,
  ) async {
    var (c, _) = await _page(tester, InteractionSuite.standard, kind: 'items');
    try {
      expect(
        tester.getRect(_kind('items')),
        within(distance: .001, from: const Rect.fromLTRB(240, 2, 290.2, 28)),
      );
      expect(
        tester.getRect(_kind('orders')),
        within(distance: .001, from: const Rect.fromLTRB(298.4332, 2, 348.6332, 28)),
      );
      expect(
        tester.getRect(_layout('cards')),
        const Rect.fromLTRB(1212, 0, 1246, 30),
      );
      expect(
        tester.getRect(_layout('rows')),
        const Rect.fromLTRB(1246, 0, 1280, 30),
      );
      expect(
        tester.getRect(
          find.descendant(of: _layout('cards'), matching: find.byType(Icon)),
        ),
        const Rect.fromLTRB(1221, 7, 1237, 23),
      );
      expect(
        tester.getRect(_clear),
        within(distance: .001, from: const Rect.fromLTRB(354, 167, 420.4, 187)),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();

      (c, _) = await _page(tester, InteractionSuite.standard);
      expect(
        tester.getRect(_row('O1')),
        const Rect.fromLTRB(241, 210, 1279, 266),
      );
      expect(
        tester.getRect(_row('O2')),
        const Rect.fromLTRB(241, 267, 1279, 323),
      );
      c.browser.setLayout('cards');
      await tester.pumpAndSettle();
      expect(
        tester.getRect(_card('O1')),
        within(distance: .001, from: const Rect.fromLTRB(240, 175, 489.5, 479)),
      );
      expect(
        tester.getRect(_card('O2')),
        within(
          distance: .001,
          from: const Rect.fromLTRB(503.5, 175, 753, 479),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();

      (c, _) = await _page(tester, InteractionSuite.standard, width: 800);
      expect(
        tester.getRect(_open),
        within(distance: .001, from: const Rect.fromLTRB(0, 5, 76.5, 25)),
      );
      await tester.tap(_open);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(_drawerClose),
        const Rect.fromLTRB(252, 0, 300, 48),
      );
      expect(
        tester.getRect(
          find.descendant(of: _drawerClose, matching: find.byType(Icon)),
        ),
        const Rect.fromLTRB(266, 14, 286, 34),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    }
  });

  for (final suite in InteractionSuite.values) {
    testWidgets('${suite.name}: kind, layout and clear by reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (c, _) = await _page(tester, suite, kind: 'items');
      try {
        activate(tester, namedButton(tester, '图片卡片'));
        await tester.pumpAndSettle();
        expect(c.browser.layout, 'cards');
        activate(tester, namedButton(tester, '订单'));
        await tester.pumpAndSettle();
        expect(c.browser.kind, 'orders');
        activate(tester, namedButton(tester, '密集行'));
        await tester.pumpAndSettle();
        expect(c.browser.layout, 'rows');
        activate(tester, namedButton(tester, '物品'));
        await tester.pumpAndSettle();
        expect(c.browser.kind, 'items');
        c.browser.keyword = 'x';
        await c.browser.reload(reset: true);
        await tester.pumpAndSettle();
        activate(tester, namedButton(tester, '全部清除'));
        await tester.pumpAndSettle();
        expect(c.browser.keyword, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });

    testWidgets('${suite.name}: order rows and cards open the order panel', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (c, _) = await _page(tester, suite);
      try {
        await tester.tap(_row('O1'));
        await tester.pumpAndSettle();
        expect(find.text('订单详情'), findsOneWidget);
        await tester.tap(find.byKey(const Key('market-order-close')));
        await tester.pumpAndSettle();
        c.browser.setLayout('cards');
        await tester.pumpAndSettle();
        await tester.tap(_card('O2'));
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
    });

    testWidgets('${suite.name}: overview retry and the narrow drawer', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (c, port) = await _page(
        tester,
        suite,
        width: 800,
        failOverview: true,
      );
      try {
        expect(_retry, findsOneWidget);
        port.failOverview = false;
        activate(tester, namedButton(tester, '重试'));
        await tester.pumpAndSettle();
        expect(_retry, findsNothing);
        activate(tester, namedButton(tester, '分类与筛选'));
        await tester.pumpAndSettle();
        expect(_drawerClose, findsOneWidget);
        activate(tester, namedButton(tester, '关闭'));
        await tester.pumpAndSettle();
        expect(_drawerClose, findsNothing);
        await tester.tap(_open);
        await tester.pumpAndSettle();
        await tester.tap(_drawerClose);
        await tester.pumpAndSettle();
        expect(_drawerClose, findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });
  }
}
