import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/native_overlay_check_controller.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';

import 'native_overlay_check_test.dart' show ObservationPort;
import 'native_overlay_observation_test.dart' show observationWire;
import 'onboarding_page_test.dart' show pumpSetup;
import 'onboarding_test_support.dart';

void main() {
  testWidgets('input observations never grant missing Host local readiness', (
    tester,
  ) async {
    final port = ObservationPort();
    final native = NativeOverlayCheckController(port);
    addTearDown(native.dispose);
    final guidePort = FakeOnboardingPort(
      facts(confirmed: true, localReady: false),
    );
    final guide = await pumpSetup(
      tester,
      step: OnboardingStep.local,
      mode: OnboardingMode.local,
      port: guidePort,
      nativeOverlay: native,
    );
    await native.startHotkeyCheck();
    port.raw = observationWire(count: 1, outcome: 'open');
    await native.refresh();
    await tester.pumpAndSettle();
    expect(native.value.hotkey, NativeHotkeyCheck.observed);
    expect(guide.value.facts.localSettingsReady, false);
    expect(guide.canContinue, false);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('onboarding-next')))
          .onPressed,
      null,
    );
    expect(guidePort.actions, isEmpty);
    expect(guidePort.finishes, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'ongoing explicit check blocks navigation and save until stopped',
    (tester) async {
      final native = NativeOverlayCheckController(ObservationPort());
      addTearDown(native.dispose);
      final guidePort = FakeOnboardingPort(facts(confirmed: true));
      var closed = false;
      await pumpSetup(
        tester,
        step: OnboardingStep.local,
        mode: OnboardingMode.local,
        port: guidePort,
        nativeOverlay: native,
        onClose: () => closed = true,
      );
      await native.startHotkeyCheck();
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('onboarding-next')))
            .onPressed,
        null,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('onboarding-close')))
            .onPressed,
        null,
      );
      expect(guidePort.saves, 0);
      expect(closed, false);
      native.stopHotkeyCheck();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('onboarding-close')))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
