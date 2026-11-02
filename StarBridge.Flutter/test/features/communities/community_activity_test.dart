import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_activity.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  testWidgets(
    'organization wait is demand bound; heartbeat quiet, reconnect reconciles',
    (tester) async {
      Future<void> pump([Duration delay = const Duration(milliseconds: 5)]) =>
          tester.pump(delay);
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
      await tester.runAsync(subscription.cancel);
      await pump();
      expect(cancels, greaterThanOrEqualTo(1));
      unawaited(source.close());
      await pump();
    },
  );

  testWidgets(
    'official heartbeat keeps one bounded unread reconciliation lane',
    (tester) async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      );
      session.acceptHostCapabilities(['officialFleet.wait']);
      const owner = BridgeAccountContext(
        environment: 'fixture',
        authority: 'scm',
        subject: 'fixture',
      );
      final waits = <BridgeEnvelope>[];
      var accountState = 'signedIn';
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
            respond(request, {'schemaVersion': 1, 'state': accountState}),
          );
        } else if (request.name == 'officialFleet.wait') {
          waits.add(request);
        }
      });
      final activity = CommunityActivity(session, now: tester.binding.clock.now)
        ..configureOfficialFleet('officialFleet:7', available: true);
      var hints = 0;
      final changes = activity.changes.stream.listen((_) => hints++);
      final errors = <String>[];
      final errorSubscription = activity.errors.stream.listen(errors.add);
      addTearDown(() async {
        await errorSubscription.cancel();
        await activity.close();
        await host.cancel();
        await session.close();
        await pair.host.close();
      });
      Future<void> heartbeat() async {
        await respond(waits.last, {
          'schemaVersion': 1,
          'sourceRef': 'officialFleet:7',
          'instance': 'a' * 32,
          'version': 0,
          'chatEvents': true,
        });
        await tester.pump();
      }

      await tester.pump(const Duration(milliseconds: 1));
      expect(waits, hasLength(1));
      await heartbeat();
      expect(hints, 1);
      await tester.pump(const Duration(milliseconds: 151));
      await tester.pump(const Duration(seconds: 8));
      await heartbeat();
      expect(
        hints,
        1,
        reason: 'A quiet heartbeat before the bound does not read chat',
      );
      // The blind safety net runs once a minute: seven more quiet heartbeats.
      for (var quiet = 0; quiet < 6; quiet++) {
        await tester.pump(const Duration(milliseconds: 151));
        await tester.pump(const Duration(seconds: 8));
        await heartbeat();
        expect(hints, 1, reason: 'Quiet heartbeat $quiet stays silent');
      }
      await tester.pump(const Duration(milliseconds: 151));
      await tester.pump(const Duration(seconds: 8));
      await heartbeat();
      expect(
        hints,
        2,
        reason: 'Missed events and other-device receipts reconcile on the same worker',
      );
      expect(waits, hasLength(9));
      accountState = 'signedOut';
      await tester.pump(const Duration(milliseconds: 151));
      expect(waits, hasLength(9));
      expect(
        errors,
        ['identityUnavailable'],
        reason: 'A real account read proving sign-out retires unread even without an event',
      );
      await tester.runAsync(changes.cancel);
      await tester.runAsync(errorSubscription.cancel);
      await tester.runAsync(activity.close);
      await tester.pump();
    },
  );
}
