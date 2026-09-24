import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/communities/community_catalog_ship_image.dart';
import 'package:starbridge_flutter/features/communities/community_fleet_statistics_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_ship_statistics.dart';
import 'package:starbridge_flutter/features/communities/community_ship_statistics_panel.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';

import '../friends/social_layout_test.dart' show loadFonts;
import 'community_ships_test.dart' show shipRow;
import 'community_workspace_test.dart' show WorkspaceTestPort;

class _AvatarPort extends WorkspaceTestPort implements CommunityShipsPort {
  @override
  bool get shipsAvailable => true;
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async => page;
  final page = CommunityShipsPage.parse({
    'schemaVersion': 1,
    'queryVersion': 2,
    'query': CommunityShipQuery().toPayload(),
    'targetRef': 'a' * 32,
    'revision': 'b' * 64,
    'offset': 0,
    'next': null,
    'totalCount': 1,
    'matchedCount': 1,
    'ships': [shipRow()],
  });
}

CommunityShipStatistics fixture({bool prices = true}) =>
    CommunityShipStatistics([
      for (var i = 0; i < 25; i++)
        CommunitySharedShip.parse(
          shipRow()
            ..['shipRef'] = i.toRadixString(16).padLeft(32, '0')
            ..['code'] = 'model-${i % 4}'
            ..['displayName'] = ['卡拉克', '大力神 C2', '黄蜂', '勘探者'][i % 4]
            ..['ownerMemberRef'] = (i % 4).toRadixString(16).padLeft(32, '0')
            ..['ownerCallsign'] = '示例舰长 ${i % 4 + 1}'
            ..['ownerGameName'] = 'Example_Captain_${i % 4 + 1}'
            ..['catalogSpec'] = i < 12 ? 'large' : (i < 22 ? 'small' : null)
            ..['roleCategory'] = i < 10
                ? 'combat'
                : (i < 20 ? 'transport' : 'industrial')
            ..['catalogPriceUsd'] = prices && i < 10
                ? '${(i + 1) * 100}'
                : null,
        ),
    ]);

Widget host(
  CommunityShipStatistics stats,
  Locale locale,
  AppearanceMode mode, {
  double scale = 1,
  Widget? content,
}) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(FutureRestraintStyle.resolve(mode), locale),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: RepaintBoundary(
      key: const ValueKey('statistics-capture'),
      child: child!,
    ),
  ),
  home:
      content ??
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    CommunityFleetStatisticsDialog(statistics: stats),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
);

Future<void> open(
  WidgetTester tester,
  CommunityShipStatistics stats, {
  double width = 1200,
  double scale = 1,
  Locale locale = const Locale('zh', 'CN'),
  AppearanceMode mode = AppearanceMode.dark,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host(stats, locale, mode, scale: scale));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('statistics-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('build/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(loadFonts);
  for (final invalidate in [false, true]) {
    testWidgets(
      'summary has no ranking media reads; invalidation=$invalidate',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final port = _AvatarPort();
        addTearDown(port.changes.close);
        var reads = 0;
        port.mediaReader = (_, _) async {
          reads++;
          throw StateError('Unexpected ranking avatar read');
        };
        await tester.pumpWidget(
          host(
            fixture(),
            const Locale('zh', 'CN'),
            AppearanceMode.dark,
            content: Scaffold(
              body: CommunityShipStatisticsPanel(
                port: port,
                targetRef: 'a' * 32,
                culture: 'zh-CN',
                firstPage: port.page,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('community-ship-statistics-expand')),
        );
        await tester.pumpAndSettle();
        final dialog = find.byKey(
          const ValueKey('community-statistics-dialog'),
        );
        expect(dialog, findsOneWidget);
        expect(find.byType(UserAvatarMenu), findsNothing);
        expect(find.text('舰船最多成员'), findsNothing);
        expect(find.text('最高价舰船'), findsNothing);
        if (invalidate) {
          port.changes.add(null);
        } else {
          await tester.pumpWidget(const SizedBox());
        }
        await tester.pumpAndSettle();
        expect(dialog, findsNothing);
        expect(reads, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('count scale, selection shares, exact matrix and no rankings', (
    tester,
  ) async {
    final stats = fixture();
    await open(tester, stats);
    final combat = find.byKey(const ValueKey('ship-distribution-large-combat'));
    final transport = find.byKey(
      const ValueKey('ship-distribution-large-transport'),
    );
    final small = find.byKey(
      const ValueKey('ship-distribution-small-transport'),
    );
    expect(
      tester.getSize(combat).width / tester.getSize(transport).width,
      closeTo(5, .01),
    );
    expect(
      tester.getSize(small).width / tester.getSize(combat).width,
      closeTo(.8, .01),
    );
    await tester.tap(combat);
    await tester.pumpAndSettle();
    final selection = tester
        .widget<Text>(find.byKey(const ValueKey('ship-distribution-selection')))
        .data!;
    expect(selection, contains('10 艘'));
    expect(selection, contains('83.3%'));
    expect(selection, contains('40.0%'));
    expect(find.byType(UserAvatarMenu), findsNothing);
    expect(find.byType(CommunityCatalogShipImage), findsNothing);
    expect(find.text(r'$5,500'), findsOneWidget);
    expect(find.text(r'$1,000'), findsNothing);
    await capture(tester, 'statistics-details-wide');
    final toggle = find.byKey(const ValueKey('ship-distribution-table-toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final table = tester.widget<DataTable>(
      find.byKey(const ValueKey('ship-distribution-table')),
    );
    expect(table.columns.length, 5);
    expect(table.rows.length, 6); // four sizes, unknown, totals
    expect((table.rows[1].cells[1].child as Text).data, '10');
    expect((table.rows.last.cells.last.child as Text).data, '25');
    expect(tester.takeException(), isNull);
  });

  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ]) {
    for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
      for (final width in [320.0, 1200.0]) {
        testWidgets(
          'statistics fits ${locale.toLanguageTag()} $mode $width enlarged',
          (tester) async {
            await open(
              tester,
              fixture(),
              width: width,
              locale: locale,
              mode: mode,
              scale: 1.5,
            );
            expect(tester.takeException(), isNull);
            final toggle = find.byKey(
              const ValueKey('ship-distribution-table-toggle'),
            );
            await tester.ensureVisible(toggle);
            await tester.tap(toggle);
            await tester.pumpAndSettle();
            expect(find.byType(DataTable), findsOneWidget);
            await tester.ensureVisible(find.byType(DataTable));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (width == 320 &&
                mode == AppearanceMode.light &&
                locale.languageCode == 'en') {
              await capture(tester, 'statistics-details-narrow');
            }
          },
        );
      }
    }
  }

  testWidgets('empty inventory and unknown prices are not zero-value assets', (
    tester,
  ) async {
    await open(tester, CommunityShipStatistics([]));
    expect(find.text('暂无可见共享舰船'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ship-distribution-table-toggle')),
      findsNothing,
    );
    expect(find.text(r'$0'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await open(tester, fixture(prices: false));
    expect(find.text('暂无价格资料'), findsOneWidget);
    expect(find.byType(CommunityCatalogShipImage), findsNothing);
    expect(find.text(r'$0'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
