import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/settings/runtime_status_controller.dart';
import 'package:starbridge_flutter/features/settings/runtime_status_dialog.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3ap_flows_test.dart'
    show Avatar, actorTarget, openAvatar;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch3fl_menu_test.dart' show menuFocus;
import 'interaction_batch3i_test.dart' show scopedApp;

final _directory = const bool.hasEnvironment('INTERACTION_CAPTURE_DIR')
    ? const String.fromEnvironment('INTERACTION_CAPTURE_DIR')
    : visualOutputDir(
        'interaction_motion_batch3fn_20261017',
        legacySubdirectory: 'review',
      );
const _suites = [
  InteractionSuite.rail,
  InteractionSuite.scan,
  InteractionSuite.glow,
];
const _locales = [Locale('zh', 'CN'), Locale('zh', 'TW'), Locale('en', 'US')];
Finder _key(String key) => find.byKey(Key(key));
Finder get _profile =>
    find.byKey(const ValueKey<Object>('avatar-view-profile'));
const _facts = RuntimeInstallationFacts(
  dataDirectory: r'C:\Fixture\Data',
  imageCacheDirectory: r'C:\Fixture\Data\Images',
  imageCacheExists: false,
  applicationVersion: '0.1.0+1',
);

/// Original runtime controller, with the same three read-closure seam used by
/// runtime_status_test. No transport, filesystem or second settings store.
class _RuntimeReads {
  _RuntimeReads() {
    controller = RuntimeStatusController(
      readInstallation: () {
        reads++;
        return gate.future;
      },
      readOverlay: () async {
        if (rejectOthers) {
          throw StateError('fixture overlay unavailable');
        }
        return const RuntimeOverlayFacts(
          windowState: 'closed',
          hotkeyBinding: 'Alt+F10',
          hotkeyState: 'conflict',
        );
      },
      readStartup: () async {
        if (rejectOthers) {
          throw StateError('fixture startup unavailable');
        }
        return null;
      },
    );
    gates.add(gate);
  }
  late final RuntimeStatusController controller;
  Completer<RuntimeInstallationFacts?> gate = Completer();
  final gates = <Completer<RuntimeInstallationFacts?>>[];
  bool rejectOthers = false;
  int reads = 0;
  void prepare({bool failAll = false}) {
    gate = Completer<RuntimeInstallationFacts?>();
    gates.add(gate);
    rejectOthers = failAll;
  }

  void finish() {
    for (final item in gates) {
      if (!item.isCompleted) {
        item.complete(null);
      }
    }
  }
}

class _Probe {
  _Probe(this.suite, this.light, this.locale);
  final InteractionSuite suite;
  final bool light;
  final Locale locale;
  final frame = GlobalKey();
  final runtime = _RuntimeReads();
  final avatar = Avatar();
  final navigation = UserPageNavigation();
  final avatarGates = <Completer<FriendRow?>>[];
  final profileSources = <InteractionSource>[];
  bool reduce = false, showAvatar = false, disposed = false;
  late StateSetter update;

  Completer<FriendRow?> holdAvatar() {
    final gate = Completer<FriendRow?>();
    avatar.held = gate;
    avatarGates.add(gate);
    return gate;
  }

  Widget _body() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Component gallery · read-only runtime and user menu'),
        const SizedBox(height: 24),
        if (showAvatar)
          UserInteractionScope(
            navigation: navigation,
            port: avatar,
            messagePage: null,
            child: UserAvatarMenu(
              name: 'Original peer',
              target: actorTarget,
              onViewProfile: () =>
                  profileSources.add(currentStarBridgeActivationSource),
              child: const SizedBox.square(
                dimension: 48,
                child: CircleAvatar(child: Text('P')),
              ),
            ),
          )
        else
          Builder(
            builder: (context) => StarBridgeActionButton(
              controlKey: const Key('3fn-runtime-open'),
              onActivate: (_) => unawaited(
                showRuntimeStatusDialog(context, runtime.controller),
              ),
              child: const Text('Open runtime'),
            ),
          ),
      ],
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

