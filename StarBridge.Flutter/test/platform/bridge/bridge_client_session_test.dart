import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test(
    'shared account timeout fails every consumer and permits a fresh retry',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
        requestTimeout: const Duration(milliseconds: 50),
      );
      final requests = <BridgeEnvelope>[];
      final subscription = pair.host.incoming.listen(requests.add);
      final first = session.request(
        'account.getCurrent',
        payload: {'schemaVersion': 1},
      );
      final second = session.request(
        'account.getCurrent',
        payload: {'schemaVersion': 1},
      );
      await Future.wait([
        expectLater(first, throwsA(isA<BridgeTimeoutException>())),
        expectLater(second, throwsA(isA<BridgeTimeoutException>())),
      ]);
      expect(requests.where((r) => r.name == 'account.getCurrent').length, 1);
      final retry = session.request(
        'account.getCurrent',
        payload: {'schemaVersion': 1},
      );
      await _waitFor(
        () => requests.where((r) => r.name == 'account.getCurrent').length == 2,
      );
      await pair.host.send(
        _ok(requests.lastWhere((r) => r.name == 'account.getCurrent'), {
          'schemaVersion': 1,
        }),
      );
      await retry;
      await subscription.cancel();
      await session.close();
      await pair.host.close();
    },
  );
  test('shared account read cancellation belongs to each consumer', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    final requests = <BridgeEnvelope>[];
    final subscription = pair.host.incoming.listen(requests.add);
    final first = session.beginRequest(
      'account.getCurrent',
      payload: {'schemaVersion': 1},
    );
    final second = session.beginRequest(
      'account.getCurrent',
      payload: {'schemaVersion': 1},
    );
    final cancelled = expectLater(
      first.future,
      throwsA(isA<BridgeCancelledException>()),
    );
    await _waitFor(() => requests.isNotEmpty);
    await first.cancel();
    await cancelled;
    expect(requests.where((r) => r.name == 'bridge.cancel'), isEmpty);
    await pair.host.send(_ok(requests.first, {'schemaVersion': 1}));
    await second.future;
    final last = session.beginRequest(
      'account.getCurrent',
      payload: {'schemaVersion': 1},
    );
    final lastCancelled = expectLater(
      last.future,
      throwsA(isA<BridgeCancelledException>()),
    );
    await last.cancel();
    await lastCancelled;
    await _waitFor(() => requests.any((r) => r.name == 'bridge.cancel'));
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  });

  test('shared account snapshots are discarded on generation change', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    final requests = <BridgeEnvelope>[];
    final subscription = pair.host.incoming.listen(requests.add);
    final old = List.generate(
      3,
      (_) =>
          session.request('account.getCurrent', payload: {'schemaVersion': 1}),
    );
    final stale = old
        .map(
          (f) => expectLater(f, throwsA(isA<BridgeStaleGenerationException>())),
        )
        .toList();
    await _waitFor(() => requests.length == 1);
    session.advanceGeneration(2);
    await Future.wait(stale);
    final current = session.request(
      'account.getCurrent',
      payload: {'schemaVersion': 1},
    );
    await _waitFor(() => requests.length == 2);
    await pair.host.send(_ok(requests.first, {'owner': 'old'}));
    await pair.host.send(_ok(requests.last, {'owner': 'new'}));
    expect((await current).payload['owner'], 'new');
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  });

  test(
    'account operation separates earlier and later shared snapshots',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      );
      final requests = <BridgeEnvelope>[];
      final subscription = pair.host.incoming.listen(requests.add);
      final first = session.request(
        'account.getCurrent',
        payload: {'schemaVersion': 1},
      );
      final login = session.request(
        'account.login',
        payload: {'schemaVersion': 1},
      );
      final second = session.request(
        'account.getCurrent',
        payload: {'schemaVersion': 1},
      );
      await _waitFor(() => requests.length == 3);
      for (final request in requests) {
        await pair.host.send(_ok(request, {'schemaVersion': 1}));
      }
      await Future.wait([first, login, second]);
      await subscription.cancel();
      await session.close();
      await pair.host.close();
    },
  );
  test('concurrent account snapshots share one read but never cache completed data', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    final requests = <BridgeEnvelope>[];
    final subscription = pair.host.incoming.listen(requests.add);
    final reads = List.generate(
      12,
      (_) =>
          session.request('account.getCurrent', payload: {'schemaVersion': 1}),
    );
    final all = Future.wait(reads)..ignore();
    try {
      await _waitFor(() => requests.isNotEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(
        requests.length,
        1,
        reason: 'Parallel page initialization must not queue 12 identical account reads',
      );
      await pair.host.send(_ok(requests.single, {'schemaVersion': 1}));
      expect((await all).length, 12);
      final next = session.request(
        'account.getCurrent',
        payload: {'schemaVersion': 1},
      );
      await _waitFor(() => requests.length == 2);
      await pair.host.send(_ok(requests.last, {'schemaVersion': 1}));
      await next;
    } finally {
      await subscription.cancel();
      await session.close();
      await pair.host.close();
    }
  });
  for (final name in const [
    'applicationUpdates.firstFrameReady',
    'applicationUpdates.prepare',
    'applicationUpdates.handoff',
  ]) {
    test('$name reaches Host without account context', () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      );
      final subscription = pair.host.incoming.listen((request) {
        expect(request.accountContext, isNull);
        unawaited(pair.host.send(_ok(request, {'schemaVersion': 1})));
      });
      try {
        final reply = await session.request(
          name,
          payload: {'schemaVersion': 1},
        );
        expect(reply.payload['schemaVersion'], 1);
      } finally {
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      }
    });
  }

  test('matches out-of-order responses by correlation ID', () async {
    final pair = InMemoryBridgeConnection.createPair();
    var nextId = 0;
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 3,
      correlationIdFactory: () => 'c${nextId++}',
    );
    final requests = <BridgeEnvelope>[];
    final hostSubscription = pair.host.incoming.listen(requests.add);

    final first = session.request('account.getCurrent');
    final second = session.request('account.getCurrent');
    await _waitFor(() => requests.length == 2);
    await pair.host.send(_ok(requests[1], {'order': 2}));
    await pair.host.send(_ok(requests[0], {'order': 1}));

    expect((await first).payload['order'], 1);
    expect((await second).payload['order'], 2);
    await hostSubscription.cancel();
    await session.close();
    await pair.host.close();
  });

  test(
    'generation advance fails pending request and drops late response',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 4,
        correlationIdFactory: () => 'pending',
      );
      final requestFuture = pair.host.incoming.first;
      final pending = session.request('account.getCurrent');
      final request = await requestFuture;

      session.advanceGeneration(5);
      await expectLater(
        pending,
        throwsA(isA<BridgeStaleGenerationException>()),
      );
      await pair.host.send(_ok(request, {'stale': true}));
      expect(session.activeGeneration, 5);
      await session.close();
      await pair.host.close();
    },
  );

  test('account changed advances generation before publishing event', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    final eventFuture = session.events.first;
    await pair.host.send(
      const BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'account.changed',
        sessionGeneration: 2,
        sequence: 0,
        payload: {},
      ),
    );

    expect((await eventFuture).sessionGeneration, 2);
    expect(session.activeGeneration, 2);
    await session.close();
    await pair.host.close();
  });

  test('cancellation restores caller and sends best-effort cancel', () async {
    final pair = InMemoryBridgeConnection.createPair();
    var nextId = 0;
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 0,
      correlationIdFactory: () => 'c${nextId++}',
    );
    final requests = <BridgeEnvelope>[];
    final hostSubscription = pair.host.incoming.listen(requests.add);
    final operation = session.beginRequest('account.login');
    await _waitFor(() => requests.isNotEmpty);

    final cancelled = expectLater(
      operation.future,
      throwsA(isA<BridgeCancelledException>()),
    );
    await operation.cancel();
    await cancelled;
    await _waitFor(() => requests.length == 2);
    expect(requests.last.name, 'bridge.cancel');
    expect(requests.last.payload['targetCorrelationId'], 'c0');
    await hostSubscription.cancel();
    await session.close();
    await pair.host.close();
  });

  test(
    'account-sensitive request fails before transport without context',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 0,
      );

      expect(
        () => session.request('profile.getSelf'),
        throwsA(isA<BridgeAccountContextRequiredException>()),
      );
      await session.close();
      await pair.host.close();
    },
  );

  test('timeout is typed and emits cancellation', () async {
    final pair = InMemoryBridgeConnection.createPair();
    var nextId = 0;
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 0,
      requestTimeout: const Duration(milliseconds: 10),
      correlationIdFactory: () => 't${nextId++}',
    );
    final requests = <BridgeEnvelope>[];
    final hostSubscription = pair.host.incoming.listen(requests.add);

    await expectLater(
      session.request('account.getCurrent'),
      throwsA(isA<BridgeTimeoutException>()),
    );
    await _waitFor(() => requests.length == 2);
    expect(requests.last.name, 'bridge.cancel');
    await hostSubscription.cancel();
    await session.close();
    await pair.host.close();
  });
}

BridgeEnvelope _ok(BridgeEnvelope request, Map<String, Object?> payload) {
  return BridgeEnvelope(
    protocolVersion: 1,
    messageType: 'response',
    name: request.name,
    correlationId: request.correlationId,
    sessionGeneration: request.sessionGeneration,
    payload: payload,
    status: 'ok',
  );
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not reached.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
