import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/features/settings/settings_page.dart';
import 'package:starbridge_flutter/features/settings/settings_models.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_sources.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

final _captureDir = const bool.hasEnvironment('INTERACTION_CAPTURE_DIR')
    ? const String.fromEnvironment('INTERACTION_CAPTURE_DIR')
    : visualOutputDir(
        'interaction_motion_batch3fh_20261017',
        legacySubdirectory: 'review',
      );
const _suites = [
  InteractionSuite.rail,
  InteractionSuite.scan,
  InteractionSuite.glow,
];
const _locales = [Locale('zh', 'CN'), Locale('zh', 'TW'), Locale('en', 'US')];
final _sourceRef = 'officialFleet:${'a' * 64}';

Finder _key(String key) => find.byKey(Key(key));
Finder _section(SettingsSection section) =>
    _key('settings-section-${section.name}');
Finder _selector() => _key('notification-source-mode-$_sourceRef');
Finder _segment(int index) => find
    .descendant(of: _selector(), matching: find.byType(SuitePressable))
    .at(index);

class _SettingsProbe {
  _SettingsProbe(this.suite, this.light, this.locale);
  final InteractionSuite suite;
  final bool light;
  final Locale locale;
  final frame = GlobalKey();
  bool reduce = false;
  NotificationSourceMode mode = NotificationSourceMode.normal;
  final requests = <NotificationSourceMode>[];
  late StateSetter update;

