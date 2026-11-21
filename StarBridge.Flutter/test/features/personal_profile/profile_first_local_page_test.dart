import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_local_personal_profile.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_avatar.dart';

import 'local_personal_profile_test.dart' show Harness, edit, shipA;

void main() {
  testWidgets('empty call sign avatar uses a placeholder', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildStarBridgeTheme(
          FutureRestraintStyle.resolve(AppearanceMode.dark),
          const Locale('en', 'US'),
        ),
        home: const Scaffold(
          body: PersonalProfileAvatar(callSign: '', styleIndex: 0, size: 72),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('?'), findsOneWidget);
  });
  setUpAll(() async {
    if (const bool.fromEnvironment('PROFILE_MODULE_GOLDENS')) {
      for (final font in {
        'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
        'Saira': 'assets/fonts/Saira-VF.ttf',
        'Rajdhani': 'assets/fonts/Rajdhani-SemiBold.ttf',
        'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
      }.entries) {
        await (FontLoader(
          font.key,
        )..addFont(rootBundle.load(font.value))).load();
      }
    }
  });

  test('legacy read failure blocks creation until a verified remote default returns', () async {
    final h = Harness(legacy: true);
    addTearDown(h.close);
    h.remote.available = false;
    final failed = await h.port.read();
    expect(failed.availability, PersonalProfileAvailability.unavailable);
    expect(failed.local, isNull);
    expect(
      (await h.port.save(edit(failed))).outcome,
      PersonalProfileActionOutcome.rejected,
    );
    expect(h.connection.content, isNull);
    h.remote.available = true;
    final first = await h.port.read();
    expect(first.allowEditing, isTrue);
    expect(first.local!.remoteAvailable, isTrue);
    expect(
      (await h.port.save(edit(first, ids: [shipA]))).outcome,
      PersonalProfileActionOutcome.completed,
    );
    await h.port.close();
    h.port = BridgeLocalPersonalProfile(
      h.session,
      remote: h.remote,
      hangar: () => h.hangar,
    );
    final reopened = await h.port.read();
    expect(reopened.callSign, 'Local call sign');
    expect(reopened.favoriteShips.single.identity.runtimeId, shipA);
    expect(h.connection.revision, 1);
    expect(h.remote.writes, 0);
  });
  for (final saved in [false, true]) {
    test(
      'legacy online adapter exception blocks editing without erasing saved content (saved=$saved)',
      () async {
        final h = Harness(legacy: true);
        addTearDown(h.close);
        if (saved) await h.port.save(edit(await h.port.read()));
        h.remote.readError = StateError('Offline fixture');
        final profile = await h.port.read();
        expect(profile.availability, PersonalProfileAvailability.unavailable);
        expect(profile.local, isNull);
        expect(
          (await h.port.save(edit(profile))).outcome,
          PersonalProfileActionOutcome.rejected,
        );
        expect(h.connection.revision, saved ? 1 : 0);
        expect(h.remote.writes, 0);
      },
    );
  }

  test(
    'local read failure is never an empty profile or a creation lease',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.remote.available = false;
      h.connection.localReadError = 'profile_local.read_failed';
      final failed = await h.port.read();
      expect(failed.availability, PersonalProfileAvailability.unavailable);
      expect(failed.failureKey, 'profile.local.readFailed');
      expect(failed.local, isNull);
      expect(
        (await h.port.save(edit(failed))).outcome,
        PersonalProfileActionOutcome.rejected,
      );
      expect(
        h.connection.requests.where(
          (e) => e.name == 'personalProfile.localSave',
        ),
        isEmpty,
      );
    },
  );

  for (final state in [
    'signedOut',
    'reauthorizationRequired',
    'providerUnavailable',
  ]) {
    test('first creation requires authenticated account: $state', () async {
      final h = Harness();
      addTearDown(h.close);
      h.remote.available = false;
      h.connection.state = state;
      final profile = await h.port.read();
      expect(
        profile.availability,
        isNot(PersonalProfileAvailability.available),
      );
      expect(profile.allowEditing, isFalse);
      expect(
        h.connection.requests.any(
          (e) => e.name.startsWith('personalProfile.local'),
        ),
        isFalse,
      );
    });
  }

  test(
    'late offline result cannot create a page after account generation changes',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.remote.pendingRead = Completer<PersonalProfileSnapshot>();
      final loading = h.port.read();
      await Future<void>.delayed(Duration.zero);
      h.session.advanceGeneration(8);
      h.remote.pendingRead!.complete(
        const PersonalProfileSnapshot.unavailable(),
      );
      final stale = await loading;
      expect(stale.availability, PersonalProfileAvailability.unavailable);
      expect(stale.local, isNull);
      expect(
        (await h.port.save(edit(stale))).outcome,
        PersonalProfileActionOutcome.rejected,
      );
    },
  );

  for (final locale in AppStrings.supportedLocales) {
    for (final mode in AppearanceMode.values) {
      for (final width in [360.0, 1280.0]) {
        for (final rich in [false, true]) {
          testWidgets(
            'legacy first page cancel, failure, retry and save $locale $mode $width rich=$rich',
            (tester) async {
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = Size(width, 1100);
              addTearDown(tester.view.resetDevicePixelRatio);
              addTearDown(tester.view.resetPhysicalSize);
              final h = Harness(legacy: true);
              // Keep both the absent-record response and the original rich review
              // account with existing roles, schedules and showcase entries.
              if (!rich) {
                h.remote.importedSnapshot = parsePersonalProfileSnapshot({
                  'schemaVersion': 1,
                  'editable': true,
                  'profile': {
                    'schemaVersion': 3,
                    'revision': 0,
                    'updatedAt': '1970-01-01T00:00:00Z',
                    'visibility': 'private',
                    'identity': {
                      'callSign': 'Fixture',
                      'gameHandle': 'SyntheticPilot',
                    },
                    'content': {},
                  },
                });
              }
              h.remote.available = false;
              final module = createPersonalProfileModule(h.port);
              await tester.runAsync(module.initialize);
              await tester.pumpWidget(
                MaterialApp(
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(1.5)),
                    child: child!,
                  ),
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
                  home: Scaffold(body: PersonalProfilePage(module: module)),
                ),
              );
              await tester.pumpAndSettle();
              final strings = AppStrings.resolve(locale);
              expect(
                find.text(strings.text('profile.error.ownerReadFailed')),
                findsOneWidget,
              );
              expect(find.byKey(const Key('profile-edit')), findsNothing);
              expect(h.connection.content, isNull);
              h.remote.available = true;
              await tester.tap(find.byKey(const Key('profile-retry')));
              await tester.pumpAndSettle();
              expect(find.byKey(const Key('profile-edit')), findsOneWidget);
              final expectedCallSign = module.projection.value.callSign;
              expect(find.byKey(const Key('profile-preview')), findsNothing);
              if (const bool.fromEnvironment('PROFILE_MODULE_GOLDENS') &&
                  locale.countryCode == 'CN' &&
                  mode == AppearanceMode.dark) {
                await expectLater(
                  find.byType(Scaffold),
                  matchesGoldenFile(
                    '../../../build/profile_first_local_${width}_$rich.png',
                  ),
                );
              }
              await tester.tap(find.byKey(const Key('profile-edit')));
              await tester.pumpAndSettle();
              final name = find.byKey(const Key('profile-call-sign-field'));
              await tester.enterText(name, 'Discard draft');
              await tester.ensureVisible(
                find.byKey(const Key('profile-edit-cancel')),
              );
              await tester.tap(find.byKey(const Key('profile-edit-cancel')));
              await tester.pumpAndSettle();
              expect(h.connection.content, isNull);
              await tester.ensureVisible(find.byKey(const Key('profile-edit')));
              await tester.tap(find.byKey(const Key('profile-edit')));
              await tester.pumpAndSettle();
              expect(
                tester.widget<TextField>(name).controller!.text,
                expectedCallSign,
              );
              await tester.enterText(name, 'New local page');
              await tester.pumpAndSettle();
              h.connection.failSave = true;
              final save = find.byKey(const Key('profile-save'));
              await tester.ensureVisible(save);
              await tester.tap(save);
              await tester.pumpAndSettle();
              expect(
                find.byKey(const Key('profile-save-error')),
                findsOneWidget,
              );
              expect(
                tester.widget<TextField>(name).controller!.text,
                'New local page',
              );
              expect(h.connection.content, isNull);
              h.connection.failSave = false;
              await tester.tap(save);
              await tester.pumpAndSettle();
              expect(
                find.byKey(const Key('profile-editor-panel')),
                findsNothing,
              );
              expect(
                find.byKey(const Key('profile-local-first-steps')),
                findsNothing,
              );
              expect(h.connection.content!['callSign'], 'New local page');
              expect(h.connection.revision, 1);
              expect(h.remote.writes, 0);
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox.shrink());
              module.dispose();
              await tester.runAsync(h.session.close);
            },
          );
        }
      }
    }
  }
}
