import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_controls.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/friends_test.dart' show PendingPort, ready;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite actual friend page remaining search actions use approved feedback',
      (t) async {
        size(t, const Size(1400, 1000));
        final port = PendingPort();
        final owner = FriendsModule(port);
        final initial = owner.enter();
        port.requests.single.complete(ready('初始好友'));
        await initial;
        try {
          await t.pumpWidget(
            scopedApp(
              FriendsPage(
                createPort: () => throw StateError('Borrowed owner'),
                module: owner,
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          final refresh = find.byKey(const Key('friends-refresh'));
          expect(
            find.ancestor(
              of: refresh,
              matching: find.byType(StarBridgeActionButton),
            ),
            findsOneWidget,
          );
          expect(find.byKey(const Key('friends-search')), findsOneWidget);
          expect(find.byType(StarBridgeFieldFrame), findsOneWidget);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          owner.dispose();
        }
      },
    );
    for (final interactive in [false, true]) {
      testWidgets(
        '$suite interactive=$interactive real menu query has one native editor and one frame',
        (t) async {
          try {
            await t.pumpWidget(
              scopedApp(
                SizedBox(
                  width: 400,
                  child: interactive
                      ? MenuFriendsControls(
                          view: const MenuFriendsView(
                            'ready',
                            interactive: true,
                          ),
                          onAction: (_, _, _) {},
                        )
                      : MenuFriendsPanel(
                          view: const MenuFriendsView('ready'),
                          onClose: () {},
                        ),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            final field = find.byKey(
              ValueKey(
                interactive ? 'friends-account-search' : 'menu-friends-filter',
              ),
            );
            expect(field, findsOneWidget);
            expect(
              find.ancestor(
                of: field,
                matching: find.byType(StarBridgeFieldFrame),
              ),
              findsOneWidget,
            );
            expect(find.byType(EditableText), findsOneWidget);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
          }
        },
      );
    }
  }
}
