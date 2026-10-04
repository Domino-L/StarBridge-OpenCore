import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_chat_widgets.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_members_panel.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;
import 'menu_rooms_panel_test.dart' show RoomPort;

void main() {
  setUpAll(loadFonts);
  testWidgets('room system events are not player bubbles', (tester) async {
    size(tester, const Size(1505, 900));
    final port = RoomPort();
    port.roomChat.messages = [
      RoomChatMessage(
        sequence: 1,
        id: 'system',
        sender: '系统',
        text: '成员创建了房间',
        time: DateTime(2026),
        kind: 'system',
      ),
      RoomChatMessage(
        sequence: 2,
        id: 'player',
        sender: '系统',
        text: '真实玩家也可以使用这个名字',
        time: DateTime(2026),
      ),
    ];
    final views = <Map<String, Object?>>[];
    final session = MenuRoomsSession(port, views.add)..show(true);
    await tester.pump();
    final boundary = GlobalKey();
    await tester.pumpWidget(
      app(
        RepaintBoundary(
          key: boundary,
          child: MenuRoomsPanel(
            view: MenuFeatureView.parse(views.last),
            onAction: session.act,
            active: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RoomMembersPanel), findsOneWidget);
    expect(find.text('房间资料'), findsOneWidget);
    expect(find.text('房间聊天'), findsOneWidget);
    // Keep system events near the chat header; shared toolbar height may vary.
    final headerBottom = tester.getBottomLeft(find.text('房间聊天')).dy;
    final eventTop = tester.getTopLeft(find.textContaining('成员创建了房间')).dy;
    expect(eventTop, greaterThan(headerBottom));
    expect(eventTop - headerBottom, lessThan(100));
    expect(find.byType(MenuChatMessage), findsOneWidget);
    expect(find.textContaining('成员创建了房间'), findsOneWidget);
    await capture(tester, boundary, 'menu-room-system-wide');
    session.dispose();
  });
  testWidgets(
    'compact room uses tabs and preserves draft across tabs and width changes',
    (tester) async {
      size(tester, const Size(683, 611));
      final port = RoomPort(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      await tester.pump();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: boundary,
            child: MenuRoomsPanel(
              view: MenuFeatureView.parse(views.last),
              onAction: session.act,
              active: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('聊天'), findsOneWidget);
      await tester.tap(find.text('聊天'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('menu-channel-draft'));
      expect(field.hitTestable(), findsOneWidget);
      await tester.enterText(field, '保留草稿');
      await tester.tap(find.text('成员'));
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      await tester.tap(find.text('聊天'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '保留草稿');
      await capture(tester, boundary, 'menu-room-compact-chat');
      size(tester, const Size(1505, 900));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '保留草稿');
      expect(find.text('聊天'), findsNothing);
      size(tester, const Size(683, 611));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '保留草稿');
      expect(tester.takeException(), isNull);
      session.dispose();
    },
  );
}
