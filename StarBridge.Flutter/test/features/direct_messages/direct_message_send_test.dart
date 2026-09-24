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
  final reply = Completer<DirectSendResult>();
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

Future<DirectMessagesModule> opened(Sender port) async {
  final m = DirectMessagesModule(port);
  await m.refresh();
  await m.open(m.visible.single);
  return m;
}

void main() {
  test('send waits for ack, prevents duplicate clicks and reloads latest without clearing unread', () async {
    final p = Sender();
    final module = await opened(p);
    addTearDown(module.dispose);
    module.editDraft('消息\n正文');
    final sending = module.send();
    await module.send();
    expect(p.writes, hasLength(1));
    expect(module.draft, '消息\n正文');
    expect(module.messages.last.sequence, 60);
    p.confirmed = p.ack();
    p.reply.complete(DirectSendResult('sent', message: p.confirmed));
    await sending;
    expect(module.sendStatus, 'sent');
    expect(module.draft, isEmpty);
    expect(module.messages.last.sequence, 61);
    expect(module.rows.first.unread, 2);
  });

  test('unknown retains draft, cannot resend, and history confirms exact outgoing intent', () async {
    final p = Sender();
    final m = await opened(p);
    addTearDown(m.dispose);
    m.editDraft('消息');
    final sending = m.send();
    p.reply.complete(const DirectSendResult('unknown'));
    await sending;
    expect(m.awaitingConfirmation, isTrue);
    expect(m.draft, '消息');
    await m.send();
    await m.load();
    expect(p.writes, hasLength(1));
    expect(m.awaitingConfirmation, isTrue);
    p.confirmed = p.ack();
    await m.load();
    expect(m.awaitingConfirmation, isFalse);
    expect(m.sendStatus, 'sent');
    expect(m.draft, isEmpty);
  });

  test('explicit rejection keeps draft, revoked permissions and long text disable sending', () async {
    final p = Sender();
    final m = await opened(p);
    addTearDown(m.dispose);
    m.editDraft('x' * 1001);
    await m.send();
    expect(p.writes, isEmpty);
    m.editDraft('消息');
    final sending = m.send();
    p.reply.complete(
      const DirectSendResult('rejected', error: 'request_pending'),
    );
    await sending;
    expect(m.draft, '消息');
    expect(m.readyToSend, isFalse);
    expect(m.awaitingConfirmation, isFalse);
    p.allowed = false;
    await m.load();
    expect(m.readyToSend, isFalse);
  });

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
      final sending = m.send();
      p.events.add(null);
      await Future<void>.delayed(Duration.zero);
      p.reply.complete(DirectSendResult('sent', message: p.ack()));
      await sending;
      expect(m.draft, isEmpty);
      expect(m.messages, isEmpty);
      expect(m.selected, isNull);
      expect(m.sendStatus, isNull);
    },
  );

  test('malformed success is uncertain, not success', () async {
    final p = Sender();
    final m = await opened(p);
    addTearDown(m.dispose);
    m.editDraft('消息');
    final sending = m.send();
    p.reply.complete(const DirectSendResult('sent'));
    await sending;
    expect(m.sendStatus, 'outcome_unknown');
    expect(m.draft, '消息');
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
      await tester.tap(find.text('示例好友 (Example)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '待发送\n第二行');
      await tester.pump();
      await tester.tap(find.byType(TextButton).first);
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
