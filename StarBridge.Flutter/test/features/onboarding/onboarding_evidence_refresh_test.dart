import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_controller.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';

import 'onboarding_page_test.dart' show pumpSetup;
import 'onboarding_test_support.dart';

FakeOnboardingPort pendingEvidence() {
  final port = FakeOnboardingPort(
    facts(evidence: OnboardingEvidence.checking, evidenceKey: null),
  );
  port.onAction = (action, checkpoint) async {
    if (action == OnboardingAction.refresh) port.facts = facts();
    return OnboardingReply(facts: port.facts);
  };
  return port;
}

void main() {
  test(
    'entering identity issues a scan instead of waiting on cached reads',
    () async {
      final port = pendingEvidence();
      final controller = OnboardingController(port);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.next();
      controller.chooseMode(OnboardingMode.local);
      await controller.next();
      await controller.next();
      expect(controller.value.step, OnboardingStep.identity);
      expect(
        port.actions.where((a) => a == OnboardingAction.refresh).length,
        1,
      );
      expect(controller.value.facts.hasCandidate, true);
    },
  );

  test(
    'restored identity issues one scan and passive reads do not rescan',
    () async {
      final port = pendingEvidence();
      port.restored = OnboardingCheckpoint(
        step: OnboardingStep.identity,
        mode: OnboardingMode.local,
        sourceKey: port.facts.sourceKey,
      );
      final controller = OnboardingController(port);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.refresh();
      expect(port.actions, [OnboardingAction.refresh]);
      expect(controller.value.facts.hasCandidate, true);
    },
  );

  testWidgets(
    'identity retry scans after refreshing expired evidence receipt',
    (tester) async {
      final port = FakeOnboardingPort(
        facts(evidence: OnboardingEvidence.failed),
      );
      final controller = await pumpSetup(
        tester,
        step: OnboardingStep.identity,
        mode: OnboardingMode.local,
        port: port,
      );
      // Native expires a previous evidence key after ten seconds. A read must
      // renew the wire receipt before sending the explicit scan command.
      port.facts = facts(
        evidence: OnboardingEvidence.checking,
        evidenceKey: null,
      );
      port.onAction = (action, checkpoint) async {
        if (action == OnboardingAction.refresh) {
          expect(checkpoint.evidenceKey, isNull);
          port.facts = facts();
        }
        return OnboardingReply(facts: port.facts);
      };
      await tester.tap(find.byKey(const Key('onboarding-refresh')));
      await tester.pumpAndSettle();
      expect(port.actions, [OnboardingAction.refresh]);
      expect(controller.value.facts.hasCandidate, true);
    },
  );

  for (final change in ['source', 'mode', 'readFailure']) {
    test(
      'retry does not scan after $change invalidates the observation',
      () async {
        final port = FakeOnboardingPort(
          facts(evidence: OnboardingEvidence.failed),
        );
        port.restored = OnboardingCheckpoint(
          step: OnboardingStep.identity,
          mode: OnboardingMode.local,
          sourceKey: port.facts.sourceKey,
          evidenceKey: port.facts.evidenceKey,
        );
        final controller = OnboardingController(port);
        addTearDown(controller.dispose);
        await controller.initialize();
        if (change == 'source') {
          port.facts = facts(source: 'fixture-ptu-other');
        } else if (change == 'mode') {
          port.facts = facts(
            activeMode: OnboardingMode.online,
            publicationSuspended: false,
          );
        } else {
          port.readThrows = true;
        }
        await controller.checkEvidence();
        expect(port.actions, isEmpty);
        expect(controller.value.completed, false);
        expect(controller.value.busy, false);
        if (change == 'readFailure') expect(controller.value.error, true);
      },
    );
  }
}
