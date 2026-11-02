import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/achievements/bridge_achievement_collection.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'scm_achievements_test.dart' show page;

class _Offline extends ChangeNotifier implements ConnectionModeControl {
  @override
  ConnectionModeSnapshot snapshot = ConnectionModeSnapshot(
    scope: 1,
    revision: 4,
    state: ConnectionModeState.offline,
    offlineAccount: OfflineAccountDisplay(
      'Synthetic',
      DateTime.utc(2026, 10, 1),
    ),
  );
  @override
  bool get failed => false;
  @override
  bool get busy => false;
  @override
  bool get allowsOnlineTraffic => false;
  @override
  bool get canEnterOffline => false;
  @override
  Future<bool> enterOffline() async => false;
}

void main() {
  for (final lane in ['online', 'retained', 'offline']) {
    test(
      '$lane reads all SCM pages through the account-fenced bridge',
      () async {
        final pair = InMemoryBridgeConnection.createPair();
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 1,
        );
        session.acceptHostCapabilities(['scmAchievements.read']);
        final mode = lane == 'offline' ? _Offline() : null;
        final commands = <BridgeEnvelope>[];
        final subscription = pair.host.incoming.listen((request) {
          commands.add(request);
          final account = request.name == 'account.getCurrent';
          final payload = account
              ? <String, Object?>{'schemaVersion': 1, 'state': 'signedIn'}
              : page(request.payload['offset'] as int? ?? 0, total: 33);
          if (!account && lane != 'online') {
            payload['cachedAtUtc'] = payload['readAtUtc'];
          }
          unawaited(
            pair.host.send(
              BridgeEnvelope(
                protocolVersion: 1,
                messageType: 'response',
                name: request.name,
                correlationId: request.correlationId,
                sessionGeneration: 1,
                status: 'ok',
                accountContext: lane == 'online'
                    ? const BridgeAccountContext(
                        environment: 'test',
                        authority: 'scm',
                        subject: 'synthetic',
                      )
                    : null,
                payload: payload,
              ),
            ),
          );
        });
        addTearDown(() async {
          await subscription.cancel();
          await session.close();
          await pair.host.close();
          mode?.dispose();
        });
        final result = await BridgeAchievementCollection(
          session,
          scm: true,
          mode: mode,
          retainedReadId: lane == 'retained' ? () => 'synthetic-read' : null,
        ).read(generation: 1);
        expect(result.catalog, hasLength(33));
        final reads = commands
            .where((e) => e.name != 'account.getCurrent')
            .toList();
        expect(reads.map((e) => e.payload['offset'] ?? 0), [0, 16, 32]);
        expect(
          reads.every(
            (e) =>
                e.name ==
                switch (lane) {
                  'online' => 'scmAchievements.read',
                  'offline' => 'onboarding.mode.scmAchievements',
                  _ => 'account.offlineData.read',
                },
          ),
          isTrue,
        );
        if (lane == 'retained') {
          expect(
            reads.every((e) => e.payload['kind'] == 'scmAchievements'),
            isTrue,
          );
        }
        expect(result.cachedAtUtc != null, lane != 'online');
      },
    );
  }
  test('a wrong owner on a later page rejects the whole SCM read', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    session.acceptHostCapabilities(['scmAchievements.read']);
    final subscription = pair.host.incoming.listen((request) {
      final offset = request.payload['offset'] as int? ?? 0;
      unawaited(
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: 1,
            status: 'ok',
            accountContext: BridgeAccountContext(
              environment: 'test',
              authority: 'scm',
              subject: offset > 0 ? 'other' : 'synthetic',
            ),
            payload: request.name == 'account.getCurrent'
                ? {'schemaVersion': 1, 'state': 'signedIn'}
                : page(offset, total: 33),
          ),
        ),
      );
    });
    addTearDown(() async {
      await subscription.cancel();
      await session.close();
      await pair.host.close();
    });
    await expectLater(
      BridgeAchievementCollection(session, scm: true).read(generation: 1),
      throwsFormatException,
    );
  });
}
