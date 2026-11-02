import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/window/bridge_menu_hotkeys.dart';

void main() {
  for (final dispose in [false, true]) {
    test(
      'pending recovery is canceled on ${dispose ? 'dispose' : 'owner revocation'}',
      () async {
        final pair = InMemoryBridgeConnection.createPair();
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 2,
        );
        final active = ValueNotifier(true);
        var attempts = 0, client = 0;
        final subscription = pair.host.incoming.listen((request) async {
          if (request.name == 'menuHotkey.attach') attempts++;
          await pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: 2,
              payload: const {},
              status: 'error',
              error: const BridgeErrorBody(
                code: 'unavailable',
                message: 'Temporary',
                retryable: true,
              ),
            ),
          );
        });
        final port = BridgeMenuHotkeys(
          session,
          activation: active,
          isActive: () => active.value,
        );
        port.initialize(() => ++client, (_) async {}, () {});
        try {
          while (attempts == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
          if (dispose) {
            port.dispose();
          } else {
            active.value = false;
          }
          await Future<void>.delayed(const Duration(milliseconds: 2200));
          expect(
            attempts,
            1,
            reason:
                'A pending retry cannot reacquire revoked shortcut authority',
          );
        } finally {
          port.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await subscription.cancel();
          await session.close();
          await pair.host.close();
          active.dispose();
        }
      },
    );
  }
  test('a temporary attach failure cannot leave game menu shortcut permanently inert', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 2,
    );
    final activation = ChangeNotifier();
    var attempts = 0, client = 0, opened = 0;
    final subscription = pair.host.incoming.listen((request) async {
      if (request.name == 'menuHotkey.attach') attempts++;
      await pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: 2,
          payload: {'schemaVersion': 1, 'state': 'registered'},
          status: attempts == 1 && request.name == 'menuHotkey.attach'
              ? 'error'
              : 'ok',
          error: attempts == 1 && request.name == 'menuHotkey.attach'
              ? const BridgeErrorBody(
                  code: 'menuHotkey.unavailable',
                  message: 'Temporary',
                  retryable: true,
                )
              : null,
        ),
      );
    });
    final port = BridgeMenuHotkeys(
      session,
      activation: activation,
      isActive: () => true,
    );
    port.initialize(() => ++client, (_) async => opened++, () {});
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (attempts < 2 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        attempts,
        greaterThanOrEqualTo(2),
        reason: 'Must recover without changing account or reopening settings',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'menuHotkey.intent',
          sessionGeneration: 2,
          sequence: 1,
          payload: {
            'schemaVersion': 1,
            'client': client,
            'action': 'open',
            'request': 0,
            'targetWindow': 77,
            'targetProcessId': 88,
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        opened,
        1,
        reason: 'Real BridgeMenuHotkeys must forward the verified game opening intent after recovery',
      );
    } finally {
      port.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await subscription.cancel();
      await session.close();
      await pair.host.close();
      activation.dispose();
    }
  });
}
