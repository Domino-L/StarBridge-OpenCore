import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/hangar/bridge_local_hangar.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

const _owner = BridgeAccountContext(
  environment: 'integration',
  authority: 'synthetic',
  subject: 'owner',
);
const _other = BridgeAccountContext(
  environment: 'integration',
  authority: 'synthetic',
  subject: 'other',
);
const _proof = AccountDisplayHandoff(
  displayKey: '0123456789abcdef0123456789abcdef',
  sourceGeneration: 0,
  route: AccountRoute(
    environment: 'integration',
    authority: 'synthetic',
    subject: 'owner',
  ),
);

void main() {
  test('recoverable read classification preserves hard auth and storage-integrity failures', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    final port = BridgeLocalHangar(session);
    expect(
      port.isTransientReadFailure(
        const BridgeTimeoutException('account.getCurrent'),
      ),
      isTrue,
    );
    expect(
      port.isTransientReadFailure(const BridgeDisconnectedException()),
      isTrue,
    );
    expect(
      port.isTransientReadFailure(
        const LocalHangarFailure('hangar.storage_busy', retryable: true),
      ),
      isTrue,
    );
    expect(
      port.isTransientReadFailure(
        const LocalHangarFailure('hangar.storage_busy'),
      ),
      isFalse,
    );
    expect(
      port.isTransientReadFailure(
        const BridgeRemoteException('account.session_expired', retryable: true),
      ),
      isFalse,
    );
    expect(
      port.isTransientReadFailure(
        const LocalHangarFailure('hangar.storage_read_failed', retryable: true),
      ),
      isFalse,
    );
    await session.close();
    await pair.host.close();
  });
  for (final boundary in [
    'success',
    'closed',
    'otherRoot',
    'rootSchema',
    'inventorySchema',
    'otherInventory',
    'proofLost',
    'generation',
    'malformed',
  ]) {
    test(
      'hangar read scope requires original complete owner receipt: $boundary',
      () async {
        final pair = InMemoryBridgeConnection.createPair();
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 1,
        );
        AccountDisplayHandoff? proof = _proof;
        final port = BridgeLocalHangar(session, displayHandoff: () => proof);
        final requests = <BridgeEnvelope>[];
        final inventory = Completer<BridgeEnvelope>();
        final subscription = pair.host.incoming.listen((r) {
          requests.add(r);
          if (r.name == 'account.getCurrent') {
            unawaited(
              pair.host.send(
                BridgeEnvelope(
                  protocolVersion: 1,
                  messageType: 'response',
                  name: r.name,
                  correlationId: r.correlationId,
                  sessionGeneration: 1,
                  accountContext: boundary == 'otherRoot' ? _other : _owner,
                  status: 'ok',
                  payload: {
                    'schemaVersion': boundary == 'rootSchema' ? 1.0 : 1,
                    'state': 'signedIn',
                  },
                ),
              ),
            );
          } else if (r.name == 'hangarReader.inventory') {
            inventory.complete(r);
          }
        });
        Object? failure;
        final pending = port.read().then<void>(
          (_) {},
          onError: (Object error) {
            failure = error;
          },
        );
        try {
          expect(port.readScope, isNull);
          if (boundary == 'otherRoot' || boundary == 'rootSchema') {
            for (var i = 0; i < 4; i++) {
              await Future<void>.delayed(Duration.zero);
            }
            expect(requests.map((r) => r.name), ['account.getCurrent']);
            await pending;
          } else {
            final r = await inventory.future.timeout(
              const Duration(seconds: 2),
            );
            if (boundary == 'proofLost') proof = null;
            if (boundary == 'generation') session.advanceGeneration(2);
            await pair.host.send(
              BridgeEnvelope(
                protocolVersion: 1,
                messageType: 'response',
                name: r.name,
                correlationId: r.correlationId,
                sessionGeneration: 1,
                accountContext: boundary == 'otherInventory' ? _other : _owner,
                status: 'ok',
                payload: {
                  'schemaVersion': boundary == 'inventorySchema' ? 1.0 : 1,
                  'revision': 1,
                  'ships': [],
                  'total': boundary == 'malformed' ? -1 : 0,
                  'nextOffset': null,
                  'formerTotal': 0,
                },
              ),
            );
            await pending;
          }
          if (boundary == 'success' || boundary == 'closed') {
            expect(failure, isNull);
            expect(port.readScope?.matches(_proof), isTrue);
            if (boundary == 'closed') {
              await session.close();
            } else {
              session.advanceGeneration(2);
            }
            expect(port.readScope, isNull);
          } else {
            expect(failure, isNotNull);
            expect(port.readScope, isNull);
          }
        } finally {
          await session.close();
          await pending;
          await subscription.cancel();
          await pair.host.close();
        }
      },
    );
  }
}
