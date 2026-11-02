import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_avatar_actions.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_panel.dart';
import 'package:starbridge_flutter/features/common/organization_member_board.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';

import '../../features/friends/social_layout_test.dart'
    show app, loadFonts, size;

Map<String, Object?> _fixture() => {
  'state': 'ready',
  'scope': 'fixture-org',
  'title': 'Fixture organization',
  'buttons': [
    {
      'key': 'a1',
      'label': '搜索成员',
      'role': 'searchMembers',
      'input': 'Search members',
      'limit': 128,
    },
    {'key': 'a2', 'label': '下一页', 'role': 'nextPage', 'limit': 128},
  ],
  'rows': [
    for (var i = 0; i < 4; i++) {'title': 'Fixture pilot $i', 'detail': ''},
  ],
  'organization': {
    'tab': 'members',
    'total': 24,
    'matched': 24,
    'offset': 0,
    'rows': [
      for (final (i, presence) in [
        'inGame',
        'online',
        'offline',
        'unknown',
      ].indexed)
        {
          'handle': 'fixture-$i',
          'role': 'Fixture role',
          'roleColor': '#00FF00',
          'presence': presence,
          'server': presence == 'inGame' ? 'Fixture server' : '未进入游戏',
          'ship': presence == 'inGame' ? 'Fixture ship' : '未进入游戏',
          'location': presence == 'inGame' ? 'Fixture location' : '未进入游戏',
          if (i == 0) 'profileKey': 'om1',
        },
    ],
  },
};

void main() {
  setUpAll(loadFonts);

  testWidgets('menu member surface reuses the shared organization board', (
    tester,
  ) async {
    size(tester, const Size(1400, 1000));
    final view = MenuFeatureView.parse(_fixture());
    expect(
      view.state,
      'ready',
      reason: 'The source protocol still accepts unknown presence',
    );
    await tester.pumpWidget(
      app(MenuOrganizationsPanel(view: view, onAction: (_, _) {})),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OrganizationMemberBoard), findsOneWidget);
    expect(find.byType(OrganizationMemberRow), findsNWidgets(4));
    final unknown = find.byType(OrganizationMemberRow).last;
    expect(
      find.descendant(of: unknown, matching: find.text('离线')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: unknown, matching: find.text('未进入游戏')),
      findsNWidgets(3),
    );
    expect(find.text('未进入游戏'), findsNWidgets(9));
    expect(
      find.descendant(of: unknown, matching: find.text('—')),
      findsNothing,
    );
  });

  testWidgets('only trusted identity clicks use the existing profile action', (
    tester,
  ) async {
    size(tester, const Size(1400, 1000));
    final profiles = <String>[], actions = <String>[];
    await tester.pumpWidget(
      app(
        MenuOrganizationsPanel(
          view: MenuFeatureView.parse(_fixture()),
          onAction: (key, value) => actions.add('$key:$value'),
          onProfile: profiles.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MenuAvatarActions), findsOneWidget);
    await tester.tap(find.text('Fixture pilot 1'));
    await tester.tap(find.text('Fixture role').first);
    await tester.pumpAndSettle();
    expect(find.text('查看个人页面'), findsNothing);
    expect(profiles, isEmpty);
    expect(actions, isEmpty);
    await tester.tap(find.text('Fixture pilot 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看个人页面'));
    await tester.pumpAndSettle();
    expect(profiles, ['om1']);
    expect(actions, isEmpty);
  });

  testWidgets(
    'menu filters and pagination retain page scope and opaque authority',
    (tester) async {
      size(tester, const Size(1400, 1000));
      final data = _fixture();
      (data['buttons'] as List).add({
        'key': 'a3',
        'label': '首页',
        'role': 'firstPage',
        'limit': 128,
      });
      final actions = <String>[];
      await tester.pumpWidget(
        app(
          MenuOrganizationsPanel(
            view: MenuFeatureView.parse(data),
            onAction: (key, value) => actions.add('$key:$value'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-org-filter-all')), findsOneWidget);
      expect(find.byKey(const Key('menu-org-filter-online')), findsOneWidget);
      expect(find.byKey(const Key('menu-org-filter-inGame')), findsOneWidget);
      expect(find.byKey(const Key('menu-org-filter-offline')), findsNothing);
      expect(find.byKey(const Key('menu-org-previous-page')), findsNothing);
      expect(find.byKey(const Key('menu-org-page-size')), findsNothing);
      expect(find.byKey(const Key('menu-org-jump')), findsNothing);
      await tester.tap(find.byKey(const Key('menu-org-filter-online')));
      await tester.pumpAndSettle();
      expect(find.byType(OrganizationMemberRow), findsNWidgets(2));
      expect(find.textContaining('共 24 人 · 本页在线 2 · 本页游戏中 1'), findsOneWidget);
      expect(find.text('在线与游戏人数仅统计当前页'), findsNothing);
      expect(actions, isEmpty);
      await tester.ensureVisible(find.byKey(const Key('menu-org-next-page')));
      await tester.tap(find.byKey(const Key('menu-org-next-page')));
      await tester.ensureVisible(find.byKey(const Key('menu-org-first-page')));
      await tester.tap(find.byKey(const Key('menu-org-first-page')));
      expect(actions, ['a2:', 'a3:']);
    },
  );

  testWidgets(
    'refresh retains the board and disables retired profile and input actions',
    (tester) async {
      size(tester, const Size(1400, 1000));
      final data = _fixture()..['refreshing'] = true;
      final actions = <String>[], profiles = <String>[];
      await tester.pumpWidget(
        app(
          MenuOrganizationsPanel(
            view: MenuFeatureView.parse(data),
            onAction: (key, value) => actions.add('$key:$value'),
            onProfile: profiles.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(OrganizationMemberRow), findsNWidgets(4));
      expect(find.byType(MenuAvatarActions), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('menu-org-search')))
            .enabled,
        isFalse,
      );
      await tester.tap(find.text('Fixture pilot 0'));
      await tester.pumpAndSettle();
      expect(profiles, isEmpty);
      expect(actions, isEmpty);
    },
  );

  testWidgets('busy retains source footer without permitting actions', (
    tester,
  ) async {
    size(tester, const Size(1400, 1000));
    for (final state in ['busy', 'refreshing', 'bodyLoading']) {
      final data = _fixture();
      if (state == 'bodyLoading') {
        (data['organization'] as Map)['bodyLoading'] = true;
      } else {
        data[state] = true;
      }
      (data['buttons'] as List).addAll(<Map<String, Object>>[
        {'key': 'a3', 'label': '首页', 'role': 'firstPage', 'limit': 128},
        {'key': 'a4', 'label': '上一页', 'role': 'previousPage', 'limit': 128},
      ]);
      final actions = <String>[];
      await tester.pumpWidget(
        app(
          MenuOrganizationsPanel(
            key: ValueKey(state),
            view: MenuFeatureView.parse(data),
            onAction: (key, value) => actions.add('$key:$value'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(OrganizationMemberRow), findsNWidgets(4));
      for (final direction in ['first', 'previous', 'next']) {
        final key = Key('menu-org-$direction-page');
        expect(find.byKey(key), findsOneWidget);
        final button = tester
            .widgetList<StarBridgeActionButton>(
              find.byType(StarBridgeActionButton),
            )
            .singleWhere((button) => button.controlKey == key);
        expect(button.onActivate, isNull);
        await tester.ensureVisible(find.byKey(key));
        await tester.tap(find.byKey(key));
        await tester.pumpAndSettle();
      }
      expect(actions, isEmpty);
    }
  });
}
