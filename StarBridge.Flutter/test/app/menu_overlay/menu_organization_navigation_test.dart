import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_sections.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_presentation.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_port.dart';
import 'package:starbridge_flutter/features/communities/community_member_banner.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;
import 'menu_organizations_test.dart' show fixture;

class DisconnectedSections
    implements
        CommunitiesPort,
        CommunityChatPort,
        CommunityShipsPort,
        CommunityAnnouncementsPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
  @override
  bool get chatAvailable => false;
  @override
  bool get shipsAvailable => false;
  @override
  bool get announcementsAvailable => false;
}

void main() {
  setUpAll(loadFonts);
  Map<String, Object?> data() {
    final value = fixture();
    (value['organization'] as Map)['navigation'] = [
      {
        'name': '第一组织',
        'summary': '领航员：集合',
        'time': '9/28 12:30',
        'unread': 2,
        'selected': true,
        'key': 'a20',
      },
      {
        'name': '第二组织',
        'summary': '暂无消息',
        'time': '',
        'unread': 0,
        'selected': false,
        'key': 'a21',
      },
    ];
    return value;
  }

  testWidgets(
    'wide organization sidebar has previews and direct scoped selection',
    (tester) async {
      size(tester, const Size(1250, 820));
      final actions = <String>[], shot = GlobalKey();
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: shot,
            child: MenuOrganizationsPanel(
              view: MenuFeatureView.parse(data()),
              onAction: (key, _) => actions.add(key),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('领航员：集合'), findsOneWidget);
      expect(find.text('进入组织'), findsNothing);
      expect(find.text('切换组织'), findsNothing);
      await capture(tester, shot, 'menu-organizations-sidebar');
      await tester.tap(find.text('第二组织'));
      expect(actions, ['a21']);
      await tester.enterText(
        find.byKey(const ValueKey('menu-organization-search')),
        '第一',
      );
      await tester.pumpAndSettle();
      expect(find.text('第二组织'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('narrow layout switches to organization list and back', (
    tester,
  ) async {
    size(tester, const Size(420, 700));
    final actions = <String>[];
    await tester.pumpWidget(
      app(
        MenuOrganizationsPanel(
          view: MenuFeatureView.parse(data()),
          onAction: (key, _) => actions.add(key),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('第二组织'), findsNothing);
    await tester.tap(find.text('组织列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二组织'));
    await tester.pumpAndSettle();
    expect(actions, ['a21']);
    expect(find.text('第二组织'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'default 900px organization keeps sidebar and adapts content width',
    (tester) async {
      size(tester, const Size(900, 700));
      final shot = GlobalKey();
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: shot,
            child: MenuOrganizationsPanel(
              view: MenuFeatureView.parse(data()),
              onAction: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('第二组织'), findsOneWidget);
      expect(find.text('组织列表'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(CommunityMemberHeader),
          matching: find.text('成员'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, shot, 'menu-organization-client-default-width');
    },
  );
  testWidgets('section identity is independent of producer wording', (
    tester,
  ) async {
    size(tester, const Size(900, 700));
    final value = data();
    for (final button in value['buttons'] as List) {
      button['label'] = 'changed wording';
    }
    final actions = <String>[];
    await tester.pumpWidget(
      app(
        MenuOrganizationsPanel(
          view: MenuFeatureView.parse(value),
          onAction: (key, _) => actions.add(key),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final chat = find.byKey(const ValueKey('community-section-chat'));
    expect(chat, findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('community-section-members')),
          )
          .selected,
      isTrue,
    );
    await tester.tap(chat);
    expect(actions, ['a5']);
    actions.clear();
    await tester.tap(find.byKey(const ValueKey('community-section-members')));
    expect(actions, isEmpty);
  });
  testWidgets(
    'refresh retains disabled section identities without stale actions',
    (tester) async {
      size(tester, const Size(900, 700));
      final refreshed = organizationRefreshingView(data(), const []);
      final parsed = MenuFeatureView.parse(refreshed);
      expect(parsed.state, 'ready');
      expect(parsed.organization!.sections.values, everyElement(isNull));
      final actions = <String>[];
      await tester.pumpWidget(
        app(
          MenuOrganizationsPanel(
            view: parsed,
            onAction: (key, _) => actions.add(key),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final chip = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('community-section-chat')),
      );
      expect(chip.onSelected, isNull);
      expect(find.byTooltip('此功能尚未接入当前客户端。'), findsNothing);
      expect(actions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'section projection rejects unknown ids and missing authorized actions',
    () {
      for (final sections in [
        {'admin': 'a2'},
        {'members': 'a99'},
        {'members': 'not-an-action'},
      ]) {
        final value = data();
        (value['organization'] as Map)['sections'] = sections;
        expect(MenuFeatureView.parse(value).state, 'unavailable');
      }
    },
  );
  test('navigation rejects untrusted images and invalid unread counts', () {
    for (final invalid in [-1, 501, '2']) {
      final value = data();
      ((value['organization'] as Map)['navigation'] as List).first['unread'] =
          invalid;
      expect(MenuFeatureView.parse(value).state, 'unavailable');
    }
    final value = data();
    ((value['organization'] as Map)['navigation'] as List).first['avatar'] =
        'https://invalid.example/a';
    expect(MenuFeatureView.parse(value).state, 'unavailable');
  });
  test('menu sections use the same connected feature flags as client', () {
    final port = DisconnectedSections();
    expect(organizationSections(port), {'members': '成员'});
  });
  testWidgets('sidebar breakpoints and large text preserve access', (
    tester,
  ) async {
    for (final (width, scale, sidebar) in [
      (859.0, 1.0, false),
      (860.0, 1.0, true),
      (1099.0, 1.3, true),
      (1100.0, 1.0, true),
      (1100.0, 1.31, false),
    ]) {
      size(tester, Size(width, 700));
      await tester.pumpWidget(
        app(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: MenuOrganizationsPanel(
              view: MenuFeatureView.parse(data()),
              onAction: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('第二组织'), sidebar ? findsOneWidget : findsNothing);
      expect(
        find.byKey(const ValueKey('community-section-chat')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
    'first organization window fits small desktop and preserves manual placement',
    (tester) async {
      size(tester, const Size(1093, 614));
      await tester.pumpWidget(
        app(
          MenuBridgePreview(
            visible: true,
            onDismiss: () {},
            onFeatureVisible: (_, _) {},
            onFeatureAction: (_, _, _) {},
            features: {'organizations': MenuFeatureView.parse(data())},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-tool-group')));
      await tester.pumpAndSettle();
      final panel = find.byKey(const ValueKey('menu-panel-organizations'));
      final bounds = tester.getRect(panel);
      expect(bounds.bottom, lessThanOrEqualTo(514));
      expect(bounds.right, lessThanOrEqualTo(1093));
      await tester.drag(
        find.byKey(const ValueKey('menu-move-organizations')),
        const Offset(-40, -20),
      );
      await tester.pumpAndSettle();
      final moved = tester.getRect(panel);
      await tester.tap(find.byKey(const ValueKey('menu-close-organizations')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-tool-group')));
      await tester.pumpAndSettle();
      expect(tester.getRect(panel), moved);
      expect(tester.takeException(), isNull);
    },
  );
}
