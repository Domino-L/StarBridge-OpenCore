import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_avatar_cache.dart';

void main() {
  test(
    'a failed versioned avatar retries after a bounded negative cache',
    () async {
      var now = DateTime.utc(2026, 10, 17), reads = 0;
      final cache = CommunityAvatarCache(now: () => now);
      addTearDown(cache.dispose);
      final bytes = Uint8List.fromList([1]);
      Future<Uint8List?> read() async {
        reads++;
        if (reads == 1) throw StateError('temporary fixture failure');
        return bytes;
      }

      await expectLater(cache.get('member', 'version', read), throwsStateError);
      now = now.add(const Duration(milliseconds: 9999));
      await expectLater(cache.get('member', 'version', read), throwsStateError);
      expect(reads, 1);
      now = now.add(const Duration(milliseconds: 1));
      expect(await cache.get('member', 'version', read), same(bytes));
      expect(reads, 2);
    },
  );

  test(
    'the read queue is bounded even while cache entries are evicted',
    () async {
      final gate = Completer<Uint8List?>();
      var reads = 0, now = DateTime.utc(2026, 10, 17);
      final cache = CommunityAvatarCache(now: () => now);
      addTearDown(cache.dispose);
      final requests = <Future<bool>>[];
      for (var i = 0; i < 200; i++) {
        requests.add(
          cache
              .get('member-$i', 'version', () {
                reads++;
                return gate.future;
              })
              .then((_) => true, onError: (Object _) => false),
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(
        reads,
        3,
        reason: 'Only the existing three physical read slots may enter.',
      );
      gate.complete(Uint8List.fromList([1]));
      final results = await Future.wait(requests)
          .timeout(const Duration(seconds: 5));
      expect(
        reads,
        96,
        reason: 'Evicting a map entry must not permit unbounded queued read closures.',
      );
      expect(results.where((value) => value), hasLength(96));
      expect(results.where((value) => !value), hasLength(104));
      now = now.add(const Duration(seconds: 10));
      expect(
        await cache.get('member-199', 'version', () async {
          reads++;
          return Uint8List.fromList([2]);
        }),
        [2],
      );
      expect(
        reads,
        97,
        reason: 'Backpressure must recover once the queue has drained.',
      );
    },
  );

  test(
    'explicit retry bypasses negative backoff, successful versions stay cached',
    () async {
      var now = DateTime.utc(2026, 10, 17), reads = 0;
      final cache = CommunityAvatarCache(now: () => now);
      addTearDown(cache.dispose);
      final bytes = Uint8List.fromList([1]);
      Future<Uint8List?> read() async {
        if (++reads == 1) throw StateError('fixture failure');
        return bytes;
      }

      await expectLater(cache.get('member', 'v1', read), throwsStateError);
      expect(await cache.get('member', 'v1', read, retry: true), same(bytes));
      now = now.add(const Duration(days: 1));
      expect(await cache.get('member', 'v1', read), same(bytes));
      expect(reads, 2);
      await cache.get('member', 'v2', read);
      await cache.get('other', 'v1', read);
      expect(reads, 4, reason: 'Identity and version keys remain distinct.');
    },
  );

  test(
    'late old failure does not expire a successful explicit retry',
    () async {
      var now = DateTime.utc(2026, 10, 17), reads = 0;
      final cache = CommunityAvatarCache(now: () => now),
          old = Completer<Uint8List?>();
      addTearDown(cache.dispose);
      final bytes = Uint8List.fromList([1]);
      Future<Uint8List?> read() {
        reads++;
        return reads == 1 ? old.future : Future.value(bytes);
      }

      final failed = expectLater(
        cache.get('member', 'v1', read),
        throwsStateError,
      );
      expect(await cache.get('member', 'v1', read, retry: true), same(bytes));
      old.completeError(StateError('late fixture failure'));
      await failed;
      now = now.add(const Duration(seconds: 11));
      expect(await cache.get('member', 'v1', read), same(bytes));
      expect(reads, 2);
    },
  );

  test('expired concurrent retries still share one physical read', () async {
    var now = DateTime.utc(2026, 10, 17), reads = 0;
    final cache = CommunityAvatarCache(now: () => now),
        ready = Completer<Uint8List?>();
    addTearDown(cache.dispose);
    Future<Uint8List?> read() {
      if (++reads == 1) return Future.error(StateError('fixture failure'));
      return ready.future;
    }

    await expectLater(cache.get('member', 'v1', read), throwsStateError);
    now = now.add(const Duration(seconds: 10));
    final a = cache.get('member', 'v1', read),
        b = cache.get('member', 'v1', read);
    expect(identical(a, b), isTrue);
    expect(reads, 2);
    ready.complete(Uint8List.fromList([1]));
    expect(await a, [1]);
    expect(await b, [1]);
  });

  test(
    'clearing a saturated scope skips queued IO and rejects all late bytes',
    () async {
      final cache = CommunityAvatarCache(), gate = Completer<Uint8List?>();
      addTearDown(cache.dispose);
      var reads = 0;
      final requests = <Future<bool>>[];
      for (var i = 0; i < 120; i++) {
        requests.add(
          cache
              .get('member-$i', 'v1', () {
                reads++;
                return gate.future;
              })
              .then((_) => true, onError: (Object _) => false),
        );
      }
      expect(reads, 3);
      cache.clear();
      gate.complete(Uint8List.fromList([1]));
      final results = await Future.wait(requests)
          .timeout(const Duration(seconds: 5));
      expect(results.every((value) => !value), isTrue);
      expect(
        reads,
        3,
        reason: 'Queued work from the retired scope must never enter its read closure.',
      );
      expect(
        await cache.get(
          'new-member',
          'v1',
          () async => Uint8List.fromList([2]),
        ),
        [2],
      );
    },
  );

  test('reference renewal discards failure metadata without expiring later success', () async {
    var now = DateTime.utc(2026, 10, 17), reads = 0;
    final cache = CommunityAvatarCache(now: () => now);
    addTearDown(cache.dispose);
    Future<Uint8List?> read() async {
      if (++reads == 1) throw StateError('fixture failure');
      return Uint8List.fromList([1]);
    }

    await expectLater(cache.get('member', 'v1', read), throwsStateError);
    cache.retainCompleted();
    expect(await cache.get('member', 'v1', read), [1]);
    now = now.add(const Duration(seconds: 11));
    expect(await cache.get('member', 'v1', read), [1]);
    expect(reads, 2);
  });
}
