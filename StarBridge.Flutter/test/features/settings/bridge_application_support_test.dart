import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/application_support_models.dart';
import 'package:starbridge_flutter/features/settings/bridge_application_support.dart';
import 'package:starbridge_flutter/features/settings/bridge_data_location.dart';
import 'package:starbridge_flutter/features/settings/bridge_data_location_result.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test(
    'location reads the owned path without account or caller path',
    () async {
      final harness = _ApplicationSupportHostHarness(
        payload: const {
          'schemaVersion': 1,
          'path': r'G:\StarBridge\data',
          'exists': true,
        },
      );
      addTearDown(harness.close);
      final location = await BridgeDataLocation(harness.session).read();
      expect(location.path, r'G:\StarBridge\data');
      expect(location.exists, isTrue);
      expect(harness.requests.single.name, 'diagnostics.getDataLocation');
      expect(harness.requests.single.accountContext, isNull);
      expect(harness.requests.single.payload, {'schemaVersion': 1});
    },
  );

  for (final path in [
    'relative/path',
    'https://example.test/data',
    'G:\\data\nsecret',
    '',
  ]) {
    test('rejects invalid location $path', () async {
      final harness = _ApplicationSupportHostHarness(
        payload: {'schemaVersion': 1, 'path': path, 'exists': true},
      );
      addTearDown(harness.close);
      await expectLater(
        BridgeDataLocation(harness.session).read(),
        throwsA(isA<BridgeFormatException>()),
      );
    });
  }

  test('migration uses host-owned choice and one-time ticket only', () async {
    final choiceHost = _ApplicationSupportHostHarness(
      payload: const {
        'schemaVersion': 1,
        'state': 'confirmation-required',
        'ticket': '0123456789abcdef0123456789abcdef',
        'source': r'G:\StarBridge\data',
        'destination': r'D:\StarBridge\data',
      },
    );
    addTearDown(choiceHost.close);
    choiceHost.session.acceptHostCapabilities(const [
      'dataLocation.chooseMigration',
      'dataLocation.confirmMigration',
    ]);
    final choice = await BridgeDataLocation(choiceHost.session)
        .chooseMigration();
    expect(choice?.destination, r'D:\StarBridge\data');
    expect(choiceHost.requests.single.payload, const {'schemaVersion': 1});

    final confirmHost = _ApplicationSupportHostHarness(
      payload: const {'schemaVersion': 1, 'accepted': true},
    );
    addTearDown(confirmHost.close);
    confirmHost.session.acceptHostCapabilities(const [
      'dataLocation.chooseMigration',
      'dataLocation.confirmMigration',
    ]);
    await BridgeDataLocation(confirmHost.session)
        .confirmMigration(choice!.ticket);
    expect(confirmHost.requests.single.payload, {
      'schemaVersion': 1,
      'ticket': choice.ticket,
    });
  });

  test(
    'migration result is read and acknowledged without account context',
    () async {
      final resultHost = _ApplicationSupportHostHarness(
        payload: const {
          'schemaVersion': 1,
          'state': 'migrated',
          'nonce': '0123456789abcdef0123456789abcdef',
          'source': r'G:\StarBridge\data',
          'destination': r'D:\StarBridge\data',
          'completedAt': '2026-09-13T18:00:00Z',
        },
      );
      addTearDown(resultHost.close);
      final result = await BridgeDataLocationResult(resultHost.session).read();
      expect(result?.state, 'migrated');
      expect(resultHost.requests.single.accountContext, isNull);

      final ackHost = _ApplicationSupportHostHarness(
        payload: const {'schemaVersion': 1, 'acknowledged': true},
      );
      addTearDown(ackHost.close);
      await BridgeDataLocationResult(ackHost.session)
          .acknowledge(result!.nonce);
      expect(ackHost.requests.single.payload, {
        'schemaVersion': 1,
        'nonce': result.nonce,
      });
    },
  );

  test(
    'reads the allowlisted support summary without account context',
    () async {
      final harness = _ApplicationSupportHostHarness();

      final snapshot = await harness.adapter.inspect();

      expect(snapshot.hasIssues, isTrue);
      expect(snapshot.dataDirectory.detail, 'writable');
      expect(
        snapshot.gameLog.state,
        ApplicationSupportCheckState.actionRequired,
      );
      expect(snapshot.installation.otherInstallations, 1);
      expect(harness.requests.single.name, 'diagnostics.getSafeSummary');
      expect(harness.requests.single.accountContext, isNull);
      expect(harness.requests.single.payload, const {'schemaVersion': 1});
      await harness.close();
    },
  );

  test('rejects an inconsistent or unsafe-shaped result', () async {
    final harness = _ApplicationSupportHostHarness(
      payload: {..._supportPayload, 'hasIssues': false},
    );

    await expectLater(
      harness.adapter.inspect(),
      throwsA(
        isA<ApplicationSupportException>().having(
          (error) => error.failure,
          'failure',
          ApplicationSupportFailure.invalidResponse,
        ),
      ),
    );
    await harness.close();
  });

  test('maps stale session generation to host unavailable', () async {
    final harness = _ApplicationSupportHostHarness(holdResponse: true);
    final pending = harness.adapter.inspect();
    await harness.requestReceived.future;

    harness.session.advanceGeneration(5);

    await expectLater(
      pending,
      throwsA(
        isA<ApplicationSupportException>().having(
          (error) => error.failure,
          'failure',
          ApplicationSupportFailure.hostUnavailable,
        ),
      ),
    );
    await harness.close();
  });

  test('opens the Host-owned data directory without sending a path', () async {
    final harness = _ApplicationSupportHostHarness();

    await harness.adapter.openDataDirectory();

    expect(harness.requests.single.name, 'diagnostics.openDataDirectory');
    expect(harness.requests.single.accountContext, isNull);
    expect(harness.requests.single.payload, const {'schemaVersion': 1});
    await harness.close();
  });
}

