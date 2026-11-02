import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_port.dart';

void main() {
  test('a throwing read releases busy state so a later refresh can run', () async {
    final port = _ThrowingPort()..throwNext = true;
    final module = createPersonalProfileModule(port);
    addTearDown(module.dispose);
    // Continue past the old escaping exception to check the stuck-busy failure.
    try {
      await module.initialize();
    } on StateError {
      // The module must also contain this failure after the fix.
    }
    final retry = await module.refresh();
    expect(port.reads, 2);
    expect(retry.outcome, PersonalProfileActionOutcome.completed);
    expect(module.projection.value.operation, PersonalProfileOperation.none);
  });

  test('a failed read still drains a queued account invalidation', () async {
    final port = _ThrowingPort();
    final pending = Completer<PersonalProfileSnapshot>();
    port.pending = pending;
    final module = createPersonalProfileModule(port);
    addTearDown(module.dispose);
    final reading = module.initialize();
    port.pending = null;
    port.events.add(null);
    final completion = expectLater(reading, completes);
    pending.completeError(StateError('synthetic read failure'));
    await completion;
    await Future<void>.delayed(Duration.zero);
    expect(port.reads, 2);
    expect(module.projection.value.operation, PersonalProfileOperation.none);
  });

  test('a read failing after disposal does not escape or publish a value', () async {
    final port = _ThrowingPort();
    final pending = Completer<PersonalProfileSnapshot>();
    port.pending = pending;
    final module = createPersonalProfileModule(port);
    final reading = module.initialize();
    var publications = 0;
    module.projection.addListener(() => publications++);
    module.dispose();
    final completion = expectLater(reading, completes);
    pending.completeError(StateError('synthetic late read failure'));
    await completion;
    expect(publications, 0);
    expect(port.reads, 1);
  });
}

final class _ThrowingPort implements PersonalProfilePort {
  final events = StreamController<void>.broadcast(sync: true);
  bool throwNext = false;
  int reads = 0;
  Completer<PersonalProfileSnapshot>? pending;

  @override
  Stream<void> get invalidations => events.stream;

  @override
  Future<PersonalProfileSnapshot> read() {
    reads++;
    if (throwNext) {
      throwNext = false;
      throw StateError('synthetic synchronous read failure');
    }
    return pending?.future ??
        Future.value(const PersonalProfileSnapshot.unavailable());
  }

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) async =>
      const PersonalProfileActionResult(PersonalProfileActionOutcome.rejected);

  @override
  Future<void> close() => events.close();
}
