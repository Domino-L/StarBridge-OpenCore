import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'bridge_communities_test.dart' show CommunityHarness;
import 'community_chat_test.dart' show chatPage;

Map<String, Object?> receipt() => {
  'schemaVersion': 1,
  'targetRef': 'a' * 32,
  'messageRef': 'c' * 32,
  'status': 'accepted',
  'error': null,
  'readThroughSequence': 25,
};

void main() {
  final message = CommunityChatPage.parse(chatPage()).messages.last;
  test(
    'explicit receipt posts only scoped references and retains advanced cursor',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.markChatRead'],
        responses: {'communities.markChatRead': receipt()},
      );
      addTearDown(host.close);
      final result = await host.adapter.markChatRead('a' * 32, message);
      expect(result.status, 'accepted');
      expect(result.readThrough, 25);
      expect(host.requests.map((v) => v.name), [
        'account.getCurrent',
        'communities.markChatRead',
      ]);
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'targetRef': 'a' * 32,
        'messageRef': 'c' * 32,
      });
      expect(host.requests.last.accountContext?.subject, 'test-subject');
    },
  );
  test('reading history never submits a receipt', () async {
    final host = CommunityHarness(
      capabilities: [
        'communities.chat',
        'communities.chatDetail',
        'communities.markChatRead',
      ],
      responses: {'communities.chat': chatPage()},
    );
    addTearDown(host.close);
    await host.adapter.readChat('a' * 32);
    expect(host.requests.map((v) => v.name), [
      'account.getCurrent',
      'communities.chat',
    ]);
  });
  test(
    'missing receipt capability never invokes account or generic commands',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.chat', 'communities.commands'],
      );
      addTearDown(host.close);
      expect(host.adapter.chatReadReceiptsAvailable, isFalse);
      expect(
        (await host.adapter.markChatRead('a' * 32, message)).status,
        'rejected',
      );
      expect(host.requests, isEmpty);
    },
  );
  for (final (key, value) in <(String, Object?)>[
    ('schemaVersion', 2),
    ('targetRef', 'e' * 32),
    ('messageRef', 'b' * 32),
    ('status', 'ok'),
    ('readThroughSequence', 11),
    ('readThroughSequence', null),
    ('readThroughSequence', '25'),
    ('error', 'notAllowed'),
  ]) {
    test('malformed receipt $key=$value never clears unread', () async {
      final host = CommunityHarness(
        capabilities: ['communities.markChatRead'],
        responses: {'communities.markChatRead': receipt()..[key] = value},
      );
      addTearDown(host.close);
      final result = await host.adapter.markChatRead('a' * 32, message);
      expect(result.status, 'unknown');
      expect(result.readThrough, isNull);
      expect(
        host.requests.where((v) => v.name == 'communities.markChatRead'),
        hasLength(1),
      );
    });
  }
  test('rejected and unknown cannot carry a confirmed read cursor', () {
    for (final status in ['rejected', 'unknown']) {
      final row = receipt()..['status'] = status;
      expect(
        () => CommunityChatReadReceipt.parse(row, 'a' * 32, message),
        throwsFormatException,
      );
      row['readThroughSequence'] = null;
      row['error'] = status == 'rejected' ? 'notAllowed' : 'outcomeUnknown';
      final parsed = CommunityChatReadReceipt.parse(row, 'a' * 32, message);
      expect(parsed.status, status);
      expect(parsed.readThrough, isNull);
    }
  });
  test(
    'account change cancels receipt and late success stays unconfirmed',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.markChatRead'],
        holdNames: {'communities.markChatRead'},
        responses: {'communities.markChatRead': receipt()},
      );
      addTearDown(host.close);
      final pending = host.adapter.markChatRead('a' * 32, message);
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
      expect((await pending).status, 'unknown');
      await host.reply(
        host.requests.firstWhere((v) => v.name == 'communities.markChatRead'),
      );
      expect(host.session.activeGeneration, 5);
    },
  );
}
