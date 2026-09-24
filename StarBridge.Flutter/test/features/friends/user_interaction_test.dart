import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/features/common/bridge_user_interaction.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import '../communities/community_visitor_profile_test.dart'
    show VisitorPort, visitorPayload;
import '../communities/bridge_communities_test.dart' show CommunityHarness;
import 'social_layout_test.dart' show app, loadFonts;

class MenuPort extends VisitorPort {
  Completer<FriendRow?>? held;
  int writes = 0;
  String? lastAction, lastRef;
  FriendRow? row = FriendRow(
    'Peer',
    'Peer_Handle',
    'none',
    DateTime.utc(2026),
    targetRef: 'c' * 32,
    chatTargetRef: 'd' * 32,
    actions: ['send'],
  );
  @override
  Future<FriendRow?> social(UserTarget target) async => held?.future ?? row;
  @override
  Future<FriendCommandResult> execute(String action, String reference) async {
    writes++;
    lastAction = action;
    lastRef = reference;
    return const FriendCommandResult('accepted');
  }
}

void main() {
  setUpAll(loadFonts);
  const target = UserTarget('friend', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
  testWidgets(
    'avatar menu never writes until explicitly selected; self has no social actions',
    (tester) async {
      final p = MenuPort();
      addTearDown(p.changes.close);
      final nav = UserPageNavigation()
        ..open = (_, _, _) async {}
        ..openSelf = (_) async {};
      Widget menu(bool self) => app(
        UserInteractionScope(
          navigation: nav,
          port: p,
          messagePage: (_, _) => const Text('Conversation'),
          child: Center(
            child: UserAvatarMenu(
              name: 'Peer',
              target: target,
              isSelf: self,
              child: const SizedBox(width: 48, height: 48),
            ),
          ),
        ),
      );
      await tester.pumpWidget(menu(false));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(UserAvatarMenu));
      await tester.pumpAndSettle();
      expect(p.writes, 0);
      expect(find.widgetWithText(MenuItemButton, '发消息'), findsOneWidget);
      await tester.tap(find.widgetWithText(MenuItemButton, '添加好友'));
      await tester.pumpAndSettle();
      expect(p.writes, 1);
      expect(p.lastAction, 'send');
      expect(p.lastRef, 'c' * 32);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(menu(true));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(UserAvatarMenu));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MenuItemButton, '添加好友'), findsNothing);
      expect(find.widgetWithText(MenuItemButton, '发消息'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('account invalidation discards a pending menu response', (
    tester,
  ) async {
    final p = MenuPort()..held = Completer<FriendRow?>();
    addTearDown(p.changes.close);
    await tester.pumpWidget(
      app(
        UserInteractionScope(
          navigation: UserPageNavigation(),
          port: p,
          messagePage: null,
          child: Center(
            child: UserAvatarMenu(
              name: 'Peer',
              target: target,
              child: const SizedBox(width: 48, height: 48),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(UserAvatarMenu));
    await tester.pump();
    p.changes.add(null);
    await tester.pump();
    p.held!.complete(p.row);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MenuItemButton, '添加好友'), findsNothing);
    expect(p.writes, 0);
    await tester.pumpWidget(const SizedBox());
  });
  test('generic visitor bridge requires read-only results and discards late account results', () async {
    final h = CommunityHarness(
      legacy: true,
      capabilities: ['users.interaction'],
      responses: {'users.profile': visitorPayload},
    );
    final p = BridgeUserInteraction(h.session);
    addTearDown(() async {
      await p.close();
      await h.close();
    });
    expect((await p.profile(target)).callSign, 'Visitor Pilot');
    expect(h.requests.last.payload, {'schemaVersion': 1, ...target.payload});
  });
  test('avatar social parser accepts exact nonfriend target but no automatic command', () async {
    final h = CommunityHarness(
      legacy: true,
      capabilities: ['users.interaction'],
      responses: {
        'users.social': {
          'schemaVersion': 1,
          'query': null,
          'friends': [],
          'incoming': [],
          'outgoing': [],
          'blocked': [],
          'results': [
            {
              'callsign': 'Peer',
              'gameId': 'Peer_Handle',
              'relationship': 'none',
              'updatedAt': '2026-09-21T00:00:00Z',
              'targetRef': 'c' * 32,
              'chatTargetRef': 'd' * 32,
              'conversationKey': 'e' * 64,
              'actions': ['send', 'block'],
            },
          ],
        },
      },
    );
    final p = BridgeUserInteraction(h.session);
    addTearDown(() async {
      await p.close();
      await h.close();
    });
    final row = await p.social(target);
    expect(row?.relationship, 'none');
    expect(row?.chatTargetRef, 'd' * 32);
    expect(h.requests.where((r) => r.name == 'friends.execute'), isEmpty);
  });
  test('closing a profile reader cancels only its pending request', () async {
    final h = CommunityHarness(
      legacy: true,
      capabilities: ['users.interaction'],
      holdNames: {'users.profile'},
      responses: {'users.profile': visitorPayload},
    );
    final first = BridgeUserInteraction(h.session),
        second = BridgeUserInteraction(h.session);
    addTearDown(h.close);
    final abandoned = first.profile(target);
    await h.readArrived.future;
    await first.close();
    expect(
      (await abandoned).availability,
      PersonalProfileAvailability.unavailable,
    );
    expect(h.requests.where((r) => r.name == 'bridge.cancel').length, 1);
    final active = second.profile(target);
    await Future<void>.delayed(Duration.zero);
    await h.reply(h.requests.lastWhere((r) => r.name == 'users.profile'));
    expect((await active).callSign, 'Visitor Pilot');
    expect(h.requests.where((r) => r.name == 'bridge.cancel').length, 1);
    await second.close();
  });
  test(
    'generic profile rejects a reply after account generation changes',
    () async {
      final h = CommunityHarness(
        legacy: true,
        capabilities: ['users.interaction'],
        holdNames: {'users.profile'},
        responses: {'users.profile': visitorPayload},
      );
      final p = BridgeUserInteraction(h.session);
      addTearDown(() async {
        await p.close();
        await h.close();
      });
      final read = p.profile(target);
      await h.readArrived.future;
      await h.connection.send(
        const BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'account.changed',
          sessionGeneration: 5,
          sequence: 1,
          payload: {'schemaVersion': 1},
        ),
      );
      await h.reply(h.requests.last);
      expect(
        (await read).availability,
        PersonalProfileAvailability.unavailable,
      );
    },
  );
}
