import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_bundle_copy.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_details.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_hall_drawers.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_hall_mine.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_copy.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_editor.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_manifest.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_publish_widgets.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_order_sheet.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_confirm.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_widgets.dart';

import 'marketplace_test.dart' show FixturePort, app;
import 'marketplace_slice4_test.dart' show preview;

MarketRow _order(int type, {String number = 'bundle-fixture'}) => {
  'orderNumber': number,
  'displayType': type,
  'creatorType': 1,
  'itemName': type == 2 ? '采矿工具包' : '单件工具',
  'seller': 'Fixture trader',
  'remainingQuantity': 3,
  'availableQuantity': 3,
  'locationId': 1,
  'unitPrice': 250,
  'qualityData': {'type': 'material', 'quality': 990},
  'items': [
    {'itemId': 101, 'itemName': '采矿工具', 'quantity': 2, 'unitPrice': 100},
    if (type != 1)
      {'itemId': 202, 'itemName': '备用组件', 'quantity': 1, 'unitPrice': 50},
  ],
};

class _Port extends FixturePort {
  final openedItems = <int>[];
  final offerOptions = <Map<String, String>>[];
  @override
  Future<MarketRead> read(String operation, {
    int id = 0, String keyword = '', int category = 0, int side = 1,
    int page = 1, String language = 'CN', Map<String, String> options = const {},
  }) async {
    if (operation == 'item') openedItems.add(id);
    if (operation == 'offers') offerOptions.add({...options});
    if (operation == 'latest') {
      return MarketRead({'rows': [
        _order(2), _order(1, number: 'single-fixture'),
        _order(3, number: 'barter-fixture'), _order(1, number: 'other-fixture'),
      ]}, DateTime.utc(2026, 11, 14));
    }
    return super.read(operation, id: id, keyword: keyword, category: category,
        side: side, page: page, language: language, options: options);
  }
}

class _ListingsPort implements MarketplaceListingsPort {
  List<MarketRow> manifests = [];
  List<MarketRow> rows = [];
  final writes = <(String, MarketRow)>[];
  @override
  Future<MarketRow> read() async => {
    'rows': rows, 'manifests': manifests, 'limit': 20,
    'items': [{'id': 202, 'name': '想要组件'}],
    'locations': [{'id': 1, 'name': '测试地点'}],
  };
  @override
  Future<void> write(String operation, MarketRow input) async {
    writes.add((operation, {...input}));
  }
}

MarketRow _manifest({Object? secondPrice = 50}) => {
  'id': 'manifest-fixture', 'name': '采矿工具包',
  'items': [
    // Same shape as the Host's manifest projection: a line's price is `price`.
    {'itemId': 101, 'name': '采矿工具', 'quantity': 2, 'price': 100},
    {'itemId': 202, 'name': '备用组件', 'quantity': 1, 'price': secondPrice},
  ],
};

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _launch(WidgetTester tester, void Function(BuildContext) open) async {
  _size(tester);
  await tester.pumpWidget(preview(Builder(builder: (context) => TextButton(
    onPressed: () => open(context), child: const Text('打开测试'),
  )), AppearanceMode.dark));
  // Localizations load asynchronously: let the first frame build.
  await tester.pumpAndSettle();
  await tester.tap(find.text('打开测试'));
  await _settle(tester);
}

