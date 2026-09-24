import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';

class CommandPort implements FriendsPort, FriendsCommandPort {
  final events = StreamController<void>.broadcast(sync: true);
  final reads = <({String? query, Completer<FriendsReadResult> result})>[];
  final writes =
      <({String action, String ref, Completer<FriendCommandResult> result})>[];
  @override
  bool commandsAvailable = true;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<FriendsReadResult> read({String? query}) {
    final result = Completer<FriendsReadResult>();
    reads.add((query: query, result: result));
    return result.future;
  }

  @override
  Future<FriendCommandResult> execute(String action, String targetRef) {
    final result = Completer<FriendCommandResult>();
    writes.add((action: action, ref: targetRef, result: result));
    return result.future;
  }

  @override
  void cancelPending() {}
  @override
  Future<void> close() => events.close();
}

FriendsSnapshot directory(
  String relation, {
  String? query,
  List<String>? actions,
  String ref = 'private-ref',
}) {
  final row = FriendRow(
    'Fixture',
    'fixture',
    relation,
    DateTime.utc(2026),
    targetRef: ref,
    actions: actions ?? friendActionsFor(relation),
    shared: const {'presence': 'Offline'},
  );
  final section = switch (relation) {
    'incoming' => FriendsSection.incoming,
    'outgoing' => FriendsSection.outgoing,
    'blocked' => FriendsSection.blocked,
    _ => FriendsSection.friends,
  };
  return FriendsSnapshot(
    groups: {
      section: [row],
    },
    results: query == null ? [] : [row],
    query: query,
  );
}

void answer(CommandPort port, FriendsSnapshot snapshot) => port
    .reads
    .last
    .result
    .complete(FriendsReadResult(FriendsReadState.ready, snapshot: snapshot));

