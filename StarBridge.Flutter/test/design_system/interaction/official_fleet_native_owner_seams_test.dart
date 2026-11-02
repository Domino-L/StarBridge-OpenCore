// SOURCE PREPARATION ONLY. Not installed in candidate-app or primary.
// Eventual location, only after approval:
// test/design_system/interaction/official_fleet_native_owner_seams_test.dart
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_support_views.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/official_fleet_motion_helpers.dart'
    show loadFonts, size, scopedApp, exposedNodes;

const _nativeKey = Key('official-fleet-retry-native');
const _referenceKey = Key('3gk-seam-reference');
const _targetKey = Key('official-fleet-retry-target');
const _imageKey = Key('3gk-seam-image');

class _PassiveMember implements GestureArenaMember {
  _PassiveMember(this.trace);
  final List<String> trace;
  int accepted = 0, rejected = 0;
  @override
  void acceptGesture(int pointer) {
    accepted++;
    trace.add('passiveAccept');
  }

  @override
  void rejectGesture(int pointer) {
    rejected++;
    trace.add('passiveReject');
  }
}

class _TrackedPointer {
  _TrackedPointer(this.gesture, this.registry);
  final TestGesture gesture;
  final Set<_TrackedPointer> registry;
  bool ended = false;
  Future<void> moveBy(Offset offset) => gesture.moveBy(offset);
  Future<void> up() async {
    if (ended) return;
    ended = true;
    try {
      await gesture.up();
    } finally {
      registry.remove(this);
    }
  }

  Future<void> cancel() async {
    if (ended) return;
    ended = true;
    try {
      await gesture.cancel();
    } finally {
      registry.remove(this);
    }
  }
}

class _Probe extends StatefulWidget {
  const _Probe(this.suite, {required super.key, this.reference = false});
  final InteractionSuite suite;
  final bool reference;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  late var suite = widget.suite;
  late var reference = widget.reference;
  bool reduce = false, light = false, competeForDrag = false, holdArena = false;
  bool holdFuture = false;
  int owner = 0, panUpdates = 0, rawCancels = 0;
  int? heldPointer;
  _PassiveMember? member;
  GestureArenaEntry? passiveEntry;
  final activePointers = <_TrackedPointer>{};
  final trace = <String>[];
  final commands = <(int, InteractionSource)>[];
  final pending = Completer<void>();
  final referenceFocus = FocusNode();
  final referenceStates = WidgetStatesController();

  void change(VoidCallback action) => setState(action);
  Future<void> _first() => _record(0);
  Future<void> _second() => _record(1);
  Future<void> _record(int id) {
    trace.add('command');
    commands.add((id, captureStarBridgeActivationSource()()));
    return holdFuture ? pending.future : Future<void>.value();
  }

  void _referenceCommand() {
    trace.add('command');
    // Reference proves real native timing, not provenance from a default getter.
    commands.add((owner, InteractionSource.programmatic));
  }

  void releaseHeld() {
    final pointer = heldPointer;
    heldPointer = null;
    if (pointer != null) {
      trace.add('releaseBegin');
      GestureBinding.instance.gestureArena.release(pointer);
    }
    // Intentional release settles the arena first, preserving the timing probe.
    // Resolve any leftover passive entry as well on an exceptional path.
    passiveEntry?.resolve(GestureDisposition.rejected);
    passiveEntry = null;
  }

  Future<void> cancelActivePointers() async {
    for (final pointer in activePointers.toList()) {
      await pointer.cancel();
    }
  }

  void completePending() {
    if (!pending.isCompleted) pending.complete();
  }

