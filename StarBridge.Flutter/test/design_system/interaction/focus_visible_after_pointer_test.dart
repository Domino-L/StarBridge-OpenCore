// Focus visuals follow the keyboard, not focus alone. Reported on build 11:
// after the account menu closed (handing focus back to its button) the
// account area kept its focus frame although the pointer had moved on,
// because desktop mouse input keeps the "traditional" highlight mode.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3i_test.dart' show scopedApp;

const _ring = BorderSide(color: Color(0xFF00FF00), width: 2);

void main() {
  for (final suite in InteractionSuite.values) {
    // Desktop: mouse input keeps the traditional highlight mode, as on the
    // user's Windows machine (the test default platform starts in touch).
    testWidgets('${suite.name}: button focused after a click shows no frame', variant: TargetPlatformVariant.only(TargetPlatform.windows), (
      tester,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      final rowNode = FocusNode();
      addTearDown(rowNode.dispose);
      PressableVisual? visual;
      await tester.pumpWidget(
        scopedApp(
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StarBridgeActionButton(
                  controlKey: const Key('account'),
                  kind: StarBridgeActionKind.quiet,
                  focusNode: node,
                  onActivate: (_) {},
                  nativeStyle: ButtonStyle(
                    side: WidgetStateProperty.resolveWith(
                      (s) => s.contains(WidgetState.focused)
                          ? _ring
                          : BorderSide.none,
                    ),
                  ),
                  child: const Text('account'),
                ),
                SuitePressable(
                  kind: PressableKind.row,
                  focusNode: rowNode,
                  onActivate: (_) {},
                  builder: (_, v) {
                    visual = v;
                    return const SizedBox(width: 40, height: 20);
                  },
                ),
              ],
            ),
          ),
          suite,
        ),
      );
      await tester.pumpAndSettle();
      BorderSide? side() => tester
          .widgetList<ButtonStyleButton>(find.byWidgetPredicate((w) => w is ButtonStyleButton))
          .firstOrNull
          ?.style
          ?.side
          ?.resolve({WidgetState.focused});
      final row = find.byType(SuitePressable).last;
      Future<void> focusRow() async {
        rowNode.requestFocus();
        await tester.pumpAndSettle();
      }

      // A mouse click, then a closing menu hands focus back.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(row));
      addTearDown(mouse.removePointer);
      await mouse.down(tester.getCenter(row));
      await mouse.up();
      await tester.pumpAndSettle();
      node.requestFocus();
      await tester.pumpAndSettle();
      if (suite == InteractionSuite.standard) {
        expect(side(), BorderSide.none);
      }
      await focusRow();
      expect(visual?.focused, isFalse);

      // Keyboard input shows focus again.
      await tester.sendKeyEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();
      expect(visual?.focused, isTrue);
      node.requestFocus();
      await tester.pumpAndSettle();
      if (suite == InteractionSuite.standard) expect(side(), _ring);

      // The next click hides it without moving focus elsewhere first.
      await focusRow();
      await mouse.down(tester.getCenter(row));
      await mouse.up();
      await tester.pumpAndSettle();
      await focusRow();
      expect(visual?.focused, isFalse);
    });
  }
}
