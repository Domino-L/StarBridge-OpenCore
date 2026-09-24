import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_chat_controller.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_send_port.dart';

CommunityChatPage page(
  List<int> sequences, {
  int latest = 20,
  int unread = 2,
  bool older = true,
  String? localRequestId,
}) => CommunityChatPage.parse({
  'schemaVersion': 1,
  'targetRef': 'a' * 32,
  'unreadCount': unread,
  'latestSequence': latest,
  'oldestSequence': sequences.firstOrNull ?? 0,
  'canSend': true,
  'hasOlder': sequences.isNotEmpty && older,
  'serverTime': '2026-09-07T00:00:00Z',
  'messages': [
    for (final sequence in sequences)
      {
        'sequence': sequence,
        'messageRef': sequence.toRadixString(16).padLeft(32, '0'),
        'senderRef': 'd' * 32,
        'senderCallsign': 'Example',
        'senderGameId': '',
        'senderRoleTitle': '成员',
        'senderRoleColor': '#29AFFF',
        'text': 'Message $sequence',
        'createdAt': '2026-09-07T00:00:00Z',
        'isSelf': localRequestId != null,
        'localRequestId': localRequestId,
        'hasAvatar': false,
        'hasAttachment': false,
      },
  ],
});

final class FakeChat implements CommunityChatPort, CommunityChatSendPort {
  final changes = StreamController<void>.broadcast(sync: true);
  final reads = <(int, int)>[];
  final receipts = <int>[];
  final sends = <CommunityChatSendIntent>[];
  Completer<CommunityChatSendOutcome>? heldSend;
  CommunityChatSendOutcome sendResult = const CommunityChatSendOutcome(
    'accepted',
    sequence: 20,
  );
  @override
  bool get chatSendAvailable => true;
  @override
  Future<CommunityChatSendOutcome> sendChat(
    CommunityChatSendIntent intent,
  ) async {
    sends.add(intent);
    return heldSend?.future ?? sendResult;
  }

  CommunityChatPage next = page([10, 12]);
  Object? failure;
  Completer<CommunityChatPage>? heldRead;
  Completer<CommunityChatReadReceipt>? heldReceipt;
  CommunityChatReadReceipt? receipt;
  @override
  bool get chatAvailable => true;
  @override
  bool get chatReadReceiptsAvailable => true;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  }) async {
    reads.add((after, before));
    if (failure != null) throw failure!;
    return heldRead?.future ?? next;
  }

  @override
  Future<CommunityChatReadReceipt> markChatRead(
    String targetRef,
    CommunityChatMessage message,
  ) async {
    receipts.add(message.sequence);
    return heldReceipt?.future ??
        receipt ??
        CommunityChatReadReceipt('accepted', readThrough: message.sequence);
  }

  @override
  Future<Map<String, Object?>> readChatDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version,
  ) => throw UnimplementedError();
}

