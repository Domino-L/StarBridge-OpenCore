import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_item_components.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_details.dart';

import 'marketplace_test.dart' show FixturePort, app;

/// Item-page buy offers carry the fused "需要｜≥tier" tag, which overflowed the
/// 64px quality column. User choice 2026-11-12 (方案 1): the buy tab gets a
/// wider quality column; the sell tab keeps its 64px. Below 200 neither
/// tab's tag names its tier; the tooltip does (user choices 2026-11-12).
MarketRow _offer(int i, int side, int quality) => {
  'orderNumber': 'Q$side$i',
  'displayType': 1,
  'creatorType': side,
  'itemName': '测试物品 1',
  'seller': 'Trader$i',
  'remainingQuantity': 3 + i,
  'unitPrice': '${1200000 - i * 25000}',
  'items': [
    {
      'itemId': 1,
      'itemName': '测试物品 1',
      'qualityData': '{"type":"material","quality":$quality}',
    },
  ],
};

class _Port extends FixturePort {
  _Port([this.qualities = const [980, 980, 900, 700]]);
  final List<int> qualities;
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
    if (operation == 'offers') {
      final rows = [
        for (var i = 0; i < qualities.length; i++)
          _offer(i + 1, side, qualities[i]),
      ];
      return MarketRead({
        'rows': rows,
        'total': rows.length,
      }, DateTime.utc(2026, 11, 12));
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

Finder _qualityColumns(double width) => find.descendant(
  of: find.byType(ItemOfferColumns),
  matching: find.byWidgetPredicate(
    (w) => w is SizedBox && w.width == width && w.child is Align,
  ),
);

void main() {
  // Real fonts: the default test font draws every glyph as a square, much
  // wider than the client's text, so widths are measured as users see them.
  setUpAll(() async {
    for (final (family, file) in [
      ('Source Sans 3', 'assets/fonts/SourceSans3VF-Upright.ttf'),
      ('Saira', 'assets/fonts/Saira-VF.ttf'),
      ('Rajdhani', 'assets/fonts/Rajdhani-SemiBold.ttf'),
      ('Source Han Sans CN', 'assets/fonts/SourceHanSansCN-VF.ttf'),
      ('Source Code Pro', 'assets/fonts/SourceCodeVF-Upright.ttf'),
    ]) {
      final bytes = File(file).readAsBytesSync();
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  for (final width in [1280.0, 1440.0, 1600.0]) {
    testWidgets('buy-tab quality tags fit their column at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = MarketplaceController(_Port());
      addTearDown(c.dispose);
      await tester.pumpWidget(
        app(c, AppearanceMode.dark, const Locale('zh', 'CN')),
      );
      await _settle(tester);
      await c.openItem(1);
      await _settle(tester);

      // Sell tab: unchanged 64px column.
      expect(tester.takeException(), isNull, reason: 'sell tab at $width');
      expect(_qualityColumns(64), findsWidgets);
      expect(_qualityColumns(112), findsNothing);

      c.selectItemTab(1);
      await _settle(tester);
      expect(
        tester.takeException(),
        isNull,
        reason: 'no overflow on the buy tab at $width',
      );
      final needs = find.byKey(const Key('market-quality-needs'));
      expect(needs, findsWidgets, reason: 'buy rows show 需要');
      // Header plus every visible row use the wider column.
      expect(_qualityColumns(112), findsWidgets);
      expect(_qualityColumns(64), findsNothing);
      for (final column in _qualityColumns(112).evaluate()) {
        final box = column.renderObject! as RenderBox;
        final left = box.localToGlobal(Offset.zero).dx;
        final right = left + box.size.width;
        for (final tag
            in find
                .descendant(
                  of: find.byWidget(column.widget),
                  matching: find.byType(MarketQualityBadge),
                )
                .evaluate()) {
          final r = (tag.renderObject! as RenderBox).paintBounds.shift(
            (tag.renderObject! as RenderBox).localToGlobal(Offset.zero),
          );
          expect(r.left, greaterThanOrEqualTo(left - .5));
          expect(r.right, lessThanOrEqualTo(right + .5));
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  // CX-HALL-BUY-QUALITY-COLUMN-REVIEW P2: below 200 a tag also named its tier
  // ("≥100 劣质"), too wide even for 112px. User choice 2026-11-12 (方案 2):
  // buy tags drop that name; the tooltip and screen reader keep it, and sell
  // tags are unchanged.
  for (final (locale, tier) in const [
    (Locale('zh', 'CN'), '劣质'),
    (
      Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'TW',
      ),
      '劣質',
    ),
    (Locale('en'), 'Inferior'),
  ]) {
    testWidgets('low buy tags fit without the tier name in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = MarketplaceController(_Port(const [199, 150, 100, 0]));
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c, AppearanceMode.dark, locale));
      await _settle(tester);
      await c.openItem(1);
      await _settle(tester);
      // User choice 2026-11-12 ("和求购一样不写档位名"): low sell tags drop
      // the tier name too, so "199 Inferior" no longer overflows the sell
      // tab's 64px column.
      expect(tester.takeException(), isNull, reason: 'sell tab in $locale');
      expect(_qualityColumns(64), findsWidgets);
      // The tier strip above the list still names the bands; the tags don't.
      expect(
        find.descendant(
          of: find.byType(MarketQualityBadge),
          matching: find.textContaining(tier),
        ),
        findsNothing,
      );
      for (final q in ['199', '150', '100', '0']) {
        expect(find.text(q), findsOneWidget, reason: 'sell $q');
      }
      _expectTierInTooltips(tester, tier, 64);

      c.selectItemTab(1);
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'no overflow in $locale');
      expect(find.byKey(const Key('market-quality-needs')), findsWidgets);
      expect(find.textContaining(tier), findsNothing);
      for (final q in ['≥199', '≥150', '≥100', '≥0']) {
        expect(find.text(q), findsOneWidget, reason: q);
      }
      _expectTierInTooltips(tester, tier, 112);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('quality tags outside the item column keep the tier name in '
        '$locale', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark),
            locale,
          ),
          home: const Scaffold(
            body: MarketQualityBadge({
              'qualityData': {'type': 'material', 'quality': 150},
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('150 $tier'), findsOneWidget);
    });
  }
}

void _expectTierInTooltips(WidgetTester tester, String tier, double column) {
  final badges = find.byType(MarketQualityBadge);
  expect(badges, findsNWidgets(4));
  for (final badge in badges.evaluate()) {
    expect(
      (badge.renderObject! as RenderBox).size.width,
      lessThanOrEqualTo(column),
    );
    final tooltip = find.descendant(
      of: find.byWidget(badge.widget),
      matching: find.byType(Tooltip),
    );
    expect(tester.widget<Tooltip>(tooltip).message, tier);
    expect(
      find.descendant(
        of: find.byWidget(badge.widget),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.label ?? '').contains(tier),
        ),
      ),
      findsOneWidget,
    );
  }
}
