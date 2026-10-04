import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_panel.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_commands.dart';
import 'package:starbridge_flutter/features/party_rooms/room_invitations.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_module.dart';

import 'menu_rooms_panel_test.dart' show Chat;

import 'menu_room_settings_test.dart' show SettingsPort;
import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;

class AdminPort extends SettingsPort
    implements RoomInvitationsPort, RoomChatProvider {
  @override
  final roomChat = Chat();
  @override
  bool supportsInvitations = true;
  bool applications = true, targets = true;
  Completer<RoomCommandResult>? gate;
  RoomInvitation invitation(String id) => RoomInvitation(
    id: id,
    roomId: 'private-room',
    title: '验收邀请',
    inviter: 'Inviter',
    recipient: 'Recipient',
    expiresAt: DateTime(2099),
  );
  @override
  Future<RoomReadResult> read() async {
    final result = await super.read();
    if (result.directory == null) return result;
    final d = result.directory!, r = d.rooms.single;
    return RoomReadResult(
      RoomReadState.ready,
      directory: RoomDirectory(
        currentRoomId: d.currentRoomId,
        serverTime: d.serverTime,
        tagOptions: d.tagOptions,
        receivedInvitations: [invitation('private-received')],
        sentInvitations: [invitation('private-sent')],
        rooms: [
          PartyRoom(
            id: r.id,
            title: r.title,
            goal: r.goal,
            capacity: r.capacity,
            isPublic: r.isPublic,
            eligibility: r.eligibility,
            admissionMode: r.admissionMode,
            passwordRequired: r.passwordRequired,
            voice: r.voice,
            language: r.language,
            expiresAt: r.expiresAt,
            recruitmentClosesAt: r.recruitmentClosesAt,
            viewerIsHost: r.viewerIsHost,
            members: r.members,
            tags: r.tags,
            pendingApplications: [
              if (applications)
                RoomApplication(
                  id: 'private-application',
                  callsign: 'Applicant',
                  gameId: '',
                  createdAt: DateTime(2026),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Future<RoomCommandResult> execute(RoomCommand command) async {
    calls.add(command);
    if (gate != null) return gate!.future;
    return RoomCommandResult(
      switch (command.operation) {
        RoomOperation.inviteTargets => 'targets',
        RoomOperation.invite => 'invited',
        RoomOperation.inviteDecline => 'declined',
        RoomOperation.inviteRevoke => 'revoked',
        RoomOperation.decide => 'approved',
        RoomOperation.close => status == 'unknown' ? 'unknown' : 'closed',
        _ => 'updated',
      },
      targets: [
        if (command.operation == RoomOperation.inviteTargets && targets)
          const RoomInviteTarget('private-target', 'Friend'),
      ],
    );
  }
}

void main() {
  setUpAll(loadFonts);
  for (final scenario in [
    'approve',
    'close',
    'decline',
    'revoke',
    'forged',
    'gone',
    'notHost',
    'unavailable',
    'unknown',
    'account',
  ]) {
    testWidgets('admin opaque command $scenario', (tester) async {
      final port = AdminPort(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      await tester.pump();
      final management = MenuFeatureView.parse(views.last).room!.management!;
      expect(jsonEncode(views.last), isNot(contains('private-application')));
      expect(jsonEncode(views.last), isNot(contains('private-received')));
      var operation = 'close';
      Map<String, Object?> data = {};
      if (scenario == 'approve' || scenario == 'gone') {
        operation = 'decide';
        data = {
          'applicationId': management.applications.single.id,
          'approve': true,
        };
      }
      if (scenario == 'decline' || scenario == 'revoke') {
        operation = scenario == 'decline' ? 'inviteDecline' : 'inviteRevoke';
        data = {
          'invitationId':
              (scenario == 'decline' ? management.received : management.sent)
                  .single
                  .id,
        };
      }
      if (scenario == 'forged') data = {'roomId': 'private-room'};
      if (scenario == 'gone') port.applications = false;
      if (scenario == 'notHost') port.host = false;
      if (scenario == 'unavailable') port.readUnavailable = true;
      if (scenario == 'unknown') port.status = 'unknown';
      if (scenario == 'account') port.gate = Completer<RoomCommandResult>();
      final key = management.actions[operation]!;
      session.act(key, jsonEncode({'request': 'q1', 'data': data}));
      await tester.pump();
      if (scenario == 'account') {
        port.changes.add(null);
        await tester.pump();
        port.gate!.complete(const RoomCommandResult('closed'));
        await tester.pump();
        expect(
          MenuFeatureView.parse(views.last).room!.management!.request,
          isNull,
        );
      } else if ([
        'forged',
        'gone',
        'notHost',
        'unavailable',
      ].contains(scenario)) {
        expect(port.calls, isEmpty);
      } else {
        expect(port.calls, hasLength(1));
        expect(port.calls.single.data['roomId'], 'private-room');
      }
      if (scenario == 'unknown') expect(views.last['notice'], contains('未确认'));
      session.act(key, jsonEncode({'request': 'q2', 'data': data}));
      await tester.pump();
      expect(port.calls.length, lessThanOrEqualTo(1));
      if (scenario == 'unknown') {
        expect(
          MenuFeatureView.parse(views.last).room!.management!.actions,
          isEmpty,
        );
      }
      session.dispose();
    });
  }
  testWidgets('invite target aliases revalidated before send', (tester) async {
    final port = AdminPort(), views = <Map<String, Object?>>[];
    final session = MenuRoomsSession(port, views.add)..show(true);
    await tester.pump();
    var m = MenuFeatureView.parse(views.last).room!.management!;
    session.act(
      m.actions['inviteTargets']!,
      jsonEncode({'request': 'q1', 'data': {}}),
    );
    await tester.pump();
    m = MenuFeatureView.parse(views.last).room!.management!;
    final target = m.reply!.targets.single.reference;
    expect(target, isNot('private-target'));
    session.act(
      m.actions['invite']!,
      jsonEncode({
        'request': 'q2',
        'data': {'targetRef': target},
      }),
    );
    await tester.pump();
    expect(port.calls.map((c) => c.operation), [
      RoomOperation.inviteTargets,
      RoomOperation.inviteTargets,
      RoomOperation.invite,
    ]);
    expect(port.calls.last.data['targetRef'], 'private-target');
    session.dispose();
  });
  testWidgets(
    'old management grant cannot survive leaving and returning to same room',
    (tester) async {
      final port = AdminPort(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      await tester.pump();
      final key = MenuFeatureView.parse(views.last)
          .room!
          .management!
          .actions['close']!;
      port.roomId = 'other-room';
      await session.refresh(silent: true);
      await tester.pump();
      port.roomId = 'private-room';
      await session.refresh(silent: true);
      await tester.pump();
      session.act(key, jsonEncode({'request': 'q1', 'data': {}}));
      await tester.pump();
      expect(port.calls, isEmpty);
      expect(views.last['rejectedAction'], key);
      session.dispose();
    },
  );
  for (final width in [1280.0, 1440.0, 700.0]) {
    testWidgets('shared full toolbar and dialogs $width', (tester) async {
      size(tester, Size(width, 900));
      final port = AdminPort();
      final notifier = ValueNotifier<Map<String, Object?>>({
        'state': 'loading',
      });
      final session = MenuRoomsSession(port, (v) => notifier.value = v)
        ..show(true);
      await tester.pump();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        app(
          ValueListenableBuilder(
            valueListenable: notifier,
            builder: (context, value, _) => RepaintBoundary(
              key: boundary,
              child: MenuRoomsPanel(
                view: MenuFeatureView.parse(value),
                onAction: session.act,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final text in [
        '房间邀请 · 1',
        '邀请好友',
        '退出房间',
        '房间设置',
        '加入申请 · 1',
        '解散房间',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      await capture(
        tester,
        boundary,
        'menu-room-complete-toolbar-${width.toInt()}',
      );
      await tester.tap(find.text('加入申请 · 1'));
      await tester.pumpAndSettle();
      expect(find.text('Applicant'), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('解散房间'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(port.calls, isEmpty);
      await tester.tap(find.text('邀请好友'));
      await tester.pumpAndSettle();
      expect(find.text('Friend'), findsOneWidget);
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.text('Friend'), findsOneWidget);
      await tester.tap(find.text('邀请').last);
      await tester.pumpAndSettle();
      expect(
        port.calls.where((c) => c.operation == RoomOperation.invite),
        hasLength(1),
      );
      port.host = false;
      await session.refresh(silent: true);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      notifier.dispose();
    });
  }
}
