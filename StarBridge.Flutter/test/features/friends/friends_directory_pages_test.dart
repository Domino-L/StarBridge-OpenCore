import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/friends/bridge_friends_adapter.dart';
import 'package:starbridge_flutter/features/friends/friends_directory_pages.dart';
import 'package:starbridge_flutter/features/friends/friends_cached_display.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  Map<String, Object?> cachedPage(int offset) => {
    'schemaVersion': 1,
    'cachedAtUtc': '2026-10-17T00:00:00Z',
    'directory': _page(offset),
  };
  test('cached page assembly preserves time and exposes only a complete read-only snapshot', () {
    final pages = FriendsCachedPages();
    expect(pages.add(cachedPage(0)), isNull);
    final display = pages.add(cachedPage(1))!;
    expect(display.cachedAtUtc, DateTime.utc(2026, 10, 17));
    expect(display.snapshot.groups[FriendsSection.incoming], hasLength(2));
    expect(
      display.snapshot.groups.values
          .expand((rows) => rows)
          .every((row) => row.actions.isEmpty && row.targetRef == null),
      isTrue,
    );
  });
  for (final change in ['time', 'reference', 'actions', 'extra', 'query']) {
    test(
      'cached pages reject changed $change before publishing a complete snapshot',
      () {
        final pages = FriendsCachedPages();
        pages.add(cachedPage(0));
        final body = cachedPage(1);
        final directory = body['directory']! as Map;
        final row = (directory['incoming'] as List).single as Map;
        if (change == 'time') body['cachedAtUtc'] = '2026-10-16T00:00:00Z';
        if (change == 'reference' || change == 'actions') {
          row['targetRef'] = 'b' * 32;
        }
        if (change == 'actions') row['actions'] = ['accept'];
        if (change == 'extra') body['authorization'] = 'synthetic';
        if (change == 'query') directory['query'] = 'Synthetic';
        expect(() => pages.add(body), throwsFormatException);
        expect(() => pages.add(cachedPage(1)), throwsFormatException);
      },
    );
  }
  test('pages stay private until a complete directory can be decoded', () {
    final pages = FriendsDirectoryPages();
    expect(pages.add(_page(0)), isNull);
    expect(pages.nextOffset, 1);
    final complete = pages.add(_page(1))!;
    final snapshot = parseFriendsSnapshot(complete);
    expect(
      snapshot.groups[FriendsSection.incoming]!.map((row) => row.callsign),
      ['Synthetic 0', 'Synthetic 1'],
    );
    expect(() => pages.nextOffset, throwsFormatException);
    expect(() => pages.add(_page(1)), throwsFormatException);
  });

  final mutations = <String, void Function(Map<String, Object?>)>{
    'missing metadata': (body) => body.remove('page'),
    'fractional schema': (body) => body['schemaVersion'] = 1.0,
    'foreign snapshot': (body) =>
        (body['page'] as Map)['snapshotId'] = 'b' * 32,
    'repeated offset': (body) => (body['page'] as Map)['offset'] = 0,
    'skipped offset': (body) => (body['page'] as Map)['offset'] = 2,
    'changed total': (body) => (body['page'] as Map)['total'] = 3,
    'wrong terminal offset': (body) => (body['page'] as Map)['nextOffset'] = 2,
    'premature empty page': (body) => body['incoming'] = [],
    'changed freshness': (body) => body['refreshedAt'] = '2026-10-16T00:00:00Z',
    'changed query': (body) => body['query'] = 'Synthetic',
    'unknown metadata': (body) => (body['page'] as Map)['authority'] = 'other',
    'unknown directory field': (body) => body['truncated'] = true,
    'regressed group': (body) {
      body['friends'] = [_row(1, relation: 'friend')];
      body['incoming'] = [];
    },
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key} without recovering a poisoned transfer', () {
      final pages = FriendsDirectoryPages();
      pages.add(_page(0));
      final changed = _page(1);
      entry.value(changed);
      expect(() => pages.add(changed), throwsFormatException);
      expect(() => pages.add(_page(1)), throwsFormatException);
    });
  }
  test('valid empty directory is complete and cannot request a next page', () {
    final pages = FriendsDirectoryPages();
    final body = _page(0);
    body['incoming'] = [];
    body['page'] = {
      'snapshotId': 'a' * 32,
      'offset': 0,
      'nextOffset': null,
      'total': 0,
    };
    expect((pages.add(body)!['incoming'] as List), isEmpty);
    expect(() => pages.nextOffset, throwsFormatException);
  });
  test('search pages cannot borrow ordinary directory rows', () {
    final body = _page(0)..['query'] = 'Synthetic';
    expect(() => FriendsDirectoryPages().add(body), throwsFormatException);
  });
  test('count limits apply across pages rather than once per frame', () {
    final pages = FriendsDirectoryPages();
    for (var offset = 0; offset < 2000; offset += 100) {
      final body = _page(0);
      body['incoming'] = [for (var i = 0; i < 100; i++) _row(offset + i)];
      body['page'] = {
        'snapshotId': 'a' * 32,
        'offset': offset,
        'nextOffset': offset + 100,
        'total': 2001,
      };
      expect(pages.add(body), isNull);
    }
    final last = _page(1);
    last['page'] = {
      'snapshotId': 'a' * 32,
      'offset': 2000,
      'nextOffset': null,
      'total': 2001,
    };
    expect(() => pages.add(last), throwsFormatException);
  });
  test(
    'adapter reads one root and publishes only the assembled directory',
    () async {
      final host = _PagingHost();
      addTearDown(host.close);
      var completed = false;
      final pending = host.adapter.read()..then((_) => completed = true);
      await host.pageArrived.future;
      expect(completed, isFalse);
      expect(host.requests.map((r) => r.name), [
        'account.getCurrent',
        'friends.read',
        'friends.readPage',
      ]);
      expect(host.requests[1].payload['pagedResponse'], isTrue);
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'snapshotId': 'a' * 32,
        'offset': 1,
      });
      await host.finish();
      final result = await pending;
      expect(result.state, FriendsReadState.ready);
      expect(result.snapshot!.groups[FriendsSection.incoming], hasLength(2));
    },
  );
  for (final change in [
    'cancel',
    'generation',
    'mode',
    'foreign owner',
    'broken page',
  ]) {
    test('$change cannot publish a partly collected directory', () async {
      final host = _PagingHost();
      addTearDown(host.close);
      final pending = host.adapter.read();
      await host.pageArrived.future;
      if (change == 'cancel') host.adapter.cancelPending();
      if (change == 'generation') host.session.advanceGeneration(5);
      if (change == 'mode') {
        await host.session.runConnectionModeChange(() async {});
      }
      await host.finish(
        foreign: change == 'foreign owner',
        broken: change == 'broken page',
      );
      final result = await pending;
      expect(result.snapshot, isNull);
      expect(
        result.state,
        const ['cancel', 'generation', 'mode'].contains(change)
            ? FriendsReadState.idle
            : FriendsReadState.unavailable,
      );
      expect(
        host.requests.where((r) => r.name == 'account.getCurrent'),
        hasLength(1),
      );
      expect(
        host.requests.where((r) => r.name == 'friends.readPage'),
        hasLength(1),
      );
    });
  }
  testWidgets('whole transfer deadline does not restart for each next page', (
    tester,
  ) async {
    final host = _PagingHost(total: 3);
    addTearDown(host.close);
    final pending = host.adapter.read();
    await tester.pump();
    expect(host.pageArrived.isCompleted, isTrue);
    await tester.pump(const Duration(seconds: 7));
    await host.finish();
    await tester.pump();
    expect(host.held!.payload['offset'], 2);
    await tester.pump(const Duration(seconds: 9));
    final result = await pending;
    expect(result.snapshot, isNull);
    expect(result.transientFailure, isTrue);
    expect(
      host.requests
          .where((r) => r.name == 'bridge.cancel')
          .map((r) => r.payload['targetCorrelationId']),
      contains(host.held!.correlationId),
    );
  });
  test(
    'online cache pages finish privately before the original fresh read',
    () async {
      final host = _CachedPagingHost();
      addTearDown(host.close);
      final pending = host.adapter.read();
      await host.cacheArrived.future;
      expect(host.displays, isEmpty);
      await host.finishCache();
      final display = await host.displayReady.future;
      expect(display.snapshot.groups[FriendsSection.incoming], hasLength(2));
      expect(
        host.requests.last.payload['displayRequestId'],
        host.fresh!.correlationId,
      );
      await host.finishFresh();
      expect((await pending).state, FriendsReadState.ready);
      expect(
        host.requests.where((r) => r.name == 'account.getCurrent'),
        hasLength(1),
      );
    },
  );
  for (final winner in ['fresh', 'generation', 'mode']) {
    test(
      '$winner retires incomplete online cache pages without publishing them',
      () async {
        final host = _CachedPagingHost();
        addTearDown(host.close);
        final pending = host.adapter.read();
        await host.cacheArrived.future;
        if (winner == 'generation') host.session.advanceGeneration(5);
        if (winner == 'mode') {
          await host.session.runConnectionModeChange(() async {});
        }
        await host.finishFresh();
        final result = await pending;
        expect(
          result.state,
          winner == 'fresh' ? FriendsReadState.ready : FriendsReadState.idle,
        );
        await host.finishCache();
        await Future<void>.delayed(Duration.zero);
        expect(host.displays, isEmpty);
      },
    );
  }
}

