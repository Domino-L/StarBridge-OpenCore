import 'package:starbridge_flutter/features/onboarding/onboarding_entry.dart';

import '../friends/social_layout_test.dart' show app, loadFonts;

import 'package:starbridge_flutter/features/onboarding/online_review_controller.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_port.dart';
import 'package:starbridge_flutter/features/onboarding/online_installation_port.dart';

import 'online_review_test_support.dart' show FakeOnlinePort;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_controller.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_copy.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';

import 'nolog_onboarding_test.dart' show deferred;
import 'bridge_onboarding_adapter_test.dart' show wire;

import 'package:starbridge_flutter/features/onboarding/bridge_onboarding_adapter.dart';

import 'onboarding_page_test.dart' show pumpSetup;
import 'onboarding_test_support.dart';

void main() {
  for (final acknowledged in [false, true]) {
    test(
      'back to log can defer only after pending online retirement: $acknowledged',
      () async {
        final port = FakeOnboardingPort(
          facts(
            confirmed: true,
            matched: false,
            onlineReviewed: false,
            onlineSetupPending: true,
          ),
        );
        port.restored = OnboardingCheckpoint(
          step: OnboardingStep.mode,
          mode: OnboardingMode.online,
          sourceKey: port.facts.sourceKey,
          evidenceKey: port.facts.evidenceKey,
        );
        port.onAction = (action, checkpoint) async {
          if (action == OnboardingAction.applyMode && acknowledged) {
            expect(checkpoint.step, OnboardingStep.log);
            expect(checkpoint.mode, OnboardingMode.local);
            port.facts = facts(
              confirmed: true,
              signedIn: false,
              matched: false,
            );
          } else if (action == OnboardingAction.skipLog) {
            expect(acknowledged, isTrue);
            port.facts = deferred;
          }
          return OnboardingReply(facts: port.facts);
        };
        final c = OnboardingController(port, skipWelcomeIntro: true);
        addTearDown(c.dispose);
        await c.initialize();
        c.back();
        c.back();
        expect(c.value.step, OnboardingStep.log);
        await c.run(OnboardingAction.skipLog);
        expect(
          port.actions,
          acknowledged
              ? [OnboardingAction.applyMode, OnboardingAction.skipLog]
              : [OnboardingAction.applyMode],
        );
        expect(c.value.withoutLog, acknowledged);
        if (acknowledged) {
          await c.next();
          expect(c.value.step, OnboardingStep.mode);
          c.chooseMode(OnboardingMode.online);
          expect(c.value.mode, OnboardingMode.local);
        } else {
          expect(c.value.error, isTrue);
          expect(c.canContinue, isFalse);
        }
      },
    );
  }
  setUpAll(loadFonts);
  testWidgets(
    'real guide entry defers retained installation until explicit step five',
    (tester) async {
      final main = FakeOnboardingPort(
        facts(
          confirmed: true,
          matched: false,
          signedIn: false,
          onlineReviewed: false,
          onlineSetupPending: true,
        ),
      );
      main.restored = OnboardingCheckpoint(
        step: OnboardingStep.mode,
        mode: OnboardingMode.online,
        sourceKey: main.facts.sourceKey,
        evidenceKey: main.facts.evidenceKey,
      );
      final port = FakeOnlinePort()
        ..snapshot = const OnlineReviewSnapshot(
          revision: 3,
          retainsSession: true,
          modeState: OnlineReviewModeState.signInRequired,
          state: OnlineReviewState.signInRequired,
        );
      addTearDown(port.close);
      final installation = _UnexpectedInstallation();
      var hostInstallations = 0;
      port.onAction = (action) async {
        final confirmed = action == OnlineReviewAction.confirm;
        port.snapshot = OnlineReviewSnapshot(
          revision: 3,
          retainsSession: true,
          modeState: OnlineReviewModeState.signInRequired,
          state: confirmed
              ? OnlineReviewState.confirmedForHandoff
              : OnlineReviewState.reviewRequired,
          localHandle: 'Pilot-Example',
          authoritativeHandle: 'PILOT-EXAMPLE',
          confirmationKey: confirmed
              ? null
              : '11111111111111111111111111111111',
        );
        main.facts = facts(
          confirmed: true,
          matched: confirmed,
          onlineReviewed: false,
          onlineSetupPending: true,
        );
        return port.snapshot;
      };
      main.onAction = (action, checkpoint) async {
        expect(action, OnboardingAction.reviewOnlineChoices);
        hostInstallations++;
        main.facts = facts(
          confirmed: true,
          activeMode: OnboardingMode.online,
          publicationSuspended: false,
        );
        return OnboardingReply(facts: main.facts);
      };
      late Future<void> opened;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () {
                opened = openFirstUseSetup(
                  context,
                  main,
                  onlineReview: port,
                  onlineInstallation: installation,
                  skipWelcomeIntro: true,
                );
              },
              child: const Text('Open setup'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open setup'));
      await tester.pumpAndSettle();
      Future<void> tap(String key) async {
        final target = find.byKey(Key(key));
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await tap('online-review-login');
      expect(port.actions, [OnlineReviewAction.resume]);
      expect(installation.calls, 0);
      expect(find.byKey(const Key('online-review-confirm')), findsOneWidget);
      await tap('online-review-confirm');
      expect(port.actions, [
        OnlineReviewAction.resume,
        OnlineReviewAction.confirm,
      ]);
      expect(installation.calls, 0);
      expect(hostInstallations, 0);
      // Retained accounts continue through their explicit confirmed card.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('onboarding-next')))
            .onPressed,
        isNull,
      );
      await tap('online-account-continue');
      expect(
        find.byKey(const Key('onboarding-action-reviewOnlineChoices')),
        findsNothing,
      );
      await tap('onboarding-next');
      expect(
        find.byKey(const Key('onboarding-action-reviewOnlineChoices')),
        findsOneWidget,
      );
      expect(hostInstallations, 0);
      await tap('onboarding-action-reviewOnlineChoices');
      expect(hostInstallations, 1);
      expect(installation.calls, 0);
      await tap('onboarding-close');
      await opened;
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'retained guide login never auto-confirms or installs before step five',
    () async {
      final port = FakeOnlinePort()
        ..snapshot = const OnlineReviewSnapshot(
          revision: 3,
          retainsSession: true,
          modeState: OnlineReviewModeState.signInRequired,
          state: OnlineReviewState.signInRequired,
        );
      final installation = _UnexpectedInstallation();
      final c = OnlineReviewController(
        port,
        installation: installation,
        autoInstallRetainedAccount: false,
      );
      addTearDown(c.dispose);
      addTearDown(port.close);
      port.onAction = (action) async {
        port.snapshot = OnlineReviewSnapshot(
          revision: 3,
          retainsSession: true,
          modeState: OnlineReviewModeState.signInRequired,
          state: action == OnlineReviewAction.confirm
              ? OnlineReviewState.confirmedForHandoff
              : OnlineReviewState.reviewRequired,
          localHandle: 'Pilot-Example',
          authoritativeHandle: 'PILOT-EXAMPLE',
          confirmationKey: action == OnlineReviewAction.confirm
              ? null
              : '11111111111111111111111111111111',
        );
        return port.snapshot;
      };
      await c.refresh();
      await c.signIn();
      expect(port.actions, [OnlineReviewAction.resume]);
      expect(c.value.canConfirm, isTrue);
      expect(installation.calls, 0);
      await c.execute(OnlineReviewAction.confirm);
      expect(port.actions, [
        OnlineReviewAction.resume,
        OnlineReviewAction.confirm,
      ]);
      expect(c.value.snapshot.identityConfirmed, isTrue);
      await c.refresh();
      expect(installation.calls, 0);
    },
  );
  for (final confirmed in [false, true]) {
    test(
      'source edits clearing UI progress resume from real identity: $confirmed',
      () async {
        final port = FakeOnboardingPort(facts(confirmed: confirmed));
        final c = OnboardingController(port, skipWelcomeIntro: true);
        addTearDown(c.dispose);
        await c.initialize();
        expect(
          c.value.step,
          confirmed ? OnboardingStep.mode : OnboardingStep.identity,
        );
        expect(c.value.completed, isFalse);
        expect(port.finishes, 0);
        expect(port.saves, 1);
        await c.initialize();
        expect(port.saves, 1);
      },
    );
  }
  test(
    'deferred domain state with no checkpoint resumes at mode, never online',
    () async {
      final port = FakeOnboardingPort(deferred);
      final c = OnboardingController(port, skipWelcomeIntro: true);
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.value.step, OnboardingStep.mode);
      expect(port.saves, 1);
      c.chooseMode(OnboardingMode.online);
      expect(c.value.mode, OnboardingMode.local);
    },
  );
  test('log and identity wire checkpoints retain the legacy non-null mode contract', () {
    for (final step in ['log', 'identity']) {
      final payload = wire();
      payload['restored'] = {
        'step': step,
        'mode': null,
        'sourceKey': null,
        'evidenceKey': null,
      };
      expect(() => OnboardingWire.parse(payload), throwsFormatException);
    }
  });
  test('opening the log step leaves an online account online', () async {
    final port = FakeOnboardingPort(
      facts(
        logReady: false,
        evidence: OnboardingEvidence.unavailable,
        activeMode: OnboardingMode.online,
        publicationSuspended: false,
      ),
    );
    final c = OnboardingController(port, skipWelcomeIntro: true);
    addTearDown(c.dispose);
    await c.initialize();
    expect(c.value.step, OnboardingStep.log);
    // Host is only asked to prepare a device without any account; this
    // signed-in account stays online.
    expect(port.actions, [OnboardingAction.prepareLog]);
    expect(c.value.mode, OnboardingMode.online);
    expect(c.value.facts.publicationSuspended, isFalse);
    expect(c.canUseLocalForLog, isFalse);
    expect(c.canContinue, isFalse);
    expect(c.value.completed, isFalse);
  });

  test(
    'a new device without a mode or account is prepared for the log step',
    () async {
      // Host projects the unchosen mode as online.
      final port = FakeOnboardingPort(
        facts(
          logReady: false,
          evidence: OnboardingEvidence.unavailable,
          signedIn: false,
          activeMode: OnboardingMode.online,
          publicationSuspended: false,
        ),
      );
      port.onAction = (action, checkpoint) async {
        if (action == OnboardingAction.prepareLog) {
          expect(checkpoint.step, OnboardingStep.log);
          expect(checkpoint.mode, OnboardingMode.local);
          port.facts = facts(
            logReady: false,
            evidence: OnboardingEvidence.unavailable,
            signedIn: false,
          );
        }
        return OnboardingReply(facts: port.facts);
      };
      final c = OnboardingController(port, skipWelcomeIntro: true);
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.value.step, OnboardingStep.log);
      expect(port.actions.first, OnboardingAction.prepareLog);
      expect(port.actions, isNot(contains(OnboardingAction.applyMode)));
      expect(c.value.mode, OnboardingMode.local);
      expect(c.value.modeApplied, isTrue);
      expect(c.value.error, isFalse);
      expect(c.canUseLocalForLog, isFalse);
      await c.searchLogsOnEntry();
      expect(port.actions, contains(OnboardingAction.locateLogs));
    },
  );

  test('online without an account here switches only after a click', () async {
    final port = FakeOnboardingPort(
      facts(
        eligibility: OnboardingEligibility.unknown,
        logReady: false,
        evidence: OnboardingEvidence.unavailable,
        signedIn: false,
        activeMode: OnboardingMode.online,
        publicationSuspended: false,
      ),
    );
    final c = OnboardingController(port, skipWelcomeIntro: true);
    addTearDown(c.dispose);
    await c.initialize();
    // Host kept the account (signed in elsewhere, restoring or unavailable).
    expect(port.actions, [OnboardingAction.prepareLog]);
    expect(c.value.mode, OnboardingMode.online);
    expect(c.canUseLocalForLog, isTrue);
    await c.run(OnboardingAction.skipLog);
    expect(port.actions, [OnboardingAction.prepareLog]);
    await c.useLocalForLog();
    expect(port.actions, [
      OnboardingAction.prepareLog,
      OnboardingAction.applyMode,
      OnboardingAction.locateLogs,
    ]);
    expect(c.value.mode, OnboardingMode.local);
    expect(c.value.modeApplied, isTrue);
    expect(c.canUseLocalForLog, isFalse);
  });

  test(
    'log, identity, mode, local, verify and summary require Host facts',
    () async {
      final port = FakeOnboardingPort(facts())
        ..restored = const OnboardingCheckpoint(
          step: OnboardingStep.log,
          mode: OnboardingMode.local,
        );
      final c = OnboardingController(port, skipWelcomeIntro: true);
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.value.steps, [
        OnboardingStep.welcome,
        OnboardingStep.log,
        OnboardingStep.identity,
        OnboardingStep.mode,
        OnboardingStep.local,
        OnboardingStep.verify,
        OnboardingStep.summary,
      ]);
      await c.next();
      expect(c.value.step, OnboardingStep.identity);
      await c.next();
      expect(c.value.step, OnboardingStep.identity);
      expect(port.actions, [OnboardingAction.confirmHandle]);
      port.facts = facts(confirmed: true);
      await c.refresh();
      await c.next();
      expect(c.value.step, OnboardingStep.mode);
      await c.next();
      expect(c.value.step, OnboardingStep.local);
      await c.next();
      expect(c.value.step, OnboardingStep.verify);
      await c.next();
      expect(c.value.step, OnboardingStep.summary);
      expect(c.value.completed, isFalse);
      await c.next();
      expect(c.value.completed, isTrue);
    },
  );

  for (final ready in [false, true]) {
    test('old mode checkpoint resumes by real log state: $ready', () async {
      final port = FakeOnboardingPort(
        ready
            ? facts(confirmed: true)
            : const OnboardingFacts(
                available: true,
                canSave: true,
                activeMode: OnboardingMode.local,
                publicationSuspended: true,
              ),
      );
      port.restored = const OnboardingCheckpoint(step: OnboardingStep.mode);
      final c = OnboardingController(port, skipWelcomeIntro: true);
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.value.step, ready ? OnboardingStep.mode : OnboardingStep.log);
      expect(c.value.completed, isFalse);
    });
  }

  for (final signedIn in [false, true]) {
    test(
      'online choice requires separate explicit SCM confirmation: $signedIn',
      () async {
        final port = FakeOnboardingPort(
          facts(confirmed: true, signedIn: signedIn, matched: false),
        );
        port.restored = OnboardingCheckpoint(
          step: OnboardingStep.mode,
          mode: OnboardingMode.local,
          sourceKey: port.facts.sourceKey,
          evidenceKey: port.facts.evidenceKey,
        );
        final c = OnboardingController(port);
        addTearDown(c.dispose);
        await c.initialize();
        c.chooseMode(OnboardingMode.online);
        expect(c.canContinue, isFalse);
        await c.run(OnboardingAction.applyMode);
        await c.next();
        expect(c.value.step, OnboardingStep.mode);
        expect(port.finishes, 0);
        port.facts = facts(
          confirmed: true,
          signedIn: true,
          matched: true,
          activeMode: OnboardingMode.online,
          publicationSuspended: false,
          onlineReviewed: false,
        );
        await c.refresh();
        await c.next();
        expect(c.value.step, OnboardingStep.local);
        await c.next();
        expect(c.value.step, OnboardingStep.online);
        expect(c.canContinue, isFalse);
      },
    );
  }

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    testWidgets(
      'no-log online option is disabled with actual settings path: $locale',
      (tester) async {
        final c = await pumpSetup(
          tester,
          step: OnboardingStep.mode,
          mode: OnboardingMode.local,
          observation: deferred,
          locale: locale,
        );
        final radio = tester.widget<RadioListTile<OnboardingMode>>(
          find.byKey(const Key('onboarding-mode-online')),
        );
        expect(radio.enabled, isFalse);
        expect(
          find.text(OnboardingCopy(locale).text('onlineNeedsLog')),
          findsOneWidget,
        );
        c.chooseMode(OnboardingMode.online);
        expect(c.value.mode, OnboardingMode.local);
        await c.next();
        expect(c.value.step, OnboardingStep.local);
        expect(c.value.steps, isNot(contains(OnboardingStep.identity)));
        expect(c.value.steps, isNot(contains(OnboardingStep.online)));
        expect(c.value.steps, isNot(contains(OnboardingStep.verify)));
      },
    );
  }
  // Opening setup (also from Settings) must never switch modes by itself.
  for (final (name, observed, expectApply) in [
    (
      'online account',
      facts(
        eligibility: OnboardingEligibility.unknown,
        logReady: false,
        activeMode: OnboardingMode.online,
        publicationSuspended: false,
      ),
      false,
    ),
    (
      'pending online choice',
      facts(logReady: false, onlineSetupPending: true, signedIn: false),
      false,
    ),
    (
      'plain local session',
      facts(logReady: false, publicationSuspended: false),
      true,
    ),
  ]) {
    test('opening the log step switches no mode: $name', () async {
      final port = FakeOnboardingPort(observed);
      final c = OnboardingController(port, skipWelcomeIntro: true);
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.value.step, OnboardingStep.log);
      expect(port.actions.contains(OnboardingAction.applyMode), expectApply);
      expect(c.value.error, isFalse);
      if (!expectApply) {
        expect(c.value.mode, OnboardingMode.online);
        await c.retryLogSetup();
        expect(port.actions, isNot(contains(OnboardingAction.applyMode)));
      }
      if (name == 'online account') {
        await c.run(OnboardingAction.skipLog);
        expect(
          port.actions,
          everyElement(OnboardingAction.prepareLog),
          reason: 'no way to switch off online',
        );
        expect(c.canUseLocalForLog, isFalse);
      }
    });
  }
}

final class _UnexpectedInstallation implements OnlineInstallationPort {
  int calls = 0;
  @override
  bool get supported => true;
  @override
  Future<OnlineInstallationSnapshot> read(int revision) async {
    calls++;
    throw StateError(
      'Guide must not observe installation before the install step',
    );
  }

  @override
  Future<OnlineInstallationSnapshot> install(int revision) async {
    calls++;
    throw StateError(
      'Guide must install only through its explicit Host action',
    );
  }
}
