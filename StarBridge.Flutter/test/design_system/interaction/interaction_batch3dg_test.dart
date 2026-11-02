import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_page_motion.dart';
import 'package:starbridge_flutter/features/settings/help_support_settings_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite actual help header uses approved action feedback', (
      t,
    ) async {
      size(t, const Size(1400, 1100));
      await t.pumpWidget(scopedApp(const HelpSupportSettingsPage(), suite));
      await t.pumpAndSettle();
      for (final id in ['help-spiritual-support', 'help-scm-team']) {
        expect(
          find.ancestor(
            of: find.byKey(Key(id)),
            matching: find.byType(StarBridgeActionButton),
          ),
          findsOneWidget,
        );
      }
      await t.pumpWidget(const SizedBox());
    });
    testWidgets(
      '$suite actual help topic keeps approved row and topic viewport feedback',
      (t) async {
        size(t, const Size(1400, 1100));
        await t.pumpWidget(scopedApp(const HelpSupportSettingsPage(), suite));
        await t.pumpAndSettle();
        final target = find.byKey(const Key('help-topic-button-notices'));
        expect(
          find.ancestor(of: target, matching: find.byType(StarBridgeActionRow)),
          findsOneWidget,
        );
        await t.tap(target);
        await t.pump();
        expect(find.byType(StarBridgePageTransition), findsWidgets);
        await t.pumpAndSettle();
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite local moral support has source-aware route and approved close',
      (t) async {
        size(t, const Size(1400, 1100));
        await t.pumpWidget(scopedApp(const HelpSupportSettingsPage(), suite));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('help-spiritual-support')));
        await t.pumpAndSettle();
        expect(
          ModalRoute.of(t.element(find.byType(AlertDialog))),
          isA<StarBridgeDialogRoute<void>>(),
        );
        expect(
          find.byKey(const Key('help-support-local-close')),
          findsOneWidget,
        );
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
