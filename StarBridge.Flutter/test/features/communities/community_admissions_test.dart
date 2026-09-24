import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_admissions_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

Map<String, Object?> admissionsPayload() => {
  'schemaVersion': 1,
  'targetRef': 'a' * 32,
  'section': 'applications',
  'offset': 0,
  'next': null,
  'totalCount': 1,
  'access': {
    'canReadApplications': true,
    'canDecideApplications': false,
    'canReadInvites': true,
    'canCreateInvite': true,
    'canSendInvitationCard': true,
  },
  'items': [
    {
      'entryRef': 'b' * 32,
      'gameName': 'Applicant',
      'callsign': 'Callsign',
      'message': 'Hello\nthere',
      'status': 'Pending',
      'createdAt': null,
      'hasAvatar': true,
      'privateAccount': 'discard',
    },
  ],
  'fetchedAt': '2026-09-07T12:00:00Z',
};
void main() {
  test(
    'current invite is validated independently and old hosts remain unknown',
    () {
      final row = <String, Object?>{
        'entryRef': 'd' * 32,
        'code': 'MY-CODE',
        'createdBy': 'Aster',
        'isOwn': true,
        'status': 'Active',
        'createdAt': null,
        'expiresAt': '2026-09-14T12:00:00Z',
        'usedCount': 0,
        'maxUses': 1,
        'canRevoke': true,
      };
      final data = admissionsPayload()
        ..['section'] = 'invites'
        ..['items'] = [row];
      CommunityAdmissionsPage parse(Map<String, Object?> value) =>
          CommunityAdmissionsPage.parse(value, 'a' * 32, 'invites', 0);
      expect(parse(data).currentInviteAvailable, isFalse);
      expect(
        parse({...data, 'currentInviteAvailable': true, 'currentInvite': null})
            .currentInvite,
        isNull,
      );
      final page = parse({
        ...data,
        'currentInviteAvailable': true,
        'currentInvite': row,
      });
      expect(page.currentInvite!['code'], 'MY-CODE');
      expect(
        () => page.currentInvite!['code'] = 'changed',
        throwsUnsupportedError,
      );
      for (final mutation in <Map<String, Object?>>[
        {'isOwn': false},
        {'status': 'Revoked'},
        {'entryRef': 'not-a-reference'},
        {'code': 'CONFLICTING-CODE'},
        {'usedCount': -1},
      ]) {
        expect(
          () => parse({
            ...data,
            'currentInviteAvailable': true,
            'currentInvite': {...row, ...mutation},
          }),
          throwsFormatException,
        );
      }
      expect(
        () => parse({...data, 'currentInvite': row}),
        throwsFormatException,
      );
      expect(
        () => parse({...data, 'currentInviteAvailable': true}),
        throwsFormatException,
      );
      expect(
        () => parse({...data, 'currentInviteAvailable': 'true'}),
        throwsFormatException,
      );
    },
  );
  test('management payload retains only validated immutable fields', () {
    final page = CommunityAdmissionsPage.parse(
      admissionsPayload(),
      'a' * 32,
      'applications',
      0,
    );
    expect(page.items.single['hasAvatar'], isTrue);
    expect(page.items.single.containsKey('privateAccount'), isFalse);
    expect(page.access['canDecideApplications'], isFalse);
    expect(
      () => page.items.single['message'] = 'changed',
      throwsUnsupportedError,
    );
    expect(
      () => page.access['canDecideApplications'] = true,
      throwsUnsupportedError,
    );
  });
  test('mismatched targets and incomplete pages fail closed', () {
    for (final mutation in <String, Object?>{
      'schemaVersion': 2,
      'targetRef': 'c' * 32,
      'section': 'invites',
      'offset': 1,
      'next': 20,
      'totalCount': 2,
      'fetchedAt': 'bad',
    }.entries) {
      expect(
        () => CommunityAdmissionsPage.parse(
          admissionsPayload()..[mutation.key] = mutation.value,
          'a' * 32,
          'applications',
          0,
        ),
        throwsFormatException,
      );
    }
  });
  test('capability unavailable means no account or data request', () async {
    final host = CommunityHarness(capabilities: []);
    addTearDown(host.close);
    await expectLater(
      host.adapter.readAdmissions('a' * 32, 'applications', 0),
      throwsA(isA<CommunityFailure>()),
    );
    expect(host.requests, isEmpty);
  });
  test(
    'management read carries scoped target and correct dedicated capability',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.admissions'],
        responses: {'communities.admissions': admissionsPayload()},
      );
      addTearDown(host.close);
      final page = await host.adapter.readAdmissions(
        'a' * 32,
        'applications',
        0,
      );
      expect(page.totalCount, 1);
      expect(host.requests.last.name, 'communities.admissions');
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'targetRef': 'a' * 32,
        'section': 'applications',
        'offset': 0,
      });
    },
  );
  test('account switch rejects late management data', () async {
    final host = CommunityHarness(
      capabilities: ['communities.admissions'],
      holdNames: {'communities.admissions'},
      responses: {'communities.admissions': admissionsPayload()},
    );
    addTearDown(host.close);
    final pending = expectLater(
      host.adapter.readAdmissions('a' * 32, 'applications', 0),
      throwsA(isA<CommunityFailure>()),
    );
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
    await pending;
    await host.reply(host.requests.last);
  });
}
