import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_save_module.dart';

void main() {
  test(
    'requires explicit empty confirmation and ignores duplicate presses',
    () async {
      final pending = Completer<LocalHangarSnapshot>();
      final port = SaveFake()..pending = pending;
      final module = LocalHangarSaveModule(port, 'scan', 0);
      await module.refresh();
      await module.save();
      expect(port.writes, 0);
      final saving = module.save(confirmEmpty: true);
      await module.save(confirmEmpty: true);
      expect(port.writes, 1);
      pending.complete(
        const LocalHangarSnapshot(revision: 5, operationId: 'scan', ships: []),
      );
      await saving;
      expect(module.phase, 'saved');
      module.dispose();
    },
  );
  test('disposing the account hides a late save response', () async {
    final pending = Completer<LocalHangarSnapshot>();
    final port = SaveFake()..pending = pending;
    final module = LocalHangarSaveModule(port, 'scan', 1);
    await module.refresh();
    var changes = 0;
    module.addListener(() => changes++);
    final saving = module.save();
    final before = changes;
    module.dispose();
    pending.complete(
      const LocalHangarSnapshot(revision: 5, operationId: 'scan', ships: []),
    );
    await saving;
    expect(changes, before);
  });
  test('loads existing revision, saves only after confirmation and reads lost receipt', () async {
    final port = SaveFake();
    final module = LocalHangarSaveModule(port, 'scan', 1);
    await module.refresh();
    expect(port.writes, 0);
    expect(module.current?.revision, 4);
    await module.save();
    expect(port.writes, 1);
    expect(module.phase, 'uncertain');
    await module.refresh();
    expect(module.phase, 'saved');
    expect(port.writes, 1);
    module.dispose();
  });
}

class SaveFake implements LocalHangarPort {
  int writes = 0;
  Completer<LocalHangarSnapshot>? pending;
  LocalHangarSnapshot snapshot = const LocalHangarSnapshot(
    revision: 4,
    ships: [],
  );
  @override
  Future<LocalHangarSnapshot> read() async => snapshot;
  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) async {
    expect(expectedRevision, 4);
    writes++;
    if (pending != null) return pending!.future;
    snapshot = LocalHangarSnapshot(
      revision: 5,
      operationId: operationId,
      ships: const [],
    );
    throw TimeoutException('synthetic lost reply');
  }
}
