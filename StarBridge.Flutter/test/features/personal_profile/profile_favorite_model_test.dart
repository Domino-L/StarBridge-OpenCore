import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_edit_groups.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_favorite_dialog.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_favorite_modules.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_presentation.dart';

import 'local_personal_profile_test.dart' show Harness, edit, shipA, shipB;

// User 11-07: "不能重复，即使该用户有两艘一样的船也不行" — a page shows each
// ship model once: across modules, within a module and in the 4th slots.

const ravenOne = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1';
const ravenTwo = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa2';
const idris = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb1';
const custom = 'ccccccccccccccccccccccccccccccc1';
const customAgain = 'ccccccccccccccccccccccccccccccc2';

const other = 'ddddddddddddddddddddddddddddddd1';

Map<String, Object?> page({
  bool editable = false,
  required Map<String, List<String>> modules,
  Map<String, String>? extras,
}) {
  Map<String, Object?> row(String code, String title, String catalog) => {
    'code': code,
    'displayName': code,
    'roleCategory': '',
    'presentation': {'title': title, 'catalogId': catalog},
  };
  final content = <String, Object?>{
    'introduction': '',
    'favoriteShipCodes': [for (final ids in modules.values) ...ids],
    'modules': [
      for (final (index, entry) in modules.entries.indexed)
        {
          'id': entry.key,
          'span': 3,
          'isVisible': true,
          'order': index,
          'position': index * 3,
          'favoriteShipIds': entry.value,
        },
    ],
    'favoriteShowcaseExtras': ?extras,
  };
  return {
    'schemaVersion': 1,
    'editable': editable,
    'profile': {
      'isPublic': true,
      'revision': 1,
      'avatarStyle': 0,
      'wallpaperId': 'none',
      if (editable)
        'presentation': {
          'schemaVersion': 1,
          'sourceVersion': 'a' * 64,
          'origins': {
            for (final group in PersonalProfilePresentation.groups)
              group: 'custom',
          },
        },
      'identity': {
        'callSign': 'Pilot',
        'gameHandle': 'Pilot',
        'avatarAssetId': null,
      },
      'content': content,
      'hangar': {
        'ships': [
          row(ravenOne, 'Raven EX', 'raven-ex'),
          row(ravenTwo, 'Raven EX', 'RAVEN-EX'),
          row(idris, 'Idris-P', 'idris-p'),
          row(custom, 'Odd Hull', 'odd-hull'),
          row(other, 'Carrack', 'carrack'),
        ],
      },
    },
  };
}

List<String>? picks(PersonalProfileSnapshot snapshot, String module) => snapshot
    .moduleLayout
    .singleWhere((e) => e.moduleId == module)
    .favoriteShipIds;

PersonalProfileShipSummary ship(String id, String name, {String? catalog}) =>
    PersonalProfileShipSummary(
      identity: PersonalProfileShipIdentity(
        runtimeId: id,
        englishName: name,
        simplifiedChineseName: name,
        traditionalChineseName: name,
        catalogId: catalog,
      ),
      manufacturer: 'Maker',
      imageAsset: '',
      roleKey: '',
      crewLabel: '',
      sizeKey: '',
      valueLabel: '',
    );

final ships = [
  ship(ravenOne, 'Raven EX', catalog: 'RAVEN-EX'),
  ship(ravenTwo, 'Raven EX (gift)', catalog: 'raven-ex'),
  ship(idris, 'Idris-P', catalog: 'idris-p'),
  ship(custom, 'Odd  Hull'),
  ship(customAgain, ' odd hull '),
];

PersonalProfileModuleLayoutItem module(
  String id,
  List<String> picks, [
  List<String>? extra,
]) => PersonalProfileModuleLayoutItem(
  moduleId: id,
  size: PersonalProfileModuleSize.three,
  isVisible: true,
  position: 0,
  favoriteShipIds: picks,
  showcaseExtra: extra,
);

