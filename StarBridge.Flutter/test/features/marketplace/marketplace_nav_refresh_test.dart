import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_attention.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_banner.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_chat_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_contracts_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_details.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_hall_drawers.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_my_activity.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_order_sheet.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_publish_entry.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_refresh.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_confirm.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_profile.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_warehouse_page.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'marketplace_bridge_trade_test.dart' show Online;
import 'marketplace_nav_refresh_fixtures.dart';
import 'marketplace_slice4_test.dart' show preview;
import 'marketplace_test.dart' show app;

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget host(MarketplaceController c, {Widget? child}) => preview(
  ListenableBuilder(listenable: c, builder: (context, _) => Column(children: [
    MarketCurrentPageHead(c, search: const SizedBox(width: 160)),
    Expanded(child: child ?? switch (c.mainTab) {
      2 => MarketplaceContractsPage(c),
      3 => MarketplaceMyActivity(c),
      4 => MarketplaceWarehousePage(c),
      _ => const SizedBox.shrink(),
    }),
  ])), AppearanceMode.dark);

Future<void> refresh(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('market-refresh')));
  await frames(tester);
}

void noHall(NavPort port) {
  expect(port.calls, isNot(contains('categories')));
  expect(port.calls, isNot(contains('trending')));
  expect(port.calls, isNot(contains('latest')));
}

Future<(MarketplaceController, NavBridge)> bridge(WidgetTester tester) async {
  final pair = InMemoryBridgeConnection.createPair();
  final session = BridgeClientSession(connection: pair.client, sessionGeneration: 1);
  session.acceptHostCapabilities([
    'marketplace.read', 'marketplace.listings', 'marketplace.trade',
    'marketplace.records', 'tradeProfile.read',
  ]);
  final mode = Online();
  final port = NavBridge();
  final subscription = pair.host.incoming.listen((request) async {
    final payload = await port.respond(request.name, request.payload);
    await pair.host.send(BridgeEnvelope(protocolVersion: 1, messageType: 'response',
      name: request.name, correlationId: request.correlationId, sessionGeneration: 1,
      accountContext: const BridgeAccountContext(environment: 'test', authority: 'fixture', subject: 'fixture'),
      status: 'ok', payload: payload));
  });
  final c = MarketplaceController(BridgeMarketplacePort(session, mode));
  addTearDown(() async {
    c.dispose();
    mode.dispose();
    await tester.runAsync(() async {
      await subscription.cancel();
      await session.close();
      await pair.host.close();
    });
  });
  return (c, port);
}

