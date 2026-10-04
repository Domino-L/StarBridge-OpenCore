import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/social_activity.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  testWidgets('malformed cursor backs off and account changes discard old waits', (tester) async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(connection: pair.client, sessionGeneration: 1);
    session.acceptHostCapabilities(['social.wait']);
    const owner = BridgeAccountContext(environment: 'fixture', authority: 'starbridge-relay-test', subject: 'fixture');
    final waits = <BridgeEnvelope>[];
    var wakes = 0;
    Future<void> respond(BridgeEnvelope request, Map<String, Object?> payload) => pair.host.send(BridgeEnvelope(
      protocolVersion: 1, messageType: 'response', name: request.name, correlationId: request.correlationId,
      sessionGeneration: request.sessionGeneration, accountContext: owner, status: 'ok', payload: payload,
    ));
    final host = pair.host.incoming.listen((request) {
      if (request.name == 'account.getCurrent') {
        unawaited(respond(request, {'schemaVersion': 1, 'state': 'legacySignedIn'}));
      } else if (request.name == 'social.wait') { waits.add(request); }
    });
    final subscription = socialActivityChanges(session).listen((_) => wakes++);
    final source = SocialActivity(session);
    addTearDown(() async {
      source.dispose(); await subscription.cancel(); await host.cancel(); await session.close(); await pair.host.close();
    });
    await tester.pump(const Duration(milliseconds: 1));
    await respond(waits.single, {'schemaVersion': 1, 'instance': 'invalid', 'version': 0});
    await tester.pump();
    expect(wakes, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(waits, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(waits, hasLength(2));
    final old = waits.last;
    await pair.host.send(const BridgeEnvelope(protocolVersion: 1, messageType: 'event', name: 'account.changed',
      sessionGeneration: 2, sequence: 1, payload: {'schemaVersion': 1}));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(waits.last.sessionGeneration, 2);
    expect(waits.last.payload['instance'], '');
    expect(waits.last.payload['version'], -1);
    await respond(old, {'schemaVersion': 1, 'instance': 'a' * 32, 'version': 5});
    await tester.pump();
    expect(wakes, 0);
    await respond(waits.last, {'schemaVersion': 1, 'instance': 'b' * 32, 'version': 0});
    await tester.pump();
    expect(wakes, 1);
    source.dispose();
    await tester.pump();
  });
  testWidgets('one pending social wait wakes subscribers immediately and is cancelled on disposal', (tester) async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(connection: pair.client, sessionGeneration: 1);
    session.acceptHostCapabilities(['social.wait']);
    const owner = BridgeAccountContext(environment: 'fixture', authority: 'starbridge-relay-test', subject: 'fixture');
    BridgeEnvelope? wait;
    var requests = 0, wakes = 0, cancellations = 0;
    Future<void> respond(BridgeEnvelope request, Map<String, Object?> payload) => pair.host.send(BridgeEnvelope(
      protocolVersion: 1, messageType: 'response', name: request.name, correlationId: request.correlationId,
      sessionGeneration: 1, accountContext: owner, status: 'ok', payload: payload,
    ));
    final host = pair.host.incoming.listen((request) {
      if (request.name == 'account.getCurrent') {
        unawaited(respond(request, {'schemaVersion': 1, 'state': 'legacySignedIn'}));
      } else if (request.name == 'social.wait') { wait = request; requests++; }
      else if (request.name == 'bridge.cancel') { cancellations++; }
    });
    final subscription = socialActivityChanges(session).listen((_) => wakes++);
    final source = SocialActivity(session);
    addTearDown(() async {
      source.dispose();
      await subscription.cancel();
      await host.cancel();
      await session.close();
      await pair.host.close();
    });
    await tester.pump(const Duration(milliseconds: 1));
    expect(requests, 1);
    await respond(wait!, {'schemaVersion': 1, 'instance': 'a' * 32, 'version': 0});
    await tester.pump();
    expect(wakes, 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(requests, 2);
    await tester.pump(const Duration(seconds: 1));
    expect(requests, 2);
    await respond(wait!, {'schemaVersion': 1, 'instance': 'a' * 32, 'version': 1});
    await tester.pump();
    expect(wakes, 2); // No 15-second/60-second refresh delay.
    await tester.pump(const Duration(milliseconds: 100));
    source.dispose();
    await tester.pump();
    expect(cancellations, 1);
  });
}
