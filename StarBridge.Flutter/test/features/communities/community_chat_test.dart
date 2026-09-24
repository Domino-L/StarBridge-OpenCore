import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

Map<String, Object?> chatPage() => {
  'schemaVersion': 1,
  'targetRef': 'a' * 32,
  'unreadCount': 2,
  'latestSequence': 20,
  'oldestSequence': 10,
  'canSend': true,
  'hasOlder': true,
  'serverTime': '2026-09-07T00:00:00Z',
  'messages': [
    for (final sequence in [10, 12])
      {
        'sequence': sequence,
        'messageRef': (sequence == 10 ? 'b' : 'c') * 32,
        'senderRef': 'd' * 32,
        'senderCallsign': 'Visible callsign',
        'senderGameId': '',
        'senderRoleTitle': '成员',
        'senderRoleColor': '#29AFFF',
        'text': 'hello\nworld',
        'createdAt': '2026-09-06T23:00:00Z',
        'isSelf': sequence == 12,
        'hasAvatar': true,
        'hasAttachment': true,
      },
  ],
};

final class ChatDetailFake implements CommunityChatPort {
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  bool get chatAvailable => true;
  @override
  bool get chatReadReceiptsAvailable => true;
  @override
  Future<CommunityChatReadReceipt> markChatRead(
    String targetRef,
    CommunityChatMessage message,
  ) async =>
      CommunityChatReadReceipt('accepted', readThrough: message.sequence);
  String mode = 'ok';
  int reads = 0;
  CommunityChatPage? pageOverride;
  final avatar =
      'data:image/png;base64,${base64Encode(List<int>.filled(400 * 1024, 1))}';
  late final bytes = utf8.encode(
    jsonEncode({
      'avatarImageData': avatar,
      'attachment': {
        'kind': 'overlay_preset',
        'title': 'Fixture',
        'summary': 'Example only',
        'overlayPresetPackage': jsonEncode({
          'version': 1,
          'name': 'Fixture',
          'settings': '{}',
          'layout': '{}',
        }),
      },
    }),
  );
  @override
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  }) async => pageOverride ?? CommunityChatPage.parse(chatPage());
  @override
  Future<Map<String, Object?>> readChatDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version,
  ) async {
    reads++;
    final end = (offset + 192 * 1024).clamp(0, bytes.length);
    final row = <String, Object?>{
      'schemaVersion': 1,
      'targetRef': targetRef,
      'messageRef': messageRef,
      'offset': offset,
      'next': end < bytes.length ? end : null,
      'totalBytes': bytes.length,
      'version': sha256.convert(bytes).toString(),
      'data': base64Encode(bytes.sublist(offset, end)),
    };
    switch (mode) {
      case 'wrong-org':
        row['targetRef'] = 'e' * 32;
      case 'wrong-message':
        row['messageRef'] = 'e' * 32;
      case 'changed-version':
        if (reads > 1) row['version'] = '0' * 64;
      case 'bad-hash':
        row['version'] = '0' * 64;
      case 'bad-next':
        row['next'] = 0;
      case 'bad-total':
        row['totalBytes'] = 2 * 1024 * 1024 + 1;
      case 'bad-offset':
        row['offset'] = 1;
      case 'bad-base64':
        row['data'] = '!';
      case 'short-chunk':
        row['data'] = 'AQ==';
    }
    return row;
  }
}

