import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_chat_controller.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_send_port.dart';

import 'community_chat_controller_test.dart' show FakeChat, page;

void main() {
  test('display-only scope preserves drafts and viewport while blocking new sends and receipts', () async {
    final port = FakeChat();
    final model = CommunityChatController(port, 'a' * 32);
    addTearDown(model.dispose);
    await model.enter();
    model.setReadingContext(visible: true, foreground: true);
    model.updateDraft('Unsent draft');
    const viewport = CommunityChatViewport(
      pixels: 240,
      followLatest: false,
      observedLatest: 12,
    );
    model.rememberViewport(viewport);
    model.setReadOnly(true);
    expect(model.canSubmit, isFalse);
    expect(model.canAcknowledge, isFalse);
    await model.submit();
    await model.acknowledgeVisible(model.messages.last.messageRef);
    expect(port.sends, isEmpty);
    expect(port.receipts, isEmpty);
    expect(model.draft, 'Unsent draft');
    expect(model.viewport, same(viewport));
    model.updateDraft('Still editable locally');
    model.setReadOnly(false);
    expect(model.canSubmit, isTrue);
    expect(
      port.sends,
      isEmpty,
      reason: 'Revalidation must not replay a draft.',
    );
    expect(model.draft, 'Still editable locally');
    await model.acknowledgeVisible(model.messages.last.messageRef);
    expect(port.receipts, [12]);
  });
  test('read-only transition keeps an already dispatched send uncertain without replay', () async {
    final port = FakeChat()..heldSend = Completer<CommunityChatSendOutcome>();
    final model = CommunityChatController(port, 'a' * 32, localEcho: true);
    addTearDown(model.dispose);
    await model.enter();
    model.updateDraft('Pending send');
    final sending = model.submit();
    final intent = port.sends.single;
    model.setReadOnly(true);
    port.heldSend!.complete(const CommunityChatSendOutcome('unknown'));
    await sending;
    expect(model.sendUncertain, isTrue);
    expect(model.localMessages.single.intent, same(intent));
    expect(model.localMessages.single.state, 'unknown');
    model.setReadOnly(false);
    await model.submit();
    expect(port.sends, hasLength(1));
    expect(model.sendUncertain, isTrue);
  });
  test('read-only mode accepts a prior receipt but does not dispatch its queued successor', () async {
    final port = FakeChat()..next = page([10, 12], latest: 12);
    final model = CommunityChatController(port, 'a' * 32);
    addTearDown(model.dispose);
    await model.enter();
    model.setReadingContext(visible: true, foreground: true);
    port.heldReceipt = Completer<CommunityChatReadReceipt>();
    final first = model.acknowledgeVisible(model.messages.first.messageRef);
    await model.acknowledgeVisible(model.messages.last.messageRef);
    model.setReadOnly(true);
    port.heldReceipt!.complete(
      const CommunityChatReadReceipt('accepted', readThrough: 10),
    );
    await first;
    expect(port.receipts, [10]);
    expect(model.confirmedReadThrough, 10);
    expect(model.displayedReadThrough, 10);
    expect(model.messages, hasLength(2));
  });
}
