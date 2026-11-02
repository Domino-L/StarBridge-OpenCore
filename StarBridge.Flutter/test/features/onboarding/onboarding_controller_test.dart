import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_controller.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';

import 'onboarding_test_support.dart';

Future<void> identity(
  OnboardingController c, {
  OnboardingMode mode = OnboardingMode.local,
}) async {
  await c.initialize();
  await c.next();
  c.chooseMode(mode);
  await c.next();
  await c.next();
  expect(c.value.step, OnboardingStep.identity);
}

void main() {
  test('product skips obsolete welcome only, without choosing mode or writing consent', () async {
    final port = FakeOnboardingPort(facts());
    final c = OnboardingController(port, skipWelcomeIntro: true);
    addTearDown(c.dispose);
    await c.initialize();
    expect(c.value.step, OnboardingStep.mode);
    expect(c.value.mode, isNull);
    expect(c.canGoBack, false);
    c.back();
    expect(c.value.step, OnboardingStep.mode);
    expect(port.actions, isEmpty);
    expect(c.value.completed, false);
  });
  test(
    'local mode requires real publication suspension acknowledgement',
    () async {
      final port = FakeOnboardingPort(
        facts(activeMode: OnboardingMode.online, publicationSuspended: false),
      );
      port.onAction = (_, _) async => OnboardingReply(facts: port.facts);
      final c = OnboardingController(port);
      addTearDown(c.dispose);
      await c.initialize();
      await c.next();
      c.chooseMode(OnboardingMode.local);
      await c.next();
      expect(c.value.step, OnboardingStep.mode);
      expect(c.value.error, true);
      expect(c.value.completed, false);
      expect(port.actions, [OnboardingAction.applyMode]);
    },
  );

  test(
    'mode acknowledgement without publication suspension is insufficient',
    () async {
      final port = FakeOnboardingPort(facts(publicationSuspended: false));
      port.onAction = (_, _) async => OnboardingReply(facts: port.facts);
      final c = OnboardingController(port);
      addTearDown(c.dispose);
      await c.initialize();
      await c.next();
      c.chooseMode(OnboardingMode.local);
      await c.next();
      expect(c.value.step, OnboardingStep.mode);
      expect(c.value.modeApplied, false);
    },
  );

  test('starts in welcome without automatically selecting a mode', () async {
    final port = FakeOnboardingPort(facts());
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await c.initialize();
    await c.initialize();
    expect(port.reads, 1);
    expect(c.value.step, OnboardingStep.welcome);
    expect(c.value.mode, isNull);
    await c.next();
    expect(c.canContinue, false);
    expect(port.actions, isEmpty);
  });

  for (final mode in OnboardingMode.values) {
    for (final evidence in [
      OnboardingEvidence.missing,
      OnboardingEvidence.conflict,
      OnboardingEvidence.failed,
      OnboardingEvidence.checking,
      OnboardingEvidence.unavailable,
    ]) {
      test('${mode.name} cannot bypass ${evidence.name}', () async {
        final port = FakeOnboardingPort(facts(evidence: evidence));
        final c = OnboardingController(port);
        addTearDown(c.dispose);
        await identity(c, mode: mode);
        await c.next();
        await c.run(OnboardingAction.confirmHandle);
        expect(c.value.step, OnboardingStep.identity);
        expect(c.canContinue, false);
        expect(
          port.actions.where((a) => a != OnboardingAction.applyMode),
          evidence == OnboardingEvidence.checking
              ? [OnboardingAction.refresh]
              : isEmpty,
        );
        expect(port.finishes, 0);
      });
    }
  }

  test('local mode does not sign in and excludes online steps', () async {
    final port = FakeOnboardingPort(facts(signedIn: false, matched: false));
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await identity(c);
    expect(c.value.steps, isNot(contains(OnboardingStep.online)));
    expect(c.canContinue, true);
    expect(port.actions, isEmpty);
  });

  test('online choice alone cannot advance past sign-in', () async {
    final port = FakeOnboardingPort(facts(signedIn: false));
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await c.initialize();
    await c.next();
    c.chooseMode(OnboardingMode.online);
    await c.next();
    expect(c.value.step, OnboardingStep.mode);
    expect(port.actions, isEmpty);
    c.chooseMode(OnboardingMode.local);
    await c.next();
    expect(c.value.step, OnboardingStep.log);
  });

  test('sign-in cannot replace local log evidence', () async {
    final port = FakeOnboardingPort(facts(evidenceKey: null, confirmed: true));
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await identity(c, mode: OnboardingMode.online);
    expect(c.canContinue, false);
  });

  test('historical candidate requires completed scope checks', () async {
    final port = FakeOnboardingPort(
      facts(origin: OnboardingEvidenceOrigin.history, scopeChecked: false),
    );
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await identity(c);
    expect(c.canContinue, false);
    port.facts = facts(origin: OnboardingEvidenceOrigin.history);
    await c.refresh();
    expect(c.canContinue, true);
  });

  test(
    'stored local association cannot clear a pending fresh-session gate',
    () async {
      final port = FakeOnboardingPort(
        facts(evidence: OnboardingEvidence.missing),
      );
      final c = OnboardingController(port);
      addTearDown(c.dispose);
      await identity(c);
      port.facts = facts(
        origin: OnboardingEvidenceOrigin.confirmedLocal,
        confirmed: true,
      );
      await c.refresh();
      expect(c.value.needsFreshEvidence, true);
      expect(c.value.identityReady, false);
      expect(c.canContinue, false);
    },
  );

  test(
    'confirmed local profile survives game exit without online authority',
    () async {
      final port = FakeOnboardingPort(
        facts(
          origin: OnboardingEvidenceOrigin.confirmedLocal,
          scopeChecked: false,
          confirmed: true,
          signedIn: false,
          matched: false,
        ),
      );
      final c = OnboardingController(port);
      addTearDown(c.dispose);
      await identity(c);
      expect(c.value.identityReady, true);
      expect(c.value.onlineIdentityReady, false);
      expect(c.canContinue, true);
      await c.next();
      expect(c.value.step, OnboardingStep.local);
    },
  );

  test('missing Handle gate survives back, mode and version changes', () async {
    final port = FakeOnboardingPort(
      facts(evidence: OnboardingEvidence.missing),
    );
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await identity(c);
    expect(c.value.needsFreshEvidence, true);
    c.back();
    c.back();
    c.chooseMode(OnboardingMode.online);
    await c.next();
    await c.next();
    port.facts = facts(
      source: 'fixture-ptu-1',
      origin: OnboardingEvidenceOrigin.freshSession,
      activeMode: OnboardingMode.online,
    );
    await c.refresh();
    expect(c.value.needsFreshEvidence, false);
    port.facts = facts(
      origin: OnboardingEvidenceOrigin.history,
      activeMode: OnboardingMode.online,
    );
    await c.refresh();
    expect(c.value.needsFreshEvidence, true);
    expect(c.canContinue, false);
    port.facts = facts(
      origin: OnboardingEvidenceOrigin.freshSession,
      activeMode: OnboardingMode.online,
    );
    await c.refresh();
    expect(c.value.needsFreshEvidence, false);
    expect(c.canContinue, true);
  });

  test('incomplete checks do not establish the missing-Handle gate', () async {
    final port = FakeOnboardingPort(
      facts(evidence: OnboardingEvidence.missing, scopeChecked: false),
    );
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await identity(c);
    expect(c.value.needsFreshEvidence, false);
    expect(c.canContinue, false);
  });

  test('Host fresh-evidence requirement survives restored progress', () async {
    final port = FakeOnboardingPort(facts(confirmed: true, requiresFresh: true))
      ..restored = const OnboardingCheckpoint(
        step: OnboardingStep.summary,
        mode: OnboardingMode.local,
        sourceKey: 'fixture-live-1',
        evidenceKey: 'fixture-evidence-1',
      );
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await c.initialize();
    expect(c.value.step, OnboardingStep.identity);
    expect(c.canContinue, false);
    expect(c.value.completed, false);
  });

  test('confirmation must come back from the owning domain', () async {
    final port = FakeOnboardingPort(facts());
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await identity(c);
    await c.next();
    expect(c.value.step, OnboardingStep.identity);
    expect(port.actions, [OnboardingAction.confirmHandle]);
    port.facts = facts(confirmed: true);
    await c.next();
    expect(c.value.step, OnboardingStep.local);
  });

  test('SCM mismatch blocks online identity only', () async {
    final port = FakeOnboardingPort(facts(matched: false));
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await identity(c, mode: OnboardingMode.online);
    expect(c.canContinue, false);
    c.back();
    c.back();
    c.chooseMode(OnboardingMode.local);
    await c.next();
    await c.next();
    expect(c.canContinue, true);
  });

  test(
    'online completion requires explicit online choices, not login',
    () async {
      final port = FakeOnboardingPort(
        facts(confirmed: true, onlineReviewed: false),
      );
      final c = OnboardingController(port);
      addTearDown(c.dispose);
      await identity(c, mode: OnboardingMode.online);
      await c.next();
      await c.next();
      expect(c.value.step, OnboardingStep.online);
      expect(c.canContinue, false);
      expect(port.finishes, 0);
    },
  );

  for (final acknowledge in [true, false]) {
    test('finish requires matching receipt: $acknowledge', () async {
      final port = FakeOnboardingPort(facts(confirmed: true))
        ..finishReceipt = acknowledge;
      final c = OnboardingController(port);
      addTearDown(c.dispose);
      await identity(c);
      await c.next();
      await c.next();
      // The optional recognition check sits before the summary.
      expect(c.value.step, OnboardingStep.verify);
      await c.next();
      expect(c.value.step, OnboardingStep.summary);
      expect(c.value.completed, false);
      await c.next();
      expect(c.value.completed, acknowledge);
      expect(c.value.error, !acknowledge);
      expect(port.finishes, 1);
    });
  }

  test('save receipt for another revision is rejected', () async {
    final port = FakeOnboardingPort(facts())
      ..alterReceipt = (p) => OnboardingCheckpoint(
        step: p.step,
        mode: p.mode,
        sourceKey: 'fixture-wrong-source',
        evidenceKey: p.evidenceKey,
      );
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await identity(c);
    expect(await c.save(), false);
    expect(c.value.saved, false);
    expect(c.value.completed, false);
    expect(c.value.error, true);
  });

  test('saving unfinished progress never completes the guide', () async {
    final port = FakeOnboardingPort(
      facts(evidence: OnboardingEvidence.missing),
    );
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await identity(c);
    expect(await c.save(), true);
    expect(c.value.step, OnboardingStep.identity);
    expect(c.value.completed, false);
    expect(c.value.needsFreshEvidence, true);
  });

  test('unsupported persistence cannot claim save or completion', () async {
    final port = FakeOnboardingPort(facts(canSave: false, confirmed: true));
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await identity(c);
    await c.next();
    await c.next();
    expect(await c.save(), false);
    await c.next();
    expect(port.finishes, 0);
    expect(port.saves, 0);
  });

  test('restoring changed source starts at log, not saved summary', () async {
    final port = FakeOnboardingPort(facts(confirmed: true))
      ..restored = const OnboardingCheckpoint(
        step: OnboardingStep.summary,
        mode: OnboardingMode.local,
        sourceKey: 'fixture-other-installation',
        evidenceKey: 'fixture-evidence-1',
      );
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await c.initialize();
    expect(c.value.step, OnboardingStep.log);
    expect(c.value.completed, false);
  });

  test('loss of identity clamps later steps and blocks completion', () async {
    final port = FakeOnboardingPort(facts(confirmed: true));
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await identity(c);
    await c.next();
    await c.next();
    port.facts = facts(evidence: OnboardingEvidence.failed);
    await c.refresh();
    expect(c.value.step, OnboardingStep.identity);
    expect(c.canContinue, false);
  });

  test('read failure keeps old content but cannot continue', () async {
    final port = FakeOnboardingPort(facts(confirmed: true));
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await identity(c);
    port.readThrows = true;
    await c.refresh();
    expect(c.value.facts.handle, 'Pilot-Example');
    expect(c.value.error, true);
    expect(c.canContinue, false);
  });

  test('cancel login ignores the late login result', () async {
    final held = Completer<OnboardingReply>();
    final port = FakeOnboardingPort(facts(signedIn: false));
    port.onAction = (action, _) async => action == OnboardingAction.login
        ? held.future
        : OnboardingReply(facts: facts(signedIn: false));
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await c.initialize();
    await c.next();
    c.chooseMode(OnboardingMode.online);
    final login = c.run(OnboardingAction.login);
    expect(c.canCancelLogin, true);
    await c.run(OnboardingAction.cancelLogin);
    c.chooseMode(OnboardingMode.local);
    held.complete(OnboardingReply(facts: facts()));
    await login;
    expect(c.value.mode, OnboardingMode.local);
    expect(c.value.facts.signedIn, false);
    expect(c.value.busy, false);
  });

  test('disposed controller ignores late replies', () async {
    final held = Completer<OnboardingReply>();
    final port = FakeOnboardingPort(facts())..onAction = (_, _) => held.future;
    final c = OnboardingController(port);
    await identity(c);
    final request = c.run(OnboardingAction.refresh);
    c.dispose();
    held.complete(OnboardingReply(facts: facts(confirmed: true)));
    await request;
  });

  test('commands for other steps cannot grant settings confirmation', () async {
    final port = FakeOnboardingPort(facts());
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await c.initialize();
    await c.run(OnboardingAction.confirmHandle);
    await c.run(OnboardingAction.reviewLocalSettings);
    await c.run(OnboardingAction.reviewOnlineChoices);
    await c.run(OnboardingAction.login);
    expect(port.actions, isEmpty);
  });

  test(
    'Host invalidation rechecks and revokes stale identity readiness',
    () async {
      final events = StreamController<void>.broadcast(sync: true);
      addTearDown(events.close);
      final port = FakeOnboardingPort(facts(confirmed: true))
        ..events = events.stream;
      final c = OnboardingController(port);
      addTearDown(c.dispose);
      await identity(c);
      await c.next();
      port.facts = facts(evidence: OnboardingEvidence.failed);
      events.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(c.value.step, OnboardingStep.identity);
      expect(c.canContinue, false);
    },
  );

  test('invalidations during a command coalesce into one recheck', () async {
    final events = StreamController<void>.broadcast(sync: true);
    addTearDown(events.close);
    final held = Completer<OnboardingReply>();
    final port = FakeOnboardingPort(facts())
      ..events = events.stream
      ..onAction = (_, _) => held.future;
    final c = OnboardingController(port);
    addTearDown(c.dispose);
    await identity(c);
    final reads = port.reads;
    final request = c.run(OnboardingAction.refresh);
    events.add(null);
    events.add(null);
    port.facts = facts(evidence: OnboardingEvidence.missing);
    held.complete(OnboardingReply(facts: facts()));
    await request;
    await Future<void>.delayed(Duration.zero);
    expect(port.reads, reads + 1);
    expect(c.value.needsFreshEvidence, true);
    expect(c.canContinue, false);
  });

  test(
    'confirmation of a changed source cannot advance the new identity',
    () async {
      final port = FakeOnboardingPort(facts())
        ..onAction = (_, _) async => OnboardingReply(
          facts: facts(source: 'fixture-ptu-2', confirmed: true),
        );
      final c = OnboardingController(port);
      addTearDown(c.dispose);
      await identity(c);
      await c.next();
      expect(c.value.step, OnboardingStep.identity);
    },
  );

  test(
    'disposing during Next ignores confirmation and detaches events',
    () async {
      final events = StreamController<void>.broadcast(sync: true);
      addTearDown(events.close);
      final held = Completer<OnboardingReply>();
      final port = FakeOnboardingPort(facts())
        ..events = events.stream
        ..onAction = (_, _) => held.future;
      final c = OnboardingController(port);
      await identity(c);
      final request = c.next();
      c.dispose();
      events.add(null);
      held.complete(OnboardingReply(facts: facts(confirmed: true)));
      await request;
      expect(c.canContinue, false);
      expect(events.hasListener, false);
    },
  );
}
