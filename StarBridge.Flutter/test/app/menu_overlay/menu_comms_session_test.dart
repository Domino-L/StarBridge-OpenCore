import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';

class Port
    implements DirectMessagesPort, DirectMessageSender, DirectReadReceiptPort {
  final events = StreamController<void>.broadcast(sync: true);
  final directories = <Completer<List<Conversation>>>[];
  final histories = <({String ref, int before, Completer<DirectPage> reply})>[];
  int cancels = 0, sends = 0, receipts = 0;
  bool closed = false;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<List<Conversation>> directory() {
    final reply = Completer<List<Conversation>>();
    directories.add(reply);
    return reply.future;
  }

  @override
  Future<DirectPage> history(String ref, {int before = 0, int after = 0}) {
    final reply = Completer<DirectPage>();
    histories.add((ref: ref, before: before, reply: reply));
    return reply.future;
  }

  @override
  void cancel() => cancels++;
  @override
  Future<void> close() async {
    closed = true;
    await events.close();
  }

  @override
  bool get supportsSending => true;
  @override
  bool get supportsReadReceipts => true;
  @override
  Future<DirectSendResult> send(String ref, String text, String id) async {
    sends++;
    return const DirectSendResult('sent');
  }

  @override
  Future<DirectReadReceipt> markRead(String ref, int through) async {
    receipts++;
    return const DirectReadReceipt(1, 0);
  }
}

Conversation peer(String name, {String? avatar}) => Conversation(
  'secret-$name',
  name,
  'not-for-directory-preview',
  DateTime.utc(2026),
  3,
  'active',
  avatar: avatar,
);
DirectPage page(
  String ref, {
  int oldest = 10,
  bool older = true,
  String text = 'Hello',
}) => DirectPage(
  ref,
  [
    DirectMessage(
      oldest,
      'server-message-id',
      true,
      text,
      DateTime.utc(2026),
      'fleet_invitation',
    ),
  ],
  oldest,
  oldest,
  older,
  'active',
  canSend: true,
);

