import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/platform/window/menu_preview_window_port.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';

import 'menu_comms_session_test.dart' show Port, peer, page;

void main() {
  testWidgets(
    'friend entry keeps directory and adds the selected conversation',
    (tester) async {
      final port = Port(), views = <Map<String, Object?>>[];
      final session = MenuCommsSession(port, views.add)..show(true);
      addTearDown(session.dispose);
      port.directories.single.complete([peer('Existing')]);
      await tester.pump();
      session.openChat(const MenuChatTarget('secret-Friend', 'Friend'));
      port.histories.last.reply.complete(page('secret-Friend'));
      await tester.pump();
      final view = MenuCommsView.parse(jsonEncode(views.last));
      expect(view.messages, isNotEmpty);
      expect(view.rows.map((r) => r.name), containsAll(['Existing', 'Friend']));
      expect(
        view.rows.where((r) => r.key == view.profileKey).single.name,
        'Friend',
      );
      session.dispose();
    },
  );
  testWidgets(
    'cold friend entry reads history first then supplements directory',
    (tester) async {
      final port = Port(), views = <Map<String, Object?>>[];
      final session = MenuCommsSession(port, views.add)..show(true);
      addTearDown(session.dispose);
      session.openChat(const MenuChatTarget('secret-Friend', 'Friend'));
      expect(port.directories.length, 1);
      port.histories.last.reply.complete(page('secret-Friend'));
      await tester.pump();
      expect(
        MenuCommsView.parse(jsonEncode(views.last)).rows.single.name,
        'Friend',
      );
      expect(port.directories.length, 2);
      port.directories.last.complete([peer('Existing'), peer('Friend')]);
      await tester.pump();
      port.directories.first.complete([peer('Obsolete')]);
      await tester.pump();
      final view = MenuCommsView.parse(jsonEncode(views.last));
      expect(
        view.rows.map((r) => r.name),
        unorderedEquals(['Existing', 'Friend']),
      );
      expect(view.messages, isNotEmpty);
      expect(port.sends, 0);
      expect(port.receipts, 0);
      session.dispose();
    },
  );
  testWidgets(
    'renewed friend reference reuses stable row and rejects late account data',
    (tester) async {
      final port = Port(), views = <Map<String, Object?>>[];
      final session = MenuCommsSession(port, views.add)..show(true);
      addTearDown(session.dispose);
      port.directories.single.complete([
        Conversation(
          'old-ref',
          'Friend',
          '',
          DateTime(2026),
          0,
          'friend',
          conversationKey: 'stable',
        ),
      ]);
      await tester.pump();
      final key = MenuCommsView.parse(jsonEncode(views.last)).rows.single.key;
      session.openChat(
        const MenuChatTarget('new-ref', 'Friend', stableKey: 'stable'),
      );
      port.histories.last.reply.complete(page('new-ref'));
      await tester.pump();
      final view = MenuCommsView.parse(jsonEncode(views.last));
      expect(view.rows.single.key, key);
      expect(view.profileKey, key);
      expect(jsonEncode(views.last), isNot(contains('new-ref')));
      session.openChat(const MenuChatTarget('other-ref', 'Other'));
      port.events.add(null);
      port.histories.last.reply.complete(page('other-ref'));
      await tester.pump();
      expect(views.last['state'], 'loading');
      port.directories.last.complete([]);
      await tester.pump();
      expect(MenuCommsView.parse(jsonEncode(views.last)).rows, isEmpty);
      session.dispose();
    },
  );
}
