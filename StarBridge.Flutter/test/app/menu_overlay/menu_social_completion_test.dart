import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_visible_receipts.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/platform/window/menu_preview_window_port.dart';

import 'menu_comms_session_test.dart' as dm;
import 'menu_friend_commands_test.dart' as friends;

void main() {
  testWidgets(
    'friend chat uses current opaque source and never sends on open',
    (tester) async {
      final port = friends.CommandPort(), views = <Map<String, Object?>>[];
      final source = MenuFriendsSession(port, views.add)..show(true);
      friends.answer(
        port,
        FriendsSnapshot(
          groups: {
            FriendsSection.friends: [
              FriendRow(
                'Peer',
                'peer',
                'friend',
                DateTime.utc(2026),
                targetRef: 'private-user',
                chatTargetRef: 'private-chat',
                conversationKey: 'private-stable',
              ),
            ],
          },
          results: [],
        ),
      );
      await tester.pump();
      final view = MenuFriendsView.parse(jsonEncode(views.last));
      final key = view.rows.single.key!;
      expect(view.chatKeys, {key});
      expect(jsonEncode(views.last), isNot(contains('private-')));
      final target = source.chatTarget(key)!;
      final messages = dm.Port(), output = <Map<String, Object?>>[];
      final chat = MenuCommsSession(messages, output.add)..show(true);
      chat.openChat(target);
      messages.directories.single.complete([]);
      messages.histories.single.reply.complete(dm.page('private-chat'));
      await tester.pump();
      expect(messages.histories.single.ref, 'private-chat');
      expect(messages.sends, 0);
      source.show(false);
      expect(source.chatTarget(key), isNull);
      source.dispose();
      chat.dispose();
      await tester.pump();
    },
  );
  testWidgets('self state shares controller and rejects old account key', (
    tester,
  ) async {
    final own = ValueNotifier(
      const ManualPresenceSnapshot(
        scope: 'A',
        confirmedMode: PresenceVisibility.online,
        canChange: true,
      ),
    );
    final writes = <PresenceVisibility>[];
    final controller = ManualPresenceController(
      source: own,
      write: (mode, scope) async {
        writes.add(mode);
        own.value = ManualPresenceSnapshot(
          scope: scope,
          confirmedMode: mode,
          canChange: true,
        );
      },
    );
    final port = friends.CommandPort(), output = <Map<String, Object?>>[];
    final session = MenuFriendsSession(port, output.add, presence: controller)
      ..show(true);
    friends.answer(port, friends.directory('friend'));
    await tester.pump();
    MenuFriendsView view() => MenuFriendsView.parse(jsonEncode(output.last));
    final oldKey = view().self!.key;
    expect(writes, isEmpty);
    session.act('presence', oldKey, 'invisible');
    await tester.pump();
    expect(view().self!.status, 'presence.invisible');
    own.value = const ManualPresenceSnapshot(
      scope: 'B',
      confirmedMode: PresenceVisibility.online,
      canChange: true,
    );
    session.act('presence', oldKey, 'invisible');
    await tester.pump();
    expect(writes, [PresenceVisibility.invisible]);
    session.dispose();
    controller.dispose();
    own.dispose();
    await tester.pump();
  });
  testWidgets(
    'read receipt only follows a currently projected incoming token',
    (tester) async {
      final port = dm.Port(), output = <Map<String, Object?>>[];
      final session = MenuCommsSession(port, output.add)..show(true);
      session.openChat(const MenuChatTarget('private-chat', 'Peer'));
      port.directories.single.complete([]);
      port.histories.single.reply.complete(dm.page('private-chat', oldest: 1));
      await tester.pump();
      final token = (output.last['receipts'] as Map).values.single as String;
      expect(port.receipts, 0);
      session.act('read', 'forged');
      expect(port.receipts, 0);
      session.act('read', token);
      await tester.pump();
      expect(port.receipts, 1);
      session.act('read', token);
      expect(port.receipts, 1);
      session.show(false);
      session.act('read', token);
      expect(port.receipts, 1);
      session.dispose();
      await tester.pump();
    },
  );
  testWidgets('covered or scrolled-out body never requests receipt', (
    tester,
  ) async {
    final reads = <String>[];
    Future<void> render(bool active) => tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 200,
          child: SingleChildScrollView(
            child: MenuVisibleReceipts(
              active: active,
              tokens: const {0: 'r1', 1: 'r2'},
              onRead: reads.add,
              builder: (keys) => Column(
                children: [
                  SizedBox(
                    key: keys[0],
                    height: 60,
                    child: const Text('visible'),
                  ),
                  const SizedBox(height: 1000),
                  SizedBox(
                    key: keys[1],
                    height: 60,
                    child: const Text('not visible'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await render(false);
    await tester.pump();
    expect(reads, isEmpty);
    await render(true);
    await tester.pump();
    expect(reads, ['r1']);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('inner message viewport also respects outer window clipping', (
    tester,
  ) async {
    final reads = <String>[];
    final outer = ScrollController();
    addTearDown(outer.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            height: 200,
            child: SingleChildScrollView(
              controller: outer,
              child: Column(
                children: [
                  const SizedBox(height: 350),
                  SizedBox(
                    height: 150,
                    child: MenuVisibleReceipts(
                      active: true,
                      tokens: const {0: 'r1'},
                      onRead: reads.add,
                      builder: (keys) => ListView(
                        children: [
                          SizedBox(
                            key: keys[0],
                            height: 60,
                            child: const Text('message'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, isEmpty);
    outer.jumpTo(300);
    await tester.pumpAndSettle();
    expect(reads, ['r1']);
    await tester.pumpWidget(const SizedBox());
  });
}
