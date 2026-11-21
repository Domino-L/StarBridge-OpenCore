import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/tools/mission_records_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'catalog_bridge_test.dart' show Mode;

const owner = BridgeAccountContext(
  environment: 'fixture',
  authority: 'synthetic',
  subject: 'record-test',
);

void main() {
  test('Host wire shape, owner, capabilities and mapped errors with no catalog RPC', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    session.acceptHostCapabilities([
      'missionRecords.read',
      'missionRecords.import',
    ]);
    final mode = Mode(), port = BridgeMissionRecordsPort(session, mode);
    final requests = <BridgeEnvelope>[];
    String? failure;
    final listener = pair.host.incoming.listen((r) {
      requests.add(r);
      unawaited(
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: r.name,
            correlationId: r.correlationId,
            sessionGeneration: r.sessionGeneration,
            accountContext: owner,
            status: failure == null ? 'ok' : 'error',
            payload: {
              if (r.name == 'account.getCurrent' ||
                  r.name == 'missionRecords.summary')
                'schemaVersion': 1,
              if (r.name == 'account.getCurrent') 'state': 'signedIn',
            },
            error: failure == null
                ? null
                : BridgeErrorBody(
                    code: failure,
                    message: 'Synthetic',
                    retryable: false,
                  ),
          ),
        ),
      );
    });
    try {
      for (final op in [
        'summary',
        'importStart',
        'importRead',
        'importCancel',
      ]) {
        await port.request(
          op,
          op == 'importRead' || op == 'importCancel'
              ? {'scanId': 'fixture-scan'}
              : {},
        );
      }
      expect(requests.map((r) => r.name), [
        'account.getCurrent',
        'missionRecords.summary',
        'missionRecords.importStart',
        'missionRecords.importRead',
        'missionRecords.importCancel',
      ]);
      expect(
        requests
            .skip(1)
            .every((r) => r.accountContext?.subject == owner.subject),
        isTrue,
      );
      expect(requests.every((r) => r.payload['schemaVersion'] == 1), isTrue);
      expect(requests[3].payload, {
        'schemaVersion': 1,
        'scanId': 'fixture-scan',
      });
      failure = 'missionRecords.busy';
      await expectLater(
        port.request('importStart'),
        throwsA(
          isA<MissionRecordsFailure>().having((e) => e.code, 'code', failure),
        ),
      );
      final count = requests.length;
      await mode.enterOffline();
      await expectLater(
        port.request('summary'),
        throwsA(isA<MissionRecordsFailure>()),
      );
      expect(requests, hasLength(count));
    } finally {
      port.dispose();
      mode.dispose();
      await listener.cancel();
      await session.close();
      await pair.host.close();
    }
  });

  test('old Host never issues even an account read', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    final mode = Mode(), port = BridgeMissionRecordsPort(session, mode);
    final requests = <BridgeEnvelope>[];
    final listener = pair.host.incoming.listen(requests.add);
    try {
      expect(port.supported, isFalse);
      await expectLater(
        port.request('summary'),
        throwsA(isA<MissionRecordsFailure>()),
      );
      expect(requests, isEmpty);
    } finally {
      port.dispose();
      mode.dispose();
      await listener.cancel();
      await session.close();
      await pair.host.close();
    }
  });

  test('read-only capability allows summary but blocks import', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    session.acceptHostCapabilities(['missionRecords.read']);
    final mode = Mode(), port = BridgeMissionRecordsPort(session, mode);
    try {
      expect(port.readable, isTrue);
      expect(port.importSupported, isFalse);
      await expectLater(
        port.request('importStart'),
        throwsA(isA<MissionRecordsFailure>()),
      );
    } finally {
      port.dispose();
      mode.dispose();
      await session.close();
      await pair.host.close();
    }
  });

  for (final retire in ['generation', 'mode', 'capability', 'offline']) {
    test('late owner response is rejected after $retire retirement', () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      );
      session.acceptHostCapabilities([
        'missionRecords.read',
        'missionRecords.import',
      ]);
      final mode = Mode(), port = BridgeMissionRecordsPort(session, mode);
      final pending = Completer<BridgeEnvelope>(),
          requests = <BridgeEnvelope>[];
      final listener = pair.host.incoming.listen((r) {
        requests.add(r);
        if (r.name == 'account.getCurrent' && !pending.isCompleted) {
          pending.complete(r);
        }
      });
      try {
        final read = port.request('summary');
        final assertion = expectLater(
          read,
          throwsA(isA<MissionRecordsFailure>()),
        );
        final request = await pending.future;
        switch (retire) {
          case 'generation':
            session.advanceGeneration(2);
          case 'mode':
            await session.runConnectionModeChange(() async {});
          case 'capability':
            session.acceptHostCapabilities([]);
          case 'offline':
            await mode.enterOffline();
        }
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: 1,
            status: 'ok',
            accountContext: owner,
            payload: const {'schemaVersion': 1},
          ),
        );
        await assertion;
        expect(
          requests.where((r) => r.name == 'missionRecords.summary'),
          isEmpty,
        );
      } finally {
        port.dispose();
        mode.dispose();
        await listener.cancel();
        await session.close();
        await pair.host.close();
      }
    });
  }
}
