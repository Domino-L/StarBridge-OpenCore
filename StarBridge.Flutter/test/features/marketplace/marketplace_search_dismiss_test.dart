import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

// User report 2026-11-07 (build 75, client): the hall search's popup could
// not be closed by clicking elsewhere. Like a browser address bar: a click in
// the box keeps it open, a click anywhere else or Esc closes it, and the text
// stays. Run in the real app shell, whose window-root widgets once hid every
// outside tap.
void main() {
  final field = find.byKey(const Key('marketplace-search'));
  bool focused(WidgetTester tester) =>
      tester.widget<TextField>(field).focusNode!.hasFocus;
  String text(WidgetTester tester) =>
      tester.widget<TextField>(field).controller!.text;
  // The popup's footer line, shown whenever there is text.
  Finder popup() => find.textContaining('Esc');

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final composition = AppComposition.forTest(
      windowChrome: InMemoryWindowChrome(),
    );
    await tester.pumpWidget(StarBridgeApp(composition: composition));
    await tester.pumpAndSettle();
    // Ctrl+K opens the hall with the search focused.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(field, '量子');
    await tester.pumpAndSettle();
    expect(popup(), findsOneWidget, reason: 'typing shows the popup');
  }

  Future<void> click(WidgetTester tester, Offset at) async {
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
  }

  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  testWidgets(
    'a click outside the box closes it; the text stays',
    variant: windows,
    (tester) async {
      await open(tester);
      final box = tester.getRect(field);
      await click(tester, Offset(box.left - 40, box.center.dy));
      expect(popup(), findsNothing);
      expect(focused(tester), isFalse);
      expect(text(tester), '量子');
      // Coming back shows the same search again.
      await click(tester, box.center);
      expect(popup(), findsOneWidget);
      expect(text(tester), '量子');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a click far from the box closes it too', variant: windows, (
    tester,
  ) async {
    await open(tester);
    // Empty space at the hall's heading row, well left of the box.
    final box = tester.getRect(field);
    await click(tester, Offset(box.left - 240, box.center.dy));
    expect(popup(), findsNothing);
    expect(focused(tester), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a click in the box keeps it open', variant: windows, (
    tester,
  ) async {
    await open(tester);
    await click(tester, tester.getCenter(field));
    expect(popup(), findsOneWidget);
    expect(focused(tester), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Esc closes it; the text stays', variant: windows, (
    tester,
  ) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(popup(), findsNothing);
    expect(text(tester), '量子');
    await tester.pumpWidget(const SizedBox());
  });
}
