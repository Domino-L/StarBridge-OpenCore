import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_widgets.dart';

class FixturePort implements MarketplacePort {
  @override
  bool available = true;
  @override
  int generation = 1;
  bool failTrend = false;
  bool emptyLists = false;
  Completer<void>? readGate, saveGate;
  Completer<MarketRead>? delayed;
  MarketRow prefs = {
    'revision': 0,
    'favorites': <int>[],
    'recentItems': <int>[],
    'recentSearches': <String>[],
  };
  @override
  Future<MarketRow> preferences([MarketRow? value]) async {
    if (value != null) {
      await saveGate?.future;
      if (value['revision'] != prefs['revision']) {
        throw StateError('Revision conflict');
      }
      prefs = {...value, 'revision': (prefs['revision'] as int) + 1};
    }
    return prefs;
  }

  static MarketRow item(int id) => {
    'id': id,
    'itemName': '测试物品 $id',
    'itemNameHant': '測試物品 $id',
    'itemNameEn': 'Fixture item $id',
  };
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
    await readGate?.future;
    if (operation == 'trend' && failTrend) throw StateError('unavailable');
    if (operation == 'search' && delayed != null) return delayed!.future;
    final data = switch (operation) {
      'item' => item(id),
      'categories' => {
        'rows': List.generate(
          9,
          (i) => {
            'id': i + 1,
            'parentId': 0,
            'name': '分类 ${i + 1}',
            'nameEn': 'Category ${i + 1}',
          },
        ),
        'total': 9000,
      },
      'trending' => {
        'rows': List.generate(15, (i) => {...item(i + 1), 'price': '1234567'}),
      },
      'latest' => {
        'rows': List.generate(
          20,
          (i) => {
            ...item(i + 1),
            'seller': 'F*****e',
            'remainingQuantity': 10,
            'unitPrice': '900000',
          },
        ),
      },
      'search' => {'rows': List.generate(20, (i) => item(i + 1)), 'total': 60},
      'offers' => {
        'rows': List.generate(
          20,
          (i) => {
            'seller': 'Trader $i',
            'unitPrice': '1000000',
            'presence': 'offline',
          },
        ),
        'total': 60,
      },
      _ => {'rows': <MarketRow>[]},
    };
    return MarketRead(
      emptyLists && data.containsKey('rows')
          ? {'rows': <MarketRow>[], 'total': 0}
          : data,
      DateTime.utc(2026, 10, 15),
    );
  }

  @override
  void dispose() {}
}