Future<void> _frames(WidgetTester t, [int count = 6]) async {
  await t.pump();
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _mount(WidgetTester t, _Probe p, double width) async {
  size(t, Size(width, 1000));
  addTearDown(() => _dispose(t, p));
  await t.pumpWidget(p.app());
  await _frames(t, 2);
}

Future<void> _dispose(WidgetTester t, _Probe p) async {
  if (p.disposed) {
    return;
  }
  p.disposed = true;
  await t.pumpWidget(const SizedBox());
  p.runtime.finish();
  for (final gate in p.avatarGates) {
    if (!gate.isCompleted) {
      gate.complete(null);
    }
  }
  await t.pump();
  await t.pump();
  p.runtime.controller.dispose();
  await t.runAsync(p.avatar.changes.close);
}

Future<void> _unmount(WidgetTester t, _Probe p) async {
  await _dispose(t, p);
  await _frames(t, 2);
  expect(t.takeException(), isNull);
}

Finder _target(WidgetTester t, Finder owner) =>
    t.widget(owner) is SuitePressable
    ? owner
    : find.descendant(of: owner, matching: find.byType(SuitePressable)).first;

Future<void> _keyboard(WidgetTester t, Finder owner) async {
  final target = _target(t, owner);
  await t.ensureVisible(target);
  final node = menuFocus(t, target);
  for (var i = 0; i < 100 && !node.hasPrimaryFocus; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
  }
  expect(node.hasPrimaryFocus, isTrue);
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pump();
  await t.pump();
}

Future<void> _reader(WidgetTester t, String label) async {
  final nodes = exposedNodes(t).where((node) {
    final data = node.getSemanticsData();
    return data.flagsCollection.isButton &&
        data.label.contains(label) &&
        data.hasAction(ui.SemanticsAction.tap);
  }).toList();
  expect(nodes, hasLength(1));
  t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
    nodes.single.id,
    ui.SemanticsAction.tap,
  );
  await t.pump();
  await t.pump();
}

Future<void> _openRuntime(WidgetTester t, _Probe p, String source) async {
  if (source == 'pointer') {
    await t.tap(_key('3fn-runtime-open'));
  } else if (source == 'keyboard') {
    await _keyboard(t, _key('3fn-runtime-open'));
  } else {
    await _reader(t, 'Open runtime');
  }
  // Finish only the surface entrance; the owner's held read stays pending.
  await _frames(t);
  expect(find.byType(RuntimeStatusDialog), findsOneWidget);
  expect(p.runtime.controller.value.busy, isTrue);
  expect(p.runtime.gate.isCompleted, isFalse);
}

Future<void> _closeRuntime(WidgetTester t) async {
  await t.tap(_key('runtime-status-close'));
  await _frames(t);
  expect(find.byType(RuntimeStatusDialog), findsNothing);
}

Future<void> _avatarStage(WidgetTester t, _Probe p) async {
  p.update(() => p.showAvatar = true);
  await _frames(t, 2);
}

Future<void> _openAvatar(WidgetTester t, String source) async {
  if (source == 'keyboard') {
    await _keyboard(t, _key('user-avatar-menu-anchor'));
  } else {
    // The reused helper's pointer/reader paths perform actual input; its
    // requestFocus-based keyboard branch is deliberately not used here.
    await openAvatar(t, source, settle: false);
  }
  await _frames(t);
  expect(_profile, findsOneWidget);
  expect(t.widget<SuitePressable>(_profile).onActivate, isNotNull);
}

Future<void> _escapeAvatar(WidgetTester t) async {
  await t.sendKeyEvent(LogicalKeyboardKey.escape);
  await t.pump();
  await t.pump();
  expect(_profile, findsNothing);
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

void _bounds(WidgetTester t, Finder target, double width) {
  expect(t.takeException(), isNull);
  final rect = t.getRect(target);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(width));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(1000));
}

Future<Map<String, Object?>> _waiting(
  WidgetTester t,
  _Probe p,
  String kind, {
  required bool animated,
}) async {
  final activity = find.byType(SocialReadActivity);
  expect(activity, findsOneWidget);
  await t.ensureVisible(activity);
  await t.pump();
  expect(t.widget<SocialReadActivity>(activity).height, 4);
  final rect = t.getRect(activity);
  expect(
    rect.height,
    4,
    reason: 'Keep the original themed linear progress slot',
  );
  await t.pump(const Duration(milliseconds: 80));
  final before = await _pixels(t, p, rect);
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  expect(t.getRect(activity), rect);
  final changed = _diff(before, await _pixels(t, p, rect));
  expect(changed, animated ? greaterThan(0) : equals(0));
  return {
    'kind': kind,
    'rect': _rect(rect),
    'elapsedMs': 600,
    'animated': animated,
    'changedPixels': changed,
  };
}

String _signature(_Probe p) => jsonEncode({
  'runtimeReads': p.runtime.reads,
  'socialReads': p.avatar.targets.length,
  'socialWrites': p.avatar.commands.length,
  'profileOpens': p.profileSources.length,
});

