import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/bridge_party_rooms_adapter.dart';
import 'package:starbridge_flutter/features/party_rooms/room_commands.dart';

import 'party_rooms_test.dart' show room, wire, ready;
import 'room_commands_test.dart' show CommandPort;
import 'room_lifecycle_widget_test.dart' show openExampleRooms;

void main() {
  test(
    'pending applications are visible only in the current host projection',
    () {
      final item = {
        'applicationId': 'request-1',
        'callsign': '申请者',
        'gameId': 'Original_CASE',
        'createdAt': '2026-09-06T12:00:00Z',
      };
      final value = room('a')
        ..['viewerIsHost'] = true
        ..['pendingApplications'] = [item];
      expect(
        parseRoomDirectory(wire(rooms: [value]))
            .rooms
            .single
            .pendingApplications,
        isEmpty,
      );
      expect(
        parseRoomDirectory(wire(current: 'a', rooms: [value]))
            .rooms
            .single
            .pendingApplications
            .single
            .displayName,
        '申请者 (Original_CASE)',
      );
      value['pendingApplications'] = [item, item];
      expect(
        () => parseRoomDirectory(wire(current: 'a', rooms: [value])),
        throwsFormatException,
      );
      value['viewerIsHost'] = false;
      expect(
        parseRoomDirectory(wire(current: 'a', rooms: [value]))
            .rooms
            .single
            .pendingApplications,
        isEmpty,
      );
    },
  );

  test(
    'management requires current membership, host role and capability',
    () async {
      for (final current in [false, true]) {
        final port = ManagementPort()
          ..result = ready(
            wire(current: current ? 'a' : null, rooms: [room('a')]),
          );
        final module = PartyRoomsModule(port);
        await module.refresh();
        final result = await module.execute(
          RoomCommand(RoomOperation.close, {'roomId': 'a'}),
        );
        expect(result.accepted, isFalse);
        expect(port.calls, 0);
        module.dispose();
      }
      final port = CommandPort()
        ..result = ready(
          wire(current: 'a', rooms: [room('a')..['viewerIsHost'] = true]),
        );
      final module = PartyRoomsModule(port);
      await module.refresh();
      expect(module.canManage, isFalse);
      expect(
        (await module.execute(
          RoomCommand(RoomOperation.close, {'roomId': 'a'}),
        )).accepted,
        isFalse,
      );
      expect(port.calls, 0);
      module.dispose();
    },
  );

  test('ownership refresh rejects an already-open host action', () async {
    final port = ManagementPort()
      ..result = ready(
        wire(current: 'a', rooms: [room('a')..['viewerIsHost'] = true]),
      );
    final module = PartyRoomsModule(port);
    await module.refresh();
    expect(module.canManage, isTrue);
    final revision = module.contextRevision;
    port.result = ready(wire(current: 'a', rooms: [room('a')]));
    await module.refresh();
    expect(
      (await module.execute(
        RoomCommand(RoomOperation.close, {'roomId': 'a'}),
        expectedRevision: revision,
      )).error,
      'notHost',
    );
    expect(port.calls, 0);
    module.dispose();
  });

  testWidgets(
    'host edits settings, keeps password, handles requests and confirms disband',
    (tester) async {
      final composition = await openExampleRooms(tester);
      final module = composition.partyRooms;
      expect(find.widgetWithText(OutlinedButton, '房间设置'), findsNothing);
      await module.selectPreviewScene('host');
      await tester.pumpAndSettle();
      expect(module.canManage, isTrue);
      await tester.tap(find.widgetWithText(OutlinedButton, '房间设置'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('room-create-title')),
        '更新后的示例房间',
      );
      final passwordToggle = find.widgetWithText(SwitchListTile, '需要密码');
      await tester.ensureVisible(passwordToggle);
      await tester.tap(passwordToggle);
      await tester.pumpAndSettle();
      final password = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.obscureText,
      );
      await tester.ensureVisible(password);
      await tester.enterText(password, 'test-secret');
      await tester.tap(find.widgetWithText(FilledButton, '保存设置'));
      await tester.pumpAndSettle();
      expect(module.selectedRoom!.title, '更新后的示例房间');
      expect(module.selectedRoom!.passwordRequired, isTrue);
      await tester.tap(find.widgetWithText(OutlinedButton, '房间设置'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(password).controller!.text, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, '保存设置'));
      await tester.pumpAndSettle();
      expect(module.selectedRoom!.passwordRequired, isTrue);
      await tester.tap(find.widgetWithText(OutlinedButton, '加入申请 · 2'));
      await tester.pumpAndSettle();
      final count = module.selectedRoom!.members.length;
      await tester.tap(
        find.byKey(const ValueKey('approve-example-application-1')),
      );
      await tester.pumpAndSettle();
      expect(module.selectedRoom!.members.length, count + 1);
      expect(find.text('已批准加入申请。'), findsWidgets);
      await tester.tap(
        find.byKey(const ValueKey('decline-example-application-2')),
      );
      await tester.pumpAndSettle();
      expect(module.selectedRoom!.members.length, count + 1);
      expect(module.selectedRoom!.pendingApplications, isEmpty);
      expect(find.text('暂无待处理的加入申请。'), findsOneWidget);
      expect(module.commandMessage, 'declined');
      await tester.tap(find.widgetWithText(TextButton, '完成'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '解散房间'));
      await tester.pumpAndSettle();
      expect(find.textContaining('所有成员'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(module.directory!.currentRoomId, isNotNull);
      await tester.tap(find.widgetWithText(OutlinedButton, '解散房间'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '解散房间'));
      await tester.pumpAndSettle();
      expect(module.directory!.currentRoomId, isNull);
      expect(find.widgetWithText(OutlinedButton, '房间设置'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class ManagementPort extends CommandPort implements RoomManagementPort {
  @override
  bool get supportsManagement => true;
}
