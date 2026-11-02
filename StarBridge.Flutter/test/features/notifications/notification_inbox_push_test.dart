import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_controller.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

class _Fixture {
  _Fixture() {
    session.acceptHostCapabilities(['notificationInbox.read']);
    host = pair.host.incoming.listen((request) {
      if (request.name == 'notificationInbox.read') {
        reads++;
        requests.add(request.payload);
        if (hold) {
          pending = request;
          return;
        }
      }
      unawaited(answer(request));
    });
  }
  static const owner = BridgeAccountContext(
    environment: 'fixture',
    authority: 'starbridge-relay-test',
    subject: 'fixture',
  );
  final pair = InMemoryBridgeConnection.createPair();
  late final session = BridgeClientSession(
    connection: pair.client,
    sessionGeneration: 1,
  );
  late final controller = NotificationInboxController(session);
  late final StreamSubscription<BridgeEnvelope> host;
  int reads = 0, sequence = 0;
  bool hold = false, read = false;
  bool? healthy = true;
  final requests = <Map<String, Object?>>[];
  BridgeEnvelope? pending;
  Future<void> answer(BridgeEnvelope request) => pair.host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: request.name,
      correlationId: request.correlationId,
      sessionGeneration: 1,
      accountContext: owner,
      status: 'ok',
      payload: request.name == 'account.getCurrent'
          ? {'schemaVersion': 1, 'state': 'legacySignedIn'}
          : {
              'schemaVersion': 1,
              if (healthy != null) 'scmPushHealthy': healthy,
              'unreadCount': read ? 0 : 1,
              'items': [
                {
                  'reference': 'a' * 32,
                  'category': 'trade',
                  'priority': 'normal',
                  'title': 'Shipped',
                  'body': 'Fixture',
                  'createdAt': '2026-10-29T00:00:00Z',
                  'read': read,
                  'isAvailable': true,
                  'actionTarget': 'marketplace_trade',
                  'actionLabel': '',
                },
              ],
            },
    ),
  );
  Future<void> push({
    bool healthy = true,
    Map<String, Object?>? payload,
    int generation = 1,
  }) => pair.host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'event',
      name: 'notificationInbox.changed',
      sessionGeneration: generation,
      sequence: ++sequence,
      payload: payload ?? {'schemaVersion': 1, 'scmPushHealthy': healthy},
    ),
  );
  bool _controllerDisposed = false;
  // Synchronous: cancels the periodic timer before the pending-timer check.
  void disposeController() {
    if (_controllerDisposed) return;
    _controllerDisposed = true;
    controller.dispose();
  }

  Future<void>? _closing;
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    disposeController();
    await host.cancel();
    await session.close();
    await pair.host.close();
  }
}

