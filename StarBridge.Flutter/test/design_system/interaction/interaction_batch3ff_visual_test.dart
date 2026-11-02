import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_read_status.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3fb_hangar_test.dart' show hangarInventory;
import 'interaction_batch3i_test.dart' show scopedApp;

final _captureDir = const bool.hasEnvironment('INTERACTION_CAPTURE_DIR')
    ? const String.fromEnvironment('INTERACTION_CAPTURE_DIR')
    : visualOutputDir(
        'interaction_motion_batch3ff_20261017',
        legacySubdirectory: 'review',
      );
const _suites = [
  InteractionSuite.rail,
  InteractionSuite.scan,
  InteractionSuite.glow,
];
const _locales = [Locale('zh', 'CN'), Locale('zh', 'TW'), Locale('en', 'US')];

class _StatusProbe {
  _StatusProbe(
    this.suite,
    this.light,
    this.locale, {
    this.source = InteractionSource.keyboard,
  });
  final InteractionSuite suite;
  final bool light;
  final Locale locale;
  final InteractionSource source;
  final frame = GlobalKey();
  int retries = 0;

  Widget app() {
    // Separate production presentations, not a synthetic inventory/save owner.
    // Explicit provenance selects the existing static/animated wait contract.
    final snapshot = hangarInventory();
    final body = SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('read-failure / retry'),
            const SizedBox(height: 12),
            LocalHangarReadStatus(
              key: const Key('3ff-read-failed'),
              snapshot: null,
              saved: false,
              loading: false,
              favoriteBusy: false,
              favoriteFailed: false,
              failed: true,
              onRetry: () => retries++,
            ),
            const Divider(height: 40),
            Text('refresh-wait / ${source.name}'),
            const SizedBox(height: 12),
            LocalHangarReadStatus(
              key: const Key('3ff-refresh-wait'),
              snapshot: snapshot,
              saved: true,
              loading: true,
              favoriteBusy: false,
              favoriteFailed: false,
              failed: false,
              readSource: source,
              readPhase: 1,
              onRetry: () => retries++,
            ),
            const Divider(height: 40),
            Text('favorite-wait / ${source.name}'),
            const SizedBox(height: 12),
            LocalHangarReadStatus(
              key: const Key('3ff-favorite-wait'),
              snapshot: snapshot,
              saved: true,
              loading: false,
              favoriteBusy: true,
              favoriteFailed: false,
              failed: false,
              favoriteSource: source,
              favoritePhase: 1,
              onRetry: () => retries++,
            ),
          ],
        ),
      ),
    );
    final base = scopedApp(body, suite, light: light) as MaterialApp;
    return RepaintBoundary(
      key: frame,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: base.theme,
        themeAnimationDuration: base.themeAnimationDuration,
        locale: locale,
        supportedLocales: base.supportedLocales,
        localizationsDelegates: base.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: base.builder!(context, child),
        ),
        home: base.home,
      ),
    );
  }
}

