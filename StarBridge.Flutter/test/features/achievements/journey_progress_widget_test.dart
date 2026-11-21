import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/achievement_entry.dart';
import 'package:starbridge_flutter/features/achievements/achievement_presentation.dart';
import 'package:starbridge_flutter/features/achievements/journey_station_markers.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Locale locale,
    Iterable<String> awards, {
    bool showStations = true,
  }) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final presentation = AchievementPresentation(
      achievementCatalog.firstWhere((d) => d.id == 'journey-pyro-all'),
      AchievementCollection(
        generation: 1,
        status: AchievementCollectionStatus.ready,
        earnedAt: {for (final id in awards) id: DateTime.utc(2026, 11, 11)},
      ),
      AppStrings.resolve(locale),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStringsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildStarBridgeTheme(
          FutureRestraintStyle.resolve(AppearanceMode.dark),
          locale,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AchievementProgress(
              presentation: presentation,
              showStations: showStations,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (locale, visited) in [
    (const Locale('zh', 'CN'), '到过：死局空间站、星光服务站'),
    (const Locale('zh', 'TW'), '到過：死局空间站、星光服务站'),
    (const Locale('en'), 'Visited: 死局空间站、星光服务站'),
  ]) {
    testWidgets('reached stations list in ${locale.toLanguageTag()}', (
      tester,
    ) async {
      await pump(tester, locale, [
        'journey-station-rr-p2-l4',
        'journey-station-rr-p3-l1',
      ]);
      expect(find.byKey(const Key('achievement-reached-stations')), findsOne);
      expect(find.text(visited), findsOne);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cards never show the station list', (tester) async {
    await pump(tester, const Locale('zh', 'CN'), [
      'journey-station-rr-p2-l4',
    ], showStations: false);
    expect(find.byKey(const Key('achievement-reached-stations')), findsNothing);
    expect(find.text('1 / 23'), findsOne);
  });

  testWidgets('all 23 stations fit 320px at 2x in the detail', (tester) async {
    await pump(tester, const Locale('en'), pyroStationMarkers);
    expect(find.byKey(const Key('achievement-reached-stations')), findsOne);
    expect(find.text('23 / 23'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no station: 0 / 23 with an empty bar, no list', (tester) async {
    await pump(tester, const Locale('zh', 'CN'), const []);
    expect(find.text('0 / 23'), findsOne);
    expect(find.byKey(const Key('achievement-reached-stations')), findsNothing);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0,
    );
    expect(tester.takeException(), isNull);
  });
}
