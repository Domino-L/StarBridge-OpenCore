import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'marketplace_confirm_location_fixture.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_market_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_order_full.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_order_sheet.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_refresh.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_confirm.dart';

import 'marketplace_trades_test.dart' show TradesPort;
import '../../design_system/interaction/interaction_batch3i_test.dart' show scopedApp;
import '../friends/social_layout_test.dart' show size;

MarketRow _row({int display = 2, bool complete = false}) => {
  'orderNumber': 'SO1', 'displayType': display, 'creatorType': 1,
  'itemName': '测试清单', 'remainingQuantity': 3, 'unitPrice': 100,
  'locationId': 1, 'locationName': '测试地点',
  'itemsComplete': complete,
  'items': [
    for (var i = 1; i <= (complete ? 4 : 1); i++)
      {'itemId': i, 'itemName': '物品$i', 'quantity': 1},
  ],
};

class _Port extends TradesPort {
  int orders = 0;
  bool orderFails = false;
  int display = 2;
  int creatorType = 1;
  int? availableQty;
  MarketRow? created;
  Completer<MarketRead>? orderGate;
  final operations = <String>[];
  MarketRow get full => {
    ..._row(display: display, complete: true),
    'creatorType': creatorType,
    'availableQuantity': availableQty,
    'wantedItems': [
      {'itemId': 8, 'itemName': '想要物品', 'quantity': 2},
    ],
  };

  @override
  Future<MarketRow> trade(String operation, [MarketRow input = const {}]) {
    if (operation == 'create') created = Map.of(input);
    return super.trade(operation, input);
  }

  @override
  Future<MarketRead> read(String operation, {
    int id = 0, String keyword = '', int category = 0, int side = 1,
    int page = 1, String language = 'CN',
    Map<String, String> options = const {},
  }) async {
    operations.add(operation);
    if (operation == 'order') {
      orders++;
      expect(keyword, 'SO1');
      expect(language, 'CN');
      if (orderFails) throw StateError('unavailable');
      if (orderGate != null) return orderGate!.future;
      return MarketRead(full, DateTime.now());
    }
    if (operation == 'latest' || operation == 'marketOrders') {
      return MarketRead({'rows': [_row(display: display)], 'total': 1,
        'pageEnd': true}, DateTime.now());
    }
    return super.read(operation, id: id, keyword: keyword, category: category,
        side: side, page: page, language: language, options: options);
  }
}

