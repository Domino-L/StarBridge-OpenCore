import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/shell/starbridge_shell.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3b_test.dart' show exposedNodes;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;

void main() {
  setUpAll(loadFonts);
  for (final style in InteractionStyle.values) {
    testWidgets(
      '3fl actual App $style keeps shell actions but root modal blocks them',
      (t) async {
        size(t, const Size(1440, 900));
        final semantics = t.ensureSemantics();
        final root = GlobalKey<NavigatorState>();
        final composition = AppComposition.forTest(
          windowChrome: InMemoryWindowChrome(),
          preferences: InMemoryAppPreferences(
            initial: AppPreferences.defaults.copyWith(interactionStyle: style),
          ),
        );
        bool hasTools() => exposedNodes(t).any(
          (n) =>
              n.getSemanticsData().label == '工具' &&
              n.getSemanticsData().hasAction(ui.SemanticsAction.tap),
        );
        try {
          await t.pumpWidget(
            StarBridgeApp(composition: composition, navigatorKey: root),
          );
          await t.pumpAndSettle();
          final chrome = exposedNodes(t)
              .where((n) => n.getSemanticsData().label == '工具')
              .toList();
          expect(chrome, hasLength(1));
          expect(
            chrome.single.getSemanticsData().flagsCollection.isButton,
            isTrue,
          );
          expect(hasTools(), isTrue);
          unawaited(
            showStarBridgeDialog<void>(
              t.element(find.byType(StarBridgeShell)),
              source: InteractionSource.keyboard,
              builder: (_) =>
                  const AlertDialog(content: Text('Root modal fixture')),
            ),
          );
          await t.pumpAndSettle();
          expect(find.text('Root modal fixture'), findsOneWidget);
          expect(
            hasTools(),
            isFalse,
            reason: 'The root modal still blocks the entire shell',
          );
          root.currentState!.pop();
          await t.pumpAndSettle();
          expect(hasTools(), isTrue);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        }
      },
    );
  }
}
