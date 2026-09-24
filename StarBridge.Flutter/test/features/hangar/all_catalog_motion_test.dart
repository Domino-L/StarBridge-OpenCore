import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/hangar/hangar_arrival_timeline.dart';
import 'package:starbridge_flutter/features/hangar/hangar_ship_icon.dart';
import 'package:starbridge_flutter/shared/ships/catalog_vehicle_icon.dart';
import 'package:starbridge_flutter/shared/ships/ship_reviewed_display.dart';

import 'hangar_combat_icons_test.dart' as fixtures;

final motionManifest = jsonDecode(
  File('lib/shared/ships/catalog_vehicle_motion_sources.json')
      .readAsStringSync(),
) as Map<String, dynamic>;
final motionKeys = (motionManifest['glyphs'] as List)
    .map((dynamic g) => g['key'] as String)
    .toList();

Widget motionApp(
  String key, {
  Duration elapsed = Duration.zero,
  bool active = true,
  bool reduced = false,
  bool ticker = true,
}) {
  final base =
      fixtures.app(fixtures.results(), HangarArrivalTimeline()) as MaterialApp;
  return MaterialApp(
    theme: base.theme,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: TickerMode(
        enabled: ticker,
        child: Center(
          child: HangarShipIcon(
            key: ValueKey(key),
            display: ShipReviewedDisplay(
              domain: key.startsWith('ground') ? 'ground' : 'spacecraft',
              category: key.split('-').first,
              sizeClass: key.split('-').last,
              iconKey: key,
            ),
            legacyCombatSize: null,
            elapsed: elapsed,
            active: active,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'scan remount resumes long sequences and a new scan restarts them',
    (tester) async {
      for (final key in [
        'competition-large',
        'ground-combat-small-mech',
        'utility-mpuv-tractor',
      ]) {
        var now = Duration.zero;
        final timeline = HangarArrivalTimeline(now: () => now);
        final view = fixtures.results(count: 1);
        (view['ships'] as List).first['display'] = ShipReviewedDisplay(
          domain: 'ground',
          category: 'combat',
          sizeClass: 'small',
          iconKey: key,
        ).toMap();
        timeline.accept(view, phase: 'reading');
        await tester.pumpWidget(fixtures.app(view, timeline));
        await tester.pumpWidget(const SizedBox());
        now = const Duration(milliseconds: 900);
        timeline.accept(view, phase: 'complete');
        await tester.pumpWidget(fixtures.app(view, timeline, complete: true));
        Animation<double> progress() =>
            tester
                    .widget<CatalogVehicleIcon>(find.byType(CatalogVehicleIcon))
                    .motion!
                as Animation<double>;
        expect(
          progress().value,
          closeTo(
            900 / CatalogVehicleIcon.motionDuration(key)!.inMilliseconds,
            .001,
          ),
        );
        await tester.pumpWidget(const SizedBox());
        now = const Duration(seconds: 20);
        await tester.pumpWidget(fixtures.app(view, timeline));
        expect(progress().value, 1);
        await tester.pumpWidget(const SizedBox());
        view['operationId'] = 'next-scan';
        timeline.accept(view, phase: 'reading');
        await tester.pumpWidget(fixtures.app(view, timeline));
        expect(progress().value, 0);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  test('frozen handoff contains 42 animated keys and 4 static-only keys', () {
    expect(motionKeys.toSet(), hasLength(42));
    expect(motionManifest['staticOnly'], hasLength(4));
    for (final key in [
      ...motionKeys,
      ...motionManifest['staticOnly'] as List,
    ]) {
      expect(
        CatalogVehicleIcon.supportsKey(key as String),
        isTrue,
        reason: key,
      );
    }
  });

  testWidgets('all 42 reviewed keys have their own finite motion', (
    tester,
  ) async {
    for (final key in motionKeys) {
      await tester.pumpWidget(motionApp(key));
      final icon = tester.widget<CatalogVehicleIcon>(
        find.byType(CatalogVehicleIcon),
      );
      expect(icon.motion, isNotNull, reason: '$key is still static');
      final progress = icon.motion! as Animation<double>;
      expect(progress.value, 0, reason: key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(progress.value, greaterThan(0), reason: key);
      expect(progress.value, lessThan(1), reason: key);
      await tester.pumpAndSettle();
      expect(progress.value, 1, reason: key);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('all final animated poses match approved static artwork', (
    tester,
  ) async {
    Future<List<int>> pixels(String key, double progress) async {
      final base = motionApp(key) as MaterialApp;
      await tester.pumpWidget(
        MaterialApp(
          theme: base.theme,
          home: Center(
            child: CatalogVehicleIcon.byKey(
              iconKey: key,
              motion: AlwaysStoppedAnimation(progress),
            ),
          ),
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
        final picture = recorder.endRecording(),
            image = await picture.toImage(96, 96);
        final data = await image.toByteData();
        if (Platform.environment['STARBRIDGE_MOTION_QA'] == '1') {
          final dir = Directory('build/local-integration/motion-qa')
            ..createSync(recursive: true);
          File('${dir.path}/$key-${progress == 1 ? 'static' : 'motion'}.png')
              .writeAsBytesSync(
                (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
                    .asUint8List(),
              );
        }
        final result = data!.buffer.asUint8List().toList();
        image.dispose();
        picture.dispose();
        return result;
      }))!;
    }

    final failures = <String>[];
    for (final key in motionKeys) {
      final actual = await pixels(key, .9999999),
          expected = await pixels(key, 1);
      var error = 0.0;
      for (var i = 0; i < actual.length; i++) {
        error += (actual[i] - expected[i]).abs();
      }
      if (error / actual.length >= .12) {
        failures.add('$key: ${error / actual.length}');
      }
    }
    expect(failures, isEmpty, reason: 'Animated/static discontinuities');
  });

  for (final mode in ['cached', 'cancelled', 'reduced', 'hidden']) {
    testWidgets('all families are static for $mode', (tester) async {
      for (final key in motionKeys) {
        await tester.pumpWidget(
          motionApp(
            key,
            elapsed: mode == 'cached' ? const Duration(days: 1) : Duration.zero,
            active: mode != 'cancelled',
            reduced: mode == 'reduced',
            ticker: mode != 'hidden',
          ),
        );
        final icon = tester.widget<CatalogVehicleIcon>(
          find.byType(CatalogVehicleIcon),
        );
        expect((icon.motion! as Animation<double>).value, 1, reason: key);
        expect(tester.binding.transientCallbackCount, 0, reason: key);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  testWidgets(
    'reduce and background changes finish immediately without replay',
    (tester) async {
      for (final background in [false, true]) {
        await tester.pumpWidget(motionApp('utility-mpuv-tractor'));
        await tester.pump(const Duration(milliseconds: 700));
        final progress =
            tester
                    .widget<CatalogVehicleIcon>(find.byType(CatalogVehicleIcon))
                    .motion!
                as Animation<double>;
        expect(progress.value, lessThan(1));
        if (background) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        } else {
          await tester.pumpWidget(
            motionApp('utility-mpuv-tractor', reduced: true),
          );
        }
        expect(progress.value, 1);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(motionApp('utility-mpuv-tractor'));
        expect(progress.value, 1);
        expect((progress as AnimationController).isAnimating, isFalse);
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'four unclassified glyphs remain static and never acquire a ticker',
    (tester) async {
      for (final key in motionManifest['staticOnly'] as List) {
        await tester.pumpWidget(motionApp(key as String));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CatalogVehicleIcon>(find.byType(CatalogVehicleIcon))
              .motion,
          isNull,
        );
        expect(tester.binding.transientCallbackCount, 0);
      }
    },
  );
}