  Widget _content(BuildContext context, SettingsSection section) {
    final strings = AppStrings.of(context);
    return SingleChildScrollView(
      key: Key('3fh-content-${section.name}'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.text(section.labelKey),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(strings.text(section.descriptionKey)),
            if (section == SettingsSection.notifications) ...[
              const SizedBox(height: 24),
              NotificationSourceRuleRow(
                key: const Key('3fh-source-row'),
                rule: NotificationSourceRule(
                  sourceRef: _sourceRef,
                  kind: NotificationSourceKind.officialFleet,
                  displayName: 'StarBridge fleet',
                  contextLabel: 'SCM',
                  mode: mode,
                ),
                enabled: true,
                onChanged: (next) async {
                  requests.add(next);
                  update(() => mode = next);
                  return true;
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget app() => StatefulBuilder(
    builder: (_, setState) {
      update = setState;
      final base = scopedApp(
        SettingsPage(
          initialSection: SettingsSection.notifications,
          accountAndIdentityBuilder: (context) =>
              _content(context, SettingsSection.accountIdentity),
          generalDataBuilder: (context) =>
              _content(context, SettingsSection.generalData),
          syncPrivacyBuilder: (context) =>
              _content(context, SettingsSection.syncPrivacy),
          notificationsBuilder: (context) =>
              _content(context, SettingsSection.notifications),
          diagnosticsBuilder: (context) =>
              _content(context, SettingsSection.diagnostics),
          helpSupportBuilder: (context) =>
              _content(context, SettingsSection.aboutLegal),
        ),
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

Future<void> _tabEnter(WidgetTester t, Finder target) async {
  expect(target, findsOneWidget);
  await t.ensureVisible(target);
  await _frames(t);
  final widget = t.widget(target);
  final focus = switch (widget) {
    SuitePressable value => value.focusNode!,
    ButtonStyleButton value => value.focusNode!,
    MenuItemButton value => value.focusNode!,
    _ => throw StateError('Unsupported real focus target $widget'),
  };
  for (var i = 0; !focus.hasPrimaryFocus && i < 100; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
  }
  expect(focus.hasPrimaryFocus, isTrue, reason: 'Real Tab must reach $target');
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pump();
  await t.pump();
}

Future<void> _pickSection(WidgetTester t, SettingsSection section) async {
  await t.tap(_key('settings-section-control'));
  await _frames(t);
  final row = find.byKey(ValueKey<Object>(('settings-section', section)));
  expect(row, findsOneWidget);
  await t.ensureVisible(row);
  await _frames(t);
  await t.tap(row);
  await _frames(t);
  expect(_key('3fh-content-${section.name}'), findsOneWidget);
}

List<double> _rect(Rect value) => [
  value.left,
  value.top,
  value.width,
  value.height,
];

Map<String, Object?> _layout(
  WidgetTester t,
  _SettingsProbe probe,
  Size viewport,
  String phase,
) {
  expect(t.takeException(), isNull, reason: '$phase must not overflow');
  expect(find.byType(SettingsPage), findsOneWidget);
  expect(find.byType(NotificationSourceRuleRow), findsOneWidget);
  final context = t.element(find.byType(SettingsPage));
  expect(Localizations.localeOf(context), probe.locale);
  expect(MediaQuery.textScalerOf(context).scale(16), 24);
  final boxes = <String, Object?>{};
  for (final entry in <String, Finder>{
    'page': find.byType(SettingsPage),
    'source-row': _key('3fh-source-row'),
    'source-selector': _selector(),
    if (viewport.width < 600) 'section-picker': _key('settings-section-picker'),
  }.entries) {
    expect(entry.value, findsOneWidget, reason: phase);
    final bounds = t.getRect(entry.value);
    expect(bounds.width, greaterThan(0));
    expect(bounds.height, greaterThan(0));
    expect(bounds.left, greaterThanOrEqualTo(-0.01));
    expect(bounds.right, lessThanOrEqualTo(viewport.width + 0.01));
    expect(bounds.top, greaterThanOrEqualTo(-0.01));
    expect(bounds.bottom, lessThanOrEqualTo(viewport.height + 0.01));
    boxes[entry.key] = _rect(bounds);
  }
  if (viewport.width >= 600) {
    final rail = find.byType(SuiteSideNav);
    expect(rail, findsOneWidget);
    final railBounds = t.getRect(rail);
    expect(railBounds.width, closeTo(viewport.width < 960 ? 196 : 276, 0.01));
    boxes['rail'] = _rect(railBounds);
    for (final section in visibleSettingsSections) {
      final item = t.getRect(_section(section));
      expect(item.left, greaterThanOrEqualTo(railBounds.left));
      expect(item.right, lessThanOrEqualTo(railBounds.right));
    }
  } else {
    expect(find.byType(SuiteSideNav), findsNothing);
  }
  expect(
    find.descendant(of: _selector(), matching: find.byType(StarBridgeIcon)),
    findsNWidgets(3),
    reason: 'All original mode glyphs remain in the shared selector',
  );
  return {'phase': phase, 'boxes': boxes, 'overflow': false};
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
      final right = rect.right.ceil().clamp(0, image.width).toInt();
      final top = rect.top.floor().clamp(0, image.height).toInt();
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

Future<Map<String, Object?>> _touch(
  WidgetTester t,
  _SettingsProbe probe,
  Finder target,
  VoidCallback unchanged,
) async {
  await t.ensureVisible(target);
  await _frames(t);
  final bounds = t.getRect(target);
  final before = await _pixels(t, probe.frame, bounds);
  await t.pump(const Duration(milliseconds: 182));
  expect(_changes(before, await _pixels(t, probe.frame, bounds)), 0);
  final pointer = await t.startGesture(
    bounds.center,
    kind: ui.PointerDeviceKind.touch,
  );
  var changes = 0;
  try {
    await t.pump(const Duration(milliseconds: 150));
    await t.pump(const Duration(milliseconds: 32));
    expect(t.getRect(target), bounds);
    changes = _changes(before, await _pixels(t, probe.frame, bounds));
    expect(
      changes,
      greaterThan(0),
      reason: 'Real touch must have visible feedback',
    );
    unchanged();
  } finally {
    await pointer.cancel();
    await _frames(t);
  }
  unchanged();
  return {'rect': _rect(bounds), 'idleChanges': 0, 'touchChanges': changes};
}

Future<Map<String, Object?>> _pointerSelect(
  WidgetTester t,
  _SettingsProbe probe,
  Finder target,
  Finder region,
) async {
  final targetRect = t.getRect(target);
  final regionRect = t.getRect(region);
  await t.tap(target);
  await t.pump();
  await t.pump(const Duration(milliseconds: 60));
  expect(t.getRect(target), targetRect);
  final moving = await _pixels(t, probe.frame, regionRect);
  await _frames(t);
  expect(t.getRect(region), regionRect);
  final changes = _changes(moving, await _pixels(t, probe.frame, regionRect));
  expect(
    changes,
    greaterThan(0),
    reason: 'Pointer selection has visible in-flight/final difference',
  );
  return {
    'region': _rect(regionRect),
    'sampleMs': 60,
    'movingToFinalChanges': changes,
  };
}

Future<Map<String, Object?>> _static(
  WidgetTester t,
  _SettingsProbe probe,
  Finder region,
) async {
  final bounds = t.getRect(region);
  final before = await _pixels(t, probe.frame, bounds);
  await t.pump(const Duration(milliseconds: 600));
  expect(t.getRect(region), bounds);
  final changes = _changes(before, await _pixels(t, probe.frame, bounds));
  expect(
    changes,
    0,
    reason: 'Keyboard/reduced selection must not leave a moving tail',
  );
  return {'region': _rect(bounds), 'elapsedMs': 600, 'changedPixels': changes};
}

Future<void> _capture(WidgetTester t, GlobalKey frame, String name) async {
  final boundary =
      frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(_captureDir);
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png')
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
    final directory = Directory(_captureDir);
    await directory.create(recursive: true);
    await File('${directory.path}/visual-summary.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scope': 'Actual SettingsPage and NotificationSourceRuleRow with injected content builders/controlled presentation callbacks',
        'excluded': 'Other production settings content, notification persistence, native/device acceptance',
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
            '3fh settings/source $suite $palette ${locale.toLanguageTag()} $width 1.5x',
            (t) async {
              final viewport = Size(width, 1100);
              size(t, viewport);
              final probe = _SettingsProbe(suite, light, locale);
              await t.pumpWidget(probe.app());
              await _frames(t);
              final pageState = t.state(find.byType(SettingsPage));
              final phases = [_layout(t, probe, viewport, 'ready')];
              await t.tap(_segment(1));
              await t.pump();
              await t.pump(const Duration(milliseconds: 60));
              expect(probe.requests, [NotificationSourceMode.importantOnly]);
              expect(probe.mode, NotificationSourceMode.importantOnly);
              phases.add(_layout(t, probe, viewport, 'source-pointer-60ms'));
              if (width == 540 && locale == const Locale('zh', 'CN')) {
                await _capture(
                  t,
                  probe.frame,
                  '${suite.name}-$palette-settings-cn-narrow',
                );
              }
              await _frames(t);
              if (width < 600) {
                await _pickSection(t, SettingsSection.generalData);
                await _pickSection(t, SettingsSection.notifications);
              } else {
                await t.tap(_section(SettingsSection.generalData));
                await _frames(t);
                expect(_key('3fh-content-generalData'), findsOneWidget);
                await t.tap(_section(SettingsSection.notifications));
                await t.pump();
                await t.pump(const Duration(milliseconds: 60));
                if (locale == const Locale('zh', 'CN')) {
                  await _capture(
                    t,
                    probe.frame,
                    '${suite.name}-$palette-settings-cn-wide',
                  );
                }
                await _frames(t);
              }
              phases.add(_layout(t, probe, viewport, 'section-returned'));
              expect(t.state(find.byType(SettingsPage)), same(pageState));
              expect(probe.requests, [NotificationSourceMode.importantOnly]);
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

      testWidgets('3fh actual compact rail196 $suite $palette 1.5x', (t) async {
        const viewport = Size(800, 1100);
        size(t, viewport);
        final probe = _SettingsProbe(suite, light, const Locale('zh', 'CN'));
        await t.pumpWidget(probe.app());
        await _frames(t);
        layouts.add({
          'suite': suite.name,
          'palette': palette,
          'width': 800,
          ..._layout(t, probe, viewport, 'compact-rail196'),
        });
        final rail = find.byType(SuiteSideNav);
        for (final section in visibleSettingsSections) {
          final copy = AppStrings.of(t.element(rail))
              .text(section.descriptionKey);
          expect(
            find.descendant(of: rail, matching: find.text(copy)),
            findsNothing,
          );
        }
        await t.pumpWidget(const SizedBox());
        await _frames(t);
      });

      testWidgets('3fh settings/source input pixels $suite $palette', (
        t,
      ) async {
        const viewport = Size(1100, 1100);
        size(t, viewport);
        final probe = _SettingsProbe(suite, light, const Locale('zh', 'CN'));
        await t.pumpWidget(probe.app());
        await _frames(t);
        final checks = <Map<String, Object?>>[];
        checks.add({
          'kind': 'source-touch',
          ...await _touch(t, probe, _segment(1), () {
            expect(probe.requests, isEmpty);
            expect(probe.mode, NotificationSourceMode.normal);
          }),
        });
        checks.add({
          'kind': 'source-pointer',
          ...await _pointerSelect(t, probe, _segment(1), _selector()),
        });
        expect(probe.mode, NotificationSourceMode.importantOnly);
        checks.add({
          'kind': 'rail-touch',
          ...await _touch(t, probe, _section(SettingsSection.generalData), () {
            expect(_key('3fh-content-notifications'), findsOneWidget);
            expect(_key('3fh-content-generalData'), findsNothing);
            expect(probe.requests, hasLength(1));
          }),
        });
        checks.add({
          'kind': 'rail-pointer',
          ...await _pointerSelect(
            t,
            probe,
            _section(SettingsSection.generalData),
            find.byType(SuiteSideNav),
          ),
        });
        expect(_key('3fh-content-generalData'), findsOneWidget);
        await _tabEnter(t, _section(SettingsSection.notifications));
        expect(_key('3fh-content-notifications'), findsOneWidget);
        checks.add({
          'kind': 'rail-keyboard',
          ...await _static(t, probe, find.byType(SuiteSideNav)),
        });
        await _tabEnter(t, _segment(0));
        expect(probe.mode, NotificationSourceMode.normal);
        checks.add({
          'kind': 'source-keyboard',
          ...await _static(t, probe, _selector()),
        });
        probe.update(() => probe.reduce = true);
        await t.pump();
        await t.pump();
        await t.tap(_segment(2));
        await t.pump();
        await t.pump();
        expect(probe.mode, NotificationSourceMode.doNotDisturb);
        checks.add({
          'kind': 'source-reduced-pointer',
          ...await _static(t, probe, _selector()),
        });
        await t.tap(_section(SettingsSection.generalData));
        await t.pump();
        await t.pump();
        checks.add({
          'kind': 'rail-reduced-pointer',
          ...await _static(t, probe, find.byType(SuiteSideNav)),
        });
        expect(probe.requests, [
          NotificationSourceMode.importantOnly,
          NotificationSourceMode.normal,
          NotificationSourceMode.doNotDisturb,
        ]);
        expect(t.takeException(), isNull);
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
