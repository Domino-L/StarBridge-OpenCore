import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_display_copy.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_display_rules.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_hall_drawers.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_item_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_market_filters.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_market_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_order_detail.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_quality.dart';

import 'marketplace_listing_copy_test.dart' show localized;
import 'marketplace_test.dart' show FixturePort;

MarketRow _order(String number, num quality, {bool legacy = false}) => {
  'orderNumber': number, 'displayType': 1, 'creatorType': 0,
  'itemId': 7, 'itemName': '测试物品', 'unitPrice': 500, 'remainingQuantity': 3,
  'items': [{'itemId': 7, 'itemName': '测试物品', 'quantity': 1}],
  'qualityData': {'type': 'material', legacy ? 'quality' : 'qualityMin': quality},
};

class _Port extends FixturePort {
  final calls = <(String, int, Map<String, String>)>[];
  bool pageEnd = true;
  final rows = <MarketRow>[
    _order('low', 400), _order('equal', 600), _order('high', 800),
    _order('legacy', 500, legacy: true),
  ];

  @override
  Future<MarketRead> read(String operation, {
    int id = 0, String keyword = '', int category = 0, int side = 1,
    int page = 1, String language = 'CN', Map<String, String> options = const {},
  }) async {
    calls.add((operation, side, Map.of(options)));
    if (operation == 'marketOrders' || operation == 'offers') {
      return MarketRead({'rows': rows, 'total': pageEnd ? rows.length : 40,
        'pageEnd': pageEnd}, DateTime.now());
    }
    if (operation == 'item') {
      return MarketRead({...FixturePort.item(id), 'sellOrderCount': 9,
        'checklistSellCount': 3, 'buyOrderCount': 2, 'checklistBuyCount': 1}, DateTime.now());
    }
    if (operation == 'qualityTiers') {
      return MarketRead({'hasQuality': true, 'tiers': [
        {'key': 'good', 'known': true, 'lowest': 100, 'count': 1},
      ]}, DateTime.now());
    }
    return super.read(operation, id: id, keyword: keyword, category: category,
        side: side, page: page, language: language, options: options);
  }
}

Future<void> _mount(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1500, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(localized(Scaffold(body: child), const Locale('zh', 'CN')));
  await tester.pumpAndSettle();
}