Future<Map<String, Object?>> _touchCancel(
  WidgetTester t,
  _Probe p,
  Finder owner,
) async {
  final target = _target(t, owner);
  await t.ensureVisible(target);
  await _frames(t, 2);
  final rect = t.getRect(target);
  final before = await _pixels(t, p, rect);
  await t.pump(const Duration(milliseconds: 180));
  expect(
    _diff(before, await _pixels(t, p, rect)),
    0,
    reason: 'Stable idle button pixels exclude unrelated progress animation',
  );
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
    expect(changed, greaterThan(0));
    expect(_signature(p), signature);
  } finally {
    await gesture.cancel();
    await _frames(t, 3);
  }
  expect(
    _signature(p),
    signature,
    reason: 'Cancelled button input cannot start reads, profile opens or social writes',
  );
  return {
    'rect': _rect(rect),
    'idlePixels': 0,
    'pressPixels': changed,
    'cancelCommands': 0,
  };
}

void _avatarSlot(WidgetTester t) {
  final activity = find.byType(SocialReadActivity);
  final padding = find.ancestor(
    of: activity,
    matching: find.byWidgetPredicate(
      (w) => w is Padding && w.padding == const EdgeInsets.only(bottom: 8),
    ),
  );
  expect(
    padding,
    findsOneWidget,
    reason: 'Avatar header retains its original bottom-8 loading padding',
  );
}

