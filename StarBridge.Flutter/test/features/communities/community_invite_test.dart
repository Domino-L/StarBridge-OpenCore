import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_invite_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

Map<String, Object?> invitePayload() => {
  'schemaVersion': 1,
  'previewRef': 'a' * 32,
  'name': 'Organization B',
  'code': 'B',
  'commander': 'Example owner',
  'memberCount': 12,
  'joinPolicy': 'Invite',
  'expiresAt': '2026-09-08T12:00:00Z',
  'remainingUses': 3,
  'alreadyMember': false,
  'acceptMode': 'direct',
  'unrelated': 'must-not-forward',
};

void main() {
  test('legacy S2 invitation uses Relay account without SCM and retains membership conflict', () async {
    final host = CommunityHarness(
      legacy: true,
      capabilities: ['communities.invites'],
      responses: {
        'communities.previewInvite': invitePayload()
          ..['membershipConflict'] = true,
        'communities.acceptInvite': {
          'schemaVersion': 1,
          'status': 'rejected',
          'error': 'membershipConflict',
        },
      },
    );
    addTearDown(host.close);
    final preview = await host.adapter.previewInvite('FIXTURE');
    expect(preview.membershipConflict, isTrue);
    expect(
      (await host.adapter.acceptInvite('b' * 32, preview.previewRef)).error,
      'membershipConflict',
    );
    expect(
      host.requests.where((r) => r.name.startsWith('communities.')),
      hasLength(2),
    );
  });
  for (final accepting in [false, true]) {
    test(
      'account invalidation rejects late invitation ${accepting ? 'acceptance' : 'preview'}',
      () async {
        final name = accepting
            ? 'communities.acceptInvite'
            : 'communities.previewInvite';
        final host = CommunityHarness(
          capabilities: ['communities.invites'],
          holdNames: {name},
          responses: {
            name: accepting
                ? {'schemaVersion': 1, 'status': 'accepted'}
                : invitePayload(),
          },
        );
        addTearDown(host.close);
        final Future<void> checked;
        if (accepting) {
          checked = expectLater(
            host.adapter.acceptInvite('b' * 32, 'a' * 32),
            completion(
              isA<CommunityInviteOutcome>().having(
                (v) => v.status,
                'status',
                'unknown',
              ),
            ),
          );
        } else {
          checked = expectLater(
            host.adapter.previewInvite('INVITE-B'),
            throwsA(isA<CommunityFailure>()),
          );
        }
        await host.readArrived.future;
        final invalidation = host.adapter.invalidations.first;
        await host.connection.send(
          const BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'event',
            name: 'account.changed',
            sessionGeneration: 5,
            sequence: 1,
            payload: {'schemaVersion': 1},
          ),
        );
        await invalidation;
        await checked;
        await host.reply(host.requests.firstWhere((r) => r.name == name));
        expect(host.requests.where((r) => r.name == name), hasLength(1));
      },
    );
  }
  test(
    'invite preview reads bounded WPF fields without exposing raw payload',
    () {
      final value = CommunityInvitePreview.parse(invitePayload());
      expect(value.name, 'Organization B');
      expect(value.membershipConflict, isFalse);
      expect(
        CommunityInvitePreview.parse(
          invitePayload()..['membershipConflict'] = true,
        ).membershipConflict,
        isTrue,
      );
      expect(
        CommunityInviteOutcome.parse({
          'schemaVersion': 1,
          'status': 'rejected',
          'error': 'membershipConflict',
        }).error,
        'membershipConflict',
      );
      expect(value.remainingUses, 3);
      expect(value.expiresAt, DateTime.utc(2026, 9, 8, 12));
      final unlimited = invitePayload()
        ..['expiresAt'] = null
        ..['remainingUses'] = -1;
      expect(CommunityInvitePreview.parse(unlimited).expiresAt, isNull);
    },
  );
  test('malformed previews cannot become actionable', () {
    for (final entry in <MapEntry<String, Object?>>[
      const MapEntry('schemaVersion', 2),
      const MapEntry('previewRef', 'raw-invitation'),
      MapEntry('name', 'x' * 513),
      const MapEntry('code', ''),
      const MapEntry('memberCount', -1),
      const MapEntry('remainingUses', -2),
      const MapEntry('expiresAt', 'invalid'),
      const MapEntry('alreadyMember', 'false'),
      const MapEntry('membershipConflict', 'false'),
      const MapEntry('acceptMode', 'unknown'),
    ]) {
      expect(
        () => CommunityInvitePreview.parse(
          invitePayload()..[entry.key] = entry.value,
        ),
        throwsFormatException,
      );
    }
  });
  test('preview capability is explicit and uses current account', () async {
    final host = CommunityHarness(
      capabilities: ['communities.invites'],
      responses: {'communities.previewInvite': invitePayload()},
    );
    addTearDown(host.close);
    final preview = await host.adapter.previewInvite('INVITE-B');
    expect(preview.code, 'B');
    expect(host.requests.map((r) => r.name), [
      'account.getCurrent',
      'communities.previewInvite',
    ]);
    expect(host.requests.last.accountContext?.subject, 'test-subject');
    expect(host.requests.last.payload, {
      'schemaVersion': 1,
      'inviteCode': 'INVITE-B',
    });
  });
  test(
    'acceptance sends only intent and issued preview reference once',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.invites'],
        responses: {
          'communities.acceptInvite': {
            'schemaVersion': 1,
            'status': 'accepted',
          },
        },
      );
      addTearDown(host.close);
      expect(
        (await host.adapter.acceptInvite('b' * 32, 'a' * 32)).status,
        'accepted',
      );
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'requestId': 'b' * 32,
        'previewRef': 'a' * 32,
      });
      expect(
        host.requests.where((r) => r.name == 'communities.acceptInvite'),
        hasLength(1),
      );
    },
  );
  test(
    'missing invitation capability makes no account or network request',
    () async {
      final host = CommunityHarness();
      addTearDown(host.close);
      await expectLater(
        host.adapter.previewInvite('INVITE-B'),
        throwsA(isA<CommunityFailure>()),
      );
      expect(
        (await host.adapter.acceptInvite('b' * 32, 'a' * 32)).status,
        'rejected',
      );
      expect(host.requests, isEmpty);
    },
  );
  test('expired or revoked preview has a specific recoverable error', () async {
    final host = CommunityHarness(
      capabilities: ['communities.invites'],
      error: 'communities.inviteInvalid',
    );
    addTearDown(host.close);
    await expectLater(
      host.adapter.previewInvite('INVITE-B'),
      throwsA(
        isA<CommunityFailure>().having((e) => e.code, 'code', 'inviteInvalid'),
      ),
    );
  });
  test(
    'malformed or failed acceptance reply never claims rejection or retries',
    () async {
      for (final error in [null, 'host.transport_failed']) {
        final host = CommunityHarness(
          capabilities: ['communities.invites'],
          error: error,
          responses: {
            'communities.acceptInvite': {
              'schemaVersion': 1,
              'status': 'not-a-receipt',
            },
          },
        );
        addTearDown(host.close);
        expect(
          (await host.adapter.acceptInvite('b' * 32, 'a' * 32)).status,
          'unknown',
        );
        expect(
          host.requests.where((r) => r.name == 'communities.acceptInvite'),
          hasLength(1),
        );
      }
    },
  );
}
