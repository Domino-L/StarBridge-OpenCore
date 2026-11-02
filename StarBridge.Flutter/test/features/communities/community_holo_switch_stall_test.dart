// Loading line 2026-10-29: switching a community back to the upper screen
// stalled, because the re-mounted announcement entry re-read announcements
// at once and the whole workspace rebuilt mid-animation.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_holo_header.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_screen_switch.dart';
import 'package:starbridge_flutter/features/official_fleet/organization_holo_shell.dart';

import 'community_image_test_support.dart' show settleCommunityImages;

Future<void> _pump(WidgetTester tester, ExampleCommunities port) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        const Locale('zh', 'CN'),
      ),
      home: Scaffold(
        body: CommunityWorkspaceView(
          port: port,
          targetRef: '00000000000000000000000000000001',
          holo: true,
          actions: const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await settleCommunityImages(tester);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'returning to the upper screen after 11 s neither reads announcements '
    'nor rebuilds the workspace while the switch plays',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = ExampleCommunities();
      addTearDown(port.close);
      await _pump(tester, port);
      expect(find.byType(OfficialFleetHoloHeader), findsOneWidget);
      final model = tester
          .state<CommunityWorkspaceViewState>(
            find.byType(CommunityWorkspaceView),
          )
          .model;
      final announcements = model.announcements!;
      expect(announcements.page, isNotNull);
      // Lower screen, long enough for the entry's 10 s re-read rule.
      await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 11));
      var readsDuringSwitch = 0;
      void watch() {
        if (announcements.loading) readsDuringSwitch++;
      }

      announcements.addListener(watch);
      addTearDown(() => announcements.removeListener(watch));
      await tester.tap(find.byKey(const Key('organization-holo-expand')));
      await tester.pump();
      // A rebuilt workspace makes a new shell widget; the same instance
      // means the deck was left alone.
      final shellAtStart = tester.widget(find.byType(OrganizationHoloShell));
      // The whole 520 ms switch, frame by frame.
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          announcements.loading,
          isFalse,
          reason: 'frame $frame: announcements read while the switch plays',
        );
      }
      expect(readsDuringSwitch, 0);
      expect(
        identical(
          tester.widget(find.byType(OrganizationHoloShell)),
          shellAtStart,
        ),
        isTrue,
        reason: 'the workspace rebuilt while the switch played',
      );
      // The deferred re-read happens afterwards and leaves the deck alone
      // when nothing changed.
      await tester.pump(CommunityAnnouncementEntryState.enterDelay);
      await tester.pumpAndSettle();
      expect(
        identical(
          tester.widget(find.byType(OrganizationHoloShell)),
          shellAtStart,
        ),
        isTrue,
      );
      expect(find.byType(OfficialFleetHoloHeader), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the screen switch builds each screen once per state build', (
    tester,
  ) async {
    var upperBuilds = 0, lowerBuilds = 0;
    var lower = false;
    late StateSetter setSwitch;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildStarBridgeTheme(
          FutureRestraintStyle.resolve(AppearanceMode.dark),
          const Locale('zh', 'CN'),
        ),
        home: StatefulBuilder(
          builder: (context, setState) {
            setSwitch = setState;
            return OfficialFleetScreenSwitch(
              lower: lower,
              upper: (_) {
                upperBuilds++;
                return const SizedBox.expand();
              },
              lowerBuilder: (_) {
                lowerBuilds++;
                return const SizedBox.expand();
              },
              banner: null,
              bannerHeight: 200,
            );
          },
        ),
      ),
    );
    await tester.pump();
    final upperBefore = upperBuilds;
    setSwitch(() => lower = true);
    await tester.pump();
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(upperBuilds - upperBefore, lessThanOrEqualTo(1));
    expect(lowerBuilds, lessThanOrEqualTo(2));
  });
}
