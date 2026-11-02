import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_avatar_actions.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_channel_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_history.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_directory.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_panel.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';

import '../../app/menu_overlay/menu_comms_channels_test.dart' show channel;
import '../../app/menu_overlay/menu_organizations_test.dart' show fixture;
import '../../app/menu_overlay/menu_friend_commands_test.dart'
    show CommandPort, answer, directory;
import '../../features/friends/social_layout_test.dart' show size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3ci_test.dart' show row, choose;
import 'interaction_batch3ca_test.dart' show fire;

Widget profileSubject(String kind, String id, ValueChanged<String> opened) {
  final key = id == 'a' ? 'c1' : 'c2', orgKey = id == 'a' ? 'om1' : 'om9';
  if (kind == 'directory') {
    return MenuCommsDirectory(
      view: MenuCommsView(
        'ready',
        rows: [
          (
            key: key,
            name: '同名用户',
            time: DateTime.utc(2026),
            unread: 0,
            request: false,
          ),
          (
            key: id == 'a' ? 'c2' : 'c1',
            name: '同名用户',
            time: DateTime.utc(2026),
            unread: 0,
            request: false,
          ),
        ],
      ),
      query: '',
      group: 'all',
      onQuery: (_) {},
      onGroup: (_) {},
      onAction: (_, _) {},
      onProfile: opened,
    );
  }
  if (kind == 'channel') {
    final raw = channel();
    (raw['chat'] as Map)['profiles'] = {'0': orgKey, '1': 'om2'};
    return MenuChannelPanel(
      view: MenuFeatureView.parse(raw),
      active: false,
      onAction: (_, _) {},
      onProfile: opened,
    );
  }
  if (kind == 'member') {
    final raw = fixture();
    (((raw['organization'] as Map)['rows'] as List).first
            as Map)['profileKey'] =
        orgKey;
    return MenuOrganizationsPanel(
      view: MenuFeatureView.parse(raw),
      active: false,
      onAction: (_, _) {},
      onProfile: opened,
    );
  }
  return MenuCommsHistory(
    view: MenuCommsView(
      'ready',
      name: '同名用户',
      profileKey: key,
      pageKey: '$key/page',
      messages: [
        (
          incoming: true,
          text: '收到的消息',
          time: DateTime.utc(2026),
          attachment: false,
        ),
        (
          incoming: false,
          text: '发出的消息',
          time: DateTime.utc(2026),
          attachment: false,
        ),
      ],
    ),
    active: false,
    onAction: (_, _) {},
    onProfile: opened,
  );
}

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite bottom-edge history avatar keeps profile row visibly clickable',
      (t) async {
        size(t, const Size(900, 740));
        final opened = <String>[];
        await t.pumpWidget(
          scopedApp(
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
            suite,
          ),
        );
        await frames(t);
        await t.tap(
          find.byWidgetPredicate(
            (w) => w is MenuAvatarActions && w.name == '我',
          ),
        );
        await frames(t);
        // Do not scroll the menu to make an initially clipped row pass.
        final rect = t.getRect(find.text('查看个人页面'));
        expect(rect.top, greaterThanOrEqualTo(8));
        expect(rect.bottom, lessThanOrEqualTo(732));
        await t.tap(find.text('查看个人页面'));
        await frames(t);
        expect(opened, ['self']);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await frames(t);
      },
    );
    for (final kind in [
      'directory',
      'channel',
      'member',
      'history-header',
      'history-incoming',
      'history-self',
    ]) {
      testWidgets(
        '$suite actual $kind identity retires equal-looking old target',
        (t) async {
          size(t, const Size(1000, 1000));
          final target = ValueNotifier('a'), opened = <String>[];
          await t.pumpWidget(
            scopedApp(
              ValueListenableBuilder<String>(
                valueListenable: target,
                builder: (_, id, _) => profileSubject(kind, id, opened.add),
              ),
              suite,
            ),
          );
          await frames(t);
          Finder avatar() {
            final all = find.byType(MenuAvatarActions);
            if (kind == 'channel') {
              return find.byWidgetPredicate(
                (w) => w is MenuAvatarActions && w.name == '北辰',
              );
            }
            if (kind == 'history-self') {
              return find.byWidgetPredicate(
                (w) => w is MenuAvatarActions && w.name == '我',
              );
            }
            if (kind == 'history-incoming') {
              return find
                  .byWidgetPredicate(
                    (w) => w is MenuAvatarActions && w.name == '同名用户',
                  )
                  .last;
            }
            return all.first;
          }

          await t.ensureVisible(avatar());
          await frames(t);
          await t.tap(avatar());
          await frames(t);
          expect(row('avatar-profile'), findsOneWidget);
          expect(opened, isEmpty);
          target.value = 'b';
          await t.pump();
          await t.pump();
          expect(row('avatar-profile'), findsNothing);
          expect(nativeViewportMenus.value, 0);
          expect(opened, isEmpty);
          await frames(t);
          await t.ensureVisible(avatar());
          await frames(t);
          await t.tap(avatar());
          await frames(t);
          await choose(t, 'pointer', '查看个人页面', row('avatar-profile'));
          await frames(t);
          expect(opened, [
            kind == 'channel' || kind == 'member'
                ? 'om9'
                : kind == 'history-self'
                ? 'self'
                : 'c2',
          ]);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await frames(t);
          target.dispose();
        },
      );
    }
    for (final outcome in ['accepted', 'rejected', 'unknown', 'invalidated']) {
      testWidgets(
        '$suite actual friend owner $outcome keeps prepare/confirm/result authority',
        (t) async {
          size(t, const Size(900, 1000));
          final port = CommandPort(),
              view = ValueNotifier(const MenuFriendsView('idle'));
          final sources = <InteractionSource>[];
          final session = MenuFriendsSession(
            port,
            (raw) => view.value = MenuFriendsView.parse(jsonEncode(raw)),
          )..show(true);
          try {
            answer(port, directory('friend'));
            await t.pump();
            final oldKey = view.value.rows.single.key!;
            await t.pumpWidget(
              scopedApp(
                Center(
                  child: SizedBox(
                    width: 340,
                    child: ValueListenableBuilder<MenuFriendsView>(
                      valueListenable: view,
                      builder: (_, v, _) => MenuFriendsPanel(
                        view: v,
                        onClose: () {},
                        onAction: (a, k, v) {
                          sources.add(currentStarBridgeActivationSource);
                          session.act(a, k, v);
                        },
                        onProfile: (_) {},
                      ),
                    ),
                  ),
                ),
                suite,
              ),
            );
            await frames(t);
            await t.tap(find.byKey(ValueKey<String>(oldKey)));
            await frames(t);
            await t.tap(find.byKey(ValueKey('friend-remove-$oldKey')));
            await frames(t);
            expect(port.writes, isEmpty);
            expect(view.value.confirmation?.action, 'remove');
            final token = view.value.confirmation!.token;
            if (outcome == 'invalidated') {
              port.events.add(null);
              await t.pump();
              await t.pump();
              session.act('confirm', token, '');
              session.act('prepare', oldKey, 'remove');
              expect(session.profileTarget(oldKey), isNull);
              expect(port.writes, isEmpty);
              expect(view.value.confirmation, isNull);
              expect(nativeViewportMenus.value, 0);
              answer(port, directory('friend', ref: 'different-private-ref'));
              await frames(t);
            } else {
              await fire(
                t,
                'pointer',
                find.byKey(ValueKey('friends-confirm-$token')),
              );
              await frames(t);
              expect(port.writes, hasLength(1));
              expect(port.writes.single.action, 'remove');
              expect(port.writes.single.ref, 'private-ref');
              expect(view.value.busy, true);
              expect(view.value.feedback, isNot('success.remove'));
              port.writes.single.result.complete(
                FriendCommandResult(
                  outcome,
                  directory: outcome == 'accepted'
                      ? directory('friend', actions: [])
                      : null,
                ),
              );
              await frames(t);
              expect(view.value.busy, false);
              expect(
                view.value.feedback,
                outcome == 'accepted' ? 'success.remove' : outcome,
              );
              expect(view.value.requiresRefresh, outcome != 'accepted');
              expect(sources, [
                InteractionSource.pointer,
                InteractionSource.pointer,
              ]);
            }
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await frames(t);
            session.dispose();
            await t.pump();
            view.dispose();
          }
        },
      );
    }
  }
}
