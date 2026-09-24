import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/hangar/hangar_arrival_timeline.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_presentation.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_ship_row.dart';
import 'package:starbridge_flutter/features/hangar/hangar_combat_icon.dart';
import 'package:starbridge_flutter/features/hangar/hangar_combat_motion.dart';
import 'package:starbridge_flutter/features/hangar/hangar_ship_icon.dart';
import 'package:starbridge_flutter/shared/ships/ship_reviewed_display.dart';
import 'package:starbridge_flutter/shared/ships/catalog_vehicle_icon.dart';

import 'hangar_combat_icons_test.dart' as fixtures;

void main() {
  for (final personal in [false, true]) {
    testWidgets(
      '${personal ? "personal" : "scan"} reviewed combat icon retains approved arrival motion',
      (tester) async {
        final timeline = HangarArrivalTimeline(
          now: () => Duration(
            milliseconds: tester.binding.clock.now().millisecondsSinceEpoch,
          ),
        );
        final view = fixtures.results(count: 1);
        (view['ships'] as List).first['display'] = const ShipReviewedDisplay(
          category: 'combat',
          sizeClass: 'small',
          domain: 'spacecraft',
          iconKey: 'combat-small',
        ).toMap();
        timeline.accept(view, phase: 'reading');
        final base = fixtures.app(view, timeline) as MaterialApp;
        await tester.pumpWidget(
          personal
              ? MaterialApp(
                  theme: base.theme,
                  home: Scaffold(
                    body: LocalHangarShipRow(
                      item: LocalHangarPresentation.fromSaved(
                        const LocalHangarShip(
                          id: 'test',
                          title: 'Test',
                          size: 'small',
                          display: ShipReviewedDisplay(
                            category: 'combat',
                            sizeClass: 'small',
                            domain: 'spacecraft',
                            iconKey: 'combat-small',
                          ),
                        ),
                      ),
                      elapsed: Duration.zero,
                      onTap: () {},
                    ),
                  ),
                )
              : base,
        );
        final icon = tester.widget<CatalogVehicleIcon>(
          find.byType(CatalogVehicleIcon),
        );
        final motion = icon.motion! as Animation<double>;
        expect(icon.size, 28);
        expect(motion.value, lessThan(.1));
        await tester.pump(const Duration(milliseconds: 800));
        expect(motion.value, greaterThan(.4));
        await tester.pumpAndSettle();
        expect(motion.value, 1);
      },
    );
  }

  for (final size in HangarCombatSize.values) {
    testWidgets(
      'reviewed ${size.name} final frame equals the current catalog artwork',
      (tester) async {
        final base = fixtures.app(
          fixtures.results(),
          HangarArrivalTimeline(),
        ) as MaterialApp;
        Future<List<int>> render(Widget icon) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: base.theme,
              home: Center(child: icon),
            ),
          );
          final painter = tester
              .widget<CustomPaint>(
                find.descendant(
                  of: find.byType(CatalogVehicleIcon),
                  matching: find.byType(CustomPaint),
                ),
              )
              .painter!;
          return (await tester.runAsync(() async {
            final recorder = ui.PictureRecorder();
            painter.paint(Canvas(recorder), const Size(96, 96));
            final picture = recorder.endRecording();
            final image = await picture.toImage(96, 96);
            final data = await image.toByteData();
            final pixels = data!.buffer.asUint8List().toList();
            image.dispose();
            picture.dispose();
            return pixels;
          }))!;
        }

        final actual = await render(
          HangarShipIcon(
            display: ShipReviewedDisplay(
              category: 'combat',
              sizeClass: size.name,
              domain: 'spacecraft',
              iconKey: 'combat-${size.name}',
            ),
            legacyCombatSize: null,
            elapsed: const Duration(seconds: 3),
          ),
        );
        final expected = await render(
          CatalogVehicleIcon.byKey(iconKey: 'combat-${size.name}'),
        );
        expect(actual, expected);
      },
    );
  }

  for (final reduced in ['system', 'user', 'cached', 'cancelled']) {
    testWidgets('reviewed motion honors $reduced without replay', (
      tester,
    ) async {
      final timeline = HangarArrivalTimeline(now: () => Duration.zero);
      final base = fixtures.app(
        fixtures.results(),
        timeline,
        userReduced: reduced == 'user',
      ) as MaterialApp;
      await tester.pumpWidget(
        MaterialApp(
          theme: base.theme,
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced == 'system'),
            child: HangarShipIcon(
              display: const ShipReviewedDisplay(
                category: 'combat',
                sizeClass: 'small',
                domain: 'spacecraft',
                iconKey: 'combat-small',
              ),
              legacyCombatSize: null,
              active: reduced != 'cancelled',
              elapsed: reduced == 'cached'
                  ? const Duration(seconds: 3)
                  : Duration.zero,
            ),
          ),
        ),
      );
      final motion =
          tester
                  .widget<CatalogVehicleIcon>(find.byType(CatalogVehicleIcon))
                  .motion!
              as Animation<double>;
      expect(motion.value, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(motion.value, 1);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets('ground combat keeps reviewed gravlev and mech geometry', (
    tester,
  ) async {
    final base = fixtures.app(
      fixtures.results(),
      HangarArrivalTimeline(),
    ) as MaterialApp;
    for (final key in [
      'ground-combat-small-gravlev',
      'ground-combat-small-mech',
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: base.theme,
          home: HangarShipIcon(
            display: ShipReviewedDisplay(
              category: 'combat',
              sizeClass: 'small',
              domain: 'ground',
              iconKey: key,
            ),
            legacyCombatSize: HangarCombatSize.small,
            elapsed: Duration.zero,
          ),
        ),
      );
      final icon = tester.widget<CatalogVehicleIcon>(
        find.byType(CatalogVehicleIcon),
      );
      expect(icon.exactKey, key);
      expect(icon.motion, isNotNull);
      expect(find.byType(HangarCombatIcon), findsNothing);
    }
  });
}
