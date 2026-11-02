import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/first_use_onboarding_flow.dart';
import 'package:starbridge_flutter/app/runtime/startup_prompt_queue.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';

import '../features/onboarding/onboarding_test_support.dart';

void main() {
  testWidgets('manual setup consumes the queued automatic offer for this launch', (tester) async {
    final queue = StartupPromptQueue(quietPeriod: const Duration(milliseconds: 5));
    var ready = false, shown = 0;
    final flow = FirstUseOnboardingFlow(port: FakeOnboardingPort(facts()), queue: queue,
      ready: () => ready, isCurrent: () => true, show: () async => shown++);
    addTearDown(flow.dispose);
    addTearDown(queue.dispose);
    await tester.pumpWidget(MaterialApp(navigatorObservers: [queue], home: const SizedBox()));
    await flow.check();
    expect(flow.blocksOptionalPrompts, true);
    flow.consumeManualEntry();
    ready = true;
    queue.wake();
    await tester.pumpAndSettle();
    await flow.check();
    await tester.pumpAndSettle();
    expect(shown, 0);
    expect(flow.blocksOptionalPrompts, false);
  });
  for (final eligibility in OnboardingEligibility.values) {
    test('automatic offer uses Host eligibility ${eligibility.name}', () {
      expect(
        FirstUseOnboardingFlow.eligible(
          OnboardingReply(facts: facts(eligibility: eligibility)),
        ),
        eligibility == OnboardingEligibility.firstUse,
      );
    });
  }
  test('unsupported save or missing host never triggers automatically', () {
    expect(
      FirstUseOnboardingFlow.eligible(
        OnboardingReply(facts: facts(canSave: false)),
      ),
      false,
    );
    expect(
      FirstUseOnboardingFlow.eligible(
        OnboardingReply(facts: facts(available: false)),
      ),
      false,
    );
    expect(
      FirstUseOnboardingFlow.eligible(
        const OnboardingReply(facts: OnboardingFacts()),
      ),
      false,
    );
  });
  test('a completed receipt suppresses the automatic offer', () {
    expect(
      FirstUseOnboardingFlow.eligible(
        OnboardingReply(
          facts: facts(),
          completed: const OnboardingCheckpoint(
            step: OnboardingStep.summary,
            mode: OnboardingMode.local,
          ),
        ),
      ),
      false,
    );
  });

  testWidgets('manual routes defer setup; recheck prevents stale offer', (
    tester,
  ) async {
    final queue = StartupPromptQueue(
      quietPeriod: const Duration(milliseconds: 5),
    );
    final navigator = GlobalKey<NavigatorState>();
    final port = FakeOnboardingPort(facts());
    var shown = 0;
    final flow = FirstUseOnboardingFlow(
      port: port,
      queue: queue,
      ready: () => true,
      isCurrent: () => true,
      show: () async => shown++,
    );
    addTearDown(flow.dispose);
    addTearDown(queue.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [queue],
        home: const SizedBox(),
      ),
    );
    navigator.currentState!.push<void>(
      MaterialPageRoute(builder: (_) => const SizedBox()),
    );
    await flow.check();
    await tester.pumpAndSettle();
    expect(shown, 0);
    expect(flow.blocksOptionalPrompts, true);
    port.facts = facts(eligibility: OnboardingEligibility.returning);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(shown, 0);
    expect(flow.blocksOptionalPrompts, false);
    expect(port.actions, isEmpty);
    expect(port.saves, 0);
  });

  testWidgets('first-use is shown once per run, not repeatedly after close', (
    tester,
  ) async {
    final queue = StartupPromptQueue(
      quietPeriod: const Duration(milliseconds: 5),
    );
    final port = FakeOnboardingPort(facts());
    var shown = 0;
    final flow = FirstUseOnboardingFlow(
      port: port,
      queue: queue,
      ready: () => true,
      isCurrent: () => true,
      show: () async => shown++,
    );
    addTearDown(flow.dispose);
    addTearDown(queue.dispose);
    await tester.pumpWidget(
      MaterialApp(navigatorObservers: [queue], home: const SizedBox()),
    );
    await flow.check();
    await tester.pumpAndSettle();
    expect(shown, 1);
    await flow.check();
    await tester.pumpAndSettle();
    expect(shown, 1);
    expect(port.actions, isEmpty);
  });

  testWidgets('lost generation prevents queued startup display', (
    tester,
  ) async {
    final queue = StartupPromptQueue(
      quietPeriod: const Duration(milliseconds: 5),
    );
    var current = true, shown = 0;
    final flow = FirstUseOnboardingFlow(
      port: FakeOnboardingPort(facts()),
      queue: queue,
      ready: () => true,
      isCurrent: () => current,
      show: () async => shown++,
    );
    addTearDown(flow.dispose);
    addTearDown(queue.dispose);
    await tester.pumpWidget(
      MaterialApp(navigatorObservers: [queue], home: const SizedBox()),
    );
    await flow.check();
    current = false;
    await tester.pumpAndSettle();
    expect(shown, 0);
  });
}
