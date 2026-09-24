import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/direct_messages/bridge_direct_messages.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

const reference = '00000000000000000000000000000001';
Map<String, Object?> directory() => {
  'schemaVersion': 1,
  'conversations': [
    {
      'targetRef': reference,
      'callsign': '呼号',
      'gameId': 'Example',
      'preview': '消息',
      'lastMessageAt': '2026-09-06T12:00:00Z',
      'unreadCount': 1,
      'state': 'request_incoming',
    },
  ],
  'totalUnread': 1,
};
Map<String, Object?> history() => {
  'schemaVersion': 1,
  'targetRef': reference,
  'messages': [
    {
      'sequence': 1,
      'messageId': 'message-1',
      'incoming': true,
      'text': '消息\n换行',
      'createdAt': '2026-09-06T12:00:00Z',
      'attachmentKind': 'overlay_preset',
    },
  ],
  'oldestSequence': 1,
  'latestSequence': 1,
  'hasOlder': false,
  'canSend': false,
  'state': 'request_incoming',
};

void main() {
  test(
    'receipt is capability gated, scoped and acknowledgement validated',
    () async {
      for (final fault in [null, 'target', 'cursor']) {
        final h = Harness(receiptCapability: true, receiptFault: fault);
        addTearDown(h.close);
        if (fault == null) {
          final receipt = await h.adapter.markRead(reference, 1);
          expect(receipt.through, 1);
          expect(receipt.unread, 0);
        } else {
          await expectLater(
            h.adapter.markRead(reference, 1),
            throwsA(isA<DirectReadFailure>()),
          );
        }
        final write = h.requests.singleWhere(
          (r) => r.name == 'directMessages.markRead',
        );
        expect(write.accountContext?.subject, 'test-subject');
        expect(write.payload, {
          'schemaVersion': 1,
          'targetRef': reference,
          'throughSequence': 1,
        });
      }
      final old = Harness();
      addTearDown(old.close);
      expect(old.adapter.supportsReadReceipts, isFalse);
      await expectLater(
        old.adapter.markRead(reference, 1),
        throwsA(isA<DirectReadFailure>()),
      );
      expect(old.requests, isEmpty);
    },
  );
  test(
    'sending is separately gated and uses scoped immutable intent',
    () async {
      final h = Harness(sendCapability: true);
      addTearDown(h.close);
      final result = await h.adapter.send(reference, '内容', reference);
      expect(result.status, 'sent');
      expect(result.message?.text, '内容');
      final writes = h.requests
          .where((r) => r.name == 'directMessages.send')
          .toList();
      expect(writes, hasLength(1));
      expect(writes.single.accountContext?.subject, 'test-subject');
      expect(writes.single.payload, {
        'schemaVersion': 1,
        'targetRef': reference,
        'text': '内容',
        'clientMessageId': reference,
      });
      final old = Harness();
      addTearDown(old.close);
      expect(old.adapter.supportsSending, isFalse);
      expect(
        (await old.adapter.send(reference, '内容', reference)).status,
        'rejected',
      );
      expect(old.requests, isEmpty);
    },
  );
  test('missing acknowledgement, wrong schema and bridge write error are uncertain', () async {
    for (final fault in ['schema', 'message', 'error']) {
      final h = Harness(
        sendCapability: true,
        sendFault: fault,
        error: fault == 'error' ? 'host.failed' : null,
      );
      addTearDown(h.close);
      expect(
        (await h.adapter.send(reference, '内容', reference)).status,
        'unknown',
      );
      expect(
        h.requests.where((r) => r.name == 'directMessages.send'),
        hasLength(1),
      );
    }
  });
  test('directory and history only send scoped read requests, never receipt or send', () async {
    final h = Harness();
    addTearDown(h.close);
    expect((await h.adapter.directory()).single.name, '呼号 (Example)');
    final page = await h.adapter.history(reference, before: 2);
    expect(page.messages.single.attachment, 'overlay_preset');
    final requests = h.requests
        .where((r) => r.name == 'directMessages.read')
        .toList();
    expect(requests, hasLength(2));
    expect(requests.last.payload, {
      'schemaVersion': 1,
      'targetRef': reference,
      'before': 2,
    });
    expect(
      requests.every((r) => r.accountContext?.subject == 'test-subject'),
      isTrue,
    );
    expect(
      h.requests.every(
        (r) => {'account.getCurrent', 'directMessages.read'}.contains(r.name),
      ),
      isTrue,
    );
  });
  test(
    'optional capability and signed-out account fail before resource read',
    () async {
      for (final capability in [false, true]) {
        final h = Harness(capability: capability, signedIn: false);
        addTearDown(h.close);
        await expectLater(
          h.adapter.directory(),
          throwsA(isA<DirectReadFailure>()),
        );
        expect(
          h.requests.where((r) => r.name == 'directMessages.read'),
          isEmpty,
        );
      }
    },
  );
  test('forbidden response maps stable error without server detail', () async {
    final h = Harness(error: 'directMessages.forbidden');
    addTearDown(h.close);
    await expectLater(
      h.adapter.directory(),
      throwsA(
        isA<DirectReadFailure>().having((e) => e.code, 'code', 'forbidden'),
      ),
    );
  });
  test(
    'account invalidation cancels in-flight read and rejects old reply',
    () async {
      final h = Harness(hold: true);
      addTearDown(h.close);
      final read = h.adapter.directory();
      final outcome = expectLater(read, throwsA(anything));
      await h.arrived.future;
      final invalidated = h.adapter.invalidations.first;
      await h.connection.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'account.changed',
          sessionGeneration: 5,
          sequence: 1,
          payload: const {},
        ),
      );
      await invalidated;
      await outcome;
      await h.reply(
        h.requests.firstWhere((r) => r.name == 'directMessages.read'),
      );
      expect(h.session.activeGeneration, 5);
    },
  );
  test(
    'projection rejects duplicate, bad cursor metadata and malformed data',
    () {
      final d = directory();
      d['conversations'] = [
        for (var n = 0; n < 2; n++)
          (directory()['conversations'] as List).single,
      ];
      expect(() => parseConversations(d), throwsA(anything));
      expect(
        () => parseConversations({...directory(), 'totalUnread': 2}),
        throwsA(anything),
      );
      expect(
        () => parseDirectPage({...history(), 'oldestSequence': 2}),
        throwsA(anything),
      );
      expect(
        () => parseDirectPage({...history(), 'latestSequence': 0}),
        throwsA(anything),
      );
      expect(
        () => parseDirectPage({...history(), 'hasOlder': 'false'}),
        throwsA(anything),
      );
      expect(
        () => parseDirectPage({
          ...history(),
          'messages': List.filled(2, (history()['messages'] as List).single),
        }),
        throwsA(anything),
      );
    },
  );
}

