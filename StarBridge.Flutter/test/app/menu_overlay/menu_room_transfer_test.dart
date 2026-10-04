import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_commands.dart';
import 'package:starbridge_flutter/features/party_rooms/bridge_party_rooms_adapter.dart';

import 'menu_room_management_test.dart' show RoomPort;
import '../../features/party_rooms/party_rooms_test.dart' show wire, room;

class TransferPort extends RoomPort {
  bool enabled = true;
  String outcome = 'hostTransferred';
  @override
  Future<RoomReadResult> read() async {
    final original = (await super.read()).directory!;
    return RoomReadResult(
      RoomReadState.ready,
      directory: RoomDirectory(
        rooms: original.rooms,
        currentRoomId: original.currentRoomId,
        serverTime: original.serverTime,
        supportsHostTransfer: enabled,
      ),
    );
  }

  @override
  Future<RoomCommandResult> execute(RoomCommand command) async {
    calls.add(command);
    if (outcome == 'hostTransferred') host = false;
    return RoomCommandResult(
      outcome,
      error: outcome == 'unknown' ? 'outcomeUnknown' : null,
      directory: outcome == 'hostTransferred' ? (await read()).directory : null,
    );
  }
}

void main() {
  test('old directory defaults transfer capability off, only explicit true enables', () {
    for (final enabled in [null, false, 'true', true]) {
      final value = wire(current: 'a', rooms: [room('a')]);
      if (enabled != null) value['supportsHostTransfer'] = enabled;
      expect(parseRoomDirectory(value).supportsHostTransfer, enabled == true);
    }
  });
  for (final state in [
    'oldServer',
    'notHost',
    'notJoined',
    'self',
    'host',
    'gone',
  ]) {
    test('module rejects transfer $state without dispatch', () async {
      final port = TransferPort()
        ..enabled = state != 'oldServer'
        ..host = state != 'notHost'
        ..joined = state != 'notJoined';
      final module = PartyRoomsModule(port);
      await module.refresh();
      final result = await module.execute(
        RoomCommand(RoomOperation.transferHost, {
          'roomId': 'private-room',
          'memberToken': switch (state) {
            'self' => 'never-self',
            'host' => 'never-host',
            'gone' => 'gone',
            _ => 'private-removal-token',
          },
        }),
      );
      expect(result.accepted, false);
      expect(port.calls, isEmpty);
      module.dispose();
    });
  }
  testWidgets('module reconciles transferred host and unknown cannot resend', (
    tester,
  ) async {
    for (final outcome in ['hostTransferred', 'unknown']) {
      final port = TransferPort()..outcome = outcome;
      final module = PartyRoomsModule(port);
      await module.refresh();
      expect(module.canTransferHost, true);
      final command = RoomCommand(RoomOperation.transferHost, {
        'roomId': 'private-room',
        'memberToken': 'private-removal-token',
      });
      await module.execute(command);
      expect(module.canTransferHost, false);
      await module.execute(command);
      expect(port.calls, hasLength(1));
      expect(module.commandNeedsRefresh, outcome == 'unknown');
      module.dispose();
    }
  });
  testWidgets(
    'menu transfer is opaque confirmed and old action cannot replay',
    (tester) async {
      final port = TransferPort(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      await tester.pump();
      final view = MenuFeatureView.parse(views.last);
      expect(view.room!.memberTransferActions.keys, [2]);
      final action = view.rows[2].buttons.singleWhere((a) => a.label == '转移房主');
      expect(action.confirm, contains('待处理邀请将失效'));
      expect(jsonEncode(views.last), isNot(contains('private-removal-token')));
      expect(jsonEncode(views.last), isNot(contains('private-room')));
      session.act(action.key, '');
      await tester.pump();
      expect(port.calls.single.operation, RoomOperation.transferHost);
      expect(port.calls.single.data['memberToken'], 'private-removal-token');
      session.act(action.key, '');
      await tester.pump();
      expect(port.calls, hasLength(1));
      expect(
        MenuFeatureView.parse(views.last).room!.memberTransferActions,
        isEmpty,
      );
      session.dispose();
    },
  );
  testWidgets('menu on old server has no transfer action', (tester) async {
    final port = TransferPort()..enabled = false;
    final views = <Map<String, Object?>>[];
    final session = MenuRoomsSession(port, views.add)..show(true);
    await tester.pump();
    expect(
      MenuFeatureView.parse(views.last).room!.memberTransferActions,
      isEmpty,
    );
    expect(jsonEncode(views.last), isNot(contains('转移房主')));
    session.dispose();
  });
}
