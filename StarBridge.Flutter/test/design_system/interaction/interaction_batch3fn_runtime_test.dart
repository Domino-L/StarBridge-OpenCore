// Borrowed-controller lifecycle probes intentionally observe, but never change,
// ChangeNotifier's protected listener diagnostic.
// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/settings/runtime_status_controller.dart';
import 'package:starbridge_flutter/features/settings/runtime_status_dialog.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3do_test.dart'
    show exposedNodes, loadFonts, scopedApp, size;

Future<void> _frames(WidgetTester t, [int count = 2]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

const _facts = RuntimeInstallationFacts(
  dataDirectory: r'C:\Synthetic\Data',
  imageCacheDirectory: r'C:\Synthetic\Data\Images',
  imageCacheExists: true,
  applicationVersion: '1.2.3',
);
const _overlay = RuntimeOverlayFacts(
  windowState: 'closed',
  hotkeyState: 'registered',
);
const _startup = RuntimeStartupFacts(
  launchAtStartup: false,
  startMinimized: false,
  keepRunningInBackground: true,
);
const _openKey = Key('runtime-open');
const _refreshKey = Key('runtime-status-refresh');
const _closeKey = Key('runtime-status-close');

class _Probe {
  _Probe() {
    controller = RuntimeStatusController(
      readInstallation: () {
        final index = installationReads++;
        sources.add(captureStarBridgeActivationSource()());
        return gates[index].future;
      },
      readOverlay: () async {
        overlayReads++;
        return _overlay;
      },
      readStartup: () async {
        startupReads++;
        return _startup;
      },
    );
  }
  final gates = List.generate(5, (_) => Completer<RuntimeInstallationFacts?>());
  final sources = <InteractionSource>[];
  int installationReads = 0, overlayReads = 0, startupReads = 0;
  late final RuntimeStatusController controller;
  void complete(int phase, {RuntimeInstallationFacts? facts = _facts}) {
    if (!gates[phase].isCompleted) {
      gates[phase].complete(facts);
    }
  }

  Future<void> release(WidgetTester t) async {
    for (final gate in gates) {
      if (!gate.isCompleted) {
        gate.complete(null);
      }
    }
    await _frames(t);
  }

  void expectReads(int count) {
    expect(installationReads, count);
    expect(overlayReads, count);
    expect(startupReads, count);
  }
}

Widget _entry(_Probe p) => Builder(
  builder: (context) => StarBridgeActionButton(
    controlKey: _openKey,
    onActivate: (_) => showRuntimeStatusDialog(context, p.controller),
    child: const Text('Open runtime'),
  ),
);

Future<void> _mount(
  WidgetTester t,
  Widget child,
  InteractionSuite suite, {
  bool reduce = false,
  bool light = false,
}) async {
  await t.pumpWidget(scopedApp(child, suite, reduce: reduce, light: light));
  await _frames(t);
}

FocusNode _focus(WidgetTester t, Finder target) => switch (t.widget(target)) {
  ButtonStyleButton b => b.focusNode!,
  SuitePressable b => b.focusNode!,
  _ => throw StateError('Missing public focus owner'),
};

Future<void> _activate(
  WidgetTester t,
  Key key,
  String input,
  String label,
) async {
  final target = find.byKey(key);
  expect(target, findsOneWidget);
  if (input == 'pointer') {
    await t.tap(target);
  } else if (input == 'keyboard') {
    final focus = _focus(t, target);
    var tabs = 0;
    do {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      tabs++;
    } while (FocusManager.instance.primaryFocus != focus && tabs < 48);
    expect(FocusManager.instance.primaryFocus, same(focus));
    expect(tabs, inInclusiveRange(1, 48));
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final nodes = exposedNodes(t)
        .where(
          (n) =>
              n.getSemanticsData().flagsCollection.isButton &&
              n.getSemanticsData().label == label &&
              n.getSemanticsData().hasAction(SemanticsAction.tap),
        )
        .toList();
    expect(nodes, hasLength(1));
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      nodes.single.id,
      SemanticsAction.tap,
    );
  }
  await _frames(t, 4);
}

