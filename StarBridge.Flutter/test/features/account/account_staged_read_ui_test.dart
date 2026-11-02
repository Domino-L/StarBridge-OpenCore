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
import 'account_staged_read_test.dart' show StagedProfileHost;

void main() {
  setUpAll(() async {
    await loadFonts();
    await ScmSuccessMotion.verifyArtwork();
  });
  const path = String.fromEnvironment('STARBRIDGE_STAGED_PROFILE_WIRE');
  for (final locale in AppStrings.supportedLocales) {
    for (final width in [480.0, 1280.0]) {
      testWidgets(
        'cached first paint stays visible through held live and directory reads $locale $width',
        (t) async {
          size(t, Size(width, 900));
          final fixture = await t.runAsync(
            () async =>
                jsonDecode(await File(path).readAsString())
                    as Map<String, dynamic>,
          );
          final h = StagedProfileHost(fixture!);
          addTearDown(h.close);
          final semantics = t.ensureSemantics();
          try {
            await h.module.initialize();
            final name =
                ((fixture['current'] as Map)['payload'] as Map)['displayName']
                    as String;
            // The open page reads its staged details itself (2026-10-21,
            // account_visible_reads): both stay held while the cached first
            // paint must remain visible.
            h.hold.add('profile.getDisplayData');
            h.hold.add('profile.getTimeZoneDirectory');
            await t.pumpWidget(
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
                home: AccountPage(module: h.module),
              ),
            );
            await t.pumpAndSettle();
            expect(find.text(name), findsWidgets);
            // Opening the page started the live read without the warm-up queue.
            expect(h.names, [
              'account.getCurrent',
              'profile.readDisplayCache',
              'profile.getDisplayData',
            ]);
            await t.pump();
            expect(find.text(name), findsWidgets);
            expect(h.module.projection.value.canEditPreferences, isFalse);
            expect(
              t
                  .getSemantics(
                    find.byKey(const Key('account-save-preferences')),
                  )
                  .getSemanticsData()
                  .hasAction(ui.SemanticsAction.tap),
              isFalse,
            );
            h.hold.remove('profile.getDisplayData');
            for (final request in h.held.remove('profile.getDisplayData')!) {
              h.reply(request);
            }
            await t.pumpAndSettle();
            // The page moved on to the directory by itself; it is still held.
            expect(h.names.last, 'profile.getTimeZoneDirectory');
            expect(find.text(name), findsWidgets);
            expect(h.module.projection.value.profile?.email, isNotNull);
            expect(h.module.projection.value.canEditPreferences, isFalse);
            h.hold.remove('profile.getTimeZoneDirectory');
            for (final request in h.held.remove(
              'profile.getTimeZoneDirectory',
            )!) {
              h.reply(request);
            }
            await t.pumpAndSettle();
            expect(h.module.projection.value.canEditPreferences, isTrue);
            expect(h.names, isNot(contains('profile.patchPreferences')));
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox.shrink());
          } finally {
            semantics.dispose();
          }
        },
        skip: path.isEmpty,
      );
    }
  }
}
