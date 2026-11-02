import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_detail.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_copy.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_ship_details.dart';
import 'package:starbridge_flutter/features/hangar/ship_specifications_panel.dart';
import 'package:starbridge_flutter/features/hangar/ship_specifications_copy.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/hangar/ship_specifications_test.dart'
    as spec_fixture
    show Port, specs, ship;
import 'interaction_batch3fb_hangar_test.dart'
    show HangarProbePort, hangarInventory, hangarKey;
import 'interaction_batch3i_test.dart' show scopedApp;

final _captureDir = const bool.hasEnvironment('INTERACTION_CAPTURE_DIR')
    ? const String.fromEnvironment('INTERACTION_CAPTURE_DIR')
    : visualOutputDir(
        'interaction_motion_batch3fe_20261017',
        legacySubdirectory: 'review',
      );
const _suites = [
  InteractionSuite.rail,
  InteractionSuite.scan,
  InteractionSuite.glow,
];
const _locales = [Locale('zh', 'CN'), Locale('zh', 'TW'), Locale('en', 'US')];

class _DetailsProbe {
  _DetailsProbe(this.suite, this.light, this.locale);
  final InteractionSuite suite;
  final bool light;
  final Locale locale;
  final frame = GlobalKey();
  final port = HangarProbePort()..snapshot = hangarInventory();

  Widget app() {
    final base = scopedApp(
      LocalHangarPage(port: port, onRead: null),
      suite,
      light: light,
    ) as MaterialApp;
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

// A separate component-constraint fixture, not a Page-entry claim. It uses the
// original public-specification test provider and the production detail/panel;
// no image editor, catalog cache, optional Page adapter or model owner is added.
class _SpecProbe {
  _SpecProbe(this.suite, this.light, this.locale);
  final InteractionSuite suite;
  final bool light;
  final Locale locale;
  final frame = GlobalKey();
  final port = spec_fixture.Port();

  Widget app() {
    final base = scopedApp(
      LocalHangarDetail(
        title: spec_fixture.ship.title,
        body: ShipSpecificationsPanel(ship: spec_fixture.ship, provider: port),
      ),
      suite,
      light: light,
    ) as MaterialApp;
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

Map<String, Object?> _specLayout(
  WidgetTester t,
  _SpecProbe probe, {
  required bool expanded,
  required String phase,
}) {
  expect(t.takeException(), isNull, reason: 'Specifications $phase overflow');
  expect(find.byType(LocalHangarPage), findsNothing);
  final target = find.byType(ShipSpecificationsPanel);
  expect(target, findsOneWidget);
  final context = t.element(target);
  expect(Localizations.localeOf(context), probe.locale);
  expect(MediaQuery.textScalerOf(context).scale(16), 24);
  final panel = t.getRect(_panel());
  expect(panel.width, closeTo(expanded ? 880 : 440, 0.01));
  expect(panel.height, closeTo(1100, 0.01));
  expect(panel.left, closeTo(expanded ? 110 : 660, 0.01));
  final content = t.getRect(target);
  expect(content.width, greaterThan(0));
  expect(content.left, greaterThanOrEqualTo(panel.left));
  expect(content.right, lessThanOrEqualTo(panel.right));
  return {
    'phase': phase,
    'panelRect': _rectData(panel),
    'specificationRect': _rectData(content),
    'overflow': false,
  };
}

void _specValues(WidgetTester t) {
  final context = t.element(find.byType(ShipSpecificationsPanel));
  expect(find.text('0 SCU'), findsOneWidget);
  expect(
    find.text('${MaterialLocalizations.of(context).formatDecimal(12000)} kg'),
    findsOneWidget,
  );
}

Future<void> _frames(WidgetTester t) async {
  await t.pump();
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _activate(WidgetTester t, Finder target) async {
  expect(target, findsOneWidget);
  await t.ensureVisible(target);
  await _frames(t);
  await t.tap(target);
  await _frames(t);
}

Finder _panel() => find
    .descendant(
      of: find.byType(LocalHangarDetail),
      matching: find.byType(Material),
    )
    .first;

Finder _bodyScroll() => find
    .descendant(
      of: find.byType(LocalHangarDetail),
      matching: find.byType(SingleChildScrollView),
    )
    .first;

List<double> _rectData(Rect rect) => [
  rect.left,
  rect.top,
  rect.width,
  rect.height,
];

void _ownerUnchanged(_DetailsProbe probe) {
  expect(probe.port.reads, 1);
  expect(probe.port.saves, 0);
  expect(probe.port.favorites, isEmpty);
  expect(probe.port.snapshot.revision, 1);
  expect(probe.port.snapshot.ships.first.id, 'alpha');
}

Map<String, Object?> _layout(
  WidgetTester t,
  _DetailsProbe probe,
  Size viewport, {
  required bool expanded,
  required String phase,
}) {
  expect(t.takeException(), isNull, reason: '$phase must not overflow');
  expect(find.byType(LocalHangarDetail), findsOneWidget);
  expect(find.byType(LocalHangarShipDetails), findsOneWidget);
  final context = t.element(find.byType(LocalHangarDetail));
  expect(Localizations.localeOf(context), probe.locale);
  expect(MediaQuery.textScalerOf(context).scale(16), 24);
  final rect = t.getRect(_panel());
  final expectedWidth = math.min(viewport.width, expanded ? 880.0 : 440.0);
  expect(rect.width, closeTo(expectedWidth, 0.01), reason: phase);
  expect(rect.height, closeTo(viewport.height, 0.01), reason: phase);
  expect(rect.top, closeTo(0, 0.01), reason: phase);
  expect(
    rect.left,
    closeTo(
      expanded
          ? (viewport.width - expectedWidth) / 2
          : viewport.width - expectedWidth,
      0.01,
    ),
    reason: phase,
  );
  for (final key in ['hangar-detail-expand', 'hangar-detail-close']) {
    final action = t.getRect(hangarKey(key));
    expect(action.left, greaterThanOrEqualTo(rect.left));
    expect(action.right, lessThanOrEqualTo(rect.right));
    expect(action.top, greaterThanOrEqualTo(rect.top));
    expect(action.bottom, lessThanOrEqualTo(rect.bottom));
  }
  _ownerUnchanged(probe);
  return {'phase': phase, 'expanded': expanded, 'panelRect': _rectData(rect)};
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
  final specificationLayouts = <Map<String, Object?>>[];
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
        'scope': 'Actual LocalHangarPage entry and details; offscreen only',
        'excluded': 'Optional Page specification-provider/image-provider/editor workflows',
        'height': 1100,
        'textScale': 1.5,
        'layouts': layouts,
        'touchFeedback': feedback,
        'specificationComponentScope':
            'LocalHangarDetail + ShipSpecificationsPanel + existing test Port; '
            'not a Page-entry provider integration',
        'specificationLayouts': specificationLayouts,
      }),
    );
  });