void _expectWait(
  WidgetTester t,
  InteractionSuite suite, {
  required bool animated,
  double height = 4,
}) {
  final wait = find.byType(SocialReadActivity);
  expect(wait, findsOneWidget);
  final frame = find.descendant(
    of: wait,
    matching: find.byType(SuiteBusyFrame),
  );
  final local = InteractionScope.of(t.element(frame));
  expect(local.suite, suite);
  expect(local.reduceMotion, !animated);
  final progress = find.descendant(
    of: wait,
    matching: find.byType(LinearProgressIndicator),
  );
  expect(progress, findsOneWidget);
  expect(t.widget<LinearProgressIndicator>(progress).minHeight, height);
  expect(t.getSize(progress).height, height);
  expect(
    t.widget<LinearProgressIndicator>(progress).value,
    animated &&
            (suite == InteractionSuite.standard ||
                suite == InteractionSuite.glow)
        ? isNull
        : .5,
  );
  expect(
    exposedNodes(t).where((n) => n.getSemanticsData().value.contains('50%')),
    isEmpty,
  );
  final labels = exposedNodes(t)
      .map((n) => n.getSemanticsData().label)
      .expand((label) => '正在读取…'.allMatches(label));
  expect(
    labels,
    hasLength(1),
    reason: 'The original status Text remains the sole readable wait.',
  );
}

