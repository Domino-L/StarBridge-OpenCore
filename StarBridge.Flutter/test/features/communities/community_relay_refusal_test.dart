import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/bridge_communities.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_admissions_port.dart';
import 'package:starbridge_flutter/features/communities/community_invite_port.dart';
import 'package:starbridge_flutter/features/communities/community_member_removal_port.dart';
import 'package:starbridge_flutter/features/communities/community_member_role_port.dart';
import 'package:starbridge_flutter/features/communities/community_ownership_transfer_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'bridge_communities_test.dart' show CommunityHarness;
import 'community_leave_test.dart' show LeavePort, member;

const _refusals = ['identityRequired', 'identityAmbiguous'];

void main() {
  for (final reason in _refusals) {
    test(
      'ordinary exit refused with $reason is explained, not uncertain',
      () async {
        final port = LeavePort()..status = reason;
        final model = CommunitiesModule(port);
        await model.refresh();
        await model.execute(member, 'leave');
        expect(model.message, reason);
        expect(port.writes, 1);
        await model.refreshJoined();
        expect(port.writes, 1, reason: 'a refused write is never replayed');
        expect(model.joined.single.targetRef, member.targetRef);
        model.dispose();
      },
    );

    test('execute passes the Host refusal $reason through', () async {
      final host = CommunityHarness(
        responses: {
          'communities.execute': {
            'schemaVersion': 1,
            'status': 'rejected',
            'error': reason,
          },
        },
      );
      addTearDown(host.close);
      expect(await host.adapter.execute('join', 'a' * 32), reason);
    });

    test('write outcomes accept the refusal $reason', () {
      final value = <String, Object?>{
        'schemaVersion': 1,
        'status': 'rejected',
        'error': reason,
      };
      expect(CommunityAdmissionOutcome.parse(value).error, reason);
      expect(CommunityMemberRemovalOutcome.parse(value).error, reason);
      expect(CommunityMemberRoleOutcome.parse(value).error, reason);
      expect(CommunityOwnershipTransferOutcome.parse(value).error, reason);
      expect(CommunityInviteOutcome.parse(value).error, reason);
    });
  }

  for (final (status, error, expected) in [
    ('rejected', 'notAllowed', 'rejected'),
    ('unknown', 'identityAmbiguous', 'unknown'),
    ('rejected', 'somethingElse', 'rejected'),
  ]) {
    test('execute keeps $status/$error as $expected', () async {
      final host = CommunityHarness(
        responses: {
          'communities.execute': {
            'schemaVersion': 1,
            'status': status,
            'error': error,
          },
        },
      );
      addTearDown(host.close);
      expect(await host.adapter.execute('join', 'a' * 32), expected);
    });
  }

  for (final scmOnly in [true, false]) {
    test(
      'disband ${scmOnly ? 'is not' : 'is'} offered ${scmOnly ? 'to' : 'without'} '
      'a blocked SCM-only account; invitation delivery always is (relay r49)',
      () async {
        final pair = InMemoryBridgeConnection.createPair();
        final session =
            BridgeClientSession(connection: pair.client, sessionGeneration: 1)
              ..acceptHostCapabilities([
                'communities.read',
                'communities.disbandPreview',
                'communities.disband',
                'communities.sendInvite',
              ]);
        final adapter = BridgeCommunities(session, scmOnly: () => scmOnly);
        expect(adapter.disbandAvailable, !scmOnly);
        expect(adapter.invitationSendingAvailable, isTrue);
        await adapter.close();
        await session.close();
        await pair.host.close();
      },
    );
  }
}
