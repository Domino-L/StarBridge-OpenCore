import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/game_log/local_game_log_setup_panel.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/features/onboarding/online_installation_port.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_controller.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_port.dart';
import 'package:starbridge_flutter/features/settings/usage_mode_controller.dart';
import 'package:starbridge_flutter/features/settings/usage_mode_page.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../onboarding/bridge_onboarding_adapter_test.dart' show wire;
import '../onboarding/onboarding_test_support.dart';
import '../onboarding/online_review_test_support.dart';
import 'usage_mode_test.dart' as fixture;

class PendingLogMode extends fixture.ModePort {
  PendingLogMode() : super(hasLog: true);
  bool identityConfirmed = true, logPending = true;

  @override
  OnboardingReply observation() => OnboardingReply(
    facts: facts(
      logReady: hasLog,
      confirmed: identityConfirmed,
      logSetupPending: logPending,
      signedIn: loggedIn,
      matched: matched,
      onlineSetupPending: pending,
    ),
    restored: restored,
    completed: receipt,
  );
}

class ObservedInstallation extends fixture.Installation {
  ObservedInstallation(super.mode, this.phase);
  final OnlineInstallationPhase phase;
  int reads = 0;

  @override
  Future<OnlineInstallationSnapshot> read(int revision) async {
    reads++;
    return snapshot(phase);
  }
}

