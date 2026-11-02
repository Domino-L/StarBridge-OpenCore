import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_details.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_widgets.dart';

import 'marketplace_test.dart' show FixturePort, app;

class ReputationPort extends FixturePort {
  ReputationPort(this.point);
  final int? point;
  bool failed = false;
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
    if (operation == 'reputation') {
      if (failed) throw StateError('unavailable');
      return MarketRead({'point': point}, DateTime.now());
    }
    return super.read(
      operation,
      id: id,
      keyword: keyword,
      category: category,
      side: side,
      page: page,
      language: language,
    );
  }
}

void main() {
  testWidgets(
    'empty focused search exposes history without adding hall sections',
    (tester) async {
      final port = FixturePort()
        ..prefs = {
          'revision': 0,
          'favorites': <int>[],
          'recentItems': [1],
          'recentSearches': ['ore'],
        };
      final c = MarketplaceController(port);
      await tester.pumpWidget(
        app(c, AppearanceMode.dark, const Locale('en', 'US')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Recent searches'), findsNothing);
      await tester.tap(find.byKey(const Key('marketplace-search')));
      await tester.pumpAndSettle();
      expect(find.text('Recent searches'), findsOneWidget);
      expect(find.text('Recently viewed'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('marketplace-search')),
        'new',
      );
      await tester.pumpAndSettle();
      expect(find.text('Recent searches'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  test(
    'quality keeps exact material value and ignores malformed/missing data',
    () {
      expect(
        marketQuality({'qualityData': '{"type":"material","quality":647}'}),
        '647',
      );
      expect(
        marketQuality({'qualityData': '{"type":"material","qualityMin":880}'}),
        '≥880',
      );
      expect(marketQuality({'qualityData': '{}'}), isNull);
      expect(marketQuality({'qualityData': 'oops'}), isNull);
    },
  );
  testWidgets(
    'unknown price has no currency suffix; genuine zero retains unit',
    (tester) async {
      for (final value in [null, 0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildStarBridgeTheme(
              FutureRestraintStyle.resolve(AppearanceMode.dark),
              const Locale('en', 'US'),
            ),
            home: Scaffold(body: MarketPrice(value)),
          ),
        );
        expect(find.text('UEC'), value == null ? findsNothing : findsOneWidget);
        expect(find.text(value == null ? '—' : '0'), findsOneWidget);
      }
    },
  );
  for (final point in [null, 0, 412]) {
    testWidgets('reputation $point visible only when freshly available', (
      tester,
    ) async {
      final port = ReputationPort(point);
      final c = MarketplaceController(port);
      await tester.pumpWidget(
        app(c, AppearanceMode.dark, const Locale('en', 'US')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('★ $point'),
        point == null ? findsNothing : findsOneWidget,
      );
      port.failed = true;
      await c.load('reputation', 'reputation');
      await tester.pumpAndSettle();
      expect(find.text('★ $point'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
  test('watch limit preserves 100 records and allows removal', () async {
    final port = FixturePort()
      ..prefs = {
        'revision': 0,
        'favorites': List.generate(100, (i) => i + 1),
        'recentItems': <int>[],
        'recentSearches': <String>[],
      };
    final c = MarketplaceController(port);
    await c.readPreferences();
    await c.toggleFavorite(101);
    expect(c.favoriteLimitReached, isTrue);
    expect(c.favorites.length, 100);
    await c.toggleFavorite(1);
    expect(c.favorites.length, 99);
    c.dispose();
  });
}
