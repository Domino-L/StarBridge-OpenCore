import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_browser.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_details.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

import 'marketplace_test.dart' show FixturePort, app;

class BrowsePort extends FixturePort {
  final requests = <String>[];
  Map<String, String> lastOptions = {};
  bool fail = false;
  static final categories = <MarketRow>[
    {
      'id': 3,
      'parentId': 0,
      'name': '武器',
      'nameEn': 'Weapons',
      'filterConfig': jsonEncode({
        'filters': [
          {
            'type': 'enum',
            'label': '武器类型',
            'labelEn': 'Weapon type',
            'jsonPath': r'$.kind',
            'options': [
              {'value': 'rifle', 'label': '步枪', 'labelEn': 'Rifle'},
            ],
          },
        ],
        'sorts': [],
      }),
    },
    {'id': 31, 'parentId': 3, 'name': '单兵武器', 'nameEn': 'Personal weapons'},
    {'id': 6, 'parentId': 0, 'name': '涂装', 'nameEn': 'Paints'},
  ];
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
    requests.add(operation);
    lastOptions = options;
    if (operation == 'categories') {
      return MarketRead({
        'rows': categories,
        'total': 422,
      }, DateTime.utc(2026, 10, 16));
    }
    if (operation == 'marketItems' || operation == 'marketOrders') {
      if (fail) throw StateError('offline');
      return MarketRead({
        'rows': List.generate(
          20,
          (i) => {
            'id': page * 100 + i,
            'itemName': '测试物品 $i',
            'itemNameEn': 'Item $i',
            'sellOrderCount': 0,
            'buyOrderCount': 1,
            'seller': 'T*****r',
            'presence': 'online',
            'point': 0,
            'creatorType': 1,
            'displayType': 1,
            'remainingQuantity': 5,
            'unitPrice': '1234567',
            'createTime': DateTime.now()
                .subtract(const Duration(days: 3))
                .millisecondsSinceEpoch,
            'tradeTime': '[1,1,1,1,1,1,1]',
            'tradeStartTime': '09:00',
            'tradeEndTime': '18:00',
            'items': [
              {'itemId': page * 100 + i, 'itemName': '测试物品 $i'},
            ],
          },
        ),
        'total': 40,
        'allTotal': 422,
      }, DateTime.utc(2026, 10, 16));
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

void main() {
  testWidgets('market top search applies keyword without opening a quote', (
    tester,
  ) async {
    final c = MarketplaceController(BrowsePort());
    await tester.pumpWidget(
      app(c, AppearanceMode.dark, const Locale('zh', 'CN')),
    );
    await tester.pumpAndSettle();
    await c.marketCategory(31);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('marketplace-search')), 'ore');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.browser.keyword, 'ore');
    expect(c.browser.listed, false);
    expect(c.itemId, isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  test(
    'category inheritance, listed defaults, pagination and failed refresh',
    () async {
      final p = BrowsePort();
      final model = MarketplaceBrowser(p);
      await model.initialize(BrowsePort.categories);
      await model.choose(category: 31);
      expect(model.config['filters'], isNotEmpty);
      expect(p.lastOptions['minOrderCount'], '1');
      await model.choose(keyword: 'ore');
      expect(p.lastOptions.containsKey('minOrderCount'), false);
      await model.reload(more: true);
      expect(model.result!.rows.length, 40);
      p.fail = true;
      await model.reload();
      expect(model.result!.rows.length, 40);
      expect(model.failed, true);
      expect(p.requests.contains('offers'), false);
      model.dispose();
    },
  );
  for (final width in [676.0, 1056.0, 1376.0]) {
    testWidgets('market layout and readonly panel at content width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 736);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = MarketplaceController(BrowsePort());
      await tester.pumpWidget(
        app(c, AppearanceMode.dark, const Locale('zh', 'CN')),
      );
      await tester.pumpAndSettle();
      c.tab(1);
      await tester.pumpAndSettle();
      await c.browser.choose(category: 31);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (width < 900) {
        await tester.tap(find.text('分类与筛选'));
        await tester.pumpAndSettle();
        expect(find.text('武器类型'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('武器类型'), findsNothing);
      }
      await c.browser.choose(kind: 'orders');
      // The table layout: cards (the default since build 11) always show age.
      c.browser.setLayout('rows');
      await tester.pumpAndSettle();
      expect(find.text('3 天前'), width < 900 ? findsNothing : findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('测试物品 0').first);
      await tester.pumpAndSettle();
      expect(find.text('查看物品'), findsOneWidget);
      expect(find.text('每天 09:00–18:00'), findsWidgets);
      expect(find.text('购买'), findsNothing);
      await tester.tap(find.text('查看物品'));
      await tester.pumpAndSettle();
      expect(c.itemId, 100);
      c.back();
      await tester.pumpAndSettle();
      expect(c.mainTab, 1);
      expect(c.browser.kind, 'orders');
      expect(c.browser.layout, 'rows');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
  testWidgets('market scroll filters and layouts survive item roundtrips', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1056, 736);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = MarketplaceController(BrowsePort());
    await tester.pumpWidget(
      app(c, AppearanceMode.dark, const Locale('zh', 'CN')),
    );
    await tester.pumpAndSettle();
    await c.marketCategory(31);
    await c.browser.filter(r'enum:$.kind', 'rifle');
    c.browser.setLayout('rows');
    await c.saveView();
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('market-results'));
    await tester.drag(list, const Offset(0, -450));
    await tester.pumpAndSettle();
    final position = c.browser.offset;
    expect(position, greaterThan(100));
    for (var i = 0; i < 3; i++) {
      await c.openItem(100);
      await tester.pumpAndSettle();
      c.back();
      await tester.pumpAndSettle();
      final scroll = tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          )
          .position;
      expect(scroll.pixels, closeTo(position, 1));
      expect(c.browser.category, 31);
      expect(c.browser.options[r'enum:$.kind'], 'rifle');
      expect(c.browser.layout, 'rows');
    }
    await c.browser.choose(category: 6);
    expect(c.browser.config, isEmpty);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('TH-22 unified days and all-day formatting', (tester) async {
    final values = <String>[];
    final c = MarketplaceController(FixturePort());
    await tester.pumpWidget(
      app(c, AppearanceMode.dark, const Locale('zh', 'CN')),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold));
    for (final days in [
      '[1,1,1,1,1,1,1]',
      '[1,1,1,1,1,0,0]',
      '[0,0,0,0,0,1,1]',
      '[1,1,1,0,1,0,0]',
    ]) {
      values.add(
        marketTradeTime(context, {
          'tradeTime': days,
          'tradeStartTime': '00:00',
          'tradeEndTime': '23:59',
        }),
      );
    }
    expect(values, ['每天 全天', '工作日 全天', '周末 全天', '周一至周三、周五 全天']);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
