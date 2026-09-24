import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/party_rooms/bridge_room_chat.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_panel.dart';
import 'package:starbridge_flutter/features/communities/community_invite_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_invite_flow.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';

import '../communities/community_invite_dialog_test.dart' as dialog;
import '../friends/social_layout_test.dart' show loadFonts;
import 'room_chat_test.dart' show ChatPort;
import 'room_lifecycle_widget_test.dart' show openExampleRooms;

Map<String, Object?> wire() => {
  'sequence': 1,
  'messageId': 'card',
  'kind': 'player',
  'senderCallsign': '成员',
  'senderGameId': 'Member',
  'text': '',
  'createdAt': '2026-09-06T00:00:00Z',
  'attachment': <String, Object?>{
    'kind': 'fleet_invitation',
    'title': '组织邀请 · 新手互助',
    'summary': '查看组织详情后决定是否加入。',
    'fleetInviteCode': 'EXAMPLE-ORG',
    'expiresAt': null,
  },
};

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'normal room destination wires the shared organization verification flow',
    (tester) async {
      final composition = await openExampleRooms(tester);
      tester.view.physicalSize = const Size(1600, 1000);
      await composition.partyRooms.selectPreviewScene('current');
      await tester.pumpAndSettle();
      final roomId = composition.partyRooms.directory!.currentRoomId;
      final before = composition.communities.joined.map((c) => c.key).toSet();
      final open = find.widgetWithText(OutlinedButton, '查看邀请');
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.byType(CommunityInviteDialog), findsOneWidget);
      expect(find.text('示例 · 新手互助 · EXAMPLE-ORG'), findsOneWidget);
      expect(composition.communities.joined.map((c) => c.key).toSet(), before);
      expect(composition.partyRooms.directory!.currentRoomId, roomId);
      await tester.tap(
        find.descendant(
          of: find.byType(CommunityInviteDialog),
          matching: find.byTooltip('关闭'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  test(
    'room projection uses the same bounded invitation data as private chat',
    () {
      final input = wire();
      final message = parseRoomChatMessage(input);
      expect(message.communityInvitation?.inviteCode, 'EXAMPLE-ORG');
      expect(message.communityInvitation?.title, '组织邀请 · 新手互助');
      expect(
        () => message.attachment!['fleetInviteCode'] = 'changed',
        throwsUnsupportedError,
      );
      (input['attachment'] as Map)['fleetInviteCode'] = 'changed';
      expect(message.communityInvitation?.inviteCode, 'EXAMPLE-ORG');
      input['attachment'] = null;
      expect(parseRoomChatMessage(input).communityInvitation, isNull);
    },
  );
  for (final entry in <String, Object?>{
    'fleetInviteCode': 'bad',
    'title': '',
    'summary': 'bad\ntext',
    'expiresAt': 'invalid',
  }.entries) {
    test('invalid room card ${entry.key} is rejected before rendering', () {
      final input = wire();
      (input['attachment'] as Map)[entry.key] = entry.value;
      expect(() => parseRoomChatMessage(input), throwsFormatException);
    });
  }
  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ]) {
    testWidgets(
      'room card revalidates, preserves draft and joins only with consent $locale',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 950);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final port = ChatPort()
          ..reading = (_, _) async =>
              RoomChatPage([parseRoomChatMessage(wire())], 1, false);
        final chat = RoomChatModule(port)..setRoom('one');
        final communities = CommunitiesModule(ExampleCommunities());
        await communities.refreshJoined();
        final before = communities.joined.map((c) => c.key).toSet();
        await tester.pump();
        chat.draft = '未发送的房间草稿';
        addTearDown(chat.dispose);
        addTearDown(communities.dispose);
        var opened = 0;
        await tester.pumpWidget(
          dialog.app(
            Scaffold(
              body: RoomChatPanel(
                module: chat,
                openCommunityInvite: (context, code) {
                  opened++;
                  return openCommunityInvitation(
                    context,
                    communities,
                    code,
                    createPrivacy: () => throw StateError(
                      'Example must not open production privacy',
                    ),
                  );
                },
              ),
            ),
            locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(opened, 0);
        final open = find.byType(OutlinedButton).first;
        await tester.tap(open);
        await tester.pumpAndSettle();
        expect(opened, 1);
        expect(find.byType(CommunityInviteDialog), findsOneWidget);
        expect(communities.joined.length, before.length);
        expect(port.sends, 0);
        await tester.tap(
          find.widgetWithText(FilledButton, dialog.text(tester, 'review')),
        );
        await tester.pumpAndSettle();
        await dialog.acknowledge(tester);
        await tester.tap(
          find.widgetWithText(FilledButton, dialog.text(tester, 'join')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CommunityInviteDialog), findsNothing);
        expect(
          communities.joined.map((c) => c.key).toSet().containsAll(before),
          isTrue,
        );
        expect(communities.joined.length, before.length + 1);
        expect(chat.roomId, 'one');
        expect(chat.draft, '未发送的房间草稿');
        expect(port.sends, 0);
        await tester.pumpWidget(const SizedBox());
        chat.setRoom(null);
        await tester.pump();
      },
    );
  }
}
