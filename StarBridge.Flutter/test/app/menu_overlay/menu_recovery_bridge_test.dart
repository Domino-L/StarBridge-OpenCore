import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/window/menu_recovery.dart';

void main() {
  test('recovery bridge is account-agnostic and rejects malformed or data-bearing replies', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 7,
    );
    final port = BridgeMenuRecovery(session);
    final requests = <BridgeEnvelope>[];
    Map<String, Object?> payload = {
      'schemaVersion': 1,
      'token': 'a' * 32,
      'previousInterrupted': true,
    };
    final subscription = pair.host.incoming.listen((request) {
      requests.add(request);
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          payload: payload,
          status: 'ok',
        ),
      );
    });
    final first = await port.begin();
    expect(first.previousInterrupted, true);
    expect(requests.single.accountContext, isNull);
    expect(requests.single.sessionGeneration, 7);
    expect(requests.single.payload, {'schemaVersion': 1});
    for (final malformed in [
      {...payload, 'account': 'forbidden'},
      {...payload, 'token': 'bad'},
      {...payload, 'previousInterrupted': 'true'},
      {...payload, 'schemaVersion': 2},
    ]) {
      payload = malformed;
      await expectLater(port.begin(), throwsFormatException);
    }
    payload = {'schemaVersion': 1, 'clean': true};
    await port.finish(first.token);
    expect(requests.last.accountContext, isNull);
    expect(requests.last.payload, {'schemaVersion': 1, 'token': first.token});
    payload = {'schemaVersion': 1, 'clean': false};
    await expectLater(port.finish(first.token), throwsFormatException);
    final before = requests.length;
    await expectLater(port.finish('invalid'), throwsFormatException);
    expect(requests.length, before);
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  });
}
