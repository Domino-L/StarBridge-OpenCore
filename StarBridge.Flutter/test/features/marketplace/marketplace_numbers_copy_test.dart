// In-memory regressions only: no partner service or real account is used.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_activity_rail.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_banner.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_best_prices.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_copy.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_hall_drawers.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_item_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_copy.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_editor.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_market_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_my_activity.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_numbers.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_order_detail.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_records_copy.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_widgets.dart';

import 'marketplace_listing_copy_test.dart' show localized;
import 'marketplace_nav_refresh_test.dart' show bridge, wide;
import 'marketplace_slice4_test.dart' show preview;
import 'marketplace_test.dart' show FixturePort, app;
import 'marketplace_trades_test.dart' show TradesPort;

class _Prices extends FixturePort {
  bool failed = false, empty = false;
  Completer<void>? pricesGate;
  @override
  Future<MarketRead> read(String operation, {int id = 0, String keyword = '',
    int category = 0, int side = 1, int page = 1, String language = 'CN',
    Map<String, String> options = const {}}) async {
    if (operation == 'bestPrices') {
      await pricesGate?.future;
      if (failed) throw StateError('fixture unavailable');
      // The Host answers a read with no offers as a row whose price is null.
      return MarketRead({'rows': [
        {'id': 2, 'side': 1, 'price': empty ? null : 123},
        {'id': 2, 'side': 0, 'price': empty ? null : 100},
      ]}, DateTime.utc(2026));
    }
    if (operation == 'trend' && failed) throw StateError('fixture unavailable');
    if (operation == 'offers') {
      return MarketRead({'rows': [
        {'orderNumber': 'filtered', 'seller': 'Fixture', 'unitPrice': 9000},
      ], 'total': 1}, DateTime.utc(2026));
    }
    return super.read(operation, id: id, keyword: keyword, category: category,
      side: side, page: page, language: language, options: options);
  }
}

class _Listings implements MarketplaceListingsPort {
  _Listings(this.rows, {int? total}) : total = total ?? rows.length;
  final List<MarketRow> rows;
  final int total;
  @override
  Future<MarketRow> read() async => {
    'rows': rows, 'total': total, 'limit': 25,
    'items': <MarketRow>[], 'manifests': <MarketRow>[],
  };
  @override
  Future<void> write(String operation, MarketRow input) async {}
}

class _PagedListings extends _Listings implements MarketplaceListingLookup {
  _PagedListings() : super([_mixed().first], total: 5);
  final pages = <int>[];
  @override
  Future<MarketRow> nextPage(int page) async {
    pages.add(page);
    return {'rows': _mixed().skip(1).toList(), 'total': 5};
  }
  @override
  Future<List<MarketRow>> searchItems(String query, {int category = 0, int page = 1}) async => [];
  @override
  Future<List<MarketRow>> categories() async => [];
}

List<MarketRow> _mixed() => [
  {'id': 'sell', 'itemId': 2, 'name': 'Fixture', 'visible': true, 'side': 'sell', 'displayType': 1},
  {'id': 'buy', 'itemId': 2, 'name': 'Fixture', 'visible': true, 'side': 'buy', 'displayType': 1},
  {'id': 'checklist', 'visible': true, 'side': 'sell', 'displayType': 2},
  {'id': 'barter', 'visible': true, 'side': 'barter', 'displayType': 3},
  {'id': 'hidden', 'visible': false, 'side': 'sell', 'displayType': 1},
];

Widget _item(MarketplaceController c) => preview(
  ListenableBuilder(listenable: c, builder: (_, _) => MarketplaceItemPage(c)),
  AppearanceMode.dark,
);

Future<void> _close(WidgetTester tester, MarketplaceController c) async {
  await tester.pumpWidget(const SizedBox.shrink());
  c.dispose();
}

