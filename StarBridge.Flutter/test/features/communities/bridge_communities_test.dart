import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/bridge_communities.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  testWidgets(
    'admission timeout remains finite and never retries the mutation',
    (tester) async {
      final host = CommunityHarness(
        legacy: true,
        holdNames: {'communities.execute'},
      );
      addTearDown(host.close);
      String? result;
      final sending = host.adapter
          .execute('join', 'a' * 32)
          .then((value) => result = value);
      await tester.pump();
      await tester.pump(const Duration(seconds: 46));
      await sending;
      expect(result, 'unknown');
      expect(
        host.requests.where((r) => r.name == 'communities.execute').length,
        1,
      );
    },
  );
  testWidgets(
    'admission waits for bounded multi-request confirmation without replay',
    (tester) async {
      final host = CommunityHarness(
        legacy: true,
        holdNames: {'communities.execute'},
      );
      addTearDown(host.close);
      String? result;
      final sending = host.adapter
          .execute('join', 'a' * 32)
          .then((value) => result = value);
      await tester.pump();
      expect(
        host.requests.where((r) => r.name == 'communities.execute').length,
        1,
      );
      await tester.pump(const Duration(seconds: 20));
      expect(
        result,
        isNull,
        reason: 'The general 15s bridge deadline must not cancel membership confirmation',
      );
      await host.reply(
        host.requests.firstWhere((r) => r.name == 'communities.execute'),
      );
      await tester.pump();
      await sending;
      expect(result, 'accepted');
      expect(
        host.requests.where((r) => r.name == 'communities.execute').length,
        1,
      );
    },
  );
  test('local hangar changes request soft refresh without clearing the organization', () async {
    final host = CommunityHarness();
    addTearDown(host.close);
    var invalidations = 0;
    final subscription = host.adapter.invalidations.listen(
      (_) => invalidations++,
    );
    addTearDown(subscription.cancel);
    final refreshed = host.adapter.shipRefreshes.first;
    await host.connection.send(
      const BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'hangarReader.changed',
        sessionGeneration: 4,
        sequence: 1,
        payload: {'schemaVersion': 1},
      ),
    );
    await refreshed.timeout(const Duration(seconds: 1));
    expect(invalidations, 0);
    expect(host.session.activeGeneration, 4);
  });
  test('Expired S2 directory cursor retains the refresh instruction', () async {
    final host = CommunityHarness(
      legacy: true,
      error: 'communities.refreshRequired',
    );
    addTearDown(host.close);
    await expectLater(
      host.adapter.read(view: 'discover', query: '', after: 'a' * 32),
      throwsA(
        isA<CommunityFailure>().having(
          (e) => e.code,
          'code',
          'refreshRequired',
        ),
      ),
    );
  });
  test('S2 legacy account reads joined organizations without SCM', () async {
    final host = CommunityHarness(legacy: true);
    addTearDown(host.close);
    final page = await host.adapter.read(view: 'mine', query: '');
    expect(page.items, isEmpty);
    expect(host.requests.map((r) => r.name), [
      'account.getCurrent',
      'communities.read',
    ]);
    expect(
      host.requests.last.accountContext?.authority,
      'starbridge-relay-test',
    );
    expect(await host.adapter.execute('join', 'a' * 32), 'accepted');
  });
  test('Missing capability never reads account or sends a command', () async {
    final host = CommunityHarness(capabilities: []);
    addTearDown(host.close);
    await expectLater(
      host.adapter.read(view: 'mine', query: ''),
      throwsA(isA<CommunityFailure>()),
    );
    expect(await host.adapter.execute('join', 'a' * 32), 'unknown');
    expect(host.requests, isEmpty);
  });
  test('Directory carries current account and bounded query only', () async {
    final host = CommunityHarness();
    addTearDown(host.close);
    final page = await host.adapter.read(view: 'discover', query: '探索');
    expect(page.items, isEmpty);
    expect(host.requests.map((r) => r.name), [
      'account.getCurrent',
      'communities.read',
    ]);
    expect(host.requests.last.accountContext?.subject, 'test-subject');
    expect(host.requests.last.sessionGeneration, 4);
    expect(host.requests.last.payload, {
      'schemaVersion': 1,
      'view': 'discover',
      'query': '探索',
    });
  });
  test('Membership command sends an opaque target exactly once', () async {
    final host = CommunityHarness();
    addTearDown(host.close);
    expect(await host.adapter.execute('join', 'a' * 32), 'accepted');
    expect(host.requests.map((r) => r.name), [
      'account.getCurrent',
      'communities.execute',
    ]);
    expect(host.requests.last.payload, {
      'schemaVersion': 1,
      'action': 'join',
      'targetRef': 'a' * 32,
    });
  });
  test(
    'Old service failure does not fall back to old bulk reads or mutations',
    () async {
      final host = CommunityHarness(error: 'communities.upgradeRequired');
      addTearDown(host.close);
      await expectLater(
        host.adapter.read(view: 'mine', query: ''),
        throwsA(
          isA<CommunityFailure>().having(
            (e) => e.code,
            'code',
            'upgradeRequired',
          ),
        ),
      );
      expect(host.requests.map((r) => r.name), [
        'account.getCurrent',
        'communities.read',
      ]);
    },
  );
  test(
    'Account change cancels a pending directory and rejects its late response',
    () async {
      final host = CommunityHarness(holdRead: true);
      addTearDown(host.close);
      final read = host.adapter.read(view: 'mine', query: '');
      final rejected = expectLater(read, throwsA(isA<CommunityFailure>()));
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
      await rejected;
      await host.reply(
        host.requests.firstWhere((r) => r.name == 'communities.read'),
      );
      expect(host.session.activeGeneration, 5);
    },
  );
}

class CommunityHarness {
  CommunityHarness({
    this.legacy = false,
    this.error,
    this.holdRead = false,
    this.holdNames = const {},
    this.responses = const {},
    List<String> capabilities = const [
      'communities.read',
      'communities.commands',
    ],
  }) {
    final pair = InMemoryBridgeConnection.createPair();
    connection = pair.host;
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
    );
    session.acceptHostCapabilities(capabilities);
    adapter = BridgeCommunities(session);
    subscription = connection.incoming.listen((request) {
      requests.add(request);
      if (request.name == 'bridge.cancel') return;
      if (request.name == 'communities.read' ||
          holdNames.contains(request.name)) {
        if (!readArrived.isCompleted) readArrived.complete();
        if (holdRead || holdNames.contains(request.name)) return;
      }
      unawaited(reply(request));
    });
  }
  final String? error;
  final bool legacy;
  final bool holdRead;
  final Set<String> holdNames;
  final Map<String, Map<String, Object?>> responses;
  late final BridgeConnection connection;
  late final BridgeClientSession session;
  late final BridgeCommunities adapter;
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
        accountContext: BridgeAccountContext(
          environment: 'test',
          authority: legacy ? 'starbridge-relay-test' : 'scm-test',
          subject: 'test-subject',
        ),
        status: failed ? 'error' : 'ok',
        error: failed
            ? BridgeErrorBody(
                code: error!,
                message: 'private upstream detail',
                retryable: false,
              )
            : null,
        payload: account
            ? {
                'schemaVersion': 1,
                'state': legacy ? 'legacySignedIn' : 'signedIn',
              }
            : responses[request.name] ??
                  (request.name == 'communities.execute'
                      ? {'schemaVersion': 1, 'status': 'accepted'}
                      : {
                          'schemaVersion': 1,
                          'view': request.payload['view'],
                          'query': request.payload['query'],
                          'items': [],
                          'next': null,
                        }),
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
