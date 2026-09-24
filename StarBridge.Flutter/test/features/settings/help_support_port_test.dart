import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/help_support_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  for (final name in [
    'applicationUpdates.check',
    'helpSupport.history',
    'helpSupport.stats',
    'helpSupport.feedback',
    'helpSupport.openScm',
  ]) {
    test('$name reaches the host without account context', () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 0,
      );
      session.acceptHostCapabilities([name]);
      final received = <BridgeEnvelope>[];
      final subscription = pair.host.incoming.listen((request) {
        received.add(request);
        pair.host.send(BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          status: 'ok',
          payload: const {'schemaVersion': 1, 'sent': true},
        ));
      });
      addTearDown(() async {
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      });
      final port = BridgeHelpSupport(session);
      if (name == 'helpSupport.feedback') {
        await port.send('', 'A feature suggestion');
      } else {
        await port.read(name);
      }
      expect(received, hasLength(1));
      expect(received.single.accountContext, isNull);
      expect(received.single.name, name);
    });
  }
}
