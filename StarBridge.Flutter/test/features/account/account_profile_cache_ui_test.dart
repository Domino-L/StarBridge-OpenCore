import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/brand/scm_success_motion.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/account/account_page.dart';

import '../friends/social_layout_test.dart' show loadFonts, size;
import 'account_profile_cache_wire_test.dart' show AccountProfileWireHost;

void main() {
  setUpAll(() async {
    await loadFonts();
    await ScmSuccessMotion.verifyArtwork();
  });
  const path = String.fromEnvironment('STARBRIDGE_ACCOUNT_PROFILE_WIRE');
  for (final locale in AppStrings.supportedLocales) {
    for (final width in [480.0, 1280.0]) {
      testWidgets(
        'account denial clears displayed profile and disables saving without dropping draft $locale $width',
        (tester) async {
          size(tester, Size(width, 900));
          final fixture = await tester.runAsync(
            () async =>
                jsonDecode(await File(path).readAsString())
                    as Map<String, dynamic>,
          );
          final host = AccountProfileWireHost.fromFixture(fixture!);
          final module = host.module();
          addTearDown(() async {
            module.dispose();
            await host.close();
          });
          final semantics = tester.ensureSemantics();
          try {
            await module.initialize();
            module.preferencesDraft.setLocale('en-US');
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
                home: Scaffold(body: AccountPage(module: module)),
              ),
            );
            await tester.pumpAndSettle();
            final profile =
                ((fixture['live'] as Map)['payload'] as Map)['profile'] as Map;
            expect(find.text(profile['displayName'] as String), findsWidgets);
            host.phase = 'forbidden';
            await module.refresh();
            await tester.pumpAndSettle();
            expect(find.text(profile['displayName'] as String), findsNothing);
            expect(
              find.text(
                AppStrings.resolve(locale)
                    .text('account.error.profileReadForbidden'),
              ),
              findsOneWidget,
            );
            expect(
              find.text(
                AppStrings.resolve(locale).text('account.login.cancelled'),
              ),
              findsNothing,
            );
            expect(module.preferencesDraft.locale, 'en-US');
            final save = tester.getSemantics(
              find.byKey(const Key('account-save-preferences')),
            );
            expect(
              save.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isFalse,
            );
            expect(tester.takeException(), isNull);
            host.phase = 'live';
            await module.refresh();
            await tester.pumpAndSettle();
            expect(module.projection.value.canEditPreferences, isTrue);
            expect(module.preferencesDraft.locale, 'en-US');
            expect(host.names, isNot(contains('profile.patchPreferences')));
            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            semantics.dispose();
          }
        },
        skip: path.isEmpty,
      );
    }
  }
}
