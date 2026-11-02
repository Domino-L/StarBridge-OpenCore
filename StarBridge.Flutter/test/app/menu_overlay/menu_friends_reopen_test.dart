import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';

import 'menu_friend_commands_test.dart' show CommandPort, answer;

// build16 window traces (2026-10-22): the friends window reopened into a
// loading screen every time (median 2.6 s), while messages and notifications
// reopened with their last display in ~6 ms.

FriendsSnapshot _directory(String label) => FriendsSnapshot(
  groups: {
    FriendsSection.friends: [
      FriendRow(
        label,
        'fixture-id',
        'friend',
        DateTime.utc(2026),
        targetRef: 'private-target-$label',
        chatTargetRef: 'private-chat-$label',
        conversationKey: 'fixture-conversation',
        actions: const ['remove', 'block'],
        shared: const {'presence': 'InGame', 'ship': 'former-detail'},
      ),
    ],
  },
  results: const [],
);

MenuFriendsView _view(Map<String, Object?> wire) =>
    MenuFriendsView.parse(jsonEncode(wire));

Future<void> _close(
  CommandPort port,
  MenuFriendsSession session,
  WidgetTester tester,
) async {
  session.dispose();
  for (final read in port.reads) {
    if (!read.result.isCompleted) {
      read.result.complete(const FriendsReadResult(FriendsReadState.signedOut));
    }
  }
  await tester.pump();
}

void main() {
  testWidgets('reopening shows the last basic display while it reads again', (
    tester,
  ) async {
    final port = CommandPort();
    final wires = <Map<String, Object?>>[];
    final session = MenuFriendsSession(port, wires.add)..show(true);
    addTearDown(session.dispose);
    answer(port, _directory('Pilot'));
    await tester.pump();
    final key = _view(wires.last).rows.single.key!;
    session.show(false);
    session.show(true);
    final reopened = _view(wires.last);
    expect(reopened.rows.map((r) => r.name), [
      'Pilot',
    ], reason: 'The window reopened into a loading screen.');
    expect(port.reads, hasLength(2), reason: 'Reopening still reads again.');
    // Capabilities of the hidden opening never survive into the kept display.
    expect(reopened.rows.single.key, isNull);
    expect(session.profileTarget(key), isNull);
    expect(session.chatTarget(key), isNull);
    expect(jsonEncode(wires.last), isNot(contains('former-detail')));
    answer(port, _directory('Pilot'));
    await tester.pump();
    expect(_view(wires.last).rows.single.key, isNotNull);
    await _close(port, session, tester);
  });

  testWidgets('an account change while hidden reopens without the old list', (
    tester,
  ) async {
    final port = CommandPort();
    final wires = <Map<String, Object?>>[];
    final session = MenuFriendsSession(port, wires.add)..show(true);
    addTearDown(session.dispose);
    answer(port, _directory('Old account pilot'));
    await tester.pump();
    session.show(false);
    port.events.add(null);
    await tester.pump();
    session.show(true);
    expect(jsonEncode(wires.last), isNot(contains('Old account pilot')));
    await _close(port, session, tester);
  });
}
