import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_connection_mode_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'connection_mode_test.dart' show modeWire;

void main() {
  for (final boundary in [
    'online',
    'offline',
    'failure',
    'bootstrap',
    'onboarding',
    'skipped',
    'malformed',
    'duplicate',
    'direct',
    'logout',
    'dispose',
  ]) {
    test(
      'mode display continuity never authorizes traffic and retires at $boundary',
      () async {
        final pair = InMemoryBridgeConnection.createPair();
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 0,
        );
        session.acceptHostCapabilities(['onboarding.mode.v1']);
        final port = BridgeConnectionModeAdapter(session);
        final control = ConnectionModeController(port);
        var disposed = false;
        final requests = <BridgeEnvelope>[];
        final held = <BridgeEnvelope>[];
        Future<void> reply(
          BridgeEnvelope request, {
          bool failed = false,
          String state = 'online',
        }) => pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            status: failed ? 'error' : 'ok',
            payload: failed ? const {} : modeWire(state),
            error: failed
                ? const BridgeErrorBody(
                    code: 'onboarding.unavailable',
                    message: 'fixture',
                    retryable: true,
                  )
                : null,
          ),
        );
        final subscription = pair.host.incoming.listen((request) {
          requests.add(request);
          if (requests.length == 1) {
            unawaited(reply(request));
          } else {
            held.add(request);
          }
        });
        Future<void> drain() async {
          for (var i = 0; i < 4; i++) {
            await Future<void>.delayed(Duration.zero);
          }
        }

        Future<void> event(
          String name,
          int generation,
          int sequence, {
          Object schema = 1,
        }) => pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'event',
            name: name,
            sessionGeneration: generation,
            sequence: sequence,
            payload: {'schemaVersion': schema},
          ),
        );
        try {
          await control.refresh();
          expect(control.allowsOnlineTraffic, isTrue);
          expect(control.displayContinuity, isNull);
          final firstName = boundary == 'bootstrap'
              ? 'bootstrap.invalidated'
              : boundary == 'onboarding'
              ? 'onboarding.changed'
              : 'account.changed';
          final firstGeneration = ['bootstrap', 'onboarding'].contains(boundary)
              ? 0
              : boundary == 'skipped'
              ? 2
              : 1;
          await event(
            firstName,
            firstGeneration,
            1,
            schema: boundary == 'malformed' ? 1.0 : 1,
          );
          await drain();
          expect(control.allowsOnlineTraffic, isFalse);
          expect(control.canEnterOffline, isFalse);
          expect(await control.enterOffline(), isFalse);
          expect(() => port.enterOffline(4), throwsStateError);
          final valid = ![
            'bootstrap',
            'onboarding',
            'skipped',
            'malformed',
          ].contains(boundary);
          expect(control.displayContinuity != null, valid);
          if (valid) {
            expect(control.displayContinuity!.sourceGeneration, 0);
            expect(control.displayContinuity!.generation, 1);
            expect(control.displayContinuity!.revision, 4);
          }
          if (['online', 'offline', 'failure'].contains(boundary)) {
            expect(held, hasLength(1));
            await reply(
              held.single,
              failed: boundary == 'failure',
              state: boundary == 'offline' ? 'offline' : 'online',
            );
          } else if (boundary == 'duplicate' || boundary == 'logout') {
            await event('account.changed', boundary == 'logout' ? 2 : 1, 2);
          } else if (boundary == 'direct') {
            session.advanceGeneration(2);
          } else if (boundary == 'dispose') {
            control.dispose();
            disposed = true;
          }
          await drain();
          expect(control.displayContinuity, isNull);
          expect(
            requests.every(
              (request) =>
                  request.name == 'onboarding.mode.read' &&
                  request.accountContext == null,
            ),
            isTrue,
          );
          if (boundary == 'online') expect(control.allowsOnlineTraffic, isTrue);
          if (boundary == 'failure') expect(control.failed, isTrue);
          if (boundary == 'offline') {
            expect(control.allowsOnlineTraffic, isFalse);
          }
        } finally {
          if (!disposed) control.dispose();
          await session.close();
          await drain();
          await subscription.cancel();
          await pair.host.close();
        }
      },
    );
  }
}
