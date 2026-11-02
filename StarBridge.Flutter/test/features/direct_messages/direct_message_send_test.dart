import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/direct_messages/example_direct_messages.dart';

import 'direct_messages_test.dart' as fixtures;

class Sender implements DirectMessagesPort, DirectMessageSender {
  final example = ExampleDirectMessages();
  final events = StreamController<void>.broadcast();
  final writes = <(String, String, String)>[];
  final replies = <Completer<DirectSendResult>>[];
  Completer<DirectSendResult> get reply => replies.first;
  DirectMessage? confirmed;
  bool allowed = true;
  String? stateOverride;
  @override
  bool get supportsSending => true;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<List<Conversation>> directory() => example.directory();
  @override
  Future<DirectPage> history(
    String ref, {
    int before = 0,
    int after = 0,
  }) async {
    final p = await example.history(ref, before: before, after: after);
    return DirectPage(
      p.ref,
      [...p.messages, ?confirmed],
      p.oldest,
      confirmed?.sequence ?? p.latest,
      p.hasOlder,
      stateOverride ?? p.state,
      canSend: allowed && p.canSend,
    );
  }

  @override
  Future<DirectSendResult> send(
    String ref,
    String text,
    String clientMessageId,
  ) {
    writes.add((ref, text, clientMessageId));
    final reply = Completer<DirectSendResult>();
    replies.add(reply);
    return reply.future;
  }

  DirectMessage ack() => DirectMessage(
    61,
    writes.last.$3,
    false,
    writes.last.$2,
    DateTime.utc(2026),
    null,
  );
  @override
  void cancel() {}
  @override
  Future<void> close() => events.close();
}

Future<DirectMessagesModule> opened(
  Sender port, {
  List<Duration> retryDelays = DirectMessageSendQueue.defaultRetryDelays,
}) async {
  final m = DirectMessagesModule(port, sendRetryDelays: retryDelays);
  await m.refresh();
  await m.open(m.visible.single);
  return m;
}

