import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/app/runtime/sharing_status_monitor.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/chrome/overlay_source_labels.dart';
import 'package:starbridge_flutter/app/shell/chrome/shell_chrome_projection.dart';
import 'package:starbridge_flutter/app/shell/shell_layout_mode.dart';
import 'package:starbridge_flutter/app/shell/widgets/account_identity_button.dart';
import 'package:starbridge_flutter/app/shell/widgets/overlay_scene_selector.dart';
import 'package:starbridge_flutter/app/shell/widgets/sharing_status_indicator.dart';
import 'package:starbridge_flutter/app/shell/widgets/sharing_status_notice.dart';
import 'package:starbridge_flutter/app/shell/widgets/top_bar_actions.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../app/presence/manual_presence_test.dart' show state;
import '../../app/sharing_status_notice_test.dart' show NoticePrivacy;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

final _directory = const bool.hasEnvironment('INTERACTION_CAPTURE_DIR')
    ? const String.fromEnvironment('INTERACTION_CAPTURE_DIR')
    : visualOutputDir(
        'interaction_motion_batch3fk_20261017',
        legacySubdirectory: 'review',
      );
const _suites = [
  InteractionSuite.rail,
  InteractionSuite.scan,
  InteractionSuite.glow,
];
const _locales = [Locale('zh', 'CN'), Locale('zh', 'TW'), Locale('en', 'US')];
const _modes = <(double, ShellLayoutMode)>[
  (600, ShellLayoutMode.iconOnly),
  (1100, ShellLayoutMode.compact),
  (1360, ShellLayoutMode.wide),
];
Finder _key(String value) => find.byKey(
  value.startsWith('overlay-source-') ? ValueKey<Object>(value) : Key(value),
);

List<FeatureDescriptor> _descriptors() => [
  for (final item in <(String, String, StarBridgeIconSemantic)>[
    ('friends', 'navigation.friends', StarBridgeIconSemantic.friends),
    ('messages', 'navigation.messages', StarBridgeIconSemantic.messages),
    (
      'notifications',
      'navigation.notifications',
      StarBridgeIconSemantic.notifications,
    ),
  ])
    FeatureDescriptor(
      id: item.$1,
      route: '/visual-${item.$1}',
      labelKey: item.$2,
      descriptionKey: item.$2,
      icon: item.$3,
      navigationRegion: NavigationRegion.topBar,
      order: 0,
      buildDestination: (_) => const SizedBox(),
    ),
];

/// Component gallery only. The source selector retains the production
/// InMemoryShellChrome owner; sharing uses the existing test privacy port.
class _Probe {
  _Probe(this.suite, this.light, this.locale, this.mode) {
    presence = ManualPresenceController(source: presenceSource);
    privacy = LocalPrivacyController(port);
  }
  final InteractionSuite suite;
  final bool light;
  final Locale locale;
  final ShellLayoutMode mode;
  final frame = GlobalKey();
  final port = NoticePrivacy()..state = 'failed';
  final chrome = InMemoryShellChrome(
    initial: InMemoryShellChrome.connectedProjection.copyWith(
      accountLabel: 'Example Captain',
    ),
  );
  final presenceSource = ValueNotifier(state(PresenceVisibility.online));
  late final ManualPresenceController presence;
  late final LocalPrivacyController privacy;
  late final SharingStatusMonitor monitor;
  final descriptors = _descriptors();
  final commands = <String>[];
  bool reduce = false;
  bool disposed = false;
  late StateSetter update;

  Future<void> initialize() async {
    await privacy.refresh();
    await privacy.refreshPublication();
    monitor = SharingStatusMonitor(controller: privacy);
  }

  void _command(String name) =>
      commands.add('$name:${currentStarBridgeActivationSource.name}');

