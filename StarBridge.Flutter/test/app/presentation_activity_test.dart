import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/social_activity.dart';
import 'package:starbridge_flutter/features/communities/bridge_communities.dart';
import 'package:starbridge_flutter/features/direct_messages/bridge_direct_messages.dart';
import 'package:starbridge_flutter/features/friends/bridge_friends_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  testWidgets('confirmed callsign wakes display readers without retiring account work', (tester) async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(connection: pair.client, sessionGeneration: 2);
    session.acceptHostCapabilities(['social.wait', 'communities.wait']);
    const owner = BridgeAccountContext(environment: 'fixture', authority: 'scm-test', subject: 'fixture');
    final requests = <BridgeEnvelope>[];
    final host = pair.host.incoming.listen((request) {
      requests.add(request);
      if (request.name == 'account.getCurrent') {
        unawaited(pair.host.send(BridgeEnvelope(
          protocolVersion: 1, messageType: 'response', name: request.name,
          correlationId: request.correlationId, sessionGeneration: 2,
          accountContext: owner, status: 'ok',
          payload: const {'schemaVersion': 1, 'state': 'signedIn'},
        )));
      }
      // Keep both normal activity waits pending during the display change.
    });
    final source = SocialActivity(session);
    final friends = BridgeFriendsAdapter(session);
    final messages = BridgeDirectMessages(session);
    final communities = BridgeCommunities(session);
    var friendWakes = 0, messageWakes = 0, communityWakes = 0, invalidations = 0;
    final subscriptions = <StreamSubscription<void>>[
      friends.changes.listen((_) => friendWakes++),
      messages.changes.listen((_) => messageWakes++),
      communities.workspaceChanges.listen((_) => communityWakes++),
      friends.invalidations.listen((_) => invalidations++),
      messages.invalidations.listen((_) => invalidations++),
      communities.invalidations.listen((_) => invalidations++),
    ];
    addTearDown(() async {
      source.dispose();
      for (final subscription in subscriptions) { await subscription.cancel(); }
      await friends.close();
      await messages.close();
      await communities.close();
      await host.cancel();
      await session.close();
      await pair.host.close();
    });
    await tester.pump(const Duration(milliseconds: 1));
    expect(requests.where((r) => r.name == 'social.wait'), hasLength(1));
    expect(requests.where((r) => r.name == 'communities.wait'), hasLength(1));
    final requestCount = requests.length;
    Future<void> emit(int generation, int sequence) => pair.host.send(BridgeEnvelope(
      protocolVersion: 1, messageType: 'event', name: 'account.presentationChanged',
      sessionGeneration: generation, sequence: sequence, payload: const {'schemaVersion': 1},
    ));
    await emit(1, 1);
    await tester.pump();
    expect([friendWakes, messageWakes, communityWakes], [0, 0, 0]);
    await emit(2, 2);
    await tester.pump();
    expect([friendWakes, messageWakes, communityWakes], [1, 1, 1]);
    expect(invalidations, 0);
    expect(session.activeGeneration, 2);
    expect(requests.length, requestCount);
    expect(requests.where((r) => r.name == 'bridge.cancel'), isEmpty);
    expect(socialActivityHealthy(session), isFalse);
    // A display event does not fabricate server heartbeat health or activity.
    await emit(2, 2);
    await tester.pump();
    expect([friendWakes, messageWakes, communityWakes], [1, 1, 1]);
    source.dispose();
    await tester.runAsync(subscriptions[2].cancel);
    await tester.pump();
  });
}
