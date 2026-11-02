import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_controls.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module_style_controls.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_schema.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_value_format.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/overlay_settings/overlay_settings_ux_a_test.dart'
    show settings;
import 'interaction_batch3bz_test.dart' show WorkspacePort;
import 'interaction_batch3i_test.dart' show scopedApp;

final _captureDir = const bool.hasEnvironment('INTERACTION_CAPTURE_DIR')
    ? const String.fromEnvironment('INTERACTION_CAPTURE_DIR')
    : visualOutputDir(
        'interaction_motion_batch3fi_20261017',
        legacySubdirectory: 'review',
      );
const _suites = [
  InteractionSuite.rail,
  InteractionSuite.scan,
  InteractionSuite.glow,
];
const _locales = [Locale('zh', 'CN'), Locale('zh', 'TW'), Locale('en', 'US')];
Finder _key(String value) => find.byKey(Key(value));
Finder _duration() => _key('overlay-duration-memberPresence-input');
Finder _opacity() => find.descendant(
  of: _key('overlay-module-background-opacity-Notice'),
  matching: find.byType(SuiteSlider),
);

class _Probe {
  _Probe(this.suite, this.light, this.locale) {
    port.values = settings({
      'showNotice': true,
      'showEventNotifications': true,
      'enableStartupTransition': true,
      'startupTransitionFrameRate': 'Fps60',
      'animationFrameRate': 'Fps60',
      'eventNotificationTypes': 1,
      'eventNotificationDurationSeconds': 2.5,
      'eventNotificationDurations': {
        ...Map<String, Object?>.from(
          settings()['eventNotificationDurations']! as Map,
        ),
        'memberPresence': 2.5,
      },
      'eventNotificationTextOpacity': .75,
      'eventNotificationBackgroundOpacity': .35,
      'eventNotificationDecorationOpacity': .65,
    });
    port.geometry = [
      for (final item in port.geometry)
        item.key == 'Notice'
            ? item.copyWith(
                textOpacity: .85,
                backgroundOpacity: .4,
                decorationOpacity: .7,
              )
            : item,
    ];
    module = OverlayWorkspaceModule(port);
  }
  final InteractionSuite suite;
  final bool light;
  final Locale locale;
  final port = WorkspacePort();
  late final OverlayWorkspaceModule module;
  final frame = GlobalKey();
  final callbacks = <String>[];
  bool reduce = false;
  late StateSetter update;

  void _setting(String field, Object? value) {
    callbacks.add('setting:$field');
    module.updateSetting(field, value);
  }

  void _layout(OverlayWorkspaceLayoutItem item, bool coalesce) {
    callbacks.add('layout:${item.key}:$coalesce');
    module.updateLayoutItem(item, coalesce: coalesce);
  }

  Widget _body() => ValueListenableBuilder<OverlayWorkspaceProjection>(
    valueListenable: module.projection,
    builder: (context, projection, _) {
      final values = projection.settings!;
      final startup = OverlayWorkspaceSettingsGroup(
        group: 'startup',
        fields: overlayWorkspaceFieldSpecs
            .where((f) => f.field == 'startupTransitionFrameRate')
            .toList(),
        settings: values,
        onChanged: _setting,
        onExperiencePreset: (preset) {
          callbacks.add('preset:$preset');
          module.applyExperiencePreset(preset);
        },
      );
      final notice = OverlayWorkspaceSettingsGroup(
        group: 'notice',
        fields: const [],
        settings: values,
        onChanged: _setting,
        footer: OverlayWorkspaceModuleStyleControls(
          group: 'notice',
          layout: projection.layout,
          settings: values,
          onLayoutChanged: _layout,
          onSettingChanged: _setting,
        ),
      );
      final events = OverlayWorkspaceSettingsGroup(
        group: 'events',
        fields: overlayWorkspaceFieldSpecs
            .where(
              (f) => const {
                'showEventNotifications',
                'eventNotificationDurationSeconds',
                'eventNotificationTypes',
                'eventNotificationDurations',
              }.contains(f.field),
            )
            .toList(),
        settings: values,
        onChanged: _setting,
        footer: OverlayWorkspaceModuleStyleControls(
          group: 'events',
          layout: projection.layout,
          settings: values,
          onLayoutChanged: _layout,
          onSettingChanged: _setting,
        ),
      );
      return SingleChildScrollView(
        key: const Key('3fi-scroll'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, bounds) => bounds.maxWidth >= 900
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            startup,
                            const SizedBox(height: 16),
                            notice,
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: events),
                    ],
                  )
                : Column(
                    children: [
                      startup,
                      const SizedBox(height: 16),
                      notice,
                      const SizedBox(height: 16),
                      events,
                    ],
                  ),
          ),
        ),
      );
    },
  );

  Widget app() => StatefulBuilder(
    builder: (_, setState) {
      update = setState;
      final base = scopedApp(
        _body(),
        suite,
        light: light,
        reduce: reduce,
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
    },
  );
}

