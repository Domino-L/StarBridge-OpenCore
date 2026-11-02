import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_read_status.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_summary.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/personal_profile/profile_refresh_retention_test.dart'
    show HeldRefreshProfile;
import 'interaction_batch3i_test.dart' show scopedApp;

final _captureDir = const bool.hasEnvironment('INTERACTION_CAPTURE_DIR')
    ? const String.fromEnvironment('INTERACTION_CAPTURE_DIR')
    : visualOutputDir(
        'interaction_motion_batch3fd_20261017',
        legacySubdirectory: 'review',
      );
const _suites = [
  InteractionSuite.rail,
  InteractionSuite.scan,
  InteractionSuite.glow,
];
const _locales = [Locale('zh', 'CN'), Locale('zh', 'TW'), Locale('en', 'US')];
const _actions = [
  'profile-refresh',
  'profile-preview',
  'profile-edit',
  'profile-preview-exit',
  'profile-retry',
];

Finder _key(String key) => find.byKey(Key(key));

class _PartsProbe {
  _PartsProbe(this.suite, this.light, this.locale)
    : port = HeldRefreshProfile() {
    module = createPersonalProfileModule(port);
  }

  // The existing port and actual module own the projection and refresh state;
  // this harness only arranges the three production components for inspection.
  final InteractionSuite suite;
  final bool light;
  final Locale locale;
  late final PersonalProfileModule module;
  final HeldRefreshProfile port;
  final frame = GlobalKey();
  final calls = <String, int>{for (final key in _actions) key: 0};

  void _count(String key) => calls[key] = calls[key]! + 1;

  Widget app() {
    final parts = ValueListenableBuilder<PersonalProfileProjection>(
      valueListenable: module.projection,
      builder: (context, projection, _) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PersonalProfileSectionHeading(
                projection: projection,
                showOwnerActions: true,
                onVisibility: () {},
                onPreview: () => _count('profile-preview'),
                onEdit: () => _count('profile-edit'),
                onRefresh: () {
                  _count('profile-refresh');
                  unawaited(module.refresh());
                },
              ),
              const SizedBox(height: 24),
              PersonalProfileVisitorPreviewBanner(
                onExit: () => _count('profile-preview-exit'),
              ),
              const SizedBox(height: 24),
              PersonalProfileUnavailableView(
                failureKey: 'profile.error.unavailable',
                retrying: projection.operation != PersonalProfileOperation.none,
                onRetry: () {
                  _count('profile-retry');
                  return module.refresh();
                },
              ),
            ],
          ),
        ),
      ),
    );
    final base = scopedApp(parts, suite, light: light) as MaterialApp;
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

Future<void> _frames(WidgetTester t) async {
  await t.pump();
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

List<double> _rectData(Rect rect) => [
  rect.left,
  rect.top,
  rect.width,
  rect.height,
];

Map<String, Object?> _layout(
  WidgetTester t,
  _PartsProbe probe,
  double width,
  String phase,
) {
  expect(t.takeException(), isNull, reason: '$phase must not overflow');
  final rects = <String, Object?>{};
  for (final type in [
    PersonalProfileSectionHeading,
    PersonalProfileVisitorPreviewBanner,
    PersonalProfileUnavailableView,
  ]) {
    final target = find.byType(type);
    expect(target, findsOneWidget);
    final context = t.element(target);
    expect(Localizations.localeOf(context), probe.locale);
    expect(MediaQuery.textScalerOf(context).scale(16), 24);
    final rect = t.getRect(target);
    expect(rect.width, greaterThan(0));
    expect(rect.left, greaterThanOrEqualTo(-0.01));
    expect(rect.right, lessThanOrEqualTo(width + 0.01));
    rects['$type'] = _rectData(rect);
  }
  return {'phase': phase, 'components': rects, 'overflow': false};
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
            'Production profile parts over real module projection; offscreen',
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
          testWidgets(
            '3fd parts $suite $palette ${locale.toLanguageTag()} $width',
            (t) async {
              size(t, Size(width, 1000));
              final probe = _PartsProbe(suite, light, locale);
              addTearDown(probe.module.dispose);
              await probe.module.initialize();
              await t.pumpWidget(probe.app());
              await _frames(t);
              final phases = [_layout(t, probe, width, 'ready')];
              final gate = Completer<PersonalProfileSnapshot>();
              probe.port.readGate = gate;
              final refreshing = probe.module.refresh();
              await _frames(t);
              expect(
                probe.module.projection.value.operation,
                PersonalProfileOperation.refreshing,
              );
              phases.add(_layout(t, probe, width, 'refreshing-retrying'));
              gate.complete(await probe.port.delegate.read());
              await refreshing;
              await _frames(t);
              phases.add(_layout(t, probe, width, 'ready-after-refresh'));
              expect(probe.port.reads, 2);
              expect(probe.port.saves, 0);
              expect(probe.calls.values, everyElement(0));
              layouts.add({
                'suite': suite.name,
                'palette': palette,
                'locale': locale.toLanguageTag(),
                'width': width,
                'states': phases,
              });
              await t.pumpWidget(const SizedBox());
              await _frames(t);
            },
          );
        }
      }

      testWidgets('3fd parts touch pixels $suite $palette', (t) async {
        size(t, const Size(500, 1000));
        final probe = _PartsProbe(suite, light, const Locale('zh', 'CN'));
        addTearDown(probe.module.dispose);
        await probe.module.initialize();
        await t.pumpWidget(probe.app());
        await _frames(t);
        _layout(t, probe, 500, 'ready');
        for (final key in _actions) {
          final target = _key(key);
          expect(target, findsOneWidget);
          await t.ensureVisible(target);
          await _frames(t);
          final beforeRect = t.getRect(target);
          final before = await _pixels(t, probe.frame, beforeRect);
          await t.pump(const Duration(milliseconds: 150));
          await t.pump(const Duration(milliseconds: 32));
          final idle = await _pixels(t, probe.frame, beforeRect);
          expect(_changedPixels(before, idle), 0, reason: '$key idle control');
          expect(t.getRect(target), beforeRect);
          final gesture = await t.startGesture(
            beforeRect.center,
            kind: ui.PointerDeviceKind.touch,
          );
          try {
            await t.pump(const Duration(milliseconds: 150));
            await t.pump(const Duration(milliseconds: 32));
            final pressedRect = t.getRect(target);
            expect(pressedRect, beforeRect, reason: '$key press geometry');
            final pressed = await _pixels(t, probe.frame, beforeRect);
            final changed = _changedPixels(before, pressed);
            expect(
              changed,
              greaterThan(0),
              reason: '$key visible touch feedback',
            );
            expect(probe.calls.values, everyElement(0));
            expect(probe.port.reads, 1);
            expect(probe.port.saves, 0);
            expect(t.takeException(), isNull);
            feedback.add({
              'suite': suite.name,
              'palette': palette,
              'control': key,
              'input': 'touch held, no hover, no callback',
              'elapsedMs': 182,
              'idleChangedPixels': 0,
              'pressedChangedPixels': changed,
              'beforeRect': _rectData(beforeRect),
              'pressedRect': _rectData(pressedRect),
            });
            if (key == 'profile-retry') {
              await _capture(
                t,
                probe.frame,
                '${suite.name}-$palette-profile-parts-cn-narrow',
              );
            }
          } finally {
            await gesture.cancel();
            await _frames(t);
          }
        }
        expect(probe.calls.values, everyElement(0));
        expect(probe.port.reads, 1);
        expect(probe.port.saves, 0);
        await t.pumpWidget(const SizedBox());
        await _frames(t);
      });
    }
  }
}
