import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_chat_media_cache.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_image_decoder.dart';
import 'package:starbridge_flutter/features/communities/community_avatar_cache.dart';
import 'package:starbridge_flutter/features/communities/community_own_avatar.dart';

import 'community_chat_test.dart' show chatPage;

CommunityChatMessage message(
  int id, {
  String sender = 'd',
  String? version,
  bool attachment = false,
  bool self = false,
  bool hasAvatar = true,
}) => CommunityChatMessage.parse({
  ...Map<String, Object?>.from((chatPage()['messages'] as List).first as Map),
  'messageRef': id.toRadixString(16).padLeft(32, '0'),
  'senderRef': sender * 32,
  'avatarVersion': version,
  'hasAttachment': attachment,
  'isSelf': self,
  'hasAvatar': hasAvatar,
});

class MediaPort implements CommunityChatPort, CommunityOwnAvatarSource {
  @override
  String? ownAvatarImageData;
  final changes = StreamController<void>.broadcast(sync: true);
  final calls = <String>[];
  Completer<void>? gate;
  bool fail = false;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  bool get chatAvailable => true;
  @override
  bool get chatReadReceiptsAvailable => false;
  @override
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  }) async => CommunityChatPage.parse(chatPage());
  @override
  Future<CommunityChatReadReceipt> markChatRead(
    String targetRef,
    CommunityChatMessage message,
  ) async => const CommunityChatReadReceipt('accepted', readThrough: 20);
  @override
  Future<Map<String, Object?>> readChatDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version,
  ) async {
    calls.add(messageRef);
    await gate?.future;
    if (fail) throw StateError('Fixture unavailable');
    final bytes = utf8.encode(
      jsonEncode({
        'avatarImageData': 'data:image/png;base64,AQIDBAUGBwg=',
        'attachment': {
          'kind': 'overlay_preset',
          'title': messageRef,
          'summary': '',
          'overlayPresetPackage': jsonEncode({
            'version': 1,
            'name': 'Fixture',
            'settings': '{}',
            'layout': '{}',
          }),
        },
      }),
    );
    return {
      'schemaVersion': 1,
      'targetRef': targetRef,
      'messageRef': messageRef,
      'offset': 0,
      'next': null,
      'totalBytes': bytes.length,
      'version': sha256.convert(bytes).toString(),
      'data': base64Encode(bytes),
    };
  }
}