Map<String, Object?> _row(int index, {String relation = 'incoming'}) => {
  'callsign': 'Synthetic $index',
  'gameId': '',
  'relationship': relation,
  'updatedAt': '2026-10-17T00:00:00Z',
  'actions': <String>[],
};
Map<String, Object?> _page(int offset, {int total = 2}) => {
  'schemaVersion': 1,
  'refreshedAt': '2026-10-17T00:00:00Z',
  'friends': [],
  'incoming': [_row(offset)],
  'outgoing': [],
  'blocked': [],
  'results': [],
  'page': {
    'snapshotId': 'a' * 32,
    'offset': offset,
    'nextOffset': offset + 1 < total ? offset + 1 : null,
    'total': total,
  },
};

final class _PagingHost {
  _PagingHost({this.total = 2}) {
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
    );
    session.acceptHostCapabilities(['friends.read', 'friends.readPages']);
    adapter = BridgeFriendsAdapter(session);
    subscription = pair.host.incoming.listen((request) {
      requests.add(request);
      if (request.name == 'bridge.cancel') return;
      if (request.name == 'friends.readPage') {
        held = request;
        if (!pageArrived.isCompleted) pageArrived.complete();
        return;
      }
      unawaited(
        _reply(
          request,
          request.name == 'account.getCurrent'
              ? {'schemaVersion': 1, 'state': 'signedIn'}
              : _page(0, total: total),
        ),
      );
    });
  }
  final pair = InMemoryBridgeConnection.createPair();
  final int total;
  late final BridgeClientSession session;
  late final BridgeFriendsAdapter adapter;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  final pageArrived = Completer<void>();
  BridgeEnvelope? held;
  static const owner = BridgeAccountContext(
    environment: 'synthetic-test',
    authority: 'synthetic',
    subject: 'synthetic',
  );
  Future<void> _reply(
    BridgeEnvelope request,
    Map<String, Object?> body, {
    bool foreign = false,
  }) => pair.host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: request.name,
      correlationId: request.correlationId,
      sessionGeneration: request.sessionGeneration,
      accountContext: foreign
          ? const BridgeAccountContext(
              environment: 'other',
              authority: 'synthetic',
              subject: 'synthetic',
            )
          : owner,
      status: 'ok',
      payload: body,
    ),
  );
  Future<void> finish({bool foreign = false, bool broken = false}) {
    final body = _page(held!.payload['offset']! as int, total: total);
    if (broken) (body['page'] as Map)['offset'] = 0;
    return _reply(held!, body, foreign: foreign);
  }

  Future<void> close() async {
    await adapter.close();
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  }
}

