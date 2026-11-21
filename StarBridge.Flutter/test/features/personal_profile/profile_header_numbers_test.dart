import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_achievement_showcase.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_public_header.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_side_rail.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_steam_header.dart';

// User 11-11: one header and one rail for the owner and every visitor who may
// see the whole page. Synthetic data only.

const _facts = PersonalProfilePublicFacts(gameRegisteredDay: '2018-11-03');

Map<String, Object?> _page({
  required bool editable,
  int? achievements,
  Object? tradeWindow,
}) => {
  'schemaVersion': 1,
  'editable': editable,
  'profile': {
    'isPublic': true,
    'visibility': 'public',
    'revision': 7,
    'identity': {'callSign': 'Pilot', 'gameHandle': 'Pilot-Handle'},
    'content': {
      'modules': <Object?>[],
      'showOnlineTime': true,
      'availabilityWindows': [
        {
          'days': [0, 1, 2, 3, 4],
          'startTime': '20:00',
          'endTime': '23:30',
        },
      ],
    },
    'gameplayStatistics': {'playTimeSeconds': 559 * 3600},
    'isGameplayStatisticsPublic': true,
    'hangar': {
      'ships': [
        for (final code in ['AEGS_Idris_P', 'ANVL_Carrack'])
          {
            'code': code,
            'displayName': code,
            'presentation': {'title': code, 'catalogId': 'catalog-$code'},
          },
      ],
    },
    'achievementCount': ?achievements,
    'tradeWindow': ?tradeWindow,
  },
};