Future<void> _frames(WidgetTester t, [int count = 8]) async {
  await t.pump();
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Finder _inputTarget(WidgetTester t, Finder target) {
  final widget = t.widget(target);
  if (widget is SuiteSwitch) {
    final row = find.ancestor(
      of: target,
      matching: find.byType(SuitePressable),
    );
    if (row.evaluate().isNotEmpty) return row.first;
    // A non-native tile's trailing control is also decorative. Cross its
    // IgnorePointer before looking for the tile's actual row gesture owner.
    final ignored = find.ancestor(
      of: target,
      matching: find.byType(IgnorePointer),
    );
    if (ignored.evaluate().isNotEmpty) {
      return find
          .ancestor(of: ignored.first, matching: find.byType(GestureDetector))
          .first;
    }
  }
  return target;
}

Future<void> _reveal(WidgetTester t, Finder target) async {
  expect(target, findsOneWidget);
  await t.ensureVisible(target);
  await _frames(t);
}

Future<void> _tap(WidgetTester t, Finder target) async {
  await _reveal(t, target);
  await t.tap(_inputTarget(t, target));
  await _frames(t);
}

Future<void> _tab(WidgetTester t, Finder target) async {
  await _reveal(t, target);
  // Pointer hit-testing climbs past the decorative switch, but keyboard
  // traversal belongs to its original, explicitly supplied focus node.
  final widget = t.widget(target);
  final node = switch (widget) {
    SuiteChoiceChip value => value.focusNode!,
    SuitePressable value => value.focusNode!,
    SuiteSlider value => value.focusNode!,
    SuiteSwitch value => value.focusNode!,
    TextField value => value.focusNode!,
    _ => throw StateError('Unsupported real keyboard target $widget'),
  };
  for (var i = 0; !node.hasPrimaryFocus && i < 200; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
  }
  expect(node.hasPrimaryFocus, isTrue, reason: 'Real Tab must reach $target');
}

Future<void> _keyboard(
  WidgetTester t,
  Finder target, [
  LogicalKeyboardKey? key,
]) async {
  await _tab(t, target);
  await t.sendKeyEvent(key ?? LogicalKeyboardKey.enter);
  await t.pump();
  await t.pump();
}

List<double> _rect(Rect value) => [
  value.left,
  value.top,
  value.width,
  value.height,
];

Map<String, Object?> _bounds(
  WidgetTester t,
  _Probe probe,
  Size viewport,
  String phase,
) {
  expect(t.takeException(), isNull, reason: '$phase overflow');
  final context = t.element(find.byType(OverlayWorkspaceSettingsGroup).first);
  expect(Localizations.localeOf(context), probe.locale);
  expect(MediaQuery.textScalerOf(context).scale(16), 24);
  final boxes = <String, Object?>{};
  for (final key in [
    'overlay-group-startup',
    'overlay-group-notice',
    'overlay-group-events',
    'overlay-module-style-Notice',
    'overlay-module-style-Events',
  ]) {
    final target = _key(key);
    expect(target, findsOneWidget);
    final rect = t.getRect(target);
    expect(rect.width, greaterThan(0));
    expect(rect.left, greaterThanOrEqualTo(-0.01));
    expect(rect.right, lessThanOrEqualTo(viewport.width + .01));
    boxes[key] = _rect(rect);
  }
  return {'phase': phase, 'boxes': boxes, 'overflow': false};
}

void _percent(WidgetTester t, String key, double value) {
  expect(
    find.descendant(
      of: _key(key),
      matching: find.text('${(value * 100).round()}%'),
    ),
    findsOneWidget,
  );
}

void _numberLabel(WidgetTester t, _Probe probe) {
  final spec = overlayWorkspaceFieldSpecs.singleWhere(
    (f) => f.field == 'eventNotificationDurationSeconds',
  );
  final strings = AppStrings.of(
    t.element(_key('overlay-field-eventNotificationDurationSeconds')),
  );
  final value = probe.module.projection.value.settings![spec.field]! as num;
  expect(
    find.text(
      '${strings.text('overlay.workspace.field.${spec.field}')}  ${overlayWorkspaceFormatValue(spec, value, strings)}',
    ),
    findsOneWidget,
  );
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

int _changes(List<int> a, List<int> b) {
  expect(b.length, a.length);
  var result = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      result++;
    }
  }
  return result;
}

