import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/profile_read_scope.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  const path = String.fromEnvironment('STARBRIDGE_HOST_FAULT_WIRE');
  for (final mode in [
    'nativeHostError',
    'legacyRemoteDisconnected',
    'connectionClosed',
  ]) {
    test(
      'actual Host baseline then $mode keeps only genuinely recoverable display',
      () async {
        final fixture =
            jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
        final success = BridgeEnvelope.fromJson(
          (fixture['success'] as Map).cast<String, Object?>(),
        );
        final fault = BridgeEnvelope.fromJson(
          (fixture['fault'] as Map).cast<String, Object?>(),
        );
        final pair = InMemoryBridgeConnection.createPair();
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: success.sessionGeneration,
        );
        var reads = 0;
        final incoming = pair.host.incoming.listen((request) {
          if (request.name == 'bridge.cancel') return;
          if (request.name == 'account.getCurrent') {
            unawaited(
              pair.host.send(
                BridgeEnvelope(
                  protocolVersion: 1,
                  messageType: 'response',
                  name: request.name,
                  correlationId: request.correlationId,
                  sessionGeneration: success.sessionGeneration,
                  accountContext: success.accountContext,
                  status: 'ok',
                  payload: const {'schemaVersion': 1, 'state': 'signedIn'},
                ),
              ),
            );
          } else {
            final captured = ++reads == 1 ? success : fault;
            if (reads > 1 && mode == 'connectionClosed') {
              unawaited(pair.client.close());
            } else {
              unawaited(
                pair.host.send(
                  BridgeEnvelope.fromJson({
                    ...captured.toJson(),
                    'correlationId': request.correlationId,
                    if (reads > 1 && mode == 'legacyRemoteDisconnected')
                      'error': {
                        'code': 'bridge.disconnected',
                        'retryable': true,
                        'message': 'Legacy Host fault.',
                      },
                  }),
                ),
              );
            }
          }
        });
        final module = createPersonalProfileModule(
          BridgePersonalProfileAdapter(session),
        );
        addTearDown(() async {
          module.dispose();
          await incoming.cancel();
          await session.close();
          await pair.host.close();
        });
        await module.initialize();
        expect(
          module.projection.value.availability,
          PersonalProfileAvailability.available,
        );
        expect(module.projection.value.callSign, 'Synthetic pilot');
        await module.refresh();
        final observed =
            (module as ProfileReadObservationOwner).readObservation;
        expect(observed?.generation, success.sessionGeneration);
        expect(
          observed?.phase,
          mode == 'connectionClosed'
              ? ProfileReadPhase.transientFailure
              : ProfileReadPhase.unavailable,
        );
        expect(
          reads,
          2,
          reason: 'An unknown failure must not automatically replay the read.',
        );
        expect(
          module.projection.value.availability,
          mode == 'connectionClosed'
              ? PersonalProfileAvailability.available
              : PersonalProfileAvailability.unavailable,
        );
        expect(
          module.projection.value.callSign,
          mode == 'connectionClosed' ? 'Synthetic pilot' : isEmpty,
        );
        expect(module.projection.value.canEdit, isFalse);
        expect(
          module.projection.value.refreshFailed,
          mode == 'connectionClosed',
        );
      },
      skip: path.isEmpty
          ? 'Requires the explicitly generated synthetic Native Host wire fixture.'
          : false,
    );
  }
}
