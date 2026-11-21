import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/communities/community_activity_time.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_catalog_ship_image.dart';
import 'package:starbridge_flutter/features/communities/community_ships_copy.dart';

import 'community_workspace_test.dart' show workspacePayload;

void main() {
  for (final asset in <String?>[null, 'assets/ships/absent-star-kitten.png']) {
    testWidgets(
      'missing optional ship image keeps neutral placeholder $asset',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              AppStringsDelegate(),
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: Scaffold(body: CommunityCatalogShipImage(asset: asset)),
          ),
        );
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(CommunityCatalogShipImage));
        expect(
          find.text(communityShipsText(context, 'noImage')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets(
      'viewer offset, no duplicate, midnight and DST approximation $locale',
      (tester) async {
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              AppStringsDelegate(),
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        CommunityWorkspace workspace(bool dst) => CommunityWorkspace.parse({
          ...workspacePayload(),
          'timeZoneId': 'America/Chicago',
          'timeZoneStandardOffsetMinutes': -360,
          'timeZoneUsesDaylightSaving': dst,
          'activityWindows': [
            {
              'days': ['mon'],
              'startTime': '23:00',
              'endTime': '01:00',
              'endsNextDay': true,
            },
          ],
        });
        expect(
          communityViewerTimeZoneSummary(
            context,
            workspace(false),
            viewerOffsetMinutes: -360,
          ),
          '',
        );
        final shifted = communityViewerTimeZoneSummary(
          context,
          workspace(false),
          viewerOffsetMinutes: 480,
        );
        expect(shifted, contains('UTC+08:00'));
        expect(
          shifted,
          contains(
            locale.languageCode == 'en'
                ? 'Tue'
                : locale.countryCode == 'TW'
                ? '週二'
                : '周二',
          ),
        );
        final summer = communityViewerTimeZoneSummary(
          context,
          workspace(true),
          viewerOffsetMinutes: -300,
        );
        expect(summer, contains('UTC−05:00'));
        expect(
          summer,
          contains(
            locale.languageCode == 'en'
                ? 'Approximate'
                : '約'.replaceAll('約', locale.countryCode == 'TW' ? '約' : '约'),
          ),
        );
        final west = communityViewerActivitySummary(
          context,
          [
            CommunityActivityWindow.parse({
              'days': ['mon'],
              'startTime': '01:00',
              'endTime': '03:00',
              'endsNextDay': false,
            }),
          ],
          480,
          viewerOffsetMinutes: -360,
        );
        expect(
          west,
          contains(
            locale.languageCode == 'en'
                ? 'Sun'
                : locale.countryCode == 'TW'
                ? '週日'
                : '周日',
          ),
        );
        final noOffset = CommunityWorkspace.parse({
          ...workspacePayload(),
          'timeZoneStandardOffsetMinutes': null,
        });
        expect(
          communityViewerTimeZoneSummary(
            context,
            noOffset,
            viewerOffsetMinutes: 480,
          ),
          '',
        );
        final noWindows = CommunityWorkspace.parse({
          ...workspacePayload(),
          'timeZoneStandardOffsetMinutes': -360,
          'activityWindows': <Object?>[],
        });
        expect(
          communityViewerTimeZoneSummary(
            context,
            noWindows,
            viewerOffsetMinutes: 330,
          ),
          'UTC+05:30',
        );
      },
    );
  }
}
