import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/friends/bridge_friends_adapter.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

const _prefix = String.fromEnvironment('STARBRIDGE_FRIENDS_PAGING_WIRE_PREFIX');

void main() {
  test(
    'two real friend adapters share one Native directory and every page',
    () async {
      final wire = Map<String, Object?>.from(
        jsonDecode(File('$_prefix-fresh.json').readAsStringSync()) as Map,
      );
      final host = _DirectoryWire(wire);
      addTearDown(host.close);
      final first = BridgeFriendsAdapter(host.session);
      final second = BridgeFriendsAdapter(host.session);
      addTearDown(first.close);
      addTearDown(second.close);
      final reads = [first.read(), second.read()];
      await _until(() => host.held.isNotEmpty);
      await _turns();
      final initialCount = host.requests
          .where((r) => r.name == 'friends.read')
          .length;
      await host.release();
      final results = await Future.wait(reads)
          .timeout(const Duration(seconds: 5));
      expect(results.map((r) => r.state), everyElement(FriendsReadState.ready));
      for (final result in results) {
        final rows = result.snapshot!.groups[FriendsSection.incoming]!;
        expect(rows, hasLength(1400));
        expect(rows.map((r) => r.callsign).toSet(), hasLength(1400));
      }
      expect(
        initialCount,
        1,
        reason: 'same pending business GET, not just shared account root',
      );
      expect(
        host.requests.where((r) => r.name == 'friends.readPage'),
        hasLength(13),
      );
      expect(
        results[0].snapshot!.groups[FriendsSection.incoming]!.first.targetRef,
        results[1].snapshot!.groups[FriendsSection.incoming]!.first.targetRef,
      );
      expect(host.requests.where((r) => r.name == 'friends.execute'), isEmpty);
    },
    skip: _prefix.isEmpty ? 'Requires actual Native paging capture' : false,
  );

  test(
    'closing one real adapter keeps the other directory transfer alive',
    () async {
      final host = _DirectoryWire(_capture('fresh'));
      addTearDown(host.close);
      final first = BridgeFriendsAdapter(host.session),
          second = BridgeFriendsAdapter(host.session);
      addTearDown(second.close);
      final firstRead = first.read(), secondRead = second.read();
      await _until(() => host.held.isNotEmpty);
      await _turns();
      await first.close();
      final retired = await firstRead;
      expect(retired.state, FriendsReadState.idle);
      await host.release();
      expect(
        (await secondRead).snapshot!.groups[FriendsSection.incoming],
        hasLength(1400),
      );
      expect(
        host.requests.where((r) => r.name == 'friends.read'),
        hasLength(1),
      );
      expect(host.requests.where((r) => r.name == 'bridge.cancel'), isEmpty);
    },
    skip: _prefix.isEmpty ? 'Requires actual Native paging capture' : false,
  );

  test(
    'completed directories are never reused as the next authenticated read',
    () async {
      final host = _DirectoryWire(_capture('fresh'));
      addTearDown(host.close);
      final adapter = BridgeFriendsAdapter(host.session);
      addTearDown(adapter.close);
      final first = adapter.read();
      await _until(() => host.held.isNotEmpty);
      await host.release();
      expect((await first).state, FriendsReadState.ready);
      final second = adapter.read();
      await _until(() => host.held.isNotEmpty);
      await host.release();
      expect((await second).state, FriendsReadState.ready);
      expect(
        host.requests.where((r) => r.name == 'friends.read'),
        hasLength(2),
      );
      expect(
        host.requests.where((r) => r.name == 'account.getCurrent'),
        hasLength(2),
      );
    },
    skip: _prefix.isEmpty ? 'Requires actual Native paging capture' : false,
  );

  test('independent friend deadlines keep the longer consumer alive', () async {
    final host = _DirectoryWire(_capture('fresh'));
    addTearDown(host.close);
    final short = host.session.beginRequest(
      'friends.read',
      accountContext: host.root.accountContext,
      payload: _directory,
      timeout: const Duration(milliseconds: 30),
    );
    final longer = host.session.beginRequest(
      'friends.read',
      accountContext: host.root.accountContext,
      payload: _directory,
      timeout: const Duration(seconds: 2),
    );
    await expectLater(
      short.future,
      throwsA(
        isA<BridgeTimeoutException>().having(
          (e) => e.requestName,
          'requestName',
          'friends.read',
        ),
      ),
    );
    expect(host.held, hasLength(1));
    expect(host.requests.where((r) => r.name == 'bridge.cancel'), isEmpty);
    await host.release();
    expect((await longer.future).status, 'ok');
  }, skip: _prefix.isEmpty ? 'Requires actual Native paging capture' : false);

  test(
    'last consumer cancels once and a new caller starts a fresh transport',
    () async {
      final host = _DirectoryWire(_capture('fresh'));
      addTearDown(host.close);
      final a = host.read(), b = host.read();
      final errors = Future.wait([
        expectLater(a.future, throwsA(isA<BridgeCancelledException>())),
        expectLater(b.future, throwsA(isA<BridgeCancelledException>())),
      ]);
      await a.cancel();
      await b.cancel();
      await errors;
      final c = host.read();
      await _turns();
      expect(
        host.requests.where((r) => r.name == 'friends.read'),
        hasLength(2),
      );
      expect(
        host.requests.where((r) => r.name == 'bridge.cancel'),
        hasLength(1),
      );
      await host.release();
      expect((await c.future).status, 'ok');
    },
    skip: _prefix.isEmpty ? 'Requires actual Native paging capture' : false,
  );

  for (final change in ['generation', 'mode', 'event', 'write']) {
    test('$change fences later friend readers from older transports', () async {
      final host = _DirectoryWire(_capture('fresh'));
      addTearDown(host.close);
      final before = host.read();
      Future<void>? oldError;
      BridgeRequestOperation? write;
      if (change == 'generation') {
        oldError = expectLater(
          before.future,
          throwsA(isA<BridgeStaleGenerationException>()),
        );
        host.session.advanceGeneration(host.session.activeGeneration + 1);
      } else if (change == 'mode') {
        await host.session.runConnectionModeChange(() async {});
      } else if (change == 'event') {
        await host.pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'event',
            name: 'bootstrap.invalidated',
            sessionGeneration: host.session.activeGeneration,
            sequence: 1,
            payload: const {'schemaVersion': 1},
          ),
        );
        await _turns();
      } else {
        write = host.session.beginRequest(
          'friends.execute',
          accountContext: host.root.accountContext,
          payload: const {
            'schemaVersion': 1,
            'action': 'reject',
            'targetRef': '00000000000000000000000000000000',
          },
        );
      }
      final after = host.read();
      await _turns();
      expect(
        host.requests.where((r) => r.name == 'friends.read'),
        hasLength(2),
      );
      if (write != null) {
        final request = host.requests.singleWhere(
          (r) => r.name == 'friends.execute',
        );
        await host.reply(request, host.frames.first);
        await write.future;
        final afterAck = host.read();
        await _turns();
        expect(
          host.requests.where((r) => r.name == 'friends.read'),
          hasLength(3),
        );
        await host.release();
        await afterAck.future;
      } else {
        await host.release();
      }
      await after.future;
      if (oldError != null) {
        await oldError;
      } else {
        await before.future;
      }
    }, skip: _prefix.isEmpty ? 'Requires actual Native paging capture' : false);
  }

  test(
    'different owners queries and wire options cannot share a directory',
    () async {
      final host = _DirectoryWire(_capture('fresh'));
      addTearDown(host.close);
      final owner = host.root.accountContext!;
      final operations = [
        host.read(),
        host.session.beginRequest(
          'friends.read',
          accountContext: BridgeAccountContext(
            environment: 'other',
            authority: owner.authority,
            subject: owner.subject,
          ),
          payload: _directory,
        ),
        host.session.beginRequest(
          'friends.read',
          accountContext: BridgeAccountContext(
            environment: owner.environment,
            authority: 'other',
            subject: owner.subject,
          ),
          payload: _directory,
        ),
        host.session.beginRequest(
          'friends.read',
          accountContext: BridgeAccountContext(
            environment: owner.environment,
            authority: owner.authority,
            subject: 'other',
          ),
          payload: _directory,
        ),
        host.session.beginRequest(
          'friends.read',
          accountContext: owner,
          payload: const {'schemaVersion': 1, 'query': 'Alpha'},
        ),
        host.session.beginRequest(
          'friends.read',
          accountContext: owner,
          payload: const {'schemaVersion': 1, 'query': 'Beta'},
        ),
        host.session.beginRequest(
          'friends.read',
          accountContext: owner,
          payload: const {'schemaVersion': 1},
        ),
      ];
      await _turns();
      expect(host.held, hasLength(7));
      await host.release();
      await Future.wait(operations.map((o) => o.future));
    },
    skip: _prefix.isEmpty ? 'Requires actual Native paging capture' : false,
  );

  test(
    'late joining real adapter receives the original Native cached display',
    () async {
      final host = _DirectoryWire(
        _capture('fresh'),
        online: _capture('online'),
      );
      addTearDown(host.close);
      final a = BridgeFriendsAdapter(host.session),
          b = BridgeFriendsAdapter(host.session);
      addTearDown(a.close);
      addTearDown(b.close);
      final firstCached = Completer<FriendsCachedDisplay>(),
          secondCached = Completer<FriendsCachedDisplay>();
      final sa = a.cachedDisplays.listen((v) {
        if (v != null && !firstCached.isCompleted) firstCached.complete(v);
      });
      final sb = b.cachedDisplays.listen((v) {
        if (v != null && !secondCached.isCompleted) secondCached.complete(v);
      });
      addTearDown(sa.cancel);
      addTearDown(sb.cancel);
      final first = a.read();
      final old = await firstCached.future.timeout(const Duration(seconds: 3));
      final second = b.read();
      final late = await secondCached.future.timeout(
        const Duration(seconds: 3),
      );
      expect(
        host.requests.where((r) => r.name == 'friends.read'),
        hasLength(1),
      );
      expect(old.cachedAtUtc, late.cachedAtUtc);
      expect(late.snapshot.groups[FriendsSection.incoming], hasLength(1400));
      for (final row in late.snapshot.groups[FriendsSection.incoming]!) {
        expect(row.targetRef, isNull);
        expect(row.chatTargetRef, isNull);
        expect(row.conversationKey, isNull);
        expect(row.actions, isEmpty);
      }
      await host.release();
      expect((await first).state, FriendsReadState.ready);
      expect((await second).state, FriendsReadState.ready);
    },
    skip: _prefix.isEmpty ? 'Requires actual Native paging capture' : false,
  );

  test(
    'one optional progress observer cannot break another subscriber',
    () async {
      final host = _DirectoryWire(
        _capture('fresh'),
        online: _capture('online'),
      );
      addTearDown(host.close);
      final seen = Completer<BridgeEnvelope>();
      final a = host.session.beginRequest(
        'friends.read',
        payload: const {..._directory, 'cachedDisplayProgress': true},
        accountContext: host.root.accountContext,
        displayProgress: BridgeDisplayProgress('friends.readDisplay', (_) {
          throw StateError('observer failure');
        }),
      );
      final b = host.session.beginRequest(
        'friends.read',
        payload: const {..._directory, 'cachedDisplayProgress': true},
        accountContext: host.root.accountContext,
        displayProgress: BridgeDisplayProgress('friends.readDisplay', (frame) {
          if (!seen.isCompleted) seen.complete(frame);
        }),
      );
      expect(
        (await seen.future.timeout(const Duration(seconds: 3))).name,
        'friends.readDisplay',
      );
      await host.release();
      expect((await a.future).status, 'ok');
      expect((await b.future).status, 'ok');
      expect(
        host.requests.where((r) => r.name == 'friends.read'),
        hasLength(1),
      );
    },
    skip: _prefix.isEmpty ? 'Requires actual Native paging capture' : false,
  );
  test(
    'unchanged social cursor preserves a flight, changed cursor fences it',
    () async {
      final host = _DirectoryWire(_capture('fresh'));
      addTearDown(host.close);
      Future<void> cursor(int version) async {
        final operation = host.session.beginRequest(
          'social.wait',
          accountContext: host.root.accountContext,
          payload: const {'schemaVersion': 1, 'instance': '', 'version': -1},
        );
        await _turns();
        final request = host.requests.lastWhere((r) => r.name == 'social.wait');
        await host.pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            status: 'ok',
            accountContext: host.root.accountContext,
            payload: {
              'schemaVersion': 1,
              'instance': '00000000000000000000000000000000',
              'version': version,
            },
          ),
        );
        await operation.future;
      }

      await cursor(1);
      final a = host.read();
      await cursor(1);
      final b = host.read();
      await _turns();
      expect(host.held, hasLength(1));
      await cursor(2);
      final c = host.read();
      await _turns();
      expect(host.held, hasLength(2));
      await host.release();
      await Future.wait([a.future, b.future, c.future]);
    },
    skip: _prefix.isEmpty ? 'Requires actual Native paging capture' : false,
  );

  test(
    'failed shared transport reaches both consumers and next read is fresh',
    () async {
      final host = _DirectoryWire(_capture('fresh'));
      addTearDown(host.close);
      final a = host.read(), b = host.read();
      final failures = Future.wait([
        expectLater(a.future, throwsA(isA<BridgeRemoteException>())),
        expectLater(b.future, throwsA(isA<BridgeRemoteException>())),
      ]);
      await _turns();
      final original = host.held.single;
      host.held.clear();
      await host.pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: original.name,
          correlationId: original.correlationId,
          sessionGeneration: original.sessionGeneration,
          status: 'error',
          error: const BridgeErrorBody(
            code: 'friends.read_transient',
            message: 'synthetic failure',
            retryable: true,
          ),
          payload: const {},
        ),
      );
      await failures;
      final retry = host.read();
      await _turns();
      expect(
        host.requests.where((r) => r.name == 'friends.read'),
        hasLength(2),
      );
      await host.release();
      expect((await retry.future).status, 'ok');
    },
    skip: _prefix.isEmpty ? 'Requires actual Native paging capture' : false,
  );

  test(
    'session close fails all consumers instead of retaining a result',
    () async {
      final host = _DirectoryWire(_capture('fresh'));
      addTearDown(host.close);
      final a = host.read(), b = host.read();
      final failures = Future.wait([
        expectLater(a.future, throwsA(isA<BridgeDisconnectedException>())),
        expectLater(b.future, throwsA(isA<BridgeDisconnectedException>())),
      ]);
      await host.session.close();
      await failures;
    },
    skip: _prefix.isEmpty ? 'Requires actual Native paging capture' : false,
  );
  test('late display listener receives a requested cache even if the first consumer did not listen', () async {
    final host = _DirectoryWire(_capture('fresh'), online: _capture('online'));
    addTearDown(host.close);
    const payload = {..._directory, 'cachedDisplayProgress': true};
    final a = host.session.beginRequest(
      'friends.read',
      accountContext: host.root.accountContext,
      payload: payload,
    );
    await _until(() => host.held.isNotEmpty);
    await _turns();
    final displays = <BridgeEnvelope>[];
    final b = host.session.beginRequest(
      'friends.read',
      accountContext: host.root.accountContext,
      payload: payload,
      displayProgress: BridgeDisplayProgress(
        'friends.readDisplay',
        displays.add,
      ),
    );
    await _turns();
    final beforeTerminal = displays.toList();
    await host.release();
    await Future.wait([a.future, b.future]);
    expect(host.requests.where((r) => r.name == 'friends.read'), hasLength(1));
    expect(beforeTerminal, hasLength(1));
    expect(
      beforeTerminal.single.payload['requestCorrelationId'],
      a.correlationId,
    );
    expect(beforeTerminal.single.accountContext, isNull);
  }, skip: _prefix.isEmpty ? 'Requires actual Native paging capture' : false);
}

