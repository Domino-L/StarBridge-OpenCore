import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_admissions_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

CommunityAdmissionIntent intent(
  CommunityAdmissionAction action, {
  bool retry = false,
}) => CommunityAdmissionIntent(
  requestId: 'a' * 32,
  targetRef: 'b' * 32,
  action: action,
  entryRef: action == CommunityAdmissionAction.generateInvite ? null : 'c' * 32,
  expiresInDays: action == CommunityAdmissionAction.generateInvite ? 7 : null,
  maxUses: action == CommunityAdmissionAction.generateInvite ? 1 : null,
  confirmUncertainRetry: retry,
);

void main() {
  for (final action in CommunityAdmissionAction.values) {
    test(
      '$action sends one scoped intent through dedicated write capability',
      () async {
        final host = CommunityHarness(
          capabilities: ['communities.manageAdmissions'],
          responses: {
            'communities.manageAdmissions': {
              'schemaVersion': 1,
              'status': 'accepted',
            },
          },
        );
        addTearDown(host.close);
        final draft = intent(action);
        expect((await host.adapter.manageAdmissions(draft)).status, 'accepted');
        expect(
          host.requests
              .where((r) => r.name == 'communities.manageAdmissions')
              .length,
          1,
        );
        expect(host.requests.last.payload, {
          'schemaVersion': 1,
          ...draft.toPayload(),
        });
        expect(host.requests.last.accountContext, isNotNull);
        expect(host.requests.last.payload['confirmUncertainRetry'], isFalse);
        expect(host.requests.last.payload.containsKey('fleetCode'), isFalse);
        expect(
          host.requests.last.payload.containsKey('applicationId'),
          isFalse,
        );
      },
    );
  }
  test(
    'read capability cannot authorize writes or trigger account request',
    () async {
      final host = CommunityHarness(capabilities: ['communities.admissions']);
      addTearDown(host.close);
      final result = await host.adapter.manageAdmissions(
        intent(CommunityAdmissionAction.approve),
      );
      expect(result.status, 'rejected');
      expect(result.error, 'unavailable');
      expect(host.requests, isEmpty);
    },
  );
  test(
    'invalid targets and WPF invite option bounds fail before any request',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.manageAdmissions'],
      );
      addTearDown(host.close);
      for (final draft in [
        CommunityAdmissionIntent(
          requestId: 'a' * 32,
          targetRef: 'raw-code',
          action: CommunityAdmissionAction.approve,
          entryRef: 'c' * 32,
        ),
        CommunityAdmissionIntent(
          requestId: 'a' * 32,
          targetRef: 'b' * 32,
          action: CommunityAdmissionAction.generateInvite,
          expiresInDays: 31,
          maxUses: 1,
        ),
        CommunityAdmissionIntent(
          requestId: 'a' * 32,
          targetRef: 'b' * 32,
          action: CommunityAdmissionAction.generateInvite,
          expiresInDays: 7,
          maxUses: 51,
        ),
        CommunityAdmissionIntent(
          requestId: 'a' * 32,
          targetRef: 'b' * 32,
          action: CommunityAdmissionAction.approve,
          entryRef: 'c' * 32,
          maxUses: 1,
        ),
      ]) {
        expect(
          (await host.adapter.manageAdmissions(draft)).error,
          'dataInvalid',
        );
      }
      expect(host.requests, isEmpty);
      expect(
        intent(
          CommunityAdmissionAction.generateInvite,
          retry: true,
        ).toPayload()['confirmUncertainRetry'],
        isTrue,
      );
    },
  );
  test(
    'malformed or contradictory write replies stay unknown without replay',
    () async {
      for (final response in <Map<String, Object?>>[
        {'schemaVersion': 1, 'status': 'accepted', 'error': 'outcomeUnknown'},
        {'schemaVersion': 1, 'status': 'unknown'},
        {'schemaVersion': 1, 'status': 'rejected', 'error': 'unexpected'},
        {'schemaVersion': 2, 'status': 'accepted'},
      ]) {
        final host = CommunityHarness(
          capabilities: ['communities.manageAdmissions'],
          responses: {'communities.manageAdmissions': response},
        );
        addTearDown(host.close);
        expect(
          (await host.adapter.manageAdmissions(
            intent(CommunityAdmissionAction.generateInvite),
          )).status,
          'unknown',
        );
        expect(
          host.requests
              .where((r) => r.name == 'communities.manageAdmissions')
              .length,
          1,
        );
      }
    },
  );
  test('explicit server refusal remains rejected', () async {
    final host = CommunityHarness(
      capabilities: ['communities.manageAdmissions'],
      responses: {
        'communities.manageAdmissions': {
          'schemaVersion': 1,
          'status': 'rejected',
          'error': 'notAllowed',
        },
      },
    );
    addTearDown(host.close);
    final result = await host.adapter.manageAdmissions(
      intent(CommunityAdmissionAction.decline),
    );
    expect(result.status, 'rejected');
    expect(result.error, 'notAllowed');
  });
  test('account switch during write never accepts the late receipt', () async {
    final host = CommunityHarness(
      capabilities: ['communities.manageAdmissions'],
      holdNames: {'communities.manageAdmissions'},
      responses: {
        'communities.manageAdmissions': {
          'schemaVersion': 1,
          'status': 'accepted',
        },
      },
    );
    addTearDown(host.close);
    final pending = host.adapter.manageAdmissions(
      intent(CommunityAdmissionAction.generateInvite),
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
    expect((await pending).status, 'unknown');
    await host.reply(host.requests.last);
    expect(
      host.requests
          .where((r) => r.name == 'communities.manageAdmissions')
          .length,
      1,
    );
  });
}
