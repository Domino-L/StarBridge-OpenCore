import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';

import '../../features/friends/user_interaction_test.dart' show MenuPort;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;
import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3am_test.dart' show action;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      'active keyboard command takes precedence over stale inherited origin $suite',
      (t) async {
        final inherited = ValueNotifier(InteractionSource.pointer);
        addTearDown(inherited.dispose);
        await mount(
          t,
          StarBridgeActivationOrigin(
            source: inherited,
            child: Builder(
              builder: (context) => Align(
                alignment: Alignment.topLeft,
                child: StarBridgeActionButton(
                  controlKey: const Key('source-probe-open'),
                  onActivate: (_) => showStarBridgeDialog<void>(
                    context,
                    builder: (_) => const AlertDialog(
                      key: Key('source-probe-dialog'),
                      title: Text('Keyboard dialog'),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
          suite,
        );
        await action(t, const Key('source-probe-open'), 'keyboard');
        expect(
          (ModalRoute.of(
                    t.element(find.byKey(const Key('source-probe-dialog'))),
                  )!
                  as StarBridgeDialogRoute)
              .instant,
          true,
        );
        expect(
          inherited.value,
          InteractionSource.pointer,
          reason: 'Do not mutate the caller origin to repair another command.',
        );
        await t.pumpWidget(const SizedBox());
      },
    );
    for (final change in ['context', 'source', 'port']) {
      testWidgets(
        'pending avatar reply belongs to exact current scope $suite change=$change',
        (t) async {
          final first = MenuPort()..held = Completer<FriendRow?>(),
              next = MenuPort();
          addTearDown(first.changes.close);
          addTearDown(next.changes.close);
          var port = first;
          var target = const UserTarget.community(
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          );
          late StateSetter rebuild;
          try {
            await mount(
              t,
              StatefulBuilder(
                builder: (_, set) {
                  rebuild = set;
                  return UserInteractionScope(
                    navigation: UserPageNavigation(),
                    port: port,
                    messagePage: null,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: UserAvatarMenu(
                        key: const Key('avatar-source-probe'),
                        name: 'Original peer',
                        target: target,
                        child: const SizedBox(width: 48, height: 48),
                      ),
                    ),
                  );
                },
              ),
              suite,
            );
            await action(
              t,
              const Key('avatar-source-probe'),
              'pointer',
              settle: false,
            );
            rebuild(() {
              if (change == 'port') {
                port = next;
              } else if (change == 'source') {
                target = const UserTarget(
                  'friend',
                  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                );
              } else {
                target = const UserTarget.community(
                  'cccccccccccccccccccccccccccccccc',
                  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                );
              }
            });
            await t.pump();
            await t.pump();
            first.held!.complete(first.row);
            await settleCommunityImages(t);
            expect(find.text('添加好友'), findsNothing);
            expect(first.writes, 0);
            expect(next.writes, 0);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
          }
        },
      );
    }
  }
}