  @override
  Widget build(BuildContext context) => scopedApp(
    Builder(
      builder: (context) {
        final label = AppStrings.of(context).text('officialFleet.action.retry');
        Widget child = reference
            ? OutlinedButton.icon(
                key: _referenceKey,
                focusNode: referenceFocus,
                statesController: referenceStates,
                onPressed: _referenceCommand,
                icon: const StarBridgeIcon(StarBridgeIconSemantic.refresh),
                label: Text(label),
              )
            : OfficialFleetStatePanel(
                icon: StarBridgeIconSemantic.warning,
                titleKey: 'officialFleet.unavailable.title',
                bodyKey: 'officialFleet.error.transient',
                actionKey: 'officialFleet.action.retry',
                onAction: owner == 0 ? _first : _second,
              );
        if (competeForDrag) {
          child = GestureDetector(
            onPanUpdate: (_) {
              panUpdates++;
            },
            child: child,
          );
        }
        return Listener(
          onPointerDown: (event) {
            if (!holdArena) return;
            heldPointer = event.pointer;
            member = _PassiveMember(trace);
            // The child tap recognizer registers first. This second passive
            // member prevents close()'s single-member default win before up.
            passiveEntry = GestureBinding.instance.gestureArena.add(
              event.pointer,
              member!,
            );
            GestureBinding.instance.gestureArena.hold(event.pointer);
            trace.add('hold');
          },
          onPointerUp: (_) {
            trace.add('rawUp');
            scheduleMicrotask(() => trace.add('rawUpMicrotask'));
          },
          onPointerCancel: (_) {
            rawCancels++;
          },
          child: RepaintBoundary(key: _imageKey, child: child),
        );
      },
    ),
    suite,
    reduce: reduce,
    light: light,
  );

  @override
  void dispose() {
    releaseHeld();
    completePending();
    referenceFocus.dispose();
    referenceStates.dispose();
    super.dispose();
  }
}

Finder _native(_ProbeState p) =>
    find.byKey(p.reference ? _referenceKey : _nativeKey);
OutlinedButton _button(WidgetTester t, _ProbeState p) =>
    t.widget<OutlinedButton>(_native(p));

Future<void> _frames(WidgetTester t, [int count = 2]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

SemanticsNode _exposedButton(WidgetTester t, _ProbeState p) {
  final label = AppStrings.of(t.element(_native(p)))
      .text('officialFleet.action.retry');
  final nodes = exposedNodes(t).where((node) {
    final data = node.getSemanticsData();
    return data.label == label && data.flagsCollection.isButton;
  }).toList();
  expect(nodes, hasLength(1));
  expect(
    nodes.single.getSemanticsData().hasAction(ui.SemanticsAction.tap),
    true,
  );
  return nodes.single;
}

Future<void> _reader(WidgetTester t, _ProbeState p) async {
  final node = _exposedButton(t, p);
  t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
    node.id,
    ui.SemanticsAction.tap,
  );
  await _frames(t);
}

EffectHostState _effect(WidgetTester t) => t.state<EffectHostState>(
  find.descendant(
    of: find.byKey(_targetKey),
    matching: find.byType(EffectHost),
  ),
);
void _noEffects(WidgetTester t) {
  final fx = _effect(t);
  for (final effect in TransientEffect.values) {
    expect(fx.isPlaying(effect), false);
  }
}

Future<List<int>> _pixels(WidgetTester t) async => (await t.runAsync(() async {
  final box = t.renderObject<RenderRepaintBoundary>(find.byKey(_imageKey));
  final image = await box.toImage();
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return bytes.buffer
        .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes)
        .toList();
  } finally {
    image.dispose();
  }
}))!;

Future<void> _quiet(WidgetTester t) async {
  await _frames(t);
  _noEffects(t);
  final before = await _pixels(t);
  await _frames(t, 8);
  final after = await _pixels(t);
  expect(after.length, before.length);
  int? difference;
  for (var i = 0; i < before.length; i++) {
    if (before[i] != after[i]) {
      difference = i;
      break;
    }
  }
  expect(
    difference,
    isNull,
    reason: 'Keyboard/reader/reduce must leave no moving paint.',
  );
}

bool _differentPixels(List<int> a, List<int> b) {
  if (a.length != b.length) return true;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return true;
  }
  return false;
}

Future<_TrackedPointer> _down(WidgetTester t, _ProbeState p) async {
  final gesture = _TrackedPointer(
    await t.startGesture(t.getCenter(_native(p))),
    p.activePointers,
  );
  p.activePointers.add(
    gesture,
  ); // Register before the first assertion can fail.
  await t.pump(const Duration(milliseconds: 150));
  expect(_button(t, p).statesController!.value, contains(WidgetState.pressed));
  return gesture;
}

