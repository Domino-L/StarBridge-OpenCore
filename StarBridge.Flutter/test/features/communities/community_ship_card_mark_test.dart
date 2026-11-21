// Card maker logo and silhouette (user 11-05 option C; 11-14 logo in the art's lower-right corner).
// Regression checks always run; captures only with STARBRIDGE_TEST_VISUAL_DIR.
// All ship/holder records are synthetic. Optional art is read from this checkout;
// no Host, transport, account, persistence or production flag is created.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/app/shell/widgets/shell_workspace_frame.dart';
import 'package:starbridge_flutter/design_system/appearance/appearance_scope.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_workspace_frame.dart';
import 'package:starbridge_flutter/features/common/organization_ship_owner.dart';
import 'package:starbridge_flutter/features/communities/community_image_decoder.dart';
import 'package:starbridge_flutter/features/communities/community_ship_card.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_manufacturers.dart';
import 'package:starbridge_flutter/shared/ships/scm_ship_thumbnail.dart';
import 'package:starbridge_flutter/shared/ships/ship_classification_tag.dart';
import 'package:starbridge_flutter/shared/ships/ship_silhouette_store.dart';

import '../../_support/restricted_files.dart';
import '../../support/synthetic_image.dart';
import '../friends/social_layout_test.dart' show app, loadFonts, size;
import 'community_ships_test.dart' show shipRow;

final _output = Platform.environment['STARBRIDGE_TEST_VISUAL_DIR'];
ShipSilhouettePack? _previewPack;
final _logoBytes = <String, ByteData>{};
String _ref(int value) => value.toRadixString(16).padLeft(32, '0');

// The user's own 11-14 screenshot of an organization ship library: same ships,
// order and official art; holders are synthetic.
const _catalog = [
  (
    'idris-p',
    '伊德里斯-P',
    'Idris-P',
    'Aegis Dynamics',
    'combat-capital',
    'capital',
    'combat',
    '可飞',
    '1900',
    'assets/ships/catalog-idris-p.jpg',
    0,
  ),
  (
    'kraken',
    '海妖',
    'Kraken',
    'Drake Interplanetary',
    'industrial-capital',
    'capital',
    'industrial',
    '概念',
    '1650',
    'assets/ships/catalog-kraken.jpg',
    3,
  ),
  (
    'polaris',
    '北极星',
    'Polaris',
    'Roberts Space Industries',
    'combat-capital',
    'capital',
    'combat',
    '可飞',
    '975',
    'assets/ships/catalog-polaris.jpg',
    0,
  ),
  (
    'apollo-medivac',
    '阿波罗 医疗',
    'Apollo Medivac',
    'Roberts Space Industries',
    'support-large',
    'large',
    'support',
    '可飞',
    '290',
    'assets/ships/catalog-apollo-medivac.jpg',
    0,
  ),
  (
    'constellation-mk-v-centaurus',
    '星座 Mk V 半人马座',
    'Constellation Mk V Centaurus',
    'Roberts Space Industries',
    null,
    'medium',
    'multi-role',
    '可飞',
    '300',
    'assets/ships/catalog-constellation-mk-v-centaurus.jpg',
    0,
  ),
  (
    'ironclad-assault',
    '铁甲 突袭',
    'Ironclad Assault',
    'Drake Interplanetary',
    'combat-large',
    'large',
    'combat',
    '可飞',
    '650',
    'assets/ships/catalog-ironclad-assault.jpg',
    0,
  ),
  (
    'merchantman',
    '巴努商船',
    'Merchantman',
    'Banu',
    'logistics-large',
    'large',
    'transport',
    '概念',
    '650',
    'assets/ships/catalog-merchantman.jpg',
    3,
  ),
  (
    'perseus',
    '英仙座',
    'Perseus',
    'Roberts Space Industries',
    'combat-large',
    'large',
    'combat',
    '可飞',
    '800',
    'assets/ships/catalog-perseus.jpg',
    0,
  ),
  (
    'reclaimer',
    '回收者',
    'Reclaimer',
    'Aegis Dynamics',
    'industrial-large',
    'large',
    'industrial',
    '可飞',
    '400',
    'assets/ships/catalog-reclaimer.jpg',
    0,
  ),
  (
    'hull-b',
    '货轮 B',
    'Hull B',
    'MISC',
    'logistics-medium',
    'medium',
    'transport',
    '可飞',
    '280',
    'assets/ships/catalog-hull-b.jpg',
    0,
  ),
  (
    'railen',
    '锐伦',
    'Railen',
    'Gatac',
    'logistics-medium',
    'medium',
    'transport',
    '可飞',
    '400',
    'assets/ships/catalog-railen.jpg',
    0,
  ),
  (
    'starlancer-tac',
    '星际枪骑兵 TAC',
    'Starlancer TAC',
    'MISC',
    'combat-medium',
    'medium',
    'combat',
    '可飞',
    '375',
    'assets/ships/catalog-starlancer-tac.jpg',
    0,
  ),
];

