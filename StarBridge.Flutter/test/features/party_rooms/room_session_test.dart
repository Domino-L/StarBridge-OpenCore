import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/shell/widgets/attention_badge.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_module.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

import 'party_rooms_test.dart' show TestRoomsPort, ready, wire, room;
import 'room_chat_test.dart' show ChatPort, message;
import 'room_lifecycle_widget_test.dart' show openExampleRooms;

class SessionPort extends TestRoomsPort implements RoomChatProvider {
  @override
  final ChatPort roomChat = ChatPort();
  SessionPort() {
    result = ready(wire(current: 'a', rooms: [room('a')]));
  }
}

void main() {
  testWidgets(
    'confirmed directory denial clears private state outside the room page',
    (tester) async {
      final port = SessionPort();
      final module = PartyRoomsModule(port)..startSession();
      await tester.pump();
      module.chat!.draft = 'private';
      port.result = const RoomReadResult(
        RoomReadState.unavailable,
        failure: 'forbidden',
      );
      await module.refresh();
      await tester.pump();
      expect(module.chat!.roomId, isNull);
      expect(module.chat!.draft, isEmpty);
      expect(module.chat!.messages, isEmpty);
      expect(module.activityCount.value, 0);
      module.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'background reads never overlap and membership exit clears chat',
    (tester) async {
      final port = SessionPort();
      final module = PartyRoomsModule(port)..startSession();
      await tester.pump();
      port.pending = Completer<RoomReadResult>();
      await tester.pump(const Duration(seconds: 8));
      final reads = port.reads;
      await tester.pump(const Duration(seconds: 40));
      expect(port.reads, reads);
      port.pending!.complete(ready(wire()));
      await tester.pump();
      expect(module.chat!.roomId, isNull);
      expect(module.chat!.messages, isEmpty);
      module.dispose();
      await tester.pump();
    },
  );

  testWidgets('app focus lifecycle keeps hidden room messages unread', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final port = SessionPort();
    final composition = AppComposition.forTest(
      windowChrome: InMemoryWindowChrome(),
      partyRoomsPort: port,
    );
    await tester.pumpWidget(StarBridgeApp(composition: composition));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('/rooms')));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    port.roomChat.reading = (_, _) async =>
        RoomChatPage([message(2)], 2, false);
    await composition.partyRooms.chat!.refresh();
    await tester.pump();
    expect(composition.partyRooms.chat!.unread, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(composition.partyRooms.chat!.unread, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'session receives off-page messages, preserves draft and stops explicitly',
    (tester) async {
      final port = SessionPort();
      final module = PartyRoomsModule(port)..startSession();
      await tester.pump();
      final chat = module.chat!;
      expect(chat.roomId, 'a');
      expect(chat.unread, 0, reason: 'History establishes a baseline');
      module.enter();
      await tester.pump();
      chat.draft = 'keep draft';
      module.leave();
      port.roomChat.reading = (_, _) async =>
          RoomChatPage([message(2)], 2, false);
      await tester.pump(const Duration(seconds: 8));
      await tester.pump();
      expect(chat.unread, 1);
      expect(module.activityCount.value, 1);
      expect(
        module.pendingCount.value,
        0,
        reason: 'Chat is not a notification-center item',
      );
      expect(chat.draft, 'keep draft');
      await chat.refresh();
      expect(chat.unread, 1, reason: 'Repeated page does not duplicate unread');
      module.enter();
      await tester.pump();
      expect(chat.unread, 0);
      expect(chat.draft, 'keep draft');
      module.stopSession();
      final reads = port.reads, chatReads = port.roomChat.cursors.length;
      await tester.pump(const Duration(seconds: 24));
      expect(port.reads, reads);
      expect(port.roomChat.cursors.length, chatReads);
      expect(chat.messages, isEmpty);
      module.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'unfocused page does not mark read; first history and own sends stay quiet',
    (tester) async {
      final port = SessionPort();
      final module = PartyRoomsModule(port)
        ..setForeground(false)
        ..startSession();
      await tester.pump();
      module.enter();
      await tester.pump();
      final chat = module.chat!;
      expect(chat.unread, 0);
      port.roomChat.reading = (_, _) async =>
          RoomChatPage([message(2)], 2, false);
      await chat.refresh();
      expect(chat.unread, 1);
      chat.setFollowing(true);
      expect(chat.unread, 1, reason: 'Following while hidden is not reading');
      chat.draft = 'local send';
      await chat.send();
      expect(chat.unread, 1);
      module.setForeground(true);
      expect(chat.unread, 0);
      chat.setFollowing(false);
      module.leave();
      port.roomChat.reading = (_, _) async =>
          RoomChatPage([message(6)], 6, false);
      await chat.refresh();
      module.enter();
      expect(
        chat.unread,
        1,
        reason: 'Returning while reading history preserves unread',
      );
      module.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'temporary read failure preserves draft but access loss and account switch clear it',
    (tester) async {
      final port = SessionPort();
      final module = PartyRoomsModule(port)..startSession();
      await tester.pump();
      final chat = module.chat!;
      chat.draft = 'private';
      port.result = const RoomReadResult(RoomReadState.unavailable);
      await module.refresh();
      expect(chat.draft, 'private');
      expect(chat.available, isFalse);
      port.result = ready(wire(current: 'a', rooms: [room('a')]));
      await module.refresh();
      await tester.pump();
      expect(chat.draft, 'private');
      expect(chat.available, isTrue);
      final pending = Completer<RoomChatPage>();
      port.roomChat.reading = (_, _) => pending.future;
      unawaited(chat.refresh());
      port.result = const RoomReadResult(RoomReadState.signedOut);
      port.events.add(null);
      await tester.pump();
      expect(chat.roomId, isNull);
      expect(chat.messages, isEmpty);
      expect(chat.draft, isEmpty);
      expect(module.activityCount.value, 0);
      pending.complete(RoomChatPage([message(9)], 9, false));
      await tester.pump();
      expect(chat.messages, isEmpty);
      final reads = port.reads;
      await tester.pump(const Duration(seconds: 24));
      expect(
        port.reads,
        reads,
        reason: 'Signed out waits for account invalidation',
      );
      module.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'room counters stay separate from the unified notification inbox',
    (tester) async {
      final composition = await openExampleRooms(tester);
      await composition.partyRooms.selectPreviewScene('host');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AttentionCount>(
              find.descendant(
                of: find.byKey(const Key('activity-party-rooms')),
                matching: find.byType(AttentionCount),
              ),
            )
            .count,
        3,
      );
      expect(
        tester
            .widget<AttentionBadge>(
              find.byKey(const Key('activity-notifications')),
            )
            .count,
        0,
      );
      await tester.tap(find.byTooltip('通知'));
      await tester.pumpAndSettle();
      expect(find.text('通知中心'), findsOneWidget);
      expect(find.text('房间提醒'), findsNothing);
      expect(find.textContaining('邀请人：'), findsNothing);
      expect(find.text('欢迎加入房间，出发前请确认路线。'), findsNothing);
      final openActions = find.byWidgetPredicate(
        (widget) =>
            widget is OutlinedButton &&
            widget.key.toString().contains('room-activity-open-'),
      );
      expect(openActions, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('mounted shell starts background sync before first room visit', (
    tester,
  ) async {
    final port = SessionPort();
    final composition = AppComposition.forTest(
      windowChrome: InMemoryWindowChrome(),
      partyRoomsPort: port,
    );
    await tester.pumpWidget(StarBridgeApp(composition: composition));
    await tester.pumpAndSettle();
    expect(port.reads, 1);
    expect(composition.partyRooms.chat!.roomId, 'a');
    await tester.pumpWidget(const SizedBox());
    final reads = port.reads;
    await tester.pump(const Duration(seconds: 24));
    expect(port.reads, reads);
  });
}
