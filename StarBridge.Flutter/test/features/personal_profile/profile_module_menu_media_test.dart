import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_favorite_modules.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_favorite_ships.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_layout.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module_controls.dart';

import 'local_personal_profile_test.dart' show Harness, edit, shipA, shipB;

Widget app(Locale locale, Widget child) => RepaintBoundary(
  key: const Key('profile-test-capture'),
  child: MaterialApp(
    locale: locale,
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStringsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    theme: buildStarBridgeTheme(
      FutureRestraintStyle.resolve(AppearanceMode.dark).withReducedMotion(true),
      locale,
    ),
    home: Scaffold(body: child),
  ),
);

void main() {
  setUpAll(() async {
    if (const bool.fromEnvironment('PROFILE_MODULE_GOLDENS')) {
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
  for (final locale in AppStrings.supportedLocales) {
    testWidgets(
      'one repeatable favorite menu entry preserves hidden selections $locale',
      (tester) async {
        var layout = PersonalProfileLayout.normalize(const [
          PersonalProfileModuleLayoutItem(
            moduleId: 'favorite-ships',
            size: PersonalProfileModuleSize.one,
            isVisible: false,
            position: -1,
            favoriteShipIds: [shipA],
          ),
          PersonalProfileModuleLayoutItem(
            moduleId: 'favorite-ships-1',
            size: PersonalProfileModuleSize.two,
            isVisible: false,
            position: -1,
            favoriteShipIds: [shipB],
          ),
        ]);
        await tester.pumpWidget(
          app(
            locale,
            StatefulBuilder(
              builder: (context, setState) => Align(
                alignment: Alignment.topLeft,
                child: PersonalProfileAddModuleButton(
                  hiddenModuleIds: [
                    ProfileFavoriteModules.addAction,
                    for (final item in layout)
                      if (!item.isVisible) item.moduleId,
                  ],
                  onSelected: (id) => setState(() {
                    expect(id, ProfileFavoriteModules.addAction);
                    layout = ProfileFavoriteModules.add(layout);
                  }),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final title = AppStrings.resolve(locale).text('profile.ships.title');
        for (var count = 1; count <= 4; count++) {
          await tester.tap(find.byType(PersonalProfileAddModuleButton));
          await tester.pumpAndSettle();
          final entries = tester
              .widgetList<PopupMenuItem<String>>(
                find.byType(PopupMenuItem<String>),
              )
              .toList();
          expect(
            entries.where((e) => e.value == ProfileFavoriteModules.addAction),
            hasLength(1),
          );
          expect(
            entries.any((e) => PersonalProfileModuleIds.isFavorite(e.value!)),
            isFalse,
          );
          expect(find.text(title), findsOneWidget);
          if (const bool.fromEnvironment('PROFILE_MODULE_GOLDENS') &&
              locale.countryCode == 'CN' &&
              count == 1) {
            await expectLater(
              find.byKey(const Key('profile-test-capture')),
              matchesGoldenFile('../../../build/profile_single_add_menu.png'),
            );
          }
          await tester.tap(find.text(title));
          await tester.pumpAndSettle();
          expect(
            layout.where(
              (e) =>
                  e.isVisible &&
                  PersonalProfileModuleIds.isFavorite(e.moduleId),
            ),
            hasLength(count),
          );
          expect(ProfileFavoriteModules.selections(layout), [shipA, shipB]);
          expect(ProfileFavoriteModules.valid(layout), isTrue);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'favorite uses square thumbnail while details retain original wide image',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final h = Harness();
      addTearDown(h.close);
      h.hangar.snapshot = const LocalHangarSnapshot(
        revision: 1,
        ships: [
          LocalHangarShip(
            id: shipA,
            title: 'Carrack',
            imageAsset: 'assets/ships/catalog-carrack.jpg',
            thumbnailAsset: 'assets/ships/catalog-square-carrack.png',
          ),
          LocalHangarShip(
            id: shipB,
            title: 'No square media',
            imageAsset: 'assets/ships/catalog-carrack.jpg',
          ),
        ],
      );
      late PersonalProfileSnapshot snapshot;
      await tester.runAsync(() async {
        await h.port.save(edit(await h.port.read(), ids: [shipA, shipB]));
        snapshot = await h.port.read();
      });
      await tester.pumpWidget(
        app(
          const Locale('zh', 'CN'),
          SizedBox(
            height: 200,
            child: PersonalProfileFavoriteShips(
              ships: snapshot.favoriteShips,
              span: 3,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final image = find.byKey(const Key('profile-favorite-ship-image-$shipA'));
      expect(
        ((tester.widget<Image>(image).image as ResizeImage).imageProvider
                as AssetImage)
            .assetName,
        'assets/ships/catalog-square-carrack.png',
      );
      expect(tester.widget<Image>(image).fit, BoxFit.cover);
      expect(find.textContaining('建议机组'), findsNothing);
      expect(tester.getSize(image).width, tester.getSize(image).height);
      if (const bool.fromEnvironment('PROFILE_MODULE_GOLDENS')) {
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/ships/catalog-square-carrack.png'),
            tester.element(image),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<RawImage>(
                find.descendant(of: image, matching: find.byType(RawImage)),
              )
              .image,
          isNotNull,
        );
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('../../../build/profile_square_thumbnail.png'),
        );
      }
      expect(
        find.byKey(const Key('profile-favorite-ship-image-$shipB')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('profile-favorite-ship-$shipA')));
      await tester.pumpAndSettle();
      final detail = tester.widget<Image>(
        find.descendant(of: find.byType(Dialog), matching: find.byType(Image)),
      );
      expect(
        (detail.image as AssetImage).assetName,
        'assets/ships/catalog-carrack.jpg',
      );
      expect(detail.fit, BoxFit.contain);
      expect(find.textContaining('建议机组'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
