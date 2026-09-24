import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/shell/starbridge_shell.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

void main() {
  testWidgets('appearance mode interpolates the application theme', (
    tester,
  ) async {
    final preferences = InMemoryAppPreferences();
    await _pumpApp(tester, preferences);

    final transition = tester.widget<AnimatedTheme>(
      find.byKey(const Key('starbridge-theme-transition')),
    );
    expect(transition.duration, const Duration(milliseconds: 220));

    final dark = _scaffoldColor(tester);
    await preferences.setAppearanceMode(AppearanceMode.light);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));

    final midway = _scaffoldColor(tester);
    expect(midway, isNot(dark));

    await tester.pumpAndSettle();
    final light = _scaffoldColor(tester);
    expect(light, isNot(dark));
    expect(midway, isNot(light));
  });

  testWidgets('reduced motion applies an appearance change immediately', (
    tester,
  ) async {
    final preferences = InMemoryAppPreferences(
      initial: AppPreferences.defaults.copyWith(
        motionPreference: MotionPreference.reduce,
      ),
    );
    await _pumpApp(tester, preferences);

    final transition = tester.widget<AnimatedTheme>(
      find.byKey(const Key('starbridge-theme-transition')),
    );
    expect(transition.duration, Duration.zero);

    final dark = _scaffoldColor(tester);
    await preferences.setAppearanceMode(AppearanceMode.light);
    await tester.pump();

    expect(_scaffoldColor(tester), isNot(dark));
  });
}

Future<void> _pumpApp(
  WidgetTester tester,
  InMemoryAppPreferences preferences,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 720);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final composition = AppComposition.forTest(
    windowChrome: InMemoryWindowChrome(),
    preferences: preferences,
  );
  await tester.pumpWidget(StarBridgeApp(composition: composition));
  await tester.pumpAndSettle();
}

Color _scaffoldColor(WidgetTester tester) {
  final context = tester.element(find.byType(StarBridgeShell));
  return Theme.of(context).scaffoldBackgroundColor;
}
