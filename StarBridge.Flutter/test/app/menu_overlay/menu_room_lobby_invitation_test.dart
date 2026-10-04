import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_room_lobby_panel.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_commands.dart';
import 'package:starbridge_flutter/features/party_rooms/room_invitations.dart';

import 'menu_room_lobby_test.dart' show LobbySource;
import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;

class InvitedLobby extends LobbySource implements RoomInvitationsPort {
  @override
  bool supportsInvitations = true;
  bool joined = false,
      expired = false,
      unavailable = false,
      previewFails = false,
      mismatch = false;
  int count = 1;
  Completer<RoomCommandResult>? gate;
  Future<PartyRoom> get room async =>
      (await source.read()).directory!.rooms.first;
  @override
  Future<RoomReadResult> read() async {
    if (unavailable) return const RoomReadResult(RoomReadState.unavailable);
    final r = await room;
    return RoomReadResult(
      RoomReadState.ready,
      directory: RoomDirectory(
        rooms: joined ? [r] : [],
        currentRoomId: joined ? r.id : null,
        serverTime: DateTime(2026),
        receivedInvitations: [
          for (var i = 0; i < count; i++)
            RoomInvitation(
              id: 'private-invite-$i',
              roomId: r.id,
              title: 'Invite $i',
              inviter: 'Sender',
              recipient: 'Receiver',
              expiresAt: expired ? DateTime(2025) : DateTime(2099),
            ),
        ],
      ),
    );
  }

  @override
  Future<RoomCommandResult> execute(RoomCommand command) async {
    calls.add(command);
    if (gate != null) return gate!.future;
    if (command.operation == RoomOperation.invitePreview) {
      if (previewFails) throw StateError('synthetic');
      return RoomCommandResult('resolved', preview: await room);
    }
    if (unknown) {
      return const RoomCommandResult('unknown', error: 'outcomeUnknown');
    }
    if (mismatch) return const RoomCommandResult('declined');
    if (command.operation == RoomOperation.inviteJoin) {
      joined = true;
      count = 0;
      return const RoomCommandResult('joined');
    }
    if (command.operation == RoomOperation.inviteDecline) {
      count = 0;
      return const RoomCommandResult('declined');
    }
    return const RoomCommandResult('rejected');
  }
}

