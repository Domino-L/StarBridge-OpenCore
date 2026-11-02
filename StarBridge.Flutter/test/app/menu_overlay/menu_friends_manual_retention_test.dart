import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/friends_window/friends_window_app.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_loading.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';

import 'menu_friend_commands_test.dart' show CommandPort, answer;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;

FriendsSnapshot _directory(String label) => FriendsSnapshot(
      groups: {
        FriendsSection.friends: [
          FriendRow(label, 'fixture-id', 'friend', DateTime.utc(2026),
              targetRef: 'private-target-$label',
              chatTargetRef: 'private-chat-$label',
              conversationKey: 'fixture-conversation',
              actions: const ['remove', 'block'],
              shared: const {
                'presence': 'InGame',
                'ship': 'former-detail',
              }),
        ],
      },
      results: const [],
    );

MenuFriendsView _view(Map<String, Object?> wire) =>
    MenuFriendsView.parse(jsonEncode(wire));

Future<void> _close(
    CommandPort port, MenuFriendsSession session, WidgetTester tester) async {
  session.dispose();
  for (final read in port.reads) {
    if (!read.result.isCompleted) {
      read.result.complete(const FriendsReadResult(FriendsReadState.signedOut));
    }
  }
  await tester.pump();
}

void main() {
  setUpAll(loadFonts);

  testWidgets('manual refresh retains display after retiring old capabilities',
      (tester) async {
    final port = CommandPort();
    final wires = <Map<String, Object?>>[];
    final session = MenuFriendsSession(port, wires.add)..show(true);
    addTearDown(session.dispose);
    try {
      answer(port, _directory('Original pilot'));
      await tester.pump();
      final before = _view(wires.last);
      final key = before.rows.single.key!;
      final profile = session.profileTarget(key)!;
      expect(session.chatTarget(key), isNotNull);
      session.act('prepare', key, 'remove');
      final token = _view(wires.last).confirmation!.token;
      final firstRefreshWire = wires.length;

      session.act('refresh', '', '');
      expect(port.reads, hasLength(2));
      expect(profile.isCurrent(), false);
      expect(session.profileTarget(key), isNull);
      expect(session.chatTarget(key), isNull);
      expect(_view(wires.last).actions, isEmpty);
      expect(_view(wires.last).chatKeys, isEmpty);
      expect(_view(wires.last).confirmation, isNull);
      session.act('prepare', key, 'remove');
      session.act('confirm', token, '');
      expect(port.writes, isEmpty);
      expect(_view(wires.last).refreshing, true);
      expect(_view(wires.last).readFeedback, isNotNull);
      for (final wire in wires.skip(firstRefreshWire)) {
        final pending = _view(wire);
        expect(pending.rows.map((row) => row.name), ['Original pilot']);
        expect(pending.rows.single.key, isNull);
        expect(pending.details, isEmpty);
        expect(pending.gameIds, isEmpty);
      }

      answer(port, _directory('New pilot'));
      await tester.pump();
      final after = _view(wires.last);
      expect(after.rows.single.name, 'New pilot');
      expect(after.refreshing, false);
      expect(after.actions, isNotEmpty);
      expect(after.rows.single.key, isNot(key));
      expect(profile.isCurrent(), false);
      session.dispose();
      await tester.pump();
    } finally {
      await _close(port, session, tester);
    }
  });

  testWidgets('auxiliary engine renders exact retained manual refresh wire',
      (tester) async {
    const channel = MethodChannel('starbridge/friends-surface');
    final messenger = tester.binding.defaultBinaryMessenger;
    final port = CommandPort();
    final wires = <Map<String, Object?>>[];
    final session = MenuFriendsSession(port, wires.add)..show(true);
    addTearDown(session.dispose);
    try {
      answer(port, _directory('Visible pilot'));
      await tester.pump();
      var revision = 0;
      Map<String, Object?> snapshot() => {
            'opening': 1,
            'revision': ++revision,
            'view': jsonEncode(wires.last),
          };
      messenger.setMockMethodCallHandler(channel,
          (call) async => call.method == 'ready' ? snapshot() : true);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      size(tester, const Size(392, 640));
      await tester.pumpWidget(const FriendsWindowApp());
      await tester.pumpAndSettle();
      expect(find.textContaining('Visible pilot'), findsOneWidget);

      session.act('refresh', '', '');
      expect(port.reads, hasLength(2));
      await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall('snapshot', snapshot())),
          (_) {});
      await tester.pump();
      expect(find.byType(MenuLoading), findsOneWidget);
      expect(find.textContaining('Visible pilot'), findsOneWidget);
      expect(find.text('正在读取好友…'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      await tester.pump();
    } finally {
      await _close(port, session, tester);
    }
  });

  for (final state in [FriendsReadState.signedOut, FriendsReadState.unavailable]) {
    testWidgets('manual refresh clears former display on $state', (tester) async {
      final port = CommandPort();
      final wires = <Map<String, Object?>>[];
      final session = MenuFriendsSession(port, wires.add)..show(true);
      answer(port, _directory('Former pilot'));
      await tester.pump();
      session.act('refresh', '', '');
      port.reads.last.result.complete(FriendsReadResult(state));
      await tester.pump();
      expect(_view(wires.last).rows, isEmpty);
      expect(_view(wires.last).actions, isEmpty);
      expect(_view(wires.last).chatKeys, isEmpty);
      session.dispose();
      await tester.pump();
    });
  }

  testWidgets('account change retires retained display and rejects late completion',
      (tester) async {
    final port = CommandPort();
    final wires = <Map<String, Object?>>[];
    final session = MenuFriendsSession(port, wires.add)..show(true);
    answer(port, _directory('Old account display'));
    await tester.pump();
    session.act('refresh', '', '');
    final oldRead = port.reads.last.result;
    port.events.add(null);
    expect(_view(wires.last).rows, isEmpty);
    expect(_view(wires.last).actions, isEmpty);
    answer(port, _directory('New account display'));
    await tester.pump();
    oldRead.complete(FriendsReadResult(FriendsReadState.ready,
        snapshot: _directory('Late old account')));
    await tester.pump();
    expect(_view(wires.last).rows.single.name, 'New account display');
    session.dispose();
    await tester.pump();
  });

  for (final change in ['section', 'search']) {
    testWidgets('$change clears manual refresh display and rejects old reply',
        (tester) async {
      final port = CommandPort();
      final wires = <Map<String, Object?>>[];
      final session = MenuFriendsSession(port, wires.add)..show(true);
      try {
        answer(port, _directory('Former query pilot'));
        await tester.pump();
        session.act('refresh', '', '');
        final oldRead = port.reads.last.result;
        session.act(change, '', change == 'section' ? 'incoming' : 'next-query');
        expect(port.reads, hasLength(3));
        expect(port.reads.last.query, change == 'search' ? 'next-query' : null);
        expect(_view(wires.last).rows, isEmpty);
        expect(_view(wires.last).requests, isEmpty);
        expect(_view(wires.last).actions, isEmpty);
        oldRead.complete(FriendsReadResult(FriendsReadState.ready,
            snapshot: _directory('Late former query')));
        await tester.pump();
        expect(_view(wires.last).rows, isEmpty);
        expect(_view(wires.last).requests, isEmpty);
      } finally {
        await _close(port, session, tester);
      }
      await tester.pump();
    });
  }
}