PersonalProfileProjection _projection(Map<String, Object?> payload) =>
    PersonalProfileProjection.fromSnapshot(
      parsePersonalProfileSnapshot(payload),
    );

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('zh', 'CN'),
  double width = 1200,
}) async {
  tester.view.physicalSize = const Size(1440, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('service time', () {
    ({int days, int? tenths})? at(String day, DateTime now) =>
        personalProfileServiceTenths(day, now: now);

    test('years cut down to one decimal, never rounded up', () {
      // 3 years and 181 of 365 days: 3.49..., shown as 3.4.
      expect(at('2018-11-03', DateTime(2022, 5, 3))?.tenths, 34);
      expect(at('2018-11-03', DateTime(2026, 11, 11))?.tenths, 80);
      expect(at('2018-11-03', DateTime(2026, 11, 2))?.tenths, 79);
    });
    test('a full year exactly is 1.0; before it, whole days', () {
      expect(at('2025-11-11', DateTime(2026, 11, 11))?.tenths, 10);
      final before = at('2025-11-12', DateTime(2026, 11, 11));
      expect(before?.tenths, isNull);
      expect(before?.days, 364);
      expect(at('2026-11-11', DateTime(2026, 11, 11))?.days, 0);
    });
    test('a leap day registration waits for March 1st', () {
      expect(at('2020-02-29', DateTime(2021, 2, 28))?.tenths, isNull);
      expect(at('2020-02-29', DateTime(2021, 3, 1))?.tenths, 10);
    });
    test('future, malformed or impossible days show nothing', () {
      expect(at('2027-01-01', DateTime(2026, 11, 11)), isNull);
      expect(at('2018-13-01', DateTime(2026, 11, 11)), isNull);
      expect(at('2018-02-30', DateTime(2026, 11, 11)), isNull);
      expect(at('2018/11/03', DateTime(2026, 11, 11)), isNull);
      expect(personalProfileServiceTenths(null), isNull);
    });
  });

  group('HK swap 5 fields', () {
    test('a full visitor page reads the window and the count', () {
      final projection = _projection(
        _page(
          editable: false,
          achievements: 42,
          tradeWindow: {
            'days': [1, 1, 1, 1, 1, 0, 0],
            'start': '19:30',
            'end': '23:00',
            'ownerOffsetMinutes': 480,
          },
        ),
      );
      expect(projection.showcaseData.achievementCount, 42);
      expect(projection.publicTradeWindow?.start, '19:30');
      expect(projection.publicTradeWindow?.ownerOffsetMinutes, 480);
    });
    test('a bad window or count leaves only that field out', () {
      for (final window in <Object>[
        'text',
        {
          'days': [1],
          'start': '19:30',
          'end': '23:00',
        },
        {
          'days': [1, 1, 1, 1, 1, 0, 0],
          'start': '7pm',
          'end': '23:00',
        },
      ]) {
        final projection = _projection(
          _page(editable: false, tradeWindow: window),
        );
        expect(projection.publicTradeWindow, isNull);
        expect(projection.callSign, 'Pilot');
      }
      expect(
        _projection(_page(editable: false, achievements: -1))
            .showcaseData
            .achievementCount,
        isNull,
      );
    });
    test('the owner keeps the hall window and reads the count', () {
      final projection = _projection(
        _page(
          editable: true,
          achievements: 7,
          tradeWindow: {
            'days': [1, 1, 1, 1, 1, 0, 0],
            'start': '19:30',
            'end': '23:00',
          },
        ),
      );
      expect(projection.publicTradeWindow, isNull);
      expect(projection.showcaseData.achievementCount, 7);
    });
  });

  group('header numbers', () {
    Future<List<String>> numbers(
      WidgetTester tester,
      PersonalProfileProjection projection, {
      required bool isSelf,
      bool publicOnly = false,
      PersonalProfilePublicFacts? facts = _facts,
    }) async {
      await _pump(
        tester,
        PersonalProfileSteamHeader(
          projection: projection,
          isSelf: isSelf,
          publicOnly: publicOnly,
          accountFacts: facts,
          gameplayHours: 559,
        ),
      );
      return [
        for (final label in ['艘舰船', '服役时间', '项成就'])
          if (find.text(label).evaluate().isNotEmpty) label,
      ];
    }

    testWidgets('owner and visitor see the same three', (tester) async {
      final owner = await numbers(
        tester,
        _projection(_page(editable: true, achievements: 42)),
        isSelf: true,
      );
      final visitor = await numbers(
        tester,
        _projection(_page(editable: false, achievements: 42)),
        isSelf: false,
      );
      expect(owner, visitor);
      expect(find.text('2'), findsOneWidget);
      expect(find.textContaining('年'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('游戏时长'), findsNothing);
      expect(find.text('559'), findsNothing);
    });
    // User 11-13: the owner's own header counts exactly like the achievements
    // page (SCM's own achievements included); visitors keep HK's count.
    testWidgets('the owner counts like the achievements page', (tester) async {
      AchievementCollection counted(AchievementCollectionStatus status) =>
          AchievementCollection(
            generation: 1,
            status: status,
            catalog: achievementCatalog,
            earnedAt: {
              'first-entry': DateTime.utc(2026, 8, 1),
              'journey-area18': DateTime.utc(2026, 9, 21),
              'hangar-home-3': DateTime.utc(2026, 10, 2),
            },
          );
      final source = ValueNotifier(counted(AchievementCollectionStatus.ready));
      addTearDown(source.dispose);
      Future<void> show({required bool owner}) => _pump(
        tester,
        ProfileAchievementsScope(
          collection: source,
          counted: source,
          activate: () async {},
          child: PersonalProfileSteamHeader(
            projection: _projection(_page(editable: owner, achievements: 13)),
            isSelf: owner,
            accountFacts: _facts,
            showAchievementCount: owner,
          ),
        ),
      );
      await show(owner: true);
      // One per earned achievement; a series counts once whatever its rank.
      expect(find.text('3'), findsOneWidget);
      expect(find.text('13'), findsNothing);
      await show(owner: false);
      expect(find.text('13'), findsOneWidget);
      // Until the achievements page knows its number, the owner sees HK's.
      source.value = counted(AchievementCollectionStatus.loading);
      await show(owner: true);
      expect(find.text('13'), findsOneWidget);
    });
    testWidgets('before HK swap 5 both sides show two', (tester) async {
      final owner = await numbers(
        tester,
        _projection(_page(editable: true)),
        isSelf: true,
      );
      final visitor = await numbers(
        tester,
        _projection(_page(editable: false)),
        isSelf: false,
      );
      expect(owner, visitor);
      expect(find.text('42'), findsNothing);
    });
    testWidgets('no service time without account facts', (tester) async {
      await numbers(
        tester,
        _projection(_page(editable: false)),
        isSelf: false,
        facts: null,
      );
      expect(find.text('服役时间'), findsNothing);
    });
    testWidgets('a page the viewer may not see shows no numbers', (
      tester,
    ) async {
      await numbers(
        tester,
        _projection(_page(editable: false, achievements: 42)),
        isSelf: false,
        publicOnly: true,
      );
      expect(find.text('服役时间'), findsNothing);
      expect(find.text('42'), findsNothing);
    });
  });

  group('rail playtime', () {
    testWidgets('leads the rail and is not repeated in the stats', (
      tester,
    ) async {
      await _pump(
        tester,
        PersonalProfileSideRail(
          projection: _projection(_page(editable: false)),
          isSelf: false,
          gameplayHours: 559,
        ),
      );
      final rail = tester.widget<Column>(
        find.byKey(const Key('profile-side-rail')),
      );
      final first = find.descendant(
        of: find.byKey(const Key('profile-side-rail')),
        matching: find.byKey(const Key('profile-showcase-gameplay')),
      );
      expect(first, findsOneWidget);
      expect(rail.children, isNotEmpty);
      expect(
        tester.getTopLeft(first).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const Key('profile-rail-organizations')))
              .dy,
        ),
      );
      expect(find.text('559'), findsOneWidget);
      expect(find.text('559 小时'), findsNothing);
    });
    for (final width in [160.0, 200.0, 272.0]) {
      testWidgets('the hour axis fits a narrow English rail: $width', (
        tester,
      ) async {
        await _pump(
          tester,
          PersonalProfileSideRail(
            projection: _projection(_page(editable: false)),
            isSelf: false,
            gameplayHours: 559,
          ),
          locale: const Locale('en', 'US'),
          width: width,
        );
        expect(find.text('0:00'), findsOneWidget);
        expect(find.text('24:00'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('a page the viewer may not see has none', (tester) async {
      await _pump(
        tester,
        PersonalProfileSideRail(
          projection: _projection(_page(editable: false)),
          isSelf: false,
          publicOnly: true,
          gameplayHours: 559,
        ),
      );
      expect(find.byKey(const Key('profile-showcase-gameplay')), findsNothing);
    });
  });
}