final class _ApplicationSupportHostHarness {
  _ApplicationSupportHostHarness({
    this.payload = _supportPayload,
    this.holdResponse = false,
  }) {
    final pair = InMemoryBridgeConnection.createPair();
    host = pair.host;
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
      requestTimeout: const Duration(seconds: 1),
    );
    adapter = BridgeApplicationSupport(session);
    subscription = host.incoming.listen(_respond);
  }

  final Map<String, Object?> payload;
  final bool holdResponse;
  late final BridgeConnection host;
  late final BridgeClientSession session;
  late final BridgeApplicationSupport adapter;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final List<BridgeEnvelope> requests = [];
  final Completer<void> requestReceived = Completer<void>();

  Future<void> _respond(BridgeEnvelope request) async {
    requests.add(request);
    if (!requestReceived.isCompleted) requestReceived.complete();
    if (holdResponse) return;
    final responsePayload = request.name == 'diagnostics.openDataDirectory'
        ? const <String, Object?>{'schemaVersion': 1, 'opened': true}
        : payload;
    await host.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        payload: responsePayload,
        status: 'ok',
      ),
    );
  }

  Future<void> close() async {
    await adapter.close();
    await subscription.cancel();
    await session.close();
    await host.close();
  }
}

const _supportPayload = <String, Object?>{
  'schemaVersion': 1,
  'hasIssues': true,
  'hasUnavailableChecks': false,
  'checks': <String, Object?>{
    'dataDirectory': <String, Object?>{
      'state': 'healthy',
      'detail': 'writable',
    },
    'gameLog': <String, Object?>{
      'state': 'actionRequired',
      'detail': 'fileMissing',
    },
    'startup': <String, Object?>{
      'state': 'healthy',
      'detail': 'notEnabled',
      'registered': false,
      'targetExists': null,
      'targetsCurrentExecutable': null,
    },
    'installation': <String, Object?>{
      'state': 'actionRequired',
      'detail': 'duplicateInstallations',
      'mode': 'installed',
      'currentInstallations': 1,
      'otherInstallations': 1,
      'orphanedRegistrations': 0,
      'scanWarnings': 0,
    },
  },
};
