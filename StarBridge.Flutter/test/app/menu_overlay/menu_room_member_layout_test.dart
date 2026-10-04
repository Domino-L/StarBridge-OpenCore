import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_member_menu.dart';
import 'package:starbridge_flutter/features/party_rooms/room_members_panel.dart';

import 'menu_room_settings_test.dart' show SettingsPort;
import 'menu_rooms_panel_test.dart' show Chat;
import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;

class LayoutRoomPort extends SettingsPort implements RoomChatProvider {
  @override
  final roomChat = Chat();
}

void main() {
  setUpAll(loadFonts);
  testWidgets('default feature action keeps its existing stretched layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        SizedBox(
          width: 400,
          height: 100,
          child: MenuFeatureAction(
            action: (
              key: 'a1',
              label: '操作',
              confirm: null,
              input: null,
              limit: 0,
            ),
            enabled: true,
            onAction: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final column = tester.widget<Column>(
      find
          .descendant(
            of: find.byType(MenuFeatureAction),
            matching: find.byType(Column),
          )
          .first,
    );
    expect(column.crossAxisAlignment, CrossAxisAlignment.stretch);
    expect(column.mainAxisSize, MainAxisSize.max);
    expect(find.byType(OutlinedButton), findsNothing);
  });
  for (final width in [1280.0, 1440.0, 700.0]) {
    testWidgets('shared room member card menu at width $width', (tester) async {
      size(tester, Size(width, 900));
      final port = LayoutRoomPort(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      await tester.pump();
      final boundary = GlobalKey();
      Widget panel() => app(
        RepaintBoundary(
          key: boundary,
          child: MenuRoomsPanel(
            view: MenuFeatureView.parse(views.last),
            onAction: session.act,
          ),
        ),
      );
      await tester.pumpWidget(panel());
      await tester.pumpAndSettle();
      expect(find.byType(RoomMemberMenu), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RoomMemberBanner),
          matching: find.byType(RoomMemberMenu),
        ),
        findsOneWidget,
      );
      expect(find.text('移出房间'), findsNothing);
      final leave = find.widgetWithText(OutlinedButton, '退出房间');
      final settings = find.byKey(const ValueKey('menu-room-settings'));
      expect(tester.getSize(leave).width, lessThan(200));
      expect(tester.getTopLeft(leave).dy, tester.getTopLeft(settings).dy);
      await capture(
        tester,
        boundary,
        'menu-room-member-layout-${width.toInt()}',
      );
      await tester.ensureVisible(find.byType(RoomMemberMenu));
      await tester.tap(find.byType(RoomMemberMenu));
      await tester.pumpAndSettle();
      expect(find.text('移出房间'), findsOneWidget);
      await capture(tester, boundary, 'menu-room-member-menu-${width.toInt()}');
      await tester.tap(find.text('移出房间'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(port.calls, isEmpty);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(port.calls, isEmpty);
      // A menu already displayed cannot outlive the capability that produced it.
      await tester.tap(find.byType(RoomMemberMenu));
      await tester.pumpAndSettle();
      port.host = false;
      await session.refresh(silent: true);
      await tester.pumpWidget(panel());
      await tester.pumpAndSettle();
      final stale = find.text('移出房间');
      if (stale.evaluate().isNotEmpty) {
        await tester.tap(stale);
        await tester.pumpAndSettle();
      }
      expect(port.calls, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });
  }
}
