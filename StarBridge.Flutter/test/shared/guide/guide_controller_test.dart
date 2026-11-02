import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/shared/guide/guide_controller.dart';
import 'package:starbridge_flutter/shared/guide/guide_scope.dart';
import 'package:starbridge_flutter/shared/guide/guide_state.dart';

/// Host stand-in with one store per profile and reads the test releases.
final class _Port implements GuideStatePort {
  final stores = <String, GuideState>{
    'a': const GuideState(available: true, eligible: true),
    'b': const GuideState(available: true),
  };
  String? profile = 'a';
  final pendingReads = <(GuideState, Completer<GuideState>)>[];
  final updates = <(String?, List<Map<String, Object?>>)>[];
  bool holdReads = false;
  bool failReads = false;

  @override
  bool get supported => true;

  @override
  Future<GuideState> read() {
    if (failReads) return Future.error(StateError('Host down'));
    final value = stores[profile] ?? GuideState.unavailable;
    if (!holdReads) return SynchronousFuture(value);
    // The snapshot is fixed when the read starts, like a real Host reply
    // that was produced before later writes landed.
    final completer = Completer<GuideState>();
    pendingReads.add((value, completer));
    return completer.future;
  }

  void releaseReads() {
    for (final (snapshot, completer) in pendingReads) {
      completer.complete(snapshot);
    }
    pendingReads.clear();
  }

  /// With [holdUpdates], Host applies each write at once (in order, like
  /// the real dispatcher) but the reply waits for [replyUpdate].
  bool holdUpdates = false;
  final failing = <String>{};
  final pendingUpdates = <(Completer<GuideState>, GuideState?, Object?)>[];

  @override
  Future<GuideState> update(List<GuideOp> ops) {
    updates.add((profile, [for (final op in ops) op.toWire()]));
    final id = ops.first.toWire()['id'];
    Object? error;
    GuideState? state;
    if (failing.contains(id)) {
      error = StateError('write failed');
    } else {
      state = stores[profile]!;
      for (final op in ops) {
        state = state!.apply(op);
      }
      stores[profile!] = state!;
    }
    if (!holdUpdates) {
      return error == null ? Future.value(state) : Future.error(error);
    }
    final completer = Completer<GuideState>();
    pendingUpdates.add((completer, state, error));
    return completer.future;
  }

  void replyUpdate(int index) {
    final (completer, state, error) = pendingUpdates[index];
    error == null ? completer.complete(state) : completer.completeError(error);
  }
}

