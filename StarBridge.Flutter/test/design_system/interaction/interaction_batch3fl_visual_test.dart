import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/shell_layout_mode.dart';
import 'package:starbridge_flutter/app/shell/shell_navigation_controller.dart';
import 'package:starbridge_flutter/app/shell/widgets/shell_top_bar.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_page_motion.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

final _directory = const bool.hasEnvironment('INTERACTION_CAPTURE_DIR')
    ? const String.fromEnvironment('INTERACTION_CAPTURE_DIR')
    : visualOutputDir(
        'interaction_motion_batch3fl_20261017',
        legacySubdirectory: 'review',
      );
const _suites = [
  InteractionSuite.rail,
  InteractionSuite.scan,
  InteractionSuite.glow,
];
const _locales = [Locale('zh', 'CN'), Locale('zh', 'TW'), Locale('en', 'US')];
Finder _key(String key) => find.byKey(Key(key));
Finder get _title => _key('shell-title-switcher');
Finder get _header => _key('3fl-header');

List<FeatureDescriptor> _destinations() => [
  for (final id in ['home', 'hangar', 'settings', 'friends'])
    FeatureDescriptor(
      id: id,
      route: '/3fl-$id',
      labelKey: 'navigation.$id',
      descriptionKey: 'navigation.$id.description',
      icon: StarBridgeIconSemantic.scene,
      navigationRegion: NavigationRegion.primary,
      order: 0,
      buildDestination: (_) => const SizedBox(),
    ),
];

/// A real ShellTopBar in an isolated gallery, not an App/Shell substitute.
/// Only fixture controls select destinations; no native window is opened.
class _Probe {
  _Probe(this.suite, this.light, this.locale, this.width) {
    navigation = ShellNavigationController(initial: destinations.first);
  }
  InteractionSuite suite;
  final bool light;
  final Locale locale;
  final double width;
  final frame = GlobalKey();
  final destinations = _destinations();
  late final ShellNavigationController navigation;
  final window = InMemoryWindowChrome();
  final chrome = InMemoryShellChrome(
    initial: InMemoryShellChrome.connectedProjection.copyWith(
      accountLabel: 'Example Captain',
    ),
  );
  final commands = <String>[];
  bool reduce = false;
  late StateSetter update;