  for (final suite in _suites) {
    for (final light in [false, true]) {
      final palette = light ? 'light' : 'dark';
      for (final locale in _locales) {
        for (final expanded in [false, true]) {
          final constraint = expanded ? 880 : 440;
          testWidgets(
            '3fe specification parts $suite $palette ${locale.toLanguageTag()} $constraint',
            (t) async {
              size(t, const Size(1100, 1100));
              final probe = _SpecProbe(suite, light, locale);
              await t.pumpWidget(probe.app());
              await _frames(t);
              if (expanded) {
                await _activate(t, hangarKey('hangar-detail-expand'));
              }
              expect(probe.port.requests, hasLength(1));
              expect(probe.port.refreshes, [false]);
              final state = t.state(find.byType(ShipSpecificationsPanel));
              final phases = [
                _specLayout(t, probe, expanded: expanded, phase: 'loading'),
              ];
              expect(find.text('0 SCU'), findsNothing);
              probe.port.requests.single.complete(spec_fixture.specs);
              await _frames(t);
              _specValues(t);
              phases.add(
                _specLayout(t, probe, expanded: expanded, phase: 'ready'),
              );

              await _activate(t, hangarKey('ship-spec-flight'));
              expect(find.text('220 m/s'), findsOneWidget);
              await _activate(t, hangarKey('ship-spec-components'));
              final component = find.text('Fixture cannon × 2');
              expect(component, findsOneWidget);
              expect(find.text('S2'), findsOneWidget);
              await t.ensureVisible(component);
              await _frames(t);
              final bodyRect = t.getRect(_bodyScroll());
              final componentRect = t.getRect(component);
              expect(
                componentRect.top,
                greaterThanOrEqualTo(bodyRect.top - 0.01),
              );
              expect(
                componentRect.bottom,
                lessThanOrEqualTo(bodyRect.bottom + 0.01),
              );
              final scrollable = find
                  .descendant(
                    of: _bodyScroll(),
                    matching: find.byType(Scrollable),
                  )
                  .first;
              final position = t.state<ScrollableState>(scrollable).position;
              phases.add({
                ..._specLayout(
                  t,
                  probe,
                  expanded: expanded,
                  phase: 'groups-open-readable',
                ),
                'scrollExtent': position.maxScrollExtent,
                'readOffset': position.pixels,
                'componentRect': _rectData(componentRect),
                'bodyViewport': _rectData(bodyRect),
              });
              if (locale == const Locale('zh', 'CN') && !expanded) {
                position.jumpTo(0);
                await _frames(t);
                await _capture(
                  t,
                  probe.frame,
                  '${suite.name}-$palette-specification-cn-compact',
                );
              }

              await _activate(t, hangarKey('ship-spec-refresh'));
              expect(probe.port.requests, hasLength(2));
              expect(probe.port.refreshes, [false, true]);
              _specValues(t);
              expect(find.text('220 m/s'), findsOneWidget);
              phases.add(
                _specLayout(
                  t,
                  probe,
                  expanded: expanded,
                  phase: 'refresh-pending-retains-value',
                ),
              );
              probe.port.requests.last.completeError(
                StateError('visual refresh refusal'),
              );
              await _frames(t);
              _specValues(t);
              final copy = LocalHangarCopy(
                t.element(find.byType(ShipSpecificationsPanel)),
              );
              expect(find.text(copy.specsFailure), findsOneWidget);
              phases.add(
                _specLayout(
                  t,
                  probe,
                  expanded: expanded,
                  phase: 'failed-retains-value',
                ),
              );

              await _activate(t, hangarKey('ship-spec-refresh'));
              expect(probe.port.requests, hasLength(3));
              _specValues(t);
              probe.port.requests.last.complete(spec_fixture.specs);
              await _frames(t);
              _specValues(t);
              expect(find.text(copy.specsFailure), findsNothing);
              expect(
                t.state(find.byType(ShipSpecificationsPanel)),
                same(state),
              );
              expect(probe.port.refreshes, [false, true, true]);
              phases.add(
                _specLayout(t, probe, expanded: expanded, phase: 'recovered'),
              );
              specificationLayouts.add({
                'suite': suite.name,
                'palette': palette,
                'locale': locale.toLanguageTag(),
                'constraintWidth': constraint,
                'states': phases,
              });
              await t.pumpWidget(const SizedBox());
              await _frames(t);
            },
          );
        }
      }
    }
  }

