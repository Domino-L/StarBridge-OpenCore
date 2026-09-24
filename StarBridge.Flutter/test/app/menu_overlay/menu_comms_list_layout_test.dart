import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';

import 'menu_comms_maturity_test.dart' show fixture;
import 'menu_comms_channels_test.dart' show channel;
import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;

MenuFeatureView organization() => MenuFeatureView.parse({
  ...channel(),
  'channels': [
    {
      'title': '远航者组织',
      'detail': '当前组织频道',
      'avatar': 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      'buttons': [
        {'key': 'a8', 'label': '打开组织会话', 'limit': 128},
      ],
    },
    {
      'title': '深空探索协会',
      'detail': '组织频道',
      'buttons': [
        {'key': 'a9', 'label': '打开组织会话', 'limit': 128},
      ],
    },
  ],
});

void main() {
  setUp(
    () =>
        TestWidgetsFlutterBinding
            .instance
            .platformDispatcher
            .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
          disableAnimations: true,
        ),
  );
  tearDown(
    () => TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearAccessibilityFeaturesTestValue(),
  );
  setUpAll(loadFonts);
  testWidgets(
    'one left conversation list switches right chat without channel tabs',
    (tester) async {
      size(tester, const Size(980, 720));
      final boundary = GlobalKey(), actions = <String>[];
      var org = false;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, update) => RepaintBoundary(
              key: boundary,
              child: MenuCommsPanel(
                embedded: true,
                active: true,
                view: fixture(count: 4),
                organization: organization(),
                organizationSelected: org,
                onConversationKind: (kind) =>
                    update(() => org = kind == 'organizationChat'),
                onOrganizationAction: (key, value) =>
                    actions.add('org:$key:$value'),
                onAction: (key, value) => actions.add('private:$key:$value'),
                onCompose: (_, _, _, _) {},
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('menu-conversation-list'));
      final logo = tester.widget<MenuInlineAvatar>(
        find.descendant(
          of: find.byKey(
            const ValueKey('menu-organization-conversation-远航者组织'),
          ),
          matching: find.byType(MenuInlineAvatar),
        ),
      );
      expect(logo.source, organization().channels.first.avatar);
      expect(
        tester.getRect(list).right,
        lessThan(
          tester.getRect(find.byKey(const ValueKey('menu-message-draft'))).left,
        ),
      );
      expect(find.text('房间聊天'), findsNothing);
      expect(
        find.byKey(const ValueKey('menu-comms-tab-private')),
        findsNothing,
      );
      await tester.tap(find.text('远航者组织'));
      await tester.pumpAndSettle();
      expect(actions, contains('org:a8:'));
      expect(
        find.byKey(const ValueKey('menu-conversation-c1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('menu-channel-draft')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('menu-channel-draft')),
        '组织草稿',
      );
      await tester.pump();
      await capture(tester, boundary, 'menu-comms-unified-list');
      await tester.tap(find.byKey(const ValueKey('menu-conversation-c2')));
      await tester.pumpAndSettle();
      expect(org, isFalse);
      expect(actions, contains('private:select:c2'));
      await tester.tap(find.text('远航者组织'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('menu-channel-draft')))
            .controller!
            .text,
        '组织草稿',
      );
      await tester.enterText(
        find.byKey(const ValueKey('menu-comms-search')),
        '深空',
      );
      await tester.pumpAndSettle();
      expect(find.text('远航者组织'), findsNothing);
      expect(find.text('深空探索协会'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'opening communications loads its two sources but never room chat',
    (tester) async {
      size(tester, const Size(1400, 900));
      final leases = <String>[];
      await tester.pumpWidget(
        app(
          MenuBridgePreview(
            visible: true,
            onDismiss: () {},
            friends: const MenuFriendsView('ready'),
            comms: fixture(),
            onCommsAction: (_, _) {},
            onFeatureAction: (_, _, _) {},
            onFeatureVisible: (tool, shown) {
              if (shown) leases.add(tool);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-tool-chat')));
      await tester.pumpAndSettle();
      expect(leases, ['organizationChat']);
      expect(find.text('房间聊天'), findsNothing);
      expect(
        find.byKey(const ValueKey('menu-comms-tab-private')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
