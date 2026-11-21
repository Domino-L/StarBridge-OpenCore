import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/features/tools/catalog_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_account_agnostic_requests.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

const operations = [
  'missions.page',
  'missions.filters',
  'missions.detail',
  'blueprints.page',
  'blueprints.filters',
  'blueprints.detail',
  'blueprints.missions',
];

final class Mode extends ChangeNotifier implements ConnectionModeControl {
  bool online = true;
  @override
  ConnectionModeSnapshot get snapshot => ConnectionModeSnapshot(
    state: online ? ConnectionModeState.online : ConnectionModeState.offline,
  );
  @override
  bool get busy => false;
  @override
  bool get failed => false;
  @override
  bool get allowsOnlineTraffic => online;
  @override
  bool get canEnterOffline => online;
  @override
  Future<bool> enterOffline() async {
    online = false;
    notifyListeners();
    return true;
  }
}

BridgeEnvelope reply(BridgeEnvelope request, {String? code}) => BridgeEnvelope(
  protocolVersion: 1,
  messageType: 'response',
  name: request.name,
  correlationId: request.correlationId,
  sessionGeneration: request.sessionGeneration,
  status: code == null ? 'ok' : 'error',
  payload: code == null
      ? {'schemaVersion': 1, 'data': <String, Object?>{}}
      : const {},
  error: code == null
      ? null
      : BridgeErrorBody(code: code, message: 'Unavailable', retryable: true),
);

void main() {
  test('seven reads and website intent are account agnostic', () {
    expect(operations.every(accountAgnosticRequests.contains), isTrue);
    expect(accountAgnosticRequests, contains('catalog.openScm'));
  });
  test('anonymous catalogue wire requests, refresh, remote limit and offline admission', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    session.acceptHostCapabilities(['catalog.read', 'catalog.openScm']);
    final mode = Mode(), seen = <BridgeEnvelope>[];
    final port = BridgeCatalogPort(session, mode);
    String? error;
    final listener = pair.host.incoming.listen((request) {
      seen.add(request);
      unawaited(pair.host.send(reply(request, code: error)));
    });
    try {
      for (final op in operations) {
        await port.read(op, const {}, refresh: true);
      }
      expect(seen, hasLength(7));
      expect(
        seen.every(
          (r) =>
              r.accountContext == null &&
              r.payload['schemaVersion'] == 1 &&
              r.payload['refresh'] == true,
        ),
        isTrue,
      );
      expect(seen.any((r) => r.name.startsWith('account.')), isFalse);
      error = 'catalog.rate_limited';
      await expectLater(
        port.read('missions.page', const {}),
        throwsA(
          isA<CatalogFailure>().having((e) => e.limited, 'limited', true),
        ),
      );
      await mode.enterOffline();
      final count = seen.length;
      await expectLater(
        port.read('missions.page', const {}),
        throwsA(isA<CatalogFailure>()),
      );
      expect(seen, hasLength(count));
    } finally {
      port.dispose();
      mode.dispose();
      await listener.cancel();
      await session.close();
      await pair.host.close();
    }
  });
  test(
    'old Host without capability remains unavailable without a request',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      );
      final mode = Mode();
      final port = BridgeCatalogPort(session, mode);
      try {
        expect(port.canOpenWebsite, isFalse);
        await expectLater(
          port.read('missions.page', const {}),
          throwsA(isA<CatalogFailure>()),
        );
      } finally {
        port.dispose();
        mode.dispose();
        await session.close();
        await pair.host.close();
      }
    },
  );
}
