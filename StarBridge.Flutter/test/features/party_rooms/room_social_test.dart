import 'dart:async';

import 'package:starbridge_flutter/features/party_rooms/room_invitation_card.dart';
import 'package:starbridge_flutter/features/party_rooms/room_directory_card.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';

import 'party_rooms_test.dart' show TestRoomsPort, ready, wire, room;
import 'room_lifecycle_widget_test.dart' show openExampleRooms;

void main() {
  testWidgets('active room polling follows authority and stops outside page', (
    tester,
  ) async {
    final port = TestRoomsPort();
    final module = PartyRoomsModule(
      port,
      refreshInterval: const Duration(seconds: 8),
    );
    module.enter();
    await tester.pump();
    expect(port.reads, 1);
    port.result = ready(wire(current: 'a', rooms: [room('a')]));
    await tester.pump(const Duration(seconds: 8));
    await tester.pump();
    expect(module.directory!.currentRoomId, 'a');
    port.pending = Completer<RoomReadResult>();
    await tester.pump(const Duration(seconds: 8));
    final reads = port.reads;
    await tester.pump(const Duration(seconds: 40));
    expect(port.reads, reads);
    module.leave();
    port.pending!.complete(ready(wire()));
    await tester.pump();
    expect(
      module.directory!.currentRoomId,
      'a',
      reason: 'late response after leaving is ignored',
    );
    await tester.pump(const Duration(seconds: 40));
    expect(port.reads, reads);
    module.dispose();
    await tester.pump();
  });
  testWidgets(
    'room invite acceptance confirms and host can invite and revoke',
    (tester) async {
      final composition = await openExampleRooms(tester);
      final module = composition.partyRooms;
      await tester.tap(find.text('房间邀请 · 1'));
      await tester.pumpAndSettle();
      final card = find.byType(RoomInvitationCard);
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.byType(RoomJoinFacts)),
        findsOneWidget,
      );
      for (final label in ['交流语言', '队长当前服务器', '队长游戏版本', '语音要求']) {
        expect(
          find.descendant(of: card, matching: find.text(label)),
          findsOneWidget,
        );
      }
      final join = find.descendant(
        of: card,
        matching: find.widgetWithText(FilledButton, '加入房间'),
      );
      expect(join, findsOneWidget);
      expect(
        find.descendant(
          of: card,
          matching: find.widgetWithText(TextButton, '拒绝'),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(join);
      await tester.tap(join);
      await tester.pumpAndSettle();
      expect(module.directory!.currentRoomId, isNull);
      await tester.tap(find.widgetWithText(FilledButton, '加入房间').last);
      await tester.pumpAndSettle();
      expect(module.directory!.currentRoomId, 'example-cargo');
      await module.selectPreviewScene('host');
      await tester.pumpAndSettle();
      await tester.tap(find.text('邀请好友'));
      await tester.pumpAndSettle();
      expect(find.text('示例好友 (Example_Friend)'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '邀请'));
      await tester.pumpAndSettle();
      expect(module.directory!.sentInvitations, hasLength(1));
      await tester.tap(find.widgetWithText(TextButton, '撤回'));
      await tester.pumpAndSettle();
      expect(module.directory!.sentInvitations, isEmpty);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
