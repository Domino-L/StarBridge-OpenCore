import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/coalesced_read.dart';

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late CoalescedRead reads;
  late List<Completer<void>> gates;
  Future<void> round() {
    final gate = Completer<void>();
    gates.add(gate);
    return gate.future;
  }

  Future<void> request() =>
      reads.run(round, current: () => true, allowed: () => true);

  setUp(() {
    reads = CoalescedRead();
    gates = [];
  });

  test(
    'requests that keep arriving never hold back an earlier waiter',
    () async {
      var starterDone = false;
      unawaited(request().then((_) => starterDone = true));
      await _settle();
      expect(gates, hasLength(1));
      // Every round gets a new request, the way the editor timer does when a
      // read outlasts its 15-second period.
      final done = <bool>[];
      for (var index = 0; index < 10; index++) {
        final waiter = done.length;
        done.add(false);
        unawaited(request().then((_) => done[waiter] = true));
        await _settle();
        gates[index].complete();
        await _settle();
        if (index == 0) expect(starterDone, isTrue);
        expect(gates, hasLength(index + 2), reason: 'One shared follow-up.');
        expect(done[waiter], isFalse, reason: 'It waits for its follow-up.');
        if (waiter > 0) {
          expect(
            done[waiter - 1],
            isTrue,
            reason: 'Released after exactly one follow-up round.',
          );
        }
      }
      gates.last.complete();
      await _settle();
      expect(done, everyElement(isTrue));
      expect(reads.active, isFalse);
      expect(gates, hasLength(11), reason: 'No round without a request.');
    },
  );

  test('several requests in one round share one follow-up', () async {
    unawaited(request());
    await _settle();
    var released = 0;
    for (var i = 0; i < 4; i++) {
      unawaited(request().then((_) => released++));
    }
    gates[0].complete();
    await _settle();
    expect(gates, hasLength(2));
    gates[1].complete();
    await _settle();
    expect(released, 4);
    expect(gates, hasLength(2));
    expect(reads.active, isFalse);
  });

  test('retire releases every waiter and starts no follow-up', () async {
    var first = false, next = false;
    unawaited(request().then((_) => first = true));
    await _settle();
    unawaited(request().then((_) => next = true));
    reads.retire();
    await _settle();
    expect(first && next, isTrue);
    expect(reads.active, isFalse);
    gates[0].complete(); // The retired read returns late.
    await _settle();
    expect(gates, hasLength(1));
  });

  test('a follow-up stops when the owner no longer allows it', () async {
    var allowed = true, released = false;
    unawaited(reads.run(round, current: () => true, allowed: () => allowed));
    await _settle();
    unawaited(
      reads
          .run(round, current: () => true, allowed: () => allowed)
          .then((_) => released = true),
    );
    allowed = false;
    gates[0].complete();
    await _settle();
    expect(released, isTrue);
    expect(gates, hasLength(1));
    expect(reads.active, isFalse);
  });
}