class Harness {
  Harness({
    bool capability = true,
    bool sendCapability = false,
    bool receiptCapability = false,
    this.receiptFault,
    this.sendFault,
    this.signedIn = true,
    this.error,
    this.hold = false,
  }) {
    final pair = InMemoryBridgeConnection.createPair();
    connection = pair.host;
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
    );
    session.acceptHostCapabilities([
      if (capability) 'directMessages.read',
      if (sendCapability) 'directMessages.send',
      if (receiptCapability) 'directMessages.markRead',
    ]);
    adapter = BridgeDirectMessages(session);
    subscription = connection.incoming.listen((r) {
      requests.add(r);
      if (r.name == 'bridge.cancel') return;
      if (r.name == 'directMessages.read') {
        if (!arrived.isCompleted) arrived.complete();
        if (hold) return;
      }
      unawaited(reply(r));
    });
  }
  final bool signedIn, hold;
  final String? error;
  final String? sendFault;
  final String? receiptFault;
  final requests = <BridgeEnvelope>[];
  final arrived = Completer<void>();
  late final BridgeConnection connection;
  late final BridgeClientSession session;
  late final BridgeDirectMessages adapter;
  late final StreamSubscription<BridgeEnvelope> subscription;
  Future<void> reply(BridgeEnvelope r) => connection.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: r.name,
      correlationId: r.correlationId,
      sessionGeneration: r.sessionGeneration,
      accountContext: signedIn
          ? const BridgeAccountContext(
              environment: 'test',
              authority: 'scm',
              subject: 'test-subject',
            )
          : null,
      status: r.name != 'account.getCurrent' && error != null ? 'error' : 'ok',
      error: r.name != 'account.getCurrent' && error != null
          ? BridgeErrorBody(
              code: error!,
              message: 'private server detail',
              retryable: false,
            )
          : null,
      payload: r.name == 'account.getCurrent'
          ? {'schemaVersion': 1, 'state': signedIn ? 'signedIn' : 'signedOut'}
          : r.name == 'directMessages.markRead'
          ? {
              'schemaVersion': 1,
              'targetRef': receiptFault == 'target'
                  ? '00000000000000000000000000000002'
                  : reference,
              'readThroughSequence': receiptFault == 'cursor' ? 0 : 1,
              'unreadCount': 0,
            }
          : r.name == 'directMessages.send'
          ? {
              'schemaVersion': sendFault == 'schema' ? 2 : 1,
              'targetRef': reference,
              'status': 'sent',
              if (sendFault != 'message')
                'message': {
                  'sequence': 2,
                  'messageId': r.payload['clientMessageId'],
                  'incoming': false,
                  'text': r.payload['text'],
                  'createdAt': '2026-09-06T12:00:00Z',
                  'attachmentKind': null,
                },
            }
          : r.payload.containsKey('targetRef')
          ? history()
          : directory(),
    ),
  );
  Future<void> close() async {
    await adapter.close();
    await subscription.cancel();
    await session.close();
    await connection.close();
  }
}
