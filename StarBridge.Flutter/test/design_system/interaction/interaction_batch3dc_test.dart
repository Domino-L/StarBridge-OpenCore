import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/direct_messages/example_direct_messages.dart';
import 'package:starbridge_flutter/features/friends/example_friends_adapter.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite real friend navigation and message use approved feedback',
      (t) async {
        size(t, const Size(1400, 1000));
        try {
          await t.pumpWidget(
            scopedApp(
              FriendsPage(
                createPort: ExampleFriendsAdapter.new,
                createChatPort: ExampleDirectMessages.new,
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          final nav = find.byKey(const Key('friends-nav-friends'));
          expect(
            find.ancestor(of: nav, matching: find.byType(StarBridgeActionRow)),
            findsOneWidget,
          );
          final message = find.byKey(const Key('friend-message-0'));
          expect(
            find.ancestor(
              of: message,
              matching: find.byType(StarBridgeActionButton),
            ),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
        }
      },
    );
    testWidgets('$suite real friend removal uses approved owned route', (
      t,
    ) async {
      size(t, const Size(1400, 1000));
      try {
        await t.pumpWidget(
          scopedApp(FriendsPage(createPort: ExampleFriendsAdapter.new), suite),
        );
        await t.pumpAndSettle();
        await t.tap(find.text('删除好友'));
        await t.pumpAndSettle();
        final route = ModalRoute.of(t.element(find.byType(AlertDialog)));
        expect(route, isA<StarBridgeDialogRoute<bool>>());
        expect(find.byKey(const Key('friend-confirm-keep')), findsOneWidget);
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
      }
    });
  }
}
