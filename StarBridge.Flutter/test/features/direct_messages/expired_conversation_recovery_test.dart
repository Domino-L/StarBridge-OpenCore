import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'direct_message_live_delivery_test.dart' show IncomingPort;

class ExpiringPort extends IncomingPort {
  bool expired = false;
  String key = 'scoped-peer';
  int replacementReads = 0;
  String? replacementFailure;
  @override
  Future<List<Conversation>> directory() async => [
    Conversation(expired ? 'renewed' : 'old', 'Peer', '', time, 0,
        'friend', conversationKey: key),
  ];
  @override
  Future<DirectPage> history(String ref, {int before = 0, int after = 0}) async {
    if (expired && ref == 'old') {
      throw const DirectReadFailure('target_changed');
    }
    if (ref == 'renewed') {
      replacementReads++;
      expect(before, 0);
      expect(after, 0);
      if (replacementFailure != null) {
        throw DirectReadFailure(replacementFailure!);
      }
    }
    return DirectPage(ref, [], 0, 0, false, 'friend', canSend: true);
  }
}

class ExpiringSendPort extends ExpiringPort implements DirectMessageSender {
  final sentRefs = <String>[];
  @override
  bool get supportsSending => true;
  @override
  Future<DirectSendResult> send(String ref, String text, String clientMessageId) async {
    sentRefs.add(ref);
    expired = true;
    return const DirectSendResult('rejected', error: 'target_changed');
  }
}

void main() {
  test('explicit stale send renews only the same scoped target and keeps draft', () async {
    final port = ExpiringSendPort();
    final module = DirectMessagesModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    await module.open(module.rows.single);
    module.editDraft('SB14-RT01');
    await module.send();
    expect(port.sentRefs, ['old'], reason: 'a rejected send must never be retried automatically');
    expect(module.selected?.ref, 'renewed');
    expect(module.draft, 'SB14-RT01');
    expect(module.canSend, isTrue);
    expect(module.readyToSend, isTrue);
    expect(module.error, isNull);
  });

  test('stale send cannot renew a different scoped identity', () async {
    final port = ExpiringSendPort();
    final module = DirectMessagesModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    await module.open(module.rows.single);
    module.editDraft('unsent');
    port.key = 'different-scope';
    await module.send();
    expect(port.sentRefs, ['old']);
    expect(module.selected?.ref, 'old');
    expect(module.draft, 'unsent');
    expect(module.canSend, isFalse);
  });

  test('stale send renewal does not bypass a later read denial', () async {
    final port = ExpiringSendPort();
    final module = DirectMessagesModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    await module.open(module.rows.single);
    module.editDraft('unsent');
    port.replacementFailure = 'forbidden';
    await module.send();
    expect(port.sentRefs, ['old']);
    expect(module.draft, 'unsent');
    expect(module.canSend, isFalse);
    expect(module.error, 'forbidden');
  });

  for (final failure in ['target_changed', 'forbidden']) {
    test('renewed target failure $failure is bounded and cannot grant sending', () async {
      final port = ExpiringPort();
      final module = DirectMessagesModule(port);
      addTearDown(module.dispose);
      await module.refresh();
      await module.open(module.rows.single);
      module.editDraft('unsent draft');
      port.expired = true;
      port.replacementFailure = failure;
      await module.load();
      expect(module.error, failure);
      expect(module.canSend, isFalse);
      expect(module.busy, isFalse);
      expect(module.messages, isEmpty);
      expect(module.draft, 'unsent draft');
      expect(port.replacementReads, 1);
    });
  }
  test('expired read target renews by scoped identity without discarding draft', () async {
    final port = ExpiringPort();
    final module = DirectMessagesModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    await module.open(module.rows.single);
    module.editDraft('unsent draft');
    port.expired = true;
    await module.receive();
    expect(module.error, isNull);
    expect(module.selected!.ref, 'renewed');
    expect(module.canSend, isTrue);
    expect(module.draft, 'unsent draft');
    expect(port.replacementReads, 1);
  });

  test('same name in another scope cannot renew an expired conversation', () async {
    final port = ExpiringPort();
    final module = DirectMessagesModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    await module.open(module.rows.single);
    module.editDraft('unsent draft');
    port.expired = true;
    port.key = 'different-scope';
    await module.load();
    expect(module.error, 'target_changed');
    expect(module.canSend, isFalse);
    expect(module.draft, 'unsent draft');
    expect(port.replacementReads, 0);
  });
}
