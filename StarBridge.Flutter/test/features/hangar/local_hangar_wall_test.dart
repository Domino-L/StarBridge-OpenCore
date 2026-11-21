import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_copy.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_detail.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_manufacturers.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_names.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_ship_accent.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_ship_row.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_stage.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_wall_card.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_wall_sections.dart';

class _Port implements LocalHangarPort, LocalHangarFavoritesPort {
  _Port(this.snapshot);
  LocalHangarSnapshot snapshot;
  int reads = 0;
  final favorites = <(String, bool)>[];
  bool failFavorite = false;
  @override
  bool get favoritesAvailable => true;
  @override
  Future<LocalHangarSnapshot> read() async {
    reads++;
    return snapshot;
  }

  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) async => snapshot;
  @override
  Future<LocalHangarSnapshot> setFavorite(
    String shipId,
    bool favorite,
    int expectedRevision,
  ) async {
    if (failFavorite) {
      throw const LocalHangarFailure('hangar.revision_conflict');
    }
    favorites.add((shipId, favorite));
    snapshot = LocalHangarSnapshot(
      revision: snapshot.revision + 1,
      ships: [
        for (final ship in snapshot.ships)
          ship.id == shipId
              ? LocalHangarShip(
                  id: ship.id,
                  title: ship.title,
                  manufacturer: ship.manufacturer,
                  size: ship.size,
                  isFavorite: favorite,
                  priceUsd: ship.priceUsd,
                )
              : ship,
      ],
    );
    return snapshot;
  }
}

LocalHangarShip _ship(
  String id, {
  String title = 'Ship',
  String? maker,
  String? size = 'small',
  num? price,
  bool favorite = false,
  String? liner,
  String? nickname,
}) => LocalHangarShip(
  id: id,
  title: title,
  manufacturer: maker,
  size: size,
  priceUsd: price,
  isFavorite: favorite,
  liner: liner,
  nickname: nickname,
);

Widget _app(
  LocalHangarPort port, {
  AppearanceMode mode = AppearanceMode.dark,
  Locale locale = const Locale('zh', 'CN'),
}) => MaterialApp(
  locale: locale,
  supportedLocales: const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ],
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(FutureRestraintStyle.resolve(mode), locale),
  home: Scaffold(
    body: LocalHangarPage(port: port, onRead: () {}),
  ),
);

