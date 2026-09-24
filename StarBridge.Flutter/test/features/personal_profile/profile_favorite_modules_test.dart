import 'package:flutter/material.dart';
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

import 'local_personal_profile_test.dart' show Harness, edit, shipA, shipB;

void main() {
  test('old twelve selections are partitioned without writing, losing, or hiding references', () {
    final ids = List.generate(12, (i) => '$i');
    final layout = ProfileFavoriteModules.materialize(const [
      PersonalProfileModuleLayoutItem(
        moduleId: 'favorite-ships',
        size: PersonalProfileModuleSize.one,
        isVisible: true,
        position: 0,
      ),
    ], ids);
    expect(ProfileFavoriteModules.selections(layout), ids);
    expect(ProfileFavoriteModules.valid(layout), isTrue);
    expect(layout.where((e) => e.isVisible), hasLength(5));
    expect(layout.lastWhere((e) => e.isVisible).position, greaterThan(8));
    expect(
      ProfileFavoriteModules.materialize(layout, ids).map((e) => e.moduleId),
      layout.map((e) => e.moduleId),
    );
  });
  test(
    'module capacity, hidden reservations, independent edits and large layouts',
    () {
      var layout = ProfileFavoriteModules.materialize(const [], [shipA, shipB]);
      final first = layout.firstWhere((e) => e.moduleId == 'favorite-ships');
      layout = PersonalProfileLayout.show(layout, first.moduleId).layout;
      final resize = PersonalProfileLayout.resize(
        layout,
        first.moduleId,
        PersonalProfileModuleSize.one,
      );
      expect(resize.failure, PersonalProfileLayoutFailure.selectionExceedsSize);
      expect(ProfileFavoriteModules.selections(resize.layout), [shipA, shipB]);
      layout = ProfileFavoriteModules.add(layout);
      expect(ProfileFavoriteModules.reserved(layout, 'favorite-ships-1'), {
        shipA,
        shipB,
      });
      expect(
        ProfileFavoriteModules.valid([
          for (final e in layout)
            e.moduleId == 'favorite-ships-1'
                ? e.copyWith(favoriteShipIds: [shipA])
                : e,
        ]),
        isFalse,
      );
      layout = PersonalProfileLayout.hide(layout, first.moduleId).layout;
      expect(ProfileFavoriteModules.reserved(layout, 'favorite-ships-1'), {
        shipA,
        shipB,
      });
      for (var i = 0; i < 20; i++) {
        layout = ProfileFavoriteModules.add(layout);
      }
      expect(layout.where((e) => e.isVisible), hasLength(21));
      final occupied = PersonalProfileLayout.occupiedCells(layout);
      expect(occupied.where((cell) => cell), hasLength(63));
      expect(layout.map((e) => e.moduleId).toSet().length, layout.length);
    },
  );
  test(
    'module selections save and reload independently without a remote write',
    () async {
      final h = Harness();
      addTearDown(h.close);
      await h.port.save(edit(await h.port.read(), ids: [shipA, shipB]));
      final snapshot = await h.port.read();
      var layout = ProfileFavoriteModules.add(snapshot.moduleLayout);
      layout = [
        for (final item in layout)
          if (item.moduleId == 'favorite-ships')
            item.copyWith(favoriteShipIds: [shipA])
          else if (item.moduleId == 'favorite-ships-1')
            item.copyWith(favoriteShipIds: [shipB])
          else
            item,
      ];
      final request = PersonalProfileEdit(
        callSign: snapshot.callSign,
        about: snapshot.about,
        avatarStyle: snapshot.avatarStyle,
        wallpaperId: snapshot.wallpaperId,
        visibility: snapshot.visibility,
        moduleLayout: layout,
      );
      expect(
        (await h.port.save(request)).outcome,
        PersonalProfileActionOutcome.completed,
      );
      final reopened = await h.port.read();
      expect(
        reopened.moduleLayout
            .singleWhere((e) => e.moduleId == 'favorite-ships')
            .favoriteShipIds,
        [shipA],
      );
      expect(
        reopened.moduleLayout
            .singleWhere((e) => e.moduleId == 'favorite-ships-1')
            .favoriteShipIds,
        [shipB],
      );
      expect(h.remote.writes, 0);
    },
  );
  for (final locale in AppStrings.supportedLocales) {
    testWidgets(
      'picker capacity and cross-module duplicate prevention $locale',
      (tester) async {
        final h = Harness();
        addTearDown(h.close);
        late PersonalProfileSnapshot snapshot;
        await tester.runAsync(() async {
          snapshot = await h.port.read();
        });
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
            home: Scaffold(
              body: ProfileFavoriteDialog(
                local: snapshot.local!,
                selected: const [],
                capacity: 1,
                reserved: {shipA},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const Key('profile-favorite-$shipA')),
              )
              .onChanged,
          isNull,
        );
        await tester.tap(find.byKey(const Key('profile-favorite-$shipB')));
        await tester.pumpAndSettle();
        expect(find.textContaining('1/1'), findsOneWidget);
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const Key('profile-favorite-$shipB')),
              )
              .value,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
