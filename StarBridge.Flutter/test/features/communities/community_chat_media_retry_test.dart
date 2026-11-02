import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_avatar_cache.dart';
import 'package:starbridge_flutter/features/communities/community_chat_media_cache.dart';

import 'community_chat_media_cache_test.dart' show MediaPort, message;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('expired avatar retry reaches a new detail read instead of the old failed future', () async {
    var now = DateTime.utc(2026, 10, 17);
    final port = MediaPort()..fail = true;
    final avatars = CommunityAvatarCache(now: () => now);
    final cache = CommunityChatMediaCache(port, 'a' * 32, avatars: avatars);
    addTearDown(cache.dispose);
    addTearDown(avatars.dispose);
    addTearDown(port.changes.close);
    final item = message(1, version: 'a' * 64);
    await expectLater(cache.load(item), throwsStateError);
    now = now.add(const Duration(milliseconds: 9999));
    await expectLater(cache.load(item), throwsStateError);
    expect(port.calls, hasLength(1));
    port.fail = false;
    now = now.add(const Duration(milliseconds: 1));
    expect((await cache.load(item)).avatar, [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(port.calls, hasLength(2));
  });

  test(
    'attachment failure retries at the same bounded deadline without an avatar',
    () async {
      var now = DateTime.utc(2026, 10, 17);
      final port = MediaPort()..fail = true;
      final avatars = CommunityAvatarCache(now: () => now);
      final cache = CommunityChatMediaCache(port, 'a' * 32, avatars: avatars);
      addTearDown(cache.dispose);
      addTearDown(avatars.dispose);
      addTearDown(port.changes.close);
      final item = message(1, attachment: true, hasAvatar: false);
      await expectLater(cache.load(item), throwsStateError);
      port.fail = false;
      now = now.add(const Duration(seconds: 10));
      expect((await cache.load(item)).attachment?['title'], item.messageRef);
      expect(port.calls, hasLength(2));
    },
  );

  test(
    'detail queue stays bounded while its32 retained entries are evicted',
    () async {
      final port = MediaPort()..gate = Completer<void>();
      final cache = CommunityChatMediaCache(port, 'a' * 32);
      addTearDown(cache.dispose);
      addTearDown(port.changes.close);
      final requests = <Future<bool>>[];
      for (var i = 1; i <= 200; i++) {
        requests.add(
          cache
              .load(message(i, attachment: true, hasAvatar: false))
              .then((_) => true, onError: (Object _) => false),
        );
      }
      expect(port.calls, hasLength(3));
      port.gate!.complete();
      final results = await Future.wait(requests)
          .timeout(const Duration(seconds: 5));
      expect(port.calls, hasLength(96));
      expect(results.where((value) => value), hasLength(96));
      expect(results.where((value) => !value), hasLength(104));
      final item = message(200, attachment: true, hasAvatar: false);
      expect(
        (await cache.load(item, retry: true)).attachment?['title'],
        item.messageRef,
      );
      expect(port.calls, hasLength(97));
    },
  );

  test('dispose while awaiting a shared avatar cannot return late conversation data', () async {
    final port = MediaPort(), avatars = CommunityAvatarCache();
    final cache = CommunityChatMediaCache(port, 'a' * 32, avatars: avatars);
    addTearDown(cache.dispose);
    addTearDown(avatars.dispose);
    addTearDown(port.changes.close);
    final gate = Completer<Uint8List?>();
    final warm = avatars.get('d' * 32, 'a' * 64, () => gate.future);
    final loading = cache.load(message(1, attachment: true, version: 'a' * 64));
    final failed = expectLater(loading, throwsStateError);
    // The fake detail port has no IO: this event-loop turn drains its parsing
    // microtasks while the independent shared-avatar barrier remains held.
    await Future<void>.delayed(Duration.zero);
    expect(port.calls, hasLength(1));
    cache.dispose();
    gate.complete(Uint8List.fromList([1]));
    await warm;
    await failed;
  });

  test(
    'retained attachment peeks the current own avatar after a completed load',
    () async {
      final port = MediaPort()
        ..ownAvatarImageData = 'data:image/png;base64,CAcGBQQDAgE=';
      final cache = CommunityChatMediaCache(port, 'a' * 32);
      addTearDown(cache.dispose);
      addTearDown(port.changes.close);
      final item = message(1, attachment: true, self: true, version: '0' * 64);
      final loaded = await cache.load(item);
      expect(loaded.avatar, [8, 7, 6, 5, 4, 3, 2, 1]);
      expect(cache.peek(item)?.avatar, same(loaded.avatar));
    },
  );

  test(
    'late old own-photo load cannot replace a newer completed presentation',
    () async {
      const oldPhoto = 'data:image/png;base64,AQIDBAUGBwg=';
      final port = MediaPort()..ownAvatarImageData = oldPhoto;
      final avatars = CommunityAvatarCache();
      final cache = CommunityChatMediaCache(port, 'a' * 32, avatars: avatars);
      addTearDown(cache.dispose);
      addTearDown(avatars.dispose);
      addTearDown(port.changes.close);
      final gate = Completer<Uint8List?>();
      final key = sha256.convert(utf8.encode(oldPhoto)).toString();
      final warm = avatars.get(
        '${'d' * 32}:current-account',
        key,
        () => gate.future,
      );
      final item = message(1, attachment: true, self: true, version: '0' * 64);
      final first = cache.load(item);
      await Future<void>.delayed(Duration.zero);
      port.ownAvatarImageData = 'data:image/png;base64,CAcGBQQDAgE=';
      final latest = await cache.load(item);
      gate.complete(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]));
      await warm;
      await first;
      expect(latest.avatar, [8, 7, 6, 5, 4, 3, 2, 1]);
      expect(cache.peek(item)?.avatar, same(latest.avatar));
    },
  );

  test(
    'explicit retry bypasses failure backoff and success stays reusable',
    () async {
      var now = DateTime.utc(2026, 10, 17);
      final port = MediaPort()..fail = true;
      final avatars = CommunityAvatarCache(now: () => now);
      final cache = CommunityChatMediaCache(port, 'a' * 32, avatars: avatars);
      addTearDown(cache.dispose);
      addTearDown(avatars.dispose);
      addTearDown(port.changes.close);
      final item = message(1, attachment: true, hasAvatar: false);
      await expectLater(cache.load(item), throwsStateError);
      port.fail = false;
      expect(
        (await cache.load(item, retry: true)).attachment?['title'],
        item.messageRef,
      );
      now = now.add(const Duration(days: 1));
      expect((await cache.load(item)).attachment?['title'], item.messageRef);
      expect(port.calls, hasLength(2));
    },
  );

  test(
    'an older failed detail cannot expire a successful explicit retry',
    () async {
      var now = DateTime.utc(2026, 10, 17);
      final port = LateFailurePort();
      final avatars = CommunityAvatarCache(now: () => now);
      final cache = CommunityChatMediaCache(port, 'a' * 32, avatars: avatars);
      addTearDown(cache.dispose);
      addTearDown(avatars.dispose);
      addTearDown(port.changes.close);
      final item = message(1, attachment: true, hasAvatar: false);
      final failed = expectLater(cache.load(item), throwsStateError);
      final current = await cache.load(item, retry: true);
      port.first.complete();
      await failed;
      now = now.add(const Duration(seconds: 11));
      expect((await cache.load(item)).attachment, same(current.attachment));
      expect(port.attempts, 2);
    },
  );

  test('an authorized attachment remains peekable while its shared avatar is pending', () async {
    final port = MediaPort(), avatars = CommunityAvatarCache();
    final cache = CommunityChatMediaCache(port, 'a' * 32, avatars: avatars);
    addTearDown(cache.dispose);
    addTearDown(avatars.dispose);
    addTearDown(port.changes.close);
    final gate = Completer<Uint8List?>();
    final warm = avatars.get('d' * 32, 'a' * 64, () => gate.future);
    final item = message(1, attachment: true, version: 'a' * 64);
    final loading = cache.load(item);
    await Future<void>.delayed(Duration.zero);
    try {
      expect(
        cache.peek(item)?.attachment?['title'],
        item.messageRef,
        reason: 'The lifetime fix must not add an avatar barrier to already-read attachment display.',
      );
    } finally {
      gate.complete(Uint8List.fromList([9]));
      await warm;
      await loading;
    }
    expect(cache.peek(item)?.avatar, [9]);
  });

  test(
    'invalidating a full queue prevents queued IO and late media publication',
    () async {
      final port = MediaPort()..gate = Completer<void>();
      final cache = CommunityChatMediaCache(port, 'a' * 32);
      addTearDown(cache.dispose);
      addTearDown(port.changes.close);
      final requests = <Future<bool>>[];
      for (var i = 1; i <= 120; i++) {
        requests.add(
          cache
              .load(message(i, attachment: true, hasAvatar: false))
              .then((_) => true, onError: (Object _) => false),
        );
      }
      expect(port.calls, hasLength(3));
      port.changes.add(null);
      port.gate!.complete();
      final results = await Future.wait(requests)
          .timeout(const Duration(seconds: 5));
      expect(results.every((value) => !value), isTrue);
      expect(port.calls, hasLength(3));
      expect(cache.peek(message(1, attachment: true)), isNull);
      await expectLater(
        cache.load(message(121, attachment: true)),
        throwsStateError,
      );
      expect(port.calls, hasLength(3));
    },
  );
}

class LateFailurePort extends MediaPort {
  final first = Completer<void>();
  int attempts = 0;
  @override
  Future<Map<String, Object?>> readChatDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version,
  ) async {
    if (++attempts == 1) {
      calls.add(messageRef);
      await first.future;
      throw StateError('late fixture failure');
    }
    return super.readChatDetail(targetRef, messageRef, offset, version);
  }
}
