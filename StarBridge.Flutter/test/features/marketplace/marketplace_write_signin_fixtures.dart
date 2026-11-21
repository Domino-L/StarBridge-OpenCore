import 'dart:async';

import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'marketplace_bridge_trade_test.dart' show Online;
import 'marketplace_test.dart' show FixturePort;
import 'marketplace_trades_test.dart' show TradesPort;

class WritePort extends TradesPort {
  Object? failure;
  bool listFailure = false;
  @override
  Future<MarketRow> trade(String op, [MarketRow input = const {}]) async {
    if (op == 'list' && listFailure) throw StateError('fixture read');
    if (!['list', 'detail', 'revision'].contains(op) && failure != null) {
      writes++;
      throw failure!;
    }
    return super.trade(op, input);
  }
}

class ListingWritePort implements MarketplaceListingsPort {
  Object? failure;
  bool readFailure = false;
  int reads = 0, writes = 0;
  MarketRow? lastInput;
  final row = <String, Object?>{
    'id': 1, 'itemId': 1, 'name': 'Fixture listing', 'side': 'sell',
    'price': 10, 'quantity': 2, 'visible': true, 'location': '1',
  };
  @override
  Future<MarketRow> read() async {
    reads++;
    if (readFailure) throw StateError('fixture read');
    return {
      'rows': [row], 'total': 1, 'limit': 20,
      'locations': [{'id': '1', 'name': 'Fixture location'}],
      'items': [{'id': 1, 'name': 'Fixture listing'}],
    };
  }
  @override
  Future<void> write(String operation, MarketRow input) async {
    writes++;
    lastInput = input;
    if (failure != null) throw failure!;
  }
}

class ReadAuthPort extends FixturePort implements
    MarketplaceContractsPort, MarketplaceWarehousePort, MarketplaceRecordsPort {
  ReadAuthPort(this.code);
  final String code;
  bool spacesOnly = false;
  int spaceReads = 0;
  @override
  bool get contractsSupported => true;
  @override
  bool get warehouseSupported => true;
  @override
  bool get recordsSupported => true;
  @override
  Future<MarketRow> contracts(String operation, [MarketRow input = const {}]) async =>
      throw MarketplaceTradeError(code);
  @override
  Future<MarketRow> records(String operation, [MarketRow input = const {}]) async =>
      throw MarketplaceTradeError(code);
  @override
  Future<MarketRow> warehouse(String operation, [MarketRow input = const {}]) async {
    if (operation == 'spaces') spaceReads++;
    if (!spacesOnly || operation == 'spaces') throw MarketplaceTradeError(code);
    return {'rows': <MarketRow>[], 'total': 0};
  }
}

/// Entirely in-memory bridge; no sockets, account files or external service.
Future<(MarketplaceController, Future<void> Function())> signedOutHall() async {
  final pair = InMemoryBridgeConnection.createPair();
  final session = BridgeClientSession(connection: pair.client, sessionGeneration: 1);
  session.acceptHostCapabilities(['marketplace.read', 'marketplace.listings', 'marketplace.trade']);
  final subscription = pair.host.incoming.listen((request) {
    unawaited(pair.host.send(BridgeEnvelope(
      protocolVersion: 1, messageType: 'response', name: request.name,
      correlationId: request.correlationId, sessionGeneration: 1,
      status: request.name == 'account.getCurrent' ? 'ok' : 'error',
      payload: request.name == 'account.getCurrent' ? {'schemaVersion': 1, 'state': 'signedOut'} : const {},
      error: request.name == 'account.getCurrent' ? null : const BridgeErrorBody(code: 'marketplace.sign_in_required', message: 'fixture', retryable: false),
    )));
  });
  final mode = Online();
  final port = BridgeMarketplacePort(session, mode);
  final market = MarketplaceController(port);
  return (market, () async {
    market.dispose();
    mode.dispose();
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  });
}
