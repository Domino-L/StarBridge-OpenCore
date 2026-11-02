import '../../_support/development_fixture_path.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:starbridge_flutter/features/common/organization_holo_choice.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_page.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_overview_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_ships_adapter.dart';
import 'package:starbridge_flutter/features/common/organization_member_board.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';
import 'package:starbridge_flutter/features/party_rooms/room_display.dart'
    show roomDate;

import '../friends/social_layout_test.dart' show loadFonts, size;

void main() {
  setUpAll(loadFonts);
  for (final fixture in [
    (const Size(1280, 900), const Locale('zh', 'CN'), 1.0, false),
    (const Size(760, 720), const Locale('zh', 'CN'), 1.5, false),
    (const Size(480, 720), const Locale('en'), 1.5, true),
    (const Size(1280, 900), const Locale('en'), 1.0, true),
    (const Size(1280, 900), const Locale('zh', 'TW'), 1.0, false),
  ]) {
    testWidgets('shared fleet frame ${fixture.$1} ${fixture.$2} ${fixture.$3}', (
      tester,
    ) async {
      size(tester, fixture.$1);
      final module = createOfficialFleetModule(
        InMemoryOfficialFleetAdapter.forReview(signedIn: true),
        UnavailableOfficialFleetOverviewAdapter(),
        InMemoryOfficialFleetMembersAdapter.forReview(),
        UnavailableOfficialFleetShipsAdapter(),
      );
      addTearDown(module.dispose);
      await module.initialize();
      final frame = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          locale: fixture.$2,
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('zh', 'TW'),
            Locale('en'),
          ],
          localizationsDelegates: const [
            AppStringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(
              fixture.$4 ? AppearanceMode.light : AppearanceMode.dark,
            ),
            fixture.$2,
          ),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(fixture.$3)),
              child: RepaintBoundary(
                key: frame,
                child: Scaffold(body: OfficialFleetPage(module: module)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Two screens: the rail on the top screen opens the member list.
      await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('official-fleet-members')), findsOneWidget);
      final traditional = fixture.$2.countryCode == 'TW';
      final english = fixture.$2.languageCode == 'en';
      // Only SCM-registered members are listed; the RSI total sits beside.
      final membersLabel = english
          ? 'Registered members'
          : traditional
          ? '已註冊成員'
          : '已注册成员';
      final updatedLabel = english
          ? 'Updated'
          : traditional
          ? '資料更新'
          : '资料更新';
      final searchLabel = english
          ? 'Search'
          : traditional
          ? '搜尋'
          : '搜索';
      final projection = module.members.projection.value;
      final board = tester.widget<OrganizationMemberBoard>(
        find.byType(OrganizationMemberBoard),
      );
      expect(
        board.summaryText,
        startsWith('$membersLabel · ${projection.totalCount} / '),
      );
      expect(board.summaryText, contains('1286'));
      expect(
        board.updatedText,
        '$updatedLabel · ${roomDate(tester.element(find.byType(OrganizationMemberBoard)), projection.lastReadAtUtc!)}',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('official-fleet-members-search-submit')),
          matching: find.text(searchLabel),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('official-fleet-tab-overview')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      if (Platform.environment['STARBRIDGE_CAPTURE_FLEET'] == '1') {
        await tester.runAsync(() async {
          final image =
              await (frame.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = Directory(
            developmentFixturePath('StarBridge-Reviews/official-fleet-20261014/screenshots'),
          );
          await output.create(recursive: true);
          await File(
            '${output.path}/fleet-${fixture.$1.width.toInt()}-${fixture.$2.languageCode}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.byKey(const Key('official-fleet-open-details')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('official-fleet-details-dialog')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('official-fleet-details-dialog')),
        findsNothing,
      );
      final memberTab = tester.widget<OrganizationHoloChoice>(
        find.ancestor(
          of: find.byKey(const Key('official-fleet-tab-members')),
          matching: find.byType(OrganizationHoloChoice),
        ),
      );
      memberTab.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final ships = tester.widget<CommunityShipsPanel>(
        find.byType(CommunityShipsPanel),
      );
      expect(ships.port.shipsAvailable, isFalse);
      expect(
        find.byKey(const Key('official-fleet-ships-unavailable')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
