import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_theme.dart';
import 'package:starbridge_flutter/platform/window/menu_display_preferences.dart';

void main() {
  test('tooltip delay validates range and defaults for old settings', () {
    final settings = const MenuDisplayPreferences().toSettingsPatch();
    final display = Map<String, Object?>.from(settings['display'] as Map);
    settings['display'] = display;
    display.remove('tooltipDelayMilliseconds');
    expect(
      MenuDisplayPreferences.fromSettings(settings)!.tooltipDelayMilliseconds,
      500,
    );
    for (final delay in [100, 500, 1500]) {
      display['tooltipDelayMilliseconds'] = delay;
      expect(
        MenuDisplayPreferences.fromSettings(settings)!.tooltipDelayMilliseconds,
        delay,
      );
    }
    for (final invalid in [null, true, '500', 500.5, 99, 1501]) {
      display['tooltipDelayMilliseconds'] = invalid;
      expect(MenuDisplayPreferences.fromSettings(settings), isNull);
    }
  });
  testWidgets(
    'actual hover waits for configured delay in normal and safe mode',
    (tester) async {
      for (final safe in [false, true]) {
        for (final delay in [100, 500, 1500]) {
          await tester.pumpWidget(
            MaterialApp(
              home: MenuPresentation(
                safeMode: safe,
                tooltipDelayMilliseconds: delay,
                child: const Scaffold(
                  body: Center(
                    child: Tooltip(
                      message: 'Menu action hint',
                      child: SizedBox(width: 80, height: 80),
                    ),
                  ),
                ),
              ),
            ),
          );
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          await tester.pump();
          await mouse.moveTo(tester.getCenter(find.byType(Tooltip)));
          await tester.pump(Duration(milliseconds: delay - 1));
          expect(find.text('Menu action hint'), findsNothing);
          await tester.pump(const Duration(milliseconds: 1));
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.text('Menu action hint'), findsOneWidget);
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      }
    },
  );
}
