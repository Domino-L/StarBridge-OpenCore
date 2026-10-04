import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_chat_controller.dart';
import 'package:starbridge_flutter/features/communities/community_chat_send_port.dart';

import 'community_chat_controller_test.dart' show FakeChat, page;
import 'community_unread_attention_test.dart' show UnreadPort;
import 'community_navigation_cache_test.dart' show card;

import 'package:starbridge_flutter/features/communities/community_workspace_session.dart';

void main() {
  late FakeChat port;
  late CommunityChatController chat;
  setUp(() async {
    port = FakeChat()..next = page([], latest: 0, unread: 0, older: false);
    chat = CommunityChatController(port, 'a' * 32, localEcho: true);
    await chat.refresh();
  });
  tearDown(() async {
    chat.dispose();
    await port.changes.close();
  });

  test(
    'send immediately moves draft to bubble; later typing survives receipt',
    () async {
      chat.updateDraft('first');
      final held = port.heldSend = Completer();
      final pending = chat.submit();
      expect(chat.draft, isEmpty);
      expect(chat.localMessages.single.intent.text, 'first');
      expect(chat.localMessages.single.state, 'sending');
      expect(chat.messages, isEmpty);
      expect(port.receipts, isEmpty);
      chat.updateDraft('next');
      held.complete(const CommunityChatSendOutcome('accepted', sequence: 1));
      await pending;
      expect(chat.draft, 'next');
      expect(chat.localMessages.single.state, 'sent');
      expect(chat.localMessages.single.sequence, 1);
      port.next = page(
        [1],
        latest: 1,
        localRequestId: port.sends.single.requestId,
      );
      await chat.refresh();
      expect(chat.localMessages, isEmpty);
      expect(chat.messages, hasLength(1));
    },
  );
  test('definite failure stays in bubble; explicit retry cannot double click', () async {
    port.sendResult = const CommunityChatSendOutcome(
      'rejected',
      error: 'rateLimited',
    );
    chat.updateDraft('first');
    await chat.submit();
    final local = chat.localMessages.single;
    expect(local.state, 'failed');
    expect(chat.draft, isEmpty);
    final firstId = local.intent.requestId;
    chat.updateDraft('next');
    final held = port.heldSend = Completer();
    final retry = chat.submit(retry: local);
    await chat.submit(retry: local);
    expect(port.sends, hasLength(2));
    expect(
      local.intent.requestId,
      isNot(firstId),
      reason:
          'Host caches definitive rejection; retry is a new explicit attempt.',
    );
    expect(local.intent.text, 'first');
    expect(chat.draft, 'next');
    held.complete(const CommunityChatSendOutcome('accepted', sequence: 2));
    await retry;
    expect(chat.localMessages.single, same(local));
    expect(local.state, 'sent');
    expect(chat.draft, 'next');
  });
  test(
    'unknown never reposts; authenticated history reconciles exactly once',
    () async {
      port.sendResult = const CommunityChatSendOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
      chat.updateDraft('first');
      await chat.submit();
      final local = chat.localMessages.single;
      expect(local.state, 'unknown');
      expect(chat.canRetry(local), isFalse);
      await chat.submit(retry: local);
      expect(port.sends, hasLength(1));
      await chat.refresh();
      expect(chat.localMessages.single, same(local));
      chat.updateDraft('next');
      port.next = page([1], latest: 1, localRequestId: local.intent.requestId);
      await chat.refresh();
      expect(chat.localMessages, isEmpty);
      expect(chat.sendUncertain, false);
      expect(chat.draft, 'next');
    },
  );
  test(
    'history before a lost response wins without duplicate local bubble',
    () async {
      chat.updateDraft('first');
      final held = port.heldSend = Completer();
      final pending = chat.submit();
      port.next = page(
        [1],
        latest: 1,
        localRequestId: port.sends.single.requestId,
      );
      await chat.refresh();
      expect(chat.localMessages, isEmpty);
      held.complete(
        const CommunityChatSendOutcome('unknown', error: 'outcomeUnknown'),
      );
      await pending;
      expect(chat.localMessages, isEmpty);
      expect(chat.sendError, isNull);
    },
  );
  test(
    'account invalidation clears local content and rejects late send',
    () async {
      chat.updateDraft('private');
      final held = port.heldSend = Completer();
      final pending = chat.submit();
      port.changes.add(null);
      expect(chat.localMessages, isEmpty);
      held.complete(const CommunityChatSendOutcome('accepted', sequence: 1));
      await pending;
      expect(chat.localMessages, isEmpty);
      expect(chat.messages, isEmpty);
      expect(chat.draft, isEmpty);
    },
  );
  test('permission rejection clears local content immediately', () async {
    chat.updateDraft('private');
    port.sendResult = const CommunityChatSendOutcome(
      'rejected',
      error: 'notAllowed',
    );
    await chat.submit();
    expect(chat.invalidated, true);
    expect(chat.localMessages, isEmpty);
  });
  test('invalid input does not clear draft or create local bubble', () async {
    chat.updateDraft('x' * 1001);
    await chat.submit();
    expect(chat.draft.length, 1001);
    expect(chat.localMessages, isEmpty);
    expect(port.sends, isEmpty);
  });
  test(
    'discarding new draft does not forget an unknown submitted message',
    () async {
      chat.updateDraft('first');
      port.sendResult = const CommunityChatSendOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
      await chat.submit();
      chat.updateDraft('new draft');
      chat.discardDraft();
      expect(chat.draft, isEmpty);
      expect(chat.localMessages.single.intent.text, 'first');
      expect(chat.sendUncertain, true);
      expect(chat.canSubmit, false);
    },
  );
  test('workspace LRU does not destroy a local delivery owner', () async {
    final source = UnreadPort();
    final session = CommunityWorkspaceSession(capacity: 1);
    addTearDown(source.close);
    addTearDown(session.clear);
    final owner = session.obtain(source, card.targetRef, card.key);
    await owner.enter(card.targetRef);
    final conversation = owner.chat!;
    await conversation.refresh();
    conversation.updateDraft('first');
    source.chat.sendResult = const CommunityChatSendOutcome(
      'unknown',
      error: 'outcomeUnknown',
    );
    await conversation.submit();
    session.obtain(source, 'b' * 32, 'organization-b');
    final restored = session.obtain(source, card.targetRef, card.key);
    expect(restored, same(owner));
    expect(restored.chat, same(conversation));
    expect(conversation.sendUncertain, true);
    expect(conversation.localMessages.single.intent.text, 'first');
    session.clear();
    await Future<void>.delayed(Duration.zero);
    expect(conversation.localMessages, isEmpty);
  });
  test(
    'failed message restores only into an empty composer without sending',
    () async {
      chat.updateDraft('first');
      port.sendResult = const CommunityChatSendOutcome(
        'rejected',
        error: 'dataInvalid',
      );
      await chat.submit();
      final local = chat.localMessages.single;
      chat.updateDraft('new draft');
      chat.restoreLocalDraft(local);
      expect(chat.draft, 'new draft');
      expect(chat.localMessages.single, same(local));
      chat.updateDraft('');
      chat.restoreLocalDraft(local);
      expect(chat.draft, 'first');
      expect(chat.localMessages, isEmpty);
      expect(port.sends, hasLength(1));
    },
  );
  test('send readback is not lost when another read is in flight', () async {
    final held = port.heldRead = Completer();
    final read = chat.refresh(silent: true);
    chat.updateDraft('first');
    port.sendResult = const CommunityChatSendOutcome('accepted', sequence: 1);
    await chat.submit();
    expect(chat.localMessages.single.state, 'sent');
    port.heldRead = null;
    port.next = page(
      [1],
      latest: 1,
      localRequestId: port.sends.single.requestId,
    );
    held.complete(page([], latest: 0, unread: 0, older: false));
    await read;
    await Future<void>.delayed(Duration.zero);
    expect(chat.localMessages, isEmpty);
    expect(chat.messages, hasLength(1));
  });
}
