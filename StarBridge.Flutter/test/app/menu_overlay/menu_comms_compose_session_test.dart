import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';

import 'menu_comms_session_test.dart' show Port, peer;

class ComposePort extends Port {
  final writes =
      <
        ({
          String ref,
          String text,
          String id,
          Completer<DirectSendResult> reply,
        })
      >[];
  @override
  Future<DirectSendResult> send(String ref, String text, String id) {
    sends++;
    final reply = Completer<DirectSendResult>();
    writes.add((ref: ref, text: text, id: id, reply: reply));
    return reply.future;
  }
}

DirectPage history({
  bool allowed = true,
  List<DirectMessage> messages = const [],
}) => DirectPage('secret-A', messages, 0, 0, false, 'friend', canSend: allowed);

void main() {
  testWidgets(
    'draft follows stable conversation key when Host target ref renews',
    (tester) async {
      final port = ComposePort(), views = <Map<String, Object?>>[];
      final lease = MenuCommsSession(port, views.add)..show(true);
      MenuCommsView view() => MenuCommsView.parse(jsonEncode(views.last));
      Future<String> select(String ref) async {
        port.directories.last.complete([
          Conversation(
            ref,
            'Fixture',
            '',
            DateTime.utc(2026),
            0,
            'friend',
            conversationKey: 'A' * 64,
          ),
        ]);
        await tester.pump();
        final key = view().rows.single.key;
        lease.act('select', key);
        port.histories.last.reply.complete(
          DirectPage(ref, [], 0, 0, false, 'friend', canSend: true),
        );
        await tester.pump();
        return key;
      }

      final first = await select('old-ref');
      lease.compose('edit', first, 'retained draft', 1);
      lease.show(false);
      lease.show(true);
      final second = await select('renewed-ref');
      expect(view().draft, 'retained draft');
      lease.compose('send', second, view().draft, 2);
      expect(port.writes.single.ref, 'renewed-ref');
      lease.show(false);
      port.writes.single.reply.complete(const DirectSendResult('rejected'));
      await tester.pump();
      lease.dispose();
      await tester.pump();
    },
  );
  testWidgets(
    'explicit send uses current target; uncertainty persists across hide and reconciles',
    (tester) async {
      final port = ComposePort(), views = <Map<String, Object?>>[];
      final lease = MenuCommsSession(port, views.add)..show(true);
      MenuCommsView view() => MenuCommsView.parse(jsonEncode(views.last));
      Future<String> select() async {
        port.directories.last.complete([peer('A')]);
        await tester.pump();
        final key = view().rows.single.key;
        lease.act('select', key);
        port.histories.last.reply.complete(history());
        await tester.pump();
        return key;
      }

      final key = await select();
      expect(view().canSend, true);
      lease.compose('edit', key, 'draft', 1);
      lease.compose('send', 'secret-A', 'wrong ref', 2);
      lease.compose('send', key, 'old', 1);
      expect(port.sends, 0);
      lease.compose('send', key, 'draft', 2);
      expect(port.sends, 1);
      expect(view().delivery, 'sending');
      expect(view().locked, true);
      lease.compose('send', key, 'duplicate', 3);
      lease.show(false);
      port.writes.single.reply.complete(const DirectSendResult('unknown'));
      await tester.pump();
      expect(port.sends, 1);
      lease.show(true);
      final next = await select();
      expect(next, isNot(key));
      expect(view().draft, 'draft');
      expect(view().delivery, 'unknown');
      lease.compose('send', next, 'duplicate', 10);
      expect(port.sends, 1);
      lease.compose('check', next, 'draft', 10);
      final write = port.writes.single;
      port.histories.last.reply.complete(
        history(
          messages: [
            DirectMessage(
              1,
              write.id,
              false,
              write.text,
              DateTime.utc(2026),
              null,
            ),
          ],
        ),
      );
      await tester.pump();
      expect(view().draft, '');
      expect(view().delivery, 'sent');
      expect(jsonEncode(views.last), isNot(contains(write.id)));
      expect(jsonEncode(views.last), isNot(contains('secret-A')));
      expect(port.receipts, 0);
      lease.dispose();
      await tester.pump();
    },
  );
  testWidgets(
    'permission revocation and account invalidation do not send or retain old drafts',
    (tester) async {
      final port = ComposePort(), views = <Map<String, Object?>>[];
      final lease = MenuCommsSession(port, views.add)..show(true);
      MenuCommsView view() => MenuCommsView.parse(jsonEncode(views.last));
      Future<String> select(bool allowed) async {
        port.directories.last.complete([peer('A')]);
        await tester.pump();
        final key = view().rows.single.key;
        lease.act('select', key);
        port.histories.last.reply.complete(history(allowed: allowed));
        await tester.pump();
        return key;
      }

      final key = await select(false);
      lease.compose('send', key, 'private draft', 1);
      expect(port.sends, 0);
      expect(view().draft, 'private draft');
      lease.show(false);
      lease.show(true);
      await select(true);
      expect(view().draft, 'private draft');
      port.events.add(null);
      final newKey = await select(true);
      expect(view().draft, '');
      lease.compose('send', key, 'old account', 99);
      expect(port.sends, 0);
      lease.compose('send', newKey, 'new draft', 1);
      port.events.add(null);
      port.writes.single.reply.complete(const DirectSendResult('sent'));
      await tester.pump();
      await select(true);
      expect(view().draft, '');
      expect(view().delivery, 'idle');
      expect(port.sends, 1);
      lease.dispose();
      await tester.pump();
    },
  );
}
