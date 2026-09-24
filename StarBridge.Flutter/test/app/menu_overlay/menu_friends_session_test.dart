import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';

class Port implements FriendsPort {
  final events = StreamController<void>.broadcast(sync: true);
  final reads = <Completer<FriendsReadResult>>[];
  int cancelled = 0;
  bool closed = false;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<FriendsReadResult> read({String? query}) {
    if (query != null) throw StateError('Menu must not submit a search');
    final pending = Completer<FriendsReadResult>();
    reads.add(pending);
    return pending.future;
  }

  @override
  void cancelPending() => cancelled++;
  @override
  Future<void> close() async {
    closed = true;
    await events.close();
  }
}

FriendsReadResult ready(String name, {String? presence}) => FriendsReadResult(
  FriendsReadState.ready,
  snapshot: FriendsSnapshot(
    groups: {
      FriendsSection.friends: [
        FriendRow(
          name,
          'fixture-handle',
          'friend',
          DateTime(2026),
          targetRef: 'not-for-display',
          avatar: 'private-avatar',
          shared: {
            'presence': presence,
            'ship': 'not-presence-proof',
            'secret': 'never-forward',
          },
        ),
      ],
      FriendsSection.incoming: [
        FriendRow('Request', '', 'incoming', DateTime(2026)),
      ],
    },
    results: [],
  ),
);

void main() {
  testWidgets(
    'friend avatars are bounded and opaque keys survive only unchanged targets',
    (tester) async {
      final port = Port(), views = <Map<String, Object?>>[];
      final lease = MenuFriendsSession(port, views.add);
      FriendsReadResult rows(List<String> refs) => FriendsReadResult(
        FriendsReadState.ready,
        snapshot: FriendsSnapshot(
          groups: {
            FriendsSection.friends: [
              for (final ref in refs)
                FriendRow(
                  'Same name',
                  '',
                  'friend',
                  DateTime(2026),
                  targetRef: ref,
                  avatar: 'data:image/png;base64,${'A' * 120000}',
                ),
            ],
          },
          results: [],
        ),
      );
      lease.show(true);
      port.reads.last.complete(rows(['a', 'b', 'c', 'd', 'e']));
      await tester.pump();
      var view = MenuFriendsView.parse(jsonEncode(views.last));
      expect(view.rows.where((r) => r.avatar != null).length, 4);
      expect(view.rows.map((r) => r.key).toSet().length, 5);
      final a = view.rows.first.key!, b = view.rows[1].key!;
      final former = lease.profileTarget(a)!;
      await tester.pump(const Duration(seconds: 10));
      port.reads.last.complete(rows(['b', 'f']));
      await tester.pump();
      view = MenuFriendsView.parse(jsonEncode(views.last));
      expect(view.rows.first.key, b);
      expect(lease.profileTarget(a), isNull);
      expect(former.isCurrent(), false);
      expect(lease.profileTarget(view.rows.last.key!)!.reference, 'f');
      lease.dispose();
      await tester.pump();
    },
  );
  testWidgets('visible lease reads only while open and filters the wire', (
    tester,
  ) async {
    final port = Port(), views = <Map<String, Object?>>[];
    final lease = MenuFriendsSession(port, views.add);
    expect(port.reads, isEmpty);
    lease.show(true);
    lease.show(true);
    expect(port.reads.length, 1);
    port.reads.single.complete(ready('Pilot', presence: 'InGame'));
    await tester.pump();
    final wire = jsonEncode(views.last);
    expect(wire, isNot(contains('not-for-display')));
    expect(wire, isNot(contains('private-avatar')));
    expect(MenuFriendsView.parse(wire).rows.single.avatar, isNull);
    expect(wire, isNot(contains('ship')));
    final view = MenuFriendsView.parse(wire);
    expect(view.incoming, 1);
    expect(view.rows.single.presence, 'inGame');
    final key = view.rows.single.key!;
    final target = lease.profileTarget(key)!;
    expect(target.source, 'friend');
    expect(target.reference, 'not-for-display');
    expect(target.isCurrent(), true);
    expect(lease.profileTarget('not-for-display'), isNull);
    await tester.pump(const Duration(seconds: 10));
    expect(port.reads.length, 2);
    lease.show(false);
    expect(target.isCurrent(), false);
    expect(target.isAccountCurrent(), true);
    expect(lease.profileTarget(key), isNull);
    port.events.add(null);
    expect(target.isAccountCurrent(), false);
    port.reads.last.complete(ready('Late'));
    await tester.pump(const Duration(seconds: 30));
    expect(port.reads.length, 2);
    expect(views.last, {'state': 'idle'});
    lease.dispose();
    expect(port.closed, true);
  });

  testWidgets(
    'account invalidation clears immediately and rejects old completion',
    (tester) async {
      final port = Port(), views = <Map<String, Object?>>[];
      final lease = MenuFriendsSession(port, views.add);
      lease.show(true);
      port.events.add(null);
      expect(views.last['state'], 'loading');
      expect(views.last['actions'], isEmpty);
      expect(views.last['chatKeys'], isEmpty);
      expect(MenuFriendsView.parse(jsonEncode(views.last)).rows, isEmpty);
      expect(port.reads.length, 2);
      port.reads[1].complete(ready('New account'));
      await tester.pump();
      port.reads[0].complete(ready('Old account'));
      await tester.pump();
      final view = MenuFriendsView.parse(jsonEncode(views.last));
      expect(view.rows.single.name, 'New account');
      expect(view.rows.single.presence, 'unknown');
      lease.dispose();
      await tester.pump();
    },
  );

  testWidgets('timeout, signed out and disposal clear displayed rows', (
    tester,
  ) async {
    final port = Port(), views = <Map<String, Object?>>[];
    final lease = MenuFriendsSession(port, views.add);
    lease.show(true);
    port.reads[0].complete(ready('Pilot'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    port.reads[1].complete(const FriendsReadResult(FriendsReadState.signedOut));
    await tester.pump();
    expect(views.last['state'], 'signedOut');
    expect(views.last['actions'], isEmpty);
    expect(MenuFriendsView.parse(jsonEncode(views.last)).rows, isEmpty);
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    expect(views.last['state'], 'unavailable');
    expect(views.last['chatKeys'], isEmpty);
    expect(MenuFriendsView.parse(jsonEncode(views.last)).rows, isEmpty);
    lease.dispose();
    await tester.pump(const Duration(seconds: 30));
    expect(views.last, {'state': 'idle'});
  });

  test('invalid payload cannot preserve a previous directory', () {
    for (final data in [
      null,
      '{}',
      'not-json',
      '{"state":"ready","rows":[],"incoming":-1}',
      '{"state":"ready","rows":[{"name":"x","presence":"invented"}],"incoming":0}',
    ]) {
      expect(MenuFriendsView.parse(data).state, 'unavailable');
      expect(MenuFriendsView.parse(data).rows, isEmpty);
    }
  });
}
