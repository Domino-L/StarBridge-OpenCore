import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_summary.dart';

import 'local_personal_profile_test.dart' show Harness;

void main() {
  for (final locale in AppStrings.supportedLocales) {
    for (final local in [false, true]) {
      for (final width in [420.0, 1200.0]) {
        testWidgets(
          'heading visibility ${locale.toLanguageTag()} local=$local width=$width',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(width, 600);
            addTearDown(tester.view.reset);
            final h = Harness();
            addTearDown(h.close);
            final remote = InMemoryPersonalProfileAdapter.forReview(
              signedIn: true,
            );
            addTearDown(remote.close);
            final snapshot = local ? await h.port.read() : await remote.read();
            final base = PersonalProfileProjection.fromSnapshot(snapshot);
            for (final visibility in PersonalProfileVisibility.values) {
              late AppStrings strings;
              var edits = 0, refreshes = 0, visibilityOpens = 0;
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
                    body: Builder(
                      builder: (context) {
                        strings = AppStrings.of(context);
                        return PersonalProfileSectionHeading(
                          projection: base.copyWith(visibility: visibility),
                          showOwnerActions: true,
                          onPreview: () {},
                          onVisibility: () { visibilityOpens++; },
                          onEdit: () {
                            edits++;
                          },
                          onRefresh: () {
                            refreshes++;
                          },
                        );
                      },
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final expected = visibility;
              expect(
                find.text(strings.text(expected.labelKey)),
                findsOneWidget,
              );
              expect(
                find.text(strings.text('profile.local.label')),
                findsNothing,
              );
              expect(
                find.text(strings.text('profile.page.description')),
                findsNothing,
              );
              await tester.tap(find.byKey(const Key('profile-edit')));
              await tester.tap(find.byKey(const Key('profile-refresh')));
              final visibilityControl = find.byKey(const Key('profile-visibility'));
              expect(tester.widget(visibilityControl), isNot(isA<OutlinedButton>()));
              await tester.tap(visibilityControl);
              expect(visibilityOpens, 1);
              expect((edits, refreshes), (1, 1));
              expect(tester.takeException(), isNull);
            }
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
