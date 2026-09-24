import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/hangar/cached_local_hangar.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';

const old = LocalHangarSnapshot(
  revision: 1,
  ships: [LocalHangarShip(id: 'old', title: 'Old')],
);
const saved = LocalHangarSnapshot(
  revision: 2,
  ships: [],
  formerShips: [LocalHangarShip(id: 'old', title: 'Old')],
);
void main() {
  test(
    'deduplicates in-flight reads and caches a complete empty snapshot',
    () async {
      final source = _Source();
      final cache = CachedLocalHangar(source, isCurrent: () => true);
      final first = cache.read();
      final second = cache.read();
      expect(identical(first, second), isTrue);
      expect(source.reads, hasLength(1));
      source.reads.single.complete(saved);
      expect(await first, same(saved));
      expect(cache.snapshot, same(saved));
      final refresh = cache.read();
      expect(source.reads, hasLength(2));
      source.reads.last.completeError(StateError('offline'));
      await expectLater(refresh, throwsStateError);
      expect(cache.snapshot, same(saved));
    },
  );
  test(
    'save publishes inventory and history; older reads cannot roll it back',
    () async {
      final source = _Source();
      final cache = CachedLocalHangar(source, isCurrent: () => true);
      final late = cache.read();
      final writing = cache.save('scan', 1, confirmEmpty: true);
      source.write.complete(saved);
      expect(await writing, same(saved));
      expect(source.confirmEmpty, isTrue);
      source.reads.single.complete(old);
      expect(await late, same(saved));
      expect(cache.snapshot, same(saved));
      expect(cache.snapshot!.formerShips, hasLength(1));
    },
  );
  test('account invalidation hides the cache and rejects late responses and writes', () async {
    var current = true;
    final source = _Source();
    final cache = CachedLocalHangar(source, isCurrent: () => current);
    final first = cache.read();
    source.reads.single.complete(old);
    await first;
    final late = cache.read();
    current = false;
    expect(cache.snapshot, isNull);
    source.reads.last.complete(saved);
    await expectLater(late, throwsA(isA<LocalHangarFailure>()));
    await expectLater(
      cache.save('scan', 1),
      throwsA(isA<LocalHangarFailure>()),
    );
    expect(source.writes, 0);
    expect(cache.snapshot, isNull);
  });
}

class _Source implements LocalHangarPort {
  final reads = <Completer<LocalHangarSnapshot>>[];
  final write = Completer<LocalHangarSnapshot>();
  var writes = 0, confirmEmpty = false;
  @override
  Future<LocalHangarSnapshot> read() {
    final result = Completer<LocalHangarSnapshot>();
    reads.add(result);
    return result.future;
  }

  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) {
    writes++;
    this.confirmEmpty = confirmEmpty;
    return write.future;
  }
}
