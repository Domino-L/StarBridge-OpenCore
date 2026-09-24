import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/startup_prompt_queue.dart';

void main() {
  testWidgets('manual dialogs win; queued prompts are ordered and separated', (
    tester,
  ) async {
    final queue = StartupPromptQueue();
    addTearDown(queue.dispose);
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [queue],
        home: const Scaffold(),
      ),
    );
    Future<void> show(String name) => showDialog<void>(
      context: key.currentContext!,
      builder: (_) => AlertDialog(title: Text(name)),
    );
    final manual = show('login');
    final order = <String>[];
    void enqueue(String name, int priority) => queue.enqueue(
      name,
      priority: priority,
      eligible: () => true,
      show: () async {
        order.add(name);
        await show(name);
      },
    );
    enqueue('startup', 200);
    enqueue('privacy', 100);
    enqueue('privacy', 100); // Duplicate requests are coalesced.
    await tester.pump(const Duration(seconds: 2));
    expect(order, isEmpty);
    key.currentState!.pop();
    await manual;
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(order, ['privacy']);
    expect(find.text('startup'), findsNothing);
    key.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(order, ['privacy']);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(order, ['privacy', 'startup']);
    key.currentState!.pop();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'background, cancelled and no-longer-eligible prompts do not open',
    (tester) async {
      final queue = StartupPromptQueue();
      addTearDown(queue.dispose);
      await tester.pumpWidget(
        MaterialApp(navigatorObservers: [queue], home: const Scaffold()),
      );
      var shown = 0;
      var eligible = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      queue.enqueue(
        'later',
        priority: 10,
        eligible: () => eligible,
        show: () async {
          shown++;
        },
      );
      await tester.pump(const Duration(seconds: 2));
      expect(shown, 0);
      eligible = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 2));
      expect(shown, 0);
      eligible = true;
      queue.cancel('later');
      queue.wake();
      await tester.pump(const Duration(seconds: 2));
      expect(shown, 0);
    },
  );
}