void main() {
  test('MK4 offers omit buy quality on first page and later pages', () async {
    final p = _Port();
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    await c.openItem(7);
    p.calls.clear();
    await c.setOfferTier(MarketQualityTier.good);
    await c.moreOffers(true);
    final buys = p.calls.where((call) => call.$1 == 'offers' && call.$2 == 0);
    expect(buys, hasLength(2));
    for (final call in buys) {
      expect(call.$3.containsKey('minQuality'), isFalse);
      expect(call.$3.containsKey('maxQuality'), isFalse);
    }
    expect(p.calls.firstWhere((call) => call.$1 == 'offers' && call.$2 == 1).$3,
        {'minQuality': '600', 'maxQuality': '799'});
    expect(marketBuyQualityRows(p.rows, c.offerFilters).map((r) => r['orderNumber']),
        ['low', 'equal', 'legacy']);
    expect(marketBuyQualityRows([_order('fraction', 600.1)], c.offerFilters), isEmpty);
  });

  test('MK4 market orders filter requirements locally and retain raw paging totals', () async {
    final p = _Port();
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    await c.browser.choose(kind: 'orders');
    await c.browser.filter('creatorType', '0');
    p.calls.clear();
    await c.browser.filter('minQuality', '600');
    final request = p.calls.single;
    expect(request.$1, 'marketOrders');
    expect(request.$3.containsKey('minQuality'), isFalse);
    expect(request.$3.containsKey('maxQuality'), isFalse);
    expect(c.browser.visibleRows.map((r) => r['orderNumber']), ['low', 'equal', 'legacy']);
    expect(c.browser.result!.rows, hasLength(4));
    expect(c.browser.result!.total, 4);
    expect(marketBuyQualityRows([{'creatorType': 0}], {'minQuality': '600'}), hasLength(1));
  });

  testWidgets('MK4 buy menu and tier strip state the requirement ceiling', (tester) async {
    final c = MarketplaceController(_Port());
    addTearDown(c.dispose);
    await c.openItem(7);
    await c.qualityTiers.ensure(7);
    await c.setOfferTier(MarketQualityTier.good);
    c.itemTab = 1;
    await _mount(tester, MarketplaceItemPage(c));
    expect(find.text('只看要求不高于 600 的求购'), findsOneWidget);
    expect(find.textContaining('仅筛选已读取的订单'), findsOneWidget);
    expect(find.byKey(const ValueKey<(String, String)>(('market-buy-tier', 'good'))), findsOneWidget);
    expect(find.byKey(const ValueKey<(String, Object)>(('market-offer-row', 'high'))), findsNothing);
    expect(find.byKey(const ValueKey<(String, Object)>(('market-offer-row', 'equal'))), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('MK4 local market filter does not prefetch to fill the viewport', (tester) async {
    final p = _Port()..pageEnd = false;
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    await c.browser.choose(kind: 'orders');
    await c.browser.filter('creatorType', '0');
    await c.browser.filter('minQuality', '600');
    final before = p.calls.where((call) => call.$1 == 'marketOrders').length;
    await _mount(tester, MarketplaceMarketPage(c));
    expect(p.calls.where((call) => call.$1 == 'marketOrders'), hasLength(before));
    expect(find.text('已读取 4 条，符合条件 3 条'), findsOneWidget);
    expect(find.byKey(const Key('market-filtered-load-more')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('MK5 tier comparison never falls back to another tier', () {
    const tiers = MarketQualityTiers(hasQuality: true, sellLowest: 10, tiers: [
      MarketTierQuote(tier: MarketQualityTier.good, known: true, lowest: 100),
    ]);
    expect(marketTierLowest(_order('same', 650), tiers), 100);
    expect(marketTierLowest(_order('missing', 975), tiers), isNull);
    expect(marketTierLowest(_order('missing', 650), null), isNull);
    expect(marketSameQualityTier(_order('a', 650), _order('b', 799)), isTrue);
    expect(marketSameQualityTier(_order('a', 650), _order('b', 800)), isFalse);
  });

  testWidgets('MK5 hover hides missing tier and uses cached tier without reading', (tester) async {
    final p = _Port();
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    final row = _order('current', 650);
    Widget drawer() => Builder(builder: (context) =>
        marketListingDrawer(context, context, c, {...row, 'creatorType': 1}, best: 10));
    await _mount(tester, drawer());
    expect(find.text('同档最低卖价'), findsNothing);
    await c.qualityTiers.ensure(7);
    p.calls.clear();
    await tester.pumpWidget(localized(Scaffold(body: drawer()), const Locale('zh', 'CN')));
    await tester.pumpAndSettle();
    expect(find.text('同档最低卖价'), findsOneWidget);
    expect(find.text('+400.0%'), findsOneWidget);
    expect(p.calls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('MK5 detail other offers use only the loaded matching tier', (tester) async {
    final p = _Port();
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    await c.qualityTiers.ensure(7);
    await _mount(tester, MarketOrderDetail(c, _order('current', 650)));
    expect(find.text('同档最低卖价'), findsOneWidget);
    // The detail's own ListView is the first Scrollable under it; the price
    // and trader blocks hold other (horizontal) scrollables.
    await tester.scrollUntilVisible(find.text('同档其他报价'), 250,
        scrollable: find
            .descendant(of: find.byType(MarketOrderDetail), matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<(String, Object)>(('market-order-other', 'equal'))), findsOneWidget);
    expect(find.byKey(const ValueKey<(String, Object)>(('market-order-other', 'high'))), findsNothing);
    expect(find.byKey(const ValueKey<(String, Object)>(('market-order-other', 'low'))), findsNothing);
    expect(p.calls.where((call) => call.$1 == 'offers'), hasLength(1));
    expect(p.calls.where((call) => call.$1 == 'order'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final multiple in [true, false]) {
    testWidgets('LS11 bundle detail hint only when a line is above 1 ($multiple)', (tester) async {
      final p = _Port();
      final c = MarketplaceController(p);
      addTearDown(c.dispose);
      await _mount(tester, MarketOrderDetail(c, {
        'orderNumber': 'B1', 'displayType': 2, 'creatorType': 1, 'itemsComplete': true,
        'itemName': '测试清单', 'unitPrice': 150000, 'remainingQuantity': 5,
        'items': [
          {'itemId': 7, 'itemName': '测试物品', 'quantity': multiple ? 2 : 1, 'unitPrice': 100000},
          {'itemId': 8, 'itemName': '测试物品二', 'quantity': 1, 'unitPrice': 50000},
        ],
      }));
      expect(find.text('每套价格'), findsWidgets);
      expect(
        find.text('这张清单有数量大于 1 的物品。SCM 目前按各行价格直接相加算每套价格，没有乘数量；成交价以 SCM 交易单上的为准。'),
        multiple ? findsOneWidget : findsNothing,
      );
      expect(p.calls.where((call) => call.$1 == 'order'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('MK6 bundle and barter remove price filters and price sort', () async {
    final c = MarketplaceController(_Port());
    addTearDown(c.dispose);
    await c.browser.choose(kind: 'orders');
    for (final type in ['2', '3']) {
      c.browser.options.addAll({'minPrice': '10', 'maxPrice': '20', 'sortType': 'price'});
      await c.browser.filter('displayType', type);
      expect(c.browser.options.containsKey('minPrice'), isFalse);
      expect(c.browser.options.containsKey('maxPrice'), isFalse);
      expect(c.browser.options['sortType'], 'time');
      expect(marketBundleType(c.browser.options), isTrue);
    }
    final rows = <MarketRow>[{'unitPrice': 80}, {'unitPrice': 20}, {'unitPrice': 50}];
    expect(marketBundlePriceRows(rows, buy: false).map((r) => r['unitPrice']), [20, 50, 80]);
    expect(marketBundlePriceRows(rows, buy: true).map((r) => r['unitPrice']), [80, 50, 20]);
    expect(rows.first['unitPrice'], 80, reason: 'raw paging data stays unchanged');
  });

  testWidgets('MK6 price inputs hidden for bundles and barter; all has scope note', (tester) async {
    final c = MarketplaceController(_Port());
    addTearDown(c.dispose);
    await c.browser.choose(kind: 'orders');
    for (final type in ['2', '3', '']) {
      await c.browser.filter('displayType', type);
      await _mount(tester, MarketplaceMarketFilters(c, reset: (work) => work));
      expect(find.text('单价（UEC）'), type.isEmpty ? findsOneWidget : findsNothing);
      expect(find.text(type.isEmpty ? '只对单件有效' : 'SCM 不支持按套价筛选和排序'), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('MK6 bundle market sort menu has no unit price choice', (tester) async {
    final c = MarketplaceController(_Port());
    addTearDown(c.dispose);
    await c.browser.choose(kind: 'orders');
    await c.browser.filter('displayType', '2');
    await _mount(tester, MarketplaceMarketPage(c));
    await tester.tap(find.byKey(const Key('market-sort')));
    await tester.pumpAndSettle();
    expect(find.textContaining('单价 ↑'), findsNothing);
    expect(find.textContaining('单价 ↓'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('MK7 item identity totals include checklists despite filtered blocks', (tester) async {
    final c = MarketplaceController(_Port());
    addTearDown(c.dispose);
    await c.openItem(7);
    c.blocks['sell'] = MarketRead({'rows': <MarketRow>[], 'total': 0}, DateTime.now());
    c.blocks['buy'] = MarketRead({'rows': <MarketRow>[], 'total': 1}, DateTime.now());
    c.offerFilters['minQuality'] = '975';
    await _mount(tester, MarketplaceItemPage(c));
    expect(find.text('12 / 3'), findsOneWidget);
    tester.view.physicalSize = const Size(800, 1100);
    await tester.pumpAndSettle();
    expect(find.text('12 / 3'), findsOneWidget);
    expect(marketItemOrderCount({'sellOrderCount': 9, 'checklistSellCount': null}, buy: false), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('D2 copy has simplified, traditional and English variants', (tester) async {
    for (final (locale, index) in [
      (const Locale('zh', 'CN'), 0), (const Locale('zh', 'TW'), 1), (const Locale('en'), 2),
    ]) {
      await tester.pumpWidget(localized(Builder(builder: (context) => Column(children: [
        Text(marketDisplayText(context, 'quantityMissing')),
        Text(marketDisplayText(context, 'buyCeiling', n: 600)),
        Text(marketDisplayText(context, 'noBundleSort')),
      ])), locale));
      await tester.pumpAndSettle();
      expect(find.text(['可交易数量没读到，选多了可能被 SCM 拒绝', '可交易數量未讀到，選多了可能被 SCM 拒絕',
        'Tradable quantity unavailable. SCM may reject a larger quantity.'][index]), findsOneWidget);
      expect(find.text(['只看要求不高于 600 的求购', '只看要求不高於 600 的求購',
        'Buy orders requiring no more than 600'][index]), findsOneWidget);
      expect(find.text(['SCM 不支持按套价筛选和排序', 'SCM 不支援按套價篩選和排序',
        'SCM does not support filtering or sorting by bundle price'][index]), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
