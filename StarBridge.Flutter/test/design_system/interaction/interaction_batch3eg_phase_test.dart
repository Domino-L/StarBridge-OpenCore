import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_connected_panel.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_controller.dart';

import 'interaction_batch3do_test.dart' show loadFonts, scopedApp, size;

/// Typed memory transport only. The real Controller and Panel retain request,
/// busy, admission and confirmation ownership. Each write awaits its receipt.
class _HeldPlay implements ContinuousPlayPort {
  ContinuousPlayValue stored = const ContinuousPlayValue(
    enabled: true,
    firstMinutes: 120,
    repeatMinutes: 120,
    revision: 4,
  );
  int reads = 0;
  final writes = <ContinuousPlayValue>[];
  final gates = <Completer<ContinuousPlayValue>>[];

  @override
  Future<ContinuousPlayValue> read() async {
    reads++;
    return stored;
  }

  @override
  Future<ContinuousPlayValue> save(ContinuousPlayValue desired) async {
    writes.add(desired);
    final gate = Completer<ContinuousPlayValue>();
    gates.add(gate);
    return stored = await gate.future;
  }

  ContinuousPlayValue receipt(int index) {
    final desired = writes[index];
    final result = ContinuousPlayValue(
      enabled: desired.enabled,
      firstMinutes: desired.firstMinutes,
      repeatMinutes: desired.repeatMinutes,
      revision: desired.revision + 1,
    );
    if (!gates[index].isCompleted) {
      gates[index].complete(result);
    }
    return result;
  }

  void releaseForCleanup() {
    for (var i = 0; i < gates.length; i++) {
      if (!gates[i].isCompleted) {
        receipt(i);
      }
    }
  }
}

Finder _row() => find.ancestor(
  of: find.byKey(const Key('notification-play-enabled')),
  matching: find.byType(StarBridgeSwitch),
);

Finder _busyFrame(Finder panel) =>
    find.descendant(of: panel, matching: find.byType(SuiteBusyFrame));

EffectHostState _publicBusyEffect(WidgetTester t, Finder frame) {
  final host = find.descendant(of: frame, matching: find.byType(EffectHost));
  expect(host, findsOneWidget);
  return t.state<EffectHostState>(host);
}

void _payload(
  ContinuousPlayValue value, {
  required bool enabled,
  required int revision,
}) {
  expect(value.enabled, enabled);
  expect(value.revision, revision);
  expect(value.firstMinutes, 120);
  expect(value.repeatMinutes, 120);
}

