import 'package:flutter_test/flutter_test.dart';

/// Native codecs complete on the real event loop. With a loading indicator,
/// fake-clock pumpAndSettle alone cannot wait for that I/O to finish.
Future<void> settleCommunityImages(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    if (!tester.binding.hasScheduledFrame) return;
  }
  // Preserve a failing signal for a genuinely stuck indicator/animation.
  await tester.pumpAndSettle();
}
