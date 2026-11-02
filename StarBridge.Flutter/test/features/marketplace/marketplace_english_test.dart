// 0.7.2: in English the trading hall shows no Chinese of its own (user
// report on build 19: "我选的是英语"). SCM content such as item, member and
// contract text may stay as SCM sent it; everything the client writes may not.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_contracts_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_publish.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_order_detail.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_chat_view.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_chat_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_profile.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_warehouse_page.dart';

import '../friends/social_layout_test.dart' show size;
import 'marketplace_contracts_page_test.dart' show ContractsPort;
import 'marketplace_slice4_test.dart' show ListingsFixture;
import 'marketplace_test.dart' show FixturePort, app;
import 'marketplace_trade_chat_view_test.dart' show ChatPort;
import 'marketplace_trade_profile_test.dart' show fixtureProfile;
import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_warehouse_page_test.dart' show WarehousePort;

// Ideographs and Chinese punctuation; full-width symbols such as ＋ are fine.
final _chinese = RegExp(r'[㐀-鿿　-〿！（），：；？]');

/// SCM and user content from the fixtures (longest first); whatever is left
/// of a text must be English.
const _content = [
  '科力晶（单个矿块）×2',
  '科力晶（单个矿块）',
  'TS-35 婆娑罗（3.5倍光学）',
  '被辐射的瓦拉卡蠕虫珍珠（AAA级）',
  'HG-15 猎人（1.5倍全息）',
  '实准 枪口补偿器 3',
  '测试物品',
  '科力晶',
  '測試物品',
  '分类',
  '默认仓位',
  '矿石仓',
  '新巴贝奇 · 微科星',
  '洛维尔 · 斯坦顿',
  '新巴贝奇',
  '上架中',
  '找到并拦截 @R***m 的货船（Hull C，哈索航线）',
  '帮忙从新巴贝奇运 96 SCU 医疗物资到洛维尔',
  '周末舰队采矿：需要 2 名 Prospector 和 1 名护航',
  '周末舰队采矿',
  '按产量分成（量子燃料 + 矿石 30%）',
  '清剿克罗地区海盗前哨',
  '运 40 SCU 钛到微科星',
  '分成',
  '哈索 · 斯坦顿',
  '目标会在本周六 20:00 前后从哈索出发。',
  '拦截后需要提供截图作为完成凭证。',
  '确认目标航线',
  '拦截并提交截图',
  '今晚 9 点新巴贝奇可以吗？',
  '好的，我先发货',
  '[订单] 伊莫德 枪口稳定器',
  '只在 SCM 里交易，谢谢。',
  '加个微信聊吧 http://pay-scm.example/abc',
  '有的，两块，单价 60 万。',
  '你好，科力晶还有吗？',
  '待发货',
  '刷单',
  '每天 19:00–22:00',
];

Widget _en(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('en', 'US'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    const Locale('en', 'US'),
  ),
  builder: (context, child) => StarBridgeInteractionConfiguration(
    suite: InteractionSuite.scan,
    child: child!,
  ),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(24), child: child),
  ),
);

/// Every visible text, tooltip and semantics label still holding Chinese
/// after the fixture content is taken out.
Set<String> _chineseOnScreen(WidgetTester tester, String where) {
  final found = <String>{};
  void check(String? text) {
    if (text == null) return;
    var rest = text;
    for (final part in [..._content]..sort((a, b) => b.length - a.length)) {
      rest = rest.replaceAll(part, '');
    }
    if (_chinese.hasMatch(rest)) found.add('$where: $text');
  }

  for (final widget in tester.allWidgets) {
    switch (widget) {
      case RichText(:final text):
        check(text.toPlainText());
      case Tooltip(:final message):
        check(message);
      case Semantics(:final properties):
        check(properties.label);
      default:
    }
  }
  return found;
}

