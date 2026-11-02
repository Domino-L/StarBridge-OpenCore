import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_restore_display.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

const _path = String.fromEnvironment('STARBRIDGE_RESTORE_DISPLAY_WIRE');

void main() {
  for (final boundary in [
    'accepted',
    'timeout',
    'mode',
    'dispose',
    'direct',
    'bootstrap',
    'disconnect',
  ]) {
    test(
      'restore generation wait settles on $boundary without using the old context',
      () async {
        final wire = jsonDecode(File(_path).readAsStringSync()) as Map;
        BridgeEnvelope native(String key) =>
            BridgeEnvelope.fromJson((wire[key] as Map).cast<String, Object?>());
        final prepared = native('prepared'), completed = native('completed');
        final pair = InMemoryBridgeConnection.createPair();
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 0,
          correlationIdFactory: () => completed.correlationId!,
        );
        session.acceptHostCapabilities(['account.restoreDisplay']);
        final display = AccountRestoreDisplay(session);
        final events = session.events.listen(display.observeEvent);
        final requests = <BridgeEnvelope>[];
        final host = pair.host.incoming.listen(requests.add);
        BridgeEnvelope? response;
        Object? failure;
        var settled = false;
        final pending = display
            .read(const Duration(seconds: 10))
            .then<void>(
              (value) {
                response = value;
                settled = true;
              },
              onError: (Object error) {
                failure = error;
                settled = true;
              },
            );
        try {
          await Future<void>.delayed(Duration.zero);
          await pair.host.send(prepared);
          await Future<void>.delayed(Duration.zero);
          await pair.host.send(completed);
          await Future<void>.delayed(Duration.zero);
          expect(settled, isFalse);
          expect(display.value?.retainedReadId, isNull);
          expect(display.value?.isSignedIn, isFalse);
          expect(display.value?.hasDisplayHandoff, isTrue);
          switch (boundary) {
            case 'accepted':
              await pair.host.send(
                BridgeEnvelope(
                  protocolVersion: 1,
                  messageType: 'event',
                  name: 'account.changed',
                  sessionGeneration: 1,
                  sequence: prepared.sequence! + 1,
                  payload: const {'schemaVersion': 1},
                ),
              );
            case 'timeout':
              await Future<void>.delayed(const Duration(seconds: 5));
            case 'mode':
              await session.runConnectionModeChange(() async {});
            case 'dispose':
              display.dispose();
            case 'direct':
              session.advanceGeneration(1);
            case 'bootstrap':
              await pair.host.send(
                BridgeEnvelope(
                  protocolVersion: 1,
                  messageType: 'event',
                  name: 'bootstrap.invalidated',
                  sessionGeneration: 0,
                  sequence: prepared.sequence! + 1,
                  payload: const {'schemaVersion': 1},
                ),
              );
            case 'disconnect':
              await session.close();
          }
          await Future<void>.delayed(Duration.zero);
          await pending;
          expect(settled, isTrue);
          expect(requests.map((r) => r.name), ['account.getCurrent']);
          if (boundary == 'accepted') {
            expect(failure, isNull);
            expect(
              response?.sessionGeneration,
              0,
              reason: 'Never retime a root response.',
            );
            expect(session.activeGeneration, 1);
            expect(display.value?.isSignedIn, isFalse);
          } else {
            expect(response, isNull);
            expect(
              failure,
              boundary == 'timeout'
                  ? isA<BridgeTimeoutException>()
                  : isA<BridgeCancelledException>(),
            );
            if (boundary != 'dispose') expect(display.value, isNull);
          }
        } finally {
          display.dispose();
          await session.close();
          await pending;
          await events.cancel();
          await host.cancel();
          await pair.host.close();
        }
      },
      skip: _path.isEmpty
          ? 'Requires actual Native restore-display wire.'
          : false,
    );
  }
}
