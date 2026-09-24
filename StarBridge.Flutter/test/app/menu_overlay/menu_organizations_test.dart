import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_view.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;

Map<String, Object?> fixture({String tab = 'members'}) => {
  'state': 'ready',
  'scope': 's1',
  'title': '远航者组织',
  'buttons': [
    for (final (i, title) in ['返回组织列表', '成员', '舰船', '公告', '聊天'].indexed)
      {'key': 'a${i + 1}', 'label': title, 'limit': 128},
    {'key': 'a6', 'label': '搜索成员', 'input': '搜索成员、呼号或职务', 'limit': 128},
  ],
  'rows': [
    for (final name in ['远航者', '北辰', '回声', '白鸦']) {'title': name, 'detail': ''},
  ],
  'organization': {
    'tab': tab,
    'code': 'VOYAGER',
    'description': '一起探索、护航与远征。',
    'total': 24,
    'matched': 24,
    'offset': 0,
    'rows': [
      for (final (i, presence) in [
        'inGame',
        'online',
        'unknown',
        'offline',
      ].indexed)
        {
          'handle': 'Pilot_${i + 1}',
          'role': i == 0 ? '组织负责人' : '组织成员',
          'roleColor': i == 0 ? '#F5B544' : '#A5B8C3',
          'presence': presence,
          'ship': i == 0 ? 'C2 大力神' : '未进入游戏',
          'location': i == 0 ? '奥里森' : '未进入游戏',
          'server': i == 0 ? '美服' : '未进入游戏',
          'profileKey': 'om${i + 1}',
          'isSelf': i == 0,
        },
    ],
  },
};