Map<String, Object?> _row(int i, {bool fleet = false}) {
  final entry = _catalog[i];
  return shipRow()..addAll({
    'shipRef': _ref(i + 1),
    'code': entry.$1,
    'displayName': entry.$2,
    'englishName': entry.$3,
    'manufacturer': entry.$4,
    'catalogIconKey': entry.$5,
    'catalogSpec': entry.$6,
    'catalogRole': entry.$7,
    'roleCategory': entry.$7,
    'catalogStatus': entry.$8,
    'catalogPriceUsd': entry.$9,
    'catalogImageAsset': entry.$10,
    'ownerMemberRef': _ref(100 + i),
    'ownerCallsign': ['远航者', '星港观察员', '探索队员'][i % 3],
    'ownerOnline': !fleet && i.isEven,
    'ownerLiveStatus': fleet ? 'Unknown' : 'Offline',
    'ownerHasAvatar': false,
    'hasCustomImage': false,
    'loaners': [
      for (var n = 0; n < entry.$11; n++)
        {'code': 'loaner-$n', 'displayName': '替代船 $n'},
    ],
  });
}

class _Ships implements CommunityShipsPort {
  _Ships(this.fleet);
  final bool fleet;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  bool get shipsAvailable => true;
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async => CommunityShipsPage.parse({
    'schemaVersion': 1,
    'targetRef': targetRef,
    'revision': 'b' * 64,
    if (query != null) 'queryVersion': 2,
    if (query != null) 'query': query.toPayload(),
    'offset': 0,
    'next': null,
    'totalCount': _catalog.length,
    'ships': [for (var i = 0; i < _catalog.length; i++) _row(i, fleet: fleet)],
  });
}

/// Image.asset still uses the regular asset path. The preview supplies the
/// existing local Fan Kit originals without copying them into product assets.
class _PreviewAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key.startsWith('assets/ships/catalog-maker-')) {
      final bytes = _logoBytes[key];
      if (bytes != null) return bytes;
      throw StateError('Optional preview logo absent');
    }
    if (openCoreTestSource &&
        key.startsWith('assets/ships/catalog-') &&
        restrictedFileIsAbsent(key)) {
      // Layout tests need a decodable image, independent of the ship preview.
      return syntheticImageData();
    }
    return rootBundle.load(key);
  }
}

Future<void> _readPreviewArt() async {
  final pack = File(
    '../StarBridge.Desktop/Data/ShipSilhouettes/catalog-silhouettes.bin',
  );
  if (await pack.exists()) {
    _previewPack = ShipSilhouettePack.parse(
      ByteData.sublistView(await pack.readAsBytes()),
    );
  }
  final logos = Directory('../StarBridge.Desktop/Data/ManufacturerLogos');
  if (await logos.exists()) {
    for (final file in logos.listSync().whereType<File>()) {
      if (file.path.endsWith('.png')) {
        _logoBytes['assets/ships/${file.uri.pathSegments.last}'] =
            ByteData.sublistView(await file.readAsBytes());
      }
    }
  }
}

void _usePreviewArt() {
  ShipSilhouetteStore.instance.debugUse(_previewPack);
  LocalHangarMakerLogos.instance.debugUse(_logoBytes.keys.toSet());
}

