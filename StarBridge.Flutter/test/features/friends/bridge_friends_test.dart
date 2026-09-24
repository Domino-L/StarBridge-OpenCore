import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/friends/bridge_friends_adapter.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test(
    'unsupported Host fails closed without requesting account data',
    () async {
      final host = Harness(capabilities: []);
      addTearDown(host.close);
      expect((await host.adapter.read()).failure, 'hostUnavailable');
      expect(host.requests, isEmpty);
    },
  );
  test('command capability is independent from reads', () async {
    final host = Harness();
    addTearDown(host.close);
    expect(
      (await host.adapter.execute('remove', '0' * 32)).error,
      'hostUnavailable',
    );
    expect(host.requests, isEmpty);
  });
  test('command forwards only action and opaque target and requires acknowledged directory', () async {
    final host = Harness(
      capabilities: ['friends.read', 'friends.commands'],
      commandPayload: {
        'schemaVersion': 1,
        'status': 'accepted',
        'directory': {
          'schemaVersion': 1,
          'friends': [],
          'incoming': [],
          'outgoing': [],
          'blocked': [],
          'results': [],
          'refreshedAt': '2026-09-06T12:00:00Z',
        },
      },
    );
    addTearDown(host.close);
    final result = await host.adapter.execute('remove', '0' * 32);
    expect(result.status, 'accepted');
    expect(result.directory, isNotNull);
    expect(host.requests.map((r) => r.name), [
      'account.getCurrent',
      'friends.execute',
    ]);
    expect(host.requests.last.payload, {
      'schemaVersion': 1,
      'action': 'remove',
      'targetRef': '0' * 32,
    });
    expect(host.requests.last.accountContext?.subject, 'test-subject');
  });
  test(
    'malformed command success is uncertain and never automatically retried',
    () async {
      final host = Harness(
        capabilities: ['friends.commands'],
        commandPayload: {'schemaVersion': 1, 'status': 'accepted'},
      );
      addTearDown(host.close);
      expect(
        (await host.adapter.execute('remove', '0' * 32)).error,
        'outcomeUnknown',
      );
      expect(
        host.requests.where((r) => r.name == 'friends.execute'),
        hasLength(1),
      );
    },
  );
  test('command rejection stays distinct from a transport failure', () async {
    final host = Harness(
      capabilities: ['friends.commands'],
      commandPayload: {
        'schemaVersion': 1,
        'status': 'rejected',
        'error': 'cooldown',
      },
    );
    addTearDown(host.close);
    final result = await host.adapter.execute('send', '0' * 32);
    expect(result.status, 'rejected');
    expect(result.error, 'cooldown');
  });
  test('signed-out account cannot dispatch a directory read', () async {
    final host = Harness(signedIn: false);
    addTearDown(host.close);
    expect((await host.adapter.read()).state, FriendsReadState.signedOut);
    expect(host.requests.map((r) => r.name), ['account.getCurrent']);
  });
  for (final query in [null, '呼号']) {
    test(
      'read carries current account context and no privacy override ($query)',
      () async {
        final host = Harness();
        addTearDown(host.close);
        expect(
          (await host.adapter.read(query: query)).state,
          FriendsReadState.ready,
        );
        expect(host.requests.map((r) => r.name), [
          'account.getCurrent',
          'friends.read',
        ]);
        expect(host.requests.last.accountContext?.subject, 'test-subject');
        expect(host.requests.last.sessionGeneration, 4);
        expect(host.requests.last.payload, {
          'schemaVersion': 1,
          'query': ?query,
        });
      },
    );
  }
  for (final entry in {
    'friends.identity_unavailable': 'identityUnavailable',
    'friends.forbidden': 'forbidden',
    'friends.data_invalid': 'invalidResponse',
    'friends.read_unavailable': 'unavailable',
  }.entries) {
    test(
      '${entry.key} stays bounded and does not logout, migrate or retry',
      () async {
        final host = Harness(error: entry.key);
        addTearDown(host.close);
        final result = await host.adapter.read();
        expect(result.failure, entry.value);
        expect(result.snapshot, isNull);
        expect(host.requests.map((r) => r.name), [
          'account.getCurrent',
          'friends.read',
        ]);
      },
    );
  }
  test('account change cancels pending reads and rejects previous generation responses', () async {
    final host = Harness(holdRead: true);
    addTearDown(host.close);
    final read = host.adapter.read();
    await host.readArrived.future;
    final invalidated = host.adapter.invalidations.first;
    await host.connection.send(
      const BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'account.changed',
        sessionGeneration: 5,
        sequence: 1,
        payload: {'schemaVersion': 1},
      ),
    );
    await invalidated.timeout(const Duration(seconds: 1));
    final result = await read.timeout(const Duration(seconds: 1));
    expect(result.snapshot, isNull);
    await host.reply(host.requests.firstWhere((r) => r.name == 'friends.read'));
    expect(host.session.activeGeneration, 5);
  });
}

class Harness {
  Harness({
    this.signedIn = true,
    this.error,
    this.holdRead = false,
    this.commandPayload,
    List<String> capabilities = const ['friends.read'],
  }) {
    final pair = InMemoryBridgeConnection.createPair();
    connection = pair.host;
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
    );
    session.acceptHostCapabilities(capabilities);
    adapter = BridgeFriendsAdapter(session);
    subscription = connection.incoming.listen((request) {
      requests.add(request);
      if (request.name == 'bridge.cancel') return;
      if (request.name == 'friends.read') {
        if (!readArrived.isCompleted) readArrived.complete();
        if (holdRead) return;
      }
      unawaited(reply(request));
    });
  }
  final bool signedIn, holdRead;
  final String? error;
  final Map<String, Object?>? commandPayload;
  late final BridgeConnection connection;
  late final BridgeClientSession session;
  late final BridgeFriendsAdapter adapter;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  final readArrived = Completer<void>();
  Future<void> reply(BridgeEnvelope request) {
    final account = request.name == 'account.getCurrent';
    final failed = !account && error != null;
    return connection.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        accountContext: signedIn
            ? const BridgeAccountContext(
                environment: 'test',
                authority: 'scm-test',
                subject: 'test-subject',
              )
            : null,
        status: failed ? 'error' : 'ok',
        error: failed
            ? BridgeErrorBody(
                code: error!,
                message: 'private upstream detail',
                retryable: false,
              )
            : null,
        payload: account
            ? {'schemaVersion': 1, 'state': signedIn ? 'signedIn' : 'signedOut'}
            : request.name == 'friends.execute' && commandPayload != null
            ? commandPayload!
            : {
                'schemaVersion': 1,
                'query': request.payload['query'],
                'refreshedAt': '2026-09-06T12:00:00Z',
                'friends': [],
                'incoming': [],
                'outgoing': [],
                'blocked': [],
                'results': [],
              },
      ),
    );
  }

  Future<void> close() async {
    await adapter.close();
    await subscription.cancel();
    await session.close();
    await connection.close();
  }
}