Future<List<int>> _pixels(
  WidgetTester t,
  GlobalKey frame, {
  Rect? globalRect,
}) async {
  final boundary =
      frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final rect = globalRect?.shift(-boundary.localToGlobal(Offset.zero));
  return (await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final pixels = bytes!.buffer.asUint8List();
      if (rect == null) return pixels.toList();
      final left = rect.left.floor().clamp(0, image.width).toInt();
      final top = rect.top.floor().clamp(0, image.height).toInt();
      final right = rect.right.ceil().clamp(0, image.width).toInt();
      final bottom = rect.bottom.ceil().clamp(0, image.height).toInt();
      return <int>[
        for (var y = top; y < bottom; y++)
          ...pixels.sublist(
            (y * image.width + left) * 4,
            (y * image.width + right) * 4,
          ),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

int _changedPixels(List<int> before, List<int> after) {
  expect(after.length, before.length);
  var changed = 0;
  for (var i = 0; i < before.length; i += 4) {
    if (before[i] != after[i] ||
        before[i + 1] != after[i + 1] ||
        before[i + 2] != after[i + 2] ||
        before[i + 3] != after[i + 3]) {
      changed++;
    }
  }
  return changed;
}

Future<void> _capture(WidgetTester t, GlobalKey frame, String name) async {
  final boundary =
      frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = Directory(_captureDir);
      await output.create(recursive: true);
      await File('${output.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final records = <Map<String, Object?>>[];
  final pointerRecords = <Map<String, Object?>>[];
  setUpAll(() async {
    await loadFonts();
    await (FontLoader('Source Code Pro')
          ..addFont(rootBundle.load('assets/fonts/SourceCodeVF-Upright.ttf')))
        .load();
  });
  tearDownAll(() async {
    final output = Directory(_captureDir);
    await output.create(recursive: true);
    await File('${output.path}/read-status-visual-summary.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scope': 'Offscreen production read-status components; no IO owner',
        'viewport': [500, 1000],
        'textScale': 1.5,
        'waitSources': 'keyboard static control; pointer animated presentation',
        'cases': records,
        'pointerCases': pointerRecords,
      }),
    );
  });
  for (final suite in _suites) {
    for (final light in [false, true]) {
      final palette = light ? 'light' : 'dark';
      for (final locale in _locales) {
        testWidgets(
          '3ff read status $suite $palette ${locale.toLanguageTag()} 1.5x',
          (t) async {
            size(t, const Size(500, 1000));
            final probe = _StatusProbe(suite, light, locale);
            await t.pumpWidget(probe.app());
            await t.pump();
            await t.pump(const Duration(milliseconds: 300));
            expect(t.takeException(), isNull);
            final rects = <String, List<double>>{};
            for (final key in [
              '3ff-read-failed',
              '3ff-refresh-wait',
              '3ff-favorite-wait',
            ]) {
              final target = find.byKey(Key(key));
              expect(target, findsOneWidget);
              final context = t.element(target);
              expect(Localizations.localeOf(context), locale);
              expect(MediaQuery.textScalerOf(context).scale(16), 24);
              final rect = t.getRect(target);
              expect(rect.width, greaterThan(0));
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(500));
              expect(rect.top, greaterThanOrEqualTo(0));
              expect(rect.bottom, lessThanOrEqualTo(1000));
              rects[key] = [rect.left, rect.top, rect.width, rect.height];
            }
            expect(find.byKey(const Key('local-hangar-retry')), findsOneWidget);
            expect(find.byType(SuiteProgressBar), findsNothing);
            expect(find.byType(LinearProgressIndicator), findsNothing);
            final before = await _pixels(t, probe.frame);
            await t.pump(const Duration(milliseconds: 600));
            final after = await _pixels(t, probe.frame);
            expect(
              after,
              orderedEquals(before),
              reason: 'Keyboard waits remain visually static',
            );
            expect(probe.retries, 0);
            if (locale == const Locale('zh', 'CN')) {
              await _capture(
                t,
                probe.frame,
                '${suite.name}-$palette-hangar-read-status-cn',
              );
            }
            records.add({
              'suite': suite.name,
              'palette': palette,
              'locale': locale.toLanguageTag(),
              'rects': rects,
              'idleChangedPixels': 0,
              'retryInvocations': probe.retries,
            });
            await t.pumpWidget(const SizedBox());
            await t.pump();
          },
        );
      }
      testWidgets('3ff pointer wait pixels $suite $palette 1.5x', (t) async {
        size(t, const Size(500, 1000));
        final probe = _StatusProbe(
          suite,
          light,
          const Locale('zh', 'CN'),
          source: InteractionSource.pointer,
        );
        await t.pumpWidget(probe.app());
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(t.takeException(), isNull);
        expect(find.byType(SuiteProgressBar), findsNWidgets(2));
        final rects = <String, Rect>{
          for (final key in ['3ff-refresh-wait', '3ff-favorite-wait'])
            key: t.getRect(find.byKey(Key(key))),
        };
        final before = <String, List<int>>{};
        for (final entry in rects.entries) {
          expect(entry.value.left, greaterThanOrEqualTo(0));
          expect(entry.value.right, lessThanOrEqualTo(500));
          expect(entry.value.top, greaterThanOrEqualTo(0));
          expect(entry.value.bottom, lessThanOrEqualTo(1000));
          before[entry.key] = await _pixels(
            t,
            probe.frame,
            globalRect: entry.value,
          );
        }
        // Same elapsed interval as the static keyboard controls, measured on
        // each actual wait region independently rather than on ticker count.
        await t.pump(const Duration(milliseconds: 600));
        final waits = <String, Object?>{};
        for (final entry in rects.entries) {
          final rectAfter = t.getRect(find.byKey(Key(entry.key)));
          expect(
            rectAfter,
            entry.value,
            reason: '${entry.key} must not relayout',
          );
          final after = await _pixels(t, probe.frame, globalRect: rectAfter);
          final changed = _changedPixels(before[entry.key]!, after);
          expect(
            changed,
            greaterThan(0),
            reason: '${entry.key} visible pointer wait',
          );
          waits[entry.key] = {
            'changedPixels': changed,
            'beforeRect': [
              entry.value.left,
              entry.value.top,
              entry.value.width,
              entry.value.height,
            ],
            'afterRect': [
              rectAfter.left,
              rectAfter.top,
              rectAfter.width,
              rectAfter.height,
            ],
          };
        }
        expect(probe.retries, 0);
        expect(t.takeException(), isNull);
        final screenshot = '${suite.name}-$palette-hangar-pointer-wait-cn';
        await _capture(t, probe.frame, screenshot);
        pointerRecords.add({
          'suite': suite.name,
          'palette': palette,
          'locale': 'zh-CN',
          'source': 'pointer (component provenance fixture; no IO owner)',
          'baselineMs': 300,
          'elapsedMs': 600,
          'captureMs': 900,
          'waits': waits,
          'retryInvocations': probe.retries,
          'screenshot': '$screenshot.png',
        });
        await t.pumpWidget(const SizedBox());
        await t.pump();
      });
    }
  }
}