Future<LocalHangarCopy> _copy(WidgetTester tester, Locale locale) async {
  late LocalHangarCopy copy;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('en'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(
        builder: (context) {
          copy = LocalHangarCopy(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return copy;
}

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  group('maker names', () {
    testWidgets('every catalog spelling and alias finds one maker', (
      tester,
    ) async {
      for (final (spelling, key) in const [
        ('Aegis Dynamics', 'aegis'),
        ('Aegis', 'aegis'),
        ('Musashi Industrial and Starflight Concern', 'misc'),
        ('MISC', 'misc'),
        ("Xi'an", 'aopoa'),
        ('Xian', 'aopoa'),
        ('Gatac', 'gatac'),
        ('Gatac Manufacture', 'gatac'),
        ('Tumbril Land Systems', 'tumbril'),
        ("Grey's", 'greys'),
        ("Grey's Market", 'greys'),
        ('Vanduul', 'vanduul'),
        ('Roberts Space Industries', 'rsi'),
        ('Greycat Industrial', 'greycat'),
      ]) {
        expect(LocalHangarManufacturers.find(spelling)?.key, key);
      }
      expect(LocalHangarManufacturers.find('A shipping company'), isNull);
    });

    testWidgets('each language reads its own name; RSI stays RSI', (
      tester,
    ) async {
      final anvil = LocalHangarManufacturers.find('Anvil Aerospace')!;
      final rsi = LocalHangarManufacturers.find('RSI')!;
      final cn = await _copy(tester, const Locale('zh', 'CN'));
      expect(anvil.name(cn), '铁砧');
      expect(anvil.original(cn), 'Anvil Aerospace');
      expect(rsi.name(cn), 'RSI');
      final tw = await _copy(tester, const Locale('zh', 'TW'));
      expect(anvil.name(tw), '鐵砧');
      final en = await _copy(tester, const Locale('en'));
      expect(anvil.name(en), 'Anvil Aerospace');
      expect(anvil.short(en), 'Anvil');
      expect(anvil.original(en), isNull);
    });

    test('search matches Chinese, traditional and English maker names', () {
      final ship = _ship('a', maker: 'Tumbril Land Systems');
      for (final query in ['盾博尔', '盾博爾', 'tumbril', 'tumbril land']) {
        expect(LocalHangarNames.matches(ship, query), isTrue, reason: query);
      }
      expect(LocalHangarNames.matches(ship, '圣盾'), isFalse);
      // Without a catalog maker, a liner naming one still counts.
      final old = _ship('b', liner: 'Anvil');
      expect(LocalHangarNames.matches(old, '铁砧'), isTrue);
    });

    test('marks exist only in the official package', () {
      final aegis = LocalHangarManufacturers.find('Aegis')!;
      expect(LocalHangarMakerLogos.instance.has(aegis, dark: true), isFalse);
      LocalHangarMakerLogos.instance.debugUse({
        LocalHangarMakerLogos.asset('aegis', dark: true),
      });
      addTearDown(() => LocalHangarMakerLogos.instance.debugUse(const {}));
      expect(LocalHangarMakerLogos.instance.has(aegis, dark: true), isTrue);
      expect(LocalHangarMakerLogos.instance.has(aegis, dark: false), isFalse);
      final greycat = LocalHangarManufacturers.find('Greycat Industrial')!;
      expect(greycat.logo, isFalse);
    });
  });

  group('sections', () {
    late LocalHangarCopy copy;
    setUp(() {});

    testWidgets('favorites lead and are not repeated; sizes keep their order', (
      tester,
    ) async {
      copy = await _copy(tester, const Locale('zh', 'CN'));
      final sections = LocalHangarWallSections.build(
        [
          _ship('small', size: 'small'),
          _ship('capital', size: 'capital'),
          _ship('truck', size: null),
          _ship('fav', size: 'capital', favorite: true),
          _ship('medium', size: 'medium'),
          _ship('ground', size: 'ground-medium'),
        ],
        byMaker: false,
        copy: copy,
        sort: 'saved',
      );
      expect(sections.map((s) => s.key).toList(), [
        'favorites',
        'size-capital',
        'size-medium',
        'size-small',
        'size-ground-medium',
        'size-other',
      ]);
      final ids = [for (final s in sections) ...s.ships.map((x) => x.id)];
      expect(ids.where((id) => id == 'fav'), hasLength(1));
      expect(ids, hasLength(6));
      expect(sections.last.title, '其他');
    });

    testWidgets('makers run from the largest; no maker closes the wall', (
      tester,
    ) async {
      copy = await _copy(tester, const Locale('zh', 'CN'));
      final sections = LocalHangarWallSections.build(
        [
          _ship('none-1'),
          _ship('none-2'),
          _ship('none-3'),
          _ship('aegis', maker: 'Aegis Dynamics'),
          _ship('anvil-1', maker: 'Anvil Aerospace'),
          _ship('anvil-2', maker: 'Anvil'),
          _ship('new', maker: 'New Maker Co'),
        ],
        byMaker: true,
        copy: copy,
        sort: 'saved',
      );
      expect(sections.first.title, '铁砧');
      expect(sections.first.ships, hasLength(2));
      expect(sections.last.key, 'maker-other');
      expect(sections.map((s) => s.title), contains('New Maker Co'));
      expect(sections.map((s) => s.title), contains('圣盾'));
    });

    testWidgets('same model stays separate; default order is by price', (
      tester,
    ) async {
      copy = await _copy(tester, const Locale('zh', 'CN'));
      final sections = LocalHangarWallSections.build(
        [
          _ship('cheap', price: 10),
          _ship('twin-1', title: 'Twin', price: 100),
          _ship('twin-2', title: 'Twin', price: 100),
          _ship('unknown'),
        ],
        byMaker: false,
        copy: copy,
        sort: 'saved',
      );
      expect(sections.single.ships.map((s) => s.id).toList(), [
        'twin-1',
        'twin-2',
        'cheap',
        'unknown',
      ]);
      // An explicit sort is the caller's order, untouched.
      final named = LocalHangarWallSections.build(
        [_ship('cheap', price: 10), _ship('dear', price: 100)],
        byMaker: false,
        copy: copy,
        sort: 'name',
      );
      expect(named.single.ships.first.id, 'cheap');
    });
  });

  testWidgets('wall groups, switches density and segment without rereading', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1216, 836));
    final port = _Port(
      LocalHangarSnapshot(
        revision: 1,
        ships: [
          _ship('a', title: 'A', maker: 'Anvil Aerospace', size: 'capital'),
          _ship('b', title: 'B', maker: 'Aegis Dynamics', size: 'small'),
          _ship('c', title: 'C', favorite: true, size: 'small'),
        ],
      ),
    );
    await tester.pumpWidget(_app(port));
    await tester.pumpAndSettle();
    expect(find.byType(LocalHangarWallCard), findsNWidgets(3));
    expect(_key('hangar-jump-favorites'), findsOneWidget);
    expect(_key('hangar-jump-size-capital'), findsOneWidget);
    await tester.tap(find.byKey(const Key('hangar-compact')));
    await tester.pumpAndSettle();
    final compact = tester.widget<LocalHangarWallCard>(
      find.byKey(const ValueKey('local-hangar-ship-a')),
    );
    expect(compact.metrics.compact, isTrue);
    expect(compact.metrics.columns, greaterThanOrEqualTo(8));
    await tester.tap(find.byKey(const Key('hangar-by-maker')));
    await tester.pumpAndSettle();
    expect(_key('hangar-jump-maker-anvil'), findsOneWidget);
    expect(_key('hangar-jump-size-capital'), findsNothing);
    await tester.tap(find.byKey(const Key('hangar-list')));
    await tester.pumpAndSettle();
    expect(find.byType(LocalHangarShipRow), findsNWidgets(3));
    expect(_key('hangar-jump-maker-anvil'), findsOneWidget);
    expect(port.reads, 1);
    expect(tester.takeException(), isNull);
  });

  for (final mode in AppearanceMode.values) {
    testWidgets('a large hangar builds only what shows; jump lands in $mode', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1216, 836));
      final port = _Port(
        LocalHangarSnapshot(
          revision: 1,
          ships: [
            for (var i = 0; i < 600; i++)
              _ship(
                'ship-$i',
                title: 'Ship $i',
                size: const ['capital', 'large', 'medium', 'small'][i % 4],
                maker: 'Anvil Aerospace',
              ),
          ],
        ),
      );
      await tester.pumpWidget(_app(port, mode: mode));
      await tester.pumpAndSettle();
      expect(
        find.byType(LocalHangarWallCard, skipOffstage: false).evaluate().length,
        lessThan(120),
      );
      expect(find.byKey(const Key('hangar-jump-top')), findsNothing);
      await tester.tap(_key('hangar-jump-size-small'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hangar-jump-top')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('hangar-jump-current')))
            .textSpan!
            .toPlainText(),
        startsWith('小型'),
      );
      final bar = tester.getRect(find.byKey(const Key('hangar-jump-bar')));
      expect(bar.top, 0);
      final heading = find
          .text('小型')
          .evaluate()
          .map(
            (e) => (e.renderObject! as RenderBox).localToGlobal(Offset.zero).dy,
          );
      expect(
        heading.any((y) => y >= bar.bottom && y < bar.bottom + 30),
        isTrue,
      );
      await tester.tap(find.byKey(const Key('hangar-jump-top')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hangar-jump-current')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('list rows jump to their section though heights are estimated', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1216, 836));
    final port = _Port(
      LocalHangarSnapshot(
        revision: 1,
        ships: [
          for (var i = 0; i < 300; i++)
            _ship(
              'ship-$i',
              title: 'Ship $i',
              size: i < 200 ? 'large' : 'small',
            ),
        ],
      ),
    );
    await tester.pumpWidget(_app(port));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hangar-list')));
    await tester.pumpAndSettle();
    await tester.tap(_key('hangar-jump-size-small'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('hangar-jump-current')))
          .textSpan!
          .toPlainText(),
      startsWith('小型'),
    );
    expect(tester.takeException(), isNull);
  });

  group('stage', () {
    Future<_Port> open(
      WidgetTester tester, {
      Size size = const Size(1216, 836),
    }) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(size);
      final port = _Port(
        LocalHangarSnapshot(
          revision: 1,
          ships: [
            for (var i = 0; i < 40; i++)
              _ship('ship-$i', title: 'Ship $i', price: 1000 - i),
          ],
        ),
      );
      await tester.pumpWidget(_app(port));
      await tester.pumpAndSettle();
      return port;
    }

    testWidgets('opens from a card; back returns to the same wall position', (
      tester,
    ) async {
      await open(tester);
      final scroll = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      scroll.jumpTo(300);
      await tester.pumpAndSettle();
      final offset = scroll.pixels;
      expect(find.byType(LocalHangarStage), findsNothing);
      await tester.tap(find.byKey(const ValueKey('hangar-open-ship-6')));
      await tester.pumpAndSettle();
      expect(find.byType(LocalHangarStage), findsOneWidget);
      expect(find.byType(LocalHangarDetail), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('hangar-stage-name'))).data,
        'Ship 6',
      );
      await tester.tap(find.byKey(const Key('hangar-stage-next')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('hangar-stage-name'))).data,
        'Ship 7',
      );
      await tester.tap(_key('hangar-stage-select-ship-5'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('hangar-stage-name'))).data,
        'Ship 5',
      );
      await tester.tap(find.byKey(const Key('hangar-stage-back')));
      await tester.pumpAndSettle();
      expect(find.byType(LocalHangarStage), findsNothing);
      expect(scroll.pixels, offset);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keyboard changes ship and Escape goes back', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('hangar-open-ship-0')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('hangar-stage-name'))).data,
        'Ship 1',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('hangar-stage-name'))).data,
        'Ship 39',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(LocalHangarStage), findsNothing);
    });

    testWidgets('details open from the stage, which stays beneath', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('hangar-open-ship-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hangar-stage-details')));
      await tester.pumpAndSettle();
      expect(find.byType(LocalHangarDetail), findsOneWidget);
      expect(find.byType(LocalHangarStage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bookmarking from the stage keeps the same ship', (
      tester,
    ) async {
      final port = await open(tester);
      await tester.tap(find.byKey(const ValueKey('hangar-open-ship-5')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hangar-stage-favorite')));
      await tester.pumpAndSettle();
      expect(port.favorites, [('ship-5', true)]);
      expect(
        tester.widget<Text>(find.byKey(const Key('hangar-stage-name'))).data,
        'Ship 5',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('hangar-stage-position')))
            .data,
        '收藏 · 第 1 / 1 艘',
      );
    });

    testWidgets('a failed bookmark says so on the stage', (tester) async {
      final port = await open(tester);
      port.failFavorite = true;
      await tester.tap(find.byKey(const ValueKey('hangar-open-ship-5')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hangar-stage-favorite')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('hangar-stage-favorite-status')))
            .data,
        contains('未能确认收藏结果'),
      );
    });

    testWidgets(
      'a ship without a picture shows its icon, a custom one does not',
      (tester) async {
        await open(tester);
        await tester.tap(find.byKey(const ValueKey('hangar-open-ship-5')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(LocalHangarStage),
            matching: find.byType(LocalHangarWallIcon),
          ),
          findsNWidgets(2),
        );
      },
    );

    for (final mode in AppearanceMode.values) {
      testWidgets('fits the smallest window in $mode', (tester) async {
        await open(tester, size: const Size(640, 480));
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('hangar-open-ship-0')),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('hangar-open-ship-0')));
        await tester.pumpAndSettle();
        expect(find.byType(LocalHangarStage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  test('stage line color comes from the artwork, or nothing when gray', () {
    final blue = Uint8List.fromList([
      for (var i = 0; i < 40; i++) ...[20, 90, 220, 255],
      for (var i = 0; i < 4; i++) ...[220, 40, 30, 255],
    ]);
    final color = HSVColor.fromColor(LocalHangarShipAccent.fromRgba(blue)!);
    expect(color.hue, inInclusiveRange(200, 240));
    expect(color.value, closeTo(.98, .01));
    final gray = Uint8List.fromList([
      for (var i = 0; i < 40; i++) ...[120, 120, 120, 255],
    ]);
    expect(LocalHangarShipAccent.fromRgba(gray), isNull);
  });
}