void main() {
  final seen = <String>{};
  tearDownAll(() {
    if (seen.isNotEmpty) {
      // ignore: avoid_print
      print('CHINESE_IN_ENGLISH ${seen.length}\n${seen.join('\n')}');
    }
  });

  testWidgets('hall, market, item, my activity: English only', (tester) async {
    size(tester, const Size(1440, 1000));
    final c = MarketplaceController(FixturePort());
    await tester.pumpWidget(app(c, AppearanceMode.dark, const Locale('en')));
    await tester.pumpAndSettle();
    seen.addAll(_chineseOnScreen(tester, 'hall'));
    for (final tab in [1, 2, 3, 4, 5]) {
      c.tab(tab);
      await tester.pumpAndSettle();
      seen.addAll(_chineseOnScreen(tester, 'tab $tab'));
    }
    await c.openItem(1);
    for (final tab in [0, 1, 2, 3]) {
      c.selectItemTab(tab);
      await tester.pumpAndSettle();
      seen.addAll(_chineseOnScreen(tester, 'item tab $tab'));
    }
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets('my trades: English only', (tester) async {
    size(tester, const Size(1440, 1000));
    final c = MarketplaceController(TradesPort());
    await tester.pumpWidget(app(c, AppearanceMode.dark, const Locale('en')));
    await tester.pumpAndSettle();
    for (final tab in [3, 5]) {
      c.tab(tab);
      await tester.pumpAndSettle();
      seen.addAll(_chineseOnScreen(tester, 'trades tab $tab'));
    }
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(const Duration(seconds: 31));
  });

  for (final step in [0, 1, 2, 3]) {
    testWidgets('publish wizard step $step: English only', (tester) async {
      size(tester, const Size(1280, 900));
      {
        final c = MarketplaceListingsController(ListingsFixture());
        await c.refresh();
        await tester.pumpWidget(
          _en(
            ListingPublishDialog(
              c,
              ListingDraft(
                item: {'id': 1, 'name': 'Fixture', 'best': 1200000},
                location: '1',
                price: '1,250,000',
                quality: '702',
              ),
              initialStep: step,
              editProfile: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        seen.addAll(_chineseOnScreen(tester, 'publish step $step'));
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    });
  }

  testWidgets('contracts and warehouse: English only', (tester) async {
    size(tester, const Size(1440, 900));
    final contracts = MarketplaceController(ContractsPort());
    addTearDown(contracts.dispose);
    await tester.pumpWidget(_en(MarketplaceContractsPage(contracts)));
    await tester.pumpAndSettle();
    seen.addAll(_chineseOnScreen(tester, 'contracts'));
    await tester.tap(
      find.byKey(const ValueKey(('market-contract-card', '17'))),
    );
    await tester.pumpAndSettle();
    seen.addAll(_chineseOnScreen(tester, 'contract detail'));
    await tester.tap(find.byKey(const ValueKey(('market-contracts-view', 1))));
    await tester.pumpAndSettle();
    seen.addAll(_chineseOnScreen(tester, 'contracts mine'));
    await tester.tap(find.byKey(const ValueKey(('market-contracts-view', 0))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('market-contracts-publish')));
    await tester.pumpAndSettle();
    seen.addAll(_chineseOnScreen(tester, 'contract publish'));

    final warehouse = MarketplaceController(WarehousePort());
    addTearDown(warehouse.dispose);
    await tester.pumpWidget(_en(MarketplaceWarehousePage(warehouse)));
    await tester.pumpAndSettle();
    seen.addAll(_chineseOnScreen(tester, 'warehouse'));
    for (final view in [1, 2]) {
      await tester.tap(find.byKey(ValueKey(('market-warehouse-view', view))));
      await tester.pumpAndSettle();
      seen.addAll(_chineseOnScreen(tester, 'warehouse view $view'));
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('trade chat, trade profile, order detail: English only', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    final chat = MarketplaceChatController(ChatPort());
    addTearDown(chat.dispose);
    await tester.pumpWidget(
      _en(MarketplaceTradeChatView(chat, header: const SizedBox())),
    );
    await tester.pumpAndSettle();
    for (final ref in ['p1', 'p3']) {
      await tester.tap(find.byKey(ValueKey(('trade-chat-conversation', ref))));
      await tester.pumpAndSettle();
      seen.addAll(_chineseOnScreen(tester, 'trade chat $ref'));
    }

    await tester.pumpWidget(
      _en(
        TradeProfileForm(
          read: () async => fixtureProfile(),
          zones: () async => [
            {'id': 1, 'label': 'UTC +08:00', 'offsetMinutes': 480},
          ],
          current: () => true,
          write: (_) async => {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    seen.addAll(_chineseOnScreen(tester, 'trade profile'));

    final market = MarketplaceController(FixturePort());
    addTearDown(market.dispose);
    await tester.pumpWidget(
      _en(
        SizedBox(
          height: 800,
          child: MarketOrderDetail(market, {
            ...FixturePort.item(1),
            'id': 40,
            'orderNumber': 'SO88',
            'creatorType': 1,
            'displayType': 1,
            'unitPrice': 900000,
            'remainingQuantity': 3,
            'seller': 'F*****e',
            'tradeStartTime': '19:00',
            'tradeEndTime': '23:00',
            'tradeTime': [1, 1, 1, 1, 1, 1, 1],
            'timezoneId': 1,
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    seen.addAll(_chineseOnScreen(tester, 'order detail'));
    await tester.pumpWidget(const SizedBox());
  });

  test('nothing above showed client Chinese in English', () {
    expect(seen, isEmpty, reason: seen.join('\n'));
  });
}