String _signature(_Probe probe) => jsonEncode({
  'settings': probe.module.projection.value.settings!.toMap(),
  'layout': probe.module.projection.value.layout.map((e) => e.toMap()).toList(),
  'callbacks': probe.callbacks.length,
});

Future<Map<String, Object?>> _touch(
  WidgetTester t,
  _Probe probe,
  Finder target, {
  bool requirePressFeedback = true,
}) async {
  await _reveal(t, target);
  target = _inputTarget(t, target);
  final rect = t.getRect(target);
  final signature = _signature(probe);
  final before = await _pixels(t, probe.frame, rect);
  await t.pump(const Duration(milliseconds: 182));
  expect(_changes(before, await _pixels(t, probe.frame, rect)), 0);
  final gesture = await t.startGesture(
    rect.center,
    kind: ui.PointerDeviceKind.touch,
  );
  var changed = 0;
  try {
    await t.pump(const Duration(milliseconds: 150));
    await t.pump(const Duration(milliseconds: 32));
    expect(t.getRect(target), rect);
    changed = _changes(before, await _pixels(t, probe.frame, rect));
    if (requirePressFeedback) {
      expect(
        changed,
        greaterThan(0),
        reason: 'Touch must give visible local feedback',
      );
    }
    expect(_signature(probe), signature);
  } finally {
    await gesture.cancel();
    await _frames(t);
  }
  expect(_signature(probe), signature);
  return {
    'rect': _rect(rect),
    'idleChangedPixels': 0,
    'touchChangedPixels': changed,
    'requiresPressFeedback': requirePressFeedback,
  };
}

Future<Map<String, Object?>> _pointer(
  WidgetTester t,
  _Probe probe,
  Finder target,
) async {
  await _reveal(t, target);
  target = _inputTarget(t, target);
  final scanChoice =
      probe.suite == InteractionSuite.scan &&
      t.widget(target) is SuiteChoiceChip;
  final beforeRect = t.getRect(target);
  final before = await _pixels(t, probe.frame, beforeRect);
  await t.tap(target);
  await t.pump();
  await t.pump(const Duration(milliseconds: 80));
  final rect = t.getRect(target);
  final moving = await _pixels(t, probe.frame, rect);
  final selectionChanges = _changes(
    before,
    await _pixels(t, probe.frame, beforeRect),
  );
  expect(
    selectionChanges,
    greaterThan(0),
    reason: 'Real pointer activation visibly updates the controlled choice',
  );
  await _frames(t);
  expect(t.getRect(target), rect);
  final changed = _changes(moving, await _pixels(t, probe.frame, rect));
  if (scanChoice) {
    // Scan chips deliberately use an immediate selected bracket/check face,
    // not a post-selection transient. Their held-press cue is checked by
    // _touch above; here require the actual click to visibly select them.
    expect(t.widget<SuiteChoiceChip>(target).selected, isTrue);
  } else {
    expect(
      changed,
      greaterThan(0),
      reason: 'Pointer intermediate feedback is visible',
    );
  }
  return {
    'rect': _rect(rect),
    'sampleMs': 80,
    'activationChangedPixels': selectionChanges,
    'requiresPostSelectionTransient': !scanChoice,
    'movingToFinalChanges': changed,
  };
}

