import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';

import 'menu_room_management_test.dart' show RoomPort;
import '../../features/friends/social_layout_test.dart' show app, size, loadFonts;

void main() {
  setUpAll(loadFonts);
  testWidgets('membership loss returns to lobby even when former room is listed', (tester) async {
    final port = RoomPort();
    final frames = <Map<String, Object?>>[];
    final session = MenuRoomsSession(port, frames.add)..show(true);
    addTearDown(session.dispose);
    await tester.pump();
    final joined = MenuFeatureView.parse(frames.last);
    expect(joined.room, isNotNull);
    port.joined = false;
    await session.refresh();
    final left = MenuFeatureView.parse(frames.last);
    expect(left.room, isNull);
    expect(left.lobby, isNotNull);
    expect(left.scope, isNot(joined.scope));
    expect(left.buttons.where((b) => b.label == '加入房间'), isEmpty);
    await session.refresh();
    expect(MenuFeatureView.parse(frames.last).lobby, isNotNull);
    expect(port.calls, isEmpty);
    size(tester, const Size(1280, 900));
    await tester.pumpWidget(app(MenuRoomsPanel(view: left, onAction: session.act)));
    await tester.pumpAndSettle();
    expect(find.text('返回房间列表'), findsNothing);
    expect(find.text('房间成员'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
