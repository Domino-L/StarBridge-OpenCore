import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_dock.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_workspace.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_workspace_controller.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_panel_recovery_identity.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_test.dart' show host, detach;
import 'interaction_batch3cy_test.dart' show openContext, friend;
import 'interaction_batch3cx_actions_test.dart' show bridgeFocus;

const layout = {
  'version': 1,
  'panels': [
    {
      'id': 'friends',
      'bounds': [-150.0, 110.0, 340.0, 500.0],
    },
  ],
  'open': ['friends'],
};
void main() {
  setUpAll(loadFonts);
  test(
    'recovery projection ignores unknown panels and preserves real leases',
    () {
      final owner = MenuWorkspaceController(
        scope: Object(),
        panels: [
          for (final id in ['friends', 'unknown-owner-panel'])
            MenuPanelSpec(
              id: id,
              initialBounds: const Rect.fromLTWH(0, 0, 300, 300),
            ),
        ],
      );
      try {
        owner.open('friends');
        owner.open('unknown-owner-panel');
        final leases = owner.openPanels.toList();
        final result = menuPanelRecoveryIdentities(leases);
        expect(result.keys, [BridgePreviewPanel.friends]);
        expect(
          result[BridgePreviewPanel.friends],
          same(leases.firstWhere((l) => l.id == 'friends')),
        );
        expect(owner.openPanels, orderedEquals(leases));
      } finally {
        owner.dispose();
      }
    },
  );
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite Esc with no context still reaches original menu dismiss',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(1600, 1000);
        var dismissed = 0;
        try {
          await t.pumpWidget(
            host(
              TooltipVisibility(
                visible: false,
                child: MenuBridgePreview(
                  visible: true,
                  onDismiss: () => dismissed++,
                ),
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          bridgeFocus(t, friend).requestFocus();
          await t.pump();
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          expect(dismissed, 1);
        } finally {
          await detach(t);
          t.view.reset();
        }
      },
    );
    for (final action in ['cancel', 'recover', 'reopen']) {
      testWidgets(
        '$suite real workspace context $action retains its original layout owner',
        (t) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = const Size(1600, 1000);
          final saved = <Map<String, Object?>>[];
          try {
            await t.pumpWidget(
              host(
                MenuBridgePreview(
                  visible: true,
                  onDismiss: () {},
                  initialLayout: layout,
                  localCall: (_, _) async => null,
                  initialSettings: {
                    ...MenuWindowPreferences.defaults.settings,
                    'restoreDesktop': true,
                  },
                  onLayoutChanged: saved.add,
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            final panel = find.byKey(const ValueKey('menu-panel-friends'));
            expect(t.getRect(panel).left, -150);
            final primary = t.widget<BridgePreviewDock>(
              find.byType(BridgePreviewDock),
            );
            final lease =
                primary.recoveryIdentities[BridgePreviewPanel.friends]!
                    as MenuPanelLease;
            expect(lease.id, 'friends');
            final updates = saved.length;
            await openContext(t, 'keyboard');
            expect(t.getRect(panel).left, -150);
            expect(saved.length, updates);
            if (action == 'recover') {
              await t.sendKeyEvent(LogicalKeyboardKey.enter);
              await t.pumpAndSettle();
              final moved = t.getRect(panel);
              expect(moved.left, greaterThanOrEqualTo(0));
              expect(moved.bottom, lessThanOrEqualTo(1000));
              expect(saved.length, greaterThan(updates));
              final current = t.widget<BridgePreviewDock>(
                find.byType(BridgePreviewDock),
              );
              expect(
                current.recoveryIdentities[BridgePreviewPanel.friends],
                same(lease),
              );
            } else if (action == 'cancel') {
              await t.sendKeyEvent(LogicalKeyboardKey.escape);
              await t.pumpAndSettle();
              expect(t.getRect(panel).left, -150);
              expect(saved.length, updates);
            } else {
              final owner = t
                  .widget<MenuBridgeWorkspace>(find.byType(MenuBridgeWorkspace))
                  .controller;
              owner.close('friends');
              owner.open('friends');
              await t.pumpAndSettle();
              expect(find.text('移回当前屏幕'), findsNothing);
              final current = t.widget<BridgePreviewDock>(
                find.byType(BridgePreviewDock),
              );
              expect(
                current.recoveryIdentities[BridgePreviewPanel.friends],
                isNot(same(lease)),
              );
              expect(t.getRect(panel).left, -150);
            }
            expect(t.takeException(), isNull);
          } finally {
            await detach(t);
            t.view.reset();
          }
        },
      );
    }
  }
}
