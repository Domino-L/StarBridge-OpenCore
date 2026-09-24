import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_message_drafts.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';

class Sender implements DirectMessageSender {
  @override
  bool get supportsSending => true;
  final calls = <({String ref, String text, String id})>[];
  final reply = Completer<DirectSendResult>();
  @override
  Future<DirectSendResult> send(String ref, String text, String id) {
    calls.add((ref: ref, text: text, id: id));
    return reply.future;
  }
}

DirectMessage confirmed(
  String id,
  String text, {
  bool incoming = false,
  String? attachment,
}) => DirectMessage(1, id, incoming, text, DateTime.utc(2026), attachment);

void main() {
  test('drafts are bounded, monotonic and cleared with account session', () {
    final store = MenuMessageDrafts();
    for (var i = 0; i < 32; i++) {
      expect(store.forTarget('$i')!.edit('draft $i', 1), true);
    }
    expect(store.forTarget('overflow'), null);
    final first = store.forTarget('0')!;
    expect(first.edit('stale', 1), false);
    expect(first.edit('x' * 1001, 2), false);
    expect(first.edit('invalid', 1000000001), false);
    expect(first.text, 'draft 0');
    first.edit('', 2);
    expect(store.forTarget('overflow'), isNotNull);
    store.clear();
    expect(store.forTarget('1')!.text, '');
  });
  for (final status in ['sent', 'duplicate', 'request_sent']) {
    test('only exact outgoing receipt confirms $status', () async {
      final draft = MenuMessageDraft()..edit(' hello ', 1);
      final sender = Sender();
      final task = draft.send(sender, 'private-ref');
      expect(draft.locked, true);
      expect(draft.edit('overwrite', 2), false);
      await draft.send(sender, 'private-ref');
      expect(sender.calls.length, 1);
      final request = sender.calls.single;
      expect(request.text, 'hello');
      expect(request.id, matches(RegExp(r'^[a-f0-9]{32}$')));
      sender.reply.complete(
        DirectSendResult(status, message: confirmed(request.id, request.text)),
      );
      await task;
      expect(draft.locked, false);
      expect(draft.text, '');
      expect(draft.status, status == 'request_sent' ? status : 'sent');
    });
  }
  test(
    'unconfirmed receipt locks resend until exact history reconciliation',
    () async {
      final draft = MenuMessageDraft()..edit('hello', 1), sender = Sender();
      final task = draft.send(sender, 'ref');
      sender.reply.complete(const DirectSendResult('sent'));
      await task;
      expect(draft.status, 'unknown');
      final id = sender.calls.single.id;
      for (final wrong in [
        confirmed('other', 'hello'),
        confirmed(id, 'other'),
        confirmed(id, 'hello', incoming: true),
        confirmed(id, 'hello', attachment: 'file'),
      ]) {
        draft.observe([wrong]);
        expect(draft.locked, true);
      }
      await draft.send(sender, 'ref');
      expect(sender.calls.length, 1);
      expect(draft.text, 'hello');
      draft.observe([confirmed(id, 'hello')]);
      expect(draft.status, 'sent');
      expect(draft.text, '');
    },
  );
  test('explicit rejection keeps editable draft', () async {
    final draft = MenuMessageDraft()..edit('hello', 1), sender = Sender();
    final task = draft.send(sender, 'ref');
    sender.reply.complete(const DirectSendResult('rejected'));
    await task;
    expect(draft.locked, false);
    expect(draft.text, 'hello');
    expect(draft.status, 'rejected');
    expect(draft.edit('corrected', 3), true);
  });
  testWidgets(
    'timeout preserves pending draft without resending or accepting late receipt',
    (tester) async {
      final draft = MenuMessageDraft()..edit('hello', 1), sender = Sender();
      final task = draft.send(sender, 'ref');
      await tester.pump(const Duration(seconds: 16));
      await task;
      expect(draft.status, 'unknown');
      sender.reply.complete(
        DirectSendResult(
          'sent',
          message: confirmed(sender.calls.single.id, 'hello'),
        ),
      );
      await tester.pump();
      expect(draft.locked, true);
      expect(draft.text, 'hello');
      expect(sender.calls.length, 1);
    },
  );
}