void main() {
  setUp(() { marketZoneOffsets.clear(); marketMyOrders.clear(); });
  tearDown(() { marketZoneOffsets.clear(); marketMyOrders.clear(); });

  testWidgets('watch and catalog refresh only themselves; background watch does not disable refresh', (tester) async {
    wide(tester);
    final p = NavPort();
    p.prefs['favorites'] = [1, 2];
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    await c.readPreferences();
    c.tab(5);
    await tester.pumpWidget(host(c));
    await frames(tester);
    p.calls.clear();
    await refresh(tester);
    expect(p.calls.where((v) => v == 'offers'), hasLength(4));
    noHall(p);

    await c.browse(query: 'fixture');
    await frames(tester);
    p.watchGate = Completer<void>();
    final pending = c.load('watch-price:99', 'offers', id: 99);
    await frames(tester);
    expect(c.currentPageLoading, isFalse);
    expect(tester.widget<MarketHallHead>(find.byType(MarketHallHead)).onRefresh, isNotNull);
    p.calls.clear();
    await refresh(tester);
    expect(p.calls, ['search']);
    p.watchGate!.complete();
    await pending;
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('contracts refresh uses the selected public, created or participated list', (tester) async {
    wide(tester);
    final p = NavPort();
    final c = MarketplaceController(p)..tab(2);
    addTearDown(c.dispose);
    await tester.pumpWidget(host(c));
    await frames(tester);
    for (final (i, call) in [(0, 'contracts:list:'), (1, 'contracts:mine:created'), (2, 'contracts:mine:participated')]) {
      await tester.tap(find.byKey(ValueKey(('market-contracts-view', i))));
      await frames(tester);
      p.calls.clear();
      await refresh(tester);
      expect(p.calls, [call]);
      noHall(p);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('warehouse refresh retains its selected inventory, ledger or escrow view', (tester) async {
    wide(tester);
    final p = NavPort();
    final c = MarketplaceController(p)..tab(4);
    addTearDown(c.dispose);
    await tester.pumpWidget(host(c));
    await frames(tester);
    for (final (i, call) in [(0, 'inventory'), (1, 'ledger'), (2, 'escrow')]) {
      await tester.tap(find.byKey(ValueKey(('market-warehouse-view', i))));
      await frames(tester);
      p.calls.clear();
      await refresh(tester);
      expect(p.calls, unorderedEquals(['warehouse:spaces', 'warehouse:summary', 'warehouse:$call']));
      noHall(p);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('activity refresh follows trades, reviews, reports and blocklist; reminder leaves reviews', (tester) async {
    wide(tester);
    final p = NavPort();
    final c = MarketplaceController(p)..tab(3);
    addTearDown(c.dispose);
    await tester.pumpWidget(host(c));
    await frames(tester);
    // The trades refresh also reads the ongoing list (status 1, TR5): two list calls.
    for (final (tab, calls) in [(0, ['trade:list', 'trade:list']), (3, ['records:reviews']), (4, ['records:reports'])]) {
      await tester.tap(find.byKey(ValueKey(('market-activity-tab', tab))));
      await frames(tester);
      p.calls.clear();
      await refresh(tester);
      expect(p.calls, calls);
      noHall(p);
    }
    await tester.tap(find.byKey(const ValueKey(('market-records-kind', 1))));
    await frames(tester);
    p.calls.clear();
    await refresh(tester);
    expect(p.calls, ['records:blocklist']);
    await tester.tap(find.byKey(const ValueKey(('market-activity-tab', 3))));
    await frames(tester);
    expect(find.byType(MarketplaceTradesPage), findsNothing);
    c.openMyTrades();
    await frames(tester);
    expect(find.byType(MarketplaceTradesPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('listings refresh and successful mutations update the hall snapshot', (tester) async {
    wide(tester);
    final (c, p) = await bridge(tester);
    c.openMyListings();
    await tester.pumpWidget(host(c));
    await frames(tester);
    p.fake.calls.clear();
    await refresh(tester);
    expect(p.fake.calls, contains('listings:read'));
    expect(p.fake.calls, isNot(contains('trade:list')));
    noHall(p.fake);
    final listings = tester.widget<MarketplaceListingsPage>(find.byType(MarketplaceListingsPage)).controller;
    for (final operation in ['create', 'update', 'delete', 'visibility']) {
      final row = <String, Object?>{'id': operation, 'name': 'fixture', 'visible': true};
      p.rows..clear()..add(row);
      p.fake.calls.clear();
      expect(await listings.write(operation, {'id': operation}), isTrue);
      expect(c.myListings.single['id'], operation);
      // Listings readback plus the hall's own paged snapshot read.
      expect(p.fake.calls.where((v) => v == 'listings:read'), hasLength(2));
    }
    p.rows..clear()..add({'id': 'batch', 'name': 'fixture', 'visible': false});
    await listings.setVisibility([{'id': 'batch', 'name': 'fixture'}], false);
    expect(c.myListings.single['visible'], isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('hall tab clears result filters and persists the home view', () async {
    final p = NavPort();
    final c = MarketplaceController(p);
    await c.readPreferences();
    await c.browse(query: 'old', category: 4);
    c.relation = 'compatible';
    c.relatedId = 17;
    c.tab(0);
    await c.saveView();
    expect(c.hasCatalog, isFalse);
    expect(c.relatedId, 0);
    c.dispose();
    final restored = MarketplaceController(p);
    await restored.readPreferences();
    expect(restored.hasCatalog, isFalse);
    restored.dispose();
  });

  testWidgets('subcategory drawer opens clean item browsing', (tester) async {
    wide(tester);
    final p = NavPort();
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    c.blocks['categories'] = MarketRead({'rows': [
      {'id': 2, 'parentId': 1, 'name': '子分类'},
    ]}, DateTime.utc(2026));
    c.browser..kind = 'orders'..keyword = 'old';
    c.browser.options['creatorType'] = '0';
    await tester.pumpWidget(preview(Builder(builder: (context) => marketCategoryDrawer(context, c, 1)), AppearanceMode.dark));
    await tester.pumpAndSettle();
    await tester.tap(find.text('子分类'));
    await frames(tester);
    expect(c.mainTab, 1);
    expect(c.browser.kind, 'items');
    expect(c.browser.category, 2);
    expect(c.browser.keyword, isEmpty);
    expect(c.browser.options, isEmpty);
    expect(p.queries.lastWhere((q) => q.$1 == 'marketItems').$3, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hall market links reset old order filters', (tester) async {
    wide(tester);
    final c = MarketplaceController(NavPort());
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c, AppearanceMode.dark, const Locale('zh', 'CN')));
    await frames(tester);
    for (final label in ['分类 1', '进入市场 →', '更多 →']) {
      c.hall();
      c.browser..kind = 'orders'..keyword = 'old';
      c.browser.options['creatorType'] = '0';
      await frames(tester);
      // The hall keeps its scroll offset; bring an off-screen heading back.
      if (find.text(label).evaluate().isEmpty) {
        await tester.scrollUntilVisible(find.text(label), -200,
            scrollable: find.ancestor(of: find.text('热门物品'),
                matching: find.byType(Scrollable)).first);
      }
      final link = find.text(label).first;
      await tester.ensureVisible(link);
      await tester.tap(link);
      await frames(tester);
      expect(c.mainTab, 1);
      expect(c.browser.kind, 'items');
      expect(c.browser.keyword, isEmpty);
      expect(c.browser.options, isEmpty);
    }
    await c.browse(query: 'result', category: 1);
    await frames(tester);
    expect(c.hasCatalog, isTrue);
    await tester.tap(find.text('大厅').first);
    await frames(tester);
    expect(c.hasCatalog, isFalse);
    expect(c.mainTab, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('all orders clears old query and carries sell, buy or barter once', () async {
    final p = NavPort();
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    for (final side in [1, 0, 2]) {
      c.side = side;
      c.browser..keyword = 'old'..category = 99;
      c.browser.options['minPrice'] = '123';
      p.queries.clear();
      await c.allHallOrders();
      final orders = p.queries.where((q) => q.$1 == 'marketOrders' && q.$4.containsKey('sortType')).toList();
      expect(orders, hasLength(1));
      expect(orders.single.$2, isEmpty);
      expect(orders.single.$3, 0);
      expect(orders.single.$4, isNot(contains('minPrice')));
      expect(orders.single.$4[side == 2 ? 'displayType' : 'creatorType'], side == 2 ? '3' : '$side');
    }
  });

  testWidgets('confirm details returns to the original order, other entry opens one detail', (tester) async {
    wide(tester);
    final c = MarketplaceController(NavPort());
    addTearDown(c.dispose);
    const row = <String, Object?>{'orderNumber': 'fixture-order', 'creatorType': 1,
      'displayType': 1, 'itemName': 'fixture', 'unitPrice': '100', 'remainingQuantity': 3};
    await tester.pumpWidget(preview(Builder(builder: (context) => Column(children: [
      TextButton(onPressed: () => showMarketOrder(context, c, row), child: const Text('order')),
      TextButton(onPressed: () => confirmMarketTrade(context, c, row), child: const Text('direct')),
    ])), AppearanceMode.dark));
    await tester.pumpAndSettle();
    await tester.tap(find.text('order'));
    await frames(tester);
    await tester.tap(find.byKey(const Key('market-order-confirm')));
    await frames(tester);
    expect(find.byType(Dialog, skipOffstage: false), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('market-confirm-details')));
    await frames(tester);
    expect(find.byType(Dialog, skipOffstage: false), findsOneWidget);
    Navigator.of(tester.element(find.byType(Dialog))).pop();
    await frames(tester);
    await tester.tap(find.text('direct'));
    await frames(tester);
    await tester.tap(find.byKey(const Key('market-confirm-details')));
    await frames(tester);
    expect(find.byType(Dialog, skipOffstage: false), findsOneWidget);
    expect(find.byKey(const Key('market-order-confirm')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('full publish wizard manages listings even when activity already exists', (tester) async {
    wide(tester);
    final (c, p) = await bridge(tester);
    p.limit = 0;
    c.tab(3);
    await tester.pumpWidget(host(c));
    await frames(tester);
    unawaited(openMarketPublish(tester.element(find.byType(MarketplaceMyActivity)), c));
    await frames(tester);
    expect(find.byType(ListingPublishDialog), findsOneWidget);
    await tester.tap(find.text('管理挂单'));
    await frames(tester);
    expect(find.byType(ListingPublishDialog), findsNothing);
    expect(find.byType(MarketplaceListingsPage), findsOneWidget);
    expect(c.activityTab, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unread trade message row requests the trade inbox destination', (tester) async {
    wide(tester);
    final p = NavPort();
    final c = MarketplaceController(p);
    final chat = MarketplaceChatController(p);
    final attention = MarketplaceAttention(c, chat);
    String? route;
    c.openDestination = (value) => route = value;
    addTearDown(() { attention.dispose(); chat.dispose(); c.dispose(); });
    await tester.pumpWidget(preview(MarketplaceAttentionCard(attention, open: c.openMyTrades), AppearanceMode.dark));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(('market-attention-row', 'messages'))));
    await frames(tester);
    expect(route, '/messages');
    expect(chat.takeRequest(), '');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('checklist resets sort direction as well as field', () async {
    final c = MarketplaceController(NavPort());
    addTearDown(c.dispose);
    c.itemId = 1;
    for (final field in ['price', 'quality']) {
      c.offerSortField = field;
      c.offerSortDesc = false;
      await c.setOfferChecklist(true);
      expect(c.offerSortField, 'price');
      expect(c.offerSortDesc, isTrue);
      await c.setOfferChecklist(false);
    }
  });

  test('twenty watched rows retain data after follow, unfollow and refresh', () async {
    final p = NavPort();
    p.prefs['favorites'] = List.generate(20, (i) => i + 1);
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    await c.readPreferences();
    await c.loadWatch();
    Future<void> check() async {
      for (var id = 13; id <= 20; id++) {
        expect(c.watchEntry(id).loaded, isTrue, reason: 'watch $id');
        expect(c.blocks['watch:$id'], isNotNull);
        expect(c.blocks['watch-buy:$id'], isNotNull);
      }
    }
    await c.toggleFavorite(21);
    await check();
    await c.toggleFavorite(1);
    await check();
    await c.loadFavorites();
    await check();
    await c.loadWatch();
    await check();
  });

  testWidgets('profile save updates banner before closing; unknown zones remain neutral; minute tick crosses boundary', (tester) async {
    wide(tester);
    final p = NavPort();
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    c.applyTradeProfile(p.profile);
    var now = DateTime.utc(2026, 11, 14, 9, 59);
    await tester.pumpWidget(preview(ListenableBuilder(listenable: c,
      builder: (context, _) => Column(children: [
        MarketHallHead(c, search: const SizedBox(width: 160), onRefresh: null, now: () => now),
        TextButton(onPressed: () => editTradeProfile(context, c), child: const Text('edit-profile')),
      ])), AppearanceMode.dark));
    await tester.pump();
    expect(marketTradeOpenNow(p.profile, now: now), isNull);
    expect(find.text('未设置'), findsNothing);
    expect(find.text('—'), findsWidgets);
    await c.load('timezones', 'timezones');
    await frames(tester);
    expect(find.textContaining('不在交易时段'), findsOneWidget);
    now = DateTime.utc(2026, 11, 14, 10);
    await tester.pump(const Duration(minutes: 1));
    expect(find.textContaining('现在可交易'), findsOneWidget);
    c.failures.add('timezones');
    c.applyTradeProfile(p.profile);
    await tester.pump();
    expect(find.textContaining('现在可交易'), findsNothing);

    // The form reads another complete window, then saves its confirmed result.
    p.profile = {...p.profile, 'tradeStartTime': '11:00', 'tradeEndTime': '13:00'};
    await tester.tap(find.text('edit-profile'));
    await frames(tester);
    await tester.tap(find.byKey(const Key('market-trade-profile-save')));
    await frames(tester);
    expect(p.calls, contains('profile:write'));
    expect(c.tradeProfile?['tradeStartTime'], '11:00');
    await tester.tap(find.byKey(const Key('market-trade-profile-close')));
    await frames(tester);
    expect(find.textContaining('不在交易时段'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 2));
    expect(tester.takeException(), isNull);
  });

  test('hall refresh also reloads trades and timezones', () async {
    final p = NavPort();
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    await c.refreshHall();
    expect(p.calls, containsAll(['trade:list', 'timezones', 'latest']));
  });

  // CX-HALL-FIX3-REVIEW P2: 刷新 stays off until every hall read is back.
  test('hall refresh keeps the button off until trades come back', () async {
    final p = NavPort();
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    p.tradeGate = Completer<void>();
    final work = c.refreshCurrentPage();
    await Future<void>.delayed(Duration.zero);
    expect(c.currentPageLoading, isTrue);
    p.tradeGate!.complete();
    await work;
    expect(c.currentPageLoading, isFalse);
  });
}
