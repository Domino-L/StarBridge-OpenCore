import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_favorite_dialog.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_favorite_ships.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_local_projection.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';

import '../settings/local_privacy_page_test.dart' show app, viewport;

void main() {
  final a = projectProfileShip(
    const LocalHangarShip(id: 'a', title: 'Carrack', cn: '克拉克', priceUsd: 600),
  ).withFormerOwnership(true);
  final b = projectProfileShip(
    const LocalHangarShip(id: 'b', title: 'Carrack', cn: '克拉克', priceUsd: 600),
  ).withFormerOwnership(true);
  testWidgets('favorite card and details identify formerly owned model', (
    tester,
  ) async {
    viewport(tester, const Size(800, 600));
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 150,
              child: PersonalProfileFavoriteShips(ships: [a], span: 1),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('曾拥有'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('profile-favorite-ship-a')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('曾拥有')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'former model is selectable once and keeps an earlier favorite ID',
    (tester) async {
      viewport(tester, const Size(800, 900));
      await tester.pumpWidget(
        app(
          Scaffold(
            body: ProfileFavoriteDialog(
              local: PersonalProfileLocalView(
                choices: [b],
                retainedChoices: [a, b],
                favoriteShipIds: ['a'],
                hangarAvailable: true,
                remoteAvailable: false,
              ),
              selected: const ['a'],
              capacity: 3,
              reserved: const {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsOneWidget);
      expect(find.byKey(const Key('profile-favorite-a')), findsOneWidget);
      expect(find.text('克拉克 · 曾拥有'), findsOneWidget);
      await tester.tap(find.byKey(const Key('profile-favorite-a')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-favorite-b')), findsOneWidget);
      await tester.tap(find.byKey(const Key('profile-favorite-b')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('profile-favorite-b')),
            )
            .value,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
