import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_visibility.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_visibility_dialog.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3fc_visibility_test.dart'
    show
        VisibilityAccess,
        VisibilityProbe,
        openVisibility,
        visibilityFrames,
        visibilityKey;

final _captureDir = const bool.hasEnvironment('INTERACTION_CAPTURE_DIR')
    ? const String.fromEnvironment('INTERACTION_CAPTURE_DIR')
    : visualOutputDir(
        'interaction_motion_batch3fc_20261017',
        legacySubdirectory: 'review',
      );
const _suites = [
  InteractionSuite.rail,
  InteractionSuite.scan,
  InteractionSuite.glow,
];
const _locales = [Locale('zh', 'CN'), Locale('zh', 'TW'), Locale('en', 'US')];

// Delegate the original probe's builder to the mounted setter. Keeping the
// StatefulBuilder/Boundary/MaterialApp ancestry preserves the active Navigator,
// dialog and access owner when locale, text scale or live settings change.
Widget _localizedProbe(VisibilityProbe probe, Locale locale) {
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

Map<String, Object?> _checkLayout(
  WidgetTester t,
  Size viewport,
  String phase,
  Locale locale,
) {
  expect(t.takeException(), isNull, reason: '$phase must not overflow');
  final dialog = find.byType(AlertDialog);
  expect(dialog, findsOneWidget);
  expect(find.byType(ProfileVisibilityDialog), findsOneWidget);
  final context = t.element(dialog);
  expect(Localizations.localeOf(context), locale);
  expect(MediaQuery.textScalerOf(context).scale(16), 24);
  final rect = t.getRect(dialog);
  expect(rect.width, greaterThan(0));
  expect(rect.height, greaterThan(0));
  expect(rect.left, greaterThanOrEqualTo(-0.01), reason: phase);
  expect(rect.top, greaterThanOrEqualTo(-0.01), reason: phase);
  expect(rect.right, lessThanOrEqualTo(viewport.width + 0.01), reason: phase);
  expect(rect.bottom, lessThanOrEqualTo(viewport.height + 0.01), reason: phase);
  for (final key in ['cancel', 'save', if (phase == 'failure') 'reload']) {
    final action = t.getRect(visibilityKey(key));
    expect(action.left, greaterThanOrEqualTo(rect.left - 0.01));
    expect(action.right, lessThanOrEqualTo(rect.right + 0.01));
    expect(action.top, greaterThanOrEqualTo(rect.top - 0.01));
    expect(action.bottom, lessThanOrEqualTo(rect.bottom + 0.01));
  }
  return {'phase': phase, 'dialogRect': _rectData(rect), 'overflow': false};
}

void _unchangedOwner(VisibilityAccess access, int reads) {
  expect(access.reads, reads);
  expect(access.writes, isEmpty);
}

Future<List<int>> _pixels(
  WidgetTester t,
  GlobalKey frame,
  Rect globalRect,
) async {
  final boundary =
      frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final rect = globalRect.shift(-boundary.localToGlobal(Offset.zero));
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final layouts = <Map<String, Object?>>[];
  final feedback = <Map<String, Object?>>[];
  setUpAll(loadFonts);
  tearDownAll(() async {
    final output = Directory(_captureDir);
    await output.create(recursive: true);
    await File('${output.path}/visual-summary.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scope':
            'Offscreen production visibility dialog; not device acceptance',
        'height': 1000,
        'textScale': 1.5,
        'layouts': layouts,
        'touchFeedback': feedback,
      }),
    );
  });

  for (final suite in _suites) {
    for (final light in [false, true]) {
      final palette = light ? 'light' : 'dark';
      for (final locale in _locales) {
        for (final width in [500.0, 900.0]) {
          final name =
              '${suite.name} $palette ${locale.toLanguageTag()} $width';
          testWidgets('3fc visibility 1.5x states $name', (t) async {
            final probe = await openVisibility(t, suite, holdRead: true);
            final viewport = Size(width, 1000);
            size(t, viewport);
            probe.light = light;
            await t.pumpWidget(_localizedProbe(probe, locale));
            // Pending operations own a live wait indicator. Never settle them.
            await visibilityFrames(t);
            _unchangedOwner(probe.access, 1);
            final phases = <Map<String, Object?>>[
              _checkLayout(t, viewport, 'initial-pending', locale),
            ];

            probe.access.readGate!.completeError(
              StateError('visual read refusal'),
            );
            await visibilityFrames(t);
            phases.add(_checkLayout(t, viewport, 'failure', locale));
            expect(visibilityKey('reload'), findsOneWidget);

            final reload = Completer<ProfileVisibilityState>();
            probe.access.readGate = reload;
            await t.tap(visibilityKey('reload'));
            await visibilityFrames(t);
            phases.add(_checkLayout(t, viewport, 'reload-pending', locale));
            _unchangedOwner(probe.access, 2);

            reload.complete(probe.access.state);
            await visibilityFrames(t);
            phases.add(_checkLayout(t, viewport, 'read-ready', locale));
            expect(visibilityKey('friendsOnly'), findsOneWidget);
            _unchangedOwner(probe.access, 2);
            layouts.add({
              'suite': suite.name,
              'palette': palette,
              'locale': locale.toLanguageTag(),
              'width': width,
              'states': phases,
            });
            await t.pumpWidget(const SizedBox());
            await visibilityFrames(t);
          });
        }
      }

      testWidgets('3fc visibility touch pixels ${suite.name} $palette', (
        t,
      ) async {
        final probe = await openVisibility(t, suite);
        const viewport = Size(500, 1000);
        size(t, viewport);
        probe.light = light;
        await t.pumpWidget(_localizedProbe(probe, const Locale('zh', 'CN')));
        await visibilityFrames(t);
        _checkLayout(t, viewport, 'read-ready', const Locale('zh', 'CN'));
        _unchangedOwner(probe.access, 1);
        final target = visibilityKey('save');
        final beforeRect = t.getRect(target);
        final before = await _pixels(t, probe.frame, beforeRect);
        await t.pump(const Duration(milliseconds: 150));
        await t.pump(const Duration(milliseconds: 32));
        final idle = await _pixels(t, probe.frame, beforeRect);
        expect(_changedPixels(before, idle), 0, reason: 'Stable idle control');
        expect(t.getRect(target), beforeRect);

        final gesture = await t.startGesture(
          beforeRect.center,
          kind: ui.PointerDeviceKind.touch,
        );
        try {
          await t.pump(const Duration(milliseconds: 150));
          await t.pump(const Duration(milliseconds: 32));
          final pressedRect = t.getRect(target);
          expect(pressedRect, beforeRect, reason: 'Press must not relayout');
          final pressed = await _pixels(t, probe.frame, beforeRect);
          final changed = _changedPixels(before, pressed);
          expect(
            changed,
            greaterThan(0),
            reason: 'Visible touch save feedback',
          );
          _unchangedOwner(probe.access, 1);
          expect(t.takeException(), isNull);
          final screenshot =
              '${suite.name}-$palette-visibility-cn-narrow-ready';
          await _capture(t, probe.frame, screenshot);
          feedback.add({
            'suite': suite.name,
            'palette': palette,
            'input': 'touch; held; no hover; save not invoked',
            'elapsedMs': 182,
            'idleChangedPixels': 0,
            'pressedChangedPixels': changed,
            'beforeRect': _rectData(beforeRect),
            'pressedRect': _rectData(pressedRect),
            'screenshot': '$screenshot.png',
          });
        } finally {
          await gesture.cancel();
          await visibilityFrames(t);
        }
        _unchangedOwner(probe.access, 1);
        await t.pumpWidget(const SizedBox());
        await visibilityFrames(t);
      });
    }
  }
}
