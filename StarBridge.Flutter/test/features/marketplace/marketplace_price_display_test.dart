// Regression (user report, build 10, 2026-10-20): in 市场·订单 the quality
// badge stretched across the name column and long prices were cut to
// "1,000,0…". Prices now read like the SCM site's 中文计数 (100万, 1.25亿),
// the badge hugs its value, and the filter options sit in an even grid.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_details.dart'
    show MarketQualityBadge;
import 'package:starbridge_flutter/features/marketplace/marketplace_market_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_widgets.dart';

import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_price_format.dart';

import 'marketplace_test.dart' show FixturePort, app;
import 'marketplace_trades_test.dart' show TradesPort;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

const _prices = [1000000, 12000000, 600000, 1234567, 125000000, 9500];

class _Port extends TradesPort {
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
  }) {
    if (operation == 'marketOrders' || operation == 'latest') {
      return Future.value(
        MarketRead({
          'rows': [
            for (var i = 0; i < _prices.length; i++)
              {
                'orderNumber': 'O$i',
                'itemId': i + 1,
                'itemName': '被辐射的瓦拉卡蠕虫珍珠（AAA级）$i',
                'availableQuantity': 14,
                'locationId': 1,
                'creatorType': i.isEven ? 1 : 0,
                'unitPrice': _prices[i],
                'seller': 'Fixture',
                'items': [
                  {
                    'itemId': i + 1,
                    'itemName': 'Fixture $i',
                    if (i.isEven)
                      'qualityData': {'type': 'material', 'quality': 880},
                  },
                ],
              },
          ],
          'total': _prices.length,
          'pageEnd': true,
        }, DateTime.utc(2026, 10, 20)),
      );
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
  testWidgets('prices abbreviate like the SCM site, per language', (
    tester,
  ) async {
    final out = <String, List<String>>{};
    for (final locale in const [
      Locale('zh', 'CN'),
      Locale('zh', 'TW'),
      Locale('en'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Builder(
            builder: (context) {
              out[locale.toLanguageTag()] = [
                for (final v in [
                  9500,
                  10000,
                  1000000,
                  1234567,
                  12000000,
                  125000000,
                  -20000,
                  null,
                ])
                  marketPrice(context, v),
              ];
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }
    expect(out['zh-CN'], [
      '9,500',
      '1万',
      '100万',
      '123.4567万',
      '1200万',
      '1.25亿',
      '-2万',
      '—',
    ]);
    expect(out['zh-TW'], [
      '9,500',
      '1萬',
      '100萬',
      '123.4567萬',
      '1200萬',
      '1.25億',
      '-2萬',
      '—',
    ]);
    expect(out['en'], [
      '9.5K',
      '10K',
      '1M',
      '1.2346M',
      '12M',
      '125M',
      '-20K',
      '—',
    ]);
  });

  test('every saved format writes prices like the SCM setting', () {
    List<String> all(String format, String locale) => [
      for (final v in [950, 9500, 1234567, 100000000, 2500000000000])
        marketPriceIn(v, format: format, locale: locale),
    ];
    expect(all('comma', 'cn'), [
      '950',
      '9,500',
      '1,234,567',
      '100,000,000',
      '2,500,000,000,000',
    ]);
    expect(all('intl', 'cn'), ['950', '9.5K', '1.2346M', '100M', '2.5T']);
    expect(all('chinese', 'cn'), ['950', '9,500', '123.4567万', '1亿', '2.5万亿']);
    expect(all('chinese', 'hant'), [
      '950',
      '9,500',
      '123.4567萬',
      '1億',
      '2.5萬億',
    ]);
    // An explicit choice wins over the UI language.
    expect(all('chinese', 'en'), all('chinese', 'cn'));
    expect(all('intl', 'hant'), all('intl', 'en'));
    expect(all('auto', 'cn'), all('chinese', 'cn'));
    expect(all('auto', 'en'), all('intl', 'en'));
  });

  testWidgets('显示设置 saves the format locally and every price follows it', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    final port = FixturePort();
    final c = MarketplaceController(port);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      app(c, AppearanceMode.dark, const Locale('zh', 'CN')),
    );
    await tester.pumpAndSettle();
    expect(c.priceFormat, 'auto', reason: 'files saved before the setting');

    await tester.tap(find.byKey(const Key('market-display-settings')));
    await tester.pumpAndSettle();
    expect(find.text('价格显示格式'), findsOneWidget);
    // Each choice shows what it does to real amounts, as the SCM page does.
    expect(find.text('¤ 123.4567万'), findsNWidgets(2)); // auto and 中文计数
    expect(find.text('¤ 1,234,567'), findsOneWidget);
    expect(find.text('¤ 1.2346M'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey(('market-price-format', 'comma'))),
    );
    await tester.pumpAndSettle();
    expect(c.priceFormat, 'comma');
    expect(port.prefs['priceFormat'], 'comma');
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey(('market-price-format', 'comma'))),
          )
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    await tester.tap(find.byKey(const Key('market-display-close')));
    await tester.pumpAndSettle();

    // Every price under the hall reads the saved choice.
    final scope = find.byType(MarketPriceFormatScope);
    expect(tester.widget<MarketPriceFormatScope>(scope).format, 'comma');
    final inside = tester.element(
      find.descendant(of: scope, matching: find.byType(Column)).first,
    );
    expect(marketPrice(inside, 1000000), '1,000,000');

    // A fresh visit restores it from the local file.
    final again = MarketplaceController(port);
    addTearDown(again.dispose);
    await again.readPreferences();
    expect(again.priceFormat, 'comma');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('order rows: badge hugs its value, prices are whole, grid even', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    final c = MarketplaceController(_Port());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      scopedApp(MarketplaceMarketPage(c), InteractionSuite.standard),
    );
    await tester.pumpAndSettle();
    await c.browser.choose(kind: 'orders');
    c.browser.setLayout('rows');
    await tester.pumpAndSettle();

    // Each badge is a small plate, not a bar across the name column.
    final badges = find.ancestor(
      of: find.text('880'),
      matching: find.byType(MarketQualityBadge),
    );
    expect(badges, findsNWidgets(3));
    for (var i = 0; i < 3; i++) {
      expect(tester.getSize(badges.at(i)).width, lessThan(80));
    }

    // Every price is drawn whole: no ellipsis, nothing past its line.
    for (final text in [
      '100万',
      '1200万',
      '60万',
      '123.4567万',
      '1.25亿',
      '9,500',
    ]) {
      final rich = find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().endsWith(text),
      );
      expect(rich, findsOneWidget, reason: text);
      final paragraph = tester.renderObject<RenderParagraph>(rich);
      expect(paragraph.didExceedMaxLines, isFalse, reason: text);
    }
    // Readers still hear the full amount.
    expect(find.bySemanticsLabel(RegExp('¤ 125,000,000')), findsWidgets);

    // 类型 options: two even rows of two, edges aligned.
    final rects = [
      for (final label in ['全部', '出售', '求购', '以物易物'])
        tester.getRect(
          find
              .ancestor(
                of: find.text(label).first,
                matching: find.byType(MarketToggle),
              )
              .first,
        ),
    ];
    expect(rects[0].top, rects[1].top);
    expect(rects[2].top, rects[3].top);
    expect(rects[2].top, greaterThan(rects[0].bottom));
    expect(rects[0].left, rects[2].left);
    expect(rects[1].right, rects[3].right);
    expect(rects[0].width, closeTo(rects[3].width, .5));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
