import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

void main() {
  for (final code in [
    'communities.identityUnavailable',
    'communities.unavailable',
  ]) {
    test(
      'joined failure preserves $code instead of assuming signed out',
      () async {
        final host = CommunityHarness(legacy: true, error: code);
        final model = CommunitiesModule(host.adapter);
        addTearDown(model.dispose);
        addTearDown(host.close);
        await model.refreshJoined();
        expect(model.joinedLoaded, isFalse);
        expect(
          model.joinedError,
          code == 'communities.identityUnavailable'
              ? 'identityUnavailable'
              : 'unavailable',
        );
      },
    );
  }
  test('directory recovers after legacy account notification and successful sidebar read', () async {
    final host = CommunityHarness(legacy: true);
    final model = CommunitiesModule(host.adapter);
    addTearDown(model.dispose);
    addTearDown(host.close);
    await model.refresh(newView: 'discover');
    expect(model.error, isNull);
    final invalidated = host.adapter.invalidations.first;
    await host.connection.send(
      const BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'account.changed',
        sessionGeneration: 4,
        sequence: 1,
        payload: {'schemaVersion': 1},
      ),
    );
    await invalidated;
    // The actual sidebar schedules this read after accountRevision changes.
    await model.refreshJoined();
    await Future<void>.delayed(Duration.zero);
    expect(model.joinedLoaded, isTrue);
    expect(model.error, isNot('identityUnavailable'));
    expect(model.directory, isNotNull);
  });
}