void _feedback(WidgetTester t, _ProbeState p) {
  if (p.suite == InteractionSuite.scan) {
    expect(_effect(t).isPlaying(TransientEffect.beam), true);
  } else if (p.suite == InteractionSuite.glow) {
    expect(_effect(t).isPlaying(TransientEffect.ring), true);
  }
}

Rect _semanticRect(SemanticsNode node) {
  var transform = Matrix4.identity();
  SemanticsNode? cursor = node;
  while (cursor != null) {
    if (cursor.transform != null) transform = cursor.transform! * transform;
    cursor = cursor.parent;
  }
  return MatrixUtils.transformRect(transform, node.rect);
}

Map<String, Object?> _facts(WidgetTester t, _ProbeState p) {
  final node = _exposedButton(t, p), data = node.getSemanticsData();
  final rect = t.getRect(_native(p));
  final flags = data.flagsCollection.toStrings()..sort();
  final render = t.renderObject<RenderBox>(_native(p));
  final points = [
    rect.center,
    Offset(rect.left + 1, rect.center.dy),
    Offset(rect.right - 1, rect.center.dy),
    Offset(rect.center.dx, rect.top + 1),
    Offset(rect.center.dx, rect.bottom - 1),
    rect.bottomRight + const Offset(4, 4),
  ];
  final hits = points
      .map(
        (point) => t
            .hitTestOnBinding(point)
            .path
            .any((entry) => identical(entry.target, render)),
      )
      .toList();
  expect(hits, [true, true, true, true, true, false]);
  return {
    'label': data.label,
    'value': data.value,
    'hint': data.hint,
    'flags': flags,
    'actions': data.actions,
    'direction': data.textDirection,
    'relativeRect': _semanticRect(node).shift(-rect.topLeft),
    'targetSize': rect.size,
    'hitResults': hits,
  };
}

void _case(
  String id,
  InteractionSuite suite,
  Future<void> Function(WidgetTester, _ProbeState) body, {
  bool reference = false,
}) {
  testWidgets('3gk native seam $id ${suite.name}', (t) async {
    final handle = t.ensureSemantics();
    final key = GlobalKey<_ProbeState>();
    size(t, const Size(1100, 1000));
    _ProbeState? mounted;
    try {
      await t.pumpWidget(_Probe(suite, key: key, reference: reference));
      await _frames(t, 4);
      final p = key.currentState!;
      mounted = p;
      await body(t, p);
      expect(t.takeException(), isNull);
    } finally {
      await mounted?.cancelActivePointers();
      mounted?.releaseHeld();
      mounted?.completePending();
      await t.pumpWidget(const SizedBox());
      await t.pump();
      handle.dispose();
    }
  });
}

Future<void> _heldTap(
  WidgetTester t,
  _ProbeState p, {
  required bool candidate,
}) async {
  p.change(() => p.holdArena = true);
  await _frames(t);
  final gesture = await _down(t, p);
  expect(p.commands, isEmpty);
  expect(p.member!.accepted, 0);
  expect(p.member!.rejected, 0);
  await gesture.up();
  await t.pump(); // Flush the raw-up microtask before releasing the arena.
  expect(p.trace, contains('rawUpMicrotask'));
  expect(
    p.commands,
    isEmpty,
    reason: 'Fixture must actually delay native onPressed.',
  );
  expect(_button(t, p).statesController!.value, contains(WidgetState.pressed));
  p.releaseHeld();
  await _frames(t);
  expect(p.commands, hasLength(1));
  expect(
    _button(t, p).statesController!.value,
    isNot(contains(WidgetState.pressed)),
  );
  expect(p.member!.accepted, 0);
  expect(p.member!.rejected, 1);
  expect(
    p.trace.indexOf('command'),
    greaterThan(p.trace.indexOf('releaseBegin')),
  );
  if (candidate) expect(p.commands.single.$2, InteractionSource.pointer);
  await _frames(t);
  expect(p.commands, hasLength(1));
}

