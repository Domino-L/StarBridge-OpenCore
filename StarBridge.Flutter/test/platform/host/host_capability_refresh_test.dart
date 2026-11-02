import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/host/host_capability_refresh.dart';
import 'package:starbridge_flutter/platform/host/native_host_connector.dart';

const baseCapabilities = ['host.lifecycle', 'account.read'];
const dynamicCapabilities = [
  'privacy.officialFleetScopes',
  'officialFleet.runtimeMembers',
  'officialFleet.runtimeActivity',
];
void main() {
  test('optional old Ready preserves negotiated capabilities and does not invent support', () async {
    final h = CapabilityHarness();
    addTearDown(h.close);
    final pending = h.binding.refresh();
    await h.waitForReady();
    await h.reply(h.requests.last, {
      'ready': true,
      'hostInstanceId': 'synthetic-host',
    });
    await pending;
    expect(h.session.hostCapabilities, baseCapabilities.toSet());
  });
  test('new Ready after mode owner install updates existing session and notifies reconcile', () async {
    final h = CapabilityHarness();
    addTearDown(h.close);
    var notifications = 0;
    final subscription = h.session.capabilitiesChanged.listen(
      (_) => notifications++,
    );
    addTearDown(subscription.cancel);
    final pending = h.session.runConnectionModeChange(() async {
      h.session.advanceGeneration(2);
      return true;
    });
    await h.waitForReady();
    expect(h.requests, hasLength(1));
    expect(h.requests.single.sessionGeneration, 2);
    await h.reply(h.requests.single, {
      'ready': true,
      'hostInstanceId': 'synthetic-host',
      'hostCapabilities': [...baseCapabilities, ...dynamicCapabilities],
    });
    expect(await pending, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(h.session.hostCapabilities, containsAll(dynamicCapabilities));
    expect(notifications, 1);
  });
  test(
    'late Ready from retired generation cannot restore former owner support',
    () async {
      final h = CapabilityHarness();
      addTearDown(h.close);
      h.session.acceptHostCapabilities([
        ...baseCapabilities,
        ...dynamicCapabilities,
      ]);
      final pending = h.binding.refresh();
      await h.waitForReady();
      final old = h.requests.last;
      h.session.advanceGeneration(2);
      expect(
        h.session.hostCapabilities,
        isNot(contains(dynamicCapabilities.first)),
      );
      await h.reply(old, {
        'ready': true,
        'hostInstanceId': 'synthetic-host',
        'hostCapabilities': [...baseCapabilities, ...dynamicCapabilities],
      });
      await h.waitForReady(count: 2);
      await h.reply(h.requests.last, {
        'ready': true,
        'hostInstanceId': 'synthetic-host',
        'hostCapabilities': baseCapabilities,
      });
      await pending;
      expect(h.session.hostCapabilities, baseCapabilities.toSet());
    },
  );
  test(
    'same-generation account retirement fences an unfinished Ready',
    () async {
      final h = CapabilityHarness();
      addTearDown(h.close);
      final pending = h.binding.refresh();
      await h.waitForReady();
      final old = h.requests.last;
      await h.pair.host.send(
        const BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'bootstrap.invalidated',
          sessionGeneration: 1,
          sequence: 1,
          payload: {'schemaVersion': 1},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await h.reply(old, {
        'ready': true,
        'hostInstanceId': 'synthetic-host',
        'hostCapabilities': [...baseCapabilities, ...dynamicCapabilities],
      });
      await h.waitForReady(count: 2);
      expect(h.session.hostCapabilities, baseCapabilities.toSet());
      await h.reply(h.requests.last, {
        'ready': true,
        'hostInstanceId': 'synthetic-host',
        'hostCapabilities': baseCapabilities,
      });
      await pending;
      expect(h.session.hostCapabilities, baseCapabilities.toSet());
    },
  );
  test(
    'repeated owner/generation events coalesce without parallel Ready requests',
    () async {
      final h = CapabilityHarness();
      addTearDown(h.close);
      h.session.advanceGeneration(2);
      await h.waitForReady();
      for (var sequence = 1; sequence <= 3; sequence++) {
        await h.pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'event',
            name: 'bootstrap.invalidated',
            sessionGeneration: 2,
            sequence: sequence,
            payload: const {'schemaVersion': 1},
          ),
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(h.requests, hasLength(1));
      await h.reply(h.requests.single, {
        'ready': true,
        'hostInstanceId': 'synthetic-host',
        'hostCapabilities': [...baseCapabilities, ...dynamicCapabilities],
      });
      await h.waitForReady(count: 2);
      expect(h.session.hostCapabilities, baseCapabilities.toSet());
      await h.reply(h.requests.last, {
        'ready': true,
        'hostInstanceId': 'synthetic-host',
        'hostCapabilities': baseCapabilities,
      });
      await Future<void>.delayed(Duration.zero);
      expect(h.requests, hasLength(2));
    },
  );
  test('failed Ready cannot add capability and unchanged notification readback stops', () async {
    final h = CapabilityHarness();
    addTearDown(h.close);
    final failed = h.binding.refresh();
    await h.waitForReady();
    await h.reply(h.requests.last, {
      'ready': true,
      'hostInstanceId': 'wrong',
      'hostCapabilities': [...baseCapabilities, ...dynamicCapabilities],
    });
    await failed;
    expect(h.session.hostCapabilities, baseCapabilities.toSet());
    var notifications = 0;
    final subscription = h.session.capabilitiesChanged.listen((_) {
      notifications++;
      unawaited(h.binding.refresh());
    });
    addTearDown(subscription.cancel);
    final good = h.binding.refresh();
    await h.waitForReady(count: 2);
    await h.reply(h.requests.last, {
      'ready': true,
      'hostInstanceId': 'synthetic-host',
      'hostCapabilities': [...baseCapabilities, ...dynamicCapabilities],
    });
    await good;
    await h.waitForReady(count: 3);
    await h.reply(h.requests.last, {
      'ready': true,
      'hostInstanceId': 'synthetic-host',
      'hostCapabilities': [...baseCapabilities, ...dynamicCapabilities],
    });
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1);
    expect(h.requests, hasLength(3));
  });
  test(
    'wrong instance, malformed or duplicate optional capabilities are rejected',
    () {
      for (final payload in <Map<String, Object?>>[
        {
          'ready': true,
          'hostInstanceId': 'other',
          'hostCapabilities': baseCapabilities,
        },
        {
          'ready': true,
          'hostInstanceId': 'synthetic-host',
          'hostCapabilities': [42],
        },
        {
          'ready': true,
          'hostInstanceId': 'synthetic-host',
          'hostCapabilities': [...baseCapabilities, 'account.read'],
        },
        {
          'ready': true,
          'hostInstanceId': 'synthetic-host',
          'hostCapabilities': ['host.lifecycle'],
        },
      ]) {
        final reply = BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: 'host.ready',
          sessionGeneration: 1,
          payload: payload,
          status: 'ok',
        );
        expect(
          () => HostCapabilityRefresh.validateReady(
            reply,
            'synthetic-host',
            baseCapabilities,
          ),
          throwsA(isA<NativeHostConnectionException>()),
        );
      }
    },
  );
}

final class CapabilityHarness {
  CapabilityHarness() {
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 1)
      ..acceptHostCapabilities(baseCapabilities);
    host = pair.host.incoming.listen((request) {
      if (request.name == 'host.ready') requests.add(request);
    });
    binding = HostCapabilityRefresh(
      session,
      'synthetic-host',
      baseCapabilities,
    );
  }
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final HostCapabilityRefresh binding;
  late final StreamSubscription<BridgeEnvelope> host;
  final requests = <BridgeEnvelope>[];
  Future<void> waitForReady({int count = 1}) async {
    for (var i = 0; i < 50 && requests.length < count; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(requests.length, greaterThanOrEqualTo(count));
  }

  Future<void> reply(BridgeEnvelope request, Map<String, Object?> payload) =>
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          payload: payload,
          status: 'ok',
        ),
      );
  Future<void> close() async {
    await binding.close();
    await host.cancel();
    await session.close();
    await pair.host.close();
  }
}
