import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_barter.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_duplicate.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_editor.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_publish_widgets.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_confirm.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_locations.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_time.dart';

import 'marketplace_listing_copy_test.dart' show localized;
import 'marketplace_slice4_test.dart' show ListingsFixture;
import 'marketplace_trades_test.dart' show TradesPort;

const _sell = <String, Object?>{
  'id': 'L1', 'itemId': 11, 'name': 'Offered', 'side': 'sell',
  'price': 120, 'quantity': 2, 'visible': true, 'location': 1,
};

class _Listings extends ListingsFixture implements MarketplaceListingLookup {
  MarketRow? written;
  final pageCalls = <int>[];
  final searches = <String>[];
  Completer<MarketRow>? second;
  List<MarketRow> first = [{..._sell}];
  List<MarketRow> next = [];
  List<MarketRow> lists = [];
  @override
  Future<MarketRow> read() async => {
    'rows': first, 'total': first.length + next.length, 'manifests': lists,
  };
  @override
  Future<MarketRow> nextPage(int page) async {
    pageCalls.add(page);
    return second?.future ?? {'rows': next, 'total': first.length + next.length};
  }
  @override
  Future<List<MarketRow>> searchItems(String query, {int category = 0, int page = 1}) async {
    searches.add(query);
    return [{'id': 22, 'name': 'Wanted', 'thumbnailUrl': null}];
  }
  @override
  Future<List<MarketRow>> categories() async => [];
  @override
  Future<void> write(String operation, MarketRow input) async {
    written = Map.of(input);
  }
}

class _Trades extends TradesPort {
  int locationReads = 0, orderReads = 0;
  bool locationsFail = false, orderFail = false;
  MarketRow? created;
  @override
  Future<MarketRead> read(String operation, {int id = 0, String keyword = '',
    int category = 0, int side = 1, int page = 1, String language = 'CN',
    Map<String, String> options = const {}}) async {
    if (operation == 'locations') {
      locationReads++;
      if (locationsFail) throw StateError('fixture');
      return MarketRead({'rows': [{'id': 99, 'name': 'My station'}], 'total': 1}, DateTime.now());
    }
    if (operation == 'order') {
      orderReads++;
      if (orderFail) throw StateError('fixture');
      return MarketRead({
        'orderNumber': keyword, 'displayType': 3, 'itemsComplete': true,
        'items': [{'itemId': 11, 'quantity': 4}],
        'wantedItems': [{'itemId': 22, 'itemName': 'Wanted', 'quantity': 6}],
      }, DateTime.now());
    }
    return MarketRead({'rows': <MarketRow>[]}, DateTime.now());
  }
  @override
  Future<MarketRow> trade(String operation, [MarketRow input = const {}]) {
    if (operation == 'create') created = Map.of(input);
    return super.trade(operation, input);
  }
}

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(Widget child) => localized(child, const Locale('zh', 'CN'));
Finder _button(String key) => find.descendant(
  of: find.byKey(Key(key)), matching: find.byType(FilledButton));

