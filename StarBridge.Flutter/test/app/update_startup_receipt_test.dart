import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/update_startup_receipt.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test('transient failures are bounded and never confirm startup', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 0,
    );
    var attempts = 0;
    final subscription = pair.host.incoming.listen((request) {
      if (request.name == 'applicationUpdates.firstFrameReady') attempts++;
    });
    expect(
      await reportUpdateStartupReceipt(
        session,
        isCurrent: () => true,
        retryDelay: Duration.zero,
        requestTimeout: const Duration(milliseconds: 5),
      ),
      isFalse,
    );
    expect(attempts, 6);
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  });
  test('obsolete Host lease is not retried', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 0,
    );
    var current = true;
    var attempts = 0;
    final subscription = pair.host.incoming.listen((request) {
      if (request.name != 'applicationUpdates.firstFrameReady') return;
      attempts++;
      current = false;
      session.advanceGeneration(1);
    });
    expect(
      await reportUpdateStartupReceipt(
        session,
        isCurrent: () => current,
        retryDelay: Duration.zero,
      ),
      isFalse,
    );
    expect(attempts, 1);
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  });
  for (final advance in [false, true]) {
    test(
      'startup receipt survives real pending-request generation change: $advance',
      () async {
        final pair = InMemoryBridgeConnection.createPair();
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 0,
        );
        final generations = <int>[];
        final subscription = pair.host.incoming.listen((request) async {
          if (request.name != 'applicationUpdates.firstFrameReady') return;
          generations.add(request.sessionGeneration);
          if (advance && generations.length == 1) {
            session.advanceGeneration(1);
            return;
          }
          await pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: request.sessionGeneration,
              status: 'ok',
              payload: const {'schemaVersion': 1, 'reported': true},
            ),
          );
        });
        final result = await reportUpdateStartupReceipt(
          session,
          isCurrent: () => true,
          retryDelay: Duration.zero,
        );
        expect(result, isTrue);
        expect(generations, advance ? [0, 1] : [0]);
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      },
    );
  }
}
