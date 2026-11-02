import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

class Online extends ChangeNotifier implements ConnectionModeControl {
  @override
  bool get allowsOnlineTraffic => true;
  @override
  bool get busy => false;
  @override
  bool get failed => false;
  @override
  bool get canEnterOffline => false;
  @override
  ConnectionModeSnapshot get snapshot =>
      const ConnectionModeSnapshot(state: ConnectionModeState.online);
  @override
  Future<bool> enterOffline() async => false;
}

void main() {
  for (final operation in ['list', 'create']) {
    for (final scenario in ['signedIn', 'signedOut', 'forbidden']) {
      final signedIn = scenario != 'signedOut';
      test('$operation enforces Host-confirmed account ($scenario)', () async {
        final pair = InMemoryBridgeConnection.createPair();
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 1,
        );
        session.acceptHostCapabilities(['marketplace.trade']);
        const owner = BridgeAccountContext(
          environment: 'test',
          authority: 'scm-test',
          subject: 'fixture',
        );
        final received = <BridgeEnvelope>[];
        final subscription = pair.host.incoming.listen((request) {
          received.add(request);
          unawaited(
            pair.host.send(
              BridgeEnvelope(
                protocolVersion: 1,
                messageType: 'response',
                name: request.name,
                correlationId: request.correlationId,
                sessionGeneration: 1,
                accountContext: owner,
                status:
                    scenario == 'forbidden' &&
                        request.name == 'marketplace.trade'
                    ? 'error'
                    : 'ok',
                error:
                    scenario == 'forbidden' &&
                        request.name == 'marketplace.trade'
                    ? const BridgeErrorBody(
                        code: 'marketplace.forbidden',
                        message: 'fixture',
                        retryable: false,
                      )
                    : null,
                payload: request.name == 'account.getCurrent'
                    ? {
                        'schemaVersion': 1,
                        'state': signedIn ? 'signedIn' : 'signedOut',
                      }
                    : {
                        'schemaVersion': 1,
                        'data': {'transactionNumber': 'fixture'},
                      },
              ),
            ),
          );
        });
        final mode = Online();
        final port = BridgeMarketplacePort(session, mode);
        try {
          if (!signedIn) {
            await expectLater(
              port.trade(operation),
              throwsA(
                isA<MarketplaceTradeError>().having(
                  (e) => e.code,
                  'code',
                  'marketplace.sign_in_required',
                ),
              ),
            );
            expect(
              received.where((r) => r.name == 'marketplace.trade'),
              isEmpty,
            );
            return;
          }
          if (scenario == 'forbidden') {
            await expectLater(
              port.trade(operation),
              throwsA(
                isA<MarketplaceTradeError>().having(
                  (e) => e.code,
                  'code',
                  'marketplace.forbidden',
                ),
              ),
            );
          } else {
            await port.trade(operation);
          }
          final trade = received.singleWhere(
            (r) => r.name == 'marketplace.trade',
          );
          expect(trade.accountContext?.toJson(), owner.toJson());
          expect(trade.payload['operation'], operation);
        } finally {
          port.dispose();
          mode.dispose();
          await subscription.cancel();
          await session.close();
          await pair.host.close();
        }
      });
    }
  }
}
