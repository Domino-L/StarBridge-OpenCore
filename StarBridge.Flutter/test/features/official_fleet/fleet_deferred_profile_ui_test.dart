import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_page.dart';

import '../friends/social_layout_test.dart' show loadFonts, size;
import 'fleet_deferred_profile_test.dart' show DeferredFleetHost;

void main() {
  setUpAll(loadFonts);
  const path = String.fromEnvironment('STARBRIDGE_FLEET_DEFERRED_WIRE');
  for (final locale in AppStrings.supportedLocales) {
    for (final width in [1280.0, 480.0]) {
      testWidgets('identity and live deferred details $locale at $width', (
        tester,
      ) async {
        size(tester, Size(width, 900));
        final fixture = await tester.runAsync(
          () async =>
              jsonDecode(await File(path).readAsString())
                  as Map<String, dynamic>,
        );
        final host = DeferredFleetHost.fromFixture(fixture!);
        final module = host.module();
        addTearDown(() async {
          module.dispose();
          await host.close();
        });
        await module.initialize();
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
            home: Scaffold(body: OfficialFleetPage(module: module)),
          ),
        );
        await tester.pumpAndSettle();
        expect(host.publicRequests, hasLength(1));
        expect(
          find.byKey(const Key('official-fleet-open-details')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('official-fleet-open-details')));
        await tester.pumpAndSettle();
        final dialog = find.byKey(const Key('official-fleet-details-dialog'));
        final element = tester.element(dialog);
        final strings = AppStrings.resolve(locale);
        expect(
          find.text(strings.text('officialFleet.profile.loading.title')),
          findsOneWidget,
        );
        expect(
          find.text(strings.text('officialFleet.profile.readFailed')),
          findsNothing,
        );
        await host.replyProfile(host.publicRequests.single, 'profileSuccess');
        await tester.pumpAndSettle();
        expect(tester.element(dialog), same(element));
        expect(find.text('Explore & build'), findsOneWidget);
        expect(
          find.text(strings.text('officialFleet.profile.loading.title')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('official-fleet-details-close')));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
      }, skip: path.isEmpty);
    }
  }
}
