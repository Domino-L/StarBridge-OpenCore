import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_controller.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';

import 'onboarding_test_support.dart';

void main() {
  test('a new user records resumable progress as soon as setup opens', () async {
    final port = FakeOnboardingPort(facts());
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await c.initialize();
    expect(port.saves, 1, reason: 'tray Exit before closing must not lose setup');
    expect(c.value.error, false);
  });

  test('returning, unknown and restored setups are not rewritten', () async {
    for (final eligibility in [
      OnboardingEligibility.returning,
      OnboardingEligibility.unknown,
    ]) {
      final port = FakeOnboardingPort(facts(eligibility: eligibility));
      final c = OnboardingController(port);
      await c.initialize();
      expect(port.saves, 0, reason: '$eligibility');
      c.dispose();
    }
    final restored = FakeOnboardingPort(facts())
      ..restored = const OnboardingCheckpoint(step: OnboardingStep.mode);
    final c = OnboardingController(restored);
    addTearDown(c.dispose);
    await c.initialize();
    expect(restored.saves, 0);
  });

  test('an unconfirmed opening save stays silent', () async {
    final port = FakeOnboardingPort(facts())..saveReceipt = false;
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await c.initialize();
    expect(port.saves, 1);
    expect(c.value.error, false);
    expect(c.value.saved, false);
  });
}
