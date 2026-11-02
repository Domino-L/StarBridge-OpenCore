import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_refresh_notice.dart';

void main() {
  for (final locale in AppStrings.supportedLocales) {
    testWidgets(
      '$locale failure notice shows the original time without a repeating animation',
      (tester) async {
        final at = DateTime(2026, 10, 15, 12);
        Widget app(bool refreshing) => MaterialApp(
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
            body: Column(
              children: [
                OfficialFleetRefreshNotice(
                  active: refreshing,
                  refreshFailed: !refreshing,
                  lastReadAtUtc: at.toUtc(),
                ),
                const Text('Retained content', key: Key('retained-content')),
              ],
            ),
          ),
        );
        await tester.pumpWidget(app(false));
        await tester.pumpAndSettle();
        final prefix = AppStrings.resolve(locale)
            .text('officialFleet.syncFailedAt')
            .split('{time}')
            .first;
        final text = tester.widget<Text>(find.textContaining(prefix)).data!;
        expect(text, contains('2026'));
        final original = tester.getTopLeft(
          find.byKey(const Key('retained-content')),
        );
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.pumpWidget(app(true));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.byKey(const Key('retained-content'))),
          original,
        );
        expect(tester.binding.hasScheduledFrame, isFalse);
      },
    );
  }
}
