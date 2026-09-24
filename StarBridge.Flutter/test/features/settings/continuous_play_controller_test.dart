import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_controller.dart';
import 'package:starbridge_flutter/features/settings/bridge_continuous_play.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test(
    'settings are unknown until read, then persist actual returned values',
    () async {
      final port = _Port();
      final controller = ContinuousPlayController(port);
      addTearDown(controller.dispose);
      expect(controller.value.settings, isNull);
      expect(await controller.refresh(), isTrue);
      expect(controller.value.settings!.firstMinutes, 120);
      expect(
        await controller.save(
          enabled: false,
          firstMinutes: 90,
          repeatMinutes: 60,
        ),
        isTrue,
      );
      expect(controller.value.settings!.enabled, isFalse);
      expect(controller.value.settings!.revision, 1);
    },
  );
  test(
    'failed save preserves real settings, never optimistic success',
    () async {
      final port = _Port();
      final controller = ContinuousPlayController(port);
      addTearDown(controller.dispose);
      await controller.refresh();
      port.fail = true;
      expect(
        await controller.save(
          enabled: false,
          firstMinutes: 90,
          repeatMinutes: 60,
        ),
        isFalse,
      );
      expect(controller.value.settings!.enabled, isTrue);
      expect(controller.value.failed, isTrue);
    },
  );
  test('pending saves coalesce and disposed results are ignored', () async {
    final port = _Port();
    final controller = ContinuousPlayController(port);
    await controller.refresh();
    port.hold = Completer<ContinuousPlayValue>();
    final pending = controller.save(
      enabled: false,
      firstMinutes: 60,
      repeatMinutes: 60,
    );
    expect(
      await controller.save(
        enabled: true,
        firstMinutes: 120,
        repeatMinutes: 120,
      ),
      isFalse,
    );
    controller.dispose();
    port.hold!.complete(port.value);
    expect(await pending, isFalse);
  });
  test(
    'Bridge reads and saves device settings with revision, no account',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(connection: pair.client, sessionGeneration: 1);
      addTearDown(session.close);
      addTearDown(pair.host.close);
      final requests = <BridgeEnvelope>[];
      final subscription = pair.host.incoming.listen((request) async {
        requests.add(request);
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            status: 'ok',
            payload: {
              'schemaVersion': 1,
              'enabled': request.name.endsWith('read'),
              'firstReminderMinutes': 120,
              'repeatReminderMinutes': 120,
              'revision': request.name.endsWith('read') ? 0 : 1,
            },
          ),
        );
      });
      addTearDown(subscription.cancel);
      final adapter = BridgeContinuousPlay(session);
      final value = await adapter.read();
      expect(value.enabled, isTrue);
      expect((await adapter.save(value)).revision, 1);
      expect(requests.every((r) => r.accountContext == null), isTrue);
      expect(requests.last.payload['expectedRevision'], 0);
    },
  );
  test(
    'Bridge rejects unsupported interval rather than showing a default',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(connection: pair.client, sessionGeneration: 1);
      addTearDown(session.close);
      addTearDown(pair.host.close);
      final subscription = pair.host.incoming.listen((request) async {
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            status: 'ok',
            payload: const {
              'schemaVersion': 1,
              'enabled': true,
              'firstReminderMinutes': 10,
              'repeatReminderMinutes': 120,
              'revision': 0,
            },
          ),
        );
      });
      addTearDown(subscription.cancel);
      await expectLater(
        BridgeContinuousPlay(session).read(),
        throwsA(isA<BridgeFormatException>()),
      );
    },
  );
}

final class _Port implements ContinuousPlayPort {
  ContinuousPlayValue value = const ContinuousPlayValue(
    enabled: true,
    firstMinutes: 120,
    repeatMinutes: 120,
    revision: 0,
  );
  bool fail = false;
  Completer<ContinuousPlayValue>? hold;
  @override
  Future<ContinuousPlayValue> read() async => value;
  @override
  Future<ContinuousPlayValue> save(ContinuousPlayValue desired) async {
    if (fail) throw StateError('storage unavailable');
    if (hold != null) return hold!.future;
    return value = ContinuousPlayValue(
      enabled: desired.enabled,
      firstMinutes: desired.firstMinutes,
      repeatMinutes: desired.repeatMinutes,
      revision: desired.revision + 1,
    );
  }
}
