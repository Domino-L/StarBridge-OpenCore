import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_style.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/app/shell/chrome/presence_color.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, capture, loadFonts;
import 'menu_friend_commands_test.dart' show CommandPort, directory, answer;

const roster = MenuFriendsView(
  'ready',
  interactive: true,
  incoming: 1,
  identity: (name: '远航者', handle: 'Pathfinder', avatar: null),
  self: (
    key: 'self1',
    status: 'presence.online',
    change: true,
    busy: false,
    failed: false,
  ),
  rows: [
    (name: '北辰', presence: 'inGame', key: 'f1', avatar: null),
    (name: '白鸦', presence: 'online', key: 'f2', avatar: null),
    (name: '回声', presence: 'away', key: 'f3', avatar: null),
    (name: '长夜', presence: 'offline', key: 'f4', avatar: null),
    (name: '无共享状态', presence: 'unknown', key: 'f5', avatar: null),
  ],
  requests: [(name: '新朋友', presence: 'unknown', key: 'f6', avatar: null)],
  actions: {
    'f6': ['accept', 'reject'],
    'f1': ['remove', 'block'],
  },
  chatKeys: {'f1', 'f2', 'f3', 'f4'},
);

void main() {
  setUpAll(loadFonts);
  test(
    'menu presence reuses client status tokens rather than decorative cyan',
    () {
      final colors = FutureRestraintStyle.resolve(AppearanceMode.dark).colors;
      for (final state in ['online', 'inGame', 'away', 'offline']) {
        expect(
          menuPresenceColor(state),
          presenceColor(colors, 'presence.$state'),
        );
      }
      expect(menuPresenceColor('online'), const Color(0xff53b7ff));
      expect(menuPresenceColor('online'), isNot(BridgeInk.blue));
      expect(menuPresenceColor('invisible'), colors.offline);
      expect(menuPresenceColor('unknown'), BridgeInk.muted);
    },
  );
  testWidgets(
    'account scope changes clear local search without clearing ordinary refresh drafts',
    (tester) async {
      Future<void> subject(String scope) => tester.pumpWidget(
        app(
          SizedBox(
            width: 340,
            child: MenuFriendsPanel(
              embedded: true,
              onClose: () {},
              onAction: (_, _, _) {},
              view: MenuFriendsView(
                'ready',
                interactive: true,
                scope: scope,
                rows: roster.rows,
              ),
            ),
          ),
        ),
      );
      await subject('friends1');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('friends-account-search')),
        'private draft',
      );
      await subject('friends1');
      await tester.pumpAndSettle();
      expect(find.text('private draft'), findsOneWidget);
      await subject('friends2');
      await tester.pumpAndSettle();
      expect(find.text('private draft'), findsNothing);
      expect(find.text('北辰'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'WPF roster order, direct request actions, single search and avatar menu',
    (tester) async {
      size(tester, const Size(900, 1000));
      final actions = <String>[], chats = <String>[];
      final shot = GlobalKey();
      await tester.pumpWidget(
        app(
          Center(
            child: RepaintBoundary(
              key: shot,
              child: SizedBox(
                width: 340,
                height: 900,
                child: ColoredBox(
                  color: BridgeInk.window,
                  child: MenuFriendsPanel(
                    view: roster,
                    onClose: () {},
                    onChat: chats.add,
                    onProfile: (_) {},
                    onAction: (a, k, v) => actions.add('$a/$k/$v'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Pathfinder'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('新朋友')).dy,
        lessThan(tester.getTopLeft(find.text('北辰')).dy),
      );
      expect(find.text('状态未共享 · 1'), findsOneWidget);
      expect(find.text('▾ 离线 · 1'), findsOneWidget);
      await capture(tester, shot, 'menu-friends-wpf-structure');
      await tester.tap(find.byKey(const ValueKey('friend-inline-accept-f6')));
      expect(actions, [
        'prepare/f6/accept',
      ]); // never executes without confirmation
      await tester.tap(find.byKey(const ValueKey('friend-open-f1')));
      expect(chats, ['f1']);
      await tester.tap(find.byKey(const ValueKey('f1')));
      await tester.pumpAndSettle();
      expect(chats, ['f1']);
      expect(find.text('查看个人页面'), findsOneWidget);
      expect(find.byKey(const ValueKey('friend-remove-f1')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('friends-account-search')),
        '北辰',
      );
      await tester.pumpAndSettle();
      expect(find.text('白鸦'), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      expect(actions.last, 'search//北辰');
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('short friend window remains scrollable at text scale $scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: SizedBox(
              width: 300,
              height: 132,
              child: MenuFriendsPanel(
                view: roster,
                embedded: true,
                onClose: () {},
                onAction: (_, _, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('friend-row-f4')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'requests use opaque validated targets alongside roster, preserved controls on loading',
    (tester) async {
      final port = CommandPort(), views = <Map<String, Object?>>[];
      final session = MenuFriendsSession(
        port,
        views.add,
        identity: () => (
          name: 'Me',
          handle: 'fixture',
          avatar: 'https://not-forwarded.invalid/image',
        ),
      );
      session.show(true);
      final incoming = directory('incoming').groups[FriendsSection.incoming]!;
      answer(
        port,
        FriendsSnapshot(
          groups: {
            FriendsSection.friends: directory(
              'friend',
              ref: 'private-friend',
            ).groups[FriendsSection.friends]!,
            FriendsSection.incoming: incoming,
          },
          results: [],
        ),
      );
      await tester.pump();
      final wire = jsonEncode(views.last), view = MenuFriendsView.parse(wire);
      expect(view.rows.length, 1);
      expect(view.requests.length, 1);
      expect(view.identity?.avatar, isNull);
      expect(wire, isNot(contains('private-ref')));
      expect(wire, isNot(contains('private-friend')));
      final request = view.requests.single.key!;
      session.act('prepare', request, 'accept');
      final pending = MenuFriendsView.parse(jsonEncode(views.last));
      expect(pending.confirmation?.action, 'accept');
      expect(port.writes, isEmpty);
      session.act('search', '', 'fixture');
      final loading = MenuFriendsView.parse(jsonEncode(views.last));
      expect(loading.state, 'loading');
      expect(loading.interactive, true);
      expect(loading.query, 'fixture');
      expect(loading.requests, isEmpty);
      expect(loading.actions, isEmpty);
      expect(session.profileTarget(request), isNull);
      session.dispose();
      await tester.pump(const Duration(seconds: 20));
    },
  );

  testWidgets(
    'floating windows paint and receive input above fixed menu chrome',
    (tester) async {
      size(tester, const Size(1600, 900));
      var dismissed = 0;
      await tester.pumpWidget(
        app(
          MenuBridgePreview(
            visible: true,
            onDismiss: () => dismissed++,
            friends: const MenuFriendsView('ready'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-tool-friends')));
      await tester.pumpAndSettle();
      final panel = find.byKey(const ValueKey('menu-panel-friends'));
      expect(tester.widget<Material>(panel).color, BridgeInk.window);
      expect(BridgeInk.window.a, greaterThan(.95));
      final returnPoint = tester.getCenter(
        find.byKey(const ValueKey('menu-return')),
      );
      final original = tester.getRect(panel);
      // Put the window over the return button, but below its own title bar.
      await tester.drag(
        find.byKey(const ValueKey('menu-move-friends')),
        Offset(
          returnPoint.dx - 150 - original.left,
          returnPoint.dy - 100 - original.top,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(panel).contains(returnPoint), true);
      await tester.tapAt(returnPoint);
      await tester.pumpAndSettle();
      expect(dismissed, 0);
      // Bring the title bar back, then close; uncovered controls work again.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(dismissed, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