void main() {
  testWidgets('descending price and quality filters do not change global lowest', (tester) async {
    wide(tester);
    final c = MarketplaceController(_Prices());
    await c.openItem(2);
    await c.setOfferSort('price', buy: false);
    await c.setOfferFilter('minQuality', '700');
    await tester.pumpWidget(_item(c));
    await tester.pumpAndSettle();
    expect(c.offerFilters['sortOrder'], 'desc');
    expect(c.blocks['sell']!.rows.first['unitPrice'], 9000);
    expect(find.text('¤ 123'), findsOneWidget);
    expect(c.currentWatchSnapshot(2)['price'], '123');
    await _close(tester, c);
  });

  testWidgets('item price changes from loading to unavailable on failure', (tester) async {
    wide(tester);
    final gate = Completer<void>();
    final port = _Prices()..failed = true..pricesGate = gate;
    final c = MarketplaceController(port);
    await c.openItem(2);
    await tester.pumpWidget(_item(c));
    await tester.pump();
    expect(find.text('读取中…'), findsWidgets);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('读取中…'), findsNothing);
    expect(find.text('暂不可用'), findsWidgets);
    expect(c.currentWatchSnapshot(2)['price'], isNull);
    await _close(tester, c);
  });

  testWidgets('an item nobody trades says so instead of unavailable', (tester) async {
    wide(tester);
    final c = MarketplaceController(_Prices()..empty = true);
    await c.openItem(2);
    await tester.pumpWidget(_item(c));
    await tester.pumpAndSettle();
    expect(find.text('暂无出售'), findsWidgets);
    expect(find.text('暂无收购'), findsWidgets);
    // The headline figures; the history average below has its own state.
    expect(find.text('—'), findsWidgets);
    await _close(tester, c);
  });

  test('missing and failed best-price responses both settle and notify', () async {
    for (final fails in [false, true]) {
      var notifications = 0;
      final prices = MarketBestPrices(read: (_) async {
        if (fails) throw StateError('fixture');
        return MarketRead({'rows': <MarketRow>[]}, DateTime.utc(2026));
      }, isCurrent: (_) => true, changed: () => notifications++);
      expect(prices.has(2, 1), isFalse);
      await prices.ensure([(2, 1)], 0);
      expect(prices.has(2, 1), isTrue);
      expect(prices.price(2, 1), isNull);
      expect(notifications, greaterThan(0));
    }
  });

  testWidgets('listing projection image, ongoing flag and expiry reach page and editor', (tester) async {
    wide(tester);
    const image = 'asset:assets/brand/scm_wordmark.png';
    final row = {..._mixed().first, 'image': image,
      'hasOngoingTransactions': true, 'expiry': '2000-01-01T00:00:00Z',
      'price': 900, 'quantity': 1};
    final c = MarketplaceListingsController(_Listings([row]));
    await tester.pumpWidget(preview(MarketplaceListingsPage(c), AppearanceMode.dark));
    await tester.pumpAndSettle();
    expect(tester.widgetList<MarketArt>(find.byType(MarketArt)).any((art) => art.source == image), isTrue);
    expect(find.text('有进行中的交易'), findsOneWidget);
    expect(find.text('已过期'), findsOneWidget);
    expect(find.text('2000-01-01T00:00:00Z'), findsNothing);
    final context = tester.element(find.byType(MarketplaceListingsPage));
    unawaited(editListing(context, c, row));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(Dialog), matching:
      find.text('有进行中的交易。改价只影响之后发起的交易。')), findsOneWidget);
    expect(tester.widgetList<MarketArt>(find.descendant(of: find.byType(Dialog), matching: find.byType(MarketArt)))
      .any((art) => art.source == image), isTrue);
    expect(marketListingImage({'displayType': 2, 'image': image}), marketChecklistArt);
    expect(marketListingExpired({'expiry': '2030-01-01T00:00:00Z'}, now: DateTime.utc(2029)), isFalse);
    expect(marketListingExpired({'expiry': '2030-01-01T00:00:00Z'}, now: DateTime.utc(2030)), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('partial listings never claim all shown; empty listings offer publish', (tester) async {
    wide(tester);
    for (final rows in [<MarketRow>[_mixed().first], <MarketRow>[]]) {
      final c = MarketplaceListingsController(_Listings(rows, total: rows.isEmpty ? 0 : 30));
      await tester.pumpWidget(preview(MarketplaceListingsPage(c), AppearanceMode.dark));
      await tester.pumpAndSettle();
      expect(find.textContaining('已显示全部'), findsNothing);
      if (rows.isEmpty) {
        expect(find.text('还没有挂单，发布一条试试吧。'), findsOneWidget);
        expect(find.text('发布挂单'), findsWidgets);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    }
  });

  // CX-HALL-FIX4-REVIEW P2: SCM counts every undeleted order of the account
  // (checklist, barter and hidden ones too), i.e. the own-orders total.
  test('capacity is the own-orders total, as SCM counts it', () {
    final rows = _mixed();
    expect(marketListingCount(rows, 5), 5);
    expect(marketListingCount(rows, 100), 100);
    expect(marketListingCount(rows, null), isNull);
    expect(marketListingFull(rows, 5, 5), isTrue);
    expect(marketListingFull(rows, 5, 25), isFalse);
    expect(marketListingFull(rows, null, 2), isFalse);
  });

  test('refresh completes listing pages; price comparison needs a single item and hall', () async {
    final port = _PagedListings();
    final c = MarketplaceListingsController(port);
    await c.refresh();
    expect(port.pages, [2]); // Filters and Select all now cover every page.
    expect(c.activeSingleListingCount, 5);
    // Without the hall, only a row's own best (none from the Host today).
    expect(c.listingBestPrice(_mixed().first), isNull);
    expect(c.listingBestPrice({..._mixed().first, 'best': 123}), 123);
    c.bestPrice = (_, side) => side == 1 ? 123 : 456;
    expect(c.listingBestPrice(_mixed()[0]), 123);
    expect(c.listingBestPrice(_mixed()[1]), 456);
    expect(c.listingBestPrice({..._mixed()[2], 'itemId': 2}), isNull);
    expect(c.listingBestPrice({..._mixed()[3], 'itemId': 2}), isNull);
    c.dispose();
  });

  testWidgets('banner, publish drawer and activity rail share single-listing capacity', (tester) async {
    wide(tester);
    final (c, host) = await bridge(tester);
    host.limit = 25;
    host.rows.addAll(_mixed());
    await c.refreshMyOrders();
    await c.loadTradeProfile();
    expect(c.activeSingleListingCount, 5);
    await tester.pumpWidget(preview(Column(children: [
      MarketHallHead(c, search: const SizedBox.shrink(), onRefresh: null),
      Builder(builder: (ctx) => marketPublishDrawer(ctx, c)),
    ]), AppearanceMode.dark));
    await tester.pumpAndSettle();
    expect(find.text('5 / 25', findRichText: true), findsNWidgets(2));
    c.openMyListings();
    await tester.pumpWidget(preview(MarketplaceMyActivity(c), AppearanceMode.dark));
    await tester.pumpAndSettle();
    final rail = tester.widget<MarketActivityRail>(find.byType(MarketActivityRail));
    expect(rail.items.firstWhere((item) => item.id == 1).count, '5 / 25');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('publish wizard uses the same complete capacity count', (tester) async {
    wide(tester);
    final c = MarketplaceListingsController(_Listings(_mixed()));
    await c.refresh();
    c.limit = 5;
    await tester.pumpWidget(preview(ListingPublishDialog(c, ListingDraft()), AppearanceMode.dark));
    await tester.pumpAndSettle();
    expect(find.textContaining('挂单已满。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    c.total = 4;
    await tester.pumpWidget(preview(ListingPublishDialog(c, ListingDraft()), AppearanceMode.dark));
    await tester.pumpAndSettle();
    expect(find.textContaining('挂单已满。'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('todo adds plus for incomplete trades; completed reviews are not active', (tester) async {
    wide(tester);
    final c = MarketplaceController(TradesPort());
    c.trades.rows = [
      {'transactionNumber': 'approve', 'actorRole': 'buyer', 'creatorType': 0, 'deliveryStatus': 0, 'transactionStatus': 1},
      {'transactionNumber': 'review', 'actorRole': 'buyer', 'deliveryStatus': 3, 'transactionStatus': 2},
    ];
    c.trades.listLoaded = true;
    c.trades.ended = false;
    expect(c.activeTradeCount, 1);
    await tester.pumpWidget(preview(MarketHallHead(c,
      search: const SizedBox.shrink(), onRefresh: null), AppearanceMode.dark));
    await tester.pumpAndSettle();
    // The head banner and the hall tab badge share one 待我处理 label (TR5).
    expect(find.text('2+'), findsWidgets);
    await _close(tester, c);
  });

  testWidgets('failed order references settle to unavailable', (tester) async {
    wide(tester);
    final c = MarketplaceController(_Prices()..failed = true);
    await tester.pumpWidget(preview(MarketOrderDetail(c, {
      'id': 2, 'itemName': 'Fixture', 'displayType': 1, 'unitPrice': 900,
    }), AppearanceMode.dark));
    await tester.pumpAndSettle();
    expect(find.text('当前最低卖价'), findsOneWidget);
    // The lowest-ask line settles to unavailable; a failed history read
    // hides its own line rather than showing a figure.
    expect(find.text('暂不可用'), findsOneWidget);
    expect(find.text('读取中…'), findsNothing);
    await _close(tester, c);
  });

  testWidgets('market empty filters offer clear; overview and row header use accurate copy', (tester) async {
    wide(tester);
    final c = MarketplaceController(FixturePort()..emptyLists = true);
    c.browser.kind = 'orders';
    c.browser.orderLayout = 'rows';
    c.browser.options['creatorType'] = '0';
    await c.browser.reload();
    await tester.pumpWidget(preview(MarketplaceMarketPage(c), AppearanceMode.dark));
    await tester.pumpAndSettle();
    expect(find.text('单件出售'), findsOneWidget);
    expect(find.text('单件求购'), findsOneWidget);
    expect(find.text('交易方'), findsOneWidget);
    expect(find.text('没有符合筛选条件的结果'), findsOneWidget);
    expect(find.text('清除筛选'), findsWidgets);
    await tester.tap(find.text('清除筛选').last);
    await tester.pumpAndSettle();
    expect(c.browser.options, isEmpty);
    expect(find.text('没有符合筛选条件的结果'), findsNothing);
    await _close(tester, c);
  });

  testWidgets('hall empty side filter offers all types', (tester) async {
    wide(tester);
    final c = MarketplaceController(FixturePort()..emptyLists = true);
    await tester.pumpWidget(app(c, AppearanceMode.dark, const Locale('zh', 'CN')));
    await tester.pumpAndSettle();
    await c.setSide(1);
    await tester.pumpAndSettle();
    expect(find.text('看全部类型'), findsOneWidget);
    await tester.ensureVisible(find.text('看全部类型'));
    await tester.tap(find.text('看全部类型'));
    await tester.pumpAndSettle();
    expect(c.side, MarketplaceController.allSides);
    expect(find.text('看全部类型'), findsNothing);
    await _close(tester, c);
  });

  testWidgets('role-filtered empty trades offer all', (tester) async {
    wide(tester);
    final c = MarketplaceController(TradesPort());
    await c.trades.refresh();
    await tester.pumpWidget(preview(MarketplaceTradesPage(c), AppearanceMode.dark));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我买的'));
    await tester.pumpAndSettle();
    expect(find.text('这个筛选下没有交易'), findsOneWidget);
    await tester.tap(find.text('看全部'));
    await tester.pumpAndSettle();
    expect(find.text('这个筛选下没有交易'), findsNothing);
    await _close(tester, c);
  });

  testWidgets('trade row decisions, formatted shipping and cancel dismissal copy', (tester) async {
    wide(tester);
    final c = MarketplaceController(TradesPort());
    final row = <String, Object?>{
      'transactionNumber': 'T1', 'itemsName': 'Fixture', 'actorRole': 'buyer',
      'creatorType': 0, 'deliveryStatus': 0, 'transactionStatus': 1,
      'shippingFee': 12500, 'amount': 1000, 'number': 1,
    };
    c.trades.detail = row;
    await tester.pumpWidget(preview(SizedBox(width: 420, child: TradeSheet(c)), AppearanceMode.dark));
    await tester.pumpAndSettle();
    expect(find.text('12,500 UEC'), findsOneWidget);
    final ctx = tester.element(find.byType(TradeSheet));
    expect(tradeActionLabel(ctx, row), '去同意');
    expect(tradeActionLabel(ctx, {...row, 'deliveryStatus': 2}), '去收货');
    unawaited(tradeDialog(ctx, c, 'cancel', row));
    await tester.pumpAndSettle();
    // The close button stays 取消: route and reader tests name it so.
    expect(find.byKey(const Key('market-trade-action-cancel')), findsOneWidget);
    await _close(tester, c);
  });

  testWidgets('new copy has simplified, traditional and English values', (tester) async {
    for (final (locale, index) in [
      (const Locale('zh', 'CN'), 0), (const Locale('zh', 'TW'), 1), (const Locale('en'), 2),
    ]) {
      await tester.pumpWidget(localized(Builder(builder: (context) => Column(children: [
        Text(marketTextN(context, 'onSale', 3)),
        Text(marketTextN(context, 'onSaleTotal', 3)),
        Text(listingText(context, '设置交易时段')),
        Text(recordsText(context, '黑名单是空的。拉黑从交易单发起。')),
      ])), locale));
      await tester.pumpAndSettle();
      expect(find.text(['3 条挂单', '3 條掛單', '3 orders'][index]), findsOneWidget);
      expect(find.text(['共 3 条挂单', '共 3 條掛單', '3 orders in total'][index]), findsOneWidget);
      expect(find.text(['设置交易时段', '設定交易時段', 'Set trading hours'][index]), findsOneWidget);
      expect(find.text(['黑名单是空的。拉黑从交易单发起。', '黑名單是空的。封鎖請從交易單發起。',
        'Nobody is blocked. Block from a trade.'][index]), findsOneWidget);
    }
  });

  // CX-HALL-FIX4-REVIEW P2: an expired entry the Host now leaves out is
  // remembered as failed (no re-read on every rebuild), and a second caller
  // waits for a read already in flight.
  test('best prices: expired entry left out is not re-read; shared reads wait', () async {
    var reads = 0;
    Completer<MarketRead>? gate;
    var answer = <MarketRow>[{'id': 2, 'side': 1, 'price': 123}];
    final prices = MarketBestPrices(
      read: (_) async {
        reads++;
        if (gate case final pending?) return pending.future;
        return MarketRead({'rows': answer}, DateTime.utc(2026));
      },
      isCurrent: (_) => true,
      changed: () {},
    );
    await prices.ensure([(2, 1)], 0);
    expect(reads, 1);
    gate = Completer<MarketRead>();
    final first = prices.ensure([(2, 3)], 0);
    var secondDone = false;
    final second = prices.ensure([(2, 3)], 0).then((_) => secondDone = true);
    await Future<void>.delayed(Duration.zero);
    expect(reads, 2, reason: 'one read for both callers');
    expect(secondDone, isFalse, reason: 'the second caller waits for it');
    gate.complete(MarketRead({'rows': <MarketRow>[]}, DateTime.utc(2026)));
    await Future.wait([first, second]);
    expect(prices.has(2, 3), isTrue);
    gate = null;
    answer = [];
    await prices.ensure([(2, 3)], 0);
    expect(reads, 2, reason: 'a fresh failure is not read again');
  });
}
