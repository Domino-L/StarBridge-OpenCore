import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_ship_statistics.dart';
import 'package:starbridge_flutter/features/communities/community_ship_statistics_view.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/shared/ships/catalog_vehicle_icon.dart';

import '../friends/social_layout_test.dart' show loadFonts;
import 'community_fleet_statistics_dialog_test.dart' show host, capture;
import 'community_ships_test.dart' show shipRow;

CommunityShipStatistics fixture({bool mixed = false}) =>
    CommunityShipStatistics([
      for (var i = 0; i < 25; i++)
        CommunitySharedShip.parse(
          shipRow()
            ..['shipRef'] = '$i'.padLeft(32, '0')
            ..['code'] = 'model-${i % 4}'
            ..['ownerMemberRef'] = '${i % 4}'.padLeft(32, '0')
            ..['roleCategory'] = i < 7
                ? 'exploration'
                : (i < 13 ? 'industrial' : 'combat')
            ..['catalogSpec'] = i < 7 ? 'large' : (i < 13 ? 'medium' : 'small')
            ..['catalogIconKey'] = i < 7
                ? 'exploration-large'
                : (i < 13 ? 'industrial-medium' : 'combat-small')
            ..['catalogStatus'] = i < 19 ? 'Flyable' : 'Concept'
            ..['ownerOnline'] = !(mixed && i == 23)
            ..['loaners'] = mixed && i == 24 ? <Object?>[] : null,
        ),
    ]);

