import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/features/hangar/hangar_arrival_timeline.dart';
import 'package:starbridge_flutter/features/hangar/hangar_combat_icon.dart';
import 'package:starbridge_flutter/features/hangar/hangar_combat_motion.dart';
import 'package:starbridge_flutter/features/hangar/hangar_combat_paths.dart';
import 'package:starbridge_flutter/features/hangar/hangar_reader_results.dart';

Map<String, Object?> results({String operation = 'scan-one', int count = 5}) =>
    {
      'operationId': operation,
      'shipCount': count,
      'ships': List.generate(
        count,
        (i) => {
          'rowId': 'ship-$i',
          'title': 'Ship $i',
          'liner': 'Builder',
          'names': {
            'zhHans': [
              'F7C-M 超级大黄蜂 MK II',
              '中型战斗舰',
              '铁甲 突袭',
              '伊德里斯-P',
              '蜻蜓',
            ][i % 5],
          },
          if (i % 5 < 4) 'combatSize': HangarCombatSize.values[i % 5].name,
        },
      ),
    };

Widget app(
  Map<String, Object?> view,
  HangarArrivalTimeline timeline, {
  bool complete = false,
  bool systemReduced = false,
  bool userReduced = false,
  AppearanceMode mode = AppearanceMode.dark,
  Locale locale = const Locale('zh', 'CN'),
}) => MaterialApp(
  locale: locale,
  supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(mode).withReducedMotion(userReduced),
    locale,
  ),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: systemReduced),
    child: Scaffold(
      body: Center(
        child: RepaintBoundary(
          key: const Key('capture'),
          child: SizedBox(
            width: 320,
            height: 480,
            child: HangarReaderResults(
              view: view,
              complete: complete,
              arrivals: timeline,
            ),
          ),
        ),
      ),
    ),
  ),
);

