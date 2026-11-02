import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/notifications/starbridge_notification_toast.dart';

import 'interaction_batch3ae_test.dart' show mount;
import '../../features/friends/social_layout_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite respects caller local reduced motion before open', (
      t,
    ) async {
      late BuildContext caller;
      await mount(
        t,
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              caller = context;
              return const Text('Caller');
            },
          ),
        ),
        suite,
      );
      final remove = showStarBridgeNotificationToast(
        caller,
        alignment: Alignment.topRight,
        title: 'Notice',
        message: 'Content',
      );
      await t.pump();
      await t.pump();
      final fade = find.descendant(
        of: find.byType(Overlay),
        matching: find.byType(FadeTransition),
      );
      if (fade.evaluate().isNotEmpty) {
        expect(t.widget<FadeTransition>(fade.last).opacity.value, 1);
      } else {
        final transition = t.widget<SuiteSurfaceTransition>(
          find.byType(SuiteSurfaceTransition),
        );
        expect(transition.animation.value, 1);
      }
      remove();
      await t.pump();
    });
  }
}