void main() {
  testWidgets('LS3 checklist price is not editable and saves the original value', (tester) async {
    _size(tester);
    final port = _Listings();
    final c = MarketplaceListingsController(port);
    await tester.pumpWidget(_app(Builder(builder: (ctx) => TextButton(
      onPressed: () => editListing(ctx, c, {..._sell, 'checklist': true, 'price': 123.45}),
      child: const Text('Open'),
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('每套价格'), findsOneWidget);
    expect(find.text('由清单物品决定'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is TextField && w.controller?.text == '123.45'), findsNothing);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(port.written?['price'], 123.45);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  for (final creator in [0, 1]) {
    testWidgets('TR4 creator $creator requires own location and sends the selection', (tester) async {
      _size(tester);
      final port = _Trades();
      final c = MarketplaceController(port);
      await tester.pumpWidget(_app(Builder(builder: (ctx) => TextButton(
        onPressed: () => confirmMarketTrade(ctx, c, {
          'orderNumber': 'PUBLIC', 'creatorType': creator, 'availableQuantity': 3,
          'unitPrice': 10, 'locationId': 7, 'locationName': 'Their station',
        }), child: const Text('Open'),
      ))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text(creator == 1 ? '收货位置' : '发货位置'), findsOneWidget);
      expect(find.text('Their station'), findsOneWidget);
      expect(tester.widget<FilledButton>(_button('market-confirm-submit')).onPressed, isNull);
      await tester.tap(find.byKey(const Key('market-confirm-location')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My station').last);
      await tester.pumpAndSettle();
      await tester.tap(_button('market-confirm-submit'));
      await tester.pumpAndSettle();
      expect(port.created?['locationId'], 99);
      expect(port.locationReads, 1);
      expect(c.tradeLocations.selected, 99);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(_button('market-confirm-submit')).onPressed, isNotNull);
      expect(port.locationReads, 1);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }

  testWidgets('TR4 failed location load disables submit and offers retry', (tester) async {
    _size(tester);
    final port = _Trades()..locationsFail = true;
    final c = MarketplaceController(port);
    await tester.pumpWidget(_app(Builder(builder: (ctx) => TextButton(
      onPressed: () => confirmMarketTrade(ctx, c, {
        'orderNumber': 'PUBLIC-RETRY', 'creatorType': 1, 'availableQuantity': 3,
        'unitPrice': 10, 'locationId': 7,
      }), child: const Text('Open'),
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('地点读取失败'), findsOneWidget);
    expect(tester.widget<FilledButton>(_button('market-confirm-submit')).onPressed, isNull);
    port.locationsFail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('地点读取失败'), findsNothing);
    expect(tester.widget<FilledButton>(_button('market-confirm-submit')).onPressed, isNull);
    expect(port.locationReads, 2);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  test('TR4 location cache resets on account switch and a failed read can retry', () async {
    final port = _Trades()..locationsFail = true;
    final c = MarketplaceController(port);
    expect(await c.tradeLocations.load(), isNull);
    port.locationsFail = false;
    await c.tradeLocations.load();
    c.tradeLocations.choose(99);
    await c.tradeLocations.load();
    expect(port.locationReads, 2);
    port.generation++;
    expect(c.tradeLocations.selected, isNull);
    await c.tradeLocations.load();
    expect(port.locationReads, 3);
    c.tradeLocations.choose(99);
    c.contextChanged();
    expect(c.tradeLocations.selected, isNull);
    c.dispose();
  });

  testWidgets('TR4 trade sheet shows both role-labelled locations', (tester) async {
    _size(tester);
    final port = _Trades();
    port.row = {...port.row, 'locationName': 'Seller station', 'transactionLocationName': 'Buyer station'};
    final c = MarketplaceController(port);
    await c.trades.refresh();
    await tester.pumpWidget(_app(MarketplaceTradesPage(c)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TradeRow));
    await tester.pumpAndSettle();
    expect(find.text('卖家发货位置'), findsOneWidget);
    expect(find.text('买家收货位置'), findsOneWidget);
    expect(find.text('Seller station'), findsOneWidget);
    expect(find.text('Buyer station'), findsOneWidget);
    expect(tradeLocationRows({'creatorType': 0, 'locationName': 'Only'}), [('买家收货位置', 'Only')]);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('LS9 wanted search is independent and both per-trade quantities survive review', (tester) async {
    _size(tester);
    final port = _Listings();
    final c = MarketplaceListingsController(port)..items = [{'id': 11, 'name': 'Offered'}];
    final draft = ListingDraft(item: c.items.single, side: 'barter', location: '1', quantity: '12');
    await tester.pumpWidget(_app(ListingBarterFields(c, draft, onChanged: () {})));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('market-publish-wanted')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Wanted');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wanted').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('publish-offered-quantity')), '4');
    await tester.enterText(find.byKey(const ValueKey('publish-wanted-quantity')), '6');
    await tester.pumpAndSettle();
    expect(c.items.single['id'], 11);
    expect(port.searches, contains('Wanted'));
    expect(draft.wantedItem['name'], 'Wanted');
    expect(draft.validation, isNull);
    expect(draft.toInput()['offeredQuantity'], 4);
    expect(marketRows(draft.toInput()['wanted']).single['quantity'], 6);
    final ctx = tester.element(find.byType(ListingBarterFields));
    expect(listingConfirmRows(ctx, c, draft, 'Offered'), contains(('想换', 'Wanted × 6')));
    draft.offeredQuantity = '1000';
    expect(draft.validation, isNotNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  test('LS7 copies exact sell quality and buy minimum quality', () async {
    for (final side in ['sell', 'buy']) {
      final draft = await duplicateListing({..._sell, 'side': side,
        'qualityData': side == 'sell' ? '{"type":"material","quality":800}'
          : '{"type":"material","qualityMin":720}'}, null);
      expect(draft.quality, side == 'sell' ? '800' : '720');
      expect(draft.item['hasQuality'], isTrue);
    }
  });

  test('LS7 barter copy reuses full-order cache and preserves wanted metadata', () async {
    final port = _Trades();
    final c = MarketplaceController(port);
    final row = {..._sell, 'side': 'barter', 'displayType': 3, 'creatorType': 1, 'itemCount': 1};
    final draft = await duplicateListing(row, c.fullOrders);
    expect(draft.wantedItem['name'], 'Wanted');
    expect(draft.wantedQuantity, '6');
    // Never inherited: 0.7.2 barters stored the stock count here.
    expect(draft.offeredQuantity, '1');
    await duplicateListing(row, c.fullOrders);
    expect(port.orderReads, 1);
    expect(listingCanCopy({...row, 'itemCount': 2}), isFalse);
    expect(listingCanCopy({...row, 'creatorType': 0}), isFalse);
    expect(listingCanCopy({...row}..remove('itemCount')), isFalse);
    expect(listingCanCopy({...row}..remove('itemCount'), c.fullOrders), isTrue);
    port.orderFail = true;
    final failed = await duplicateListing({...row, 'id': 'FAIL'}, c.fullOrders);
    expect(failed.wanted, isEmpty);
    expect(failed.wantedItem, isEmpty);
    c.dispose();
  });

  testWidgets('LS4 LS7 unknown/multi barter has detail action but no copy', (tester) async {
    _size(tester);
    final port = _Listings()..first = [{..._sell, 'side': 'barter', 'displayType': 3,
      'creatorType': 1, 'itemCount': 2}];
    final c = MarketplaceListingsController(port);
    var opened = 0;
    c.openOrder = (_, _) async { opened++; };
    await tester.pumpWidget(_app(MarketplaceListingsPage(c)));
    await tester.pumpAndSettle();
    expect(find.textContaining('待更新'), findsNothing);
    await tester.tap(find.byKey(const ValueKey<(String, Object?)>(('market-listing-detail', 'L1'))));
    await tester.pumpAndSettle();
    expect(opened, 1);
    await tester.tap(find.byKey(const ValueKey<(String, Object?)>(('market-listing-more', 'L1'))));
    await tester.pumpAndSettle();
    expect(find.text('复制为新挂单'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('LS6 manifest timestamp uses local time instead of raw milliseconds', (tester) async {
    _size(tester);
    const timestamp = 1731561234000;
    final port = _Listings()..lists = [{'id': 1, 'name': 'Manifest', 'updated': timestamp, 'items': <MarketRow>[]}];
    final c = MarketplaceListingsController(port);
    await tester.pumpWidget(_app(MarketplaceListingsPage(c, initialManifests: true)));
    await tester.pumpAndSettle();
    expect(find.textContaining('$timestamp'), findsNothing);
    expect(find.textContaining(scmLocalTime(timestamp)!), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('LS8 short filtered list still loads the second-page barter', (tester) async {
    _size(tester);
    final port = _Listings()
      ..next = [{..._sell, 'id': 'L2', 'name': 'Second barter', 'side': 'barter'}]
      ..second = Completer<MarketRow>();
    final c = MarketplaceListingsController(port);
    await tester.pumpWidget(_app(MarketplaceListingsPage(c)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<(String, Object?)>(('market-listing-select', 'L1'))));
    await tester.pumpAndSettle();
    final selectAll = find.byWidgetPredicate((w) => w is StarBridgeCheckboxTile &&
      w.controlKey == const Key('market-listings-select-all'));
    expect(tester.widget<StarBridgeCheckboxTile>(selectAll).onChanged, isNull);
    await tester.tap(find.text('以物易物').first);
    await tester.pumpAndSettle();
    expect(c.allListingsLoaded, isFalse);
    port.second!.complete({'rows': port.next, 'total': 2});
    await tester.pumpAndSettle();
    expect(find.text('Second barter'), findsOneWidget);
    expect(find.text('Offered'), findsNothing);
    expect(find.text('已显示 2 / 2'), findsOneWidget);
    expect(c.allListingsLoaded, isTrue);
    expect(tester.widget<StarBridgeCheckboxTile>(selectAll).onChanged, isNotNull);
    expect(port.pageCalls, [2]);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
