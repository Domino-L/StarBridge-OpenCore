import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_avatar_cache.dart';
import 'package:starbridge_flutter/features/communities/community_ships_controller.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';

import 'community_ships_test.dart' show shipRow;
import 'community_workspace_test.dart' show WorkspaceTestPort, mediaChunk;

class _Port extends WorkspaceTestPort implements CommunityShipsPort {
  int reads = 0;
  String? avatarVersion;
  Uint8List bytes = Uint8List.fromList([1]);
  @override
  bool get shipsAvailable => true;
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async => CommunityShipsPage.parse({
    'schemaVersion': 1,
    'queryVersion': 2,
    'query': (query ?? CommunityShipQuery()).toPayload(),
    'targetRef': targetRef,
    'revision': 'b' * 64,
    'offset': 0,
    'next': null,
    'totalCount': 1,
    'matchedCount': 1,
    'ships': [shipRow()..['ownerAvatarVersion'] = avatarVersion],
  });
  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) async {
    reads++;
    return mediaChunk(bytes, offset, kind: kind, memberRef: memberRef);
  }
}

void main() {
  for (final version in <String?>[null, '']) {
    test(
      'unversioned avatar $version expires after completion; joins in-flight IO',
      () async {
        var now = DateTime.utc(2026, 11, 2), reads = 0;
        final cache = CommunityAvatarCache(now: () => now);
        addTearDown(cache.dispose);
        final gate = Completer<Uint8List?>();
        Future<Uint8List?> read() {
          reads++;
          return gate.future;
        }

        final first = cache.get('member', version, read);
        now = now.add(const Duration(minutes: 2));
        final joined = cache.get('member', version, read);
        expect(reads, 1);
        gate.complete(Uint8List.fromList([1]));
        expect(await first, [1]);
        expect(await joined, [1]);
        now = now.add(const Duration(seconds: 59));
        expect(cache.isFresh('member', version), isTrue);
        expect(await cache.get('member', version, read), [1]);
        now = now.add(const Duration(seconds: 1));
        expect(cache.isFresh('member', version), isFalse);
        expect(
          await cache.get('member', version, () async {
            reads++;
            return Uint8List.fromList([2]);
          }),
          [2],
        );
        expect(reads, 2);
      },
    );
  }

  test(
    'versioned portraits survive time; clear rejects a pending old scope',
    () async {
      var now = DateTime.utc(2026, 11, 2), reads = 0;
      final cache = CommunityAvatarCache(now: () => now);
      addTearDown(cache.dispose);
      Future<Uint8List?> read() async {
        reads++;
        return Uint8List.fromList([1]);
      }

      await cache.get('member', 'version', read);
      now = now.add(const Duration(days: 1));
      await cache.get('member', 'version', read);
      expect(reads, 1);
      final gate = Completer<Uint8List?>();
      final pending = cache.get('other', null, () => gate.future);
      final rejected = expectLater(pending, throwsStateError);
      cache.clear();
      gate.complete(Uint8List.fromList([2]));
      await rejected;
      expect(cache.isFresh('member', 'version'), isFalse);
    },
  );

  for (final version in <String?>[null, 'c' * 64]) {
    test(
      'unchanged ship revision refreshes expired unversioned owners: $version',
      () async {
        var now = DateTime.utc(2026, 11, 2);
        final port = _Port()..avatarVersion = version;
        final model = CommunityShipsController(
          port,
          'a' * 32,
          mediaPort: port,
          now: () => now,
        );
        addTearDown(model.dispose);
        await model.load();
        expect(port.reads, 1);
        now = now.add(const Duration(seconds: 59));
        await model.refreshVisible();
        expect(port.reads, 1);
        now = now.add(const Duration(seconds: 1));
        port.bytes = Uint8List.fromList([2]);
        await model.refreshVisible();
        expect(port.reads, version == null ? 2 : 1);
        expect(model.avatar('d' * 32), version == null ? [2] : [1]);
        model.invalidate();
        expect(model.avatar('d' * 32), isNull);
      },
    );
  }
}