void main() {
  setUpAll(loadFonts);
  for (final scenario in [
    'preview',
    'join',
    'decline',
    'expired',
    'gone',
    'joined',
    'unavailable',
    'raw',
    'unknown',
    'mismatch',
    'previewFailure',
  ]) {
    testWidgets('lobby invitation $scenario', (tester) async {
      final port = InvitedLobby(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      await tester.pump();
      final lobby = MenuFeatureView.parse(views.last).lobby!;
      final item = lobby.directory.receivedInvitations.single;
      expect(jsonEncode(views.last), isNot(contains('private-invite')));
      final op = scenario.startsWith('preview')
          ? RoomOperation.invitePreview
          : scenario == 'decline'
          ? RoomOperation.inviteDecline
          : RoomOperation.inviteJoin;
      if (scenario == 'expired') port.expired = true;
      if (scenario == 'gone') port.count = 0;
      if (scenario == 'joined') port.joined = true;
      if (scenario == 'unavailable') port.unavailable = true;
      if (scenario == 'unknown') port.unknown = true;
      if (scenario == 'mismatch') port.mismatch = true;
      if (scenario == 'previewFailure') port.previewFails = true;
      final key = lobby.actions[op]!;
      session.act(
        key,
        jsonEncode({
          'request': 'q1',
          'data': {
            'roomId': item.roomId,
            'invitationId': scenario == 'raw' ? 'private-invite-0' : item.id,
          },
        }),
      );
      await tester.pump();
      if ([
        'expired',
        'gone',
        'joined',
        'unavailable',
        'raw',
      ].contains(scenario)) {
        expect(port.calls, isEmpty);
      } else {
        expect(port.calls, hasLength(1));
      }
      if (scenario == 'preview') {
        final current = MenuFeatureView.parse(views.last).lobby!;
        expect(current.invitationReply!['status'], 'resolved');
        session.act(
          current.actions[RoomOperation.join]!,
          jsonEncode({
            'request': 'q2',
            'data': {'roomId': item.roomId, 'password': ''},
          }),
        );
        await tester.pump();
        expect(
          port.calls,
          hasLength(1),
        ); // Invitation preview cannot authorize ordinary join.
      }
      if (scenario == 'previewFailure') {
        final current = MenuFeatureView.parse(views.last).lobby!;
        expect(current.invitationReply!['status'], 'rejected');
        expect(current.actions[RoomOperation.inviteJoin], isNotNull);
      }
      if (scenario == 'unknown' || scenario == 'mismatch') {
        expect(MenuFeatureView.parse(views.last).lobby!.actions, isEmpty);
      }
      session.act(
        key,
        jsonEncode({
          'request': 'q3',
          'data': {'roomId': item.roomId, 'invitationId': item.id},
        }),
      );
      await tester.pump();
      expect(port.calls.length, lessThanOrEqualTo(1));
      session.dispose();
    });
  }
  for (final retire in ['account', 'hide', 'room']) {
    testWidgets('late invitation preview after $retire is discarded', (
      tester,
    ) async {
      final port = InvitedLobby(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      await tester.pump();
      final lobby = MenuFeatureView.parse(views.last).lobby!,
          item = MenuFeatureView.parse(views.last)
              .lobby!
              .directory
              .receivedInvitations
              .single;
      port.gate = Completer<RoomCommandResult>();
      session.act(
        lobby.actions[RoomOperation.invitePreview]!,
        jsonEncode({
          'request': 'q1',
          'data': {'roomId': item.roomId, 'invitationId': item.id},
        }),
      );
      await tester.pump();
      if (retire == 'account') {
        port.changes.add(null);
        await tester.pump();
      } else {
        session.show(false);
        if (retire == 'room') port.joined = true;
      }
      port.gate!.complete(
        RoomCommandResult('resolved', preview: await port.room),
      );
      await tester.pump();
      session.show(true);
      await tester.pump();
      expect(MenuFeatureView.parse(views.last).lobby?.invitationReply, isNull);
      session.dispose();
    });
  }
  testWidgets(
    'shared invitation dialog previews sequentially then confirms join',
    (tester) async {
      size(tester, const Size(1280, 900));
      final port = InvitedLobby()..count = 2;
      final frame = ValueNotifier<Map<String, Object?>>({'state': 'loading'});
      final session = MenuRoomsSession(port, (v) => frame.value = v)
        ..show(true);
      await tester.pump();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        app(
          ValueListenableBuilder(
            valueListenable: frame,
            builder: (_, raw, _) => RepaintBoundary(
              key: boundary,
              child: MenuRoomsPanel(
                view: MenuFeatureView.parse(raw),
                onAction: session.act,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('房间邀请 · 2'));
      await tester.pumpAndSettle();
      expect(
        port.calls.where((c) => c.operation == RoomOperation.invitePreview),
        hasLength(2),
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      await capture(tester, boundary, 'menu-lobby-invitations-1280');
      final join = find.widgetWithText(FilledButton, '加入房间').first;
      await tester.ensureVisible(join);
      await tester.tap(join);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNWidgets(2));
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(
        port.calls.where((c) => c.operation == RoomOperation.inviteJoin),
        isEmpty,
      );
      await tester.tap(join);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '加入房间').last);
      await tester.pumpAndSettle();
      expect(
        port.calls.where((c) => c.operation == RoomOperation.inviteJoin),
        hasLength(1),
      );
      expect(find.byType(MenuRoomLobbyPanel), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      frame.dispose();
    },
  );
  testWidgets(
    'preview timeout is read failure and permits reopening; UI decline removes count',
    (tester) async {
      size(tester, const Size(1280, 900));
      final port = InvitedLobby()..gate = Completer<RoomCommandResult>();
      final frame = ValueNotifier<Map<String, Object?>>({'state': 'loading'});
      final session = MenuRoomsSession(port, (v) => frame.value = v)
        ..show(true);
      await tester.pump();
      await tester.pumpWidget(
        app(
          ValueListenableBuilder(
            valueListenable: frame,
            builder: (_, raw, _) => MenuRoomsPanel(
              view: MenuFeatureView.parse(raw),
              onAction: session.act,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('房间邀请 · 1'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(
        MenuFeatureView.parse(frame.value).lobby!.invitationReply!['status'],
        'rejected',
      );
      expect(
        MenuFeatureView.parse(frame.value)
            .lobby!
            .actions[RoomOperation.inviteJoin],
        isNotNull,
      );
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      port.gate!.complete(
        RoomCommandResult('resolved', preview: await port.room),
      );
      port.gate = null;
      await tester.pump();
      await tester.tap(find.text('房间邀请 · 1'));
      await tester.pumpAndSettle();
      final decline = find.widgetWithText(TextButton, '拒绝');
      await tester.ensureVisible(decline);
      await tester.tap(decline);
      await tester.pumpAndSettle();
      expect(
        port.calls.where((c) => c.operation == RoomOperation.inviteDecline),
        hasLength(1),
      );
      expect(find.text('房间邀请 · 0'), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      frame.dispose();
    },
  );
  testWidgets('renderer preview transport timeout is not an unknown write', (
    tester,
  ) async {
    final source = InvitedLobby(), views = <Map<String, Object?>>[];
    final session = MenuRoomsSession(source, views.add)..show(true);
    await tester.pump();
    final lobby = MenuFeatureView.parse(views.last).lobby!;
    final item = lobby.directory.receivedInvitations.single;
    final port = MenuRoomLobbyPort(lobby, (_, _) {});
    final result = port.execute(
      RoomCommand(RoomOperation.invitePreview, {
        'roomId': item.roomId,
        'invitationId': item.id,
      }),
    );
    await tester.pump(const Duration(seconds: 18));
    expect((await result).status, 'rejected');
    await port.close();
    session.dispose();
  });
}
