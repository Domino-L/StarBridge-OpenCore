// build 68 acceptance (user 2026-11-06: "显示"): the large favourite card shows
// its maker mark even when only one ship is chosen. The profile used only the
// RSI liner text, so an Idris-P whose liner is not a maker name lost the Aegis
// mark the hangar wall shows. The profile now follows the hangar's maker rule.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_manufacturers.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_favorite_maker.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_favorite_ships.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_local_projection.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_showcase_frame.dart';

const _idris = LocalHangarShip(
  id: 'idris',
  title: 'Idris-P',
  liner: 'Idris-P Frigate',
  manufacturer: 'Aegis Dynamics',
);

void main() {
  setUp(
    () => LocalHangarMakerLogos.instance.debugUse({
      LocalHangarMakerLogos.asset('aegis', dark: true),
      LocalHangarMakerLogos.asset('anvil', dark: true),
    }),
  );
  tearDown(() => LocalHangarMakerLogos.instance.debugUse(const {}));

  test('the profile finds the maker the same way as the hangar', () {
    for (final (ship, expected) in [
      (_idris, 'Aegis Dynamics'),
      (
        const LocalHangarShip(id: 'b', title: 'F8C', liner: 'Anvil'),
        'Anvil Aerospace',
      ),
      (
        const LocalHangarShip(
          id: 'c',
          title: 'X',
          manufacturer: 'aegs',
          liner: 'Pack',
        ),
        'Aegis Dynamics',
      ),
      (
        const LocalHangarShip(
          id: 'd',
          title: 'Y',
          manufacturer: 'Odd Works',
          liner: 'Pack',
        ),
        'Odd Works',
      ),
      (const LocalHangarShip(id: 'e', title: 'Z', liner: 'Pack'), 'Pack'),
      (const LocalHangarShip(id: 'f', title: 'W'), ''),
    ]) {
      expect(projectProfileShip(ship).manufacturer, expected, reason: ship.id);
    }
    expect(
      ProfileFavoriteMaker.shown(projectProfileShip(_idris).manufacturer)?.key,
      'aegis',
    );
  });

  testWidgets('one chosen ship still carries its maker mark', (tester) async {
    final ship = projectProfileShip(_idris);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppStringsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppStrings.supportedLocales,
        theme: buildStarBridgeTheme(
          FutureRestraintStyle.resolve(AppearanceMode.dark),
          const Locale('zh', 'CN'),
        ),
        home: Scaffold(
          body: ProfileShowcaseScope(
            child: SingleChildScrollView(
              child: PersonalProfileFavoriteShips(ships: [ship], span: 3),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-favorite-showcase')), findsOneWidget);
    expect(
      find.byKey(const Key('profile-favorite-maker-idris')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('profile-favorite-fankit-notice')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
