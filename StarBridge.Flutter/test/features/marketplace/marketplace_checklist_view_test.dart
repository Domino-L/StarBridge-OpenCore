import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_widgets.dart';

import 'marketplace_test.dart' show FixturePort, app;

/// Checklist orders (SCM displayType 2) in the hall, user 2026-11-11:
/// A1 side and type are separate order filters, A2 the item page's 单件 / 清单
/// switch, A3 a checklist order's title.
MarketRow _single(int i, int creator) => {
  'orderNumber': 'SO$i',
  'displayType': 1,
  'creatorType': creator,
  'itemName': '测试物品 $i',
  'seller': 'Trader$i',
  'remainingQuantity': 5,
  'unitPrice': '${800000 + i}',
  'items': [
    {
      'itemId': i,
      'itemName': '测试物品 $i',
      'qualityData': '{"type":"material","quality":980}',
    },
  ],
};

MarketRow _checklist(String number, {String? name, String? remark}) => {
  'orderNumber': number,
  'displayType': 2,
  'creatorType': 1,
  'itemName': ?name,
  'remark': ?remark,
  'seller': 'Bundle*****r',
  'remainingQuantity': 2,
  'unitPrice': '5200000',
  'items': [
    {
      'itemId': 1,
      'itemName': '测试物品 1',
      'qualityData': '{"type":"material","quality":990}',
    },
  ],
};

class _Port extends FixturePort {
  final calls = <(String, int, Map<String, String>, String)>[];