Future<void> pump(
  WidgetTester tester,
  CommunityShipStatistics stats, {
  double width = 1400,
  Locale locale = const Locale('zh', 'CN'),
  AppearanceMode mode = AppearanceMode.dark,
  double scale = 1,
  void Function(bool)? onDetails,
}) async {
  tester.view.physicalSize = Size(width, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    host(
      stats,
      locale,
      mode,
      scale: scale,
      content: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: CommunityShipStatisticsView(
            statistics: stats,
            onDetails: onDetails ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'same type separates all four sizes and preserves each exact glyph',
    (tester) async {
      final stats = CommunityShipStatistics([
        for (final size in ['small', 'medium', 'large', 'capital'])
          CommunitySharedShip.parse(
            shipRow()
              ..['catalogSpec'] = size
              ..['roleCategory'] = 'combat'
              ..['catalogIconKey'] = 'combat-$size',
          ),
      ]);
      await pump(tester, stats);
      expect(
        tester
            .widgetList<CatalogVehicleIcon>(find.byType(CatalogVehicleIcon))
            .map((icon) => '${icon.category}-${icon.sizeClass}')
            .toSet(),
        {'combat-small', 'combat-medium', 'combat-large', 'combat-capital'},
      );
      for (final label in ['小型', '中型', '大型', '旗舰级']) {
        expect(find.text('$label · 战斗 1'), findsOneWidget);
      }
    },
  );
  for (final entry in <String, List<String?>>{
    'missing': [null],
    'partly missing': ['combat-small', null],
    'conflicting': ['combat-small', 'unclassified-small'],
    'wrong size': ['combat-medium'],
    'invalid': ['not-a-catalog-icon'],
  }.entries) {
    testWidgets('unreliable ${entry.key} keys use text only', (tester) async {
      final stats = CommunityShipStatistics([
        for (final key in entry.value)
          CommunitySharedShip.parse(
            shipRow()
              ..['catalogSpec'] = 'small'
              ..['roleCategory'] = 'combat'
              ..['catalogIconKey'] = key,
          ),
      ]);
      await pump(tester, stats);
      expect(find.byType(CatalogVehicleIcon), findsNothing);
      expect(find.text('小型 · 战斗 ${entry.value.length}'), findsOneWidget);
    });
  }
  testWidgets(
    'unknown size and unsupported competition capital do not invent icons',
    (tester) async {
      final stats = CommunityShipStatistics([
        CommunitySharedShip.parse(
          shipRow()
            ..['catalogSpec'] = null
            ..['roleCategory'] = 'combat'
            ..['catalogIconKey'] = 'combat-small',
        ),
        CommunitySharedShip.parse(
          shipRow()
            ..['catalogSpec'] = 'capital'
            ..['catalogIconKey'] = 'competition-capital',
        ),
      ]);
      await pump(tester, stats);
      expect(find.byType(CatalogVehicleIcon), findsNothing);
    },
  );
  testWidgets(
    'legacy loaners without icon keys never inherit the parent icon',
    (tester) async {
      final stats = CommunityShipStatistics([
        CommunitySharedShip.parse(
          shipRow()
            ..['catalogSpec'] = 'capital'
            ..['catalogIconKey'] = 'exploration-capital'
            ..['catalogStatus'] = 'Concept'
            ..['loaners'] = [
              {
                'code': 'legacy-loaner',
                'displayName': 'Loaner',
                'catalogSpec': 'small',
                'catalogStatus': 'Flyable',
                'roleCategory': 'combat',
              },
            ],
        ),
      ]);
      await pump(tester, stats);
      expect(find.byType(CatalogVehicleIcon), findsNothing);
      expect(find.text('小型 · 战斗 1'), findsOneWidget);
      expect(stats.candidates.single.catalogIconKey, isNull);
    },
  );
  testWidgets(
    'dispatch icons retain exact size and category instead of medium fallback',
    (tester) async {
      final stats = CommunityShipStatistics([
        CommunitySharedShip.parse(
          shipRow()
            ..['catalogSpec'] = 'small'
            ..['roleCategory'] = 'combat'
            ..['catalogIconKey'] = 'combat-small',
        ),
        CommunitySharedShip.parse(
          shipRow()
            ..['shipRef'] = 'e' * 32
            ..['catalogSpec'] = 'large'
            ..['roleCategory'] = 'exploration'
            ..['catalogIconKey'] = 'exploration-large',
        ),
      ]);
      await pump(tester, stats);
      final icons = tester.widgetList<CatalogVehicleIcon>(
        find.byType(CatalogVehicleIcon),
      );
      expect(
        icons.map((icon) => '${icon.category}-${icon.sizeClass}').toSet(),
        {'combat-small', 'exploration-large'},
      );
      expect(find.text('小型 · 战斗 1'), findsOneWidget);
      expect(find.text('大型 · 探索 1'), findsOneWidget);
    },
  );
  testWidgets(
    'summary shows 19/25 with proportional status segments and real categories',
    (tester) async {
      bool? selected;
      await pump(tester, fixture(), onDetails: (value) => selected = value);
      expect(find.text('可用比例  19 / 25 艘 · 76%'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('dispatch-category-small-combat')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('dispatch-category-small-combat')),
          matching: find.text('小型 · 战斗 6'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('dispatch-segment-notFlyable')),
        findsNothing,
      );
      final available = tester
          .getSize(find.byKey(const ValueKey('dispatch-segment-dispatchable')))
          .width;
      final pending = tester
          .getSize(
            find.byKey(const ValueKey('dispatch-segment-pendingAvailability')),
          )
          .width;
      expect(available / pending, closeTo(19 / 6, .001));
      await capture(tester, 'dispatch-summary-wide');
      await tester.tap(
        find.byKey(const ValueKey('community-dispatch-details')),
      );
      expect(selected, isTrue);
    },
  );
  testWidgets(
    'offline unavailable unknown and empty inventories remain distinct',
    (tester) async {
      await pump(tester, fixture(mixed: true));
      expect(
        find.byKey(const ValueKey('dispatch-segment-ownerOffline')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('dispatch-segment-notFlyable')),
        findsOneWidget,
      );
      expect(find.text('当前不可飞'), findsOneWidget);
      await pump(tester, CommunityShipStatistics([]));
      expect(find.text('可用比例  0 / 0 艘 · —'), findsOneWidget);
      expect(find.text('暂无已确认可调度舰船'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('dispatch-segment-dispatchable')),
        findsNothing,
      );
    },
  );
  testWidgets(
    'loaner candidates use their own type without increasing shared count',
    (tester) async {
      final stats = CommunityShipStatistics([
        CommunitySharedShip.parse(
          shipRow()
            ..['catalogStatus'] = 'Concept'
            ..['roleCategory'] = 'exploration'
            ..['catalogSpec'] = 'capital'
            ..['catalogIconKey'] = 'exploration-capital'
            ..['loaners'] = [
              {
                'code': 'loaner-a',
                'displayName': 'A',
                'catalogStatus': 'Flyable',
                'roleCategory': 'industrial',
                'catalogSpec': 'small',
                'catalogIconKey': 'industrial-small',
              },
              {
                'code': 'loaner-b',
                'displayName': 'B',
                'catalogStatus': 'Flyable',
                'roleCategory': 'support',
                'catalogSpec': 'large',
                'catalogIconKey': 'support-large',
              },
            ],
        ),
      ]);
      await pump(tester, stats);
      expect(find.text('可用比例  1 / 1 艘 · 100%'), findsOneWidget);
      expect(find.text('可调度类型 · 含替代船'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('dispatch-category-capital-exploration')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('dispatch-category-small-industrial')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('dispatch-category-large-support')),
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<CatalogVehicleIcon>(find.byType(CatalogVehicleIcon))
            .map((icon) => '${icon.category}-${icon.sizeClass}')
            .toSet(),
        {'industrial-small', 'support-large'},
      );
    },
  );
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    for (final mode in AppearanceMode.values) {
      for (final width in [320.0, 800.0, 1400.0]) {
        testWidgets('responsive dispatch $locale $mode $width enlarged text', (
          tester,
        ) async {
          await pump(
            tester,
            fixture(mixed: true),
            locale: locale,
            mode: mode,
            width: width,
            scale: 1.5,
          );
          expect(
            find.byKey(const ValueKey('community-dispatch-share')),
            findsOneWidget,
          );
          if (locale == const Locale('zh', 'CN') &&
              mode == AppearanceMode.dark &&
              width == 320) {
            await tester.ensureVisible(
              find.byKey(const ValueKey('community-dispatch-share')),
            );
            await capture(tester, 'dispatch-summary-narrow');
          }
        });
      }
    }
  }
}