void main() {
  setUpAll(loadFonts);
  // Positive controls first: fixture validity is distinct from candidate source.
  for (final suite in InteractionSuite.values) {
    _case(
      'N09-native-positive',
      suite,
      (t, p) => _heldTap(t, p, candidate: false),
      reference: true,
    );
  }
  for (final suite in InteractionSuite.values) {
    _case('N01-real-pointer-consumed-before-cleanup', suite, (t, p) async {
      final trace = <String>[];
      final states = _button(t, p).statesController!;
      var previousPressed = states.value.contains(WidgetState.pressed);
      void observe() {
        final pressed = states.value.contains(WidgetState.pressed);
        if (pressed == previousPressed) return;
        previousPressed = pressed;
        final event = pressed ? 'down' : 'notPressed';
        trace.add(event);
        p.trace.add(event);
      }

      states.addListener(observe);
      try {
        final gesture = await _down(t, p);
        _feedback(t, p);
        await gesture.up();
        await t.pump();
        expect(trace, contains('notPressed'));
        expect(
          p.trace.indexOf('notPressed'),
          lessThan(p.trace.indexOf('command')),
        );
        expect(p.commands, [(0, InteractionSource.pointer)]);
        await _frames(t);
        expect(p.commands, hasLength(1));
        await _reader(t, p);
        expect(p.commands, [
          (0, InteractionSource.pointer),
          (0, InteractionSource.keyboard),
        ]);
        await _quiet(t);
      } finally {
        states.removeListener(observe);
      }
    });

    _case('N02-drag-cancel-does-not-poison-reader-or-next-tap', suite, (
      t,
      p,
    ) async {
      p.change(() => p.competeForDrag = true);
      await _frames(t);
      final gesture = await _down(t, p);
      await gesture.moveBy(const Offset(0, 70));
      await _frames(t);
      // DragStartBehavior.start consumes the winning move as its origin.
      await gesture.moveBy(const Offset(0, 12));
      await _frames(t);
      expect(p.panUpdates, greaterThan(0));
      expect(
        p.rawCancels,
        0,
      ); // Cancellation comes from the arena, not raw cancel.
      expect(
        _button(t, p).statesController!.value,
        isNot(contains(WidgetState.pressed)),
      );
      await gesture.up();
      await _frames(t);
      expect(p.commands, isEmpty);
      await _reader(t, p);
      expect(p.commands, [(0, InteractionSource.keyboard)]);
      await _quiet(t);
      await t.tap(_native(p));
      await _frames(t);
      expect(p.commands, [
        (0, InteractionSource.keyboard),
        (0, InteractionSource.pointer),
      ]);
    });

    _case('N03-rapid-active-commands-never-coalesce-or-queue', suite, (
      t,
      p,
    ) async {
      p.holdFuture = true;
      final fx = _effect(t);
      for (var i = 0; i < 3; i++) {
        final before = await _pixels(t);
        final gesture = await _down(t, p);
        _feedback(t, p);
        await _frames(t);
        expect(
          _differentPixels(before, await _pixels(t)),
          true,
          reason: 'Every active press needs a visible cue, including Rail/Standard.',
        );
        expect(identical(_effect(t), fx), true);
        await gesture.up();
        await _frames(t);
        expect(p.commands, List.filled(i + 1, (0, InteractionSource.pointer)));
        expect(p.pending.isCompleted, false);
      }
      await _frames(t, 50);
      _noEffects(t);
      expect(t.binding.hasScheduledFrame, false);
      p.completePending();
      await _frames(t);
      expect(p.commands, hasLength(3));
    });

    _case('N04-reader-and-keyboard-interrupt-held-pointer-without-ink', suite, (
      t,
      p,
    ) async {
      for (final source in ['reader', 'keyboard']) {
        p.commands.clear();
        final gesture = await _down(t, p);
        _feedback(t, p);
        if (source == 'reader') {
          await _reader(t, p);
        } else {
          _button(t, p).focusNode!.requestFocus();
          await _frames(t);
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
        }
        expect(p.commands, [(0, InteractionSource.keyboard)]);
        await _quiet(t);
        await gesture.up();
        await _frames(t);
        // The still-native pending physical input is not a second reader input.
        expect(p.commands, [
          (0, InteractionSource.keyboard),
          (0, InteractionSource.pointer),
        ]);
        await t.tap(_native(p));
        await _frames(t);
        expect(p.commands.last, (0, InteractionSource.pointer));
      }
    });

    _case(
      'N05-live-reduce-keeps-native-recognizer-and-does-not-replay',
      suite,
      (t, p) async {
        final element = t.element(_native(p));
        final focus = _button(t, p).focusNode;
        final states = _button(t, p).statesController;
        final gesture = await _down(t, p);
        p.change(() => p.reduce = true);
        await _frames(t);
        expect(identical(t.element(_native(p)), element), true);
        expect(identical(_button(t, p).focusNode, focus), true);
        expect(identical(_button(t, p).statesController, states), true);
        await _quiet(t);
        await gesture.up();
        await _frames(t);
        expect(p.commands, [(0, InteractionSource.pointer)]);
        p.change(() => p.reduce = false);
        await _frames(t);
        _noEffects(t);
        final next = await _down(t, p);
        _feedback(t, p);
        await next.up();
        await _frames(t);
        expect(p.commands, List.filled(2, (0, InteractionSource.pointer)));
      },
    );

    _case('N06-real-focus-and-three-keyboard-keys-stay-static', suite, (
      t,
      p,
    ) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await _frames(t);
      final node = _exposedButton(t, p);
      expect(node.getSemanticsData().hasAction(ui.SemanticsAction.focus), true);
      t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        node.id,
        ui.SemanticsAction.focus,
      );
      await _frames(t);
      expect(_button(t, p).focusNode!.hasFocus, true);
      expect(p.commands, isEmpty);
      for (final key in [
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.numpadEnter,
      ]) {
        await t.sendKeyEvent(key);
        await _frames(t);
        expect(p.commands.last, (0, InteractionSource.keyboard));
        await _quiet(t);
      }
      expect(p.commands, List.filled(3, (0, InteractionSource.keyboard)));
    });

    _case('N07-native-exposed-facts-rect-and-hit-parity', suite, (t, p) async {
      for (final phase in ['idle', 'focus', 'pressed', 'cancelled']) {
        final observations = <Map<String, Object?>>[];
        for (final reference in [true, false]) {
          p.change(() => p.reference = reference);
          await _frames(t, 4);
          FocusManager.instance.primaryFocus?.unfocus();
          await _frames(t);
          if (phase == 'focus') {
            _button(t, p).focusNode!.requestFocus();
            await _frames(t);
          }
          _TrackedPointer? gesture;
          if (phase == 'pressed' || phase == 'cancelled') {
            gesture = await _down(t, p);
          }
          if (phase == 'cancelled') {
            await gesture!.cancel();
            gesture = null;
            await _frames(t, 12);
          }
          observations.add(_facts(t, p));
          if (gesture != null) {
            await gesture.cancel();
            await _frames(t, 12);
          }
        }
        expect(
          observations.last,
          observations.first,
          reason:
              'Compare facts/geometry/actions, never require native node ID.',
        );
      }
      expect(p.commands, isEmpty);
    });

    _case('N08-owner-theme-suite-and-unmount-preserve-input-owner', suite, (
      t,
      p,
    ) async {
      p.holdFuture = true;
      final element = t.element(_native(p));
      final focus = _button(t, p).focusNode;
      final states = _button(t, p).statesController;
      final gesture = await _down(t, p);
      p.change(() {
        p.light = !p.light;
        p.suite = InteractionSuite
            .values[(suite.index + 1) % InteractionSuite.values.length];
        p.owner = 1;
      });
      await _frames(t);
      expect(identical(t.element(_native(p)), element), true);
      expect(identical(_button(t, p).focusNode, focus), true);
      expect(identical(_button(t, p).statesController, states), true);
      _noEffects(t);
      await gesture.up();
      await _frames(t);
      expect(p.commands, [(1, InteractionSource.pointer)]);
      final cancelled = await _down(t, p);
      await t.pumpWidget(const SizedBox());
      await cancelled.cancel();
      p.completePending();
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await _frames(t, 50);
      expect(p.commands, [(1, InteractionSource.pointer)]);
      expect(t.binding.hasScheduledFrame, false);
    });

    _case(
      'N09-held-arena-retains-pointer-after-raw-up-microtask',
      suite,
      (t, p) => _heldTap(t, p, candidate: true),
    );
  }
}