  for (final suite in _suites) {
    for (final light in [false, true]) {
      final palette = light ? 'light' : 'dark';
      for (final locale in _locales) {
        for (final width in [540.0, 1100.0]) {
          testWidgets(
            '3fe real hangar details $suite $palette ${locale.toLanguageTag()} $width',
            (t) async {
              final viewport = Size(width, 1100);
              size(t, viewport);
              final probe = _DetailsProbe(suite, light, locale);
              await t.pumpWidget(probe.app());
              await _frames(t);
              final pageState = t.state(find.byType(LocalHangarPage));
              expect(hangarKey('local-hangar-ship-alpha'), findsOneWidget);
              await _activate(t, hangarKey('hangar-open-alpha'));
              final detailState = t.state(find.byType(LocalHangarShipDetails));
              final phases = [
                _layout(
                  t,
                  probe,
                  viewport,
                  expanded: false,
                  phase: 'card-compact',
                ),
              ];
              await _activate(t, hangarKey('hangar-detail-expand'));
              phases.add(
                _layout(t, probe, viewport, expanded: true, phase: 'expanded'),
              );
              expect(
                t.state(find.byType(LocalHangarShipDetails)),
                same(detailState),
              );
              await _activate(t, hangarKey('hangar-detail-expand'));
              phases.add(
                _layout(
                  t,
                  probe,
                  viewport,
                  expanded: false,
                  phase: 'compact-again',
                ),
              );
              expect(
                t.state(find.byType(LocalHangarShipDetails)),
                same(detailState),
              );

              if (width == 540) {
                // Short-window stress gives the real body a nonzero scroll
                // range without inventing optional specifications or images.
                // At 560 high the short inventory fixture still fits; 320
                // leaves less body space than its existing 400x225 fallback
                // image plus metadata. Keep both extent/offset assertions.
                const shortWindowHeight = 320.0;
                size(t, Size(width, shortWindowHeight));
                await _frames(t);
                final scrollable = find
                    .descendant(
                      of: _bodyScroll(),
                      matching: find.byType(Scrollable),
                    )
                    .first;
                final position = t.state<ScrollableState>(scrollable).position;
                expect(position.maxScrollExtent, greaterThan(0));
                await t.drag(_bodyScroll(), const Offset(0, -240));
                await _frames(t);
                expect(position.pixels, greaterThan(0));
                expect(
                  t.takeException(),
                  isNull,
                  reason: 'Narrow real body scroll',
                );
                phases.add({
                  'phase': 'narrow-short-window-scroll',
                  'height': shortWindowHeight,
                  'extent': position.maxScrollExtent,
                  'offset': position.pixels,
                });
                size(t, viewport);
                await _frames(t);
                phases.add(
                  _layout(
                    t,
                    probe,
                    viewport,
                    expanded: false,
                    phase: 'restored-height',
                  ),
                );
              }
              await _activate(t, hangarKey('hangar-detail-close'));
              expect(find.byType(LocalHangarDetail), findsNothing);
              expect(t.state(find.byType(LocalHangarPage)), same(pageState));
              await _activate(t, hangarKey('hangar-list'));
              await _activate(t, hangarKey('hangar-open-alpha'));
              phases.add(
                _layout(
                  t,
                  probe,
                  viewport,
                  expanded: false,
                  phase: 'row-compact',
                ),
              );
              await _activate(t, hangarKey('hangar-detail-close'));
              _ownerUnchanged(probe);
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

      testWidgets('3fe detail touch pixels $suite $palette', (t) async {
        const viewport = Size(540, 1100);
        size(t, viewport);
        final probe = _DetailsProbe(suite, light, const Locale('zh', 'CN'));
        await t.pumpWidget(probe.app());
        await _frames(t);
        await _activate(t, hangarKey('hangar-open-alpha'));
        final detailState = t.state(find.byType(LocalHangarShipDetails));
        for (final key in [
          'hangar-detail-expand',
          'hangar-detail-favorite',
          'hangar-detail-close',
        ]) {
          final target = hangarKey(key);
          await t.ensureVisible(target);
          await _frames(t);
          final beforeRect = t.getRect(target);
          final before = await _pixels(t, probe.frame, beforeRect);
          await t.pump(const Duration(milliseconds: 150));
          await t.pump(const Duration(milliseconds: 32));
          final idle = await _pixels(t, probe.frame, beforeRect);
          expect(_changedPixels(before, idle), 0, reason: '$key idle control');
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
            _layout(t, probe, viewport, expanded: false, phase: '$key held');
            expect(
              t.state(find.byType(LocalHangarShipDetails)),
              same(detailState),
            );
            _ownerUnchanged(probe);
            feedback.add({
              'suite': suite.name,
              'palette': palette,
              'control': key,
              'input': 'touch held, no hover, no action until release',
              'elapsedMs': 182,
              'idleChangedPixels': 0,
              'pressedChangedPixels': changed,
              'beforeRect': _rectData(beforeRect),
              'pressedRect': _rectData(pressedRect),
            });
            if (key == 'hangar-detail-expand') {
              await _capture(
                t,
                probe.frame,
                '${suite.name}-$palette-hangar-detail-cn',
              );
            }
          } finally {
            await gesture.cancel();
            await _frames(t);
          }
          _ownerUnchanged(probe);
          expect(
            t.state(find.byType(LocalHangarShipDetails)),
            same(detailState),
          );
        }
        await _activate(t, hangarKey('hangar-detail-close'));
        _ownerUnchanged(probe);
        await t.pumpWidget(const SizedBox());
        await _frames(t);
      });
    }
  }
}
