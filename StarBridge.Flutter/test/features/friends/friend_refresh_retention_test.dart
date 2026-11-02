import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';

import 'friends_test.dart' show PendingPort, ready;

void main() {
  test('session retirement rejects late data and repeated disposal is harmless', () async {
    final port = PendingPort();
    final module = FriendsModule(port);
    final pending = module.enter();
    module.dispose();
    port.requests.single.complete(ready('Late retired pilot'));
    await pending;
    expect(module.snapshot, isNull);
    expect(() => module.dispose(), returnsNormally);
  });
  test('offscreen ordinary changes expire freshness without erasing data or issuing a read', () async {
    final port = _ActivityPort();
    final module = FriendsModule(port);
    addTearDown(module.dispose);
    final first = module.enter();
    port.requests.single.complete(ready('Loaded pilot'));
    await first;
    final synced = module.lastSuccessfulReadUtc;
    port.soft.add(null);
    expect(module.rows.single.callsign, 'Loaded pilot');
    expect(port.requests, hasLength(1));
    final next = module.enter();
    expect(port.requests, hasLength(2));
    expect(module.lastSuccessfulReadUtc, synced);
    port.requests.last.complete(ready('Updated pilot'));
    await next;
  });

  test('a denied read clears incoming attention along with the inaccessible rows', () async {
    final port = PendingPort();
    final module = FriendsModule(port);
    addTearDown(module.dispose);
    final first = module.enter();
    port.requests.single.complete(FriendsReadResult(FriendsReadState.ready, snapshot: FriendsSnapshot(
      groups: {FriendsSection.incoming: [FriendRow('Request', '', 'incoming', DateTime.utc(2026))]}, results: [],
    )));
    await first;
    expect(module.incomingAttention.value, 1);
    final failed = module.refresh();
    port.requests.last.complete(const FriendsReadResult(FriendsReadState.unavailable, failure: 'forbidden'));
    await failed;
    expect(module.snapshot, isNull);
    expect(module.incomingAttention.value, 0);
  });
  test('retained rows are display-only and do not extend freshness', () async {
    var now = DateTime.utc(2026, 10, 15, 12);
    final port = _Commands();
    final module = FriendsModule(port, now: () => now);
    addTearDown(module.dispose);
    final row = FriendRow(
      'Loaded pilot',
      'Pilot',
      'friend',
      now,
      avatar: 'retained-avatar',
      targetRef: 'a' * 32,
      chatTargetRef: 'b' * 32,
      actions: ['remove'],
      shared: {'presence': 'AppOnline', 'location': 'old location'},
    );
    final first = module.enter();
    port.requests.single.complete(
      FriendsReadResult(
        FriendsReadState.ready,
        snapshot: FriendsSnapshot(
          groups: {
            FriendsSection.friends: [row],
          },
          results: [],
        ),
      ),
    );
    await first;
    final at = module.lastSuccessfulReadUtc;
    final refresh = module.refresh();
    expect(module.canExecute(row, 'remove'), isFalse);
    now = now.add(const Duration(seconds: 1));
    port.requests.last.complete(
      const FriendsReadResult(
        FriendsReadState.unavailable,
        transientFailure: true,
      ),
    );
    await refresh;
    expect(module.refreshFailed, isTrue);
    expect(module.rows.single.avatar, 'retained-avatar');
    expect(module.rows.single.shared, isEmpty);
    expect(module.rows.single.actions, isEmpty);
    expect(module.rows.single.targetRef, isNull);
    expect(module.rows.single.chatTargetRef, isNull);
    expect(module.lastSuccessfulReadUtc, at);
    await module.execute(row, 'remove');
    expect(port.writes, 0);
    final retry = module.enter();
    expect(
      port.requests,
      hasLength(3),
      reason: 'A failed refresh is not a new fresh result.',
    );
    port.requests.last.complete(ready('Recovered pilot'));
    await retry;
    expect(module.refreshFailed, isFalse);
  });

  test('hard invalidation clears rows and scroll and rejects a late transient failure', () async {
    final port = PendingPort();
    final module = FriendsModule(port);
    addTearDown(module.dispose);
    final first = module.enter();
    port.requests.single.complete(ready('Previous owner'));
    await first;
    final view = module.viewEpoch;
    module.rememberScroll(500, expectedEpoch: view);
    final old = module.refresh();
    port.events.add(null);
    expect(module.snapshot, isNull);
    expect(module.scrollOffset, 0);
    module.rememberScroll(900, expectedEpoch: view);
    expect(module.scrollOffset, 0);
    port.requests[1].complete(
      const FriendsReadResult(
        FriendsReadState.unavailable,
        transientFailure: true,
      ),
    );
    await old;
    expect(module.snapshot, isNull);
    port.requests[2].complete(ready('Current owner'));
    await Future<void>.delayed(Duration.zero);
    expect(module.rows.single.callsign, 'Current owner');
  });

  test('different queries and unclassified failures cannot retain a previous directory', () async {
    final port = PendingPort();
    final module = FriendsModule(port);
    addTearDown(module.dispose);
    final first = module.enter();
    port.requests.single.complete(ready('Directory pilot'));
    await first;
    module.editQuery('Search');
    expect(module.snapshot, isNull);
    final search = module.refresh();
    port.requests.last.complete(ready('Wrong query', query: 'Other'));
    await search;
    expect(module.snapshot, isNull);
    expect(module.failure, 'invalidResponse');
    final retry = module.refresh();
    port.requests.last.complete(ready('Search pilot', query: 'Search'));
    await retry;
    final failed = module.refresh();
    port.requests.last.complete(
      const FriendsReadResult(
        FriendsReadState.unavailable,
        failure: 'forbidden',
      ),
    );
    await failed;
    expect(module.snapshot, isNull);
    expect(module.refreshFailed, isFalse);
  });

  test('manual refresh keeps an already loaded directory visible', () async {
    final port = PendingPort();
    final module = FriendsModule(port);
    addTearDown(module.dispose);
    final first = module.enter();
    port.requests.single.complete(ready('Loaded pilot'));
    await first;
    final refresh = module.refresh();
    expect(module.state, FriendsReadState.ready);
    expect(module.rows.single.callsign, 'Loaded pilot');
    expect(module.reading, isTrue);
    port.requests.last.complete(ready('Updated pilot'));
    await refresh;
    expect(module.rows.single.callsign, 'Updated pilot');
  });

  test('same-query manual refreshes share one pending read', () async {
    final port = PendingPort();
    final module = FriendsModule(port);
    addTearDown(module.dispose);
    final first = module.refresh();
    final joined = module.refresh();
    expect(port.requests, hasLength(1));
    port.requests.single.complete(ready('Loaded pilot'));
    await Future.wait([first, joined]);
  });

  test('an explicit timeout keeps confirmed rows for the same query', () async {
    final port = PendingPort();
    final module = FriendsModule(port);
    addTearDown(module.dispose);
    final first = module.enter();
    port.requests.single.complete(ready('Loaded pilot'));
    await first;
    final refresh = module.refresh();
    port.requests.last.completeError(
      TimeoutException('synthetic directory timeout'),
    );
    await refresh;
    expect(module.state, FriendsReadState.ready);
    expect(module.rows.single.callsign, 'Loaded pilot');
    expect(module.reading, isFalse);
  });
}

final class _Commands extends PendingPort implements FriendsCommandPort {
  int writes = 0;
  @override
  bool get commandsAvailable => true;
  @override
  Future<FriendCommandResult> execute(String action, String targetRef) async {
    writes++;
    return const FriendCommandResult('rejected');
  }
}

final class _ActivityPort extends PendingPort implements FriendsActivityPort {
  final soft = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get changes => soft.stream;
  @override
  Future<void> close() async { await super.close(); await soft.close(); }
}