void main() {
  test('chat bridge negotiates exact separate capabilities and preserves read context', () async {
    final host = CommunityHarness(
      capabilities: ['communities.chat', 'communities.chatDetail'],
      responses: {'communities.chat': chatPage()},
    );
    addTearDown(host.close);
    final page = await host.adapter.readChat('a' * 32);
    expect(host.adapter.chatAvailable, isTrue);
    expect(page.messages[1].isSelf, isTrue);
    expect(page.messages[0].text, 'hello\nworld');
    expect(page.messages[0].gameId, isEmpty);
    expect(page.messages[0].createdAt, DateTime.utc(2026, 9, 6, 23));
    expect(host.requests.last.payload, {
      'schemaVersion': 1,
      'targetRef': 'a' * 32,
      'after': 0,
      'before': 0,
    });
    expect(host.requests.last.accountContext?.subject, 'test-subject');
  });
  test(
    'old Host cannot read chat using generic community capability',
    () async {
      final host = CommunityHarness(capabilities: ['communities.commands']);
      addTearDown(host.close);
      expect(host.adapter.chatAvailable, isFalse);
      await expectLater(
        host.adapter.readChat('a' * 32),
        throwsA(isA<CommunityFailure>()),
      );
      expect(host.requests, isEmpty);
    },
  );
  for (final (key, value) in <(String, Object?)>[
    ('schemaVersion', 2),
    ('targetRef', 'raw-code'),
    ('unreadCount', 501),
    ('latestSequence', 11),
    ('oldestSequence', 11),
    ('canSend', 'true'),
    ('serverTime', 'not-time'),
    ('messages', <Object?>[]),
  ]) {
    test('malformed chat page $key rejected', () {
      expect(
        () => CommunityChatPage.parse(chatPage()..[key] = value),
        throwsFormatException,
      );
    });
  }
  test('duplicate message refs, descending sequences and unsupported role color rejected', () {
    for (final (key, value) in [
      ('sequence', 9),
      ('messageRef', 'b' * 32),
      ('senderRoleColor', 'red'),
      ('createdAt', ''),
    ]) {
      final row = chatPage();
      ((row['messages'] as List)[1] as Map)[key] = value;
      expect(() => CommunityChatPage.parse(row), throwsFormatException);
    }
  });
  test('returned cursor range and org must match requested lane', () async {
    final host = CommunityHarness(
      capabilities: ['communities.chat', 'communities.chatDetail'],
      responses: {'communities.chat': chatPage()},
    );
    addTearDown(host.close);
    await expectLater(
      host.adapter.readChat('e' * 32),
      throwsA(isA<CommunityFailure>()),
    );
    await expectLater(
      host.adapter.readChat('a' * 32, after: 10),
      throwsA(isA<CommunityFailure>()),
    );
    await expectLater(
      host.adapter.readChat('a' * 32, before: 12),
      throwsA(isA<CommunityFailure>()),
    );
    final requests = host.requests.length;
    await expectLater(
      host.adapter.readChat('a' * 32, after: 1, before: 2),
      throwsA(isA<CommunityFailure>()),
    );
    expect(host.requests.length, requests);
  });
  test('account change rejects late chat response', () async {
    final host = CommunityHarness(
      capabilities: ['communities.chat', 'communities.chatDetail'],
      holdNames: {'communities.chat'},
      responses: {'communities.chat': chatPage()},
    );
    addTearDown(host.close);
    final pending = host.adapter.readChat('a' * 32);
    final rejected = expectLater(pending, throwsA(isA<CommunityFailure>()));
    await host.readArrived.future;
    final invalidated = host.adapter.invalidations.first;
    await host.connection.send(
      const BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'account.changed',
        sessionGeneration: 5,
        sequence: 1,
        payload: {'schemaVersion': 1},
      ),
    );
    await invalidated;
    await rejected;
    await host.reply(
      host.requests.firstWhere((r) => r.name == 'communities.chat'),
    );
    expect(host.session.activeGeneration, 5);
  });
  test(
    'large original detail is assembled with hash and attachment intact',
    () async {
      final port = ChatDetailFake();
      final result = await assembleCommunityChatDetail(
        port,
        'a' * 32,
        'c' * 32,
        checkCurrent: () {},
      );
      expect(port.reads, greaterThan(1));
      expect(result.avatar, port.avatar);
      expect(result.attachment?['kind'], 'overlay_preset');
    },
  );
  for (final mode in [
    'wrong-org',
    'wrong-message',
    'changed-version',
    'bad-hash',
    'bad-next',
    'bad-total',
    'bad-offset',
    'bad-base64',
    'short-chunk',
  ]) {
    test('detail $mode rejected before exposing partial bytes', () async {
      final port = ChatDetailFake()..mode = mode;
      await expectLater(
        assembleCommunityChatDetail(
          port,
          'a' * 32,
          'c' * 32,
          checkCurrent: () {},
        ),
        throwsFormatException,
      );
    });
  }
  test('context check stops detail assembly after invalidation', () async {
    final port = ChatDetailFake();
    var checks = 0;
    await expectLater(
      assembleCommunityChatDetail(
        port,
        'a' * 32,
        'c' * 32,
        checkCurrent: () {
          if (++checks == 3) {
            throw const CommunityFailure('identityUnavailable');
          }
        },
      ),
      throwsA(isA<CommunityFailure>()),
    );
    expect(port.reads, 1);
  });
  test('detail forbids remote avatar URLs and unrelated attachment types', () {
    expect(
      () => CommunityChatDetail.parse({
        'avatarImageData': 'https://example.invalid/a.png',
        'attachment': null,
      }),
      throwsFormatException,
    );
    expect(
      () => CommunityChatDetail.parse({
        'avatarImageData': null,
        'attachment': {'kind': 'fleet_invitation'},
      }),
      throwsFormatException,
    );
    expect(
      () => CommunityChatDetail.parse({
        'avatarImageData': null,
        'attachment': {
          'kind': 'overlay_preset',
          'title': 'a',
          'summary': 'b',
          'overlayPresetPackage': '{}',
        },
      }),
      throwsFormatException,
    );
  });
}