Widget app(MarketplaceController c, AppearanceMode appearance, Locale locale) =>
    MaterialApp(
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(appearance),
        locale,
      ),
      home: RepaintBoundary(
        key: const Key('market-render'),
        child: Scaffold(body: MarketplacePage(c)),
      ),
    );

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('MARKET_CAPTURE')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('market-render')),
  );
  await tester.runAsync(() async {
    final picture = await boundary.toImage();
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory(
      '../.artifacts/trading-hall-intake-20261015/renders',
    );
    await folder.create(recursive: true);
    await File('${folder.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final (family, file) in [
      ('Source Sans 3', 'SourceSans3VF-Upright.ttf'),
      ('Saira', 'Saira-VF.ttf'),
      ('Rajdhani', 'Rajdhani-SemiBold.ttf'),
      ('Source Han Sans CN', 'SourceHanSansCN-VF.ttf'),
      ('Source Code Pro', 'SourceCodeVF-Upright.ttf'),
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$file'))).load();
    }
  });
  test('unknown values remain unknown and Hant only affects display', () {
    expect(marketMoney(null), '—');
    expect(marketMoney(0), '0');
    expect(marketMoney('1234567'), '1,234,567');
    final row = FixturePort.item(1);
    expect(marketName(row, 'hant'), '測試物品 1');
    expect(row['itemName'], '测试物品 1');
    expect(row['id'], 1);
  });
  test('late catalog cannot cross account generation', () async {
    final port = FixturePort()..delayed = Completer();
    final c = MarketplaceController(port);
    final request = c.browse(query: 'original');
    c.contextChanged();
    port.delayed!.complete(
      MarketRead({
        'rows': [FixturePort.item(1)],
      }, DateTime.now()),
    );
    await request;
    expect(c.blocks, isEmpty);
    expect(c.keyword, isEmpty);
    c.dispose();
  });
  test('local mutations serialize without dropping recent items', () async {
    final c = MarketplaceController(FixturePort());
    await c.readPreferences();
    await Future.wait([
      c.remember(1, 'one'),
      c.remember(2, 'two'),
      c.toggleFavorite(3),
    ]);
    expect(c.recentItems, [2, 1]);
    expect(c.favorites, [3]);
    c.dispose();
  });
  for (final width in [900.0, 1280.0, 1600.0]) {
    for (final appearance in [AppearanceMode.dark, AppearanceMode.light]) {
      for (final locale in AppStrings.supportedLocales) {
        testWidgets(
          '$width $appearance $locale hall and item have no overflow or write actions',
          (tester) async {
            tester.view.physicalSize = Size(width, 1000);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final port = FixturePort();
            final c = MarketplaceController(port);
            await tester.pumpWidget(app(c, appearance, locale));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (locale.countryCode == 'CN') {
              await capture(
                tester,
                'fixture-hall-${width.toInt()}-${appearance.name}',
              );
            }
            await c.openItem(1);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (locale.countryCode == 'CN') {
              await capture(
                tester,
                'fixture-item-${width.toInt()}-${appearance.name}',
              );
            }
            expect(find.text('购买'), findsNothing);
            expect(find.text('发布'), findsNothing);
            expect(find.text('Purchase'), findsNothing);
            expect(find.text('Publish'), findsNothing);
            // Virtualized quotes do not construct off-screen records.
            expect(find.text('Trader 19'), findsNothing);
            await tester.tap(find.byKey(const Key('marketplace-back')));
            await tester.pumpAndSettle();
            expect(c.itemId, isNull);
            await tester.pumpWidget(const SizedBox());
            c.dispose();
          },
        );
      }
    }
  }
  testWidgets('trend failure offers retry and recovers to honest empty state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = FixturePort()..failTrend = true;
    final c = MarketplaceController(port);
    await tester.pumpWidget(
      app(c, AppearanceMode.dark, const Locale('en', 'US')),
    );
    await tester.pumpAndSettle();
    await c.openItem(1);
    c.selectItemTab(2);
    await tester.pumpAndSettle();
    expect(find.text('Price history is unavailable'), findsOneWidget);
    await capture(tester, 'fixture-trend-failure-1280-dark');
    port.failTrend = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No price history yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets(
    'search enter opens first quote and retains original query; back restores hall offset',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = MarketplaceController(FixturePort());
      await tester.pumpWidget(
        app(c, AppearanceMode.dark, const Locale('en', 'US')),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const PageStorageKey('marketplace-hall')),
        const Offset(0, -450),
      );
      await tester.pumpAndSettle();
      final offset = c.hallOffset;
      expect(offset, greaterThan(0));
      await c.focusSearch();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('marketplace-search')),
        'raw SCM query',
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.itemId, 1);
      expect(find.text('Trader 0'), findsOneWidget);
      expect(c.recentSearches.first, 'raw SCM query');
      await tester.tap(find.byKey(const Key('marketplace-back')));
      await tester.pumpAndSettle();
      expect(c.hallOffset, closeTo(offset, 1));
      for (var pass = 0; pass < 3; pass++) {
        await c.openItem(pass + 1);
        await tester.pumpAndSettle();
        c.back();
        await tester.pumpAndSettle();
        final scrollable = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const PageStorageKey('marketplace-hall')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(scrollable.position.pixels, closeTo(offset, 1));
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  test('7 day change requires the exact date and valid observations', () {
    expect(
      marketSevenDaySellChange([
        {'date': '2026-10-01', 'sellPrice': 100},
        {'date': '2026-10-08', 'sellPrice': 125},
      ]),
      25,
    );
    expect(
      marketSevenDaySellChange([
        {'date': '2026-10-02', 'sellPrice': 100},
        {'date': '2026-10-08', 'sellPrice': 125},
      ]),
      isNull,
    );
    expect(
      marketSevenDaySellChange([
        {'date': '2026-10-01', 'sellPrice': 0},
        {'date': '2026-10-08', 'sellPrice': 125},
      ]),
      isNull,
    );
  });
  testWidgets('loading empty and local watch save states', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = FixturePort()..readGate = Completer<void>();
    final c = MarketplaceController(port);
    await tester.pumpWidget(
      app(c, AppearanceMode.dark, const Locale('en', 'US')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MarketSkeleton), findsWidgets);
    await capture(tester, 'fixture-loading-1280-dark');
    port.emptyLists = true;
    port.readGate!.complete();
    await tester.pumpAndSettle();
    await c.openItem(1);
    await tester.pumpAndSettle();
    expect(find.text('No sell offers'), findsWidgets);
    await capture(tester, 'fixture-empty-offers-1280-dark');
    port.saveGate = Completer<void>();
    await tester.tap(find.text('Watch'));
    await tester.pumpAndSettle();
    expect(c.savingPreferences, isTrue);
    expect(c.favorites, isEmpty);
    await capture(tester, 'fixture-local-watch-saving-1280-dark');
    port.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(c.favorites, [1]);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
