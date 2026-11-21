import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_collaboration.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_edit_row.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_main_role.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_playstyle_editor.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_steam_header.dart';

import 'local_personal_profile_test.dart' show Harness, edit;

// Main role (user 11-05, plan B): at most one of the skilled roles, set with
// words in the editor, saved beside the local file; the HK page only once its
// server returned the field.
Widget _app(Widget child) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark).withReducedMotion(true),
    const Locale('zh', 'CN'),
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  test('only a ticked role is marked, at most one', () {
    final roles = ProfileCollaboration.tags(['pilot', 'gunner'], 'roles')!;
    final marked = ProfileMainRole.mark(roles, 'gunner');
    expect([for (final r in marked) r.isPrimary], [false, true]);
    expect(
      ProfileMainRole.mark(roles, 'medic').any((r) => r.isPrimary),
      isFalse,
    );
    expect(ProfileMainRole.mark(roles, '').any((r) => r.isPrimary), isFalse);
    expect(ProfileMainRole.mark(roles, null), same(roles));
  });

  test(
    'local save keeps the main role beside playStyle and reads it back',
    () async {
      final h = Harness();
      addTearDown(h.close);
      final initial = await h.port.read();
      expect(initial.showcaseData.mainRoleEditable, isTrue);
      await h.port.save(
        edit(
          initial,
          playStyle: const PersonalProfilePlayStyle(
            roles: ['pilot', 'gunner'],
            mainRole: 'gunner',
          ),
        ),
      );
      final saved = h.connection.content!;
      expect(saved['mainRole'], 'gunner');
      expect((saved['playStyle'] as Map).containsKey('mainRole'), isFalse);
      final read = await h.port.read();
      expect(
        ProfileMainRole.idOf(PersonalProfileProjection.fromSnapshot(read)),
        'gunner',
      );

      // An edit that does not touch the main role keeps it; '' clears it.
      await h.port.save(
        edit(
          read,
          playStyle: const PersonalProfilePlayStyle(roles: ['pilot', 'gunner']),
        ),
      );
      expect(h.connection.content!['mainRole'], 'gunner');
      await h.port.save(
        edit(
          await h.port.read(),
          playStyle: const PersonalProfilePlayStyle(mainRole: ''),
        ),
      );
      expect(h.connection.content!['mainRole'], '');
    },
  );

  testWidgets('the editor says in words what each role is and does', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.close);
    final page = await tester.runAsync(h.port.read);
    PersonalProfilePlayStyle? changed;
    await tester.pumpWidget(
      _app(
        PersonalProfilePlayStyleEditor(
          projection: PersonalProfileProjection.fromSnapshot(page!),
          initial: const PersonalProfilePlayStyle(roles: ['pilot', 'gunner']),
          enabled: true,
          onChanged: (value) => changed = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(
      find
          .descendant(
            of: find.byKey(const Key('profile-roles-editor')),
            matching: find.byType(ProfileEditGroupRow),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-main-role-picker')), findsOneWidget);
    expect(find.text('设为主岗位'), findsNWidgets(2));
    expect(find.text('主岗位 · 取消'), findsNothing);

    await tester.tap(find.byKey(const Key('profile-main-role-gunner')));
    await tester.pumpAndSettle();
    expect(changed!.mainRole, 'gunner');
    expect(find.text('主岗位 · 取消'), findsOneWidget);
    expect(find.text('设为主岗位'), findsOneWidget);

    // Another role moves it: still only one.
    await tester.tap(find.byKey(const Key('profile-main-role-pilot')));
    await tester.pumpAndSettle();
    expect(changed!.mainRole, 'pilot');
    expect(find.text('主岗位 · 取消'), findsOneWidget);

    // A second click removes it.
    await tester.tap(find.byKey(const Key('profile-main-role-pilot')));
    await tester.pumpAndSettle();
    expect(changed!.mainRole, '');
    expect(find.text('主岗位 · 取消'), findsNothing);

    // Unticking the main role removes it as the main role too.
    await tester.tap(find.byKey(const Key('profile-main-role-gunner')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-roles-gunner')));
    await tester.pumpAndSettle();
    expect(changed!.roles, ['pilot']);
    expect(changed!.mainRole, '');
    expect(find.byKey(const Key('profile-main-role-gunner')), findsNothing);
  });

  for (final visible in [true, false]) {
    testWidgets('visitors see the main role only with the roles showcase '
        '(shown: $visible)', (tester) async {
      final h = Harness();
      addTearDown(h.close);
      h.connection
        ..content = {
          'callSign': 'Main role',
          'introduction': '',
          'avatarStyle': 0,
          'wallpaperId': 'none',
          'preserveEmptyFields': true,
          'favoriteShipIds': <String>[],
          'modules': [
            {
              'id': 'skilled-roles',
              'span': 2,
              'isVisible': visible,
              'position': visible ? 0 : -1,
            },
          ],
          'playStyle': {
            'roles': ['pilot', 'gunner'],
          },
          'mainRole': 'gunner',
        }
        ..revision = 1
        ..operation = '0' * 32;
      final page = await tester.runAsync(h.port.read);
      final projection = PersonalProfileProjection.fromSnapshot(page!);
      for (final owner in [true, false]) {
        await tester.pumpWidget(
          _app(
            PersonalProfileSteamHeader(
              projection: projection,
              isSelf: owner,
              showAchievementCount: owner,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('profile-steam-main-role')),
          owner || visible ? findsOneWidget : findsNothing,
          reason: 'owner=$owner',
        );
      }
    });
  }

  test('an HK page without the field cannot set a main role', () {
    final roles = ProfileCollaboration.tags(['pilot'], 'roles')!;
    // A saved local '' replaces any marked main role, even one carried over.
    final carried = [
      for (final r in roles)
        PersonalProfileTagValue(
          labelKey: r.labelKey,
          category: r.category,
          isPrimary: true,
        ),
    ];
    expect(ProfileMainRole.mark(carried, '').any((r) => r.isPrimary), isFalse);
    expect(ProfileMainRole.mark(carried, null).single.isPrimary, isTrue);
  });
}
