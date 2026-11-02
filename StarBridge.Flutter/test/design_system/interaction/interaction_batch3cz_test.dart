import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/tray/tray_quick_panel.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_native_icon_action.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'tray close uses approved native-layout feedback and remains independent',
    (t) async {
      var closes = 0;
      await t.pumpWidget(
        scopedApp(
          TrayQuickPanel(
            state: const TrayQuickPanelState(),
            onDismiss: () => closes++,
          ),
          InteractionSuite.glow,
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(StarBridgeNativeIconAction), findsOneWidget);
      await t.tap(find.byKey(const Key('tray-close')));
      expect(closes, 1);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    },
  );
  testWidgets(
    'Esc on a closed tray status trigger still dismisses the original panel',
    (t) async {
      var closes = 0;
      final source = ValueNotifier(const ManualPresenceSnapshot(scope: 1));
      final control = ManualPresenceController(source: source);
      try {
        await t.pumpWidget(
          scopedApp(
            TrayQuickPanel(
              state: const TrayQuickPanelState(),
              onDismiss: () => closes++,
              manualPresence: control,
            ),
            InteractionSuite.rail,
          ),
        );
        await t.pumpAndSettle();
        final trigger = t.widget<StarBridgeActionButton>(
          find.ancestor(
            of: find.byKey(const Key('tray-presence-menu')),
            matching: find.byType(StarBridgeActionButton),
          ),
        );
        trigger.focusNode!.requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        expect(closes, 1);
      } finally {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        control.dispose();
        source.dispose();
      }
    },
  );
  testWidgets(
    'tray visibility menu uses approved surface and stays open during an unconfirmed write',
    (t) async {
      final source = ValueNotifier(
        const ManualPresenceSnapshot(
          scope: 1,
          confirmedMode: PresenceVisibility.online,
          canChange: true,
        ),
      );
      final control = ManualPresenceController(
        source: source,
        write: (_, _) async {},
      );
      try {
        await t.pumpWidget(
          scopedApp(
            TrayQuickPanel(
              state: const TrayQuickPanelState(),
              onDismiss: () {},
              manualPresence: control,
            ),
            InteractionSuite.scan,
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('tray-presence-menu')));
        await t.pump();
        await t.pump();
        expect(find.byType(SuiteSurfaceTransition), findsOneWidget);
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('manual-presence-invisible')));
        await t.pumpAndSettle();
        expect(find.byType(SuiteSurfaceTransition), findsOneWidget);
        expect(
          find.byKey(const Key('manual-presence-feedback')),
          findsOneWidget,
        );
        expect(control.snapshot.confirmedMode, PresenceVisibility.online);
      } finally {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        control.dispose();
        source.dispose();
      }
    },
  );
  testWidgets(
    'actual tray open command uses approved feedback without delaying its owner',
    (t) async {
      var calls = 0;
      await t.pumpWidget(
        scopedApp(
          TrayQuickPanel(
            state: const TrayQuickPanelState(),
            onDismiss: () {},
            onOpen: () async {
              calls++;
            },
          ),
          InteractionSuite.rail,
        ),
      );
      await t.pumpAndSettle();
      final action = find.byKey(const Key('tray-open'));
      expect(t.widget(action), isA<SuitePressable>());
      await t.tap(action);
      expect(calls, 1);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    },
  );
}
