import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_hangar_sharing_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

Map<String, Object?> snapshot() => {
  'schemaVersion': 1,
  'editRef': 'a' * 32,
  'usesExplicitTargets': true,
  'maximumTargets': 64,
  'options': [
    {'targetRef': 'b' * 32, 'name': '组织 A', 'selected': true},
    {'targetRef': 'c' * 32, 'name': '组织 B', 'selected': false},
  ],
};

const capabilities = [
  'communities.hangarSharing',
  'communities.saveHangarSharing',
];

void main() {
  testWidgets('sharing editor accepts a bounded slow multi-request read', (
    tester,
  ) async {
    final host = CommunityHarness(
      legacy: true,
      capabilities: capabilities,
      holdNames: {'communities.hangarSharing'},
      responses: {'communities.hangarSharing': snapshot()},
    );
    addTearDown(host.close);
    Object? outcome;
    final read = host.adapter.readHangarSharing().then<void>(
      (value) => outcome = value,
      onError: (Object error) => outcome = error,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    expect(
      outcome,
      isNull,
      reason: 'A valid editor must not fail at the generic 15-second deadline',
    );
    await host.reply(
      host.requests.firstWhere((r) => r.name == 'communities.hangarSharing'),
    );
    await tester.pump();
    await read;
    expect(outcome, isA<CommunityHangarSharing>());
  });
  test('selection is explicit and snapshots cannot be modified', () {
    final value = CommunityHangarSharing.parse(snapshot());
    expect(value.options.map((row) => row.selected), [true, false]);
    expect(() => value.options.clear(), throwsUnsupportedError);
    expect(
      CommunityHangarSharingOutcome.parse({
        'schemaVersion': 1,
        'status': 'accepted',
      }).status,
      'accepted',
    );
  });
  test('invalid or incomplete selections cannot silently become empty', () {
    for (final patch in <Map<String, Object?>>[
      {'schemaVersion': 2},
      {'editRef': 'raw-code'},
      {'usesExplicitTargets': false},
      {'usesExplicitTargets': null},
      {'maximumTargets': 100},
      {'options': null},
      {
        'options': [
          {'targetRef': 'b' * 32, 'name': 'A', 'selected': 'true'},
        ],
      },
      {
        'options': [
          {'targetRef': 'b' * 32, 'name': 'A', 'selected': false},
          {'targetRef': 'b' * 32, 'name': 'B', 'selected': false},
        ],
      },
    ]) {
      expect(
        () => CommunityHangarSharing.parse({...snapshot(), ...patch}),
        throwsFormatException,
      );
    }
  });
  test('missing capability sends nothing', () async {
    final host = CommunityHarness(capabilities: []);
    addTearDown(host.close);
    expect(host.adapter.hangarSharingAvailable, isFalse);
    expect(
      (await host.adapter.saveHangarSharing('a' * 32, [])).status,
      'rejected',
    );
    await expectLater(
      host.adapter.readHangarSharing(),
      throwsA(isA<CommunityFailure>()),
    );
    expect(host.requests, isEmpty);
  });
  test(
    'real adapter reads account and sends scoped opaque choices once',
    () async {
      final host = CommunityHarness(
        capabilities: capabilities,
        responses: {
          'communities.hangarSharing': snapshot(),
          'communities.saveHangarSharing': {
            'schemaVersion': 1,
            'status': 'accepted',
          },
        },
      );
      addTearDown(host.close);
      final value = await host.adapter.readHangarSharing();
      expect(value.options.length, 2);
      expect(host.requests.last.accountContext?.subject, 'test-subject');
      final refs = ['c' * 32];
      final saving = host.adapter.saveHangarSharing(value.editRef, refs);
      refs.add('b' * 32);
      expect((await saving).status, 'accepted');
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'editRef': 'a' * 32,
        'selectedRefs': ['c' * 32],
        'inventoryMode': 'auto',
      });
      expect(
        host.requests
            .where((request) => request.name == 'communities.saveHangarSharing')
            .length,
        1,
      );
    },
  );
  test('raw codes and duplicates fail before any request', () async {
    final host = CommunityHarness(capabilities: capabilities);
    addTearDown(host.close);
    for (final refs in [
      ['A'],
      ['b' * 32, 'b' * 32],
    ]) {
      expect(
        (await host.adapter.saveHangarSharing('a' * 32, refs)).error,
        'invalidDraft',
      );
    }
    expect(host.requests, isEmpty);
  });
  test('old service is not replaced by legacy fallback', () async {
    final host = CommunityHarness(
      capabilities: capabilities,
      error: 'communities.upgradeRequired',
    );
    addTearDown(host.close);
    await expectLater(
      host.adapter.readHangarSharing(),
      throwsA(
        isA<CommunityFailure>().having(
          (error) => error.code,
          'code',
          'upgradeRequired',
        ),
      ),
    );
    expect(host.requests.map((request) => request.name), [
      'account.getCurrent',
      'communities.hangarSharing',
    ]);
  });
  test(
    'account invalidation after dispatch never reports save success',
    () async {
      final host = CommunityHarness(
        capabilities: capabilities,
        holdNames: {'communities.saveHangarSharing'},
      );
      addTearDown(host.close);
      final saving = host.adapter.saveHangarSharing('a' * 32, []);
      await host.readArrived.future;
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
      expect((await saving).status, 'unknown');
      expect(
        host.requests
            .where((request) => request.name == 'communities.saveHangarSharing')
            .length,
        1,
      );
    },
  );
}
