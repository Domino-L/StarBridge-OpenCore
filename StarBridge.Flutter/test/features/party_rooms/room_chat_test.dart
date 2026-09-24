import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_module.dart';
import 'package:starbridge_flutter/features/party_rooms/bridge_room_chat.dart';

import 'bridge_party_rooms_test.dart' show Harness;
import 'room_lifecycle_widget_test.dart' show openExampleRooms;

RoomChatMessage message(int sequence) => RoomChatMessage(
  sequence: sequence,
  id: 'm-$sequence',
  sender: '呼号 (Handle_CN)',
  text: '消息 $sequence',
  time: DateTime.utc(2026),
);

class ChatPort implements RoomChatPort {
  @override
  bool available = true;
  final cursors = <int>[];
  int sends = 0;
  Future<RoomChatPage> Function(int, int)? reading;
  Future<RoomChatMessage> Function()? sending;
  @override
  Future<RoomChatPage> read(
    String roomId, {
    int after = 0,
    int before = 0,
  }) async {
    cursors.add(after);
    return reading?.call(after, before) ?? RoomChatPage([message(1)], 1, false);
  }

  @override
  Future<RoomChatMessage> send(String roomId, String text) async {
    sends++;
    return sending?.call() ?? message(5);
  }
}

void main() {
  testWidgets('unread messages and latest reload do not lose the draft', (
    tester,
  ) async {
    final port = ChatPort();
    final module = RoomChatModule(port);
    module.setRoom('one');
    await tester.pump();
    module.setFollowing(false);
    module.draft = 'keep draft';
    port.reading = (_, _) async => RoomChatPage([message(2)], 2, false);
    await module.refresh();
    expect(module.unread, 1);
    await module.refresh();
    expect(module.unread, 1);
    await module.refresh(latest: true);
    expect(port.cursors.last, 0);
    expect(module.unread, 0);
    expect(module.followLatest, isTrue);
    expect(module.draft, 'keep draft');
    module.dispose();
    await tester.pump();
  });
  testWidgets(
    'confirmed access loss clears private history until membership is verified',
    (tester) async {
      final port = ChatPort();
      final module = RoomChatModule(port);
      module.setRoom('one');
      await tester.pump();
      module.draft = 'private';
      port.reading = (_, _) async => throw const RoomChatFailure('notMember');
      await module.refresh();
      expect(module.messages, isEmpty);
      expect(module.draft, isEmpty);
      expect(module.available, isFalse);
      final reads = port.cursors.length;
      await tester.pump(const Duration(seconds: 16));
      expect(port.cursors.length, reads);
      port.reading = (_, _) async => RoomChatPage([message(2)], 2, false);
      module.setRoom('one', verified: true);
      await tester.pump();
      expect(module.available, isTrue);
      expect(module.messages.single.sequence, 2);
      module.dispose();
      await tester.pump();
    },
  );
  testWidgets(
    'chat uses received cursor, catches up pages, and own send cannot skip peers',
    (tester) async {
      final port = ChatPort();
      final module = RoomChatModule(port);
      module.setRoom('one');
      await tester.pump();
      module.draft = 'hello';
      expect(await module.send(), isTrue);
      expect(module.messages.last.sequence, 5);
      port.reading = (after, before) async => after == 1
          ? RoomChatPage([message(2), message(3)], 5, true)
          : RoomChatPage([message(4), message(5)], 5, true);
      await module.refresh();
      expect(port.cursors, [0, 1, 3]);
      expect(module.messages.map((item) => item.sequence), [1, 2, 3, 4, 5]);
      module.dispose();
      await tester.pump();
    },
  );
  testWidgets('unknown send retains draft and blocks blind replay', (
    tester,
  ) async {
    final port = ChatPort()
      ..sending = () async => throw const RoomChatFailure('outcomeUnknown');
    final module = RoomChatModule(port);
    module.setRoom('one');
    await tester.pump();
    module.draft = 'do not lose';
    expect(await module.send(), isFalse);
    expect(module.draft, 'do not lose');
    expect(module.uncertain, isTrue);
    expect(await module.send(), isFalse);
    expect(port.sends, 1);
    module.acknowledgeUncertain();
    expect(module.uncertain, isFalse);
    module.dispose();
    await tester.pump();
  });
  testWidgets('room change discards late history and draft', (tester) async {
    final pending = Completer<RoomChatPage>();
    final port = ChatPort()..reading = (_, _) => pending.future;
    final module = RoomChatModule(port);
    module.setRoom('one');
    module.draft = 'private draft';
    module.setRoom(null);
    pending.complete(RoomChatPage([message(1)], 1, false));
    await tester.pump();
    expect(module.messages, isEmpty);
    expect(module.draft, '');
    expect(module.roomId, isNull);
    module.dispose();
    await tester.pump();
  });
  test(
    'chat Bridge keeps account context and no optimistic malformed success',
    () async {
      final host = Harness(
        capabilities: ['partyRooms.chat'],
        commandPayload: {'schemaVersion': 1, 'status': 'sent'},
      );
      final port = BridgeRoomChat(host.session);
      await expectLater(
        port.send('one', 'hello'),
        throwsA(
          isA<RoomChatFailure>().having(
            (e) => e.code,
            'code',
            'outcomeUnknown',
          ),
        ),
      );
      expect(host.requests.last.accountContext?.subject, 'test-subject');
      expect(
        host.requests.where((r) => r.name == 'partyRooms.execute'),
        hasLength(1),
      );
      await host.close();
    },
  );
  testWidgets('real chat panel sends example message and clears on room exit', (
    tester,
  ) async {
    final composition = await openExampleRooms(tester);
    await composition.partyRooms.selectPreviewScene('current');
    await tester.pumpAndSettle();
    expect(find.text('房间聊天'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('room-chat-draft')), '这是验收消息');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(composition.partyRooms.chat!.messages.last.text, '这是验收消息');
    expect(composition.partyRooms.chat!.draft, '');
    await composition.partyRooms.selectPreviewScene('directory');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-chat-draft')), findsNothing);
    expect(composition.partyRooms.chat!.messages, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
