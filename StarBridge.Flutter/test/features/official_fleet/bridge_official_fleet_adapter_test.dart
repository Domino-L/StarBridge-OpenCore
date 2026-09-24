import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test(
    'reads the current official fleet through the Host projection',
    () async {
      final harness = _OfficialFleetHostHarness();

      final snapshot = await harness.adapter.read();

      expect(snapshot.availability, OfficialFleetAvailability.available);
      expect(snapshot.fleet?.sourceRef, 'officialFleet:7');
      expect(snapshot.fleet?.name, "Aster's Wing");
      expect(snapshot.fleet?.officialRankValue, 4);
      expect(snapshot.resourceVersion, 11);
      expect(harness.requestNames, [
        'account.getCurrent',
        'officialFleet.getCurrent',
      ]);
      await harness.close();
    },
  );

  test('keeps signed-out and no-membership states distinct', () async {
    final signedOut = _OfficialFleetHostHarness(signedIn: false);
    expect(
      (await signedOut.adapter.read()).availability,
      OfficialFleetAvailability.signedOut,
    );
    await signedOut.close();

    final notMember = _OfficialFleetHostHarness(member: false);
    expect(
      (await notMember.adapter.read()).availability,
      OfficialFleetAvailability.notMember,
    );
    await notMember.close();
  });

  test('rejects an out-of-range RSI rank instead of inferring it', () async {
    final harness = _OfficialFleetHostHarness(rankValue: 7);

    final snapshot = await harness.adapter.read();

    expect(snapshot.availability, OfficialFleetAvailability.unavailable);
    expect(snapshot.failureKey, 'officialFleet.error.invalidResponse');
    await harness.close();
  });

  test('publishes account changes as fleet invalidations', () async {
    final harness = _OfficialFleetHostHarness();
    final invalidated = harness.adapter.invalidations.first;

    await harness.sendAccountChanged();

    await invalidated.timeout(const Duration(seconds: 1));
    await harness.close();
  });
}

final class _OfficialFleetHostHarness {
  _OfficialFleetHostHarness({
    this.signedIn = true,
    this.member = true,
    this.rankValue = 4,
  }) {
    final pair = InMemoryBridgeConnection.createPair();
    _host = pair.host;
    _session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
      requestTimeout: const Duration(seconds: 1),
    );
    adapter = BridgeOfficialFleetAdapter(_session);
    _subscription = _host.incoming.listen(_respond);
  }

  final bool signedIn;
  final bool member;
  final int rankValue;
  late final BridgeConnection _host;
  late final BridgeClientSession _session;
  late final StreamSubscription<BridgeEnvelope> _subscription;
  late final BridgeOfficialFleetAdapter adapter;
  final List<BridgeEnvelope> requests = [];

  List<String> get requestNames => requests.map((item) => item.name).toList();

  Future<void> _respond(BridgeEnvelope request) async {
    requests.add(request);
    const context = BridgeAccountContext(
      environment: 'development',
      authority: 'scm-development',
      subject: 'synthetic-subject',
    );
    if (request.name == 'account.getCurrent') {
      await _send(request, <String, Object?>{
        'schemaVersion': 1,
        'state': signedIn ? 'signedIn' : 'signedOut',
        'displayName': signedIn ? 'Aster Lin' : null,
        'avatarUrl': null,
      }, context: signedIn ? context : null);
      return;
    }
    if (request.name != 'officialFleet.getCurrent') {
      throw StateError('Unexpected request ${request.name}');
    }
    expect(request.accountContext?.subject, 'synthetic-subject');
    await _send(request, <String, Object?>{
      'schemaVersion': 1,
      'state': member ? 'member' : 'notMember',
      'fleet': member
          ? <String, Object?>{
              'sourceRef': 'officialFleet:7',
              'sid': 'ASTER',
              'name': "Aster's Wing",
              'logoUrl': null,
              'officialRankName': 'Officer',
              'officialRankValue': rankValue,
            }
          : null,
      'freshness': 'live',
      'resourceVersion': 11,
      'observedAtUtc': '2026-09-01T12:00:00Z',
    }, context: context);
  }

  Future<void> sendAccountChanged() => _host.send(
    const BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'event',
      name: 'account.changed',
      sessionGeneration: 5,
      sequence: 1,
      payload: <String, Object?>{'schemaVersion': 1},
    ),
  );

  Future<void> _send(
    BridgeEnvelope request,
    Map<String, Object?> payload, {
    BridgeAccountContext? context,
  }) => _host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: request.name,
      correlationId: request.correlationId,
      sessionGeneration: request.sessionGeneration,
      accountContext: context,
      payload: payload,
      status: 'ok',
    ),
  );

  Future<void> close() async {
    await adapter.close();
    await _subscription.cancel();
    await _session.close();
    await _host.close();
  }
}
