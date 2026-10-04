import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/scrolling/starbridge_scroll_behavior.dart';
import 'package:starbridge_flutter/design_system/scrolling/wheel_direction_guard.dart';

import '../features/friends/social_layout_test.dart' show app;

void main() {
  for (final reduced in [false, true]) {
    testWidgets('nested wheel targets inner list, reduced=$reduced', (
      tester,
    ) async {
      final outer = ScrollController(),
          inner = ScrollController(initialScrollOffset: 100);
      await tester.pumpWidget(
        app(
          MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: ScrollConfiguration(
              behavior: const StarBridgeScrollBehavior(),
              child: ListView(
                controller: outer,
                children: [
                  SizedBox(
                    height: 200,
                    child: ListView(
                      controller: inner,
                      children: [const SizedBox(height: 1500)],
                    ),
                  ),
                  const SizedBox(height: 1600),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(100, 100),
          scrollDelta: Offset(0, 100),
          timeStamp: Duration(seconds: 1),
        ),
      );
      expect(inner.offset, reduced ? 200 : 100);
      await tester.pumpAndSettle();
      expect(inner.offset, closeTo(200, .3));
      expect(outer.offset, 0);
      await tester.pumpWidget(const SizedBox());
      outer.dispose();
      inner.dispose();
    });
  }
  testWidgets('programmatic history restoration cancels pending wheel motion', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 200);
    await tester.pumpWidget(
      app(
        ScrollConfiguration(
          behavior: const StarBridgeScrollBehavior(),
          child: ListView(
            controller: controller,
            children: [const SizedBox(height: 3000)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(100, 100),
        scrollDelta: Offset(0, 100),
        timeStamp: Duration(seconds: 1),
      ),
    );
    await tester.pump();
    controller.jumpTo(400);
    await tester.pumpAndSettle();
    expect(controller.offset, 400);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  test('WPF pulse protection brakes once and permits confirmed reversal', () {
    final guard = WheelDirectionGuard();
    bool input(double d, int time) =>
        guard.accept(d, time, moving: true, boundary: false);
    expect(input(50, 100), true);
    expect(input(-50, 120), false);
    expect(input(-50, 150), true);
    expect(input(50, 300), true);
    guard.reset();
    expect(input(-50, 301), true);
  });
  testWidgets('wheel moves over frames and brakes a spurious reverse pulse', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 200);
    await tester.pumpWidget(
      app(
        ScrollConfiguration(
          behavior: const StarBridgeScrollBehavior(),
          child: ListView(
            controller: controller,
            children: [
              for (var i = 0; i < 100; i++)
                SizedBox(height: 50, child: Text('$i')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> wheel(double d, int time) => tester.sendEventToBinding(
      PointerScrollEvent(
        position: const Offset(100, 100),
        scrollDelta: Offset(0, d),
        timeStamp: Duration(milliseconds: time),
      ),
    );
    await wheel(100, 100);
    expect(controller.offset, 200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.offset, greaterThan(200));
    expect(controller.offset, lessThan(300));
    final before = controller.offset;
    await wheel(-100, 120);
    await tester.pump(const Duration(milliseconds: 40));
    expect(controller.offset, before);
    await wheel(-100, 150);
    await tester.pumpAndSettle();
    expect(controller.offset, lessThan(before));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