Future<Map<String, Object?>> _static(
  WidgetTester t,
  _Probe probe,
  Finder target,
) async {
  target = _inputTarget(t, target);
  final rect = t.getRect(target);
  final before = await _pixels(t, probe.frame, rect);
  await t.pump(const Duration(milliseconds: 600));
  expect(t.getRect(target), rect);
  final changed = _changes(before, await _pixels(t, probe.frame, rect));
  expect(changed, 0, reason: 'Keyboard/reduced input leaves no FX tail');
  return {'rect': _rect(rect), 'elapsedMs': 600, 'changedPixels': changed};
}

Future<void> _drag(WidgetTester t, Finder target) async {
  await _reveal(t, target);
  final slider = t.widget<SuiteSlider>(target);
  final rect = t.getRect(target);
  final fraction = (slider.value - slider.min) / (slider.max - slider.min);
  final start = Offset(
    rect.left + 16 + (rect.width - 32) * fraction,
    rect.center.dy,
  );
  final gesture = await t.startGesture(start, kind: ui.PointerDeviceKind.touch);
  await gesture.moveBy(const Offset(60, 0));
  await t.pump(const Duration(milliseconds: 80));
  await gesture.up();
  await _frames(t);
}

Future<void> _capture(WidgetTester t, GlobalKey frame, String name) async {
  final boundary =
      frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory(_captureDir);
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final layouts = <Map<String, Object?>>[], feedback = <Map<String, Object?>>[];
  setUpAll(() async {
    await loadFonts();
    await (FontLoader('Source Code Pro')
          ..addFont(rootBundle.load('assets/fonts/SourceCodeVF-Upright.ttf')))
        .load();
  });
  tearDownAll(() async {
    final dir = Directory(_captureDir);
    await dir.create(recursive: true);
    await File('${dir.path}/visual-summary.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scope': 'Real selected settings groups/module-style widgets over original OverlayWorkspaceModule/WorkspacePort fixture',
        'excluded': 'Full workspace/editor, preset pages, native overlay/runtime, saved persistence/device acceptance',
        'fields': [
          'startupTransitionFrameRate',
          'experience presets',
          'showEventNotifications',
          'eventNotificationDurationSeconds',
          'eventNotificationTypes',
          'eventNotificationDurations',
        ],
        'gallery': 'Real scroll; wide two-column component fixture, narrow stacked; not a full workspace layout claim',
        'textScale': 1.5,
        'height': 1100,
        'layouts': layouts,
        'feedback': feedback,
      }),
    );
  });
  for (final suite in _suites) {
    for (final light in [false, true]) {
      final palette = light ? 'light' : 'dark';
      for (final locale in _locales) {
        for (final width in [540.0, 1100.0]) {
          testWidgets(
            '3fi groups/styles $suite $palette ${locale.toLanguageTag()} $width 1.5x',
            (t) async {
              final viewport = Size(width, 1100);
              size(t, viewport);
              final probe = _Probe(suite, light, locale);
              addTearDown(probe.module.dispose);
              await probe.module.initialize();
              await t.pumpWidget(probe.app());
              await _frames(t);
              final phases = [_bounds(t, probe, viewport, 'initial')];
              for (final entry in <String, double>{
                'text': .85,
                'background': .4,
                'decoration': .7,
              }.entries) {
                _percent(
                  t,
                  'overlay-module-${entry.key}-opacity-Notice',
                  entry.value,
                );
              }
              for (final entry in <String, double>{
                'text': .75,
                'background': .35,
                'decoration': .65,
              }.entries) {
                _percent(
                  t,
                  'overlay-module-${entry.key}-opacity-Events',
                  entry.value,
                );
              }
              _numberLabel(t, probe);
              final field = t.widget<TextField>(_duration());
              expect(field.controller!.text, '2.5');
              expect(field.enabled, isTrue);
              final controller = field.controller, focus = field.focusNode;
              if (locale == const Locale('zh', 'CN') && width == 1100) {
                await _capture(
                  t,
                  probe.frame,
                  '${suite.name}-$palette-overlay-controls-cn-wide',
                );
              }
              await _tap(t, _key('overlay-event-type-2'));
              expect(
                probe
                    .module
                    .projection
                    .value
                    .settings!['eventNotificationTypes'],
                3,
              );
              expect(
                t.widget<TextField>(_duration()).controller,
                same(controller),
              );
              expect(t.widget<TextField>(_duration()).focusNode, same(focus));
              await _reveal(
                t,
                _key('overlay-duration-${overlayDurationFields.last.$1}-input'),
              );
              final visible = t.getRect(
                _key('overlay-duration-${overlayDurationFields.last.$1}-input'),
              );
              expect(visible.top, greaterThanOrEqualTo(-.01));
              expect(visible.bottom, lessThanOrEqualTo(1100.01));
              phases.add(_bounds(t, probe, viewport, 'duration-tail-readable'));
              await _reveal(t, _key('overlay-module-style-Events'));
              if (locale == const Locale('zh', 'CN') && width == 540) {
                await _capture(
                  t,
                  probe.frame,
                  '${suite.name}-$palette-overlay-controls-cn-narrow',
                );
              }
              // Edits save on their own; nothing else is written.
              expect(
                probe.port.writes.every(
                  (w) => w.$1.kind == OverlayWorkspaceMutationKind.saveActive,
                ),
                isTrue,
              );
              expect(
                probe.port.runtimeCalls.every(
                  (e) => e.$1 == OverlayRuntimeAction.getState,
                ),
                isTrue,
              );
              layouts.add({
                'suite': suite.name,
                'palette': palette,
                'locale': locale.toLanguageTag(),
                'width': width,
                'phases': phases,
              });
              await t.pumpWidget(const SizedBox());
              await _frames(t);
            },
          );
        }
      }

      testWidgets('3fi real input pixels/values $suite $palette', (t) async {
        const viewport = Size(1100, 1100);
        size(t, viewport);
        final probe = _Probe(suite, light, const Locale('zh', 'CN'));
        addTearDown(probe.module.dispose);
        await probe.module.initialize();
        await t.pumpWidget(probe.app());
        await _frames(t);
        final checks = <Map<String, Object?>>[];
        final smooth = _key('overlay-experience-Smooth'),
            balanced = _key('overlay-experience-Balanced');
        final event1 = _key('overlay-event-type-1'),
            event2 = _key('overlay-event-type-2');
        checks.add({
          'kind': 'experience-touch',
          ...await _touch(t, probe, smooth),
        });
        checks.add({
          'kind': 'experience-pointer',
          ...await _pointer(t, probe, smooth),
        });
        expect(
          probe.module.projection.value.settings!['startupTransitionFrameRate'],
          'Fps120',
        );
        expect(
          probe.module.projection.value.settings!['animationFrameRate'],
          'Fps120',
        );
        checks.add({'kind': 'event-touch', ...await _touch(t, probe, event2)});
        checks.add({
          'kind': 'event-pointer',
          ...await _pointer(t, probe, event2),
        });
        expect(
          probe.module.projection.value.settings!['eventNotificationTypes'],
          3,
        );
        await _keyboard(t, balanced);
        expect(
          probe.module.projection.value.settings!['startupTransitionFrameRate'],
          'Fps60',
        );
        checks.add({
          'kind': 'experience-keyboard',
          ...await _static(t, probe, balanced),
        });
        await _keyboard(t, event1);
        expect(
          probe.module.projection.value.settings!['eventNotificationTypes'],
          2,
        );
        checks.add({
          'kind': 'event-keyboard',
          ...await _static(t, probe, event1),
        });
        final lock = _key('overlay-module-lock-Notice');
        // SuiteSwitch acknowledges the requested value on release, rather
        // than playing a press face while the undecided gesture is held.
        // Cancellation must still leave the owner and geometry unchanged.
        checks.add({
          'kind': 'lock-touch-cancel',
          ...await _touch(t, probe, lock, requirePressFeedback: false),
        });
        checks.add({'kind': 'lock-pointer', ...await _pointer(t, probe, lock)});
        expect(
          probe.module.projection.value.layout
              .singleWhere((e) => e.key == 'Notice')
              .isLocked,
          isTrue,
        );
        await _keyboard(t, lock);
        expect(
          probe.module.projection.value.layout
              .singleWhere((e) => e.key == 'Notice')
              .isLocked,
          isFalse,
        );
        checks.add({'kind': 'lock-keyboard', ...await _static(t, probe, lock)});
        await _drag(t, _opacity());
        final opacity = probe.module.projection.value.layout
            .singleWhere((e) => e.key == 'Notice')
            .backgroundOpacity;
        expect(opacity, greaterThan(.4));
        _percent(t, 'overlay-module-background-opacity-Notice', opacity);
        await _keyboard(t, _opacity(), LogicalKeyboardKey.arrowRight);
        final stepped = probe.module.projection.value.layout
            .singleWhere((e) => e.key == 'Notice')
            .backgroundOpacity;
        expect(stepped, greaterThan(opacity));
        _percent(t, 'overlay-module-background-opacity-Notice', stepped);
        checks.add({
          'kind': 'opacity-keyboard',
          ...await _static(t, probe, _opacity()),
        });
        await _drag(t, _key('overlay-field-eventNotificationDurationSeconds'));
        expect(
          (probe
                  .module
                  .projection
                  .value
                  .settings!['eventNotificationDurationSeconds']!
              as num),
          greaterThan(2.5),
        );
        _numberLabel(t, probe);
        final original = t.widget<TextField>(_duration());
        final controller = original.controller, focus = original.focusNode;
        await _tab(t, _duration());
        await t.enterText(_duration(), '7.5');
        await t.testTextInput.receiveAction(TextInputAction.done);
        await _frames(t);
        expect(
          (probe
                  .module
                  .projection
                  .value
                  .settings!['eventNotificationDurations']!
              as Map)['memberPresence'],
          7.5,
        );
        final edited = t.widget<TextField>(_duration());
        expect(edited.controller, same(controller));
        expect(edited.focusNode, same(focus));
        expect(edited.controller!.text, '7.5');
        expect(
          edited.decoration!.suffixText,
          AppStrings.of(t.element(_duration()))
              .text('overlay.workspace.durationSecondsSuffix'),
        );
        probe.update(() => probe.reduce = true);
        await t.pump();
        await t.pump();
        await _reveal(t, lock);
        await t.tap(_inputTarget(t, lock));
        await t.pump();
        await t.pump();
        expect(
          probe.module.projection.value.layout
              .singleWhere((e) => e.key == 'Notice')
              .isLocked,
          isTrue,
        );
        checks.add({
          'kind': 'lock-reduced-pointer',
          ...await _static(t, probe, lock),
        });
        await _reveal(t, event1);
        await t.tap(event1);
        await t.pump();
        await t.pump();
        expect(
          probe.module.projection.value.settings!['eventNotificationTypes'],
          3,
        );
        checks.add({
          'kind': 'event-reduced-pointer',
          ...await _static(t, probe, event1),
        });
        await _tap(t, _key('overlay-field-showEventNotifications'));
        expect(
          probe.module.projection.value.settings!['showEventNotifications'],
          isFalse,
        );
        expect(t.widget<SuiteChoiceChip>(event2).onActivate, isNull);
        expect(t.widget<TextField>(_duration()).enabled, isFalse);
        expect(t.widget<TextField>(_duration()).controller, same(controller));
        final numeric = _key('overlay-field-eventNotificationDurationSeconds');
        expect(t.widget<SuiteSlider>(numeric).onChanged, isNull);
        await _reveal(t, event2);
        final signature = _signature(probe);
        final writes = probe.port.writes.length;
        await t.tapAt(t.getCenter(event2));
        await _frames(t);
        expect(_signature(probe), signature);
        expect(probe.port.writes, hasLength(writes));
        _bounds(t, probe, viewport, 'disabled-events');
        feedback.add({
          'suite': suite.name,
          'palette': palette,
          'checks': checks,
        });
        await t.pumpWidget(const SizedBox());
        await _frames(t);
      });
    }
  }
}