void main() {
  testWidgets(
    'profile targets retire on selection, close and account invalidation',
    (tester) async {
      final port = Port(), views = <Map<String, Object?>>[];
      final lease = MenuCommsSession(port, views.add);
      lease.show(true);
      port.directories.single.complete([peer('A')]);
      await tester.pump();
      final key = MenuCommsView.parse(jsonEncode(views.last)).rows.single.key;
      final directoryTarget = lease.profileTarget(key)!;
      expect(directoryTarget.source, 'conversation');
      expect(directoryTarget.reference, 'secret-A');
      expect(lease.profileTarget('secret-A'), isNull);
      lease.act('select', key);
      expect(directoryTarget.isCurrent(), false);
      port.histories.single.reply.complete(page('secret-A'));
      await tester.pump();
      expect(MenuCommsView.parse(jsonEncode(views.last)).profileKey, key);
      final target = lease.profileTarget(key)!;
      expect(target.isCurrent(), true);
      final own = lease.profileTarget('self')!;
      expect(own.source, 'self');
      expect(own.reference, isEmpty);
      expect(own.isCurrent(), true);
      lease.show(false);
      expect(target.isCurrent(), false);
      expect(own.isCurrent(), false);
      expect(target.isAccountCurrent(), true);
      port.events.add(null);
      expect(target.isAccountCurrent(), false);
      expect(own.isAccountCurrent(), false);
      expect(port.sends + port.receipts, 0);
      lease.dispose();
      await tester.pump();
    },
  );
  testWidgets('refresh retains current row keys but removes revoked targets', (
    tester,
  ) async {
    final port = Port(), views = <Map<String, Object?>>[];
    final lease = MenuCommsSession(port, views.add)..show(true);
    port.directories.last.complete([peer('Retained'), peer('Removed')]);
    await tester.pump();
    final original = MenuCommsView.parse(jsonEncode(views.last)).rows;
    await tester.pump(const Duration(seconds: 10));
    port.directories.last.complete([peer('Retained')]);
    await tester.pump();
    expect(
      MenuCommsView.parse(jsonEncode(views.last)).rows.single.key,
      original.first.key,
    );
    lease.act('select', original.last.key);
    expect(port.histories, isEmpty);
    lease.dispose();
  });
  testWidgets(
    'directory and history are explicit reads without writes or receipts',
    (tester) async {
      final port = Port(), views = <Map<String, Object?>>[];
      final lease = MenuCommsSession(port, views.add);
      expect(port.directories, isEmpty);
      lease.show(true);
      lease.show(true);
      expect(port.directories.length, 1);
      port.directories.last.complete([
        peer('Pilot', avatar: 'https://not-allowed.invalid/avatar'),
      ]);
      await tester.pump();
      final view = MenuCommsView.parse(jsonEncode(views.last));
      expect(view.rows.single.unread, 3);
      expect(jsonEncode(views.last), isNot(contains('secret-')));
      expect(jsonEncode(views.last), contains('not-for-directory-preview'));
      lease.act('select', 'secret-Pilot');
      expect(port.histories, isEmpty);
      lease.act('select', view.rows.single.key);
      expect(port.histories.single.ref, 'secret-Pilot');
      lease.act('select', view.rows.single.key);
      expect(port.histories.length, 1);
      port.histories.last.reply.complete(
        page('secret-Pilot', text: 'a' * 3000),
      );
      await tester.pump();
      final history = MenuCommsView.parse(jsonEncode(views.last));
      expect(history.avatar, null);
      expect(history.messages.single.text.length, 3000);
      expect(history.messages.single.attachment, true);
      expect(jsonEncode(views.last), isNot(contains('server-message-id')));
      lease.act('send', 'ignored');
      expect(port.sends, 0);
      expect(port.receipts, 0);
      lease.dispose();
    },
  );

  testWidgets('older paging is bounded and polling never jumps to latest', (
    tester,
  ) async {
    final port = Port(), views = <Map<String, Object?>>[];
    final lease = MenuCommsSession(port, views.add)..show(true);
    port.directories.last.complete([peer('Pilot')]);
    await tester.pump();
    lease.act(
      'select',
      MenuCommsView.parse(jsonEncode(views.last)).rows.single.key,
    );
    port.histories.last.reply.complete(page('secret-Pilot'));
    await tester.pump();
    lease.act('older', '');
    expect(port.histories.last.before, 10);
    port.histories.last.reply.complete(
      page('secret-Pilot', oldest: 1, older: false),
    );
    await tester.pump();
    expect(MenuCommsView.parse(jsonEncode(views.last)).olderPage, true);
    await tester.pump(const Duration(seconds: 10));
    expect(port.histories.last.before, 10);
    port.histories.last.reply.complete(
      page('secret-Pilot', oldest: 1, older: false),
    );
    await tester.pump();
    lease.act('latest', '');
    expect(port.histories.last.before, 0);
    final late = port.histories.last.reply;
    lease.show(false);
    late.complete(page('secret-Pilot'));
    await tester.pump(const Duration(seconds: 30));
    expect(views.last, {'state': 'idle'});
    expect(port.histories.length, 4);
    lease.dispose();
  });

  testWidgets(
    'account switch clears history and rejects old UI keys and late responses',
    (tester) async {
      final port = Port(), views = <Map<String, Object?>>[];
      final lease = MenuCommsSession(port, views.add)..show(true);
      port.directories.last.complete([peer('Old')]);
      await tester.pump();
      final oldKey = MenuCommsView.parse(jsonEncode(views.last))
          .rows
          .single
          .key;
      lease.act('select', oldKey);
      port.events.add(null);
      expect(views.last, {'state': 'loading'});
      port.histories.last.reply.complete(page('secret-Old'));
      await tester.pump();
      expect(views.last, {'state': 'loading'});
      port.directories.last.complete([peer('New')]);
      await tester.pump();
      lease.act('select', oldKey);
      expect(port.histories.length, 1);
      expect(
        MenuCommsView.parse(jsonEncode(views.last)).rows.single.name,
        'New',
      );
      lease.dispose();
    },
  );

  testWidgets(
    'wrong history identity, revoked access and timeout clear all content',
    (tester) async {
      final port = Port(), views = <Map<String, Object?>>[];
      final lease = MenuCommsSession(port, views.add)..show(true);
      port.directories.last.complete([peer('Pilot')]);
      await tester.pump();
      lease.act(
        'select',
        MenuCommsView.parse(jsonEncode(views.last)).rows.single.key,
      );
      port.histories.last.reply.complete(page('different-target'));
      await tester.pump();
      expect(views.last, {'state': 'unavailable'});
      lease.act('retry', '');
      port.directories.last.completeError(const DirectReadFailure('forbidden'));
      await tester.pump();
      expect(views.last, {'state': 'restricted'});
      lease.act('retry', '');
      final cancels = port.cancels;
      await tester.pump(const Duration(seconds: 11));
      expect(port.cancels, greaterThan(cancels));
      expect(views.last, {'state': 'unavailable'});
      port.directories.last.complete([peer('Late')]);
      await tester.pump();
      expect(views.last, {'state': 'unavailable'});
      lease.dispose();
    },
  );

  test(
    'wire rejects external avatars, invalid counts and oversized history',
    () {
      for (final value in [
        null,
        '{}',
        '{"state":"ready","rows":[{"unread":-1}]}',
        jsonEncode({
          'state': 'ready',
          'name': 'X',
          'avatar': 'https://invalid.test',
          'messages': [],
        }),
      ]) {
        expect(MenuCommsView.parse(value).state, 'unavailable');
      }
    },
  );
}
