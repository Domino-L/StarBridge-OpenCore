import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/bridge_marketplace_listings_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'marketplace_bridge_trade_test.dart' show Online;

void main() {
  for (final failure in [
    'marketplace.reauthorize_required',
    'trade_profile.rejected',
    'missingCapability',
  ]) {
    test('listings still load when the trade profile read fails ($failure)',
        () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      );
      session.acceptHostCapabilities([
        'marketplace.read',
        'marketplace.listings',
        if (failure != 'missingCapability') 'tradeProfile.read',
      ]);
      const owner = BridgeAccountContext(
        environment: 'test',
        authority: 'scm-test',
        subject: 'fixture',
      );
      final subscription = pair.host.incoming.listen((request) {
        final failed = request.name == 'tradeProfile.read';
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: 1,
              accountContext: owner,
              status: failed ? 'error' : 'ok',
              error: failed
                  ? BridgeErrorBody(
                      code: failure,
                      message: 'fixture',
                      retryable: false,
                    )
                  : null,
              payload: request.name == 'account.getCurrent'
                  ? {'schemaVersion': 1, 'state': 'signedIn'}
                  : request.name == 'marketplace.listings'
                  ? {
                      'schemaVersion': 1,
                      'data': {
                        'rows': [
                          {'id': 7},
                        ],
                      },
                    }
                  : {
                      'schemaVersion': 1,
                      'readAt': '2026-10-19T00:00:00Z',
                      'data': {'rows': <Object>[]},
                    },
            ),
          ),
        );
      });
      final mode = Online();
      final market = BridgeMarketplacePort(session, mode);
      try {
        final result = await BridgeMarketplaceListingsPort(market).read();
        expect(result['rows'], [
          {'id': 7},
        ]);
        expect(result['limit'], isNull);
        expect(result['tradeProfile'], isNull);
        if (failure == 'trade_profile.rejected') {
          // Host codes reach the form instead of collapsing into "unknown".
          await expectLater(
            market.tradeProfile(),
            throwsA(
              isA<MarketplaceTradeError>().having(
                (e) => e.code,
                'code',
                'trade_profile.rejected',
              ),
            ),
          );
        }
      } finally {
        market.dispose();
        mode.dispose();
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      }
    });
  }
}