const _directory = {'schemaVersion': 1, 'pagedResponse': true};
Map<String, Object?> _capture(String kind) => Map<String, Object?>.from(
  jsonDecode(File('$_prefix-$kind.json').readAsStringSync()) as Map,
);

Future<void> _turns() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _until(bool Function() ready) async {
  final end = DateTime.now().add(const Duration(seconds: 3));
  while (!ready()) {
    if (DateTime.now().isAfter(end)) {
      throw StateError('Expected request did not arrive');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

final class _DirectoryWire {
  _DirectoryWire(Map<String, Object?> data, {Map<String, Object?>? online}) {
    root = BridgeEnvelope.fromJson(
      Map<String, Object?>.from(data['root'] as Map),
    );
    frames = (data['frames'] as List)
        .map(
          (v) => BridgeEnvelope.fromJson(Map<String, Object?>.from(v as Map)),
        )
        .toList();
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: root.sessionGeneration,
    );
    final cachedFrames = online == null
        ? <BridgeEnvelope>[]
        : (online['cachedFrames'] as List)
              .map(
                (v) => BridgeEnvelope.fromJson(
                  Map<String, Object?>.from(v as Map),
                ),
              )
              .toList();
    session.acceptHostCapabilities([
      'friends.read',
      'friends.readPages',
      if (online != null) 'friends.readDisplay',
    ]);
    subscription = pair.host.incoming.listen((request) {
      requests.add(request);
      if (request.name == 'account.getCurrent') {
        unawaited(reply(request, root));
      } else if (request.name == 'friends.read') {
        held.add(request);
        if (online != null &&
            request.payload['cachedDisplayProgress'] == true) {
          final source = BridgeEnvelope.fromJson(
            Map<String, Object?>.from(online['prepared'] as Map),
          );
          unawaited(
            pair.host.send(
              BridgeEnvelope(
                protocolVersion: 1,
                messageType: 'event',
                name: source.name,
                sessionGeneration: request.sessionGeneration,
                sequence: ++sequence,
                payload: {
                  ...source.payload,
                  'requestCorrelationId': request.correlationId,
                },
              ),
            ),
          );
        }
      } else if (request.name == 'friends.readPage') {
        final candidates = request.payload.containsKey('displayRequestId')
            ? cachedFrames
            : frames;
        final source = candidates.singleWhere(
          (f) =>
              (f.payload['page'] as Map)['offset'] == request.payload['offset'],
        );
        unawaited(reply(request, source));
      }
    });
  }
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final BridgeEnvelope root;
  late final List<BridgeEnvelope> frames;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[], held = <BridgeEnvelope>[];
  int sequence = 0;
  BridgeRequestOperation read() => session.beginRequest(
    'friends.read',
    accountContext: root.accountContext,
    payload: _directory,
  );
  Future<void> reply(BridgeEnvelope request, BridgeEnvelope source) =>
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: source.protocolVersion,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: source.accountContext,
          status: source.status,
          error: source.error,
          payload: source.payload,
        ),
      );
  Future<void> release() async {
    final waiting = held.toList();
    held.clear();
    for (final request in waiting) {
      await reply(request, frames.first);
    }
  }

  Future<void> close() async {
    await session.close();
    await subscription.cancel();
    await pair.host.close();
  }
}
