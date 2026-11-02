import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_module.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/general_settings_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch2c_test.dart' show DelayedStore;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite actual general choices and independent exit use approved feedback',
      (t) async {
        size(t, const Size(1400, 1100));
        final owner = InMemoryAppPreferences();
        try {
          await t.pumpWidget(
            scopedApp(GeneralSettingsPage(preferences: owner), suite),
          );
          await t.pumpAndSettle();
          for (final id in [
            'general-language-control-en-US',
            'general-appearance-light',
          ]) {
            expect(
              find.ancestor(
                of: find.byKey(Key(id)),
                matching: find.byType(StarBridgeActionRow),
              ),
              findsOneWidget,
            );
          }
          expect(
            find.ancestor(
              of: find.byKey(const Key('general-reduce-motion')),
              matching: find.byType(StarBridgeSwitch),
            ),
            findsOneWidget,
          );
          expect(
            find.ancestor(
              of: find.byKey(const Key('general-exit-application')),
              matching: find.byType(StarBridgeActionButton),
            ),
            findsOneWidget,
          );
        } finally {
          await t.pumpWidget(const SizedBox());
          owner.dispose();
        }
      },
    );
    testWidgets(
      '$suite actual pending preference keeps approved wait and no fake confirmation',
      (t) async {
        size(t, const Size(1400, 1100));
        final owner = AppPreferencesModule();
        final store = DelayedStore();
        await owner.attachStore(store);
        try {
          await t.pumpWidget(
            scopedApp(GeneralSettingsPage(preferences: owner), suite),
          );
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('general-appearance-light')));
          await t.pump();
          await t.pump();
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(find.byType(SuiteProgressBar), findsOneWidget);
          expect(
            t.getSize(find.byType(SuiteProgressBar)).width,
            greaterThan(100),
          );
          expect(owner.projection.value.revision, 4);
          store.pending.completeError(StateError('synthetic failure'));
          await t.pumpAndSettle();
          expect(find.byType(SuiteProgressBar), findsNothing);
        } finally {
          await t.pumpWidget(const SizedBox());
          owner.dispose();
        }
      },
    );
  }
}