void main() {
  final models = ProfileFavoriteModules.modelsOf(ships);

  test('model key follows the hangar rule: catalog ID, else English name', () {
    expect(models[ravenOne], 'catalog:raven-ex');
    expect(models[ravenTwo], 'catalog:raven-ex');
    expect(models[idris], 'catalog:idris-p');
    expect(models[custom], 'name:odd hull');
    expect(models[customAgain], 'name:odd hull');
  });

  test('reading shows the first ship of each model and keeps the slots', () {
    final shown = ProfileFavoriteModules.firstOfEachModel([
      module('favorite-ships', [ravenOne, ravenTwo, idris], [customAgain]),
      module('favorite-ships-1', [custom, 'unknown-ship'], [idris]),
      module('favorite-ships-2', [ravenTwo], const []),
    ], models);
    expect(shown[0].favoriteShipIds, [ravenOne, idris]);
    expect(shown[0].showcaseExtra, [customAgain]);
    expect(shown[1].favoriteShipIds, ['unknown-ship']);
    expect(shown[1].showcaseExtra, isEmpty, reason: 'slot stays, repeat hidden');
    expect(shown[2].favoriteShipIds, isEmpty);
    expect(shown[2].showcaseExtra, isEmpty);
    expect(
      ProfileFavoriteModules.firstShipOfEachModel(ships).map(
        (e) => e.identity.runtimeId,
      ),
      [ravenOne, idris, custom],
    );
  });

  test('reserved and valid compare models, 4th slots included', () {
    final layout = [
      module('favorite-ships', [ravenOne], [idris]),
      module('favorite-ships-1', const []),
    ];
    expect(
      ProfileFavoriteModules.reserved(
        layout,
        'favorite-ships-1',
        models: models,
      ),
      {'catalog:raven-ex', 'catalog:idris-p'},
    );
    expect(ProfileFavoriteModules.valid(layout, models: models), isTrue);
    expect(
      ProfileFavoriteModules.valid([
        layout[0],
        module('favorite-ships-1', [ravenTwo]),
      ], models: models),
      isFalse,
    );
    expect(
      ProfileFavoriteModules.valid([
        module('favorite-ships', [ravenOne, ravenTwo]),
      ], models: models),
      isFalse,
    );
    expect(
      ProfileFavoriteModules.valid([
        module('favorite-ships', [custom], [customAgain]),
      ], models: models),
      isFalse,
    );
  });

  test('a saved repeat is hidden on read; the saved page stays as it was', () async {
    // The default harness hangar holds two Carracks (same model).
    final h = Harness();
    addTearDown(h.close);
    await h.port.save(edit(await h.port.read(), ids: [shipA, shipB]));
    final saved = jsonEncode(h.connection.content);
    final shown = await h.port.read();
    expect(
      shown.moduleLayout
          .singleWhere((e) => e.moduleId == 'favorite-ships')
          .favoriteShipIds,
      [shipA],
    );
    expect(shown.favoriteShips.map((e) => e.identity.runtimeId), [shipA]);
    expect(jsonEncode(h.connection.content), saved);
    expect(saved, contains(shipB));
  });

  test('a visitor read shows each model once (catalog ID from the Host)', () {
    final snapshot = parsePersonalProfileSnapshot(
      page(
        modules: {
          'favorite-ships': [ravenOne, ravenTwo],
          'favorite-ships-1': [idris],
        },
      ),
    );
    expect(picks(snapshot, 'favorite-ships'), [ravenOne]);
    expect(
      snapshot.favoriteShips.map((e) => e.identity.runtimeId),
      [ravenOne, idris],
    );
  });

  test('an earlier 4th ship wins over a later module pick, and stays shown', () {
    // CX-FAV-MODEL-DEDUPE-073: the flat list puts module picks before the
    // 4th ships, the layout does not; the visitor must still see the model.
    final snapshot = parsePersonalProfileSnapshot(
      page(
        modules: {
          'favorite-ships': [idris, custom, other],
          'favorite-ships-1': [ravenTwo],
        },
        extras: {'favorite-ships': ravenOne},
      ),
    );
    final first = snapshot.moduleLayout.singleWhere(
      (e) => e.moduleId == 'favorite-ships',
    );
    expect(first.showcaseExtra, [ravenOne]);
    expect(picks(snapshot, 'favorite-ships-1'), isEmpty);
    expect(
      snapshot.favoriteShips.map((e) => e.identity.runtimeId),
      containsAll([ravenOne, idris, custom, other]),
    );
    expect(
      snapshot.favoriteShips.map((e) => e.identity.runtimeId),
      isNot(contains(ravenTwo)),
    );
  });

  test('a layout save clears a hidden 4th ship; other saves leave it', () {
    // CX-FAV-MODEL-DEDUPE-073: the saved map still holds the hidden repeat.
    final displayed = parsePersonalProfileSnapshot(
      page(
        editable: true,
        modules: {
          'favorite-ships': [ravenOne, idris, custom],
        },
        extras: {'favorite-ships': ravenTwo},
      ),
    );
    final first = displayed.moduleLayout.singleWhere(
      (e) => e.moduleId == 'favorite-ships',
    );
    expect(first.showcaseExtra, isEmpty);
    PersonalProfileEdit request(List<PersonalProfileModuleLayoutItem> layout) =>
        PersonalProfileEdit(
          callSign: displayed.callSign,
          about: 'changed',
          avatarStyle: displayed.avatarStyle,
          wallpaperId: displayed.wallpaperId,
          visibility: displayed.visibility,
          moduleLayout: layout,
        );
    final untouched = personalProfileEditGroups(
      displayed,
      request(displayed.moduleLayout),
    );
    expect(untouched.containsKey('layout'), isFalse);
    final swapped = personalProfileEditGroups(displayed, request([
      for (final item in displayed.moduleLayout)
        item.moduleId == 'favorite-ships'
            ? item.copyWith(favoriteShipIds: [idris, custom, other])
            : item,
    ]));
    expect(swapped['layout']!['favoriteShowcaseExtras'], <String, String>{});
  });
  for (final locale in AppStrings.supportedLocales) {
    testWidgets('picker closes a model picked here or elsewhere $locale', (
      tester,
    ) async {
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
              local: PersonalProfileLocalView(
                choices: ships,
                favoriteShipIds: const [],
                hangarAvailable: true,
                remoteAvailable: true,
              ),
              selected: const [],
              capacity: 4,
              reserved: {models[idris]!},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(ProfileFavoriteDialog));
      final strings = AppStrings.of(element);
      StarBridgeCheckboxTile tile(String id) => tester.widget(
        find.byWidgetPredicate(
          (w) =>
              w is StarBridgeCheckboxTile &&
              w.controlKey == Key('profile-favorite-$id'),
        ),
      );

      expect(tile(idris).onChanged, isNull);
      expect(tile(idris).subtitle, strings.text('profile.favorites.used'));
      expect(tile(ravenTwo).onChanged, isNotNull);

      await tester.tap(find.byKey(const Key('profile-favorite-$ravenOne')));
      await tester.pumpAndSettle();
      expect(tile(ravenTwo).onChanged, isNull);
      expect(
        tile(ravenTwo).subtitle,
        strings.text('profile.favorites.sameModel'),
      );
      expect(tile(ravenOne).onChanged, isNotNull, reason: 'can be unpicked');

      await tester.tap(find.byKey(const Key('profile-favorite-$custom')));
      await tester.pumpAndSettle();
      expect(tile(customAgain).onChanged, isNull);

      await tester.tap(find.byKey(const Key('profile-favorite-$ravenOne')));
      await tester.pumpAndSettle();
      expect(tile(ravenTwo).onChanged, isNotNull);
    });
  }
}