  /// While set, buy-side offer reads wait for it (a slow refilter).
  Completer<void>? buyGate;
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
    calls.add((operation, side, {...options}, language));
    if (operation == 'offers' && side == 0) await buyGate?.future;
    if (operation == 'marketOrders') {
      final rows = [
        _checklist('SOLIST1', name: '新手采矿套装'),
        for (var i = 1; i <= 3; i++) _single(i, i.isEven ? 0 : 1),
      ];
      return MarketRead({
        'rows': rows,
        'total': rows.length,
      }, DateTime.utc(2026, 11, 11));
    }
    if (operation == 'offers') {
      final rows = options['displayType'] == '2'
          ? [_checklist('SOLIST1', name: '新手采矿套装')]
          : [for (var i = 1; i <= 3; i++) _single(i, side)];
      return MarketRead({
        'rows': rows,
        'total': rows.length,
      }, DateTime.utc(2026, 11, 11));
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets(
    'A3: a checklist order is titled by its checklist, never as one item',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        Localizations(
          locale: const Locale('zh', 'CN'),
          delegates: const [
            AppStringsDelegate(),
            DefaultWidgetsLocalizations.delegate,
            DefaultMaterialLocalizations.delegate,
          ],
          child: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();
      // SCM's list title for a checklist order is the checklist name.
      expect(
        marketOrderTitle(context, _checklist('A', name: '新手采矿套装')),
        '新手采矿套装',
      );
      // No name: the remark SCM stored the checklist title in.
      expect(
        marketOrderTitle(context, _checklist('B', remark: '  采矿套装 ')),
        '采矿套装',
      );
      // Neither: the first item, marked as part of a bundle.
      expect(marketOrderTitle(context, _checklist('C')), '测试物品 1 等');
      expect(
        marketOrderTitle(context, {..._checklist('D'), 'items': <MarketRow>[]}),
        '清单',
      );
      // A single-item order without a row name still reads as its item.
      expect(
        marketOrderTitle(context, {..._single(7, 1), 'itemName': null}),
        '测试物品 7',
      );
      // A barter order's remark is not a title source.
      expect(
        marketOrderTitle(context, {
          ..._single(8, 1),
          'displayType': 3,
          'itemName': '',
          'remark': '想换',
        }),
        '测试物品 8',
      );
    },
  );

  testWidgets('A1: order side and order type filter separately', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = _Port();
    final c = MarketplaceController(port);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      app(c, AppearanceMode.dark, const Locale('zh', 'CN')),
    );
    await _settle(tester);
    await c.marketCategory(1);
    await c.browser.choose(kind: 'orders');
    await _settle(tester);
    expect(find.text('方向'), findsOneWidget);
    expect(find.text('单件'), findsOneWidget);
    Map<String, String> last() =>
        port.calls.lastWhere((e) => e.$1 == 'marketOrders').$3;

    await tester.tap(find.text('清单').first);
    await _settle(tester);
    expect(last()['displayType'], '2');
    expect(last().containsKey('creatorType'), isFalse);

    // Choosing 出售 keeps 清单: sell checklists, no forced single-item type.
    await tester.tap(find.text('出售').first);
    await _settle(tester);
    expect(last()['displayType'], '2');
    expect(last()['creatorType'], '1');

    await tester.tap(find.text('以物易物').first);
    await _settle(tester);
    expect(last()['displayType'], '3');
    expect(last()['creatorType'], '1');

    // 全部 under 类型 drops only the type.
    await tester.tap(find.text('全部').at(1));
    await _settle(tester);
    expect(last().containsKey('displayType'), isFalse);
    expect(last()['creatorType'], '1');
    // The checklist order's card carries its checklist name.
    expect(find.text('新手采矿套装'), findsWidgets);
  });

  testWidgets(
    'A2: the item page shows checklists containing the item, without per-item maths',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = _Port();
      final c = MarketplaceController(port);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        app(c, AppearanceMode.dark, const Locale('zh', 'CN')),
      );
      await _settle(tester);
      await c.openItem(1);
      await _settle(tester);
      // Single-item offers by default; the quality menu is there.
      final offers = port.calls.where((e) => e.$1 == 'offers').toList();
      expect(offers.every((e) => !e.$3.containsKey('displayType')), isTrue);
      expect(find.byKey(const Key('market-quality-menu')), findsOneWidget);
      expect(
        find.byKey(const ValueKey(('market-offer-kind', false))),
        findsOneWidget,
      );

      await c.setOfferFilter('minQuality', '800');
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey(('market-offer-kind', true))));
      await _settle(tester);
      final checklist = port.calls
          .where((e) => e.$1 == 'offers')
          .toList()
          .reversed
          .take(2);
      expect(checklist.map((e) => e.$2).toSet(), {0, 1});
      for (final call in checklist) {
        expect(call.$3['displayType'], '2');
        expect(
          call.$3.containsKey('minQuality'),
          isFalse,
          reason: 'quality filters drop for bundles',
        );
      }
      expect(c.offerChecklist, isTrue);
      // Bundle prices stay apart: the single-item rows behind the lowest
      // price, the follow snapshot and the quality tiers are untouched.
      expect(c.blocks['sell-checklist']!.rows.single['orderNumber'], 'SOLIST1');
      expect(c.blocks['sell']!.rows.map((r) => r['orderNumber']), [
        'SO1',
        'SO2',
        'SO3',
      ]);
      // The follow snapshot reads the market-wide best single price (fix 4),
      // never the bundle's whole-set price.
      expect(c.currentWatchSnapshot(1)['price'], c.bestPrice(1, 1));
      expect(
        c.currentWatchSnapshot(1)['price'],
        isNot(c.blocks['sell-checklist']!.rows.single['unitPrice']),
      );
      expect(
        find.byKey(
          const ValueKey<(String, Object)>(('market-checklist-row', 'SOLIST1')),
        ),
        findsOneWidget,
      );
      expect(find.text('新手采矿套装'), findsOneWidget);
      expect(find.byKey(const Key('market-quality-menu')), findsNothing);
      expect(
        find.byKey(
          const ValueKey<(String, Object)>(('market-offer-row', 'SO1')),
        ),
        findsNothing,
      );

      // The buy tab and a refresh keep the switch.
      c.selectItemTab(1);
      await _settle(tester);
      expect(
        find.byKey(
          const ValueKey<(String, Object)>(('market-checklist-row', 'SOLIST1')),
        ),
        findsOneWidget,
      );

      // Back on 出售 (buy rows carry quality tags this test does not measure).
      c.selectItemTab(0);
      await _settle(tester);
      await tester.tap(
        find.byKey(const ValueKey(('market-offer-kind', false))),
      );
      await _settle(tester);
      expect(c.offerChecklist, isFalse);
      expect(
        port.calls
            .lastWhere((e) => e.$1 == 'offers')
            .$3
            .containsKey('displayType'),
        isFalse,
      );
      expect(
        find.byKey(
          const ValueKey<(String, Object)>(('market-offer-row', 'SO1')),
        ),
        findsOneWidget,
      );
    },
  );

  test(
    'A2: a quality sort gives way to price when switching to checklists',
    () async {
      final c = MarketplaceController(_Port());
      addTearDown(c.dispose);
      await c.openItem(1);
      c.offerSortField = 'perPoint';
      await c.setOfferChecklist(true);
      expect(c.offerSortField, 'price');
      expect(c.offerFilters, {'displayType': '2'});
    },
  );

  // CX-HALL-CHECKLIST-A2-REVIEW P2: one side done, the other cancelled.
  test(
    'A2: cancelling a refilter puts back a side that already finished',
    () async {
      final port = _Port();
      final c = MarketplaceController(port);
      addTearDown(c.dispose);
      await c.openItem(1);
      await c.setOfferChecklist(true);
      final sell = c.blocks['sell-checklist'], buy = c.blocks['buy-checklist'];
      port.buyGate = Completer<void>();
      final change = c.setOfferFilter('creatorStatus', '1');
      await pumpEventQueue();
      // 出售 already shows the online-only rows; 求购 is still waiting.
      expect(identical(c.blocks['sell-checklist'], sell), isFalse);
      expect(c.refiltering, {'buy-checklist'});

      c.cancelRefilter('buy-checklist');
      expect(c.offerFilters, {'displayType': '2'});
      expect(identical(c.blocks['sell-checklist'], sell), isTrue);
      expect(identical(c.blocks['buy-checklist'], buy), isTrue);
      expect(c.refiltering, isEmpty);
      // The late 求购 answer belongs to the cancelled filter and is dropped.
      port.buyGate!.complete();
      await change;
      expect(identical(c.blocks['buy-checklist'], buy), isTrue);
      // Single-item rows were never part of the change.
      expect(c.blocks['sell']!.rows.first['orderNumber'], 'SO1');
    },
  );

  // CX-HALL-CHECKLIST-A2-REVIEW-R2 P2: a second filter while 求购 still waits
  // on the first; cancelling must not pair the first filter with old rows.
  test(
    'A2: cancelling overlapping refilters restores one whole state',
    () async {
      final port = _Port();
      final c = MarketplaceController(port);
      addTearDown(c.dispose);
      await c.openItem(1);
      await c.setOfferChecklist(true);
      final sell = c.blocks['sell-checklist'], buy = c.blocks['buy-checklist'];
      port.buyGate = Completer<void>();
      final first = c.setOfferFilter('creatorStatus', '1');
      await pumpEventQueue();
      expect(identical(c.blocks['sell-checklist'], sell), isFalse);
      final second = c.setOfferFilter(
        'locationId',
        '7',
        location: const {'id': 7, 'name': 'Area18'},
      );
      await pumpEventQueue();
      expect(c.refiltering, contains('buy-checklist'));

      c.cancelRefilter('buy-checklist');
      // Both changes are undone together, rows and filters alike.
      expect(c.offerFilters, {'displayType': '2'});
      expect(c.offerLocation, isNull);
      expect(identical(c.blocks['sell-checklist'], sell), isTrue);
      expect(identical(c.blocks['buy-checklist'], buy), isTrue);
      expect(c.refiltering, isEmpty);
      port.buyGate!.complete();
      await Future.wait([first, second]);
      expect(identical(c.blocks['sell-checklist'], sell), isTrue);
      expect(identical(c.blocks['buy-checklist'], buy), isTrue);
      expect(c.blocks['sell']!.rows.first['orderNumber'], 'SO1');
    },
  );

  // CX-HALL-CHECKLIST-A2-REVIEW P2: the language switch skipped checklists.
  test(
    'A2: a language change rereads checklists with the current filters',
    () async {
      final port = _Port();
      final c = MarketplaceController(port);
      addTearDown(c.dispose);
      await c.initialize();
      await c.openItem(1);
      await c.setOfferFilter('creatorStatus', '1');
      await c.setOfferChecklist(true);
      port.calls.clear();
      await c.changeLocale('en');
      final offers = port.calls.where((e) => e.$1 == 'offers').toList();
      expect(offers.map((e) => e.$2).toSet(), {0, 1});
      for (final call in offers) {
        expect(call.$3, {'displayType': '2', 'creatorStatus': '1'});
        expect(call.$4, 'EN');
      }
      expect(c.blocks['sell-checklist']!.rows.single['orderNumber'], 'SOLIST1');
      // A next page now reads in the same language as the first.
      await c.moreOffers(false);
      expect(port.calls.last.$4, 'EN');
      expect(port.calls.last.$3['displayType'], '2');
    },
  );
}