  Widget _body() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListenableBuilder(
        listenable: navigation,
        builder: (context, _) => ShellTopBar(
          key: const Key('3fl-header'),
          selected: navigation.selected,
          interaction: navigation.lastInteraction,
          topBarDestinations: const [],
          accountMenuDestinations: const [],
          projection: chrome.projection.value,
          shellChrome: chrome,
          mode: ShellLayoutResolver.resolve(width),
          windowChrome: window,
          onSelect: (item) => commands.add(item.id),
          onAccountLogin: () => commands.add('login'),
          onAccountLogout: () => commands.add('logout'),
          onAccountIssueAction: () => commands.add('issue'),
        ),
      ),
      const SizedBox(height: 24),
      // Isolate fixture button effects from the title's pixel sample. A glow
      // ring from a previous pointer action must not masquerade as title motion.
      ClipRect(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (var i = 0; i < destinations.length; i++)
                StarBridgeActionButton(
                  controlKey: Key('3fl-choose-$i'),
                  onActivate: (source) => navigation.select(
                    destinations[i],
                    interaction: source == InteractionSource.keyboard
                        ? NavigationInteraction.keyboard
                        : NavigationInteraction.pointer,
                  ),
                  child: Text('Change ${String.fromCharCode(65 + i)}'),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Component gallery: fixture inputs drive the original navigation owner. No destination content or native window is started.',
        ),
      ),
    ],
  );

  Widget app() => StatefulBuilder(
    builder: (_, setter) {
      update = setter;
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
          themeAnimationDuration: Duration.zero,
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

Future<void> _frames(WidgetTester t, [int count = 5]) async {
  await t.pump();
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _mount(WidgetTester t, _Probe p) async {
  size(t, Size(p.width, 400));
  addTearDown(p.navigation.dispose);
  await t.pumpWidget(p.app());
  await _frames(t);
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await _frames(t, 2);
  expect(t.takeException(), isNull);
}

StarBridgePageTransition _transition(WidgetTester t) =>
    t.widget<StarBridgePageTransition>(
      find.descendant(
        of: _title,
        matching: find.byType(StarBridgePageTransition),
      ),
    );

void _settled(WidgetTester t) {
  final animation = _transition(t).animation;
  expect(animation.value, 1);
  expect(animation.status, AnimationStatus.completed);
  expect(animation, isA<AnimationController>());
  expect(
    (animation as AnimationController).isAnimating,
    isFalse,
    reason: 'The actual title controller has no residual ticker',
  );
}

void _noOldTitle(WidgetTester t, _Probe p, FeatureDescriptor old) {
  final strings = AppStrings.of(t.element(_header));
  for (final key in [old.labelKey, old.descriptionKey]) {
    final text = strings.text(key);
    expect(
      find.descendant(of: _header, matching: find.text(text)),
      findsNothing,
    );
    expect(
      find.bySemanticsLabel(RegExp(RegExp.escape(text))),
      findsNothing,
      reason: 'Retired title is not left in the accessibility tree',
    );
  }
}

void _currentTitle(WidgetTester t, _Probe p) {
  final strings = AppStrings.of(t.element(_header));
  for (final key in [
    p.navigation.selected.labelKey,
    p.navigation.selected.descriptionKey,
  ]) {
    final text = strings.text(key);
    expect(
      find.descendant(of: _header, matching: find.text(text)),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp(RegExp.escape(text))), findsWidgets);
  }
}

Future<List<int>> _pixels(WidgetTester t, _Probe p, Rect globalRect) async {
  final boundary =
      p.frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final rect = globalRect.shift(-boundary.localToGlobal(Offset.zero));
  return (await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
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

int _diff(List<int> a, List<int> b) {
  expect(b.length, a.length);
  var changed = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      changed++;
    }
  }
  return changed;
}

List<double> _rect(Rect r) => [r.left, r.top, r.width, r.height];

Future<void> _capture(WidgetTester t, _Probe p, String name) async {
  final boundary =
      p.frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(_directory).create(recursive: true);
      await File('$_directory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void _layout(WidgetTester t, _Probe p) {
  expect(t.takeException(), isNull);
  final header = t.getRect(_header);
  expect(header.left, 0);
  expect(header.width, p.width);
  expect(header.height, 64);
  final title = t.getRect(_title);
  expect(title.left, greaterThanOrEqualTo(header.left));
  expect(title.right, lessThanOrEqualTo(header.right));
  expect(title.top, greaterThanOrEqualTo(header.top));
  expect(title.bottom, lessThanOrEqualTo(header.bottom));
}

Future<void> _keyboard(WidgetTester t, int index) async {
  final target = _key('3fl-choose-$index');
  final node = t.widget<SuitePressable>(target).focusNode!;
  for (var i = 0; i < 80 && !node.hasPrimaryFocus; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
  }
  expect(node.hasPrimaryFocus, isTrue);
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pump();
}

Future<Map<String, Object?>> _stable(
  WidgetTester t,
  _Probe p,
  String kind,
) async {
  final header = t.getRect(_header);
  final rect = t.getRect(_title);
  final before = await _pixels(t, p, rect);
  await t.pump(const Duration(milliseconds: 600));
  await t.pump();
  expect(t.getRect(_header), header);
  expect(t.getRect(_title), rect);
  final changed = _diff(before, await _pixels(t, p, rect));
  expect(
    changed,
    0,
    reason: '$kind title remains static over the same 600ms interval',
  );
  _settled(t);
  return {
    'kind': kind,
    'rect': _rect(rect),
    'elapsedMs': 600,
    'changedPixels': changed,
  };
}

void main() {
  setUpAll(loadFonts);
  final evidence = <Map<String, Object?>>[];
  tearDownAll(() async {
    await Directory(_directory).create(recursive: true);
    await File('$_directory/visual-summary.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scope': 'Actual ShellTopBar component gallery, original ShellNavigationController and in-memory chrome/window ports. Not full App/Shell routes, composition source wiring, native window movement or device acceptance.',
        'checks': evidence,
      }),
    );
  });
  for (final suite in _suites) {
    for (final light in [false, true]) {
      final palette = light ? 'light' : 'dark';
      for (final locale in _locales) {
        for (final width in [900.0, 1440.0]) {
          testWidgets('3fl title layout $suite $palette $locale $width 1.5x', (
            t,
          ) async {
            final p = _Probe(suite, light, locale, width);
            await _mount(t, p);
            _layout(t, p);
            final header = t.getRect(_header);
            await t.tap(_key('3fl-choose-1'));
            await t.pump();
            await t.pump(const Duration(milliseconds: 60));
            expect(p.navigation.lastInteraction, NavigationInteraction.pointer);
            expect(_transition(t).animation.value, lessThan(1));
            final partialTitle = t.getRect(_title);
            _layout(t, p);
            if (locale.countryCode == 'CN' && width == 1440) {
              await _capture(t, p, '${suite.name}-$palette-title-partial');
            }
            await _frames(t);
            _settled(t);
            expect(t.getRect(_header), header);
            expect(t.getRect(_title), partialTitle);
            _layout(t, p);
            if (locale.countryCode == 'CN' && width == 1440) {
              await _capture(t, p, '${suite.name}-$palette-title-settled');
            }
            expect(p.window.commands, isEmpty);
            expect(p.commands, isEmpty);
            evidence.add({
              'kind': 'layout',
              'suite': suite.name,
              'palette': palette,
              'locale': locale.toLanguageTag(),
              'width': width,
              'mode': ShellLayoutResolver.resolve(width).name,
              'header': _rect(header),
              'title': _rect(partialTitle),
            });
            await _unmount(t);
          });
        }
      }
      testWidgets('3fl title input pixels $suite $palette', (t) async {
        final p = _Probe(suite, light, const Locale('zh', 'CN'), 1440);
        final semantics = t.ensureSemantics();
        await _mount(t, p);
        final header = t.getRect(_header);
        final checks = <Map<String, Object?>>[];
        await t.tap(_key('3fl-choose-1'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 60));
        expect(_transition(t).animation.value, inExclusiveRange(0, 1));
        _noOldTitle(t, p, p.destinations.first);
        final rect = t.getRect(_title);
        final partial = await _pixels(t, p, rect);
        await _frames(t);
        _settled(t);
        final changed = _diff(partial, await _pixels(t, p, rect));
        expect(
          changed,
          greaterThan(0),
          reason: 'The actual pointer title transition is visibly different from its final raster',
        );
        expect(t.getRect(_header), header);
        expect(t.getRect(_title), rect);
        checks.add({
          'kind': 'pointer',
          'rect': _rect(rect),
          'sampleMs': 60,
          'partialToFinalPixels': changed,
        });

        await _keyboard(t, 2);
        expect(p.navigation.lastInteraction, NavigationInteraction.keyboard);
        _settled(t);
        _currentTitle(t, p);
        _noOldTitle(t, p, p.destinations[1]);
        checks.add(await _stable(t, p, 'keyboard'));
        await t.tap(_key('3fl-choose-2'));
        await t.pump();
        await t.pump();
        _settled(t);
        checks.add(await _stable(t, p, 'same-current'));

        await t.tap(_key('3fl-choose-3'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 30));
        expect(_transition(t).animation.value, lessThan(1));
        p.update(() => p.reduce = true);
        await t.pump();
        await t.pump();
        _settled(t);
        _noOldTitle(t, p, p.destinations[2]);
        checks.add(await _stable(t, p, 'live-reduced'));
        p.update(() => p.reduce = false);
        await t.pump();
        await t.pump();
        await t.tap(_key('3fl-choose-0'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 30));
        expect(_transition(t).animation.value, lessThan(1));
        p.update(
          () =>
              p.suite = _suites[(_suites.indexOf(suite) + 1) % _suites.length],
        );
        await t.pump();
        await t.pump();
        _settled(t);
        _noOldTitle(t, p, p.destinations[3]);
        checks.add(await _stable(t, p, 'suite-change'));

        final dragTarget = find
            .ancestor(of: _title, matching: find.byType(GestureDetector))
            .first;
        await t.drag(dragTarget, const Offset(28, 0));
        await _frames(t);
        expect(p.window.commands, ['beginDrag']);
        final center = t.getCenter(dragTarget);
        await t.tapAt(center);
        await t.pump(const Duration(milliseconds: 70));
        await t.tapAt(center);
        await _frames(t);
        expect(p.window.commands, ['beginDrag', 'toggleMaximize']);
        expect(p.commands, isEmpty);
        _layout(t, p);
        evidence.add({
          'kind': 'input',
          'suite': suite.name,
          'palette': palette,
          'checks': checks,
          'windowCommands': p.window.commands,
        });
        await _unmount(t);
        semantics.dispose();
      });
    }
  }
}
