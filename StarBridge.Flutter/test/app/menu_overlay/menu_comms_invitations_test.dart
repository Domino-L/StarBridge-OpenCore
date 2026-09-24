import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_invitations.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_send_port.dart';
import 'package:starbridge_flutter/features/communities/community_invite_port.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';

import '../../features/communities/community_admission_test.dart'
    show AdmissionInvites, AdmissionPrivacy;

class InvitePort extends AdmissionInvites
    implements CommunitiesPort, CommunityInvitationSendPort {
  int sends = 0, resumes = 0;
  String? acceptedRequest, acceptedPreview;
  @override
  Future<CommunityInviteOutcome> acceptInvite(
    String requestId,
    String previewRef,
  ) async {
    acceptedRequest = requestId;
    acceptedPreview = previewRef;
    calls.add('accept');
    return result;
  }

  Completer<List<CommunityInvitationOperation>>? holdOutbox;
  @override
  bool get invitationSendingAvailable => true;
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async => CommunityDirectory(view, query, [
    CommunityCard(targetRef: 'b' * 32, name: '组织 B', relationship: 'member'),
  ]);
  @override
  Future<String> execute(String action, String targetRef) async =>
      throw StateError('not used');
  @override
  Future<void> close() async {
    await events.close();
  }

  @override
  Future<List<CommunityInvitationOperation>> readInvitationOutbox() async =>
      holdOutbox?.future ?? [];
  @override
  Future<CommunityInvitationProgress> sendInvitation({
    required String operationId,
    required String organizationRef,
    required String channel,
    required String destinationRef,
    required int maxUses,
  }) async {
    sends++;
    return CommunityInvitationProgress(operationId, 'sent');
  }

  @override
  Future<CommunityInvitationProgress> resumeInvitation(
    String operationId, {
    String action = 'check',
  }) async {
    resumes++;
    return CommunityInvitationProgress(operationId, 'unknown');
  }
}

void main() {
  testWidgets('timed out invitation preview cannot mint late action keys', (
    tester,
  ) async {
    final port = InvitePort(), views = <Map<String, Object?>>[];
    final pending = port.holdPreview = Completer<CommunityInvitePreview>();
    final session = MenuCommsInvitations(port, views.add)
      ..openAttachment('secret');
    await tester.pump(const Duration(seconds: 13));
    expect(views.last['state'], 'unavailable');
    pending.complete(port.value);
    await tester.pump();
    session.act('a1', '');
    await tester.pump();
    expect(views.last['state'], 'unavailable');
    expect(port.calls, isEmpty);
    session.dispose();
  });
  testWidgets(
    'invitation preview requires reviewed sharing and explicit admission',
    (tester) async {
      final port = InvitePort(), views = <Map<String, Object?>>[];
      final privacy = AdmissionPrivacy(port.calls);
      final session = MenuCommsInvitations(
        port,
        views.add,
        createPrivacy: () => privacy,
      );
      session.openAttachment('secret-invitation-code');
      await tester.pump();
      MenuFeatureView view() => MenuFeatureView.parse(views.last);
      void act(String label) => session.act(
        view().buttons.singleWhere((b) => b.label == label).key,
        '',
      );
      expect(view().state, 'ready');
      expect(port.calls, isEmpty);
      expect(jsonEncode(views.last), isNot(contains('secret-invitation-code')));
      expect(jsonEncode(views.last), isNot(contains(port.value.previewRef)));
      expect(view().buttons.where((b) => b.label == '保存选择并加入'), isEmpty);
      act('确认共享设置');
      await tester.pump();
      expect(port.calls, ['read']);
      final toggle = view().rows
          .singleWhere((r) => r.title == '实时状态共享')
          .buttons
          .single;
      session.act(toggle.key, '');
      await tester.pump();
      expect(port.calls, ['read']);
      act('我已确认共享选择');
      await tester.pump();
      final join = view().buttons.singleWhere((b) => b.label == '保存选择并加入');
      expect(join.confirm, isNotEmpty);
      session.act(join.key, '');
      session.act(join.key, '');
      await tester.pump();
      expect(port.calls, [
        'read',
        'save',
        'accept',
      ], reason: jsonEncode(views.last));
      expect(port.acceptedRequest, matches(RegExp(r'^[a-f0-9]{32}$')));
      expect(port.acceptedPreview, port.value.previewRef);
      expect(view().notice, contains('已加入组织'));
      session.dispose();
      await tester.pump();
      await privacy.events.close();
    },
  );
  testWidgets('only explicit fresh invitation command sends once', (
    tester,
  ) async {
    final port = InvitePort(), views = <Map<String, Object?>>[];
    final session = MenuCommsInvitations(port, views.add);
    final recipient = Conversation(
      'c' * 32,
      'Recipient',
      '',
      DateTime.utc(2026),
      0,
      'accepted',
    );
    var allowed = true;
    session.openSend(recipient, () => allowed);
    await tester.pump();
    final view = MenuFeatureView.parse(views.last);
    expect(port.sends, 0);
    final command = view.rows.single.buttons.single;
    expect(command.confirm, isNotEmpty);
    expect(jsonEncode(views.last), isNot(contains(recipient.ref)));
    session.act(command.key, '');
    session.act(command.key, '');
    await tester.pump();
    expect(port.sends, 1);
    session.openSend(recipient, () => allowed);
    await tester.pump();
    final stale = MenuFeatureView.parse(views.last).rows.single.buttons.single;
    allowed = false;
    session.act(stale.key, '');
    await tester.pump();
    expect(port.sends, 1);
    session.openRecords();
    await tester.pump();
    expect(port.resumes, 0);
    session.dispose();
  });
  testWidgets(
    'late outbox read after switching flow cannot mint recipient actions',
    (tester) async {
      final port = InvitePort(), views = <Map<String, Object?>>[];
      final pending = port.holdOutbox =
          Completer<List<CommunityInvitationOperation>>();
      final session = MenuCommsInvitations(port, views.add);
      session.openSend(
        Conversation(
          'c' * 32,
          'Recipient',
          '',
          DateTime.utc(2026),
          0,
          'accepted',
        ),
        () => true,
      );
      await tester.pump();
      session.openAttachment('secret');
      await tester.pump();
      pending.complete([]);
      await tester.pump();
      expect(MenuFeatureView.parse(views.last).title, '组织邀请');
      expect(port.sends, 0);
      session.dispose();
    },
  );
  testWidgets(
    'expired and conflicting invitations have no join or sharing command',
    (tester) async {
      for (final conflict in [false, true]) {
        final port = InvitePort()..conflict = conflict;
        if (!conflict) port.expiry = DateTime.utc(2020);
        final views = <Map<String, Object?>>[];
        final session = MenuCommsInvitations(port, views.add)
          ..openAttachment('secret');
        await tester.pump();
        final view = MenuFeatureView.parse(views.last);
        expect(view.buttons.map((b) => b.label), isNot(contains('确认共享设置')));
        expect(port.calls, isEmpty);
        session.dispose();
      }
    },
  );
}
