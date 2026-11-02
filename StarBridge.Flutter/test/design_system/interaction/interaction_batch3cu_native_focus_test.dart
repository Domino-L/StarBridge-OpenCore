import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_recovery_prompt.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_test.dart' show host, detach;
import 'interaction_batch3ct_geometry_test.dart' show pixels;
import 'interaction_batch3cu_test.dart' show focusOf;

void main() {
  setUpAll(loadFonts);
  for (final choice in ['restore', 'start-clean']) {
    testWidgets(
      'native $choice follows live focus-highlight mode without changing focus or choices',
      (t) async {
        final manager = FocusManager.instance;
        final original = manager.highlightStrategy;
        final root = GlobalKey();
        final choices = <String>[];
        manager.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
        try {
          await t.pumpWidget(
            host(
              RepaintBoundary(
                key: root,
                child: MenuRecoveryPrompt(onChoose: choices.add),
              ),
              InteractionSuite.standard,
              reduce: true,
            ),
          );
          await t.pumpAndSettle();
          final focus = focusOf(t, choice);
          focus.requestFocus();
          await t.pumpAndSettle();
          final before = await pixels(t, root);
          manager.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
          await t.pump();
          await t.pump();
          final keyboard = await pixels(t, root);
          expect(keyboard, isNot(orderedEquals(before)));
          expect(focusOf(t, choice), same(focus));
          expect(focus.hasFocus, isTrue);
          expect(choices, isEmpty);
          // Native InkWell may run an invisible highlight controller. Verify
          // the visible static contract instead of a global ticker count.
          await t.pump(const Duration(milliseconds: 80));
          expect(await pixels(t, root), orderedEquals(keyboard));
          manager.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
          await t.pump();
          await t.pump();
          expect(await pixels(t, root), orderedEquals(before));
          await detach(t);
          // Disposed listeners must not schedule or touch their old controllers.
          manager.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
          await t.pump();
          expect(t.takeException(), isNull);
          expect(t.binding.transientCallbackCount, 0);
        } finally {
          await detach(t);
          manager.highlightStrategy = original;
        }
      },
    );
  }
  testWidgets(
    'changing highlight mode during a held native choice does not cancel its activation',
    (t) async {
      final manager = FocusManager.instance;
      final original = manager.highlightStrategy;
      final choices = <String>[];
      try {
        await t.pumpWidget(
          host(
            MenuRecoveryPrompt(onChoose: choices.add),
            InteractionSuite.standard,
          ),
        );
        await t.pumpAndSettle();
        final gesture = await t.startGesture(t.getCenter(find.text('恢复窗口')));
        await t.pump();
        manager.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
        await t.pump();
        manager.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
        await t.pump();
        await gesture.up();
        expect(choices, ['restore']);
        expect(t.takeException(), isNull);
      } finally {
        await detach(t);
        manager.highlightStrategy = original;
      }
    },
  );
}
