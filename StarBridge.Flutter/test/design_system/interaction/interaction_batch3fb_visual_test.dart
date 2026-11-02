import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_controls.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_overview.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_summary.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3fb_hangar_test.dart'
    show HangarProbe, HangarProbePort, hangarKey, mountHangar, summaryHeader;

final _captureDir = const bool.hasEnvironment('INTERACTION_CAPTURE_DIR')
    ? const String.fromEnvironment('INTERACTION_CAPTURE_DIR')
    : visualOutputDir(
        'interaction_motion_batch3fb_20261017',
        legacySubdirectory: 'review',
      );
const _suites = [
  InteractionSuite.rail,
  InteractionSuite.scan,
  InteractionSuite.glow,
];
const _locales = [Locale('zh', 'CN'), Locale('zh', 'TW'), Locale('en', 'US')];

// Invoke the original probe builder with this mounted StateSetter. In
// particular, probe.update still rebuilds the same page, port and frame, rather
// than updating an unmounted copy of the behaviour fixture.
Widget _localizedProbe(HangarProbe probe, Locale locale) {
  final original = probe.app() as StatefulBuilder;
  return StatefulBuilder(
    builder: (context, update) {
      final boundary = original.builder(context, update) as RepaintBoundary;
      final app = boundary.child! as MaterialApp;
      return RepaintBoundary(
        key: boundary.key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: app.theme,
          themeAnimationDuration: app.themeAnimationDuration,
          locale: locale,
          supportedLocales: app.supportedLocales,
          localizationsDelegates: app.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: app.builder!(context, child),
          ),
          home: app.home,
        ),
      );
    },
  );
}

List<double> _rectData(Rect rect) => [
  rect.left,
  rect.top,
  rect.width,
  rect.height,
];

void _withinWidth(WidgetTester t, Finder target, double width, String name) {
  expect(target, findsOneWidget, reason: name);
  final rect = t.getRect(target);
  expect(rect.width, greaterThan(0), reason: name);
  expect(rect.left, greaterThanOrEqualTo(-0.01), reason: name);
  expect(rect.right, lessThanOrEqualTo(width + 0.01), reason: name);
}

