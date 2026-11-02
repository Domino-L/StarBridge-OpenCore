import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/menu_engine_prewarm.dart';

// testWidgets fails on any timer left pending, which also proves every path
// below stops polling native.
void main() {
  const channel = MethodChannel('test/menu-prewarm');
  const tick = Duration(seconds: 1);
  // The mocked platform reply completes on a following microtask turn.
  Future<void> advance(WidgetTester tester, Duration by) async {
    await tester.pump(by);
    await tester.pump();
  }

  void mock(
    WidgetTester tester,
    Future<Object?> Function(MethodCall) handler,
  ) => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    handler,
  );

  testWidgets('prewarm waits while idle, retries a deferral, then stops', (
    tester,
  ) async {
    final replies = [false, true];
    final seen = <MethodCall>[];
    var calls = 0;
    mock(tester, (call) async {
      seen.add(call);
      return replies[calls++];
    });
    MenuEnginePrewarm(channel, delay: tick).start(() => true);
    await advance(tester, tick ~/ 2);
    expect(calls, 0, reason: 'never competes with startup work');
    await advance(tester, tick);
    expect(calls, 1);
    await advance(tester, tick);
    expect(calls, 2);
    await advance(tester, tick * 5);
    expect(calls, 2, reason: 'a prepared engine is requested only once');
    expect(seen.map((call) => (call.method, call.arguments)), [
      ('prewarm', null),
      ('prewarm', null),
    ]);
  });

  testWidgets('prewarm skips openings and is bounded', (tester) async {
    var calls = 0;
    var opening = true;
    mock(tester, (_) async {
      calls++;
      return false;
    });
    MenuEnginePrewarm(
      channel,
      delay: tick,
      maxAttempts: 3,
    ).start(() => !opening);
    await advance(tester, tick);
    expect(calls, 0, reason: 'an opening owns native creation itself');
    opening = false;
    await advance(tester, tick * 10);
    expect(calls, 2);
  });

  testWidgets('prewarm stops on native failure or dispose', (tester) async {
    var calls = 0;
    mock(tester, (_) async {
      calls++;
      throw PlatformException(code: 'menu.unavailable');
    });
    MenuEnginePrewarm(channel, delay: tick).start(() => true);
    await advance(tester, tick * 3);
    expect(calls, 1);
    MenuEnginePrewarm(channel, delay: tick)
      ..start(() => true)
      ..dispose();
    await advance(tester, tick * 3);
    expect(calls, 1);
  });
}
