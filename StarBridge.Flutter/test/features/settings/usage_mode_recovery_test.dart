import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/features/onboarding/online_installation_port.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_controller.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_port.dart';
import 'package:starbridge_flutter/features/settings/usage_mode_controller.dart';
import 'package:starbridge_flutter/features/settings/usage_mode_copy.dart';
import 'package:starbridge_flutter/features/settings/usage_mode_page.dart';

import '../onboarding/onboarding_test_support.dart';
import '../onboarding/online_review_test_support.dart';
import 'usage_mode_test.dart' as fixture;

class RecoveryMode extends fixture.ModePort {
  bool recovering = true;
  @override
  OnboardingReply observation() => recovering
      ? OnboardingReply(facts: facts(activeMode: null), completed: receipt)
      : super.observation();
  @override
  Future<OnboardingReply> execute(
    OnboardingAction action,
    OnboardingCheckpoint checkpoint,
  ) async {
    if (action == OnboardingAction.applyMode &&
        checkpoint.mode == OnboardingMode.local) {
      recovering = false;
    }
    return super.execute(action, checkpoint);
  }
}

class FailedInstallation extends fixture.Installation {
  FailedInstallation(this.recovery, this.failure) : super(recovery);
  final RecoveryMode recovery;
  final OnlineInstallationFailure failure;
  @override
  Future<OnlineInstallationSnapshot> read(int revision) async =>
      recovery.recovering
      ? OnlineInstallationSnapshot(
          revision: revision,
          phase: OnlineInstallationPhase.completed,
          controlGeneration: 7,
          modeRevision: revision,
          modeState: 'recoveryRequired',
          failure: failure,
        )
      : super.read(revision);
}

class RejectingInstallation extends FailedInstallation {
  RejectingInstallation(super.recovery, super.failure);
  @override
  Future<OnlineInstallationSnapshot> install(int revision) async {
    installs++;
    recovery.recovering = true;
    return read(revision);
  }
}

class RunningInstallation extends fixture.Installation {
  RunningInstallation(super.mode);
  @override
  Future<OnlineInstallationSnapshot> read(int revision) async =>
      OnlineInstallationSnapshot(
        revision: revision,
        phase: OnlineInstallationPhase.running,
        controlGeneration: 7,
        modeRevision: revision,
        modeState: 'switching',
      );
}

void main() {
  test('installation failure retains stage/kind and recheck never replays the task', () async {
    final mode = RecoveryMode()
      ..recovering = false
      ..hasLog = true
      ..loggedIn = true
      ..matched = true;
    final reviewPort = FakeOnlinePort()
      ..snapshot = const OnlineReviewSnapshot(
        revision: 3,
        modeState: OnlineReviewModeState.signInRequired,
        state: OnlineReviewState.confirmedForHandoff,
      );
    final installation = RejectingInstallation(
      mode,
      const OnlineInstallationFailure('commitMode', 'storage'),
    );
    final c = UsageModeController(
      mode,
      OnlineReviewController(reviewPort),
      installation,
    );
    addTearDown(c.dispose);
    addTearDown(c.review.dispose);
    addTearDown(reviewPort.close);
    await c.refresh();
    c.step = UsageModeStep.installation;
    await c.install();
    expect(c.failure?.code, 'commitMode/storage');
    expect(c.recoveryRequired, true);
    expect(c.failed, true);
    await c.refresh();
    expect(c.failure?.code, 'commitMode/storage');
    expect(installation.installs, 1);
    await c.cancel();
    expect(c.recoveryRequired, false);
    expect(c.modeKnown, true);
    expect(c.failed, false);
  });

  test(
    'running installation is only observed on repeated install and refresh',
    () async {
      final mode = fixture.ModePort(hasLog: true)
        ..loggedIn = true
        ..matched = true
        ..pending = true
        ..restored = const OnboardingCheckpoint(
          step: OnboardingStep.online,
          mode: OnboardingMode.online,
        );
      final reviewPort = FakeOnlinePort()
        ..snapshot = const OnlineReviewSnapshot(
          revision: 3,
          modeState: OnlineReviewModeState.signInRequired,
          state: OnlineReviewState.confirmedForHandoff,
        );
      final installation = RunningInstallation(mode);
      final c = UsageModeController(
        mode,
        OnlineReviewController(reviewPort),
        installation,
      );
      addTearDown(c.dispose);
      addTearDown(c.review.dispose);
      addTearDown(reviewPort.close);
      await c.refresh();
      await c.install();
      await c.install();
      await c.refresh();
      expect(installation.installs, 0);
      expect(c.installationObservation?.phase, OnlineInstallationPhase.running);
    },
  );
  for (final stage in [
    'prepareAccount',
    'drainNative',
    'retireLocalSources',
    'stageBusiness',
    'configureBusiness',
    'activateBusiness',
    'installNative',
    'commitMode',
  ]) {
    for (final kind in [
      'cancelled',
      'rejected',
      'storage',
      'timeout',
      'unexpected',
      'notCommitted',
    ]) {
      testWidgets(
        'recovery $stage/$kind explains and returns through applyMode(local)',
        (tester) async {
          final mode = RecoveryMode(), reviewPort = FakeOnlinePort();
          reviewPort.snapshot = const OnlineReviewSnapshot(
            revision: 3,
            modeState: OnlineReviewModeState.recoveryRequired,
            state: OnlineReviewState.recoveryRequired,
          );
          // Model the Host's actual applyMode(local) readback, rather than hiding
          // recovery purely in the renderer or treating the action as successful.
          reviewPort.onRead = () async => mode.recovering
              ? reviewPort.snapshot
              : const OnlineReviewSnapshot(
                  revision: 4,
                  modeState: OnlineReviewModeState.local,
                  state: OnlineReviewState.notStarted,
                );
          final installation = FailedInstallation(
            mode,
            OnlineInstallationFailure(stage, kind),
          );
          final c = UsageModeController(
            mode,
            OnlineReviewController(reviewPort),
            installation,
          );
          addTearDown(c.dispose);
          addTearDown(c.review.dispose);
          addTearDown(reviewPort.close);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildStarBridgeTheme(
                FutureRestraintStyle.resolve(AppearanceMode.dark),
                const Locale('en'),
              ),
              home: Scaffold(
                body: UsageModePage(
                  controller: c,
                  logPanel: (_) => const SizedBox.shrink(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(c.recoveryRequired, true);
          expect(c.failure?.code, '$stage/$kind');
          expect(
            find.text(usageModeText(const Locale('en'), 'failure.$kind')),
            findsOneWidget,
          );
          expect(find.text('Diagnostic code: $stage/$kind'), findsNothing);
          final exit = find.byKey(const Key('usage-mode-recover-local'));
          await tester.ensureVisible(exit);
          await tester.tap(exit);
          await tester.pumpAndSettle();
          expect(mode.actions, contains(OnboardingAction.applyMode));
          expect(mode.recovering, false);
          expect(c.recoveryRequired, false);
          expect(c.failed, false);
          expect(find.text('Current: Local mode'), findsOneWidget);
          expect(find.byKey(const Key('usage-mode-to-online')), findsOneWidget);
          expect(installation.installs, 0);
          expect(mode.finishes, 0);
          expect(tester.takeException(), null);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