void main() {
  setUpAll(loadFonts);
  for (final scenario in const [
    (InteractionSuite.rail, TransientEffect.sweep),
    (InteractionSuite.scan, TransientEffect.bracketFlash),
    (InteractionSuite.glow, TransientEffect.pulse),
  ]) {
    final suite = scenario.$1;
    final completion = scenario.$2;
    testWidgets(
      '$suite Play second pointer save retires actual completion FX and keeps its new held wait dynamic',
      (t) async {
        size(t, const Size(1000, 850));
        final port = _HeldPlay();
        final owner = ContinuousPlayController(port);
        try {
          await t.pumpWidget(
            scopedApp(ContinuousPlayConnectedPanel(controller: owner), suite),
          );
          // Only the initial read and entrance are allowed to finish here.
          // Do not settle either of the controlled pending writes below.
          for (var i = 0; i < 12; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          final panel = find.byType(ContinuousPlayConnectedPanel);
          final row = _row();
          expect(panel, findsOneWidget);
          expect(row, findsOneWidget);
          expect(port.reads, 1);
          expect(port.writes, isEmpty);
          final confirmed = owner.value.settings!;
          _payload(confirmed, enabled: true, revision: 4);
          expect(owner.value.busy, isFalse);
          expect(t.widget<StarBridgeSwitch>(row).value, isTrue);
          expect(t.widget<StarBridgeSwitch>(row).onChanged, isNotNull);

          // Hit the real single row target, not the inert decorative key.
          await t.ensureVisible(row);
          await t.pump();
          await t.tap(row);
          await t.pump();
          expect(port.writes, hasLength(1));
          expect(port.gates.single.isCompleted, isFalse);
          _payload(port.writes.single, enabled: false, revision: 4);
          expect(owner.value.settings, same(confirmed));
          expect(owner.value.busy, isTrue);
          expect(port.reads, 1);

          final firstReceipt = port.receipt(0);
          await t.pump();
          await t.pump(const Duration(milliseconds: 16));
          expect(owner.value.settings, same(firstReceipt));
          _payload(owner.value.settings!, enabled: false, revision: 5);
          expect(owner.value.busy, isFalse);
          expect(owner.value.failed, isFalse);
          expect(t.widget<StarBridgeSwitch>(row).value, isFalse);
          expect(t.widget<StarBridgeSwitch>(row).onChanged, isNotNull);
          final frame = _busyFrame(panel);
          expect(frame, findsOneWidget);
          final completedEffect = _publicBusyEffect(t, frame);
          expect(
            completedEffect.isPlaying(completion),
            isTrue,
            reason:
                'Prerequisite: actual $completion is playing after the first receipt, not just a changed token.',
          );
          expect(InteractionScope.of(t.element(frame)).animates, isTrue);

          // The completion is still running. A second real pointer activation
          // must reach the same owner and held typed port without auto replay.
          await t.tap(row);
          await t.pump();
          await t.pump(const Duration(milliseconds: 16));
          expect(port.writes, hasLength(2));
          expect(port.gates[0].isCompleted, isTrue);
          expect(port.gates[1].isCompleted, isFalse);
          _payload(port.writes[1], enabled: true, revision: 5);
          expect(port.reads, 1);
          expect(owner.value.settings, same(firstReceipt));
          expect(owner.value.busy, isTrue);
          expect(owner.value.failed, isFalse);
          expect(t.widget<StarBridgeSwitch>(row).value, isFalse);
          expect(t.widget<StarBridgeSwitch>(row).onChanged, isNull);
          expect(
            t.widget<ContinuousPlayConnectedPanel>(panel).controller,
            same(owner),
          );

          expect(frame, findsOneWidget);
          expect(t.widget<SuiteBusyFrame>(frame).busy, isTrue);
          final data = InteractionScope.of(t.element(frame));
          expect(data.suite, suite);
          expect(data.reduceMotion, isFalse);
          expect(data.animates, isTrue);
          expect(TickerMode.valuesOf(t.element(frame)).enabled, isTrue);
          final labels = find.descendant(
            of: panel,
            matching: find.byType(SuiteBusyLabel),
          );
          expect(labels, findsOneWidget);
          expect(InteractionScope.of(t.element(labels)).suite, suite);
          expect(InteractionScope.of(t.element(labels)).animates, isTrue);
          final currentEffect = _publicBusyEffect(t, frame);
          expect(
            currentEffect.isPlaying(completion),
            isFalse,
            reason: 'The previous completion must not remain over a new pending save.',
          );
          if (suite == InteractionSuite.scan) {
            expect(currentEffect.isPlaying(TransientEffect.scanLine), isFalse);
          }
          // Accept phase remounting or explicit cancellation. Do not require a
          // particular key, private state, or retained-host implementation.
          if (completedEffect.mounted) {
            expect(
              completedEffect.isPlaying(completion),
              isFalse,
              reason:
                  'A retained previous host must retire its old effect too.',
            );
          }
          expect(
            t.binding.hasScheduledFrame,
            isTrue,
            reason:
                'Keep current waiting feedback; reduced motion is not a fix.',
          );
          expect(t.takeException(), isNull);

          final secondReceipt = port.receipt(1);
          await t.pump();
          await t.pump(const Duration(milliseconds: 16));
          expect(owner.value.settings, same(secondReceipt));
          _payload(owner.value.settings!, enabled: true, revision: 6);
          expect(owner.value.busy, isFalse);
          expect(owner.value.failed, isFalse);
          expect(port.reads, 1);
          expect(port.writes, hasLength(2));
          expect(t.takeException(), isNull);
        } finally {
          port.releaseForCleanup();
          await t.pump();
          await t.pumpWidget(const SizedBox.shrink());
          owner.dispose();
        }
      },
    );
  }
}