Future<void> _mount(WidgetTester tester, MarketplaceController c,
    MarketRow row) async {
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  size(tester, const Size(1500, 1100));
  await tester.pumpWidget(scopedApp(Builder(builder: (context) => Column(
    children: [
      TextButton(key: const Key('detail'),
        onPressed: () => showMarketOrder(context, c, row),
        child: const Text('详情入口')),
      TextButton(key: const Key('confirm'),
        onPressed: () => confirmMarketTrade(context, c, row),
        child: const Text('确认入口')),
    ],
  )), InteractionSuite.standard));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void _fourItems() {
  for (var i = 1; i <= 4; i++) {
    expect(find.text('物品$i'), findsOneWidget);
  }
}

FilledButton _submit(WidgetTester tester) => tester.widget<FilledButton>(
  find.descendant(of: find.byKey(const Key('market-confirm-submit')),
      matching: find.byType(FilledButton)));

void main() {
  test('chat snapshot reads once on demand; recent orders reset with account', () async {
    final p = _Port();
    final cache = MarketOrderFull(p, language: () => 'CN');
    cache.rememberOpened(_row());
    expect(p.orders, 0);
    expect(cache.recentOrders.single['orderNumber'], 'SO1');
    final snapshot = <String, Object?>{'orderNumber': 'SO1', 'chatSnapshot': true};
    expect((await cache.fullOrder(snapshot))!['itemsComplete'], isTrue);
    await cache.fullOrder(snapshot);
    expect(p.orders, 1);
    cache.clear();
    expect(cache.recentOrders, hasLength(1), reason: 'hall refresh preserves recent orders');
    cache.clear(forgetRecent: true);
    expect(cache.recentOrders, isEmpty);
  });

  test('concurrent consumers share one read and merge each original row', () async {
    final p = _Port()..orderGate = Completer<MarketRead>();
    final cache = MarketOrderFull(p, language: () => 'CN');
    final a = cache.fullOrder({..._row(), 'local': 'a'});
    final b = cache.fullOrder({..._row(), 'local': 'b'});
    await Future<void>.delayed(Duration.zero);
    expect(p.orders, 1);
    p.orderGate!.complete(MarketRead(p.full, DateTime.now()));
    expect((await a)!['local'], 'a');
    expect((await b)!['local'], 'b');
    expect(marketRows((await cache.fullOrder(_row()))!['items']), hasLength(4));
    expect(p.orders, 1);
  });

  test('success and failure expire at five minutes; explicit retry bypasses failure', () async {
    final p = _Port();
    var now = DateTime(2026);
    final cache = MarketOrderFull(p, language: () => 'CN', clock: () => now);
    await cache.fullOrder(_row());
    now = now.add(const Duration(minutes: 4));
    await cache.fullOrder(_row());
    expect(p.orders, 1);
    now = now.add(const Duration(minutes: 1));
    p.orderFails = true;
    expect(await cache.fullOrder(_row()), isNull);
    expect(await cache.fullOrder(_row()), isNull);
    expect(p.orders, 2);
    now = now.add(const Duration(minutes: 5));
    expect(await cache.fullOrder(_row()), isNull);
    expect(p.orders, 3);
    p.orderFails = false;
    expect(await cache.fullOrder(_row(), retry: true), isNotNull);
    expect(p.orders, 4);
  });

  test('clearing during a read prevents stale completion and preserves newer read', () async {
    final p = _Port()..orderGate = Completer<MarketRead>();
    final cache = MarketOrderFull(p, language: () => 'CN');
    final oldGate = p.orderGate!;
    final old = cache.fullOrder(_row());
    await Future<void>.delayed(Duration.zero);
    cache.clear();
    p.orderGate = Completer<MarketRead>();
    final fresh = cache.fullOrder(_row());
    await Future<void>.delayed(Duration.zero);
    oldGate.complete(MarketRead(p.full, DateTime.now()));
    expect(await old, isNull);
    final shared = cache.fullOrder(_row());
    p.orderGate!.complete(MarketRead(p.full, DateTime.now()));
    expect(await fresh, isNotNull);
    expect(await shared, isNotNull);
    expect(p.orders, 2);
  });

  test('account change clears cached orders', () async {
    final p = _Port();
    final c = MarketplaceController(p);
    await c.fullOrders.fullOrder(_row());
    c.contextChanged();
    await c.fullOrders.fullOrder(_row());
    expect(p.orders, 2);
    c.dispose();
  });

  test('a new account generation never reuses cached or in-flight answers', () async {
    final p = _Port();
    final cache = MarketOrderFull(p, language: () => 'CN');
    await cache.fullOrder(_row());
    p.generation = 2;
    expect(await cache.fullOrder(_row()), isNotNull);
    expect(p.orders, 2);

    p.orderGate = Completer<MarketRead>();
    final oldGate = p.orderGate!;
    p.generation = 3;
    final old = cache.fullOrder(_row());
    await Future<void>.delayed(Duration.zero);
    p.generation = 4;
    p.orderGate = Completer<MarketRead>();
    final fresh = cache.fullOrder(_row());
    await Future<void>.delayed(Duration.zero);
    oldGate.complete(MarketRead(p.full, DateTime.now()));
    expect(await old, isNull);
    p.orderGate!.complete(MarketRead(p.full, DateTime.now()));
    expect(await fresh, isNotNull);
    expect(p.orders, 4);
  });

  for (final wanted in ['missing', 'null', 'empty']) {
    test('barter wanted list $wanted', () async {
      final p = _Port()..display = 3;
      final full = {...p.full};
      if (wanted == 'missing') full.remove('wantedItems');
      if (wanted == 'null') full['wantedItems'] = null;
      if (wanted == 'empty') full['wantedItems'] = const <MarketRow>[];
      p.orderGate = Completer<MarketRead>()
        ..complete(MarketRead(full, DateTime.now()));
      final cache = MarketOrderFull(p, language: () => 'CN');
      final result = await cache.fullOrder(_row(display: 3));
      if (wanted == 'empty') {
        expect(result, isNotNull);
        expect(marketRows(result!['wantedItems']), isEmpty);
      } else {
        expect(result, isNull);
      }
    });
  }

  testWidgets('detail expands one item to four; purchase shares the read', (tester) async {
    final p = _Port();
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    await _mount(tester, c, _row());
    await _tap(tester, 'detail');
    _fourItems();
    expect(p.orders, 1);
    await _tap(tester, 'market-order-confirm');
    for (var i = 1; i <= 4; i++) {
      expect(find.text('物品$i × 1'), findsOneWidget);
    }
    expect(p.orders, 1);
  });

  testWidgets('failed detail retries once and shows all items', (tester) async {
    final p = _Port()..orderFails = true;
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    await _mount(tester, c, _row());
    await _tap(tester, 'detail');
    expect(find.text('清单内容没有读全'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    p.orderFails = false;
    await _tap(tester, 'market-order-full-retry');
    _fourItems();
    expect(p.orders, 2);
  });

  testWidgets('failed confirmation blocks submission and retry recovers', (tester) async {
    final p = _Port()..orderFails = true;
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    await _mount(tester, c, _row());
    await _tap(tester, 'detail');
    await _tap(tester, 'market-order-confirm');
    expect(find.text('没有读到这张清单的全部物品，暂时不能下单'), findsOneWidget);
    expect(_submit(tester).onPressed, isNull);
    expect(p.orders, 1);
    p.orderFails = false;
    await _tap(tester, 'market-confirm-full-retry');
    expect(find.text('物品4 × 1'), findsOneWidget);
    await chooseConfirmLocation(tester);
    expect(_submit(tester).onPressed, isNotNull);
    expect(p.orders, 2);
  });

  testWidgets('loading confirmation disables submit', (tester) async {
    final p = _Port()..orderGate = Completer<MarketRead>();
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    await _mount(tester, c, _row());
    await _tap(tester, 'confirm');
    expect(find.text('读取中…'), findsOneWidget);
    expect(_submit(tester).onPressed, isNull);
    p.orderGate!.complete(MarketRead(p.full, DateTime.now()));
    await tester.pumpAndSettle();
    expect(find.text('物品4 × 1'), findsOneWidget);
  });

  for (final failed in [false, true]) {
    testWidgets('barter wanted items, failure=$failed', (tester) async {
      final p = _Port()
        ..display = 3
        ..orderFails = failed;
      final c = MarketplaceController(p);
      addTearDown(c.dispose);
      await _mount(tester, c, _row(display: 3));
      await _tap(tester, 'detail');
      expect(find.text(failed ? '没有读到' : '想要物品'), findsOneWidget);
      expect(find.text('未填写'), findsNothing);
      expect(p.orders, 1);
    });
  }

  for (final row in [_row(display: 1), _row(complete: true)]) {
    testWidgets('quantity read on confirm for display=${row['displayType']} complete=${row['itemsComplete']}',
        (tester) async {
      final p = _Port()..display = row['displayType'] as int;
      final c = MarketplaceController(p);
      addTearDown(c.dispose);
      await _mount(tester, c, row);
      await _tap(tester, 'detail');
      expect(p.orders, 0, reason: 'opening a complete detail adds no read');
      await _tap(tester, 'market-order-confirm');
      expect(p.orders, 1, reason: 'confirmation now needs available quantity');
    });
  }

  for (final side in [0, 1]) {
    for (final failed in [false, true]) {
      testWidgets('MK3 single side=$side failed=$failed quantity and submission', (tester) async {
        final p = _Port()
          ..display = 1
          ..creatorType = side
          ..availableQty = 2
          ..orderFails = failed;
        final c = MarketplaceController(p);
        addTearDown(c.dispose);
        await _mount(tester, c, {..._row(display: 1), 'creatorType': side});
        await _tap(tester, 'confirm');
        expect(p.orders, 1);
        for (var i = 0; i < 4; i++) {
          await _tap(tester, 'market-confirm-quantity-add');
        }
        expect(find.text('${failed ? 3 : 2} 件'), findsOneWidget);
        expect(find.text('可交易数量没读到，选多了可能被 SCM 拒绝'),
            failed ? findsOneWidget : findsNothing);
        await chooseConfirmLocation(tester);
        expect(_submit(tester).onPressed, isNotNull);
        await tester.ensureVisible(find.byKey(const Key('market-confirm-submit')));
        await _tap(tester, 'market-confirm-submit');
        expect(p.created?['number'], failed ? 3 : 2);
        expect(p.orders, 1);
      });
    }
  }

  testWidgets('MK3 single waits for quantity then clamps an earlier selection', (tester) async {
    final p = _Port()
      ..display = 1
      ..availableQty = 1
      ..orderGate = Completer<MarketRead>();
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    await _mount(tester, c, _row(display: 1));
    await _tap(tester, 'confirm');
    await _tap(tester, 'market-confirm-quantity-add');
    expect(find.text('2 件'), findsOneWidget);
    await chooseConfirmLocation(tester);
    expect(_submit(tester).onPressed, isNull);
    p.orderGate!.complete(MarketRead(p.full, DateTime.now()));
    await tester.pumpAndSettle();
    expect(find.text('1 件'), findsOneWidget);
    expect(_submit(tester).onPressed, isNotNull);
  });

  testWidgets('MK3/MK11 detail read shares quantity cache with single confirm', (tester) async {
    final p = _Port()..display = 1
      ..availableQty = 2;
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    // A chat snapshot already uses the existing detail read path.
    await _mount(tester, c, {..._row(display: 1), 'chatSnapshot': true});
    await _tap(tester, 'detail');
    expect(p.orders, 1);
    expect(find.text('可交易'), findsOneWidget);
    expect(find.text('有进行中的交易'), findsOneWidget);
    await _tap(tester, 'market-order-confirm');
    expect(p.orders, 1);
    for (var i = 0; i < 3; i++) {
      await _tap(tester, 'market-confirm-quantity-add');
    }
    expect(find.text('2 件'), findsOneWidget);
  });

  testWidgets('MK3 zero available disables submission', (tester) async {
    final p = _Port()..display = 1
      ..availableQty = 0;
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    await _mount(tester, c, _row(display: 1));
    await _tap(tester, 'confirm');
    await chooseConfirmLocation(tester);
    expect(_submit(tester).onPressed, isNull);
    expect(p.orders, 1);
  });

  testWidgets('MK3 a full read without available keeps the row cap, not remaining', (tester) async {
    // m99 review P2: the full read merges {...row, ...data}; a null available
    // there must fall back to the row's own available (2), not remaining (3).
    final p = _Port()..display = 1;
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    await _mount(tester, c, {..._row(display: 1), 'availableQuantity': 2});
    await _tap(tester, 'confirm');
    expect(p.orders, 1);
    for (var i = 0; i < 3; i++) {
      await _tap(tester, 'market-confirm-quantity-add');
    }
    expect(find.text('2 件'), findsOneWidget);
  });

  testWidgets('MK11 open detail updates after single confirmation read', (tester) async {
    final p = _Port()..display = 1
      ..availableQty = 2;
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    await _mount(tester, c, _row(display: 1));
    await _tap(tester, 'detail');
    expect(p.orders, 0);
    expect(find.text('可交易'), findsNothing);
    await _tap(tester, 'market-order-confirm');
    await _tap(tester, 'market-confirm-close');
    expect(find.text('可交易'), findsOneWidget);
    expect(find.text('有进行中的交易'), findsOneWidget);
    expect(p.orders, 1);
    await _tap(tester, 'market-order-confirm');
    expect(p.orders, 1);
  });

  test('MK3 forced single quantity read shares cache and expires after five minutes', () async {
    final p = _Port()..display = 1
      ..availableQty = 2;
    var now = DateTime(2026);
    final cache = MarketOrderFull(p, language: () => 'CN', clock: () => now);
    addTearDown(cache.dispose);
    expect((await cache.fullOrder(_row(display: 1), quantity: true))!['availableQuantity'], 2);
    await cache.fullOrder(_row(display: 1), quantity: true);
    expect(p.orders, 1);
    now = now.add(const Duration(minutes: 5));
    await cache.fullOrder(_row(display: 1), quantity: true);
    expect(p.orders, 2);
  });

  for (final tab in [0, 1]) {
    testWidgets('top refresh clears order cache on tab $tab', (tester) async {
      final p = _Port();
      final c = MarketplaceController(p);
      addTearDown(c.dispose);
      await _mount(tester, c, _row());
      await _tap(tester, 'detail');
      await _tap(tester, 'market-order-close');
      c.mainTab = tab;
      await c.refreshCurrentPage();
      await _tap(tester, 'detail');
      _fourItems();
      expect(p.orders, 2);
    });
  }

  testWidgets('hall and market rendering never request full orders', (tester) async {
    final p = _Port();
    final c = MarketplaceController(p);
    size(tester, const Size(1500, 1100));
    await tester.pumpWidget(scopedApp(MarketplacePage(c),
        InteractionSuite.standard));
    await tester.pumpAndSettle();
    expect(p.orders, 0);
    await tester.pumpWidget(scopedApp(MarketplaceMarketPage(c),
        InteractionSuite.standard));
    await tester.pumpAndSettle();
    await c.browser.choose(kind: 'orders');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<(String, Object)>(
        ('market-order-card', 'SO1'))), findsOneWidget);
    expect(p.orders, 0);
    // The hall starts the trades poll; dispose inside the body so its timer
    // is cancelled before the pending-timer check.
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.pump(const Duration(seconds: 3));
  });
}