void main() {
  late FakeChat port;
  late CommunityChatController controller;
  setUp(() {
    port = FakeChat();
    controller = CommunityChatController(port, 'a' * 32);
  });
  tearDown(() async {
    controller.dispose();
    await port.changes.close();
  });

  test(
    'send requires loaded permissions and preserves draft until accepted',
    () async {
      controller.updateDraft('hello');
      await controller.submit();
      expect(port.sends, isEmpty);
      await controller.refresh();
      final held = port.heldSend = Completer();
      final pending = controller.submit();
      expect(controller.draft, 'hello');
      expect(controller.sending, isTrue);
      await controller.submit();
      expect(port.sends, hasLength(1));
      port.next = page([20], older: false);
      held.complete(const CommunityChatSendOutcome('accepted', sequence: 20));
      await pending;
      expect(controller.draft, isEmpty);
      expect(controller.messages.last.sequence, 20);
      expect(controller.sending, isFalse);
    },
  );
  test(
    'new typing during an in-flight send is not cleared by old success',
    () async {
      await controller.refresh();
      controller.updateDraft('first');
      final held = port.heldSend = Completer();
      final pending = controller.submit();
      controller.updateDraft('second');
      port.next = page([20], older: false);
      held.complete(const CommunityChatSendOutcome('accepted', sequence: 20));
      await pending;
      expect(controller.draft, 'second');
      expect(port.sends.single.text, 'first');
    },
  );
  test('definite rejection preserves draft and next intentional attempt has new nonce', () async {
    await controller.refresh();
    controller.updateDraft('hello');
    port.sendResult = const CommunityChatSendOutcome(
      'rejected',
      error: 'rateLimited',
    );
    port.next = page([]);
    await controller.submit();
    expect(controller.draft, 'hello');
    expect(controller.sendError, 'rateLimited');
    expect(controller.canSubmit, isTrue);
    await controller.submit();
    expect(port.sends, hasLength(2));
    expect(port.sends.first.requestId, isNot(port.sends.last.requestId));
  });
  test(
    'unknown send locks replay and authenticated history resolves it',
    () async {
      await controller.refresh();
      controller.updateDraft('hello');
      port.sendResult = const CommunityChatSendOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
      await controller.submit();
      expect(controller.draft, 'hello');
      expect(controller.sendUncertain, isTrue);
      await controller.submit();
      expect(port.sends, hasLength(1));
      port.next = page([15], localRequestId: 'f' * 32);
      await controller.refresh();
      expect(controller.sendUncertain, isTrue);
      port.next = page([20], localRequestId: port.sends.single.requestId);
      await controller.refresh();
      expect(controller.draft, isEmpty);
      expect(controller.sendUncertain, isFalse);
      expect(controller.canSubmit, isTrue);
    },
  );
  test('history confirmation wins over late unknown POST response', () async {
    await controller.refresh();
    controller.updateDraft('hello');
    final held = port.heldSend = Completer();
    final pending = controller.submit();
    port.next = page([20], localRequestId: port.sends.single.requestId);
    await controller.refresh();
    expect(controller.draft, isEmpty);
    held.complete(
      const CommunityChatSendOutcome('unknown', error: 'outcomeUnknown'),
    );
    await pending;
    expect(controller.sendUncertain, isFalse);
    expect(controller.sendError, isNull);
  });
  test(
    'switching account clears draft and cannot accept old send result',
    () async {
      await controller.refresh();
      controller.updateDraft('private draft');
      final held = port.heldSend = Completer();
      final pending = controller.submit();
      port.changes.add(null);
      held.complete(const CommunityChatSendOutcome('accepted', sequence: 20));
      await pending;
      expect(controller.draft, isEmpty);
      expect(controller.invalidated, isTrue);
      expect(controller.messages, isEmpty);
      expect(controller.sending, isFalse);
    },
  );
  test('invalid draft remains editable without network send', () async {
    await controller.refresh();
    controller.updateDraft('x' * 1001);
    await controller.submit();
    expect(controller.draft.length, 1001);
    expect(controller.sendError, 'dataInvalid');
    expect(port.sends, isEmpty);
    expect(controller.canSubmit, isTrue);
  });

  test('incremental cursor uses last received not server latest and does not mark read', () async {
    await controller.refresh();
    expect(controller.hasNewer, isTrue);
    port.next = page([15, 20], older: false);
    await controller.refresh();
    expect(port.reads, [(0, 0), (12, 0)]);
    expect(controller.messages.map((m) => m.sequence), [10, 12, 15, 20]);
    expect(controller.hasNewer, isFalse);
    expect(controller.hasOlder, isTrue);
    expect(port.receipts, isEmpty);
  });
  test(
    'older history prepends without replacing current message identities',
    () async {
      await controller.refresh();
      final previous = controller.messages.last;
      port.next = page([5, 7], older: false);
      await controller.loadOlder();
      expect(port.reads.last, (0, 10));
      expect(controller.messages.map((m) => m.sequence), [5, 7, 10, 12]);
      expect(identical(controller.messages.last, previous), isTrue);
      expect(controller.hasOlder, isFalse);
      await controller.loadOlder();
      expect(port.reads, hasLength(2));
    },
  );
  test(
    'background, hidden and unknown messages cannot submit receipts',
    () async {
      await controller.refresh();
      final ref = controller.messages.last.messageRef;
      await controller.acknowledgeVisible(ref);
      controller.setReadingContext(visible: true, foreground: false);
      await controller.acknowledgeVisible(ref);
      controller.setReadingContext(visible: false, foreground: true);
      await controller.acknowledgeVisible(ref);
      controller.setReadingContext(visible: true, foreground: true);
      await controller.acknowledgeVisible('f' * 32);
      expect(port.receipts, isEmpty);
      await controller.acknowledgeVisible(ref);
      expect(port.receipts, [12]);
      expect(controller.confirmedReadThrough, 12);
      expect(controller.unreadCount, 2, reason: 'newer sequence20 is not seen');
    },
  );
  test(
    'confirmed latest clears badge; stale counts do not resurrect it',
    () async {
      port.next = page([10, 12], latest: 12);
      await controller.refresh();
      controller.setReadingContext(visible: true, foreground: true);
      await controller.acknowledgeVisible(controller.messages.last.messageRef);
      expect(controller.unreadCount, 0);
      await controller.acknowledgeVisible(controller.messages.last.messageRef);
      expect(port.receipts, [12]);
      port.next = page([], latest: 12);
      await controller.refresh();
      expect(controller.unreadCount, 0);
      port.next = page([15], latest: 15, unread: 1);
      await controller.refresh();
      expect(controller.unreadCount, 1);
    },
  );
  test(
    'uncertain acknowledgement preserves unread and only explicit retry sends',
    () async {
      port.next = page([10, 12], latest: 12);
      await controller.refresh();
      port.receipt = const CommunityChatReadReceipt(
        'unknown',
        error: 'outcomeUnknown',
      );
      controller.setReadingContext(visible: true, foreground: true);
      await controller.acknowledgeVisible(controller.messages.last.messageRef);
      expect(controller.unreadCount, 2);
      expect(controller.confirmedReadThrough, 0);
      expect(controller.receiptError, 'outcomeUnknown');
      expect(port.receipts, [12]);
      port.receipt = null;
      await controller.acknowledgeVisible(
        controller.messages.last.messageRef,
        retry: true,
      );
      expect(port.receipts, [12, 12]);
      expect(controller.unreadCount, 0);
    },
  );
  test('new visible messages queue while a receipt is in flight', () async {
    port.next = page([10, 12], latest: 12);
    await controller.refresh();
    controller.setReadingContext(visible: true, foreground: true);
    final held = port.heldReceipt = Completer();
    final pending = controller.acknowledgeVisible(
      controller.messages.first.messageRef,
    );
    await controller.acknowledgeVisible(controller.messages.last.messageRef);
    expect(port.receipts, [10]);
    port.heldReceipt = null;
    held.complete(const CommunityChatReadReceipt('accepted', readThrough: 10));
    await pending;
    expect(port.receipts, [10, 12]);
    expect(controller.unreadCount, 0);
  });
  test(
    'hiding clears queued receipts, but a confirmed prior view remains read',
    () async {
      await controller.refresh();
      controller.setReadingContext(visible: true, foreground: true);
      final held = port.heldReceipt = Completer();
      final pending = controller.acknowledgeVisible(
        controller.messages.first.messageRef,
      );
      await controller.acknowledgeVisible(controller.messages.last.messageRef);
      controller.setReadingContext(visible: false, foreground: false);
      held.complete(
        const CommunityChatReadReceipt('accepted', readThrough: 10),
      );
      await pending;
      expect(port.receipts, [10]);
      expect(controller.confirmedReadThrough, 10);
    },
  );
  test(
    'read failures preserve history and cursor; losing membership clears it',
    () async {
      await controller.refresh();
      port.failure = const CommunityFailure('unavailable');
      await controller.refresh();
      expect(controller.messages, hasLength(2));
      expect(controller.error, 'unavailable');
      port.failure = null;
      port.next = page([15]);
      await controller.refresh();
      expect(port.reads.last, (12, 0));
      expect(controller.messages, hasLength(3));
      port.failure = const CommunityFailure('notAllowed');
      await controller.refresh();
      expect(controller.invalidated, isTrue);
      expect(controller.messages, isEmpty);
      expect(controller.unreadCount, 0);
      expect(controller.canSend, isFalse);
    },
  );
  test('bad cursor page never replaces known messages', () async {
    await controller.refresh();
    await controller.refresh(); // Fixture improperly repeats old sequences.
    expect(controller.error, 'dataInvalid');
    expect(controller.messages.map((m) => m.sequence), [10, 12]);
  });
  test('account change clears state and rejects late read', () async {
    final held = port.heldRead = Completer();
    final pending = controller.refresh();
    await controller.refresh();
    expect(port.reads, hasLength(1));
    port.changes.add(null);
    held.complete(page([10, 12]));
    await pending;
    expect(controller.invalidated, isTrue);
    expect(controller.messages, isEmpty);
    expect(controller.loading, isFalse);
  });
  test('account change rejects late successful receipt', () async {
    await controller.refresh();
    controller.setReadingContext(visible: true, foreground: true);
    final held = port.heldReceipt = Completer();
    final pending = controller.acknowledgeVisible(
      controller.messages.last.messageRef,
    );
    port.changes.add(null);
    held.complete(const CommunityChatReadReceipt('accepted', readThrough: 25));
    await pending;
    expect(controller.invalidated, isTrue);
    expect(controller.confirmedReadThrough, 0);
    expect(controller.messages, isEmpty);
    expect(controller.markingRead, isFalse);
  });
  test('read permission rejection clears conversation instead of retaining private data', () async {
    await controller.refresh();
    controller.setReadingContext(visible: true, foreground: true);
    port.receipt = const CommunityChatReadReceipt(
      'rejected',
      error: 'notAllowed',
    );
    await controller.acknowledgeVisible(controller.messages.last.messageRef);
    expect(controller.invalidated, isTrue);
    expect(controller.messages, isEmpty);
  });
}
