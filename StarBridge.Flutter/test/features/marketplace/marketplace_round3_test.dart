import 'package:flutter/material.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_details.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_widgets.dart';

import 'marketplace_test.dart' show app, FixturePort;

Widget themed(Widget child, AppearanceMode mode) => MaterialApp(
  locale: const Locale('en', 'US'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(mode),
    const Locale('en', 'US'),
  ),
  home: Scaffold(body: child),
);

void main() {
  testWidgets(
    'item headers disappear for empty offers and watch retains its heart affordance',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = MarketplaceController(FixturePort());
      await tester.pumpWidget(
        app(c, AppearanceMode.dark, const Locale('en', 'US')),
      );
      await tester.pumpAndSettle();
      await c.openItem(1);
      await tester.pumpAndSettle();
      expect(find.text('Trading hours'), findsOneWidget);
      expect(find.text('Not provided'), findsWidgets);
      expect(find.text('Not set'), findsWidgets);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      c.blocks['sell'] = MarketRead({
        'rows': <MarketRow>[],
        'total': 0,
      }, DateTime.now());
      c.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Trading hours'), findsNothing);
      expect(find.text('Nobody is selling this item yet'), findsOneWidget);
      tester.view.physicalSize = const Size(900, 800);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  test(
    'latest rows are complete at every column count, except sparse first row',
    () {
      for (var columns = 1; columns <= 8; columns++) {
        for (var count = 0; count <= 20; count++) {
          final visible = marketCompleteRowCount(count, columns);
          expect(visible, lessThanOrEqualTo(count));
          expect(visible, lessThanOrEqualTo(columns * 2));
          expect(
            count < columns ? visible == count : visible % columns == 0,
            isTrue,
          );
        }
      }
      expect(marketCompleteRowCount(8, 5), 5);
    },
  );
  testWidgets(
    'quality thresholds and minimum ranges use the five token bands',
    (tester) async {
      for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
        final tokens = FutureRestraintStyle.resolve(mode);
        for (final value in [
          199,
          200,
          399,
          400,
          599,
          600,
          647,
          799,
          800,
          880,
          909,
        ]) {
          await tester.pumpWidget(
            themed(
              MarketQualityBadge({
                'qualityData': {'type': 'material', 'qualityMin': value},
              }),
              mode,
            ),
          );
          await tester.pumpAndSettle();
          final text = tester.widget<Text>(find.textContaining('≥$value'));
          expect(
            text.style!.color,
            value >= 800
                ? tokens.domainColors.industry.foreground
                : value >= 600
                ? tokens.domainColors.recon.foreground
                : value >= 400
                ? tokens.colors.textSecondary
                : tokens.colors.textDisabled,
          );
          expect(
            find.textContaining('Inferior'),
            value < 200 ? findsOneWidget : findsNothing,
          );
        }
      }
    },
  );
  testWidgets('cards omit absent location and hours, skeleton has no text', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(
        SizedBox(
          width: 210,
          height: 280,
          child: MarketCard({
            'itemNameEn': 'Test',
            'seller': 'T***r',
            'point': 0,
            'presence': 'offline',
            'unitPrice': 100,
            'remainingQuantity': 1,
          }, open: () {}),
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Not provided'), findsNothing);
    expect(find.text('Not set'), findsNothing);
    expect(
      tester.widget<MarketTrader>(find.byType(MarketTrader)).compact,
      isTrue,
    );
    expect(find.text(' ★ 0'), findsOneWidget);
    await tester.pumpWidget(
      themed(const MarketSkeleton(kind: 'quotes'), AppearanceMode.dark),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsNothing);
    expect(find.bySemanticsLabel('Loading…'), findsOneWidget);
  });
  testWidgets('watch differentiates empty sell, highest buy and failed read', (
    tester,
  ) async {
    final port = FixturePort()
      ..prefs = {
        'revision': 0,
        'favorites': [1],
        'recentItems': <int>[],
        'recentSearches': <String>[],
      };
    final c = MarketplaceController(port);
    await tester.pumpWidget(
      app(c, AppearanceMode.dark, const Locale('en', 'US')),
    );
    await tester.pumpAndSettle();
    c.blocks['watch-price:1'] = MarketRead({
      'rows': <MarketRow>[],
    }, DateTime.now());
    c.blocks['watch-buy:1'] = MarketRead({
      'rows': [
        {'unitPrice': '500000'},
      ],
    }, DateTime.now());
    c.notifyListeners();
    await tester.pumpAndSettle();
    // The watch strip sits near the top of the hall now (G3, 0.7.2).
    expect(find.text('No sell offers'), findsOneWidget);
    expect(find.textContaining('500,000 UEC'), findsOneWidget);
    final watch = find.byKey(const ValueKey<(String, int)>(('market-watch-row', 1)));
    expect(watch, findsOneWidget);
    expect(
      find.descendant(of: watch, matching: find.textContaining('—')),
      findsNothing,
    );
    c.failures.add('watch-price:1');
    c.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('No sell offers'), findsNothing);
    expect(find.text('Temporarily unavailable'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  // User 10-27 (backlog 30): the "最低卖价" label sat on the item name. The
  // label and the price now share one line under the name.
  testWidgets('watch: the lowest-ask label and price stay under the name', (
    tester,
  ) async {
    final port = FixturePort()
      ..prefs = {
        'revision': 0,
        'favorites': [1],
        'recentItems': <int>[],
        'recentSearches': <String>[],
      };
    final c = MarketplaceController(port);
    await tester.pumpWidget(
      app(c, AppearanceMode.dark, const Locale('zh', 'CN')),
    );
    await tester.pumpAndSettle();
    c.blocks['watch-price:1'] = MarketRead({
      'rows': [
        {'unitPrice': '1000000'},
      ],
    }, DateTime.now());
    c.notifyListeners();
    await tester.pumpAndSettle();
    final watch = find.byKey(const ValueKey<(String, int)>(('market-watch-row', 1)));
    final price = find.byKey(const ValueKey<(String, int)>(('market-watch-price', 1)));
    expect(price, findsOneWidget);
    final label = find.descendant(of: price, matching: find.text('最低卖价'));
    expect(label, findsOneWidget);
    final texts = tester.widgetList<Text>(
      find.descendant(of: watch, matching: find.byType(Text)),
    );
    final name = find.descendant(
      of: watch,
      matching: find.byWidget(texts.first),
    );
    final nameRect = tester.getRect(name);
    final priceRect = tester.getRect(price);
    expect(priceRect.top, greaterThanOrEqualTo(nameRect.bottom - .5),
        reason: 'the price line starts below the name');
    expect(tester.getRect(label).overlaps(nameRect), isFalse);
    expect(tester.getRect(label).left, lessThan(priceRect.left + 1),
        reason: 'the label leads the price line');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