void main() {
  setUp(marketMyOrders.clear);
  tearDown(marketMyOrders.clear);

  testWidgets('hall bundles and barter open details; singles still open items', (tester) async {
    _size(tester);
    final port = _Port();
    final c = MarketplaceController(port);
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c, AppearanceMode.dark, const Locale('zh', 'CN')));
    await _settle(tester);
    for (final (number, heading) in [
      ('bundle-fixture', '清单内容'), ('barter-fixture', '提供'),
    ]) {
      final card = find.byWidgetPredicate((w) =>
          w is MarketCard && w.row['orderNumber'] == number);
      await tester.ensureVisible(card);
      await tester.tap(card);
      await _settle(tester);
      expect(find.text('订单详情'), findsOneWidget);
      expect(find.text(heading), findsOneWidget);
      expect(port.openedItems, isEmpty);
      await tester.tap(find.byKey(const Key('market-order-close')));
      await _settle(tester);
    }
    final single = find.byWidgetPredicate((w) =>
        w is MarketCard && w.row['orderNumber'] == 'single-fixture');
    await tester.ensureVisible(single);
    await tester.tap(single);
    await _settle(tester);
    expect(c.itemId, 101);
    expect(port.openedItems, contains(101));
    expect(find.text('订单详情'), findsNothing);
  });

  testWidgets('bundle drawer opens details without single-item comparisons', (tester) async {
    _size(tester);
    final port = _Port();
    final c = MarketplaceController(port);
    addTearDown(c.dispose);
    await tester.pumpWidget(preview(Builder(builder: (context) =>
      SizedBox(width: 400, child: marketListingDrawer(context, context, c,
          _order(2), best: 100))), AppearanceMode.dark));
    await tester.pumpAndSettle();
    expect(find.text('看清单'), findsOneWidget);
    expect(find.textContaining('比最低价'), findsNothing);
    await tester.tap(find.text('看清单'));
    await _settle(tester);
    expect(find.text('清单内容'), findsOneWidget);
    expect(port.openedItems, isEmpty);
  });

  testWidgets('bundle detail hides view-item; content opens its own item after close', (tester) async {
    final port = _Port();
    final c = MarketplaceController(port);
    addTearDown(c.dispose);
    await _launch(tester, (context) => unawaited(showMarketOrder(context, c, _order(2))));
    expect(find.text('查看物品'), findsNothing);
    expect(find.byType(MarketQualityBadge), findsNothing);
    await tester.ensureVisible(find.text('备用组件'));
    await tester.tap(find.text('备用组件'));
    await _settle(tester);
    expect(find.text('订单详情'), findsNothing);
    expect(port.openedItems, [202]);
    expect(c.itemId, 202);
  });

  testWidgets('bundle confirmation ignores previously opened item and shows sets and contents', (tester) async {
    final c = MarketplaceController(_Port());
    addTearDown(c.dispose);
    await c.openItem(999);
    final row = _order(2)..remove('itemName');
    row['remark'] = '采矿工具包';
    await _launch(tester, (context) => unawaited(confirmMarketTrade(context, c, row)));
    expect(find.text('采矿工具包'), findsWidgets);
    expect(find.text('测试物品 999'), findsNothing);
    expect(find.text('1 套'), findsOneWidget);
    expect(find.textContaining('每套价格'), findsOneWidget);
    expect(find.text('采矿工具 × 2'), findsOneWidget);
    expect(find.text('备用组件 × 1'), findsOneWidget);
    expect(find.textContaining('990'), findsNothing);
    expect(find.byType(MarketQualityBadge), findsNothing);
  });

  // CX-HALL-FIX1-REVIEW follow-up: a single order without its own name
  // borrows the open item page's name only when it is that same item.
  for (final (opened, expected, absent) in const [
    (101, '测试物品 101', '采矿工具'),
    (999, '采矿工具', '测试物品 999'),
  ]) {
    testWidgets('single confirmation name with item $opened open', (tester) async {
      final c = MarketplaceController(_Port());
      addTearDown(c.dispose);
      await c.openItem(opened);
      final row = _order(1, number: 'single-fixture')..remove('itemName');
      await _launch(tester, (context) => unawaited(confirmMarketTrade(context, c, row)));
      expect(find.text(expected), findsOneWidget);
      expect(find.text(absent), findsNothing);
      expect(find.text('1 件'), findsOneWidget);
    });
  }

  testWidgets('barter detail explains contact and empty wanted items', (tester) async {
    final c = MarketplaceController(_Port());
    addTearDown(c.dispose);
    await _launch(tester, (context) => unawaited(showMarketOrder(context, c, _order(3))));
    expect(find.text('以物易物需要和对方商量，请先私信联系'), findsOneWidget);
    expect(find.text('交易方式'), findsOneWidget);
    // The empty wanted list (the trader's empty location also says 未填写).
    expect(find.text('未填写'), findsWidgets);
    expect(find.text('查看物品'), findsNothing);
  });

  testWidgets('own barter uses the own-listing hint', (tester) async {
    marketMyOrders.add('bundle-fixture');
    final c = MarketplaceController(_Port());
    addTearDown(c.dispose);
    await _launch(tester, (context) => unawaited(showMarketOrder(context, c, _order(3))));
    expect(find.text('这是你自己发布的挂单，不能和自己交易'), findsOneWidget);
    expect(find.text('以物易物需要和对方商量，请先私信联系'), findsNothing);
  });

  testWidgets('bundle cards omit quality and lowest-price tags', (tester) async {
    await tester.pumpWidget(preview(SizedBox(width: 320, height: 304,
      child: MarketCard(_order(2), open: () {}, best: 500)), AppearanceMode.dark));
    expect(find.textContaining('990'), findsNothing);
    expect(find.text('最低价'), findsNothing);
    await tester.pumpWidget(preview(SizedBox(width: 320, height: 304,
      child: MarketCard({..._order(2), 'qualityData': null}, open: () {}, best: 500)), AppearanceMode.dark));
    expect(find.text('最低价'), findsNothing);
    final port = _Port();
    port.prefs['favorites'] = [101];
    final c = MarketplaceController(port);
    addTearDown(c.dispose);
    await c.readPreferences();
    expect(c.isWatched(_order(2)), isFalse);
    expect(c.isWatched(_order(3)), isFalse);
    expect(c.isWatched(_order(1)), isTrue);
  });

  testWidgets('manifest publishing uses line prices times sets, without a price field', (tester) async {
    _size(tester);
    final port = _ListingsPort()..manifests = [_manifest()];
    final c = MarketplaceListingsController(port);
    addTearDown(c.dispose);
    await c.refresh();
    final draft = ListingDraft(manifestId: 'manifest-fixture',
        price: 'stale invalid price', quantity: '3', location: '1');
    await tester.pumpWidget(preview(ListingPublishDialog(c, draft, initialStep: 2), AppearanceMode.dark));
    await _settle(tester);
    expect(find.text('单价（UEC）'), findsNothing);
    expect(find.text('份数'), findsOneWidget);
    expect(c.priceFor(draft), 250);
    final total = tester.widget<MarketPrice>(find.byType(MarketPrice));
    expect(total.value, 750);
    await tester.ensureVisible(find.byKey(const Key('market-publish-next')));
    await tester.tap(find.byKey(const Key('market-publish-next')));
    await _settle(tester);
    expect(find.text('每套价格 × 份数'), findsOneWidget);
    expect(find.text('750 UEC'), findsOneWidget);
    expect(draft.toInput().containsKey('price'), isFalse);
  });

  for (final badPrice in [null, 0, -1]) {
    testWidgets('manifest publishing blocks missing or invalid line price: $badPrice', (tester) async {
      _size(tester);
      final port = _ListingsPort()..manifests = [_manifest(secondPrice: badPrice)];
      final c = MarketplaceListingsController(port);
      addTearDown(c.dispose);
      await c.refresh();
      await tester.pumpWidget(preview(ListingPublishDialog(c,
        ListingDraft(manifestId: 'manifest-fixture', location: '1'), initialStep: 2,
      ), AppearanceMode.dark));
      await _settle(tester);
      await tester.ensureVisible(find.byKey(const Key('market-publish-next')));
      await tester.tap(find.byKey(const Key('market-publish-next')));
      await _settle(tester);
      expect(find.text('清单里有物品没有填单价，请先到 SCM 补上'), findsOneWidget);
      expect(find.text('发布'), findsNothing);
      expect(port.writes, isEmpty);
    });
  }

  testWidgets('empty manifests disable the option and explain how to create one', (tester) async {
    _size(tester);
    final c = MarketplaceListingsController(_ListingsPort());
    addTearDown(c.dispose);
    await c.refresh();
    await tester.pumpWidget(preview(ListingPublishDialog(c, ListingDraft()), AppearanceMode.dark));
    await _settle(tester);
    final card = tester.widget<ListingOptionCard>(find.widgetWithText(ListingOptionCard, '清单'));
    expect(card.onTap, isNull);
    expect(find.text('还没有清单，请先在 SCM 创建'), findsOneWidget);
    await tester.pumpWidget(preview(MarketplaceListingsPage(c, initialManifests: true), AppearanceMode.dark));
    await _settle(tester);
    expect(find.text('还没有清单，请先在 SCM 创建'), findsOneWidget);
  });

  testWidgets('barter editor omits price and saves zero', (tester) async {
    final port = _ListingsPort();
    final c = MarketplaceListingsController(port);
    addTearDown(c.dispose);
    final row = <String, Object?>{'id': 'own-barter', 'itemId': 101,
      'side': 'barter', 'name': '易物工具', 'price': 'invalid', 'quantity': 2};
    await _launch(tester, (context) => unawaited(editListing(context, c, row)));
    expect(find.text('单价（UEC）'), findsNothing);
    await tester.tap(find.byKey(const Key('market-listing-save')));
    await _settle(tester);
    expect(port.writes, hasLength(1));
    expect(port.writes.single.$1, 'update');
    expect(port.writes.single.$2['price'], 0);
    expect(port.writes.single.$2['quantity'], 2);
    expect(find.text('编辑挂单'), findsNothing);
  });

  testWidgets('copying barter omits price and accepts a numeric location', (tester) async {
    _size(tester);
    final port = _ListingsPort()..rows = [{
      'id': 'own-barter-copy', 'itemId': 101, 'name': '易物工具',
      'side': 'barter', 'quantity': 2, 'price': 900, 'location': 1,
      'visible': true, 'wanted': '202',
      // Copy is offered only for a one-item sell-side barter (LS7).
      'displayType': 3, 'creatorType': 1, 'itemCount': 1,
    }];
    final c = MarketplaceListingsController(port);
    addTearDown(c.dispose);
    await tester.pumpWidget(preview(MarketplaceListingsPage(c), AppearanceMode.dark));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey<(String, Object?)>(('market-listing-more', 'own-barter-copy'))));
    await _settle(tester);
    await tester.tap(find.text('复制为新挂单'));
    await _settle(tester);
    final draft = tester.widget<ListingPublishDialog>(find.byType(ListingPublishDialog)).draft;
    expect(draft.price, isEmpty);
    expect(draft.location, '1');
    // The wanted item comes from the full order read (none in this fixture);
    // once picked, the published input still carries no price.
    draft.wanted = '202';
    expect(draft.toInput().containsKey('price'), isFalse);
    expect(find.text('单价（UEC）'), findsNothing);
  });

  for (final side in ['sell', 'barter']) {
    testWidgets('own multi-item hall card opens listings: $side', (tester) async {
      _size(tester);
      final port = _Port();
      final c = MarketplaceController(port)
        ..myListingsLoaded = true
        ..myListings = [{
          'id': 'own-hall', 'itemId': 101, 'name': '我的工具包',
          'side': side, 'checklist': side == 'sell', 'visible': true,
        }];
      addTearDown(c.dispose);
      await tester.pumpWidget(preview(MarketMyListingsStrip(c), AppearanceMode.dark));
      await _settle(tester);
      await tester.tap(find.text('我的工具包'));
      await _settle(tester);
      expect(c.mainTab, 3);
      expect(c.activityTab, 1);
      expect(port.openedItems, isEmpty);
    });
  }

  testWidgets('checklist listings hide copy in their page menu and hall drawer', (tester) async {
    _size(tester);
    final row = <String, Object?>{'id': 'own-bundle', 'itemId': 101,
      'name': '我的工具包', 'side': 'sell', 'checklist': true,
      'quantity': 2, 'price': 250, 'quality': 990, 'visible': true};
    final port = _ListingsPort()..rows = [row];
    final c = MarketplaceListingsController(port);
    addTearDown(c.dispose);
    await tester.pumpWidget(preview(MarketplaceListingsPage(c), AppearanceMode.dark));
    await _settle(tester);
    expect(find.byType(MarketQualityBadge), findsNothing);
    await tester.tap(find.byKey(const ValueKey<(String, Object?)>(('market-listing-more', 'own-bundle'))));
    await _settle(tester);
    expect(find.text('复制为新挂单'), findsNothing);
    expect(find.text('下架'), findsWidgets);
    final market = MarketplaceController(_Port());
    addTearDown(market.dispose);
    await tester.pumpWidget(preview(Builder(builder: (context) =>
      marketMineDrawer(context, context, market, row)), AppearanceMode.dark));
    await _settle(tester);
    expect(find.text('复制'), findsNothing);
  });

  testWidgets('clear all filters keeps checklist mode and requests checklist offers', (tester) async {
    _size(tester);
    final port = _Port();
    final c = MarketplaceController(port);
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c, AppearanceMode.dark, const Locale('zh', 'CN')));
    await _settle(tester);
    await c.openItem(101);
    await c.setOfferChecklist(true);
    await c.setOfferFilter('locationId', '1');
    await _settle(tester);
    port.offerOptions.clear();
    await tester.ensureVisible(find.byKey(const Key('market-offer-clear-filters')));
    await tester.tap(find.byKey(const Key('market-offer-clear-filters')));
    await _settle(tester);
    expect(c.offerChecklist, isTrue);
    expect(c.offerFilters, {'displayType': '2'});
    expect(port.offerOptions, isNotEmpty);
    expect(port.offerOptions.every((o) => o['displayType'] == '2'), isTrue);
    expect(find.byKey(const Key('market-offer-clear-filters')), findsNothing);
  });

  test('new bundle and listing copy has all three languages', () {
    for (final values in marketBundleCopy.values) {
      expect(values, hasLength(3));
      expect(values.every((text) => text.trim().isNotEmpty), isTrue);
    }
    for (final key in ['份数', '每套价格 × 份数', '还没有清单，请先在 SCM 创建',
      '正在读取清单…', '清单里有物品没有填单价，请先到 SCM 补上']) {
      expect(listingCopy[key], hasLength(3));
    }
  });
}
