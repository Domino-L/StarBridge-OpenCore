import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_activity.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test(
    'organization wait is demand bound; heartbeat quiet, reconnect reconciles',
    () async {
      Future<void> pump([Duration delay = const Duration(milliseconds: 5)]) =>
          Future<void>.delayed(delay);
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      );
      session.acceptHostCapabilities(['communities.wait']);
      const owner = BridgeAccountContext(
        environment: 'fixture',
        authority: 'starbridge-relay-test',
        subject: 'fixture',
      );
      final waits = <BridgeEnvelope>[];
      var wakes = 0, cancels = 0;
      Future<void> respond(
        BridgeEnvelope request,
        Map<String, Object?> payload,
      ) => pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: owner,
          status: 'ok',
          payload: payload,
        ),
      );
      final host = pair.host.incoming.listen((request) {
        if (request.name == 'account.getCurrent') {
          unawaited(
            respond(request, {'schemaVersion': 1, 'state': 'legacySignedIn'}),
          );
        } else if (request.name == 'communities.wait') {
          waits.add(request);
        } else if (request.name == 'bridge.cancel') {
          cancels++;
        }
      });
      final source = CommunityActivity(session);
      addTearDown(() async {
        await source.close();
        await host.cancel();
        await session.close();
        await pair.host.close();
      });
      await pump(const Duration(seconds: 1));
      expect(waits, isEmpty);
      final subscription = source.changes.stream.listen((_) => wakes++);
      await pump(const Duration(milliseconds: 1));
      await respond(waits.last, {
        'schemaVersion': 1,
        'instance': 'a' * 32,
        'version': 0,
      });
      await pump();
      expect(wakes, 1); // Establish snapshot against the initial cursor.
      expect(source.healthy, isFalse); // Old server retains readback fallback.
      await pump(const Duration(milliseconds: 150));
      await respond(waits.last, {
        'schemaVersion': 1,
        'instance': 'a' * 32,
        'version': 0,
        'presenceEvents': true,
      });
      await pump();
      expect(wakes, 1); // Heartbeat does not request content.
      expect(source.healthy, isTrue);
      await pump(const Duration(milliseconds: 150));
      await respond(waits.last, {
        'schemaVersion': 1,
        'instance': 'a' * 32,
        'version': 1,
      });
      await pump();
      expect(wakes, 2);
      await pump(const Duration(milliseconds: 150));
      await respond(waits.last, {
        'schemaVersion': 1,
        'instance': 'invalid',
        'version': 1,
      });
      await pump();
      expect(source.healthy, isFalse);
      final count = waits.length;
      await pump(const Duration(seconds: 1));
      expect(waits.length, count);
      await pump(const Duration(seconds: 1));
      await respond(waits.last, {
        'schemaVersion': 1,
        'instance': 'a' * 32,
        'version': 1,
      });
      await pump();
      expect(
        wakes,
        3,
      ); // Same cursor after a gap still revalidates authorization.
      await pump(const Duration(milliseconds: 150));
      final old = waits.last;
      await pair.host.send(
        const BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'account.changed',
          sessionGeneration: 2,
          sequence: 1,
          payload: {'schemaVersion': 1},
        ),
      );
      await pump();
      await pump(const Duration(milliseconds: 1));
      await respond(old, {
        'schemaVersion': 1,
        'instance': 'a' * 32,
        'version': 5,
      });
      await pump();
      expect(wakes, 3);
      expect(waits.last.payload['version'], -1);
      await subscription.cancel();
      await pump();
      expect(cancels, greaterThanOrEqualTo(1));
      unawaited(source.close());
      await pump();
    },
  );
}