void main() {
  testWidgets(
    'confirmation expiry and rejected result require a fresh explicit decision',
    (tester) async {
      final port = CommandPort(), views = <Map<String, Object?>>[];
      var now = DateTime.utc(2026);
      final lease = MenuFriendsSession(port, views.add, now: () => now)
        ..show(true);
      MenuFriendsView view() => MenuFriendsView.parse(jsonEncode(views.last));
      answer(port, directory('friend'));
      await tester.pump();
      lease.act('prepare', view().rows.single.key!, 'remove');
      final token = view().confirmation!.token;
      now = now.add(const Duration(seconds: 31));
      lease.act('confirm', token, '');
      expect(view().feedback, 'expired');
      expect(port.writes, isEmpty);
      lease.act('refresh', '', '');
      answer(port, directory('friend'));
      await tester.pump();
      lease.act('prepare', view().rows.single.key!, 'remove');
      lease.act('confirm', view().confirmation!.token, '');
      port.writes.single.result.complete(
        const FriendCommandResult('rejected', error: 'forbidden'),
      );
      await tester.pump();
      expect(view().feedback, 'rejected');
      expect(view().requiresRefresh, true);
      expect(view().actions, isEmpty);
      lease.dispose();
      await tester.pump();
    },
  );
  for (final entry in const {
    'send': 'none',
    'accept': 'incoming',
    'reject': 'incoming',
    'cancel': 'outgoing',
    'remove': 'friend',
    'block': 'friend',
    'unblock': 'blocked',
  }.entries) {
    testWidgets(
      '${entry.key} requires a current target and one explicit confirmation',
      (tester) async {
        final port = CommandPort(), views = <Map<String, Object?>>[];
        final lease = MenuFriendsSession(port, views.add)..show(true);
        MenuFriendsView view() => MenuFriendsView.parse(jsonEncode(views.last));
        answer(port, directory('friend'));
        await tester.pump();
        if (entry.value == 'none') {
          lease.act('search', '', 'fixture');
          expect(port.reads.last.query, 'fixture');
          answer(port, directory('none', query: 'fixture'));
          await tester.pump();
        } else if (entry.value != 'friend') {
          lease.act('section', '', entry.value);
          answer(port, directory(entry.value));
          await tester.pump();
        }
        final key = view().rows.single.key!;
        lease.act('confirm', key, entry.key);
        lease.act('prepare', 'private-ref', entry.key);
        expect(port.writes, isEmpty);
        lease.act('prepare', key, entry.key);
        final token = view().confirmation!.token;
        expect(port.writes, isEmpty);
        expect(jsonEncode(views.last), isNot(contains('private-ref')));
        lease.act('confirm', token, '');
        lease.act('confirm', token, '');
        expect(port.writes.length, 1);
        expect(port.writes.single.action, entry.key);
        expect(port.writes.single.ref, 'private-ref');
        expect(view().busy, true);
        port.writes.single.result.complete(
          FriendCommandResult('accepted', directory: directory('friend')),
        );
        await tester.pump();
        expect(view().feedback, 'success.${entry.key}');
        expect(view().busy, false);
        expect(view().confirmation, null);
        lease.dispose();
        await tester.pump();
      },
    );
  }
  testWidgets(
    'unknown result locks writes across reopen until explicit readback; late success is ignored',
    (tester) async {
      final port = CommandPort(), views = <Map<String, Object?>>[];
      final lease = MenuFriendsSession(port, views.add)..show(true);
      MenuFriendsView view() => MenuFriendsView.parse(jsonEncode(views.last));
      answer(port, directory('friend'));
      await tester.pump();
      final key = view().rows.single.key!;
      lease.act('prepare', key, 'remove');
      lease.act('confirm', view().confirmation!.token, '');
      await tester.pump(const Duration(seconds: 16));
      expect(view().feedback, 'unknown');
      expect(view().requiresRefresh, true);
      final reads = port.reads.length;
      lease.show(false);
      lease.show(true);
      await tester.pump(const Duration(seconds: 20));
      expect(port.reads.length, reads);
      lease.act('prepare', key, 'remove');
      expect(port.writes.length, 1);
      lease.act('refresh', '', '');
      answer(port, directory('friend'));
      await tester.pump();
      expect(view().requiresRefresh, false);
      expect(view().feedback, 'reviewed');
      expect(port.writes.length, 1);
      port.writes.single.result.complete(
        FriendCommandResult('accepted', directory: directory('blocked')),
      );
      await tester.pump();
      expect(view().feedback, 'reviewed');
      lease.dispose();
      await tester.pump();
    },
  );
  testWidgets(
    'confirmation retires on revocation, hide, account change and reused name',
    (tester) async {
      final port = CommandPort(), views = <Map<String, Object?>>[];
      final lease = MenuFriendsSession(port, views.add)..show(true);
      MenuFriendsView view() => MenuFriendsView.parse(jsonEncode(views.last));
      answer(port, directory('friend'));
      await tester.pump();
      final key = view().rows.single.key!;
      lease.act('prepare', key, 'block');
      final token = view().confirmation!.token;
      await tester.pump(const Duration(seconds: 10));
      answer(port, directory('friend', actions: []));
      await tester.pump();
      expect(view().confirmation, null);
      lease.act('confirm', token, '');
      expect(port.writes, isEmpty);
      lease.show(false);
      lease.show(true);
      answer(port, directory('friend'));
      await tester.pump();
      lease.act('prepare', view().rows.single.key!, 'remove');
      final beforeAccount = view().confirmation!.token;
      port.events.add(null);
      lease.act(
        'search',
        '',
        'x',
      ); // invalid input must not republish previous account rows
      expect(view().rows, isEmpty);
      answer(port, directory('friend', ref: 'new-account-ref'));
      await tester.pump();
      lease.act('confirm', beforeAccount, '');
      lease.act('prepare', key, 'remove');
      expect(port.writes, isEmpty);
      lease.act('prepare', view().rows.single.key!, 'remove');
      lease.act('confirm', view().confirmation!.token, '');
      port.events.add(null);
      answer(port, directory('friend', ref: 'third-account'));
      await tester.pump();
      port.writes.single.result.complete(
        FriendCommandResult('accepted', directory: directory('blocked')),
      );
      await tester.pump();
      expect(view().section, 'friends');
      expect(view().feedback, '');
      lease.dispose();
      await tester.pump();
    },
  );
  testWidgets(
    'search is explicit, bounded, stale-safe and cannot grant relation-incompatible commands',
    (tester) async {
      final port = CommandPort(), views = <Map<String, Object?>>[];
      final lease = MenuFriendsSession(port, views.add)..show(true);
      MenuFriendsView view() => MenuFriendsView.parse(jsonEncode(views.last));
      answer(port, directory('friend'));
      await tester.pump();
      lease.act('search', '', 'x');
      lease.act('search', '', 'x' * 129);
      expect(port.reads.length, 1);
      lease.act('search', '', 'first');
      final stale = port.reads.last.result;
      lease.act('search', '', 'second');
      answer(
        port,
        directory('none', query: 'second', actions: ['send', 'remove']),
      );
      await tester.pump();
      final key = view().rows.single.key!;
      expect(view().actions[key], ['send']);
      lease.act('prepare', key, 'remove');
      expect(view().confirmation, null);
      stale.complete(
        FriendsReadResult(
          FriendsReadState.ready,
          snapshot: directory('friend', query: 'first'),
        ),
      );
      await tester.pump();
      expect(view().query, 'second');
      port.commandsAvailable = false;
      lease.act('prepare', key, 'send');
      expect(port.writes, isEmpty);
      expect(view().confirmation, null);
      lease.dispose();
      await tester.pump();
    },
  );
}
