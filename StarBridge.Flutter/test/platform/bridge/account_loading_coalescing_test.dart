import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/bridge_account_adapter.dart';
import 'package:starbridge_flutter/features/hangar/bridge_local_hangar.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test('mixed-deadline consumers reject generation changes together', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    final subscription = pair.host.incoming.listen((_) {});
    final first = session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
    );
    final second = session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
      timeout: const Duration(seconds: 60),
    );
    final errors = Future.wait([
      expectLater(first, throwsA(isA<BridgeStaleGenerationException>())),
      expectLater(second, throwsA(isA<BridgeStaleGenerationException>())),
    ]);
    session.advanceGeneration(2);
    await errors;
    await session.close();
    await subscription.cancel();
    await pair.host.close();
  });
  test('different snapshot payloads remain ordering boundaries', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    final requests = <BridgeEnvelope>[];
    final subscription = pair.host.incoming.listen((request) {
      requests.add(request);
      unawaited(pair.host.send(_ok(request)));
    });
    final reads = [
      session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      ),
      session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1, 'different': true},
      ),
      session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
        timeout: const Duration(seconds: 60),
      ),
    ];
    await Future.wait(reads);
    expect(requests, hasLength(3));
    await session.close();
    await subscription.cancel();
    await pair.host.close();
  });
  test(
    'startup account, fleet and hangar consumers share one host read',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      );
      final account = BridgeAccountAdapter(session);
      final fleet = BridgeOfficialFleetAdapter(session);
      final requests = <BridgeEnvelope>[];
      final subscription = pair.host.incoming.listen(requests.add);
      final accountRead = account.read();
      final fleetRead = fleet.read();
      final hangarRead = expectLater(
        BridgeLocalHangar(session).read(),
        throwsA(isA<BridgeDisconnectedException>()),
      );
      await Future<void>.delayed(Duration.zero);
      // Capture the verdict, then drain the real adapters even on the red run.
      final count = requests
          .where((request) => request.name == 'account.getCurrent')
          .length;
      await session.close();
      await Future.wait<Object?>([accountRead, fleetRead, hangarRead]);
      await account.close();
      await fleet.close();
      await subscription.cancel();
      await pair.host.close();
      expect(
        count,
        1,
        reason:
            'real startup consumers must not queue duplicate account snapshots',
      );
    },
  );

  testWidgets('later subscriber keeps its full independent timeout', (
    tester,
  ) async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
      requestTimeout: const Duration(milliseconds: 40),
    );
    final requests = <BridgeEnvelope>[];
    final subscription = pair.host.incoming.listen(requests.add);
    Object? firstError, secondError;
    BridgeEnvelope? secondValue;
    session
        .request('account.getCurrent', payload: const {'schemaVersion': 1})
        .then(
          (_) {},
          onError: (Object error) {
            firstError = error;
          },
        );
    await tester.pump(const Duration(milliseconds: 30));
    session
        .request(
          'account.getCurrent',
          payload: const {'schemaVersion': 1},
          timeout: const Duration(milliseconds: 60),
        )
        .then(
          (value) {
            secondValue = value;
          },
          onError: (Object error) {
            secondError = error;
          },
        );
    await tester.pump(const Duration(milliseconds: 20));
    expect(firstError, isA<BridgeTimeoutException>());
    expect(secondError, isNull);
    expect(
      requests.where((request) => request.name == 'bridge.cancel'),
      isEmpty,
    );
    final count = requests
        .where((request) => request.name == 'account.getCurrent')
        .length;
    await pair.host.send(_ok(requests.first));
    await tester.pump();
    expect(secondError, isNull);
    expect(secondValue, isNotNull);
    await tester.runAsync(() async {
      await session.close();
      await subscription.cancel();
      await pair.host.close();
    });
    expect(count, 1);
  });

  testWidgets('last subscriber timeout retires transport and allows retry', (
    tester,
  ) async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    final requests = <BridgeEnvelope>[];
    final subscription = pair.host.incoming.listen(requests.add);
    Object? firstError, secondError;
    session
        .request(
          'account.getCurrent',
          payload: const {'schemaVersion': 1},
          timeout: const Duration(milliseconds: 20),
        )
        .then(
          (_) {},
          onError: (Object e) {
            firstError = e;
          },
        );
    session
        .request(
          'account.getCurrent',
          payload: const {'schemaVersion': 1},
          timeout: const Duration(milliseconds: 50),
        )
        .then(
          (_) {},
          onError: (Object e) {
            secondError = e;
          },
        );
    await tester.pump(const Duration(milliseconds: 25));
    expect(firstError, isA<BridgeTimeoutException>());
    expect(secondError, isNull);
    expect(
      requests.where((request) => request.name == 'bridge.cancel'),
      isEmpty,
    );
    await tester.pump(const Duration(milliseconds: 30));
    expect(secondError, isA<BridgeTimeoutException>());
    expect(
      requests.where((request) => request.name == 'bridge.cancel'),
      hasLength(1),
    );
    final retry = session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
    );
    await tester.pump();
    expect(
      requests.where((request) => request.name == 'account.getCurrent'),
      hasLength(2),
    );
    await pair.host.send(_ok(requests.last));
    await tester.pump();
    await retry;
    await tester.runAsync(() async {
      await session.close();
      await subscription.cancel();
      await pair.host.close();
    });
  });
}

BridgeEnvelope _ok(BridgeEnvelope request) => BridgeEnvelope(
  protocolVersion: 1,
  messageType: 'response',
  name: request.name,
  correlationId: request.correlationId,
  sessionGeneration: request.sessionGeneration,
  payload: const {'schemaVersion': 1},
  status: 'ok',
);