Future<List<int>> _buttonPixels(
  WidgetTester t,
  GlobalKey frame,
  Rect globalRect,
) async {
  final boundary =
      frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final offset = boundary.localToGlobal(Offset.zero);
  final rect = globalRect.shift(-offset);
  return (await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      final left = rect.left.floor().clamp(0, image.width).toInt();
      final top = rect.top.floor().clamp(0, image.height).toInt();
      final right = rect.right.ceil().clamp(0, image.width).toInt();
      final bottom = rect.bottom.ceil().clamp(0, image.height).toInt();
      return <int>[
        for (var y = top; y < bottom; y++)
          ...bytes.sublist(
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
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = Directory(_captureDir);
      await output.create(recursive: true);
      await File('${output.path}/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void _unchangedOwner(HangarProbe probe, {required int reads}) {
  expect(probe.port, isA<HangarProbePort>());
  expect(probe.port.reads, reads);
  expect(probe.port.saves, 0);
  expect(probe.port.favorites, isEmpty);
  expect(probe.scanOpens, 0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final layouts = <Map<String, Object?>>[];
  final feedback = <Map<String, Object?>>[];

  setUpAll(() async {
    await loadFonts();
    await (FontLoader('Source Code Pro')
          ..addFont(rootBundle.load('assets/fonts/SourceCodeVF-Upright.ttf')))
        .load();
  });

  tearDownAll(() async {
    final output = Directory(_captureDir);
    await output.create(recursive: true);
    await File('${output.path}/visual-summary.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scope': 'Offscreen actual LocalHangarPage; not device acceptance',
        'textScale': 1.5,
        'height': 1200,
        'layouts': layouts,
        'touchFeedback': feedback,
      }),
    );
  });

  for (final suite in _suites) {
    for (final light in [false, true]) {
      final palette = light ? 'light' : 'dark';
      for (final locale in _locales) {
        for (final width in [1120.0, 540.0]) {
          final name =
              '${suite.name} $palette ${locale.toLanguageTag()} $width';
          testWidgets('3fb hangar 1.5x layout $name', (t) async {
            size(t, Size(width, 1200));
            final probe = HangarProbe(suite)..light = light;
            await t.pumpWidget(_localizedProbe(probe, locale));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull, reason: '$name collapsed');
            expect(
              Localizations.localeOf(
                t.element(find.byType(LocalHangarToolbar)),
              ),
              locale,
            );
            expect(
              MediaQuery.textScalerOf(
                t.element(find.byType(LocalHangarToolbar)),
              ).scale(16),
              24,
            );
            for (final entry in <String, Finder>{
              'toolbar': find.byType(LocalHangarToolbar),
              'filters': find.byType(LocalHangarFilters),
              'summary': find.byType(LocalHangarOverview),
            }.entries) {
              _withinWidth(t, entry.value, width, '$name ${entry.key}');
            }
            await t.ensureVisible(summaryHeader());
            await t.tap(summaryHeader());
            await t.pumpAndSettle();
            expect(t.takeException(), isNull, reason: '$name expanded');
            expect(find.byType(LocalHangarSummary), findsOneWidget);
            _withinWidth(
              t,
              find.byType(LocalHangarSummary),
              width,
              '$name expanded summary',
            );
            layouts.add({
              'suite': suite.name,
              'palette': palette,
              'locale': locale.toLanguageTag(),
              'width': width,
              'toolbar': _rectData(t.getRect(find.byType(LocalHangarToolbar))),
              'filters': _rectData(t.getRect(find.byType(LocalHangarFilters))),
              'expandedSummary': _rectData(
                t.getRect(find.byType(LocalHangarSummary)),
              ),
              'overflow': false,
            });
            _unchangedOwner(probe, reads: 1);
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
          });
        }
      }

      testWidgets('3fb hangar touch pixels ${suite.name} $palette', (t) async {
        // The shared mount and localized wrapper both keep StatefulBuilder ->
        // RepaintBoundary -> MaterialApp ancestry. The same page and port must
        // therefore survive the locale/text-scale rebuild without another read.
        final probe = await mountHangar(t, suite);
        probe.light = light;
        await t.pumpWidget(_localizedProbe(probe, const Locale('zh', 'CN')));
        await t.pumpAndSettle();
        const reads = 1;
        _unchangedOwner(probe, reads: reads);
        await t.tap(summaryHeader());
        await t.pumpAndSettle();
        final target = hangarKey('local-hangar-read');
        expect(target, findsOneWidget);
        await t.ensureVisible(target);
        await t.pumpAndSettle();
        final beforeRect = t.getRect(target);
        final before = await _buttonPixels(t, probe.frame, beforeRect);
        // A matched no-input control rules out idle repaint/async font effects.
        await t.pump(const Duration(milliseconds: 150));
        await t.pump(const Duration(milliseconds: 32));
        final idle = await _buttonPixels(t, probe.frame, beforeRect);
        expect(t.getRect(target), beforeRect, reason: 'Idle rect control');
        expect(_changedPixels(before, idle), 0, reason: 'Stable idle control');

        final gesture = await t.startGesture(
          beforeRect.center,
          kind: ui.PointerDeviceKind.touch,
        );
        try {
          await t.pump(const Duration(milliseconds: 150));
          await t.pump(const Duration(milliseconds: 32));
          final pressedRect = t.getRect(target);
          expect(pressedRect, beforeRect, reason: 'Press must not relayout');
          final pressed = await _buttonPixels(t, probe.frame, beforeRect);
          final changed = _changedPixels(before, pressed);
          expect(changed, greaterThan(0), reason: 'Visible touch feedback');
          expect(t.takeException(), isNull);
          _unchangedOwner(probe, reads: reads);
          final screenshot = '${suite.name}-$palette-hangar-cn-wide-pressed';
          await _capture(t, probe.frame, screenshot);
          feedback.add({
            'suite': suite.name,
            'palette': palette,
            'input': 'touch; pointer held; no hover',
            'elapsedMs': 182,
            'summaryExpanded': true,
            'idleChangedPixels': 0,
            'pressedChangedPixels': changed,
            'beforeRect': _rectData(beforeRect),
            'pressedRect': _rectData(pressedRect),
            'screenshot': '$screenshot.png',
          });
        } finally {
          await gesture.cancel();
          await t.pumpAndSettle();
        }
        _unchangedOwner(probe, reads: reads);
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      });
    }
  }
}
