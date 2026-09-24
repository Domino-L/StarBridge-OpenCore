import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_invitation_send_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

void main() {
  final id = 'a' * 32;
  test('outbox storage failure keeps its stable local error', () async {
    final host = CommunityHarness(
      capabilities: ['communities.sendInvite'],
      error: 'communities.localRecoveryUnavailable',
    );
    addTearDown(host.close);
    await expectLater(
      host.adapter.readInvitationOutbox(),
      throwsA(
        isA<CommunityFailure>().having(
          (error) => error.code,
          'code',
          'localRecoveryUnavailable',
        ),
      ),
    );
  });
  Map<String, Object?> progress({String status = 'unknown'}) => {
    'schemaVersion': 1,
    'operationId': id,
    'status': status,
    'error': null,
  };
  Map<String, Object?> row() => {
    'operationId': id,
    'channel': 'private',
    'phase': 'sending',
    'sourceName': 'Organization',
    'destinationName': 'Recipient',
    'requestedAt': '2026-09-08T10:00:00Z',
    'maxUses': 1,
  };
  test(
    'missing capability performs no account or invitation request',
    () async {
      final host = CommunityHarness(capabilities: []);
      addTearDown(host.close);
      expect(host.adapter.invitationSendingAvailable, isFalse);
      expect((await host.adapter.resumeInvitation(id)).status, 'rejected');
      expect(host.requests, isEmpty);
    },
  );
  test(
    'send uses scoped references and never sends raw card or account data',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.sendInvite'],
        responses: {'communities.sendInvite': progress()},
      );
      addTearDown(host.close);
      final result = await host.adapter.sendInvitation(
        operationId: id,
        organizationRef: 'b' * 32,
        channel: 'private',
        destinationRef: 'c' * 32,
        maxUses: 1,
      );
      expect(result.status, 'unknown');
      expect(host.requests.map((r) => r.name), [
        'account.getCurrent',
        'communities.sendInvite',
      ]);
      expect(host.requests.last.accountContext?.subject, 'test-subject');
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'operationId': id,
        'organizationRef': 'b' * 32,
        'channel': 'private',
        'destinationRef': 'c' * 32,
        'maxUses': 1,
        'action': 'advance',
      });
    },
  );
  test(
    'recovery defaults to checking same operation without recipient override',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.sendInvite'],
        responses: {'communities.resumeInvite': progress(status: 'sent')},
      );
      addTearDown(host.close);
      expect((await host.adapter.resumeInvitation(id)).status, 'sent');
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'operationId': id,
        'action': 'check',
      });
      expect(
        host.requests.where((r) => r.name == 'communities.sendInvite'),
        isEmpty,
      );
    },
  );
  test('outbox exposes only bounded labels and phase', () async {
    final host = CommunityHarness(
      capabilities: ['communities.sendInvite'],
      responses: {
        'communities.invitationOutbox': {
          'schemaVersion': 1,
          'items': [row()],
        },
      },
    );
    addTearDown(host.close);
    final items = await host.adapter.readInvitationOutbox();
    expect(items.single.sourceName, 'Organization');
    expect(items.single.phase, 'sending');
    expect(host.requests.last.payload, {'schemaVersion': 1});
    expect(host.requests.length, 2);
  });
  for (final malformed in [
    {...progress(), 'operationId': 'd' * 32},
    {...progress(), 'status': 'accepted'},
    {...progress(), 'code': 'must-not-expose'},
    {...progress(), 'error': 'private-error-details'},
  ]) {
    test(
      'untrusted delivery result remains unknown ${malformed.keys}',
      () async {
        final host = CommunityHarness(
          capabilities: ['communities.sendInvite'],
          responses: {'communities.resumeInvite': malformed},
        );
        addTearDown(host.close);
        final result = await host.adapter.resumeInvitation(id);
        expect(result.status, 'unknown');
        expect(result.error, 'outcomeUnknown');
      },
    );
  }
  test(
    'local persistence error is not treated as rejection or automatic retry',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.sendInvite'],
        error: 'communities.localRecoveryUnavailable',
      );
      addTearDown(host.close);
      final result = await host.adapter.resumeInvitation(id);
      expect(result.status, 'unknown');
      expect(result.error, 'localRecoveryUnavailable');
      expect(host.requests.length, 2);
    },
  );
  test('extra or duplicate outbox rows rejected', () {
    expect(
      () => CommunityInvitationOperation.parsePage({
        'schemaVersion': 1,
        'items': [row(), row()],
      }),
      throwsFormatException,
    );
    expect(
      () => CommunityInvitationOperation.parsePage({
        'schemaVersion': 1,
        'items': [
          {...row(), 'code': 'secret'},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => CommunityInvitationOperation.parsePage({
        'schemaVersion': 1,
        'items': List.generate(129, (_) => row()),
      }),
      throwsFormatException,
    );
  });
  test('late result after adapter closes does not become success', () async {
    final host = CommunityHarness(
      capabilities: ['communities.sendInvite'],
      holdNames: {'communities.resumeInvite'},
      responses: {'communities.resumeInvite': progress(status: 'sent')},
    );
    addTearDown(host.close);
    final pending = host.adapter.resumeInvitation(id);
    await host.readArrived.future;
    await host.adapter.close();
    expect((await pending).status, 'unknown');
  });
  test(
    'malformed read reports failure instead of empty successful list',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.sendInvite'],
        responses: {
          'communities.invitationOutbox': {'schemaVersion': 1, 'items': 'bad'},
        },
      );
      addTearDown(host.close);
      await expectLater(
        host.adapter.readInvitationOutbox(),
        throwsA(isA<CommunityFailure>()),
      );
    },
  );
}