Widget _page(
  GlobalKey key, {
  bool fleet = false,
  AppearanceMode mode = AppearanceMode.dark,
}) => RepaintBoundary(
  key: key,
  child: app(
    DefaultAssetBundle(
      bundle: _PreviewAssets(),
      child: ShipThumbnailScope(
        read: null,
        child: Builder(
          builder: (context) => ShellWindowFrame(
            child: ColoredBox(
              color: context.tokens.surfaces.ground.fill,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const AppearanceSurfaceBackdrop(role: SurfaceRole.ground),
                  OrganizationWorkspacePage(
                    child: OrganizationWorkspaceSurface(
                      child: CommunityShipsPanel(
                        port: _Ships(fleet),
                        targetRef: _ref(fleet ? 8 : 9),
                        name: fleet ? '示例主舰队' : '示例社区组织',
                        onBack: () {},
                        ownerTargetFactory: fleet
                            ? null
                            : communityShipOwnerTarget,
                        includeSocialActions: !fleet,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    mode,
  ),
);

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  expect(tester.takeException(), isNull);
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('$_output/ship-card-final');
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _card(
  WidgetTester tester, {
  int index = 0,
  double width = 280,
  VoidCallback? onDetails,
  AppearanceMode mode = AppearanceMode.dark,
  double textScale = 1,
}) async {
  final card = SizedBox(
    width: width,
    child: CommunityShipCard(
      ship: CommunitySharedShip.parse(_row(index)),
      targetRef: _ref(9),
      avatarBytes: null,
      avatarLoading: false,
      imageDecoder: decodeCommunityImage,
      onDetails: onDetails ?? () {},
      ownerTargetFactory: communityShipOwnerTarget,
      includeSocialActions: true,
    ),
  );
  await tester.pumpWidget(
    app(
      DefaultAssetBundle(
        bundle: _PreviewAssets(),
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: Center(child: card),
          ),
        ),
      ),
      mode,
    ),
  );
  await tester.pumpAndSettle();
}

// 11-14 user: "现在舰船卡片标签最长能叠到多少字？会占百分之多少长度？" The longest
// real names, tag combinations and widest Fan Kit logos in the catalog.
const _stress = [
  (
    'mustang-alpha-vindicator',
    '联合外域 野马 阿尔法 辩护者',
    'Mustang Alpha Vindicator',
    'Consolidated Outland',
    'multi-role',
    'small',
    'spacecraft',
    null,
    '可飞',
    '30',
    'assets/ships/catalog-mustang-alpha-vindicator.png',
  ),
  (
    'carrack-expedition-w-c8x',
    '铁砧 克拉克 远征版 带/C8X',
    'Carrack Expedition w/C8X',
    'Anvil Aerospace',
    'exploration',
    'large',
    'spacecraft',
    'exploration-large',
    '可飞',
    '645',
    'assets/ships/catalog-carrack-expedition-w-c8x.jpg',
  ),
  (
    'f7c-m-super-hornet-heartseeker-mk-i',
    'F7C-M 大黄蜂 寻心者 Mk I',
    'F7C-M Super Hornet Heartseeker Mk I',
    'Anvil Aerospace',
    'combat',
    'small',
    'spacecraft',
    'combat-small',
    '可飞',
    '200',
    'assets/ships/catalog-f7c-m-super-hornet-heartseeker-mk-i.jpg',
  ),
  (
    'g12r',
    'G12r',
    'G12r',
    'Origin Jumpworks',
    'competition',
    'medium',
    'ground',
    null,
    '概念',
    '60',
    'assets/ships/catalog-g12r.jpg',
  ),
  (
    'nova',
    '新星',
    'Nova',
    'Tumbril',
    'combat',
    'large',
    'ground',
    'ground-combat-large-tracked',
    '可飞',
    '120',
    'assets/ships/catalog-nova.jpg',
  ),
  (
    'mole',
    '鼹鼠',
    'MOLE',
    'Argo Astronautics',
    'industrial',
    'medium',
    'spacecraft',
    'industrial-medium',
    '可飞',
    '315',
    'assets/ships/catalog-mole.jpg',
  ),
  (
    'constellation-mk-v-centaurus',
    '星座 Mk V 半人马座',
    'Constellation Mk V Centaurus',
    'Roberts Space Industries',
    'multi-role',
    'medium',
    'spacecraft',
    null,
    '可飞',
    '300',
    'assets/ships/catalog-constellation-mk-v-centaurus.jpg',
  ),
  (
    'merchantman',
    '巴努商船',
    'Merchantman',
    'Banu',
    'transport',
    'large',
    'spacecraft',
    'logistics-large',
    '概念',
    '650',
    'assets/ships/catalog-merchantman.jpg',
  ),
];

Map<String, Object?> _stressRow(int i, bool english) {
  final e = _stress[i];
  return shipRow()..addAll({
    'shipRef': _ref(200 + i),
    'code': e.$1,
    'displayName': english ? e.$3 : e.$2,
    'englishName': e.$3,
    'manufacturer': e.$4,
    'display': {
      'category': e.$5,
      'sizeClass': e.$6,
      'domain': e.$7,
      'iconKey': e.$8,
    },
    'catalogStatus': e.$9,
    'catalogPriceUsd': e.$10,
    'catalogImageAsset': e.$11,
    'ownerMemberRef': _ref(300 + i),
    'ownerCallsign': english ? 'Port watcher' : '星港观察员',
    'ownerOnline': false,
    'ownerLiveStatus': 'Offline',
    'ownerHasAvatar': false,
    'hasCustomImage': false,
    'loaners': i == 7
        ? [
            for (var n = 0; n < 3; n++)
              {'code': 'loaner-$n', 'displayName': '替代船 $n'},
          ]
        : [],
  });
}

Widget _appIn(Widget child, AppearanceMode mode, Locale locale) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  // Windows falls back to a system CJK face for Chinese inside English text;
  // the test engine has only the bundled fonts, so name the bundled one.
  theme: () {
    final theme = buildStarBridgeTheme(
      FutureRestraintStyle.resolve(mode),
      locale,
    );
    return theme.copyWith(
      textTheme: theme.textTheme.apply(
        fontFamilyFallback: const ['Source Han Sans CN'],
      ),
    );
  }(),
  home: Scaffold(body: child),
);

Widget _stressGrid(
  GlobalKey key,
  double width,
  bool english, {
  AppearanceMode mode = AppearanceMode.dark,
  double textScale = 1,
}) {
  final locale = english ? const Locale('en') : const Locale('zh', 'CN');
  return RepaintBoundary(
    key: key,
    child: _appIn(
      DefaultAssetBundle(
        bundle: _PreviewAssets(),
        child: ShipThumbnailScope(
          read: null,
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: ColoredBox(
                color: context.tokens.surfaces.ground.fill,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      for (var i = 0; i < _stress.length; i++)
                        SizedBox(
                          width: width,
                          child: CommunityShipCard(
                            ship: CommunitySharedShip.parse(
                              _stressRow(i, english),
                            ),
                            targetRef: _ref(9),
                            avatarBytes: null,
                            avatarLoading: false,
                            imageDecoder: decodeCommunityImage,
                            onDetails: () {},
                            ownerTargetFactory: communityShipOwnerTarget,
                            includeSocialActions: true,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      mode,
      locale,
    ),
  );
}

Future<void> _settleImages(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await loadFonts();
    await _readPreviewArt();
  });
  tearDown(() {
    ShipSilhouetteStore.instance.debugUse(null);
    LocalHangarMakerLogos.instance.debugUse({});
  });

  // User 11-14: "这样卡片高度就会不一样，还是在右下角吧" / "我是说图片的右下角".
  // The logo sits in the art's lower-right corner and the silhouette in the
  // card's: neither overlaps text or the other, and a card is exactly as tall
  // with them as without them.
  for (final english in [false, true]) {
    for (final width in [280.0, 385.0]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets(
          'marks keep card height and overlap nothing: ${english ? 'en' : 'zh'} $width x$scale',
          (tester) async {
            size(tester, Size(width * 4 + 14 * 3 + 40, 900));
            Future<List<double>> heights() async {
              await tester.pumpWidget(
                _stressGrid(GlobalKey(), width, english, textScale: scale),
              );
              await _settleImages(tester);
              expect(tester.takeException(), isNull);
              return [
                for (var i = 0; i < _stress.length; i++)
                  tester
                      .getSize(
                        find.byKey(
                          ValueKey('community-ship-card-${_ref(200 + i)}'),
                        ),
                      )
                      .height,
              ];
            }

            ShipSilhouetteStore.instance.debugUse(null);
            LocalHangarMakerLogos.instance.debugUse({});
            final plain = await heights();
            await tester.pumpWidget(const SizedBox());
            _usePreviewArt();
            final marked = await heights();
            expect(marked, plain);

            var logos = 0;
            for (var i = 0; i < _stress.length; i++) {
              final ref = _ref(200 + i);
              final card = tester.getRect(
                find.byKey(ValueKey('community-ship-card-$ref')),
              );
              final marks = [
                for (final key in [
                  'community-ship-maker-$ref',
                  'community-ship-silhouette-$ref',
                ])
                  if (find.byKey(ValueKey(key)).evaluate().isNotEmpty)
                    tester.getRect(find.byKey(ValueKey(key))),
              ];
              if (find
                  .byKey(ValueKey('community-ship-maker-$ref'))
                  .evaluate()
                  .isNotEmpty) {
                logos++;
              }
              final texts = find.descendant(
                of: find.byKey(ValueKey('community-ship-card-$ref')),
                matching: find.byType(Text),
              );
              final tags = find.descendant(
                of: find.byKey(ValueKey('community-ship-tags-$ref')),
                matching: find.byType(ShipClassificationTag),
              );
              expect(tags, findsNWidgets(3));
              final others = [
                for (final tag in tester.widgetList(tags))
                  tester.getRect(find.byWidget(tag)),
                for (final text in tester.widgetList<Text>(texts))
                  tester.getRect(find.byWidget(text)),
              ];
              for (final mark in marks) {
                expect(card.contains(mark.topLeft), isTrue);
                expect(
                  card.contains(mark.bottomRight - const Offset(1, 1)),
                  isTrue,
                );
                for (final other in others) {
                  expect(
                    other.intersect(mark).width > .5 &&
                        other.intersect(mark).height > .5,
                    isFalse,
                    reason: '${_stress[i].$3}: $other under mark $mark',
                  );
                }
              }
              final logo = find.byKey(ValueKey('community-ship-maker-$ref'));
              if (logo.evaluate().isNotEmpty) {
                final art = tester.getRect(
                  find.byKey(ValueKey('community-ship-card-image-$ref')),
                );
                final mark = tester.getRect(logo);
                expect(art.contains(mark.topLeft), isTrue);
                expect(
                  art.contains(mark.bottomRight - const Offset(1, 1)),
                  isTrue,
                );
                // Lower-right corner of the art: flush with the name strip's end.
                expect(art.right - mark.right, lessThanOrEqualTo(10.5));
                expect(art.bottom - mark.bottom, lessThanOrEqualTo(8.5));
              }
              if (marks.length == 2) {
                expect(marks[0].overlaps(marks[1]), isFalse);
              }
            }
            // The private package carries the Fan Kit originals; public source
            // has none and every card simply shows no logo. Large text may give
            // a narrow card's corner back to the price.
            if (_logoBytes.isNotEmpty && scale == 1 && width == 385) {
              expect(logos, _stress.length);
            }
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }

  testWidgets('missing logo pack shows no logo and no placeholder', (
    tester,
  ) async {
    LocalHangarMakerLogos.instance.debugUse({});
    await _card(tester, index: 0);
    expect(
      find.byKey(ValueKey('community-ship-maker-${_ref(1)}')),
      findsNothing,
    );
    expect(find.byType(ShipClassificationTag), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'silhouette steps aside for large text, the logo stays on the art',
    (tester) async {
      _usePreviewArt();
      await _card(tester, index: 1);
      final silhouette = find.byKey(
        ValueKey('community-ship-silhouette-${_ref(2)}'),
      );
      final logo = find.byKey(ValueKey('community-ship-maker-${_ref(2)}'));
      if (_previewPack != null) expect(silhouette, findsOneWidget);
      if (_logoBytes.isNotEmpty) expect(logo, findsOneWidget);
      await _card(tester, index: 1, textScale: 3);
      expect(silhouette, findsNothing);
      // The logo lives on the art, which large text does not crowd.
      if (_logoBytes.isNotEmpty) expect(logo, findsOneWidget);
      expect(find.textContaining('替代船'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  // Offline visual review (STARBRIDGE_TEST_VISUAL_DIR): the user's own screenshot
  // ships and the longest real cases.
  for (final surface in [
    ('community-dark', false, AppearanceMode.dark),
    ('community-light', false, AppearanceMode.light),
    ('main-fleet-dark', true, AppearanceMode.dark),
  ]) {
    testWidgets('visual ${surface.$1}', (tester) async {
      size(tester, const Size(2000, 1100));
      _usePreviewArt();
      final key = GlobalKey();
      await tester.pumpWidget(_page(key, fleet: surface.$2, mode: surface.$3));
      await _settleImages(tester);
      expect(find.byType(CommunityShipCard), findsWidgets);
      await _capture(tester, key, 'real-${surface.$1}');
      await tester.pumpWidget(const SizedBox());
    }, skip: _output == null);
  }
  for (final english in [false, true]) {
    for (final width in [280.0, 385.0]) {
      final name = 'longest-${english ? 'en' : 'zh'}-${width.toInt()}';
      testWidgets('visual $name', (tester) async {
        size(tester, Size(width * 4 + 14 * 3 + 40, 640));
        _usePreviewArt();
        final key = GlobalKey();
        await tester.pumpWidget(_stressGrid(key, width, english));
        await _settleImages(tester);
        await _capture(tester, key, name);
        await tester.pumpWidget(const SizedBox());
      }, skip: _output == null);
    }
  }
}