// User choice 2026-10-21 "A2": a sent message appears at once with a clock,
// the composer clears, history replaces the local copy; failures keep the
// text and retry with the same clientMessageId (the relay deduplicates on it).
void main() {
  test(
    'a sent message appears at once and history replaces its local copy',
    () async {
      final p = Sender();
      final module = await opened(p);
      addTearDown(module.dispose);
      module.editDraft('消息\n正文');
      await module.send();
      expect(module.draft, isEmpty, reason: 'the composer is free at once');
      expect(module.outgoing.single.text, '消息\n正文');
      expect(module.outgoing.single.state, DirectOutgoingState.sending);
      expect(p.writes, hasLength(1));
      await module.send();
      expect(p.writes, hasLength(1), reason: 'an empty composer sends nothing');
      expect(module.messages.last.sequence, 60);
      p.confirmed = p.ack();
      p.reply.complete(DirectSendResult('sent', message: p.confirmed));
      await pumpEventQueue();
      expect(module.messages.last.sequence, 61);
      expect(module.outgoing, isEmpty, reason: 'never shown twice');
      expect(module.rows.first.unread, 2);
    },
  );

  test(
    'later messages wait for the earlier one, keeping their order',
    () async {
      final p = Sender();
      final m = await opened(p);
      addTearDown(m.dispose);
      m.editDraft('一');
      await m.send();
      m.editDraft('二');
      await m.send();
      expect(m.outgoing.map((o) => o.text), ['一', '二']);
      expect(p.writes.map((w) => w.$2), ['一']);
      p.reply.complete(DirectSendResult('sent', message: p.ack()));
      await pumpEventQueue();
      expect(p.writes.map((w) => w.$2), ['一', '二']);
    },
  );

  test(
    'an uncertain result retries with the same id and reconciles by history',
    () async {
      final p = Sender();
      final m = await opened(p, retryDelays: const [Duration.zero]);
      addTearDown(m.dispose);
      m.editDraft('消息');
      await m.send();
      p.reply.complete(const DirectSendResult('unknown'));
      await pumpEventQueue();
      expect(p.writes, hasLength(2));
      expect(p.writes[1].$3, p.writes[0].$3, reason: 'same clientMessageId');
      expect(m.outgoing.single.state, DirectOutgoingState.sending);
      // The first attempt had in fact arrived: the relay answers duplicate.
      p.confirmed = p.ack();
      p.replies[1].complete(
        DirectSendResult('duplicate', message: p.confirmed),
      );
      await pumpEventQueue();
      expect(m.outgoing, isEmpty);
      expect(m.messages.where((x) => x.id == p.writes[0].$3), hasLength(1));
    },
  );

  test(
    'retries are bounded, then the message fails and keeps its text',
    () async {
      final p = Sender();
      final m = await opened(p, retryDelays: const [Duration.zero]);
      addTearDown(m.dispose);
      m.editDraft('消息');
      await m.send();
      p.reply.complete(const DirectSendResult('unknown'));
      await pumpEventQueue();
      p.replies[1].complete(const DirectSendResult('unknown'));
      await pumpEventQueue();
      expect(p.writes, hasLength(2));
      expect(m.outgoing.single.state, DirectOutgoingState.failed);
      expect(m.outgoing.single.text, '消息');
      // The user retries: same id, fresh budget.
      m.retrySend(m.outgoing.single.id);
      expect(p.writes, hasLength(3));
      expect(p.writes[2].$3, p.writes[0].$3);
      expect(m.outgoing.single.state, DirectOutgoingState.sending);
    },
  );

  test(
    'explicit rejection fails at once, keeps the text and disables sending',
    () async {
      final p = Sender();
      final m = await opened(p);
      addTearDown(m.dispose);
      m.editDraft('x' * 1001);
      await m.send();
      expect(p.writes, isEmpty);
      m.editDraft('消息');
      await m.send();
      p.reply.complete(
        const DirectSendResult('rejected', error: 'request_pending'),
      );
      await pumpEventQueue();
      expect(p.writes, hasLength(1), reason: 'a rejection is not retried');
      expect(m.outgoing.single.state, DirectOutgoingState.failed);
      expect(m.outgoing.single.error, 'request_pending');
      expect(m.outgoing.single.text, '消息');
      expect(m.sendStatus, 'request_pending');
      expect(m.readyToSend, isFalse);
      p.allowed = false;
      await m.load();
      expect(m.readyToSend, isFalse);
    },
  );

  test(
    'a restored connection sends a waiting message without backoff',
    () async {
      final p = Sender();
      final m = await opened(p, retryDelays: const [Duration(hours: 1)]);
      addTearDown(m.dispose);
      m.editDraft('排队');
      await m.send();
      p.reply.complete(const DirectSendResult('unknown'));
      await pumpEventQueue();
      expect(p.writes, hasLength(1));
      m.connectionRestored();
      expect(p.writes, hasLength(2));
      expect(p.writes[1].$3, p.writes[0].$3);
    },
  );

  for (final state in ['request_incoming', 'request_outgoing']) {
    test(
      '$state follows the authoritative remaining-message permission',
      () async {
        final p = Sender()..stateOverride = state;
        final m = await opened(p);
        addTearDown(m.dispose);
        expect(m.state, state);
        expect(m.canSend, isTrue);
        m.editDraft('消息');
        expect(m.readyToSend, isTrue);

        p.allowed = false;
        await m.load();
        expect(m.canSend, isFalse);
        expect(m.readyToSend, isFalse);
      },
    );
  }

  test(
    'account invalidation clears drafts and ignores delayed acknowledgement',
    () async {
      final p = Sender();
      final m = await opened(p);
      addTearDown(m.dispose);
      m.editDraft('private');
      await m.send();
      p.events.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(m.outgoing, isEmpty, reason: 'sends never cross the boundary');
      p.reply.complete(DirectSendResult('sent', message: p.ack()));
      await pumpEventQueue();
      expect(m.draft, isEmpty);
      expect(m.messages, isEmpty);
      expect(m.selected, isNull);
      expect(m.sendStatus, isNull);
      expect(m.outgoing, isEmpty);
    },
  );

  test('malformed success is uncertain, not success', () async {
    final p = Sender();
    final m = await opened(p, retryDelays: const []);
    addTearDown(m.dispose);
    m.editDraft('消息');
    await m.send();
    p.reply.complete(const DirectSendResult('sent'));
    await pumpEventQueue();
    expect(m.outgoing.single.state, DirectOutgoingState.failed);
    expect(m.outgoing.single.error, 'unknown');
    expect(m.outgoing.single.text, '消息');
  });

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets('composer, draft leave guard, Enter and avatars $locale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(fixtures.app(locale, ExampleDirectMessages.new));
      await tester.pumpAndSettle();
      await tester.tap(find.text('示例好友  @Example'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '待发送\n第二行');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-back-list')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextButton),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('待发送\n第二行'), findsOneWidget);
      await tester.tap(find.byType(TextFormField));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('待发送\n第二行'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
