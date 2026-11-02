import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_recovery_prompt.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import '../../app/menu_overlay/menu_overlay_surface_app_test.dart' show push;
import 'interaction_batch3cv_test.dart' show activate;
import 'interaction_batch3cv_recovery_test.dart'
    show RecoveryFixture, configuration, expectWaiting;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final oldOutcome in ['success', 'failure']) {
      testWidgets(
        '$suite old pending $oldOutcome cannot finish or recolor a new pending recovery',
        (t) async {
          final fixture = RecoveryFixture();
          try {
            await fixture.mount(t, suite);
            final began = t.binding.clock.now();
            await activate(
              t,
              'pointer',
              find.byKey(const Key('menu-recovery-restore')),
            );
            await t.pump();
            expectWaiting(t, suite, InteractionSource.pointer);
            await push(t, configuration(1, suite, wanted: false));
            await push(t, configuration(2, suite));
            await t.pump();
            expect(
              t
                  .widget<MenuRecoveryPrompt>(find.byType(MenuRecoveryPrompt))
                  .busySource,
              InteractionSource.programmatic,
            );
            await activate(
              t,
              'keyboard',
              find.byKey(const Key('menu-recovery-start-clean')),
            );
            await t.pump();
            await t.pump();
            expectWaiting(t, suite, InteractionSource.keyboard);
            final pendingState = t.state(find.byType(SuiteBusyFrame));
            expect(fixture.requests.map((call) => call.arguments), [
              {'opening': 1, 'action': 'restore'},
              {'opening': 2, 'action': 'startClean'},
            ]);
            // This is deliberately before A's six-second timeout, not the
            // timeout-then-reopen case covered by the other regression file.
            expect(
              t.binding.clock.now().difference(began).inMilliseconds,
              lessThan(6000),
            );
            if (oldOutcome == 'success') {
              fixture.replies.first.complete(
                MenuWindowPreferences.defaults.encode(),
              );
            } else {
              fixture.replies.first.completeError(
                PlatformException(code: 'old.rejected'),
              );
            }
            await t.pump();
            await t.pump();
            expectWaiting(t, suite, InteractionSource.keyboard);
            expect(t.state(find.byType(SuiteBusyFrame)), same(pendingState));
            expect(
              t
                  .widget<MenuRecoveryPrompt>(find.byType(MenuRecoveryPrompt))
                  .failed,
              isFalse,
            );
            expect(fixture.replies.last.isCompleted, isFalse);
            fixture.replies.last.complete(
              MenuWindowPreferences.defaults.encode(),
            );
            await t.pump();
            await t.pump();
            expect(find.byType(MenuRecoveryPrompt), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await fixture.dispose(t);
          }
        },
      );
    }
  }
}