void main() {
  setUpAll(loadFonts);
  Map<String, Object?> directory({bool busy = false}) => {
    'state': 'ready',
    'scope': 's2',
    'title': '我的组织',
    'busy': busy,
    'buttons': [
      {'key': 'a1', 'label': '搜索组织', 'input': '搜索已加入的组织', 'limit': 128},
    ],
    'rows': [
      for (var i = 0; i < 2; i++)
        {
          'title': i == 0 ? '远航者组织' : '深空探索协会',
          'detail': '一起探索、护航与远征。',
          'buttons': [
            {'key': 'a${i + 2}', 'label': '打开组织', 'limit': 128},
          ],
        },
    ],
    'organization': {
      'tab': 'directory',
      'total': 2,
      'matched': 2,
      'offset': 0,
      'rows': [
        for (var i = 0; i < 2; i++)
          {
            'memberCount': i == 0 ? 24 : 86,
            'relationship': i == 0 ? 'owner' : 'member',
            'language': 'zh-CN',
            'tags': '探索,贸易',
            'activeTime': '周末 19:00–23:00',
          },
      ],
    },
  };
  testWidgets(
    'client organization cards open and search with existing actions',
    (tester) async {
      size(tester, const Size(1000, 800));
      final boundary = GlobalKey(), actions = <String>[];
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: boundary,
            child: MenuOrganizationsPanel(
              view: MenuFeatureView.parse(directory()),
              onAction: (key, value) => actions.add('$key:$value'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('24 位成员'), findsOneWidget);
      expect(find.text('组织负责人'), findsOneWidget);
      await capture(tester, boundary, 'menu-organization-client-directory');
      await tester.tap(find.text('深空探索协会'));
      expect(actions, ['a3:']);
      await tester.tap(find.text('进入组织').first);
      expect(actions.last, 'a2:');
      await tester.enterText(find.byType(TextField), '远航');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(actions.last, 'a1:远航');
      await tester.pumpWidget(
        app(
          MenuOrganizationsPanel(
            view: MenuFeatureView.parse(directory(busy: true)),
            onAction: (key, value) => actions.add('$key:$value'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final count = actions.length;
      await tester.tap(find.text('深空探索协会'));
      expect(actions.length, count);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('directory compact large text remains usable', (tester) async {
    size(tester, const Size(320, 400));
    await tester.pumpWidget(
      app(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MenuOrganizationsPanel(
            view: MenuFeatureView.parse(directory()),
            onAction: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -1500),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  test('directory display rejects remote logos and invalid member counts', () {
    for (final value in [
      'https://example.invalid/logo.png',
      'data:image/png;base64,${'a' * 28000}',
    ]) {
      final source = directory();
      ((source['organization'] as Map)['rows'] as List).first['logo'] = value;
      expect(MenuFeatureView.parse(source).state, 'unavailable');
    }
    final source = directory();
    ((source['organization'] as Map)['rows'] as List).first['memberCount'] = -1;
    expect(MenuFeatureView.parse(source).state, 'unavailable');
  });
  test(
    'presence uses WPF semantics without inventing offline or same-server',
    () {
      expect(organizationPresence(true, 'AppOnline'), 'online');
      expect(organizationPresence(true, 'InGame'), 'inGame');
      expect(organizationPresence(true, 'Away'), 'away');
      for (final status in ['Paused', 'Hidden', 'Unknown', '']) {
        expect(organizationPresence(false, status), 'unknown');
      }
      expect(organizationPresence(false, 'Offline'), 'offline');
    },
  );
  test(
    'projection rejects malformed rows and never accepts arbitrary image paths',
    () {
      final source = fixture();
      expect(MenuFeatureView.parse(source).organization!.rows.length, 4);
      final org = source['organization'] as Map;
      (org['rows'] as List).first['image'] =
          'https://invalid.example/private.jpg';
      expect(
        MenuFeatureView.parse(source).organization!.rows.first.image,
        isNull,
      );
      (org['rows'] as List).first['profileKey'] = 'account-id';
      expect(MenuFeatureView.parse(source).state, 'unavailable');
      (org['rows'] as List).removeLast();
      expect(MenuFeatureView.parse(source).state, 'unavailable');
    },
  );
  testWidgets(
    'real organization adapter tabs search paging and target leases',
    (tester) async {
      final views = <Map<String, Object?>>[];
      final session = MenuOrganizationsSession(ExampleCommunities(), views.add)
        ..show(true);
      await tester.pump();
      var view = MenuFeatureView.parse(views.last);
      expect(view.state, 'ready');
      expect(view.organization!.tab, 'directory');
      expect(view.rows, isNotEmpty);
      final directoryQuery = view.rows.first.title;
      session.act(
        view.buttons.singleWhere((a) => a.label == '搜索组织').key,
        directoryQuery,
      );
      await tester.pump();
      view = MenuFeatureView.parse(views.last);
      expect(view.organization!.query, directoryQuery);
      expect(view.organization!.rows.first.memberCount, isNotNull);
      session.act(view.rows.first.buttons.single.key, '');
      await tester.pump();
      view = MenuFeatureView.parse(views.last);
      expect(view.state, 'ready');
      expect(view.organization!.tab, 'members');
      expect(view.organization!.rows[1].presence, 'online');
      expect(view.organization!.rows[3].presence, 'unknown');
      final key = view.organization!.rows.first.profileKey!;
      final target = session.profileTarget(key)!;
      expect(target.source, 'community');
      expect(target.contextRef, isNotNull);
      expect(jsonEncode(views.last), isNot(contains('memberRef')));
      expect(jsonEncode(views.last), isNot(contains('targetRef')));
      session.act(
        view.buttons.singleWhere((a) => a.label == '搜索成员').key,
        'Example_Member_1',
      );
      await tester.pump();
      view = MenuFeatureView.parse(views.last);
      expect(view.organization!.query, 'Example_Member_1');
      expect(session.profileTarget(key), isNull);
      session.act(view.buttons.singleWhere((a) => a.label == '成员').key, '');
      await tester.pump();
      view = MenuFeatureView.parse(views.last);
      expect(
        view.organization!.query,
        'Example_Member_1',
        reason: 'Re-selecting the current tab retains its search.',
      );
      for (final (tab, label) in [
        ('ships', '舰船'),
        ('announcements', '公告'),
        ('chat', '聊天'),
      ]) {
        session.act(view.buttons.singleWhere((a) => a.label == label).key, '');
        await tester.pump();
        view = MenuFeatureView.parse(views.last);
        expect(view.state, 'ready', reason: label);
        expect(view.organization!.tab, tab);
      }
      session.act(view.buttons.singleWhere((a) => a.label == '返回组织列表').key, '');
      await tester.pump();
      view = MenuFeatureView.parse(views.last);
      expect(view.organization!.tab, 'directory');
      expect(view.organization!.query, directoryQuery);
      session.show(false);
      expect(target.isCurrent(), isFalse);
      session.dispose();
      expect(target.isAccountCurrent(), isFalse);
    },
  );
  testWidgets('member columns avatar menu search and page status filters', (
    tester,
  ) async {
    size(tester, const Size(1000, 800));
    final boundary = GlobalKey(), actions = <String>[], profiles = <String>[];
    await tester.pumpWidget(
      app(
        RepaintBoundary(
          key: boundary,
          child: SizedBox(
            width: 900,
            child: MenuOrganizationsPanel(
              view: MenuFeatureView.parse(fixture()),
              onAction: (key, value) => actions.add('$key:$value'),
              onProfile: profiles.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('状态统计 · 当前页'), findsOneWidget);
    expect(find.text('服务器'), findsOneWidget);
    expect(find.text('位置'), findsOneWidget);
    await capture(tester, boundary, 'menu-organizations-wpf-structure');
    await tester.tap(find.bySemanticsLabel('远航者 · 头像菜单').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看个人页面'));
    await tester.pumpAndSettle();
    expect(profiles, ['om1']);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '北辰');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(actions, ['a6:北辰']);
    await tester.tap(find.byKey(const ValueKey('menu-org-filter-online')));
    await tester.pumpAndSettle();
    expect(
      find
          .text('北辰', findRichText: false)
          .evaluate()
          .where((e) => e.widget is Text),
      hasLength(1),
    );
    expect(find.text('回声'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('compact and enlarged text retain all fields without overflow', (
    tester,
  ) async {
    for (final scale in [1.0, 2.0]) {
      size(tester, const Size(320, 240));
      await tester.pumpWidget(
        app(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: MenuOrganizationsPanel(
              view: MenuFeatureView.parse(fixture()),
              onAction: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -2500),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
