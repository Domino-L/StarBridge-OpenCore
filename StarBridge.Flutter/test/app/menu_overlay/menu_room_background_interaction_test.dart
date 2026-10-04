import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_room_member_menu.dart';
import 'package:starbridge_flutter/features/party_rooms/room_member_menu.dart';

import '../../features/friends/social_layout_test.dart' show app;

import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_commands.dart';

import 'menu_room_management_test.dart' show RoomPort;

class SlowRoomPort extends RoomPort {
  Completer<RoomReadResult>? pendingRead;
  int reads = 0;
  @override
  Future<RoomReadResult> read() {
    reads++;
    return pendingRead?.future ?? super.read();
  }
}

void main() {
  testWidgets('account invalidation retires old member actions during refresh', (tester) async {
    final port = SlowRoomPort();
    final views = <Map<String, Object?>>[];
    final session = MenuRoomsSession(port, views.add)..show(true);
    await tester.pump();
    final action = MenuFeatureView.parse(views.last).rows[2].buttons.single;
    final pending = port.pendingRead = Completer<RoomReadResult>();
    final refresh = session.refresh(silent: true);
    port.changes.add(null);
    session.act(action.key, '');
    expect(port.calls, isEmpty);
    pending.complete(const RoomReadResult(RoomReadState.unavailable));
    await refresh;
    await tester.pump();
    expect(port.calls, isEmpty);
    session.dispose();
  });
  testWidgets(
    'unchanged confirmation survives a background action-reference renewal',
    (tester) async {
      var key = 'a1';
      late StateSetter rebuild;
      final calls = <String>[];
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return MenuRoomMemberMenu(
                enabled: true,
                action: (
                  key: key,
                  label: '移出房间',
                  confirm: '移出测试成员？',
                  input: null,
                  limit: 128,
                ),
                dispatch: (key, _) => calls.add(key),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(RoomMemberMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移出房间'));
      await tester.pumpAndSettle();
      rebuild(() => key = 'a2');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '移出房间'));
      await tester.pumpAndSettle();
      expect(
        calls,
        ['a1'],
        reason: 'Dispatch the exact confirmed target, never retarget to the new reference.',
      );
    },
  );
  testWidgets('silent room read does not reject a visible member action', (
    tester,
  ) async {
    final port = SlowRoomPort();
    final views = <Map<String, Object?>>[];
    final session = MenuRoomsSession(port, views.add)..show(true);
    await tester.pump();
    final action = MenuFeatureView.parse(views.last).rows[2].buttons.single;
    final pending = port.pendingRead = Completer<RoomReadResult>();
    final refresh = session.refresh(silent: true);
    session.act(action.key, '');
    await tester.pump();
    expect(port.calls, hasLength(1));
    pending.complete(const RoomReadResult(RoomReadState.unavailable));
    await refresh;
    await tester.pump();
    session.dispose();
  });

  test(
    'client keeps current room controls available during a background read',
    () async {
      final port = SlowRoomPort();
      final module = PartyRoomsModule(port);
      await module.refresh();
      final pending = port.pendingRead = Completer<RoomReadResult>();
      final refresh = module.refresh();
      expect(module.canManage, isTrue);
      await module.execute(
        RoomCommand(RoomOperation.remove, {
          'roomId': 'private-room',
          'removalToken': 'private-removal-token',
        }),
      );
      expect(port.calls, hasLength(1));
      pending.complete(const RoomReadResult(RoomReadState.unavailable));
      await refresh;
      expect(
        module.state,
        RoomReadState.ready,
        reason:
            'Retired background response cannot overwrite the command state.',
      );
      module.dispose();
    },
  );

  testWidgets(
    'background read cannot block invalidation or stop later refreshes',
    (tester) async {
      final port = SlowRoomPort();
      final module = PartyRoomsModule(port)..startSession();
      await tester.pump();
      final pending = port.pendingRead = Completer<RoomReadResult>();
      final refresh = module.refresh();
      await module.execute(
        RoomCommand(RoomOperation.remove, {
          'roomId': 'private-room',
          'removalToken': 'private-removal-token',
        }),
      );
      port.pendingRead = null;
      pending.complete(const RoomReadResult(RoomReadState.unavailable));
      await refresh;
      final count = port.reads;
      await tester.pump(const Duration(seconds: 9));
      expect(port.reads, greaterThan(count));
      port.pendingRead = Completer<RoomReadResult>();
      port.changes.add(null);
      expect(module.directory, isNull);
      expect(module.canManage, isFalse);
      module.dispose();
    },
  );
}
