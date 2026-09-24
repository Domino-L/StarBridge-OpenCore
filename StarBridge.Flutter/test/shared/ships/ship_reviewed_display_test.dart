import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/shared/ships/ship_reviewed_display.dart';
import 'package:starbridge_flutter/shared/ships/catalog_vehicle_icon.dart';
import 'package:starbridge_flutter/features/communities/community_ship_statistics.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_presentation.dart';
import 'package:starbridge_flutter/features/hangar/legacy_profile_hangar.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_local_projection.dart';

import '../../features/communities/community_ships_test.dart' show shipRow;
import '../../features/friends/social_layout_test.dart' show loadFonts;

const groundKeys = <String>[
  'ground-combat-small-gravlev',
  'ground-combat-small-wheeled',
  'ground-combat-small-mech',
  'ground-combat-medium-wheeled',
  'ground-combat-medium-tracked',
  'ground-combat-large-wheeled',
  'ground-combat-large-tracked',
  'ground-industrial-mining-mech',
  'ground-transport-cargo-mech',
  'ground-industrial-small-rover',
  'ground-industrial-medium-rover',
  'ground-exploration-gravlev',
  'ground-exploration-light-rover',
  'ground-exploration-medium-rover',
  'ground-support-medical-rover',
  'ground-competition-gravlev',
  'ground-competition-light-rover',
  'ground-transport-flatbed',
  'utility-mpuv-tractor',
];
Map<String, Object?> review(
  String category, {
  String domain = 'spacecraft',
  String size = 'small',
  String? icon,
}) => {
  'category': category,
  'sizeClass': size,
  'domain': domain,
  'iconKey': icon,
};
void main() {
  setUpAll(loadFonts);
  test('V3 overlay preserves official facts and explicit MTC size reuse', () {
    final d = ShipReviewedDisplay.parse(
      review(
        'transport',
        domain: 'ground',
        size: 'medium',
        icon: 'ground-transport-flatbed',
      ),
    )!;
    final raw = shipRow()
      ..['display'] = d.toMap()
      ..['catalogSpec'] = '小型'
      ..['roleCategory'] = 'combat';
    final ship = CommunitySharedShip.parse(raw);
    expect(ship.catalogSpec, '小型');
    expect(ship.roleCategory, 'combat');
    expect(ship.displaySpec, 'ground-medium');
    expect(ship.displayRole, 'ground-transport');
    expect(ship.displayIcon, 'ground-transport-flatbed');
    expect(
      CommunityShipStatistics([ship])
          .countAt('ground-medium', 'ground-transport'),
      1,
    );
  });
  test('competition and multi-role stay distinct; blank artwork overrides fallback', () {
    final ships = [
      for (final role in ['competition', 'multi-role', 'combat'])
        CommunitySharedShip.parse(
          shipRow()
            ..['display'] = review(role)
            ..['catalogIconKey'] = 'unclassified-small',
        ),
    ];
    expect(CommunityShipStatistics(ships).roles, {
      'competition': 1,
      'multi-role': 1,
      'combat': 1,
    });
    expect(ships[1].displayIcon, isNull);
    final mpuv = ShipReviewedDisplay.parse(
      review(
        'transport',
        domain: 'flying-utility',
        icon: 'utility-mpuv-tractor',
      ),
    )!;
    expect(mpuv.spec, 'small');
    expect(mpuv.role, 'transport');
  });
  test('hangar profile and legacy projection share display facts, not ownership edits', () {
    final ship = LocalHangarShip(
      id: 's',
      title: 'Synthetic',
      category: 'utility',
      sizeClass: 'small',
      priceUsd: 45,
      display: ShipReviewedDisplay.parse(
        review(
          'competition',
          domain: 'ground',
          icon: 'ground-competition-gravlev',
        ),
      ),
    );
    final item = LocalHangarPresentation.fromSaved(ship),
        profile = projectProfileShip(ship);
    expect(item.role, 'ground-competition');
    expect(item.sizeClass, 'ground-small');
    expect(item.priceCents, 4500);
    expect(ship.category, 'utility');
    expect(profile.roleKey, 'profile.local.category.ground-competition');
    expect(profile.sizeKey, 'profile.local.size.ground-small');
    expect(profile.catalogIconKey, 'ground-competition-gravlev');
    final legacy = profileHangarShip({
      'displayName': 'Synthetic',
      'presentation': {'title': 'Synthetic', 'display': ship.display!.toMap()},
    }, 'legacy');
    expect(legacy.display!.role, item.role);
  });
  test('loaner display remains attached to its source ownership reference', () {
    final source = CommunitySharedShip.parse(
      shipRow()
        ..['loaners'] = [
          {
            'code': 'replacement',
            'displayName': 'Replacement',
            'catalogStatus': 'Flyable',
            'display': review('competition', icon: 'competition-small'),
          },
        ],
    );
    final candidate = source.loaners!.single.forDispatch(source);
    expect(candidate.displayRole, 'competition');
    expect(candidate.displayIcon, 'competition-small');
    expect(candidate.shipRef, source.shipRef);
    expect(CommunityShipStatistics([source]).ships.length, 1);
  });
  test('malformed optional overlays keep legacy compatibility', () {
    expect(ShipReviewedDisplay.parse(review('invented')), isNull);
    expect(
      ShipReviewedDisplay.parse(
        review('combat', domain: 'ground', size: 'capital'),
      ),
      isNull,
    );
    expect(
      ShipReviewedDisplay.parse(review('combat', icon: '../other')),
      isNull,
    );
    expect(ShipReviewedDisplay.parse({'category': 1}), isNull);
    final ship = CommunitySharedShip.parse(
      shipRow()..['catalogIconKey'] = 'combat-small',
    );
    expect(ship.display, isNull);
    expect(ship.displayIcon, 'combat-small');
  });
  for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
    testWidgets('19 approved ground glyphs render statically ${mode.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(980, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tokens = FutureRestraintStyle.resolve(mode);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildStarBridgeTheme(tokens, const Locale('en')),
          home: RepaintBoundary(
            key: const ValueKey('v3-capture'),
            child: Scaffold(
              body: Wrap(
                children: [
                  for (final key in groundKeys)
                    SizedBox(
                      width: 190,
                      height: 105,
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final size in [24.0, 28.0, 40.0])
                                CatalogVehicleIcon.byKey(
                                  iconKey: key,
                                  size: size,
                                ),
                            ],
                          ),
                          Text(
                            key,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 10, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(groundKeys.every(CatalogVehicleIcon.supportsKey), isTrue);
      expect(CatalogVehicleIcon.supportsKey('multi-role-small'), isFalse);
      expect(CatalogVehicleIcon.supportsKey('competition-capital'), isFalse);
      expect(
        find.descendant(
          of: find.byType(CatalogVehicleIcon),
          matching: find.byType(CustomPaint),
        ),
        findsNWidgets(57),
      );
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('v3-capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(),
            data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/v3-ground-icons-${mode.name}.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    });
  }
}
