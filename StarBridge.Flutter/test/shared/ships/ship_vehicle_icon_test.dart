import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_view.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/hangar/hangar_catalog_icon.dart';
import 'package:starbridge_flutter/features/hangar/hangar_ship_icon.dart';
import 'package:starbridge_flutter/shared/ships/catalog_vehicle_icon.dart';
import 'package:starbridge_flutter/shared/ships/ship_reviewed_display.dart';
import 'package:starbridge_flutter/shared/ships/ship_silhouette_store.dart';
import 'package:starbridge_flutter/shared/ships/ship_vehicle_icon.dart';

ByteData packBytes({bool truncate = false}) {
  final index = utf8.encode(
    jsonEncode({
      'grid': 1000,
      'ships': [
        {
          'keys': ['gladius', 'cataloggladius', '短剑'],
          'outline': [3],
          'mid': [3],
        },
      ],
    }),
  );
  final padding = (8 + index.length) % 2;
  const points = [500, 0, 1000, 1000, 0, 1000, 500, 200, 700, 800, 300, 800];
  final bytes = BytesBuilder()
    ..add(ascii.encode('SBSL'))
    ..add(
      Uint8List(4)
        ..buffer.asByteData().setUint32(0, index.length, Endian.little),
    )
    ..add(index)
    ..add(Uint8List(padding));
  for (final value in truncate ? points.sublist(2) : points) {
    bytes.add(
      Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little),
    );
  }
  return ByteData.sublistView(bytes.takeBytes());
}

class _Bundle extends CachingAssetBundle {
  _Bundle(this.result);
  final ByteData? result;
  String? asked;

  @override
  Future<ByteData> load(String key) async {
    asked = key;
    return result ?? (throw FlutterError('Unable to load asset: $key'));
  }
}

Widget host(Widget child) => MaterialApp(
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    const Locale('en'),
  ),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  tearDown(() => ShipSilhouetteStore.instance.debugUse(null));

  test(
    'the pack finds a ship by any normalized identity, exact name first',
    () {
      final pack = ShipSilhouettePack.parse(packBytes());
      final ship = pack.find(['Gladius']);
      expect(ship, isNotNull);
      expect(pack.find([null, 'unknown', 'catalog-gladius']), same(ship));
      expect(pack.find(['短剑']), same(ship));
      expect(pack.find(['A.E.G.S'.substring(0, 1), null]), isNull);
      expect(ship!.outline.getBounds(), const Rect.fromLTRB(0, 0, 1000, 1000));
      expect(ship.raised.getBounds().top, 200);
    },
  );

  test('a damaged pack is refused instead of painting wrong shapes', () {
    expect(
      () => ShipSilhouettePack.parse(ByteData(4)),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => ShipSilhouettePack.parse(packBytes(truncate: true)),
      throwsA(isA<FormatException>()),
    );
  });

  test('the menu window receives the ship identity for its silhouette', () {
    final row = MenuOrganizationRow.parse(const {'vehicleName': 'Gladius'});
    expect(row.vehicleName, 'Gladius');
  });

  test(
    'the real read path: a good pack loads, missing or damaged is absent',
    () async {
      final store = ShipSilhouetteStore.instance;
      final good = _Bundle(packBytes());
      await store.loadFrom(good);
      expect(good.asked, shipSilhouetteAsset);
      expect(store.load, ShipSilhouetteLoad.ready);
      expect(store.pack?.find(['Gladius']), isNotNull);

      await store.loadFrom(_Bundle(null));
      expect(store.load, ShipSilhouetteLoad.absent);
      expect(store.pack, isNull);

      await store.loadFrom(_Bundle(packBytes(truncate: true)));
      expect(store.load, ShipSilhouetteLoad.absent);
      expect(store.pack, isNull);
    },
  );

  testWidgets('no pack keeps the category artwork, as in public source', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ShipVehicleIcon(
          names: const ['Gladius'],
          fallback: CatalogVehicleIcon.byKey(iconKey: 'combat-small'),
        ),
      ),
    );
    expect(find.byType(CatalogVehicleIcon), findsOneWidget);
    expect(find.byType(ShipSilhouetteIcon), findsNothing);
  });

  testWidgets(
    'a known ship shows its silhouette and an unknown one falls back',
    (tester) async {
      ShipSilhouetteStore.instance.debugUse(
        ShipSilhouettePack.parse(packBytes()),
      );
      await tester.pumpWidget(
        host(
          Column(
            children: [
              ShipVehicleIcon(
                names: const ['Gladius'],
                fallback: CatalogVehicleIcon.byKey(iconKey: 'combat-small'),
              ),
              ShipVehicleIcon(
                names: const ['Not a ship'],
                fallback: CatalogVehicleIcon.byKey(iconKey: 'combat-small'),
              ),
            ],
          ),
        ),
      );
      expect(find.byType(ShipSilhouetteIcon), findsOneWidget);
      expect(find.byType(CatalogVehicleIcon), findsOneWidget);
    },
  );

  testWidgets('the hangar reveal is one shot and honours reduced motion', (
    tester,
  ) async {
    ShipSilhouetteStore.instance.debugUse(
      ShipSilhouettePack.parse(packBytes()),
    );
    const display = ShipReviewedDisplay(
      category: 'combat',
      sizeClass: 'small',
      domain: 'spacecraft',
      iconKey: 'combat-small',
    );
    Widget icon({bool reduced = false}) => host(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: const HangarShipIcon(
          display: display,
          legacyCombatSize: null,
          elapsed: Duration.zero,
          names: ['Gladius'],
        ),
      ),
    );
    Animation<double>? motion() => tester
        .widget<ShipSilhouetteIcon>(find.byType(ShipSilhouetteIcon))
        .motion;

    await tester.pumpWidget(icon());
    expect(find.byType(HangarCatalogIcon), findsOneWidget);
    expect(motion()!.value, lessThan(1));
    await tester.pump(shipSilhouetteReveal);
    expect(motion()!.value, 1);
    // The theme transition around the icon ends on its own; nothing keeps ticking.
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(icon(reduced: true));
    expect(motion()!.value, 1);
  });

  testWidgets(
    'a hangar ship without a silhouette keeps its reviewed sequence',
    (tester) async {
      const display = ShipReviewedDisplay(
        category: 'combat',
        sizeClass: 'small',
        domain: 'spacecraft',
        iconKey: 'combat-small',
      );
      await tester.pumpWidget(
        host(
          const HangarShipIcon(
            display: display,
            legacyCombatSize: null,
            elapsed: Duration(hours: 1),
            names: ['Not a ship'],
          ),
        ),
      );
      expect(find.byType(HangarCatalogIcon), findsOneWidget);
      expect(find.byType(CatalogVehicleIcon), findsOneWidget);
      expect(find.byType(ShipSilhouetteIcon), findsNothing);
    },
  );
}
