import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/hangar/hangar_combat_icon.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_presentation.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_ship_row.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_summary.dart';
import 'package:starbridge_flutter/shared/ships/ship_classification_tag.dart';

void main() {
  testWidgets(
    'classification icons have a fixed left column before fleet-style tags',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in [1120.0, 420.0]) {
        await tester.binding.setSurfaceSize(Size(width, 900));
        await tester.pumpWidget(
          _app(
            Column(
              children: [
                for (final item in _visual())
                  LocalHangarShipRow(
                    item: item,
                    elapsed: const Duration(days: 1),
                    onTap: () {},
                  ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        final columns = _visual()
            .map(
              (item) => tester.getRect(
                find.byKey(
                  ValueKey('local-hangar-icon-column-${item.ship.id}'),
                ),
              ),
            )
            .toList();
        expect(columns.map((rect) => rect.left).toSet(), hasLength(1));
        expect(columns.every((rect) => rect.width == 32), isTrue);
        for (final item in _visual()) {
          final row = find.byKey(
            ValueKey('local-hangar-classification-${item.ship.id}'),
          );
          final icon = tester.getRect(
            find.byKey(ValueKey('local-hangar-icon-column-${item.ship.id}')),
          );
          for (final element
              in find
                  .descendant(
                    of: row,
                    matching: find.byType(ShipClassificationTag),
                  )
                  .evaluate()) {
            expect(
              tester.getRect(find.byWidget(element.widget)).left,
              greaterThan(icon.right),
            );
          }
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
  setUpAll(() async {
    if (const bool.fromEnvironment('LOCAL_HANGAR_GOLDENS')) {
      for (final font in {
        'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
        'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
      }.entries) {
        await (FontLoader(
          font.key,
        )..addFont(rootBundle.load(font.value))).load();
      }
    }
  });

  test('counts instances, preserves unknowns, and sums in cents', () {
    final totals = LocalHangarTotals([
      _item('one', price: 0.1),
      _item('two', price: 0.2),
      _item('zero', price: 0),
      _item('unknown'),
      _item('invalid', price: -100),
      _item('nan', price: double.nan),
      _item('infinity', price: double.infinity),
    ]);
    expect(totals.count, 7);
    expect(totals.pricedCount, 3);
    expect(totals.knownValueCents, 30);
    expect(totals.unpricedCount, 4);
    expect(totals.roles, {'combat': 7});
    expect(totals.statuses, {'flyable': 7});
    final unmapped = LocalHangarPresentation.fromSaved(
      const LocalHangarShip(
        id: 'unmapped',
        title: 'Not in the catalog',
        size: 'small',
      ),
    );
    expect(unmapped.priceCents, isNull);
    expect(unmapped.bundledImage, isNull);
    expect(unmapped.role, 'unknown');
    expect(unmapped.status, 'unknown');
  });

  test('image metadata accepts bundled ship images only', () {
    for (final value in [
      'https://example.com/ship.png',
      'C:/private/ship.png',
      'assets/ships/../secret.png',
      'assets/ships/a.png?x=1',
      'assets/ships/ship.svg',
      'assets/ships/sub/ship.png',
    ]) {
      expect(_item('bad', image: value).bundledImage, isNull);
    }
    expect(
      _item('valid', image: 'assets/ships/carrack.png').bundledImage,
      'assets/ships/carrack.png',
    );
  });

  testWidgets(
    'incomplete prices say known value and keep unknown in distribution',
    (tester) async {
      await tester.pumpWidget(
        _app(
          LocalHangarSummary(
            ships: [
              _item('one', price: 600),
              _item('same-model', price: 600),
              const LocalHangarPresentation(
                ship: LocalHangarShip(id: 'unknown', title: 'Unknown ship'),
              ),
            ],
          ),
        ),
      );
      expect(find.text('已知估值'), findsOneWidget);
      expect(find.text(r'$1,200'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text(r'$1,200')).style?.color,
        tester.element(find.text(r'$1,200')).tokens.colors.info,
      );
      expect(find.text('1 艘未计价'), findsOneWidget);
      final combat = tester.widget<Expanded>(
        find.byKey(const ValueKey('local-hangar-distribution-combat')),
      );
      final unknown = tester.widget<Expanded>(
        find.byKey(const ValueKey('local-hangar-distribution-unknown')),
      );
      expect(combat.flex, 2);
      expect(unknown.flex, 1);
    },
  );

  testWidgets('empty, unpriced, zero priced, and complete are distinct', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const LocalHangarSummary(ships: [])));
    expect(find.text('0'), findsOneWidget);
    expect(find.text(r'$0'), findsNothing);
    await tester.pumpWidget(
      _app(LocalHangarSummary(ships: [_item('no-price')])),
    );
    expect(find.text('暂无价格'), findsOneWidget);
    expect(find.text('已知估值'), findsOneWidget);
    expect(find.text(r'$0'), findsNothing);
    await tester.pumpWidget(
      _app(LocalHangarSummary(ships: [_item('zero', price: 0)])),
    );
    expect(find.text(r'$0'), findsOneWidget);
    expect(find.text('机库估值'), findsOneWidget);
    expect(find.text('已知估值'), findsNothing);
  });

  testWidgets('bundled image and combat icon coexist; missing image recovers', (
    tester,
  ) async {
    final item = _item(
      'with-image',
      image: 'assets/ships/carrack.png',
      price: 600,
    );
    await tester.pumpWidget(
      _app(
        LocalHangarShipRow(
          item: item,
          elapsed: const Duration(days: 1),
          onTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
    expect(find.byType(HangarCombatIcon), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      _app(
        LocalHangarShipRow(
          item: _item('missing', image: 'assets/ships/missing-test.png'),
          elapsed: const Duration(days: 1),
          onTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('暂无图片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ship rows preserve keyboard activation and show catalog price', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      _app(
        LocalHangarShipRow(
          item: _item('keyboard', price: 250.55),
          elapsed: Duration.zero,
          onTap: () => opened = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(find.text(r'$250.55 USD'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text(r'$250.55 USD')).style?.color,
      tester.element(find.text(r'$250.55 USD')).tokens.colors.info,
    );
    expect(tester.hasRunningAnimations, isFalse);
  });

  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ]) {
    for (final mode in AppearanceMode.values) {
      testWidgets(
        'summary and image rows responsive ${locale.toLanguageTag()} ${mode.name}',
        (tester) async {
          addTearDown(() => tester.binding.setSurfaceSize(null));
          for (final size in const [Size(1120, 820), Size(360, 720)]) {
            await tester.binding.setSurfaceSize(size);
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LocalHangarSummary(ships: _visual()),
                const SizedBox(height: 16),
                for (final item in _visual()) ...[
                  LocalHangarShipRow(
                    item: item,
                    elapsed: const Duration(days: 1),
                    onTap: () {},
                  ),
                  const Divider(height: 1),
                ],
              ],
            );
            await tester.pumpWidget(_app(content, locale: locale, mode: mode));
            await tester.runAsync(() async {
              final context = tester.element(find.byType(LocalHangarSummary));
              await Future.wait(
                tester
                    .widgetList<Image>(find.byType(Image))
                    .map(
                      (image) => precacheImage(
                        image.image,
                        context,
                        // Prefetch is optional. The actual row must still handle
                        // absent source-build media without a widget exception.
                        onError: (error, stack) {},
                      ),
                    ),
              );
            });
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (const bool.fromEnvironment('LOCAL_HANGAR_GOLDENS') &&
                locale.countryCode == 'CN') {
              await expectLater(
                find.byType(Scaffold),
                matchesGoldenFile(
                  '../../../build/hangar_summary_${mode.name}_${size.width.toInt()}.png',
                ),
              );
            }
            await tester.pumpWidget(
              _app(content, locale: locale, mode: mode, scale: 1.5),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
}

LocalHangarPresentation _item(String id, {num? price, String? image}) =>
    LocalHangarPresentation(
      ship: LocalHangarShip(
        id: id,
        title: 'Carrack',
        cn: '克拉克',
        tw: '克拉克',
        liner: 'Anvil Aerospace',
        size: 'large',
      ),
      catalogId: 'carrack',
      category: 'combat',
      sizeClass: 'large',
      deliveryStatus: 'flyable',
      priceUsd: price,
      imageAsset: image,
    );

List<LocalHangarPresentation> _visual() => [
  const LocalHangarPresentation(
    ship: LocalHangarShip(
      id: 'synthetic-hornet',
      title: 'F7C-M Super Hornet Mk II',
      cn: 'F7C-M 超级大黄蜂 Mk II',
      tw: 'F7C-M 超級大黃蜂 Mk II',
      liner: 'Anvil Aerospace',
      size: 'small',
    ),
    category: 'combat',
    deliveryStatus: 'flyable',
    priceUsd: 185,
    imageAsset: bool.fromEnvironment('LOCAL_HANGAR_PRIVATE_MEDIA')
        ? 'assets/ships/catalog-f7c-m-super-hornet-mk-ii.jpg'
        : 'assets/ships/f7c-m-super-hornet-mk-ii.jpg',
  ),
  const LocalHangarPresentation(
    ship: LocalHangarShip(
      id: 'synthetic-carrack',
      title: 'Carrack',
      cn: '克拉克',
      tw: '克拉克',
      liner: 'Anvil Aerospace',
    ),
    sizeClass: 'large',
    category: 'exploration',
    deliveryStatus: 'flyable',
    priceUsd: 600,
    imageAsset: bool.fromEnvironment('LOCAL_HANGAR_PRIVATE_MEDIA')
        ? 'assets/ships/catalog-carrack.png'
        : 'assets/ships/carrack.png',
  ),
  const LocalHangarPresentation(
    ship: LocalHangarShip(
      id: 'synthetic-vulture',
      title: 'Vulture',
      cn: '秃鹫',
      tw: '禿鷲',
      liner: 'Drake Interplanetary',
    ),
    sizeClass: 'small',
    category: 'industrial',
    deliveryStatus: 'flyable',
    priceUsd: 175,
    imageAsset: bool.fromEnvironment('LOCAL_HANGAR_PRIVATE_MEDIA')
        ? 'assets/ships/catalog-vulture.jpg'
        : 'assets/ships/vulture.jpg',
  ),
  const LocalHangarPresentation(
    ship: LocalHangarShip(
      id: 'synthetic-zeus',
      title: 'Zeus Mk II MR',
      cn: '宙斯 Mk II MR',
      tw: '宙斯 Mk II MR',
      liner: 'Roberts Space Industries',
    ),
    sizeClass: 'medium',
    category: 'combat',
    deliveryStatus: 'concept',
    priceUsd: 190,
    imageAsset: bool.fromEnvironment('LOCAL_HANGAR_PRIVATE_MEDIA')
        ? 'assets/ships/catalog-zeus-mk-ii-mr.jpg'
        : 'assets/ships/zeus-mk-ii-mr.jpg',
  ),
  const LocalHangarPresentation(
    ship: LocalHangarShip(
      id: 'synthetic-unknown',
      title: 'Unlisted ship',
      cn: '未收录舰船',
      tw: '未收錄艦船',
    ),
  ),
];

Widget _app(
  Widget child, {
  Locale locale = const Locale('zh', 'CN'),
  AppearanceMode mode = AppearanceMode.dark,
  double scale = 1,
}) => MaterialApp(
  locale: locale,
  supportedLocales: const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(mode).withReducedMotion(true),
    locale,
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: child,
    ),
  ),
);
