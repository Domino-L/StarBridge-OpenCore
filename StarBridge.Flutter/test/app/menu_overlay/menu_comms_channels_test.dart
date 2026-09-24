import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_channel_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';
import 'package:starbridge_flutter/features/party_rooms/example_party_rooms_adapter.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;

Map<String, Object?> channel({
  int revision = 0,
  String status = 'idle',
  String scope = 's1',
}) => {
  'state': 'ready',
  'scope': scope,
  'title': '远航者 · 组织频道',
  'buttons': [
    {'key': 'a1', 'label': '发送消息', 'limit': 1000},
  ],
  'rows': [
    {'title': '北辰', 'detail': '准备好后在奥里森集合。'},
    {'title': '远航者', 'detail': '收到，我会先检查补给。'},
  ],
  'chat': {
    'status': status,
    'revision': revision,
    'receipts': {'0': 'a2'},
    'messages': [
      for (final self in [false, true])
        {'self': self, 'time': '2026-09-23T18:20:00Z'},
    ],
  },
};

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'organization channel uses isolated selection and explicit send',
    (tester) async {
      final views = <Map<String, Object?>>[];
      final session = MenuOrganizationsSession(
        ExampleCommunities(),
        views.add,
        chatOnly: true,
      )..show(true);
      await tester.pump();
      var view = MenuFeatureView.parse(views.last);
      session.act(view.rows.first.buttons.single.key, '');
      await tester.pump();
      view = MenuFeatureView.parse(views.last);
      expect(view.state, 'ready');
      expect(view.organization!.tab, 'chat');
      expect(view.chat!.messages.length, view.rows.length);
      expect(view.buttons.where((a) => a.label == '成员'), isEmpty);
      final send = view.buttons.singleWhere((a) => a.label == '发送消息');
      session.act(send.key, 'synthetic channel message');
      session.act(send.key, 'synthetic channel message');
      await tester.pump();
      view = MenuFeatureView.parse(views.last);
      expect(view.chat!.status, 'sent');
      expect(view.chat!.revision, 1);
      expect(
        view.rows.where((r) => r.detail == 'synthetic channel message'),
        hasLength(1),
      );
      expect(jsonEncode(views.last), isNot(contains('messageRef')));
      session.dispose();
    },
  );
  testWidgets('room channel never joins a room on open', (tester) async {
    final views = <Map<String, Object?>>[], port = ExamplePartyRoomsAdapter();
    final session = MenuRoomsSession(port, views.add, chatOnly: true)
      ..show(true);
    await tester.pump();
    final view = MenuFeatureView.parse(views.last);
    expect(view.state, 'ready');
    expect(view.notice, contains('尚未加入房间'));
    expect(view.buttons, isEmpty);
    expect((await port.read()).directory!.currentRoomId, isNull);
    session.dispose();
  });
  test('channel projection rejects mismatched metadata and self receipts', () {
    final raw = channel();
    (raw['chat'] as Map)['messages'] = [];
    expect(MenuFeatureView.parse(raw).state, 'unavailable');
    final selfReceipt = channel();
    (selfReceipt['chat'] as Map)['receipts'] = {'1': 'a2'};
    expect(MenuFeatureView.parse(selfReceipt).state, 'unavailable');
    expect(
      MenuFeatureView.envelope(
        jsonEncode({...channel(), 'tool': 'organizationChat'}),
      )?.$1,
      'organizationChat',
    );
  });
  testWidgets(
    'fixed channel composer keeps rejected draft and clears only confirmed sends',
    (tester) async {
      size(tester, const Size(940, 700));
      final actions = <String>[];
      final boundary = GlobalKey();
      Future<void> render(
        Map<String, Object?> value, {
        bool active = true,
      }) async {
        await tester.pumpWidget(
          app(
            RepaintBoundary(
              key: boundary,
              child: MenuChannelPanel(
                view: MenuFeatureView.parse(value),
                active: active,
                onAction: (key, text) => actions.add('$key:$text'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await render(channel(), active: false);
      expect(actions, isEmpty, reason: 'hidden channel does not mark read');
      await render(channel());
      expect(actions, ['a2:']);
      await tester.enterText(
        find.byKey(const ValueKey('menu-channel-draft')),
        '准备出发',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('menu-channel-send')));
      await tester.pump();
      expect(actions.last, 'a1:准备出发');
      await render(channel(status: 'rejected'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '准备出发',
      );
      await tester.tap(find.byKey(const ValueKey('menu-channel-send')));
      await render(channel(revision: 1, status: 'sent'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await capture(tester, boundary, 'menu-comms-channel-ready');
      await tester.enterText(find.byType(TextField), 'private draft');
      await render(channel(scope: 's2'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('channel remains scrollable at small size and 200 percent text', (
    tester,
  ) async {
    size(tester, const Size(320, 240));
    await tester.pumpWidget(
      app(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MenuChannelPanel(
            view: MenuFeatureView.parse(channel()),
            active: false,
            onAction: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
