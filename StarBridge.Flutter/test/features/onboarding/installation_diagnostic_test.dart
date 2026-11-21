import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_installation_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  for (final valid in [true, false]) {
    test('installation diagnostics use validated stage/kind only, valid=$valid', () async {
      final messages = <String?>[], previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) => messages.add(message);
      addTearDown(() => debugPrint = previous);
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 7,
      );
      session.acceptHostCapabilities([
        BridgeOnlineInstallationAdapter.capability,
      ]);
      final adapter = BridgeOnlineInstallationAdapter(session);
      final subscription = pair.host.incoming.listen((r) {
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: r.name,
              correlationId: r.correlationId,
              sessionGeneration: 7,
              status: 'ok',
              payload: {
                'schemaVersion': 1,
                'revision': 3,
                'phase': 'completed',
                'controlGeneration': 7,
                'modeRevision': 4,
                'modeState': 'offline',
                'failure': {
                  'stage': valid ? 'configureBusiness' : 'untrusted-body',
                  'kind': 'storage',
                },
              },
            ),
          ),
        );
      });
      addTearDown(() async {
        adapter.dispose();
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      });
      if (valid) {
        expect(
          (await adapter.read(3)).failure?.code,
          'configureBusiness/storage',
        );
        await adapter.read(3);
        expect(messages, [
          'onboarding.onlineInstallation stage=configureBusiness kind=storage',
        ]);
      } else {
        await expectLater(adapter.read(3), throwsFormatException);
        expect(messages, isEmpty);
      }
    });
  }
}