Future<Uint8List> _pixels(WidgetTester t) async {
  final finder = find.descendant(
    of: find.byType(SocialReadActivity),
    matching: find.byType(RepaintBoundary),
  );
  expect(finder, findsOneWidget);
  final boundary = t.renderObject<RenderRepaintBoundary>(finder);
  return (await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return Uint8List.fromList(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'runtime actual keyboard opening holds original read under static wait',
    (t) async {
      size(t, const Size(1100, 900));
      final gate = Completer<RuntimeInstallationFacts?>();
      var reads = 0;
      final controller = RuntimeStatusController(
        readInstallation: () {
          reads++;
          return gate.future;
        },
        readOverlay: () async =>
            const RuntimeOverlayFacts(windowState: 'closed'),
        readStartup: () async => null,
      );
      try {
        await t.pumpWidget(
          scopedApp(
            Builder(
              builder: (context) => StarBridgeActionButton(
                controlKey: const Key('runtime-open'),
                onActivate: (_) => showRuntimeStatusDialog(context, controller),
                child: const Text('Open runtime'),
              ),
            ),
            InteractionSuite.scan,
          ),
        );
        await _frames(t);
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await _frames(t);
        final dialog = find.byType(RuntimeStatusDialog);
        expect(dialog, findsOneWidget);
        expect(
          (ModalRoute.of(t.element(dialog))! as StarBridgeDialogRoute).instant,
          isTrue,
        );
        expect(controller.value.busy, isTrue);
        expect(controller.value.installation, isNull);
        expect(reads, 1);
        expect(gate.isCompleted, isFalse);
        expect(find.byType(SocialReadActivity), findsOneWidget);
        final frame = find.descendant(
          of: dialog,
          matching: find.byType(SuiteBusyFrame),
        );
        expect(InteractionScope.of(t.element(frame)).reduceMotion, isTrue);
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox.shrink());
        if (!gate.isCompleted) {
          gate.complete(null);
        }
        await _frames(t);
        controller.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite runtime first read/refresh/close actual $input preserves owner',
        (t) async {
          size(t, const Size(1100, 900));
          final semantics = t.ensureSemantics();
          final p = _Probe();
          try {
            await _mount(t, _entry(p), suite);
            await _activate(t, _openKey, input, 'Open runtime');
            final dialog = find.byType(RuntimeStatusDialog);
            expect(
              (ModalRoute.of(t.element(dialog))! as StarBridgeDialogRoute)
                  .instant,
              input != 'pointer',
            );
            expect(p.controller.value.busy, isTrue);
            expect(p.controller.value.installation, isNull);
            p.expectReads(1);
            _expectWait(t, suite, animated: input == 'pointer');
            expect(p.gates[0].isCompleted, isFalse);
            final refresh = t.widget<StarBridgeActionButton>(
              find.ancestor(
                of: find.byKey(_refreshKey),
                matching: find.byType(StarBridgeActionButton),
              ),
            );
            expect(refresh.onActivate, isNull);
            // A pointer cannot hit a button that the real entrance clip has
            // not revealed yet. Wait on the actual route, not the busy read,
            // before probing that disabled button instead of the scrim.
            final route = ModalRoute.of(t.element(dialog))!;
            for (
              var i = 0;
              route.animation?.status != AnimationStatus.completed && i < 30;
              i++
            ) {
              await t.pump(const Duration(milliseconds: 50));
            }
            expect(route.animation?.status, AnimationStatus.completed);
            await t.tapAt(t.getCenter(find.byKey(_refreshKey)));
            await _frames(t);
            p.expectReads(1);
            p.complete(0);
            await _frames(t);
            expect(p.controller.value.busy, isFalse);
            expect(p.controller.value.installation, same(_facts));
            expect(p.controller.value.overlay, same(_overlay));
            expect(p.controller.value.startup, same(_startup));
            expect(p.controller.value.incomplete, isFalse);
            expect(find.byType(SocialReadActivity), findsNothing);
            await _activate(t, _refreshKey, input, '刷新');
            p.expectReads(2);
            expect(
              p.sources.last,
              input == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(
              p.controller.value.installation,
              isNull,
              reason: 'Original refresh clears stale facts.',
            );
            expect(p.controller.value.overlay, isNull);
            expect(p.controller.value.loaded, isFalse);
            _expectWait(t, suite, animated: input == 'pointer');
            await _activate(t, _closeKey, input, '关闭');
            await _frames(t, 8);
            expect(find.byType(RuntimeStatusDialog), findsNothing);
            expect(
              p.controller.value.busy,
              isTrue,
              reason: 'Dialog does not cancel a borrowed read.',
            );
            expect(p.controller.hasListeners, isFalse);
            p.complete(1, facts: null);
            await _frames(t);
            expect(p.controller.value.incomplete, isTrue);
            expect(p.controller.value.overlay, same(_overlay));
            expect(find.byType(RuntimeStatusDialog), findsNothing);
            p.expectReads(2);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox.shrink());
            await p.release(t);
            p.controller.dispose();
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }

    for (final pair in [('pointer', 'keyboard'), ('keyboard', 'pointer')]) {
      testWidgets(
        '$suite runtime ${pair.$1} opening then ${pair.$2} refresh uses new phase',
        (t) async {
          size(t, const Size(1100, 900));
          final semantics = t.ensureSemantics();
          final p = _Probe();
          try {
            await _mount(t, _entry(p), suite);
            await _activate(t, _openKey, pair.$1, 'Open runtime');
            _expectWait(t, suite, animated: pair.$1 == 'pointer');
            final firstWait = t.state(find.byType(SocialReadActivity));
            p.complete(0);
            await _frames(t);
            await _activate(t, _refreshKey, pair.$2, '刷新');
            _expectWait(t, suite, animated: pair.$2 == 'pointer');
            expect(
              t.state(find.byType(SocialReadActivity)),
              isNot(same(firstWait)),
            );
            expect(
              p.sources.last,
              pair.$2 == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(
              t
                  .widget<SocialReadActivity>(find.byType(SocialReadActivity))
                  .opening,
              isFalse,
            );
            p.expectReads(2);
            expect(p.gates[1].isCompleted, isFalse);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox.shrink());
            await p.release(t);
            p.controller.dispose();
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }

    testWidgets(
      '$suite already-busy borrowed runtime phase stays unknown/static',
      (t) async {
        size(t, const Size(1100, 900));
        final semantics = t.ensureSemantics();
        final p = _Probe();
        final reading = p.controller
            .refresh(); // Existing owner read, before UI attachment.
        try {
          p.expectReads(1);
          await _mount(t, _entry(p), suite);
          await _activate(t, _openKey, 'pointer', 'Open runtime');
          p.expectReads(1);
          final activity = t.widget<SocialReadActivity>(
            find.byType(SocialReadActivity),
          );
          expect(activity.source, InteractionSource.programmatic);
          expect(activity.opening, isFalse);
          _expectWait(t, suite, animated: false);
          p.complete(0);
          await reading;
          await _frames(t);
          await _activate(t, _refreshKey, 'pointer', '刷新');
          p.expectReads(2);
          _expectWait(t, suite, animated: true);
          await _activate(t, _closeKey, 'keyboard', '关闭');
          expect(p.controller.hasListeners, isFalse);
          p.complete(1);
          await _frames(t);
          // Public owner operation proves the dialog did not dispose the loan.
          final next = p.controller.refresh();
          p.expectReads(3);
          p.complete(2);
          await next;
          expect(p.controller.value.installation, same(_facts));
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox.shrink());
          await p.release(t);
          await reading;
          p.controller.dispose();
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite controller replacement retires only old presentation listener',
      (t) async {
        size(t, const Size(1100, 900));
        final semantics = t.ensureSemantics();
        final first = _Probe(), next = _Probe();
        try {
          await _mount(
            t,
            RuntimeStatusDialog(controller: first.controller, embedded: true),
            suite,
          );
          first.expectReads(1);
          expect(first.controller.hasListeners, isTrue);
          await _mount(
            t,
            RuntimeStatusDialog(controller: next.controller, embedded: true),
            suite,
          );
          first.expectReads(1);
          next.expectReads(1);
          expect(first.controller.hasListeners, isFalse);
          expect(next.controller.hasListeners, isTrue);
          _expectWait(t, suite, animated: false);
          expect(
            t
                .widget<SocialReadActivity>(find.byType(SocialReadActivity))
                .opening,
            isFalse,
          );
          first.complete(0);
          await _frames(t);
          expect(first.controller.value.installation, same(_facts));
          expect(next.controller.value.busy, isTrue);
          expect(next.controller.value.installation, isNull);
          expect(
            t
                .widget<RuntimeStatusDialog>(find.byType(RuntimeStatusDialog))
                .controller,
            same(next.controller),
          );
          next.complete(0, facts: null);
          await _frames(t);
          expect(
            find.byKey(const Key('runtime-status-partial')),
            findsOneWidget,
          );
          expect(next.controller.value.overlay, same(_overlay));
          expect(next.controller.value.incomplete, isTrue);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox.shrink());
          expect(first.controller.hasListeners, isFalse);
          expect(next.controller.hasListeners, isFalse);
          await first.release(t);
          await next.release(t);
          first.controller.dispose();
          next.controller.dispose();
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite programmatic controller replacement cannot borrow old keyboard route opening',
      (t) async {
        size(t, const Size(1100, 900));
        final semantics = t.ensureSemantics();
        final first = _Probe(), next = _Probe();
        final current = ValueNotifier<_Probe>(first);
        try {
          await _mount(
            t,
            Builder(
              builder: (context) => StarBridgeActionButton(
                controlKey: _openKey,
                onActivate: (_) => showStarBridgeDialog<void>(
                  context,
                  builder: (_) => ValueListenableBuilder<_Probe>(
                    valueListenable: current,
                    builder: (context, probe, _) =>
                        RuntimeStatusDialog(controller: probe.controller),
                  ),
                ),
                child: const Text('Open runtime'),
              ),
            ),
            suite,
          );
          await _activate(t, _openKey, 'keyboard', 'Open runtime');
          expect(
            (ModalRoute.of(t.element(find.byType(RuntimeStatusDialog)))!
                    as StarBridgeDialogRoute)
                .instant,
            isTrue,
          );
          _expectWait(t, suite, animated: false);
          first.complete(0);
          await _frames(t);
          expect(first.controller.value.loaded, isTrue);
          final originalState = t.state(find.byType(RuntimeStatusDialog));
          // Public owner replacement, not a simulated UI edit or new read grant.
          current.value = next;
          await _frames(t);
          expect(
            t.state(find.byType(RuntimeStatusDialog)),
            same(originalState),
          );
          expect(first.controller.hasListeners, isFalse);
          first.expectReads(1);
          next.expectReads(1);
          final activity = t.widget<SocialReadActivity>(
            find.byType(SocialReadActivity),
          );
          expect(activity.source, InteractionSource.programmatic);
          expect(activity.opening, isFalse);
          _expectWait(t, suite, animated: false);
          expect(next.gates[0].isCompleted, isFalse);
          expect(next.controller.value.installation, isNull);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox.shrink());
          await first.release(t);
          await next.release(t);
          first.controller.dispose();
          next.controller.dispose();
          current.dispose();
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite embedded initial keyboard viewport does not relabel later passive refresh',
      (t) async {
        size(t, const Size(1100, 900));
        final semantics = t.ensureSemantics();
        final p = _Probe();
        try {
          await _mount(
            t,
            Builder(
              builder: (context) => starBridgeInitialReadViewport(
                context,
                source: InteractionSource.keyboard,
                child: RuntimeStatusDialog(
                  controller: p.controller,
                  embedded: true,
                ),
              ),
            ),
            suite,
          );
          _expectWait(t, suite, animated: false);
          p.complete(0);
          await _frames(t);
          final passive = p.controller.refresh();
          await _frames(t);
          p.expectReads(2);
          expect(p.sources.last, InteractionSource.programmatic);
          expect(
            t
                .widget<SocialReadActivity>(find.byType(SocialReadActivity))
                .opening,
            isFalse,
          );
          _expectWait(t, suite, animated: false);
          p.complete(1);
          await passive;
          await _frames(t);
          expect(find.byKey(_closeKey), findsNothing);
          await _activate(t, _refreshKey, 'pointer', '刷新');
          _expectWait(t, suite, animated: true);
          p.expectReads(3);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox.shrink());
          await p.release(t);
          p.controller.dispose();
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite runtime live theme/suite/reduce keeps one read and static pixels',
      (t) async {
        size(t, const Size(1100, 900));
        final semantics = t.ensureSemantics();
        final p = _Probe();
        try {
          await _mount(t, _entry(p), suite);
          await _activate(t, _openKey, 'pointer', 'Open runtime');
          _expectWait(t, suite, animated: true);
          final dialog = t.state(find.byType(RuntimeStatusDialog));
          final next = InteractionSuite
              .values[(suite.index + 1) % InteractionSuite.values.length];
          await _mount(t, _entry(p), next, reduce: true, light: true);
          expect(t.state(find.byType(RuntimeStatusDialog)), same(dialog));
          _expectWait(t, next, animated: false);
          p.expectReads(1);
          expect(
            Theme.of(t.element(find.byType(SocialReadActivity))).brightness,
            Brightness.light,
          );
          final before = await _pixels(t);
          await _frames(t, 5);
          expect(listEquals(before, await _pixels(t)), isTrue);
          await _mount(t, _entry(p), next);
          _expectWait(t, next, animated: true);
          p.expectReads(1);
          expect(p.gates[0].isCompleted, isFalse);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox.shrink());
          await p.release(t);
          p.controller.dispose();
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite runtime progress uses original themed height without extra caption',
      (t) async {
        size(t, const Size(1100, 900));
        final semantics = t.ensureSemantics();
        final p = _Probe();
        try {
          await _mount(
            t,
            ProgressIndicatorTheme(
              data: const ProgressIndicatorThemeData(linearMinHeight: 7),
              child: RuntimeStatusDialog(
                controller: p.controller,
                embedded: true,
              ),
            ),
            suite,
          );
          _expectWait(t, suite, animated: true, height: 7);
          expect(find.text('正在读取…'), findsOneWidget);
          expect(
            t.widget<SocialReadActivity>(find.byType(SocialReadActivity)).label,
            isEmpty,
          );
          p.expectReads(1);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox.shrink());
          await p.release(t);
          p.controller.dispose();
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
