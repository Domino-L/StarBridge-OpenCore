import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_channel_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_style.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_history.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_session.dart';

import '../../features/friends/social_layout_test.dart' show app, size;
import 'menu_comms_channels_test.dart' show channel;
import 'menu_channel_media_session_test.dart' show PhotoPort;

void main() {
  testWidgets(
    'channel avatars open menus then resolve the selected sender only',
    (tester) async {
      size(tester, const Size(900, 740));
      final raw = channel(), opened = <String>[];
      (raw['chat'] as Map)['profiles'] = {'0': 'om1', '1': 'om2'};
      await tester.pumpWidget(
        app(
          MenuChannelPanel(
            view: MenuFeatureView.parse(raw),
            active: false,
            onAction: (_, _) => fail('Avatar must not send or mark messages'),
            onProfile: opened.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final entry in {'北辰': 'om1', '我': 'om2'}.entries) {
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is BridgeMenuAction && w.label == '${entry.key} · 头像菜单',
          ),
        );
        await tester.pumpAndSettle();
        expect(opened.length, entry.key == '北辰' ? 0 : 1);
        await tester.tap(find.text('查看个人页面'));
        await tester.pumpAndSettle();
        expect(opened.last, entry.value);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('private self avatar does not reuse the peer target', (
    tester,
  ) async {
    size(tester, const Size(900, 740));
    final opened = <String>[];
    await tester.pumpWidget(
      app(
        MenuCommsHistory(
          view: MenuCommsView(
            'ready',
            name: 'Peer',
            profileKey: 'c1',
            messages: [
              (
                incoming: false,
                text: 'Own message',
                time: DateTime.utc(2026),
                attachment: false,
              ),
            ],
          ),
          active: false,
          onAction: (_, _) {},
          onProfile: opened.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is BridgeMenuAction && w.label == '我 · 头像菜单',
      ),
    );
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    await tester.tap(find.text('查看个人页面'));
    await tester.pumpAndSettle();
    expect(opened, ['self']);
  });

  testWidgets(
    'archive without authenticated sender refs has no guessed target',
    (tester) async {
      size(tester, const Size(900, 740));
      await tester.pumpWidget(
        app(
          MenuChannelPanel(
            view: MenuFeatureView.parse(channel()),
            active: false,
            onAction: (_, _) {},
            onProfile: (_) => fail('No sender authority'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MenuAnchor), findsNothing);
    },
  );

  test(
    'channel profile codec rejects authority refs and invalid row indices',
    () {
      for (final profiles in [
        {'0': 'private-sender'},
        {'2': 'om1'},
        {'-1': 'om1'},
      ]) {
        final raw = channel();
        (raw['chat'] as Map)['profiles'] = profiles;
        expect(MenuFeatureView.parse(raw).state, 'unavailable');
      }
    },
  );

  test(
    'sender keys survive quiet polls but retire on hide and account change',
    () async {
      final port = PhotoPort(), views = <MenuFeatureView>[];
      final directory = Completer<MenuFeatureView>(),
          ready = Completer<MenuFeatureView>();
      final session = MenuOrganizationsSession(port, (raw) {
        final view = MenuFeatureView.parse(raw);
        views.add(view);
        if (view.organization?.tab == 'directory' && !directory.isCompleted) {
          directory.complete(view);
        }
        if (view.chat != null &&
            view.chat!.profiles.length == 2 &&
            !ready.isCompleted) {
          ready.complete(view);
        }
        expect(jsonEncode(raw), isNot(contains('senderRef')));
      }, chatOnly: true);
      addTearDown(session.dispose);
      session.show(true);
      session.act(
        (await directory.future).channels.single.buttons.single.key,
        '',
      );
      final first = await ready.future.timeout(const Duration(seconds: 5));
      final otherKey = first.chat!.profiles[0]!,
          ownKey = first.chat!.profiles[1]!;
      expect(session.profileTarget(otherKey)!.source, 'community');
      expect(session.profileTarget(otherKey)!.reference, 'd' * 32);
      expect(session.profileTarget(otherKey)!.contextRef, 'a' * 32);
      expect(session.profileTarget(ownKey)!.source, 'self');
      expect(session.profileTarget(ownKey)!.reference, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      port.chatGate = Completer<void>();
      final pending = session.refresh(silent: true);
      expect(session.profileTarget(otherKey), isNotNull);
      port.chatGate!.complete();
      await pending;
      expect(views.last.chat!.profiles[0], otherKey);
      session.show(false);
      expect(session.profileTarget(otherKey), isNull);
      final target = session.profileTarget(ownKey);
      expect(target, isNull);
      port.changes.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(session.profileTarget(otherKey), isNull);
    },
  );
}