void main() {
  late _Port port;
  late ValueNotifier<int> context;
  late GuideController controller;
  setUp(() {
    port = _Port();
    context = ValueNotifier(0);
    controller = GuideController(port, reload: context);
  });
  tearDown(() {
    controller.dispose();
    context.dispose();
  });

  void switchTo(String? profile) {
    port.profile = profile;
    context.value++;
  }

  test('a context switch hides the old state at once', () async {
    await pumpEventQueue();
    expect(controller.value.eligible, isTrue);
    port.holdReads = true;
    switchTo('b');
    expect(
      controller.value.available,
      isFalse,
      reason: 'no stale profile shown',
    );
    controller.markSeen('tip.fleet');
    expect(port.updates, isEmpty, reason: 'no write before the new read');
    port.releaseReads();
    await pumpEventQueue();
    expect(controller.value.available, isTrue);
    expect(controller.value.eligible, isFalse, reason: "now b's own state");
  });

  test('a slow read from the old context never lands in the new one', () async {
    await pumpEventQueue();
    port.holdReads = true;
    unawaited(controller.refresh()); // read for a, held
    switchTo('b'); // read for b, held
    port.pendingReads.first.$2.complete(port.stores['a']!);
    await pumpEventQueue();
    expect(
      controller.value.available,
      isFalse,
      reason: "a's late reply dropped",
    );
    port.pendingReads.removeAt(0);
    port.releaseReads();
    await pumpEventQueue();
    expect(controller.value.eligible, isFalse);
  });

  test('an older read snapshot never undoes a newer local edit', () async {
    await pumpEventQueue();
    controller.markSeen('tip.rooms');
    await pumpEventQueue();
    port.holdReads = true;
    unawaited(controller.refresh()); // snapshot: tip.rooms only
    controller.markSeen('tip.fleet'); // its write and reply finish first
    await pumpEventQueue();
    expect(port.stores['a']!.seen, contains('tip.fleet'));
    port.releaseReads(); // the old snapshot returns last
    await pumpEventQueue();
    expect(controller.value.seen, containsAll(['tip.rooms', 'tip.fleet']));
  });

  for (final failFirst in [true, false]) {
    for (final readLast in [true, false]) {
      test(
        'first write fails, second succeeds: replies '
        '${failFirst ? 'fail→ok' : 'ok→fail'}, read ${readLast ? 'last' : 'first'}',
        () async {
          await pumpEventQueue();
          port.holdUpdates = true;
          port.holdReads = true;
          port.failing.add('tip.rooms');
          controller.markSeen('tip.rooms'); // 0: fails
          controller.markSeen('tip.fleet'); // 1: succeeds
          unawaited(controller.refresh()); // snapshot after both writes
          if (!readLast) {
            port.releaseReads();
            await pumpEventQueue();
          }
          port.replyUpdate(failFirst ? 0 : 1);
          await pumpEventQueue();
          port.replyUpdate(failFirst ? 1 : 0);
          await pumpEventQueue();
          if (readLast) {
            port.releaseReads();
            await pumpEventQueue();
          }
          // One fixed outcome whatever the order: the saved edit is in Host,
          // the failed one stays local for this session and is not resent.
          expect(controller.value.seen, {'tip.rooms', 'tip.fleet'});
          expect(port.stores['a']!.seen, {'tip.fleet'});
          expect(port.updates, hasLength(2));
        },
      );
    }
  }

  test('many edits during one slow read are all kept', () async {
    await pumpEventQueue();
    port.holdReads = true;
    unawaited(controller.refresh()); // old snapshot, returns last
    for (var i = 0; i < 70; i++) {
      controller.markDone(i.isEven ? 'a$i' : 'b$i');
      if (i % 10 == 9) controller.resetChecklist();
      controller.markSeen('tip.n$i');
    }
    await pumpEventQueue();
    port.releaseReads();
    await pumpEventQueue();
    // No count-based trimming: every edit survives the old snapshot.
    expect(controller.value.seen, {for (var i = 0; i < 70; i++) 'tip.n$i'});
    expect(controller.value.done, port.stores['a']!.done);
  });

  test('a failed read after a switch keeps everything hidden', () async {
    await pumpEventQueue();
    port.failReads = true;
    switchTo('b');
    await pumpEventQueue();
    expect(controller.value.available, isFalse);
    controller.markDone('hangar');
    expect(port.updates, isEmpty);
  });

  test(
    'refresh(then) writes only to the profile that read installed',
    () async {
      port.stores['c'] = const GuideState(available: true);
      port.holdReads = true;
      port.profile = 'c';
      unawaited(controller.refresh(then: [const GuideOp.markEligible()]));
      switchTo('b'); // the user moves on before the read returns
      port.releaseReads();
      await pumpEventQueue();
      expect(
        port.stores['c']!.eligible,
        isFalse,
        reason: 'dropped with its context',
      );
      expect(
        port.stores['b']!.eligible,
        isFalse,
        reason: 'never sent elsewhere',
      );
      port.holdReads = false;
      port.profile = 'c';
      await controller.refresh(then: [const GuideOp.markEligible()]);
      await pumpEventQueue();
      expect(port.stores['c']!.eligible, isTrue);
    },
  );

  test('idempotent no-ops never reach Host', () async {
    await pumpEventQueue();
    controller.markSeen('tip.fleet');
    controller.markSeen('tip.fleet');
    controller.markEligible(); // already eligible
    await pumpEventQueue();
    expect(port.updates, hasLength(1));
  });

  testWidgets('a queued automatic start is re-checked when it runs', (
    tester,
  ) async {
    await tester.pumpAndSettle();
    final hub = GuideHub(
      controller: controller,
      online: ValueNotifier(true),
      navigate: (_) {},
    );
    addTearDown(hub.dispose);
    port.holdReads = true;
    hub.visit('/marketplace'); // queues the market tour for the next frame
    switchTo('b'); // before it runs, the profile changes
    await tester.pump();
    port.releaseReads();
    await tester.pumpAndSettle();
    expect(hub.run.value, isNull, reason: 'b is not eligible; a never starts');
  });

  testWidgets('a queued do-it start dies with a failed read', (tester) async {
    await tester.pumpAndSettle();
    final hub = GuideHub(
      controller: controller,
      online: ValueNotifier(true),
      navigate: (_) {},
    );
    addTearDown(hub.dispose);
    hub.visit('/rooms');
    hub.report('rooms.formOpened'); // queued start
    port.failReads = true;
    switchTo('a'); // same profile, but its read now fails
    await tester.pumpAndSettle();
    expect(hub.run.value, isNull);
  });

  testWidgets('switching profiles ends a running tour', (tester) async {
    await tester.pumpAndSettle();
    final hub = GuideHub(
      controller: controller,
      online: ValueNotifier(true),
      navigate: (_) {},
    );
    addTearDown(hub.dispose);
    hub.start('market');
    expect(hub.run.value, isNotNull);
    port.holdReads = true;
    switchTo(null); // signed out
    expect(hub.run.value, isNull);
    port.releaseReads();
    await tester.pumpAndSettle();
    expect(hub.run.value, isNull);
  });
}