void main() {
  setUpAll(loadFonts);
  final evidence = <Map<String, Object?>>[];
  tearDownAll(() async {
    await Directory(_directory).create(recursive: true);
    await File('$_directory/visual-summary.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scope': 'Component gallery of actual RuntimeStatusDialog/shared route and actual UserAvatarMenu/shared menu. Original runtime read-closure seam and 3ap Avatar port; profile callback spy, not a full profile page. No full shell/composition/device/real-account acceptance.',
        'checks': evidence,
      }),
    );
  });
  for (final suite in _suites) {
    for (final light in [false, true]) {
      final palette = light ? 'light' : 'dark';
      for (final locale in _locales) {
        for (final width in [540.0, 1100.0]) {
          testWidgets(
            '3fn runtime/avatar layout $suite $palette $locale $width 1.5x',
            (t) async {
              final p = _Probe(suite, light, locale);
              await _mount(t, p, width);
              await _openRuntime(t, p, 'pointer');
              _bounds(t, _key('settings-entry-runtime-status'), width);
              expect(find.byType(SocialReadActivity), findsOneWidget);
              if (locale.countryCode == 'CN' && width == 540) {
                await _capture(t, p, '${suite.name}-$palette-runtime-pending');
              }
              p.runtime.gate.complete(_facts);
              await _frames(t, 3);
              expect(p.runtime.controller.value.busy, isFalse);
              expect(p.runtime.controller.value.incomplete, isTrue);
              expect(find.byType(SocialReadActivity), findsNothing);
              expect(_key('runtime-status-partial'), findsOneWidget);
              await t.tap(_key('runtime-status-details'));
              await _frames(t, 2);
              await t.ensureVisible(_key('runtime-status-server'));
              await _frames(t, 2);
              _bounds(t, _key('settings-entry-runtime-status'), width);
              p.runtime.prepare(failAll: true);
              await t.tap(_key('runtime-status-refresh'));
              await _frames(t, 2);
              expect(p.runtime.controller.value.busy, isTrue);
              p.runtime.gate.completeError(
                StateError('fixture installation unavailable'),
              );
              await _frames(t, 3);
              expect(p.runtime.controller.value.installation, isNull);
              expect(p.runtime.controller.value.overlay, isNull);
              expect(p.runtime.controller.value.startup, isNull);
              expect(_key('runtime-status-partial'), findsOneWidget);
              expect(
                find.textContaining('fixture installation unavailable'),
                findsNothing,
              );
              _bounds(t, _key('settings-entry-runtime-status'), width);
              await _closeRuntime(t);

              await _avatarStage(t, p);
              final held = p.holdAvatar();
              await _openAvatar(t, 'pointer');
              _bounds(t, _profile, width);
              _avatarSlot(t);
              if (locale.countryCode == 'CN' && width == 1100) {
                await _capture(t, p, '${suite.name}-$palette-avatar-pending');
              }
              held.completeError(StateError('fixture social unavailable'));
              await _frames(t, 3);
              expect(find.byType(SocialReadActivity), findsNothing);
              expect(t.widget<SuitePressable>(_profile).onActivate, isNotNull);
              await t.tap(_profile);
              await _frames(t);
              expect(p.profileSources, [InteractionSource.pointer]);
              expect(p.avatar.commands, isEmpty);
              expect(p.avatar.targets, hasLength(1));
              evidence.add({
                'kind': 'layout',
                'suite': suite.name,
                'palette': palette,
                'locale': locale.toLanguageTag(),
                'width': width,
                'runtimeStates': [
                  'pending',
                  'partial',
                  'all-sources-unavailable',
                ],
                'avatarStates': [
                  'pending',
                  'social-unavailable',
                  'profile-still-usable',
                ],
              });
              await _unmount(t, p);
            },
          );
        }
      }
      testWidgets('3fn wait sources/local pixels $suite $palette', (t) async {
        final semantics = t.ensureSemantics();
        final p = _Probe(suite, light, const Locale('zh', 'CN'));
        try {
          await _mount(t, p, 1100);
          final checks = <Map<String, Object?>>[];
          await _openRuntime(t, p, 'pointer');
          checks.add(await _waiting(t, p, 'runtime-pointer', animated: true));
          p.update(() => p.reduce = true);
          await t.pump();
          await t.pump();
          checks.add(
            await _waiting(t, p, 'runtime-live-reduced', animated: false),
          );
          p.runtime.gate.complete(_facts);
          await _frames(t, 3);
          p.update(() => p.reduce = false);
          await t.pump();
          await t.pump();
          checks.add({
            'kind': 'runtime-refresh-touch',
            ...await _touchCancel(t, p, _key('runtime-status-refresh')),
          });
          p.runtime.prepare();
          await _keyboard(t, _key('runtime-status-refresh'));
          expect(p.runtime.reads, 2);
          checks.add(await _waiting(t, p, 'runtime-keyboard', animated: false));
          p.runtime.gate.complete(null);
          await _frames(t, 3);
          p.runtime.prepare();
          final strings = AppStrings.of(
            t.element(find.byType(RuntimeStatusDialog)),
          );
          final refreshText = t
              .widget<Text>(
                find
                    .descendant(
                      of: _key('runtime-status-refresh'),
                      matching: find.byType(Text),
                    )
                    .first,
              )
              .data!;
          // Localized actual exposed reader action; never a direct callback.
          await _reader(t, refreshText);
          expect(p.runtime.reads, 3);
          checks.add(await _waiting(t, p, 'runtime-reader', animated: false));
          p.runtime.gate.complete(null);
          await _frames(t, 3);
          await _closeRuntime(t);

          await _avatarStage(t, p);
          checks.add({
            'kind': 'avatar-anchor-touch',
            ...await _touchCancel(t, p, _key('user-avatar-menu-anchor')),
          });
          var held = p.holdAvatar();
          await _openAvatar(t, 'pointer');
          _avatarSlot(t);
          checks.add(await _waiting(t, p, 'avatar-pointer', animated: true));
          p.update(() => p.reduce = true);
          await t.pump();
          await t.pump();
          checks.add(
            await _waiting(t, p, 'avatar-live-reduced', animated: false),
          );
          await t.tap(_profile);
          await _frames(t);
          expect(p.profileSources, [InteractionSource.pointer]);
          held.complete(null);
          await _frames(t, 2);
          p.update(() => p.reduce = false);
          await t.pump();
          await t.pump();
          held = p.holdAvatar();
          await _openAvatar(t, 'keyboard');
          checks.add(await _waiting(t, p, 'avatar-keyboard', animated: false));
          held.completeError(StateError('fixture social unavailable'));
          await _frames(t, 3);
          expect(t.widget<SuitePressable>(_profile).onActivate, isNotNull);
          await _escapeAvatar(t);
          held = p.holdAvatar();
          await _openAvatar(t, 'reader');
          checks.add(await _waiting(t, p, 'avatar-reader', animated: false));
          await _reader(t, strings.text('avatar.viewProfile'));
          await _frames(t);
          expect(p.profileSources.last, InteractionSource.keyboard);
          held.complete(null);
          await _frames(t, 2);
          expect(p.avatar.commands, isEmpty);
          expect(p.avatar.targets, hasLength(3));
          expect(p.runtime.reads, 3);
          evidence.add({
            'kind': 'input',
            'suite': suite.name,
            'palette': palette,
            'checks': checks,
          });
          await _unmount(t, p);
        } finally {
          await _dispose(t, p);
          semantics.dispose();
        }
      });
    }
  }
}
