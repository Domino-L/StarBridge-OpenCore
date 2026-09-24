import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/bridge_overlay_scenes.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test('wire round trip accepts value-equal identities, persists choice and rejects wrong owner', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
    );
    session.acceptHostCapabilities([
      'overlayScenes.read',
      'overlayScenes.select',
      'overlayScenes.focusCommunity',
    ]);
    final adapter = BridgeOverlayScenes(session);
    var wrongOwner = false;
    final requests = <BridgeEnvelope>[];
    final sub = pair.host.incoming.listen((request) {
      requests.add(request);
      unawaited(
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: 4,
            // Deliberately distinct objects, as on a JSON transport.
            accountContext: BridgeAccountContext(
              environment: 'test',
              authority: 'starbridge-relay-test',
              subject: wrongOwner && request.name != 'account.getCurrent'
                  ? 'other'
                  : 'synthetic',
            ),
            status: 'ok',
            payload: request.name == 'account.getCurrent'
                ? {'schemaVersion': 1, 'state': 'legacySignedIn'}
                : {
                    'schemaVersion': 1,
                    'revision': 1,
                    'mode': request.payload['mode'] ?? 'auto',
                    'code': request.name == 'overlayScenes.select'
                        ? request.payload['code']
                        : null,
                    'actualId': null,
                    'status': 'standby',
                    'organizations': [
                      {'code': 'A', 'name': '组织'},
                    ],
                  },
          ),
        ),
      );
    });
    addTearDown(() async {
      adapter.close();
      await sub.cancel();
      await session.close();
      await pair.host.close();
    });
    expect((await adapter.read()).available, true);
    expect((await adapter.focusCommunity('A')).mode, 'auto');
    expect(
      requests
          .singleWhere((x) => x.name == 'overlayScenes.focusCommunity')
          .payload,
      {'schemaVersion': 1, 'code': 'A'},
    );
    expect((await adapter.select(0, 'community', 'A')).code, 'A');
    final write = requests.singleWhere((x) => x.name == 'overlayScenes.select');
    expect(write.accountContext?.subject, 'synthetic');
    expect(write.payload, {
      'schemaVersion': 1,
      'revision': 0,
      'mode': 'community',
      'code': 'A',
    });
    wrongOwner = true;
    await expectLater(adapter.read(), throwsStateError);
  });
}