void main() {
  test('own historical messages use the current account avatar without rewriting history', () async {
    final source = MediaPort()
      ..ownAvatarImageData = 'data:image/png;base64,AQIDBAUGBwg=';
    final media = CommunityChatMediaCache(source, 'a' * 32);
    addTearDown(media.dispose);
    addTearDown(source.changes.close);
    final own = await media.load(message(1, self: true, version: '0' * 64));
    expect(own.avatar, orderedEquals([1, 2, 3, 4, 5, 6, 7, 8]));
    final oldBlank = await media.load(message(2, self: true, hasAvatar: false));
    expect(oldBlank.avatar, same(own.avatar));
    expect(source.calls, isEmpty);
    source.ownAvatarImageData = 'data:image/png;base64,CAcGBQQDAgE=';
    final changed = await media.load(message(1, self: true, version: '0' * 64));
    expect(changed.avatar, orderedEquals([8, 7, 6, 5, 4, 3, 2, 1]));
    await media.load(message(3, self: false, version: '0' * 64));
    expect(
      source.calls,
      hasLength(1),
      reason: 'Other senders keep their own authorized avatar',
    );
  });
  test(
    'avatar byte cache evicts old large photos as well as limiting entry count',
    () async {
      final avatars = CommunityAvatarCache();
      var reads = 0;
      Future<Uint8List?> read() async {
        reads++;
        return Uint8List(1024 * 1024);
      }

      try {
        for (var index = 0; index < 18; index++) {
          await avatars.get('member-$index', 'version', read);
        }
        await avatars.get('member-17', 'version', read);
        expect(reads, 18, reason: 'Recent photos remain reusable');
        await avatars.get('member-0', 'version', read);
        expect(
          reads,
          19,
          reason: 'Old large photos must leave the 16 MiB cache',
        );
      } finally {
        avatars.dispose();
      }
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  late MediaPort port;
  late CommunityChatMediaCache cache;
  setUp(() {
    port = MediaPort();
    cache = CommunityChatMediaCache(port, 'a' * 32);
  });
  tearDown(() async {
    cache.dispose();
    await port.changes.close();
  });

  test(
    'one in-flight request and identical retained avatar bytes per sender',
    () async {
      port.gate = Completer<void>();
      final reads = [
        cache.load(message(1)),
        cache.load(message(2)),
        cache.load(message(3)),
      ];
      expect(port.calls, hasLength(1));
      port.gate!.complete();
      final values = await Future.wait(reads);
      expect(identical(values[0].avatar, values[1].avatar), isTrue);
      expect((await cache.load(message(4))).avatar, same(values[0].avatar));
      expect(port.calls, hasLength(1));
    },
  );

  test(
    'distinct senders and changed versions never reuse another avatar',
    () async {
      final a = await cache.load(message(1, version: 'a' * 64));
      final b = await cache.load(message(2, sender: 'e', version: 'a' * 64));
      final changed = await cache.load(message(1, version: 'b' * 64));
      expect(port.calls, hasLength(3));
      expect(identical(a.avatar, b.avatar), isFalse);
      expect(identical(a.avatar, changed.avatar), isFalse);
    },
  );

  test(
    'attachments remain message-specific while their avatar is shared',
    () async {
      final first = cache.load(message(1, attachment: true));
      final avatarOnly = cache.load(message(2));
      final second = cache.load(message(3, attachment: true));
      final values = await Future.wait([first, avatarOnly, second]);
      expect(port.calls, hasLength(2));
      expect(values[0].avatar, same(values[2].avatar));
      expect(values[1].attachment, isNull);
      expect(
        values[0].attachment!['title'],
        isNot(values[2].attachment!['title']),
      );
    },
  );

  test('failed reads do not stampede and explicit retry can recover', () async {
    port.fail = true;
    await expectLater(cache.load(message(1)), throwsStateError);
    await expectLater(cache.load(message(2)), throwsStateError);
    expect(port.calls, hasLength(1));
    port.fail = false;
    expect((await cache.load(message(2), retry: true)).avatar, isNotNull);
    expect(port.calls, hasLength(2));
  });

  test(
    'invalidation rejects late media and does not issue queued requests',
    () async {
      port.gate = Completer<void>();
      final reads = [
        for (final sender in ['a', 'b', 'c', 'd'])
          cache.load(message(sender.codeUnitAt(0), sender: sender)),
      ];
      final errors = [
        for (final read in reads) expectLater(read, throwsStateError),
      ];
      expect(port.calls, hasLength(3));
      port.changes.add(null);
      port.gate!.complete();
      await Future.wait(errors);
      await expectLater(cache.load(message(5)), throwsStateError);
      expect(port.calls, hasLength(3));
    },
  );

  test(
    'bounded reads run three at a time, with no global serial avatar queue',
    () async {
      port.gate = Completer<void>();
      final reads = [
        for (final sender in ['a', 'b', 'c', 'd', 'e'])
          cache.load(message(sender.codeUnitAt(0), sender: sender)),
      ];
      expect(port.calls, hasLength(3));
      port.gate!.complete();
      await Future.wait(reads);
      expect(port.calls, hasLength(5));
    },
  );

  test('separate conversations do not share media', () async {
    final other = CommunityChatMediaCache(port, 'b' * 32);
    addTearDown(other.dispose);
    final a = await cache.load(message(1));
    final b = await other.load(message(1));
    expect(port.calls, hasLength(2));
    expect(identical(a.avatar, b.avatar), isFalse);
  });

  Future<ui.Image> pixel() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xff123456), ui.BlendMode.src);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(1, 1);
    } finally {
      picture.dispose();
    }
  }

  test(
    'decode once, clone handles, retain after widget handle disposal',
    () async {
      var decodes = 0;
      final images = CommunityImageDecodeCache(
        decoder: (_, _) {
          decodes++;
          return pixel();
        },
      );
      final bytes = Uint8List.fromList([1]);
      final pair = await Future.wait([
        images.decode(bytes, 96),
        images.decode(bytes, 96),
      ]);
      expect(decodes, 1);
      expect(pair[0].isCloneOf(pair[1]), isTrue);
      pair[0].dispose();
      final again = await images.decode(bytes, 96);
      expect(decodes, 1);
      images.dispose();
      expect(await again.toByteData(), isNotNull);
      pair[1].dispose();
      again.dispose();
    },
  );

  test(
    'eviction during native decode keeps callers safe and releases masters',
    () async {
      final gate = Completer<ui.Image>();
      var decodes = 0;
      final images = CommunityImageDecodeCache(
        decoder: (_, _) {
          decodes++;
          return decodes == 1 ? gate.future : pixel();
        },
      );
      final bytes = Uint8List(1);
      final first = images.decode(bytes, 96);
      for (var i = 0; i < 64; i++) {
        (await images.decode(Uint8List.fromList([i]), 96)).dispose();
      }
      final master = await pixel();
      gate.complete(master);
      final retained = await first;
      expect(master.debugDisposed, isTrue);
      expect(await retained.toByteData(), isNotNull);
      retained.dispose();
      (await images.decode(bytes, 96)).dispose();
      expect(decodes, 66);
      images.dispose();
    },
  );
  test(
    'late native decode is discarded when conversation is disposed',
    () async {
      final gate = Completer<ui.Image>();
      final images = CommunityImageDecodeCache(decoder: (_, _) => gate.future);
      final read = images.decode(Uint8List(1), 96);
      final failed = expectLater(read, throwsStateError);
      images.dispose();
      final image = await pixel();
      gate.complete(image);
      await failed;
      expect(image.debugDisposed, isTrue);
    },
  );
}
