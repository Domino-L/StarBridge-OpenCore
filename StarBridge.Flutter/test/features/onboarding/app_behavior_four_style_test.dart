import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/features/onboarding/app_behavior_choice_controller.dart';
import 'package:starbridge_flutter/features/onboarding/app_behavior_choice_panel.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_copy.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final reduce in [false, true]) {
      testWidgets(
        '${suite.name} reduce=$reduce behavior choices retain radio and disabled states',
        (t) async {
          final prefs = InMemoryAppPreferences();
          final c = AppBehaviorChoiceController(prefs);
          var enabled = true;
          late StateSetter update;
          await t.pumpWidget(
            scopedApp(
              StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  return SingleChildScrollView(
                    child: AppBehaviorChoicePanel(
                      copy: OnboardingCopy(const Locale('zh', 'CN')),
                      controller: c,
                      enabled: enabled,
                    ),
                  );
                },
              ),
              suite,
              reduce: reduce,
            ),
          );
          await t.pumpAndSettle();
          final auto = find.byKey(const Key('app-behavior-startup-auto'));
          final manual = find.byKey(const Key('app-behavior-startup-manual'));
          expect(
            find.descendant(
              of: auto,
              matching: find.byType(StarBridgeActionRow),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(of: auto, matching: find.byType(Radio<bool>)),
            findsOneWidget,
          );
          await t.tap(auto);
          await t.pumpAndSettle();
          expect(c.value.launchAtStartup, isTrue);
          t
              .widget<FocusableActionDetector>(
                find
                    .descendant(
                      of: manual,
                      matching: find.byType(FocusableActionDetector),
                    )
                    .first,
              )
              .focusNode!
              .requestFocus();
          await t.pumpAndSettle();
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
          await t.pump();
          expect(c.value.launchAtStartup, isFalse);
          update(() => enabled = false);
          await t.pumpAndSettle();
          expect(
            t
                .widget<StarBridgeActionRow>(
                  find.descendant(
                    of: auto,
                    matching: find.byType(StarBridgeActionRow),
                  ),
                )
                .onActivate,
            isNull,
          );
          await t.tap(auto, warnIfMissed: false);
          await t.pumpAndSettle();
          expect(c.value.launchAtStartup, isFalse);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          c.dispose();
          prefs.dispose();
        },
      );
    }
  }
}
