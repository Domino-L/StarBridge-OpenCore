import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_commands.dart';
import 'package:starbridge_flutter/features/party_rooms/room_member_removal.dart';
import 'package:starbridge_flutter/features/party_rooms/room_members_panel.dart';
import 'package:starbridge_flutter/features/party_rooms/room_member_menu.dart';

import 'party_rooms_test.dart' show room, wire, ready;
import 'room_management_test.dart' show ManagementPort;
import '../friends/social_layout_test.dart' show app;

const token = '0123456789abcdef0123456789abcdef';
Map<String, Object?> removalRoom({bool host = true, bool peer = true}) {
  final value = room('a')..['viewerIsHost'] = host;
  final owner = Map<String, Object?>.from(
    (value['members'] as List).single as Map,
  )..['isSelf'] = true;
  value['members'] = [
    owner,
    if (peer)
      {
        ...owner,
        'callsign': '合成成员',
        'isSelf': false,
        'isHost': false,
        'removalToken': token,
      },
  ];
  return value;
}

void main() {
  test(
    'removal token is scoped to current host and current membership',
    () async {
      for (final host in [false, true]) {
        for (final joined in [false, true]) {
          final port = ManagementPort()
            ..result = ready(
              wire(
                current: joined ? 'a' : null,
                rooms: [removalRoom(host: host)],
              ),
            );
          final module = PartyRoomsModule(port);
          await module.refresh();
          final peer = module.directory!.rooms.single.members.last;
          expect(peer.removalToken, host && joined ? token : isNull);
          if (!host || !joined) {
            final result = await module.execute(
              RoomCommand(RoomOperation.remove, {
                'roomId': 'a',
                'removalToken': token,
              }),
            );
            expect(result.accepted, isFalse);
            expect(port.calls, 0);
          }
          module.dispose();
        }
      }
    },
  );

  for (final outcome in ['removed', 'rejected']) {
    testWidgets('confirmation $outcome sends one command and never replays', (
      tester,
    ) async {
      final port = ManagementPort()
        ..result = ready(wire(current: 'a', rooms: [removalRoom()]));
      final module = PartyRoomsModule(port);
      await module.refresh();
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => RoomMembersPanel(
                room: module.selectedRoom!,
                serverTime: module.directory!.serverTime,
                onRemove: (member) => removeRoomMember(context, module, member),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('移出房间'), findsNothing);
      await tester.tap(find.byType(RoomMemberMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移出房间'));
      await tester.pumpAndSettle();
      expect(find.textContaining('合成成员'), findsWidgets);
      expect(port.calls, 0);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(port.calls, 0);
      await tester.tap(find.byType(RoomMemberMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移出房间'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '移出房间'));
      await tester.pump();
      expect(port.calls, 1);
      port.pendingCommand.complete(
        RoomCommandResult(
          outcome,
          error: outcome == 'rejected' ? 'unavailable' : null,
          directory: outcome == 'removed'
              ? ready(wire(current: 'a', rooms: [removalRoom(peer: false)]))
                    .directory
              : null,
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 8));
      expect(port.calls, 1);
      expect(module.selectedRoom!.members.length, outcome == 'removed' ? 1 : 2);
      await tester.pumpWidget(const SizedBox());
      module.dispose();
    });
  }

  testWidgets('ownership lost while confirmation is open prevents submission', (
    tester,
  ) async {
    final port = ManagementPort()
      ..result = ready(wire(current: 'a', rooms: [removalRoom()]));
    final module = PartyRoomsModule(port);
    await module.refresh();
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => removeRoomMember(
              context,
              module,
              module.selectedRoom!.members.last,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    port.result = ready(wire(current: 'a', rooms: [removalRoom(host: false)]));
    await module.refresh();
    await tester.tap(find.widgetWithText(FilledButton, '移出房间'));
    await tester.pumpAndSettle();
    expect(port.calls, 0);
    expect(module.selectedRoom!.members.length, 2);
    await tester.pumpWidget(const SizedBox());
    module.dispose();
  });
}
