import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_invitations.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_invite_port.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';

import 'menu_channel_media_session_test.dart' show PhotoPort;
import 'menu_comms_invitations_test.dart' show InvitePort;
import 'menu_comms_session_test.dart' show Port;
import '../../features/communities/community_admission_test.dart'
    show AdmissionPrivacy;
import '../../features/communities/community_workspace_test.dart'
    show workspacePayload;
import '../../features/communities/community_chat_test.dart' show chatPage;

final _cjk = RegExp(r'[\u3400-\u9fff\uf900-\ufaff\u3000-\u303f\uff00-\uffef]');
Object? _input(Object? value) {
  if (value is String) return _cjk.hasMatch(value) ? 'Fixture' : value;
  if (value is Map) {
    return <String, Object?>{
      for (final e in value.entries) e.key as String: _input(e.value),
    };
  }
  if (value is List) return [for (final item in value) _input(item)];
  return value;
}

class _Organizations extends PhotoPort {
  @override
  Future<CommunityWorkspace> readWorkspace(
    String targetRef,
    String query,
    int offset,
  ) async {
    workspaceReads++;
    return CommunityWorkspace.parse(
      _input(workspacePayload(target: targetRef, query: query))
          as Map<String, Object?>,
    );
  }

  @override
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  }) async =>
      CommunityChatPage.parse(_input(chatPage()) as Map<String, Object?>);
}

class _Rooms implements PartyRoomsPort {
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<void> close() async {}
  @override
  Future<RoomReadResult> read() async => RoomReadResult(
    RoomReadState.ready,
    directory: RoomDirectory(rooms: [], serverTime: DateTime.utc(2026)),
  );
}

class _Invites extends InvitePort {
  @override
  CommunityInvitePreview get value => const CommunityInvitePreview(
    previewRef: '1234567890abcdef1234567890abcdef',
    name: 'Organization',
    code: 'ORG',
    commander: 'Owner',
    memberCount: 10,
    joinPolicy: 'direct',
    expiresAt: null,
    remainingUses: -1,
    alreadyMember: false,
  );
}

Future<void> verifyEnglishSessions(WidgetTester tester) async {
  const locale = Locale('en', 'US');
  void check(Map<String, Object?> value) {
    final wire = jsonEncode(value);
    expectSync(_cjk.hasMatch(wire), isFalse, reason: wire);
    expectSync(wire, isNot(contains('Instance of')));
    expectSync(wire, isNot(contains('menu.overlay.')));
  }

  Future<void> flush() async {
    for (var i = 0; i < 15; i++) {
      await tester.pump();
    }
  }

  final orgPort = _Organizations(), orgViews = <Map<String, Object?>>[];
  final org = MenuOrganizationsSession(
    orgPort,
    orgViews.add,
    locale: () => locale,
  )..show(true);
  await flush();
  check(orgViews.last);
  final view = MenuFeatureView.parse(orgViews.last);
  final members = view.organization?.sections['members'];
  expect(members, isNotNull);
  org.act(members!, '');
  await flush();
  check(orgViews.last);
  org.dispose();
  final rooms = MenuRoomsSession(_Rooms(), check, locale: () => locale)
    ..show(true);
  await flush();
  rooms.dispose();
  final directPort = Port();
  final comms = MenuCommsSession(directPort, check, locale: () => locale)
    ..show(true);
  await flush();
  directPort.directories.single.complete([]);
  await flush();
  comms.dispose();
  final invites = _Invites(), views = <Map<String, Object?>>[];
  final privacy = AdmissionPrivacy(invites.calls);
  final session = MenuCommsInvitations(
    invites,
    views.add,
    locale: () => locale,
    createPrivacy: () => privacy,
  );
  session.openAttachment('synthetic-invite');
  await flush();
  check(views.last);
  final review = MenuFeatureView.parse(views.last).buttons
      .singleWhere((b) => b.role == 'reviewSharing');
  session.act(review.key, '');
  await flush();
  check(views.last);
  expect(
    MenuFeatureView.parse(views.last).rows
        .expand((r) => r.buttons)
        .any((b) => b.role == 'togglePublication'),
    isTrue,
  );
  session.dispose();
  await tester.pump(const Duration(seconds: 3));
  await flush();
}
