import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_chat_controller.dart';
import 'package:starbridge_flutter/features/communities/community_chat_copy.dart';
import 'package:starbridge_flutter/features/communities/community_chat_panel.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_local_message_tile.dart';
import 'package:starbridge_flutter/features/communities/community_ship_loaners.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/communities/community_chat_controller_test.dart'
    show FakeChat, page;
import '../../features/communities/community_ship_loaners_test.dart'
    show source, loaner;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

final _dir = const bool.hasEnvironment('INTERACTION_CAPTURE_DIR')
    ? const String.fromEnvironment('INTERACTION_CAPTURE_DIR')
    : visualOutputDir(
        'interaction_motion_batch3fj_20261017',
        legacySubdirectory: 'review',
      );
const _suites = [
  InteractionSuite.rail,
  InteractionSuite.scan,
  InteractionSuite.glow,
];
const _locales = [Locale('zh', 'CN'), Locale('zh', 'TW'), Locale('en', 'US')];
Finder _key(String key) => find.byKey(Key(key));

/// Actual chat/controller and existing in-memory port; support tiles are the
/// production display-only constructor, not synthetic domain messages.
class _Probe {
  _Probe(this.suite, this.light, this.locale) {
    port.next = page(List.generate(15, (i) => i + 10), latest: 40);
    controller = CommunityChatController(port, 'a' * 32);
  }
  final InteractionSuite suite;
  final bool light;
  final Locale locale;
  final port = FakeChat();
  late final CommunityChatController controller;
  final frame = GlobalKey();
  final calls = <String>[];
  bool reduce = false, support = false;
  late StateSetter update;

