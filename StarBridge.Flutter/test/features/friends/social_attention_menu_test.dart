import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/example_party_rooms_adapter.dart';
import 'package:starbridge_flutter/features/party_rooms/room_invitation_card.dart';

import 'social_layout_test.dart' show app, capture, loadFonts, size;

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'self avatar uses guarded shell route, peer never opens own profile',
    (tester) async {
      size(tester, const Size(600, 400));
      String? route;
      for (final self in [true, false]) {
        await tester.pumpWidget(
          app(
            Actions(
              actions: {
                OpenDestinationIntent: CallbackAction<OpenDestinationIntent>(
                  onInvoke: (intent) {
                    route = intent.route;
                    return null;
                  },
                ),
              },
              child: Center(
                child: UserAvatarMenu(
                  name: '示例',
                  isSelf: self,
                  child: const SizedBox(width: 44, height: 44),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(UserAvatarMenu));
        await tester.pumpAndSettle();
        final profile = find.widgetWithText(
          MenuItemButton,
          self ? '个人页面' : '查看资料',
        );
        expect(profile, findsOneWidget);
        if (self) {
          await tester.tap(profile);
          await tester.pumpAndSettle();
          expect(route, '/profile');
          route = null;
        } else {
          expect(tester.widget<MenuItemButton>(profile).onPressed, isNull);
          expect(route, isNull);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        }
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets(
    'invitation card keeps full decision facts and actions at narrow widths',
    (tester) async {
      final module = PartyRoomsModule(ExamplePartyRoomsAdapter());
      await module.refresh();
      final directory = module.directory!;
      final invitation = directory.receivedInvitations.single;
      final room = directory.rooms.firstWhere((r) => r.id == invitation.roomId);
      for (final width in [600.0, 390.0]) {
        size(tester, Size(width, 800));
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: app(
              SingleChildScrollView(
                child: RoomInvitationCard(
                  invitation: invitation,
                  room: room,
                  actions: Wrap(
                    spacing: 8,
                    children: [
                      TextButton(onPressed: () {}, child: const Text('拒绝')),
                      FilledButton(onPressed: () {}, child: const Text('加入房间')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('队长当前服务器'), findsOneWidget);
        final card = tester.getRect(find.byType(Card));
        for (final type in [TextButton, FilledButton]) {
          final action = tester.getRect(find.byType(type));
          expect(card.contains(action.topLeft), isTrue);
          expect(
            card.contains(action.bottomRight - const Offset(.1, .1)),
            isTrue,
          );
        }
        await capture(tester, key, 'invitation-card-${width.toInt()}');
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      module.dispose();
    },
  );
}