List<HangarCombatPainter> painters(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<HangarCombatPainter>()
    .toList();

void main() {
  if (const bool.fromEnvironment('HANGAR_READER_GOLDENS')) {
    TestWidgetsFlutterBinding.ensureInitialized();
    setUpAll(() async {
      for (final font in {
        'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
        'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
        'Source Code Pro': 'assets/fonts/SourceCodeVF-Upright.ttf',
      }.entries) {
        await (FontLoader(
          font.key,
        )..addFont(rootBundle.load(font.value))).load();
      }
    });
  }
  test('arrival timestamps survive rebuild and completion; duplicates remain distinct', () {
    var time = Duration.zero;
    final timeline = HangarArrivalTimeline(now: () => time);
    timeline.accept(results(count: 2), phase: 'reading');
    time = const Duration(seconds: 1);
    timeline.accept(results(count: 3), phase: 'verifying');
    expect(timeline.elapsed('ship-0'), time);
    expect(timeline.elapsed('ship-1'), time);
    expect(timeline.elapsed('ship-2'), Duration.zero);
    timeline.accept(results(count: 3), phase: 'complete');
    expect(timeline.elapsed('ship-0'), time);
    timeline.accept(results(count: 3), phase: 'cancelled');
    expect(timeline.active, false);
    expect(timeline.elapsed('ship-2'), greaterThan(const Duration(seconds: 3)));
    timeline.accept(results(operation: 'new-scan'), phase: 'reading');
    expect(timeline.elapsed('ship-0'), Duration.zero);
  });
  test(
    'approved timing, recoil peak firing and exact final rest for all sizes',
    () {
      expect(HangarCombatSize.parse('unknown'), isNull);
      for (final size in HangarCombatSize.values) {
        expect(hangarCombatPaths[size.name], hasLength(5));
        final end = size.milliseconds.toDouble();
        for (final part in [0, 1, 2, 4]) {
          expect(HangarCombatMotion.part(size, part, 0).alpha, 0);
          final frame = HangarCombatMotion.part(size, part, end);
          expect(
            [frame.x, frame.y, frame.sx, frame.sy, frame.alpha],
            [0, 0, 1, 1, 1],
          );
        }
        final fire = HangarCombatMotion.firingAt(size);
        expect(HangarCombatMotion.recoil(size, fire).y, closeTo(.65, .00001));
        expect(HangarCombatMotion.ammoY(size, fire), size.ammoTravel);
        expect(HangarCombatMotion.ammoY(size, fire + 140), 0);
        expect(HangarCombatMotion.ammoY(size, end), 0);
        expect(HangarCombatMotion.recoil(size, end).y, 0);
      }
    },
  );
  test('final frame pixels equal approved static path geometry', () async {
    for (final size in HangarCombatSize.values) {
      Future<List<int>> pixels(bool animated) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        if (animated) {
          HangarCombatPainter(
            sizeClass: size,
            progress: const AlwaysStoppedAnimation(1),
            hull: Colors.white,
            ammunition: Colors.red,
          ).paint(canvas, const Size(96, 96));
        } else {
          canvas.scale(3);
          final paths = hangarCombatPaths[size.name]!;
          canvas.save();
          canvas.clipRect(Rect.fromLTWH(0, 0, 32, size.muzzleHeight));
          canvas.drawPath(paths[3], Paint()..color = Colors.red);
          canvas.restore();
          for (final i in [0, 1, 2, 4]) {
            canvas.drawPath(paths[i], Paint()..color = Colors.white);
          }
        }
        final picture = recorder.endRecording();
        final image = await picture.toImage(96, 96);
        final bytes = await image.toByteData();
        final result = bytes!.buffer.asUint8List().toList();
        image.dispose();
        picture.dispose();
        return result;
      }

      expect(await pixels(true), await pixels(false), reason: size.name);
    }
  });
  testWidgets(
    'number icon name order; once per scan, no live-preview or locale replay',
    (tester) async {
      final timeline = HangarArrivalTimeline(
        now: () => Duration(
          milliseconds: tester.binding.clock.now().millisecondsSinceEpoch,
        ),
      );
      final view = results();
      timeline.accept(view, phase: 'reading');
      await tester.pumpWidget(app(view, timeline));
      expect(painters(tester), hasLength(4));
      final number = tester.getRect(find.text('01'));
      final icon = tester.getRect(find.byType(HangarCombatIcon).first);
      final title = tester.getRect(
        find.byKey(const Key('hangar-reader-ship-name-0')),
      );
      expect(number.right, lessThan(icon.left));
      expect(icon.right, lessThan(title.left));
      expect(icon.size, const Size(24, 24));
      await tester.pump(const Duration(milliseconds: 900));
      expect(painters(tester).first.progress.value, greaterThan(.4));
      timeline.accept(view, phase: 'complete');
      await tester.pumpWidget(
        app(view, timeline, complete: true, locale: const Locale('en')),
      );
      expect(painters(tester).first.progress.value, greaterThan(.4));
      await tester.pumpAndSettle();
      expect(painters(tester).every((p) => p.progress.value == 1), true);
      final next = results(operation: 'scan-two');
      timeline.accept(next, phase: 'reading');
      await tester.pumpWidget(app(next, timeline));
      expect(painters(tester).first.progress.value, lessThan(.1));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('scrolling virtualized rows does not replay arrivals', (
    tester,
  ) async {
    final timeline = HangarArrivalTimeline(
      now: () => Duration(
        milliseconds: tester.binding.clock.now().millisecondsSinceEpoch,
      ),
    );
    final view = results(count: 40);
    timeline.accept(view, phase: 'reading');
    await tester.pumpWidget(app(view, timeline));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(painters(tester).every((p) => p.progress.value == 1), true);
    await tester.drag(find.byType(ListView), const Offset(0, 1300));
    await tester.pumpAndSettle();
    expect(painters(tester).every((p) => p.progress.value == 1), true);
    expect(tester.takeException(), isNull);
  });
  for (final system in [false, true]) {
    testWidgets(
      'reduced motion from ${system ? "system" : "settings"} starts and remains static',
      (tester) async {
        final view = results();
        final timeline = HangarArrivalTimeline()..accept(view);
        await tester.pumpWidget(
          app(view, timeline, systemReduced: system, userReduced: !system),
        );
        expect(painters(tester).every((p) => p.progress.value == 1), true);
        await tester.pumpWidget(app(view, timeline));
        expect(painters(tester).every((p) => p.progress.value == 1), true);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
    testWidgets('narrow icon rows render in ${mode.name}', (tester) async {
      final view = results();
      final timeline = HangarArrivalTimeline()..accept(view);
      await tester.pumpWidget(
        app(view, timeline, mode: mode, userReduced: true),
      );
      await tester.pumpAndSettle();
      expect(painters(tester), hasLength(4));
      expect(painters(tester).every((p) => p.hull != p.ammunition), true);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('HANGAR_READER_GOLDENS')) {
        await expectLater(
          find.byKey(const Key('capture')),
          matchesGoldenFile(
            '../../../../.artifacts/hangar-reader-ui/combat-${mode.name}.png',
          ),
        );
      }
    });
  }
}
