import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/bridge_communities.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_activity.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

class PausedHost {
  final pair = InMemoryBridgeConnection.createPair();
  late final session = BridgeClientSession(
    connection: pair.client,
    sessionGeneration: 7,
  );
  late final StreamSubscription<BridgeEnvelope> incoming;
  bool paused = true;
  int roots = 0, waits = 0;
  static const owner = BridgeAccountContext(
    environment: 'fixture',
    authority: 'starbridge-relay-test',
    subject: 'fixture',
  );
  PausedHost() {
    session.acceptHostCapabilities(['communities.read', 'communities.wait']);
    incoming = pair.host.incoming.listen((request) {
      if (request.name == 'account.getCurrent') roots++;
      if (request.name == 'communities.wait') waits++;
      if (request.name == 'bridge.cancel') return;
      unawaited(
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            accountContext: paused ? null : owner,
            status: paused ? 'error' : 'ok',
            error: paused
                ? const BridgeErrorBody(
                    code: 'account.local_mode',
                    message: 'Online work is paused.',
                    retryable: false,
                  )
                : null,
            payload: paused
                ? const {}
                : switch (request.name) {
                    'account.getCurrent' => {
                      'schemaVersion': 1,
                      'state': 'legacySignedIn',
                    },
                    'communities.wait' => {
                      'schemaVersion': 1,
                      'instance': 'a' * 32,
                      'version': 0,
                    },
                    _ => {
                      'schemaVersion': 1,
                      'view': request.payload['view'] ?? 'mine',
                      'query': '',
                      'items': <Object?>[],
                    },
                  },
          ),
        ),
      );
    });
  }
  Future<void> restore() async {
    paused = false;
    await pair.host.send(
      const BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'account.changed',
        sessionGeneration: 8,
        sequence: 1,
        payload: {'schemaVersion': 1},
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> close() async {
    await incoming.cancel();
    await session.close();
    await pair.host.close();
  }
}

void main() {
  test('explicit local-mode rejection stops joined retries until real account invalidation', () async {
    final h = PausedHost();
    final model = CommunitiesModule(BridgeCommunities(h.session));
    addTearDown(() async {
      model.dispose();
      await h.close();
    });
    await model.refreshJoined();
    expect(model.joinedError, 'onlinePaused');
    expect(model.joinedLoaded, isFalse);
    await model.refreshJoined();
    expect(h.roots, 1);
    await h.restore();
    await model.refreshJoined();
    expect(model.joinedLoaded, isTrue);
    expect(model.joinedError, isNull);
    // Existing recovery opens discovery after the refreshed joined directory;
    // each non-overlapping read still confirms its own root account context.
    expect(h.roots, 3);
    expect(h.waits, 0);
  });
  testWidgets(
    'explicit local-mode rejection pauses organization activity until a real owner event',
    (tester) async {
      final h = PausedHost();
      final activity = CommunityActivity(h.session);
      final subscription = activity.changes.stream.listen((_) {});
      addTearDown(() async {
        await subscription.cancel();
        await activity.close();
        await h.close();
      });
      await tester.pump(const Duration(milliseconds: 10));
      expect(h.roots, 1);
      await tester.pump(const Duration(minutes: 1));
      expect(h.roots, 1);
      expect(h.waits, 0);
      h.paused = false;
      await h.pair.host.send(
        const BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'account.changed',
          sessionGeneration: 8,
          sequence: 1,
          payload: {'schemaVersion': 1},
        ),
      );
      await tester.pump(const Duration(milliseconds: 10));
      expect(h.roots, 2);
      expect(h.waits, 1);
      await tester.runAsync(() async {
        await subscription.cancel();
        await activity.close();
        await h.close();
      });
    },
  );
}
