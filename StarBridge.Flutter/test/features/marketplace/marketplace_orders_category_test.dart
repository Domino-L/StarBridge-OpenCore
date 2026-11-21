import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_category_tree.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

import 'marketplace_test.dart' show FixturePort, app;

/// G3 (user 2026-11-14, "1放"): the market's orders tab browses by category,
/// like SCM's order search. The tree narrows the current order filters.
class _Port extends FixturePort {
  final calls = <(String, int, Map<String, String>)>[];
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
  }) async {
    calls.add((operation, category, {...options}));
    if (operation == 'marketOrders') {
      final rows = [
        for (var i = 1; i <= 3; i++)
          {
            'orderNumber': 'OC$category$i',
            'displayType': 1,
            'creatorType': 1,
            'itemName': '测试物品 $i',
            'seller': 'Trader$i',
            'remainingQuantity': i,
            'unitPrice': '${100000 * i}',
            'items': [
              {'itemId': i, 'itemName': '测试物品 $i'},
            ],
          },
      ];
      return MarketRead({
        'rows': rows,
        'total': category == 0 ? 42 : 7,
        'allTotal': category == 0 ? 42 : 7,
      }, DateTime.utc(2026, 11, 14));
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

  (int, Map<String, String>) get lastOrders {
    final call = calls.lastWhere((e) => e.$1 == 'marketOrders');
    return (call.$2, call.$3);
  }
}

/// The page heading shares the tree's first label; look inside the tree.
Finder _tree(String text) => find.descendant(
  of: find.byType(MarketCategoryTree),
  matching: find.text(text),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<(MarketplaceController, _Port)> _openOrders(
  WidgetTester tester,
  Locale locale,
) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final port = _Port();
  final c = MarketplaceController(port);
  addTearDown(c.dispose);
  await tester.pumpWidget(app(c, AppearanceMode.dark, locale));
  await _settle(tester);
  await c.marketCategory(0);
  await c.browser.choose(kind: 'orders');
  await _settle(tester);
  return (c, port);
}

void main() {
  testWidgets('orders tab shows the category tree and sends the category', (
    tester,
  ) async {
    final (c, port) = await _openOrders(tester, const Locale('zh', 'CN'));
    expect(_tree('全部订单'), findsOneWidget);
    expect(_tree('全部物品'), findsNothing);
    expect(_tree('分类 3'), findsOneWidget);
    expect(port.lastOrders.$1, 0);

    // Side and type first, then a category: the category narrows them.
    await tester.tap(find.text('求购').first);
    await _settle(tester);
    await tester.tap(find.text('清单').first);
    await _settle(tester);
    await tester.tap(_tree('分类 3'));
    await _settle(tester);
    expect(c.browser.category, 3);
    expect(port.lastOrders.$1, 3);
    expect(port.lastOrders.$2['creatorType'], '0');
    expect(port.lastOrders.$2['displayType'], '2');
    expect(port.lastOrders.$2['sortType'], 'time');

    // Back to all orders keeps the filters too.
    await tester.tap(_tree('全部订单'));
    await _settle(tester);
    expect(c.browser.category, 0);
    expect(port.lastOrders.$1, 0);
    expect(port.lastOrders.$2['creatorType'], '0');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('orders tab tree counts the current filter in English', (
    tester,
  ) async {
    final (c, _) = await _openOrders(tester, const Locale('en'));
    expect(_tree('All orders'), findsOneWidget);
    expect(find.text('42'), findsWidgets);
    await tester.tap(_tree('Category 2'));
    await _settle(tester);
    expect(c.browser.category, 2);
    // A root row carries no count; the page header counts the orders.
    expect(find.textContaining('7 orders'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('entering a category from outside still resets order filters', (
    tester,
  ) async {
    final (c, port) = await _openOrders(tester, const Locale('zh', 'CN'));
    await tester.tap(find.text('求购').first);
    await _settle(tester);
    expect(port.lastOrders.$2['creatorType'], '0');
    // The hall's category tiles and other callers keep the old behaviour.
    await c.browser.choose(category: 4);
    await _settle(tester);
    expect(port.lastOrders.$1, 4);
    expect(port.lastOrders.$2.containsKey('creatorType'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('items tab tree is unchanged', (tester) async {
    final (c, _) = await _openOrders(tester, const Locale('zh', 'CN'));
    await c.browser.choose(kind: 'items');
    await _settle(tester);
    expect(_tree('全部物品'), findsOneWidget);
    expect(_tree('全部订单'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
