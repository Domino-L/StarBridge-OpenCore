import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_favorite_dialog.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_favorite_modules.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_layout.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module_grid.dart';

import 'local_personal_profile_test.dart' show Harness, edit, shipA, shipB;

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
    for (final mode in AppearanceMode.values) {
      for (final width in [360.0, 1280.0]) {
        testWidgets(
          'independent modules fit $locale $mode $width at 150% text',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(width, 1400);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPhysicalSize);
            final h = Harness();
            addTearDown(h.close);
            late PersonalProfileSnapshot snapshot;
            await tester.runAsync(() async {
              await h.port.save(edit(await h.port.read(), ids: [shipA, shipB]));
              snapshot = await h.port.read();
            });
            var projection = PersonalProfileProjection.fromSnapshot(snapshot);
            var layout = ProfileFavoriteModules.add(projection.moduleLayout);
            layout = [
              for (final item in layout)
                if (item.moduleId == 'favorite-ships')
                  item.copyWith(
                    favoriteShipIds: [shipA],
                    size: PersonalProfileModuleSize.one,
                  )
                else if (item.moduleId == 'favorite-ships-1')
                  item.copyWith(
                    favoriteShipIds: [shipB],
                    size: PersonalProfileModuleSize.two,
                  )
                else
                  item.copyWith(isVisible: false, position: -1),
            ];
            layout = PersonalProfileLayout.normalize(layout);
            late StateSetter update;
            await tester.pumpWidget(
              MaterialApp(
                locale: locale,
                supportedLocales: AppStrings.supportedLocales,
                localizationsDelegates: const [
                  AppStringsDelegate(),
                  ...GlobalMaterialLocalizations.delegates,
                ],
                theme: buildStarBridgeTheme(
                  FutureRestraintStyle.resolve(mode).withReducedMotion(true),
                  locale,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(1.5)),
                  child: child!,
                ),
                home: Scaffold(
                  body: StatefulBuilder(
                    builder: (context, setState) {
                      update = setState;
                      return SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: PersonalProfileModuleGrid(
                            projection: projection,
                            visitorView: false,
                            editing: true,
                            layout: layout,
                            onLayoutChanged: (value) =>
                                setState(() => layout = value),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const Key('profile-favorite-ship-$shipA')),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('profile-favorite-ship-$shipB')),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            if (const bool.fromEnvironment('PROFILE_MODULE_GOLDENS') &&
                locale.countryCode == 'CN' &&
                mode == AppearanceMode.dark) {
              await expectLater(
                find.byType(Scaffold),
                matchesGoldenFile('../../../build/profile_modules_$width.png'),
              );
            }
            final control = find.byKey(
              const Key('profile-module-edit-favorite-ships-1'),
            );
            await tester.ensureVisible(control);
            await tester.tap(control);
            await tester.pumpAndSettle();
            expect(find.byType(ProfileFavoriteDialog), findsOneWidget);
            expect(
              tester
                  .widget<CheckboxListTile>(
                    find.byKey(const Key('profile-favorite-$shipA')),
                  )
                  .onChanged,
              isNull,
            );
            expect(tester.takeException(), isNull);
            // A refreshed/invalidated projection must close the old selection route.
            update(
              () =>
                  projection = projection.copyWith(callSign: 'Changed account'),
            );
            await tester.pumpAndSettle();
            expect(find.byType(ProfileFavoriteDialog), findsNothing);
            expect(
              layout
                  .singleWhere((e) => e.moduleId == 'favorite-ships-1')
                  .favoriteShipIds,
              [shipB],
            );
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}
