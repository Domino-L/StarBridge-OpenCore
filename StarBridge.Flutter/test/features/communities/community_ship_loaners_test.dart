import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_ship_loaners.dart';
import 'package:starbridge_flutter/features/communities/community_ship_statistics.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';

import 'community_ships_test.dart' show shipRow;

Map<String, Object?> loaner(String code, String spec, String status) => {
  'code': code,
  'displayName': code,
  'catalogSpec': spec,
  'catalogStatus': status,
  'catalogPriceUsd': '900',
  'roleCategory': 'transport',
};
CommunitySharedShip source({bool online = true, Object? rows}) =>
    CommunitySharedShip.parse(
      shipRow()
        ..['ownerOnline'] = online
        ..['catalogStatus'] = 'Concept'
        ..['catalogPriceUsd'] = '100'
        ..['loaners'] = rows,
    );

void main() {
  test('two replacements remain one owned and dispatchable asset', () {
    final ship = source(
      rows: [
        loaner('Small Test', 'small', 'flyable'),
        loaner('Capital Test', 'capital', 'flyable'),
      ],
    );
    final stats = CommunityShipStatistics([ship]);
    expect(stats.ships.length, 1);
    expect(stats.totalCents, 10000);
    expect(stats.available.length, 1);
    expect(stats.candidates.length, 2);
    expect(stats.preferred!.code, 'Capital Test');
    expect(stats.topOwner!.length, 1);
  });
  test('offline owner prevents replacement dispatch', () {
    final stats = CommunityShipStatistics([
      source(online: false, rows: [loaner('Test', 'large', 'flyable')]),
    ]);
    expect(stats.ownerOffline, 1);
    expect(stats.available, isEmpty);
    expect(stats.preferred, isNull);
  });
  test('known empty and unresolved replacements remain distinct', () {
    expect(CommunityShipStatistics([source(rows: [])]).notFlyable, 1);
    expect(CommunityShipStatistics([source()]).availabilityUnknown, 1);
    expect(
      CommunityShipStatistics([
        source(rows: [loaner('Test', 'large', 'unknown')]),
      ]).availabilityUnknown,
      1,
    );
  });
  test('duplicate or unbounded Loaner payload is rejected', () {
    expect(
      () => source(
        rows: [
          loaner('Test', 'small', 'flyable'),
          loaner('test', 'small', 'flyable'),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => source(
        rows: List.generate(17, (i) => loaner('$i', 'small', 'flyable')),
      ),
      throwsFormatException,
    );
  });
  testWidgets('replacement details can expand in a narrow existing surface', (
    tester,
  ) async {
    final ship = source(rows: [loaner('Replacement Test', 'large', 'flyable')]);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppStringsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppStrings.supportedLocales,
        theme: buildStarBridgeTheme(
          FutureRestraintStyle.resolve(AppearanceMode.dark),
          const Locale('en'),
        ),
        home: Scaffold(
          body: SizedBox(width: 360, child: CommunityShipLoaners(ship: ship)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Loaners · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Replacement Test'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
