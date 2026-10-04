import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_commands.dart';
import 'package:starbridge_flutter/features/party_rooms/room_member_menu.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts;

class RoomPort implements PartyRoomsPort, RoomCommandsPort, RoomManagementPort {
  final changes = StreamController<void>.broadcast(sync: true);
  final calls = <RoomCommand>[];
  bool host = true,
      joined = true,
      full = false,
      closed = false,
      pending = false;
  @override
  bool supportsManagement = true;
  @override
  bool get supportsCommands => true;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<void> close() => changes.close();
  RoomMember member(
    String name, {
    bool isHost = false,
    bool isSelf = false,
    String? token,
  }) => RoomMember(
    callsign: name,
    gameId: name,
    isHost: isHost,
    isSelf: isSelf,
    presence: '应用在线',
    location: '',
    ship: '',
    shard: '',
    removalToken: token,
  );
  @override
  Future<RoomReadResult> read() async => RoomReadResult(
    RoomReadState.ready,
    directory: RoomDirectory(
      currentRoomId: joined ? 'private-room' : null,
      serverTime: DateTime(2026, 10, 1),
      viewerPendingRoomIds: pending ? ['private-room'] : [],
      rooms: [
        PartyRoom(
          id: 'private-room',
          title: '验收房间',
          goal: '协作',
          capacity: full ? 4 : 6,
          isPublic: true,
          eligibility: 'everyone',
          admissionMode: 'approval',
          passwordRequired: false,
          voice: 'preferred',
          language: 'zh',
          expiresAt: closed ? DateTime(2026) : DateTime(2027),
          recruitmentClosesAt: null,
          viewerIsHost: host,
          members: [
            member('Host', isHost: true, token: 'never-host'),
            member('Self', isSelf: true, token: 'never-self'),
            member('Member', token: 'private-removal-token'),
            member('NoToken'),
          ],
        ),
      ],
    ),
  );
  @override
  Future<RoomCommandResult> execute(RoomCommand command) async {
    calls.add(command);
    return RoomCommandResult(
      command.operation == RoomOperation.remove ? 'removed' : 'pending',
    );
  }
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'host removal uses opaque confirmed action; stale actions cannot remove',
    (tester) async {
      final port = RoomPort(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      await tester.pump();
      final view = MenuFeatureView.parse(views.last);
      expect(view.state, 'ready');
      expect(view.rows.expand((r) => r.buttons).length, 1);
      final remove = view.rows[2].buttons.single;
      expect(remove.confirm, contains('Member'));
      expect(jsonEncode(views.last), isNot(contains('private-removal-token')));
      expect(jsonEncode(views.last), isNot(contains('private-room')));
      for (final width in [1200.0, 390.0]) {
        size(tester, Size(width, 900));
        await tester.pumpWidget(
          app(MenuRoomsPanel(view: view, onAction: session.act)),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        // The accepted room layout keeps policy facts in its details section.
        if (find.widgetWithText(TextButton, '房间资料').evaluate().isNotEmpty) {
          await tester.tap(find.widgetWithText(TextButton, '房间资料'));
          await tester.pump();
        }
        expect(find.text('需要申请'), findsOneWidget);
      }
      final button = find.byType(RoomMemberMenu);
      await tester.scrollUntilVisible(
        button,
        180,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('menu-room-members')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('移出房间'));
      await tester.pumpAndSettle();
      expect(port.calls, isEmpty);
      expect(find.text(remove.confirm!), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '移出房间'));
      await tester.pump();
      expect(port.calls.single.operation, RoomOperation.remove);
      expect(port.calls.single.data['removalToken'], 'private-removal-token');
      expect(MenuFeatureView.parse(views.last).notice, '已将成员移出房间。');
      port.changes.add(null);
      session.act(remove.key, '');
      await tester.pump();
      expect(port.calls.length, 1);
      session.dispose();
    },
  );
  for (final mode in ['nonHost', 'noManagement', 'notJoined']) {
    testWidgets('$mode cannot remove members', (tester) async {
      final port = RoomPort();
      if (mode == 'nonHost') port.host = false;
      if (mode == 'noManagement') port.supportsManagement = false;
      if (mode == 'notJoined') port.joined = false;
      final views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      await tester.pump();
      if (!port.joined) {
        expect(MenuFeatureView.parse(views.last).lobby, isNotNull);
      }
      expect(
        MenuFeatureView.parse(views.last).rows.expand((r) => r.buttons),
        isEmpty,
      );
      session.dispose();
    });
  }
  for (final mode in ['approval', 'full', 'closed', 'pending']) {
    testWidgets('join availability follows client policy: $mode', (
      tester,
    ) async {
      final port = RoomPort()
        ..joined = false
        ..host = false;
      port.full = mode == 'full';
      port.closed = mode == 'closed';
      port.pending = mode == 'pending';
      final views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      await tester.pump();
      expect(port.calls, isEmpty);
      final lobby = MenuFeatureView.parse(views.last).lobby!;
      session.act(
        lobby.actions[RoomOperation.join]!,
        jsonEncode({
          'request': 'q1',
          'data': {'roomId': lobby.directory.rooms.single.id, 'password': ''},
        }),
      );
      await tester.pump();
      expect(port.calls.length, mode == 'approval' ? 1 : 0);
      if (port.calls.isNotEmpty) {
        expect(port.calls.single.data['roomId'], 'private-room');
      }
      session.dispose();
    });
  }
}