void main() {
  testWidgets('late healthy response cannot undo a disconnect cache bypass', (
    tester,
  ) async {
    final f = _Fixture();
    addTearDown(f.close);
    expect(await f.controller.refresh(), isTrue);
    f.hold = true;
    await f.push();
    await tester.pump();
    expect(f.requests.last, {'schemaVersion': 1, 'allowScmCache': true});
    await f.push(healthy: false);
    await tester.pump();
    f.hold = false;
    await f.answer(f.pending!);
    await tester.pump();
    expect(f.reads, 3);
    expect(f.requests.last, {'schemaVersion': 1});
  });

  testWidgets('healthy new Host permits only automatic cache requests', (
    tester,
  ) async {
    final f = _Fixture();
    addTearDown(f.close);
    expect(await f.controller.refresh(), isTrue);
    expect(f.requests.single, {'schemaVersion': 1});
    await f.push();
    await tester.pump();
    expect(f.requests.last, {'schemaVersion': 1, 'allowScmCache': true});
    expect(await f.controller.refresh(), isTrue);
    expect(f.requests.last, {'schemaVersion': 1});
    expect(await f.controller.refresh(quiet: true), isTrue);
    expect(f.requests.last, {'schemaVersion': 1});
    f.healthy = false;
    await f.push(healthy: false);
    await tester.pump();
    expect(f.requests.last, {'schemaVersion': 1});
    await f.push(healthy: false);
    await tester.pump();
    expect(f.requests.last, {'schemaVersion': 1});
  });

  testWidgets('old Host without health never receives cache permission', (
    tester,
  ) async {
    final f = _Fixture()..healthy = null;
    addTearDown(f.close);
    try {
      f.controller.start();
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));
      expect(f.reads, 2);
      expect(await f.controller.refresh(), isTrue);
      expect(f.requests, everyElement({'schemaVersion': 1}));
    } finally {
      f.disposeController();
    }
  });

  testWidgets('unhealthy new Host automatic poll bypasses cache', (
    tester,
  ) async {
    final f = _Fixture()..healthy = false;
    addTearDown(f.close);
    try {
      f.controller.start();
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));
      expect(f.reads, 2);
      expect(f.requests, everyElement({'schemaVersion': 1}));
      f.healthy = true;
      await tester.pump(const Duration(seconds: 60));
      expect(f.requests.last, {'schemaVersion': 1});
      await tester.pump(const Duration(seconds: 60));
      expect(f.requests.last, {'schemaVersion': 1, 'allowScmCache': true});
    } finally {
      f.disposeController();
    }
  });

  testWidgets(
    'push wakes existing reader and coalesces arrivals during readback',
    (tester) async {
      final f = _Fixture();
      addTearDown(f.close);
      expect(await f.controller.refresh(), isTrue);
      expect(f.reads, 1);
      f.hold = true;
      await f.push();
      await tester.pump();
      expect(f.reads, 2);
      expect(
        f.controller.unread.value,
        1,
        reason: 'push counts never optimistically clear authoritative unread',
      );
      await f.push();
      await f.push();
      await tester.pump();
      expect(f.reads, 2);
      f.hold = false;
      f.read = true;
      await f.answer(f.pending!);
      await tester.pump();
      expect(
        f.reads,
        3,
        reason: 'one trailing read reconciles all signals received while busy',
      );
      expect(f.controller.unread.value, 0);
      expect(f.controller.items.single.read, isTrue);
    },
  );

  testWidgets('unknown payloads and stale generations do not wake inbox', (
    tester,
  ) async {
    final f = _Fixture();
    addTearDown(f.close);
    expect(await f.controller.refresh(), isTrue);
    await f.push(payload: const {});
    await f.push(payload: const {'schemaVersion': 2, 'scmPushHealthy': true});
    await f.push(payload: const {'schemaVersion': 1, 'scmPushHealthy': null});
    await f.push(
      payload: const {
        'schemaVersion': 1,
        'scmPushHealthy': true,
        'raw': 'ignored',
      },
    );
    await f.push(generation: 0);
    await tester.pump();
    expect(f.reads, 1);
    await f.push(healthy: false);
    await tester.pump();
    expect(
      f.reads,
      2,
      reason: 'disconnect reconciles via the same REST reader',
    );
  });

  testWidgets(
    'Relay retains 60-second polling even when SCM source is healthy',
    (tester) async {
      final f = _Fixture();
      addTearDown(f.close);
      // The periodic Relay timer must be cancelled inside the test body:
      // addTearDown runs after the pending-timer invariant check.
      try {
        f.controller.start();
        await tester.pump();
        expect(f.reads, 1);
        await tester.pump(const Duration(seconds: 59));
        expect(f.reads, 1);
        await tester.pump(const Duration(seconds: 1));
        expect(
          f.reads,
          2,
          reason: 'Host alone applies the five-minute healthy SCM page cache',
        );
        await f.push(healthy: false);
        await tester.pump();
        expect(f.reads, 3);
        await tester.pump(const Duration(seconds: 60));
        expect(f.reads, 4);
      } finally {
        f.disposeController();
      }
    },
  );
}