final class _CachedPagingHost {
  _CachedPagingHost() {
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
    );
    session.acceptHostCapabilities([
      'friends.read',
      'friends.readPages',
      'friends.readDisplay',
    ]);
    adapter = BridgeFriendsAdapter(session);
    displaySubscription = adapter.cachedDisplays.listen((display) {
      if (display == null) return;
      displays.add(display);
      if (!displayReady.isCompleted) displayReady.complete(display);
    });
    subscription = pair.host.incoming.listen((request) {
      requests.add(request);
      switch (request.name) {
        case 'account.getCurrent':
          unawaited(_reply(request, {'schemaVersion': 1, 'state': 'signedIn'}));
        case 'friends.read':
          fresh = request;
          unawaited(
            pair.host.send(
              BridgeEnvelope(
                protocolVersion: 1,
                messageType: 'event',
                name: 'friends.readDisplay',
                sessionGeneration: request.sessionGeneration,
                sequence: 1,
                payload: {
                  'schemaVersion': 1,
                  'requestCorrelationId': request.correlationId,
                  'cachedAtUtc': DateTime.now().toUtc().toIso8601String(),
                  'directory': _page(0),
                },
              ),
            ),
          );
        case 'friends.readPage':
          cache = request;
          if (!cacheArrived.isCompleted) cacheArrived.complete();
      }
    });
  }
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final BridgeFriendsAdapter adapter;
  late final StreamSubscription<BridgeEnvelope> subscription;
  late final StreamSubscription<FriendsCachedDisplay?> displaySubscription;
  final requests = <BridgeEnvelope>[];
  final displays = <FriendsCachedDisplay>[];
  final cacheArrived = Completer<void>();
  final displayReady = Completer<FriendsCachedDisplay>();
  BridgeEnvelope? fresh, cache;
  Future<void> _reply(BridgeEnvelope request, Map<String, Object?> body) =>
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: _PagingHost.owner,
          status: 'ok',
          payload: body,
        ),
      );
  Future<void> finishCache() => _reply(cache!, _page(1));
  Future<void> finishFresh() {
    final body = _page(0);
    body['incoming'] = [_row(0), _row(1)];
    body['page'] = {
      'snapshotId': 'c' * 32,
      'offset': 0,
      'nextOffset': null,
      'total': 2,
    };
    return _reply(fresh!, body);
  }

  Future<void> close() async {
    await adapter.close();
    await displaySubscription.cancel();
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  }
}