  Widget _body() => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Component gallery · ${mode.name}',
            key: const Key('3fk-gallery-label'),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<ShellChromeProjection>(
            valueListenable: chrome.projection,
            builder: (context, projection, _) => SizedBox(
              height: 72,
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OverlaySceneSelector(
                        projection: projection.overlay,
                        port: chrome,
                        mode: mode,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  TopBarActions(
                    descriptors: descriptors,
                    accountMenuDestinations: const [],
                    projection: projection,
                    mode: mode,
                    onSelect: (item) => _command(item.id),
                    onAccountLogin: () => _command('login'),
                    onAccountLogout: () => _command('logout'),
                    onAccountIssueAction: () => _command('issue'),
                    sharingIndicator: SharingStatusIndicator(
                      monitor: monitor,
                      compact: mode != ShellLayoutMode.wide,
                      onOpenSettings: () => _command('indicator'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: mode == ShellLayoutMode.wide ? 420 : 300,
              height: 44,
              child: AccountIdentityButton(
                avatar: const CircleAvatar(child: Text('A')),
                name: 'Example Captain · 星海远航',
                gameId: 'Captain-Example',
                compact: mode == ShellLayoutMode.iconOnly,
                presence: presence,
                onPressed: () => _command('identity'),
                onActivate: (_) => _command('identity'),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SharingStatusNotice(
            status: monitor,
            onOpenSettings: () => _command('settings'),
            onRetry: () => monitor.canRetry
                ? () {
                    _command('retry');
                    unawaited(monitor.retry());
                  }
                : null,
          ),
          const SizedBox(height: 24),
          const Text(
            'Gallery callbacks do not navigate, open native windows, or change a real account.',
          ),
        ],
      ),
    ),
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

Future<void> _frames(WidgetTester t, [int count = 4]) async {
  await t.pump();
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _mount(WidgetTester t, _Probe p, Size viewport) async {
  size(t, viewport);
  await p.initialize();
  addTearDown(() => _dispose(t, p));
  await t.pumpWidget(p.app());
  await _frames(t);
  expect(p.monitor.value, isNotNull);
}

Future<void> _dispose(WidgetTester t, _Probe p) async {
  if (p.disposed) return;
  p.disposed = true;
  p.monitor.dispose();
  p.privacy.dispose();
  p.presence.dispose();
  p.presenceSource.dispose();
  await t.runAsync(p.port.close);
}

Future<void> _unmount(WidgetTester t, [_Probe? p]) async {
  await t.pumpWidget(const SizedBox());
  if (p != null) await _dispose(t, p);
  await _frames(t, 2);
  expect(t.takeException(), isNull);
}

List<double> _rect(Rect r) => [r.left, r.top, r.width, r.height];

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

Finder _target(WidgetTester t, Finder owner) {
  final widget = t.widget(owner);
  if (widget is SuitePressable || widget is IconButton) {
    return owner;
  }
  final suite = find.descendant(
    of: owner,
    matching: find.byType(SuitePressable),
  );
  if (suite.evaluate().isNotEmpty) {
    return suite.first;
  }
  return find.descendant(of: owner, matching: find.byType(IconButton)).first;
}

Future<void> _tab(WidgetTester t, Finder owner) async {
  expect(owner, findsOneWidget);
  await t.ensureVisible(owner);
  final target = _target(t, owner);
  final widget = t.widget(target);
  final node = widget is SuitePressable
      ? widget.focusNode!
      : (widget as IconButton).focusNode!;
  for (var i = 0; i < 80 && !node.hasPrimaryFocus; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
  }
  expect(node.hasPrimaryFocus, isTrue);
}

Future<void> _keyboard(WidgetTester t, Finder owner) async {
  await _tab(t, owner);
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pump();
  await t.pump();
}

String _signature(_Probe p) => jsonEncode({
  'commands': p.commands,
  'preferred': p.chrome.projection.value.overlay.preferredSceneId,
  'actual': p.chrome.projection.value.overlay.actualSceneId,
  'writes': p.port.writes,
  'apply': p.port.actions.where((a) => a != 'status').toList(),
});

Future<Map<String, Object?>> _touchCancel(
  WidgetTester t,
  _Probe p,
  Finder owner,
) async {
  final target = _target(t, owner);
  await t.ensureVisible(target);
  await _frames(t);
  final rect = t.getRect(target);
  final before = await _pixels(t, p, rect);
  await t.pump(const Duration(milliseconds: 180));
  expect(_diff(before, await _pixels(t, p, rect)), 0);
  final signature = _signature(p);
  final gesture = await t.startGesture(
    rect.center,
    kind: ui.PointerDeviceKind.touch,
  );
  var changed = 0;
  try {
    await t.pump(const Duration(milliseconds: 150));
    await t.pump(const Duration(milliseconds: 30));
    expect(t.getRect(target), rect);
    changed = _diff(before, await _pixels(t, p, rect));
    expect(
      changed,
      greaterThan(0),
      reason: '$owner: actual held press visibly changes the local face',
    );
    expect(_signature(p), signature);
  } finally {
    await gesture.cancel();
    await _frames(t);
  }
  expect(
    _signature(p),
    signature,
    reason:
        'Cancelled input must not issue navigation/publication/scene commands',
  );
  return {'rect': _rect(rect), 'idlePixels': 0, 'pressPixels': changed};
}

Future<Map<String, Object?>> _stable(
  WidgetTester t,
  _Probe p,
  Finder owner,
) async {
  final rect = t.getRect(owner);
  final before = await _pixels(t, p, rect);
  await t.pump(const Duration(milliseconds: 600));
  expect(t.getRect(owner), rect);
  final changed = _diff(before, await _pixels(t, p, rect));
  expect(changed, 0);
  return {'rect': _rect(rect), 'elapsedMs': 600, 'changedPixels': changed};
}

Future<Map<String, Object?>> _nativeRelease(
  WidgetTester t,
  _Probe p,
  Finder owner,
) async {
  final target = _target(t, owner);
  await t.ensureVisible(target);
  await _frames(t);
  final rect = t.getRect(target);
  final signature = _signature(p);
  final cancelled = await t.startGesture(
    rect.center,
    kind: ui.PointerDeviceKind.touch,
  );
  await t.pump(const Duration(milliseconds: 180));
  expect(t.getRect(target), rect);
  expect(_signature(p), signature);
  await cancelled.cancel();
  await _frames(t);
  expect(_signature(p), signature);

  final before = await _pixels(t, p, rect);
  await t.pump(const Duration(milliseconds: 180));
  expect(_diff(before, await _pixels(t, p, rect)), 0);
  final click = await t.startGesture(
    rect.center,
    kind: ui.PointerDeviceKind.touch,
  );
  await click.up();
  await t.pump();
  await t.pump(const Duration(milliseconds: 30));
  final changed = _diff(before, await _pixels(t, p, rect));
  expect(
    changed,
    greaterThan(0),
    reason: 'Native icon recipe plays at activation, not while held',
  );
  expect(t.getRect(target), rect);
  expect(p.commands, ['friends:pointer']);
  expect(p.port.writes, 0);
  await _frames(t, 12);
  return {
    'control': 'top-action-friends',
    'kind': 'release-feedback',
    'rect': _rect(rect),
    'idlePixels': 0,
    'releasePixels': changed,
    'cancelCommands': 0,
  };
}

void _layout(WidgetTester t, Size viewport) {
  expect(t.takeException(), isNull);
  for (final key in [
    'overlay-scene-selector',
    'top-action-cluster',
    'account-identity-command',
    'sharing-status-notice',
  ]) {
    final owner = _key(key);
    expect(owner, findsOneWidget);
    final rect = t.getRect(owner);
    expect(rect.left, greaterThanOrEqualTo(-.01));
    expect(rect.right, lessThanOrEqualTo(viewport.width + .01));
    expect(rect.top, greaterThanOrEqualTo(-.01));
    expect(rect.bottom, lessThanOrEqualTo(viewport.height + .01));
  }
  // The gallery's failed publication is unconfirmed: no badge (2026-10-22).
  expect(_key('sharing-status-indicator'), findsNothing);
}

void _menuBounds(WidgetTester t, Size viewport) {
  for (final id in ['default', 'room', 'operation']) {
    final rect = t.getRect(_key('overlay-source-$id'));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(viewport.width));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(viewport.height));
  }
}

Widget _sourceTextApp(InteractionSuite suite, double textScale, Widget child) {
  final base = scopedApp(
    SizedBox(
      height: 72,
      width: 680,
      child: Align(alignment: Alignment.centerLeft, child: child),
    ),
    suite,
  ) as MaterialApp;
  return MaterialApp(
    theme: base.theme,
    themeAnimationDuration: Duration.zero,
    locale: const Locale('zh', 'CN'),
    supportedLocales: base.supportedLocales,
    localizationsDelegates: base.localizationsDelegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: base.builder!(context, child),
    ),
    home: base.home,
  );
}

void main() {
  setUpAll(loadFonts);
  final evidence = <Map<String, Object?>>[];
  tearDownAll(() async {
    await Directory(_directory).create(recursive: true);
    await File('$_directory/visual-summary.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scope': 'Component gallery only: actual source selector, top actions, identity, sharing notice/indicator with existing in-memory owners. Not full App/Shell, native windows, account/Host or device acceptance.',
        'checks': evidence,
      }),
    );
  });
  for (final suite in [InteractionSuite.standard, ..._suites]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        '3fk source fixed chrome retains full-size primary $suite text$scale',
        (t) async {
          size(t, const Size(900, 600));
          final chrome = InMemoryShellChrome(
            initial: InMemoryShellChrome.connectedProjection,
          );
          final projection = chrome.projection.value.overlay;
          await t.pumpWidget(
            _sourceTextApp(
              suite,
              scale,
              OverlaySceneSelector(
                projection: projection,
                port: chrome,
                mode: ShellLayoutMode.wide,
              ),
            ),
          );
          await _frames(t, 2);
          expect(
            t.takeException(),
            isNull,
            reason:
                'No layout errors may be suppressed in the formal regression',
          );
          final selector = _key('overlay-scene-selector');
          final context = t.element(find.byType(OverlaySceneSelector));
          final strings = AppStrings.of(context);
          final label = overlaySourceLabel(projection, strings);
          final subtitle = strings.text('top.overlayScene');
          final primary = find.descendant(
            of: selector,
            matching: find.text(label),
          );
          expect(primary, findsOneWidget);
          final text = t.widget<Text>(primary);
          final expectedFont = Theme.of(context)
              .textTheme
              .labelLarge!
              .fontSize!;
          expect(text.style!.fontSize, expectedFont);
          expect(
            MediaQuery.textScalerOf(t.element(primary)).scale(expectedFont),
            closeTo(expectedFont * scale, .0001),
          );
          expect(
            find.descendant(of: selector, matching: find.byType(FittedBox)),
            findsNothing,
          );
          expect(
            find.descendant(of: selector, matching: find.text(subtitle)),
            scale == 1 ? findsOneWidget : findsNothing,
          );
          final tooltip = t.widget<StarBridgeTooltip>(
            find.byType(StarBridgeTooltip),
          );
          expect(
            tooltip.message,
            '$label\n${strings.text(overlaySourceHint(projection))}',
          );
          expect(tooltip.consumeEscape, isFalse);
          final action = t.widget<StarBridgeActionButton>(
            find.byType(StarBridgeActionButton),
          );
          expect(action.nativeStyle!.minimumSize!.resolve({})!.height, 40);
          expect(action.nativeStyle!.maximumSize!.resolve({})!.height, 40);
          final face = suite == InteractionSuite.standard
              ? find
                    .descendant(of: selector, matching: find.byType(Material))
                    .first
              : selector;
          expect(
            t.getSize(face).height,
            40,
            reason: 'Preserve the painted chrome face; SDK tap-target padding is not resized',
          );
          evidence.add({
            'kind': 'source-text',
            'suite': suite.name,
            'textScale': scale,
            'primaryFontSize': expectedFont,
            'faceHeight': t.getSize(face).height,
            'subtitle': scale == 1,
          });
          await _unmount(t);
        },
      );
    }
  }
  for (final suite in _suites) {
    for (final light in [false, true]) {
      final palette = light ? 'light' : 'dark';
      for (final locale in _locales) {
        for (final (width, mode) in _modes) {
          testWidgets('3fk gallery $suite $palette $locale $mode $width 1.5x', (
            t,
          ) async {
            expect(ShellLayoutResolver.resolve(width), mode);
            final p = _Probe(suite, light, locale, mode);
            final viewport = Size(width, 1000);
            await _mount(t, p, viewport);
            _layout(t, viewport);
            final triggerRect = t.getRect(_key('overlay-scene-selector'));
            if (mode != ShellLayoutMode.wide) {
              expect(triggerRect.width, triggerRect.height);
            }
            if (locale.countryCode == 'CN' &&
                mode == ShellLayoutMode.iconOnly) {
              await _capture(t, p, '${suite.name}-$palette-iconOnly');
            }
            await t.tap(_key('overlay-scene-selector'));
            await _frames(t);
            expect(_key('overlay-source-operation'), findsOneWidget);
            _menuBounds(t, viewport);
            _layout(t, viewport);
            if (locale.countryCode == 'CN' && mode == ShellLayoutMode.wide) {
              await _capture(t, p, '${suite.name}-$palette-wide-menu');
            }
            await t.tap(_key('overlay-source-operation'));
            await _frames(t);
            expect(
              p.chrome.projection.value.overlay.preferredSceneId,
              'operation',
            );
            expect(p.chrome.projection.value.overlay.actualSceneId, 'default');
            expect(p.commands, isEmpty);
            expect(p.port.writes, 0);
            evidence.add({
              'kind': 'layout',
              'suite': suite.name,
              'palette': palette,
              'locale': locale.toLanguageTag(),
              'mode': mode.name,
              'width': width,
              'selectorRect': _rect(triggerRect),
            });
            await _unmount(t, p);
          });
        }
      }
      testWidgets('3fk gallery real input $suite $palette', (t) async {
        final p = _Probe(
          suite,
          light,
          const Locale('zh', 'CN'),
          ShellLayoutMode.wide,
        );
        await _mount(t, p, const Size(1360, 1000));
        final checks = <Map<String, Object?>>[];
        for (final id in [
          'overlay-scene-selector',
          'account-identity-command',
          'sharing-status-settings',
        ]) {
          checks.add({'control': id, ...await _touchCancel(t, p, _key(id))});
        }
        checks.add(await _nativeRelease(t, p, _key('top-action-friends')));
        await t.tap(_key('overlay-scene-selector'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 30));
        final surface = find.byType(SuiteSurfaceTransition);
        expect(surface, findsOneWidget);
        final animation = t.widget<SuiteSurfaceTransition>(surface).animation;
        expect(animation.value, lessThan(1));
        p.update(() => p.reduce = true);
        await t.pump();
        await t.pump();
        expect(t.widget<SuiteSurfaceTransition>(surface).animation.value, 1);
        checks.add({
          'kind': 'menu-live-reduced',
          ...await _stable(t, p, surface),
        });
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        expect(_key('overlay-source-operation'), findsNothing);
        p.update(() => p.reduce = false);
        await t.pump();
        await t.pump();

        await _keyboard(t, _key('overlay-scene-selector'));
        expect(_key('overlay-source-operation'), findsOneWidget);
        expect(
          t
              .widget<SuiteSurfaceTransition>(
                find.byType(SuiteSurfaceTransition),
              )
              .animation
              .value,
          1,
        );
        checks.add({
          'kind': 'menu-keyboard',
          ...await _stable(t, p, find.byType(SuiteSurfaceTransition)),
        });
        await _keyboard(t, _key('overlay-source-operation'));
        expect(p.chrome.projection.value.overlay.preferredSceneId, 'operation');
        expect(p.chrome.projection.value.overlay.actualSceneId, 'default');
        expect(_key('overlay-source-operation'), findsNothing);
        await _keyboard(t, _key('account-identity-command'));
        expect(p.commands, ['friends:pointer', 'identity:keyboard']);
        checks.add({
          'kind': 'identity-keyboard',
          ...await _stable(t, p, _key('account-identity-command')),
        });
        await _keyboard(t, _key('top-action-friends'));
        expect(p.commands.last, 'friends:keyboard');
        checks.add({
          'kind': 'native-icon-keyboard',
          ...await _stable(t, p, _key('top-action-friends')),
        });
        p.update(() => p.reduce = true);
        await t.pump();
        await t.pump();
        await t.tap(_key('sharing-status-settings'));
        await t.pump();
        await t.pump();
        expect(p.commands.last, 'settings:pointer');
        checks.add({
          'kind': 'settings-reduced-pointer',
          ...await _stable(t, p, _key('sharing-status-settings')),
        });
        expect(p.port.writes, 0);
        expect(p.port.actions.every((a) => a == 'status'), isTrue);
        evidence.add({
          'kind': 'input',
          'suite': suite.name,
          'palette': palette,
          'checks': checks,
        });
        await _unmount(t, p);
      });
    }
  }
}