  Widget _body() => support
      ? SingleChildScrollView(
          key: const Key('3fj-support-scroll'),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CommunityLocalMessageTile.presentation(
                key: const Key('3fj-failed'),
                text: 'Flight plan could not be delivered. Keep this draft.',
                state: 'failed',
                error: 'rateLimited',
                createdAt: DateTime.utc(2026, 10, 17, 8, 30),
                composerOccupied: true,
                onRetry: () => calls.add('retry'),
                onRestore: null,
              ),
              const SizedBox(height: 16),
              CommunityLocalMessageTile.presentation(
                key: const Key('3fj-unknown'),
                text: 'Delivery is unknown. Check history before trying again.',
                state: 'unknown',
                error: 'outcomeUnknown',
                createdAt: DateTime.utc(2026, 10, 17, 8, 32),
                onCheck: () => calls.add('check'),
              ),
              const SizedBox(height: 16),
              CommunityShipLoaners(
                ship: source(
                  rows: [
                    loaner('Replacement Courier', 'small', 'flyable'),
                    loaner('Replacement Transport', 'large', 'flyable'),
                  ],
                ),
              ),
            ],
          ),
        )
      : CommunityChatPanel(
          port: port,
          controller: controller,
          targetRef: 'a' * 32,
          name: 'Northwind 联合组织',
          onBack: () => calls.add('back'),
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

Future<void> _mount(WidgetTester t, _Probe probe, Size viewport) async {
  size(t, viewport);
  addTearDown(probe.port.changes.close);
  addTearDown(probe.controller.dispose);
  await probe.controller.refresh();
  await t.pumpWidget(probe.app());
  await _frames(t);
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await _frames(t, 2);
  expect(t.takeException(), isNull);
}

Finder _localAction(WidgetTester t, String tile, String copy) {
  final owner = _key(tile);
  final label = communityChatText(t.element(owner), copy);
  return find.descendant(
    of: owner,
    matching: find.widgetWithText(StarBridgeActionButton, label),
  );
}

Finder _pressable(Finder owner) {
  return find
      .descendant(of: owner, matching: find.byType(SuitePressable))
      .first;
}

Future<void> _reveal(WidgetTester t, Finder target) async {
  expect(target, findsOneWidget);
  await t.ensureVisible(target);
  await _frames(t, 2);
}

Future<void> _tab(WidgetTester t, Finder owner) async {
  await _reveal(t, owner);
  final target = t.widget(owner) is SuitePressable ? owner : _pressable(owner);
  final node = t.widget<SuitePressable>(target).focusNode!;
  for (var i = 0; i < 100 && !node.hasPrimaryFocus; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
  }
  expect(
    node.hasPrimaryFocus,
    isTrue,
    reason: 'Real Tab traversal reaches the original target',
  );
}

Future<void> _keyboard(WidgetTester t, Finder owner) async {
  await _tab(t, owner);
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pump();
  await t.pump();
}

Future<List<int>> _pixels(WidgetTester t, _Probe probe, Rect globalRect) async {
  final boundary =
      probe.frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final rect = globalRect.shift(-boundary.localToGlobal(Offset.zero));
  return (await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
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

int _diff(List<int> a, List<int> b) {
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

Map<String, double> _rect(Rect r) => {
  'left': r.left,
  'top': r.top,
  'width': r.width,
  'height': r.height,
};

void _layout(WidgetTester t, Size viewport) {
  expect(t.takeException(), isNull);
  for (final element in find.byType(SuitePressable).evaluate()) {
    final box = element.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) continue;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    // Offscreen content in the genuine scroll view is valid; horizontal
    // controls may not escape the viewport in any locale/theme.
    expect(rect.left, greaterThanOrEqualTo(-.01));
    expect(rect.right, lessThanOrEqualTo(viewport.width + .01));
  }
}

Future<void> _capture(WidgetTester t, _Probe probe, String name) async {
  final boundary =
      probe.frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(_dir).create(recursive: true);
      await File('$_dir/$name.png').writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

String _signature(_Probe p) => jsonEncode({
  'reads': p.port.reads.map((r) => [r.$1, r.$2]).toList(),
  'sends': p.port.sends.length,
  'draft': p.controller.draft,
  'callbacks': p.calls,
});

Future<Map<String, Object?>> _touchCancel(
  WidgetTester t,
  _Probe p,
  Finder owner,
) async {
  await _reveal(t, owner);
  final target = t.widget(owner) is SuitePressable ? owner : _pressable(owner);
  final rect = t.getRect(target);
  final before = await _pixels(t, p, rect);
  await t.pump(const Duration(milliseconds: 180));
  expect(
    _diff(before, await _pixels(t, p, rect)),
    0,
    reason: 'Equal idle time is stable',
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
    expect(
      changed,
      greaterThan(0),
      reason: 'Actual held press has visible local feedback',
    );
    expect(_signature(p), signature, reason: 'No command before release');
  } finally {
    await gesture.cancel();
    await _frames(t);
  }
  expect(
    _signature(p),
    signature,
    reason: 'Cancelled gestures never issue a command',
  );
  return {'rect': _rect(rect), 'idlePixels': 0, 'pressPixels': changed};
}

Future<Map<String, Object?>> _stable(
  WidgetTester t,
  _Probe p,
  Finder target,
) async {
  final rect = t.getRect(target);
  final before = await _pixels(t, p, rect);
  await t.pump(const Duration(milliseconds: 600));
  expect(t.getRect(target), rect);
  final changed = _diff(before, await _pixels(t, p, rect));
  expect(changed, 0, reason: 'Keyboard/reduced feedback is static');
  return {'rect': _rect(rect), 'elapsedMs': 600, 'changedPixels': changed};
}

Future<Map<String, Object?>> _waitingPixels(
  WidgetTester t,
  _Probe p, {
  required bool animated,
}) async {
  final target = find.byType(SocialReadActivity);
  expect(target, findsOneWidget);
  final rect = t.getRect(target).inflate(4);
  await t.pump(const Duration(milliseconds: 80));
  final before = await _pixels(t, p, rect);
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  expect(t.getRect(target).inflate(4), rect);
  final changed = _diff(before, await _pixels(t, p, rect));
  expect(changed, animated ? greaterThan(0) : equals(0));
  return {
    'rect': _rect(rect),
    'elapsedMs': 600,
    'animated': animated,
    'changedPixels': changed,
  };
}

Future<void> _complete(
  WidgetTester t,
  _Probe p,
  CommunityChatPage result,
) async {
  final held = p.port.heldRead!;
  p.port.heldRead = null;
  held.complete(result);
  await _frames(t, 3);
  expect(p.controller.loading, isFalse);
}

void main() {
  setUpAll(loadFonts);
  final evidence = <Map<String, Object?>>[];
  tearDownAll(() async {
    await Directory(_dir).create(recursive: true);
    await File('$_dir/visual-summary.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scope': 'Actual CommunityChatPanel/controller + existing FakeChat; production presentation-only failed/unknown local tiles and loaner widget. No workspace/online pane/native window/real account acceptance.',
        'checks': evidence,
      }),
    );
  });

  for (final suite in _suites) {
    for (final light in [false, true]) {
      final palette = light ? 'light' : 'dark';
      for (final locale in _locales) {
        for (final width in [540.0, 1100.0]) {
          testWidgets('3fj chat/support $suite $palette $locale $width 1.5x', (
            t,
          ) async {
            final viewport = Size(width, 1100);
            final p = _Probe(suite, light, locale);
            await _mount(t, p, viewport);
            _layout(t, viewport);
            expect(p.controller.messages.length, 15);
            final list = find.descendant(
              of: find.byType(CommunityChatPanel),
              matching: find.byType(ListView),
            );
            final scroll = t.state<ScrollableState>(
              find
                  .descendant(of: list, matching: find.byType(Scrollable))
                  .first,
            );
            expect(
              scroll.position.maxScrollExtent,
              greaterThan(0),
              reason: 'Actual message list remains scrollable',
            );
            final scrollExtent = scroll.position.maxScrollExtent;
            await t.drag(list, const Offset(0, 220));
            await _frames(t, 2);
            _layout(t, viewport);
            expect(_key('community-chat-latest'), findsOneWidget);

            p.port.heldRead = Completer<CommunityChatPage>();
            await t.tap(_key('community-chat-refresh'));
            await _frames(t, 2);
            expect(p.controller.loading, isTrue);
            expect(find.byType(SocialReadActivity), findsOneWidget);
            _layout(t, viewport);
            if (locale.countryCode == 'CN' && width == 540) {
              await _capture(t, p, '${suite.name}-$palette-chat-pending');
            }
            final rejected = p.port.heldRead!;
            p.port.heldRead = null;
            rejected.completeError(const CommunityFailure('unavailable'));
            await _frames(t, 2);
            expect(p.controller.error, 'unavailable');
            _layout(t, viewport);

            p.port.heldRead = Completer<CommunityChatPage>();
            await t.tap(_key('community-chat-older'));
            await _frames(t, 2);
            expect(p.controller.loading, isTrue);
            _layout(t, viewport);
            await _complete(t, p, page([5, 7], latest: 40, older: false));
            expect(p.controller.messages.first.sequence, 5);
            p.port.next = page([30, 40], latest: 40, older: false);
            await t.tap(_key('community-chat-latest'));
            await _frames(t, 3);
            expect(p.controller.messages.last.sequence, 40);
            _layout(t, viewport);
            expect(p.port.sends, isEmpty);

            p.update(() => p.support = true);
            await _frames(t, 3);
            expect(find.byType(CommunityLocalMessageTile), findsNWidgets(2));
            final disclosure = find
                .descendant(
                  of: find.byType(CommunityShipLoaners),
                  matching: find.byType(SuitePressable),
                )
                .first;
            await _reveal(t, disclosure);
            await t.tap(disclosure);
            await _frames(t, 5);
            expect(find.text('Replacement Courier'), findsNWidgets(2));
            _layout(t, viewport);
            if (locale.countryCode == 'CN' && width == 1100) {
              await _capture(t, p, '${suite.name}-$palette-local-loaners');
            }
            expect(p.calls, isEmpty);
            evidence.add({
              'kind': 'layout',
              'suite': suite.name,
              'palette': palette,
              'locale': locale.toLanguageTag(),
              'width': width,
              'messageScrollExtent': scrollExtent,
            });
            await _unmount(t);
          });
        }
      }

      testWidgets('3fj actual inputs/pixels $suite $palette', (t) async {
        final p = _Probe(suite, light, const Locale('zh', 'CN'));
        await _mount(t, p, const Size(1100, 1100));
        final checks = <Map<String, Object?>>[];
        // Cancel a real enabled history button; no reads/sends/draft changes.
        final older = _key('community-chat-older');
        checks.add({
          'kind': 'history-touch',
          ...await _touchCancel(t, p, older),
        });

        p.port.heldRead = Completer<CommunityChatPage>();
        await t.tap(_key('community-chat-refresh'));
        await t.pump();
        await t.pump();
        expect(p.controller.loading, isTrue);
        checks.add({
          'kind': 'pointer-wait',
          ...await _waitingPixels(t, p, animated: true),
        });
        p.update(() => p.reduce = true);
        await t.pump();
        await t.pump();
        checks.add({
          'kind': 'live-reduce-wait',
          ...await _waitingPixels(t, p, animated: false),
        });
        await _complete(t, p, page([30], latest: 40));
        p.update(() => p.reduce = false);
        await t.pump();
        await t.pump();

        // The real panel's 3-second poll remains enabled. Do not let it
        // consume the held response while _tab reveals/traverses the button.
        // Any poll during that preparation gets an admissible empty delta;
        // install the hold only after enabled focus has actually arrived.
        p.port.next = page([], latest: 40, older: true);
        await _tab(t, _key('community-chat-refresh'));
        expect(p.controller.loading, isFalse);
        final readsBeforeKeyboard = p.port.reads.length;
        p.port.heldRead = Completer<CommunityChatPage>();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        await t.pump();
        expect(p.port.reads.length, readsBeforeKeyboard + 1);
        expect(p.controller.loading, isTrue);
        checks.add({
          'kind': 'keyboard-wait',
          ...await _waitingPixels(t, p, animated: false),
        });
        await _complete(t, p, page([40], latest: 40));
        expect(p.port.sends, isEmpty);

        p.update(() => p.support = true);
        await _frames(t, 3);
        final disclosure = find
            .descendant(
              of: find.byType(CommunityShipLoaners),
              matching: find.byType(SuitePressable),
            )
            .first;
        checks.add({
          'kind': 'loaners-touch',
          ...await _touchCancel(t, p, disclosure),
        });
        await t.tap(disclosure);
        await _frames(t, 5);
        expect(find.text('Replacement Courier'), findsNWidgets(2));
        await _keyboard(t, disclosure);
        expect(find.text('Replacement Courier'), findsNothing);
        checks.add({
          'kind': 'loaners-keyboard',
          ...await _stable(t, p, disclosure),
        });
        final retry = _localAction(t, '3fj-failed', 'retry');
        final check = _localAction(t, '3fj-unknown', 'checkSend');
        final restore = _localAction(t, '3fj-failed', 'restoreLocalDraft');
        expect(t.widget<StarBridgeActionButton>(restore).onActivate, isNull);
        checks.add({
          'kind': 'local-retry-touch',
          ...await _touchCancel(t, p, retry),
        });
        checks.add({
          'kind': 'local-check-touch',
          ...await _touchCancel(t, p, check),
        });
        await _keyboard(t, retry);
        expect(p.calls, ['retry']);
        checks.add({'kind': 'local-keyboard', ...await _stable(t, p, retry)});
        p.update(() => p.reduce = true);
        await t.pump();
        await t.pump();
        await t.tap(check);
        await t.pump();
        await t.pump();
        expect(p.calls, ['retry', 'check']);
        checks.add({
          'kind': 'local-reduced-pointer',
          ...await _stable(t, p, check),
        });
        expect(p.port.sends, isEmpty);
        evidence.add({
          'kind': 'input',
          'suite': suite.name,
          'palette': palette,
          'checks': checks,
        });
        await _unmount(t);
      });
    }
  }
}
