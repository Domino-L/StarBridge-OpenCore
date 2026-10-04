import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'menu_friends_session_test.dart' show Port;
import '../../features/friends/social_layout_test.dart' show app, size;

void main() {
  for (final state in ['InGame', 'Offline', null]) {
    testWidgets('authorized friend game detail projection with presence $state', (tester) async {
      final port = Port();
      final views = <Map<String, Object?>>[];
      final session = MenuFriendsSession(port, views.add);
      session.show(true);
      port.reads.single.complete(FriendsReadResult(FriendsReadState.ready,
        snapshot: FriendsSnapshot(groups: {FriendsSection.friends: [
          FriendRow('Fixture', 'fixture', 'friend', DateTime(2026), targetRef: 'fixture-ref', shared: {
            'presence': state, 'serverId': 'fixture-server', 'serverRegion': 'US',
            'location': 'fixture-location', 'ship': 'fixture-ship', 'secret': 'never-forward',
          }, sharedLabels: {
            'location': {'zhHans': '测试地点', 'en': 'Fixture location'},
            'ship': {'zhHans': '测试飞船', 'en': 'Fixture ship'},
          }),
        ]}, results: [])));
      await tester.pump();
      final row = (views.last['rows'] as List).single as Map;
      if (state == 'InGame') {
        expect((row['details'] as Map?)?['serverId'], 'fixture-server');
        expect((row['details'] as Map?)?['location'], 'fixture-location');
        expect(jsonEncode(row), contains('测试地点'));
        size(tester, const Size(392, 640));
        await tester.pumpWidget(app(MenuFriendsPanel(
          view: MenuFriendsView.parse(jsonEncode(views.last)),
          embedded: true, onClose: () {},
        )));
        await tester.pumpAndSettle();
        expect(find.text('fixture-server'), findsOneWidget);
        expect(find.text('测试地点'), findsOneWidget);
        expect(find.text('测试飞船'), findsOneWidget);
        expect(find.text('fixture-ship'), findsNothing);
        final strings = AppStrings.of(tester.element(find.byType(MenuFriendsPanel)));
        final region = find.text(strings.text('gameLog.regionUS'));
        expect(region, findsOneWidget);
        expect(find.text('US'), findsNothing);
        expect(
          tester.getTopLeft(find.text('fixture-server')).dy,
          closeTo(tester.getTopLeft(region).dy, 1),
          reason: 'Authorized game details should share a compact row when there is room.',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } else {
        expect(row['details'], isNull);
      }
      expect(jsonEncode(row), isNot(contains('never-forward')));
      session.dispose();
      await tester.pump();
    });
  }
}
