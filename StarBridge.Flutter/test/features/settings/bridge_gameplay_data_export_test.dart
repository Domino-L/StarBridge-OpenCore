import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/bridge_gameplay_data_export.dart';
import 'package:starbridge_flutter/features/settings/gameplay_data_export_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test('foreign account response never claims a saved file', () async {
    final h = _Harness(foreignOwner: true);
    addTearDown(h.close);
    expect(await h.adapter.export('en'), GameplayExportOutcome.unknown);
  });
  test(
    'export is account-bound and sends no file path or statistics',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      expect(await h.adapter.export('zh-CN'), GameplayExportOutcome.saved);
      final request = h.requests.single;
      expect(request.name, 'gameplayTime.export');
      expect(request.accountContext?.subject, 'fixture');
      expect(request.sessionGeneration, 4);
      expect(request.payload, {'schemaVersion': 1, 'locale': 'zh-CN'});
    },
  );
  test('picker cancellation is not success', () async {
    final h = _Harness(outcome: 'cancelled');
    addTearDown(h.close);
    expect(await h.adapter.export('en'), GameplayExportOutcome.cancelled);
  });
  for (final item in {
    'gameplayExport.account_changed': GameplayExportOutcome.accountChanged,
    'gameplayExport.data_unavailable': GameplayExportOutcome.dataUnavailable,
    'gameplayExport.file_exists': GameplayExportOutcome.fileExists,
    'gameplayExport.invalid_destination':
        GameplayExportOutcome.invalidDestination,
    'gameplayExport.save_failed': GameplayExportOutcome.failed,
    'gameplayExport.busy': GameplayExportOutcome.busy,
  }.entries) {
    test('maps ${item.key}', () async {
      final h = _Harness(error: item.key);
      addTearDown(h.close);
      expect(await h.adapter.export('en'), item.value);
    });
  }
  test('uncertain response never becomes success', () async {
    final h = _Harness(outcome: 'something-new');
    addTearDown(h.close);
    expect(await h.adapter.export('en'), GameplayExportOutcome.unknown);
  });
  test('duplicates are suppressed and disconnect is uncertain', () async {
    final h = _Harness(hold: true);
    addTearDown(h.close);
    final pending = h.adapter.export('en');
    await h.received.future;
    expect(await h.adapter.export('en'), GameplayExportOutcome.busy);
    await h.session.close();
    expect(await pending, GameplayExportOutcome.unknown);
    expect(h.requests.length, 1);
  });
  test('account generation change suppresses old result', () async {
    final h = _Harness(hold: true);
    addTearDown(h.close);
    final pending = h.adapter.export('en');
    await h.received.future;
    h.session.advanceGeneration(5);
    expect(await pending, GameplayExportOutcome.accountChanged);
  });
  test('cancel sends cancellation and does not claim a saved file', () async {
    final h = _Harness(hold: true);
    addTearDown(h.close);
    final pending = h.adapter.export('en');
    await h.received.future;
    h.adapter.cancel();
    expect(await pending, isNot(GameplayExportOutcome.saved));
    await Future<void>.delayed(Duration.zero);
    expect(h.messages.any((e) => e.name == 'bridge.cancel'), isTrue);
  });
}

final class _Harness {
  _Harness({
    this.outcome = 'saved',
    this.error,
    this.hold = false,
    bool foreignOwner = false,
  }) {
    final pair = InMemoryBridgeConnection.createPair();
    host = pair.host;
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
    );
    adapter = BridgeGameplayDataExport(
      session,
      const BridgeAccountContext(
        environment: 'test',
        authority: 'local',
        subject: 'fixture',
      ),
    );
    subscription = host.incoming.listen((request) async {
      messages.add(request);
      if (request.messageType != 'request' ||
          request.name != 'gameplayTime.export') {
        return;
      }
      requests.add(request);
      if (!received.isCompleted) received.complete();
      if (hold) return;
      await host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: 4,
          accountContext: foreignOwner
              ? const BridgeAccountContext(
                  environment: 'test',
                  authority: 'local',
                  subject: 'other',
                )
              : request.accountContext,
          payload: error == null
              ? {'schemaVersion': 1, 'outcome': outcome}
              : const {},
          status: error == null ? 'ok' : 'error',
          error: error == null
              ? null
              : BridgeErrorBody(
                  code: error!,
                  message: 'private internal detail',
                  retryable: true,
                ),
        ),
      );
    });
  }
  final String outcome;
  final String? error;
  final bool hold;
  late final BridgeConnection host;
  late final BridgeClientSession session;
  late final BridgeGameplayDataExport adapter;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final received = Completer<void>();
  final requests = <BridgeEnvelope>[];
  final messages = <BridgeEnvelope>[];
  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await host.close();
  }
}