void main() {
  UsageModeController create(
    PendingLogMode port,
    FakeOnlinePort online, {
    OnlineInstallationPhase phase = OnlineInstallationPhase.idle,
  }) {
    final c = UsageModeController(
      port,
      OnlineReviewController(online),
      ObservedInstallation(port, phase),
    );
    addTearDown(c.dispose);
    addTearDown(c.review.dispose);
    addTearDown(online.close);
    return c;
  }

  for (final checkpoint in [
    OnboardingStep.log,
    OnboardingStep.identity,
    OnboardingStep.online,
  ]) {
    for (final confirmed in [false, true]) {
      test(
        'pending log clamps restored $checkpoint (review=$confirmed)',
        () async {
          final port = PendingLogMode()
            ..pending = true
            ..loggedIn = true
            ..matched = true
            ..restored = OnboardingCheckpoint(
              step: checkpoint,
              mode: OnboardingMode.online,
            );
          final online = FakeOnlinePort()
            ..snapshot = OnlineReviewSnapshot(
              revision: 3,
              modeState: OnlineReviewModeState.signInRequired,
              state: confirmed
                  ? OnlineReviewState.confirmedForHandoff
                  : OnlineReviewState.needsLocalIdentity,
            );
          final c = create(port, online);
          await c.refresh();
          expect(c.usableLog, false);
          expect(c.step, UsageModeStep.log);
          expect(port.restored?.step, OnboardingStep.log);
          expect((c.installation as ObservedInstallation).reads, 0);
          expect((c.installation as ObservedInstallation).installs, 0);
          await c.refresh();
          expect(c.step, UsageModeStep.log);
          port.logPending = false;
          await c.refresh();
          expect(
            c.step,
            confirmed ? UsageModeStep.installation : UsageModeStep.names,
          );
        },
      );
    }
  }

  test(
    'pending log precedes even an installation observation on restore',
    () async {
      final port = PendingLogMode()
        ..pending = true
        ..loggedIn = true
        ..matched = true
        ..restored = const OnboardingCheckpoint(
          step: OnboardingStep.online,
          mode: OnboardingMode.online,
        );
      final online = FakeOnlinePort()
        ..snapshot = const OnlineReviewSnapshot(
          revision: 3,
          modeState: OnlineReviewModeState.signInRequired,
          state: OnlineReviewState.confirmedForHandoff,
        );
      final c = create(port, online, phase: OnlineInstallationPhase.running);
      await c.refresh();
      expect(c.step, UsageModeStep.log);
      expect((c.installation as ObservedInstallation).reads, 0);
    },
  );

  test(
    'pending log blocks account, log, name and install advancement',
    () async {
      final port = PendingLogMode()
        ..loggedIn = true
        ..matched = true;
      final online = FakeOnlinePort()
        ..snapshot = const OnlineReviewSnapshot(
          revision: 3,
          modeState: OnlineReviewModeState.signInRequired,
          state: OnlineReviewState.confirmedForHandoff,
        );
      final c = create(port, online);
      await c.refresh();
      await c.begin();
      await c.accountConfirmed();
      expect(c.step, UsageModeStep.log);
      await c.logConfirmed();
      expect(c.step, UsageModeStep.log);
      await c.namesConfirmed();
      expect(c.step, UsageModeStep.log);
      await c.install();
      expect(c.failed, true);
      expect((c.installation as ObservedInstallation).installs, 0);
      port.logPending = false;
      await c.logConfirmed();
      expect(c.failed, false);
      expect(c.step, UsageModeStep.names);
      await c.namesConfirmed();
      expect(c.step, UsageModeStep.installation);
    },
  );

  testWidgets(
    'reopening after migration failure keeps log retry until success',
    (tester) async {
      // Completed local first use without a log. The deferred statistics choice
      // belongs to Host; the bridge below simulates its first migration failing.
      final port = PendingLogMode()
        ..hasLog = false
        ..identityConfirmed = false
        ..logPending = false;
      final online = FakeOnlinePort()
        ..snapshot = const OnlineReviewSnapshot(
          revision: 3,
          modeState: OnlineReviewModeState.signInRequired,
          state: OnlineReviewState.needsLocalIdentity,
        );
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 7,
      );
      session.acceptHostCapabilities(['onboarding.firstUse.v1']);
      final actions = <String>[];
      final subscription = pair.host.incoming.listen((request) {
        if (request.messageType != 'request') return;
        var failed = false;
        if (request.name == 'onboarding.execute') {
          final action = request.payload['action']! as String;
          actions.add(action);
          if (action == 'selectLog') port.hasLog = true;
          if (action == 'confirmHandle') {
            port.identityConfirmed = true;
            port.logPending = true;
            failed = true;
          }
          if (action == 'finishLogSetup') port.logPending = false;
        }
        final payload = wire();
        (payload['facts']! as Map<String, Object?>).addAll({
          'logReady': port.hasLog,
          'logDeferred': !port.hasLog,
          'localIdentityConfirmed': port.identityConfirmed,
          'logSetupPending': port.logPending,
          'onlineSetupPending': port.pending,
          'signedIn': port.loggedIn,
        });
        if (!port.hasLog) {
          (payload['facts']! as Map<String, Object?>).addAll({
            'sourceKey': null,
            'evidenceKey': null,
            'version': null,
            'evidence': 'unavailable',
            'origin': null,
            'handle': null,
            'observedAt': null,
          });
        }
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: 7,
              status: failed ? 'error' : 'ok',
              error: failed
                  ? const BridgeErrorBody(
                      code: 'synthetic.statistics_locked',
                      message: 'Synthetic statistics migration failure',
                      retryable: true,
                    )
                  : null,
              payload: payload,
            ),
          ),
        );
      });
      addTearDown(() async {
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      });

      Future<void> open(UsageModeController c) async {
        const locale = Locale('zh', 'CN');
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: const [locale],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: buildStarBridgeTheme(
              FutureRestraintStyle.resolve(AppearanceMode.dark),
              locale,
            ),
            home: Scaffold(
              body: UsageModePage(
                controller: c,
                logPanel: (confirmed) => LocalGameLogSetupPanel(
                  session: session,
                  allowOnlineSetup: true,
                  onConfirmed: confirmed,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> tap(String key) async {
        final button = find.byKey(Key(key));
        expect(button, findsOneWidget, reason: key);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      final first = create(port, online);
      await open(first);
      await tap('usage-mode-to-online');
      port.loggedIn = true;
      await first.accountConfirmed();
      await tester.pumpAndSettle();
      await tap('local-settings-select-log');
      await tap('local-settings-confirm-handle');
      expect(port.logPending, true);
      expect(first.step, UsageModeStep.log);
      expect(find.text('游戏日志已确认，但统计设置还没保存好。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      final reopened = create(
        port,
        FakeOnlinePort()..snapshot = online.snapshot,
      );
      await open(reopened);
      expect(reopened.step, UsageModeStep.log);
      expect(find.text('游戏日志已确认，但统计设置还没保存好。'), findsOneWidget);
      expect(find.byKey(const Key('usage-mode-names')), findsNothing);
      final retry = find.byKey(const Key('local-settings-finish-log-setup'));
      expect(
        find.descendant(of: retry, matching: find.text('重试')),
        findsOneWidget,
      );
      await tap('local-settings-finish-log-setup');
      expect(actions, [
        'locateLogs',
        'selectLog',
        'refresh',
        'confirmHandle',
        'locateLogs',
        'finishLogSetup',
      ]);
      expect(port.logPending, false);
      expect(reopened.step, UsageModeStep.names);
      expect(find.byKey(const Key('usage-mode-names')), findsOneWidget);
      expect(find.text('游戏日志已确认，但统计设置还没保存好。'), findsNothing);
      expect(port.online, false);
      expect(port.finishes, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
