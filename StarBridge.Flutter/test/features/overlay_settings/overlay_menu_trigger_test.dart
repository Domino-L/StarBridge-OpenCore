import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_menu_trigger.dart';

import '../friends/social_layout_test.dart' show app, size;

void main() {
  for (final mode in AppearanceMode.values) {
    testWidgets('menu trigger is visibly bounded before hover in $mode', (
      tester,
    ) async {
      size(tester, const Size(600, 300));
      await tester.pumpWidget(
        app(
          Center(
            child: PopupMenuButton<String>(
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'space', child: Text('太空示意')),
              ],
              child: const OverlayMenuTrigger(label: '网格'),
            ),
          ),
          mode,
        ),
      );
      await tester.pumpAndSettle();
      final trigger = find.byType(OverlayMenuTrigger);
      final ink = tester.widget<Ink>(
        find.descendant(of: trigger, matching: find.byType(Ink)),
      );
      final decoration = ink.decoration! as BoxDecoration;
      expect(decoration.color, isNotNull);
      expect((decoration.border! as Border).top.width, greaterThan(0));
      expect(
        find.descendant(of: trigger, matching: _menuArrow()),
        findsOneWidget,
      );
      expect(tester.getSize(trigger).height, greaterThanOrEqualTo(36));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('太空示意'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('太空示意'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('disabled menu stays bounded but does not open', (tester) async {
    size(tester, const Size(600, 300));
    await tester.pumpWidget(
      app(
        Center(
          child: PopupMenuButton<String>(
            enabled: false,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'space', child: Text('太空示意')),
            ],
            child: const OverlayMenuTrigger(label: '网格', enabled: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OverlayMenuTrigger), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('太空示意'), findsNothing);
    expect(_menuArrow(), findsOneWidget);
  });
}

Finder _menuArrow() => find.byWidgetPredicate(
  (widget) =>
      widget is StarBridgeIcon &&
      widget.semantic == StarBridgeIconSemantic.menuDown,
);
