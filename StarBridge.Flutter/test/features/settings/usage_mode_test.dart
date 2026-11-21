import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_copy.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_review_adapter.dart'
    show OnlineReviewWire;
import 'package:starbridge_flutter/features/onboarding/online_review_controller.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_port.dart';
import 'package:starbridge_flutter/features/onboarding/online_installation_port.dart';
import 'package:starbridge_flutter/features/settings/usage_mode_controller.dart';
import 'package:starbridge_flutter/features/settings/usage_mode_copy.dart';
import 'package:starbridge_flutter/features/settings/usage_mode_page.dart';

import '../onboarding/onboarding_test_support.dart';
import '../onboarding/online_review_test_support.dart';

class ModePort extends FakeOnboardingPort {
  ModePort({
    this.online = false,
    this.hasLog = false,
    this.done = true,
    this.eligibility = OnboardingEligibility.firstUse,
  }) : super(facts());
  final OnboardingEligibility eligibility;
  bool online, hasLog, done, pending = false, loggedIn = false, matched = false;
  final receipt = const OnboardingCheckpoint(
    step: OnboardingStep.summary,
    mode: OnboardingMode.local,
  );
  OnboardingReply observation() => OnboardingReply(
    facts: facts(
      eligibility: eligibility,
      activeMode: online ? OnboardingMode.online : OnboardingMode.local,
      publicationSuspended: !online,
      logReady: hasLog,
      confirmed: hasLog,
      signedIn: loggedIn,
      matched: matched,
      onlineReviewed: online,
      onlineSetupPending: pending,
    ),
    restored: restored,
    completed: done ? receipt : null,
  );
  @override
  Future<OnboardingReply> read() async => observation();
  @override
  Future<OnboardingReply> execute(
    OnboardingAction action,
    OnboardingCheckpoint checkpoint,
  ) async {
    actions.add(action);
    if (action == OnboardingAction.applyMode) {
      pending = checkpoint.mode == OnboardingMode.online;
      if (!pending) online = false;
      restored = checkpoint;
    }
    if (action == OnboardingAction.cancelLogin) pending = false;
    return observation();
  }

  @override
  Future<OnboardingReply> save(OnboardingCheckpoint checkpoint) async {
    restored = checkpoint;
    saves++;
    return observation();
  }
}

class Installation implements OnlineInstallationPort {
  Installation(this.mode);
  final ModePort mode;
  int installs = 0;
  @override
  bool get supported => true;
  OnlineInstallationSnapshot snapshot(OnlineInstallationPhase phase) =>
      OnlineInstallationSnapshot(
        revision: 3,
        phase: phase,
        controlGeneration: 7,
        modeRevision: phase == OnlineInstallationPhase.completed ? 4 : 3,
        modeState: phase == OnlineInstallationPhase.completed
            ? 'online'
            : 'local',
      );
  @override
  Future<OnlineInstallationSnapshot> read(int revision) async => snapshot(
    installs == 0
        ? OnlineInstallationPhase.idle
        : OnlineInstallationPhase.completed,
  );
  @override
  Future<OnlineInstallationSnapshot> install(int revision) async {
    installs++;
    mode.online = true;
    mode.pending = false;
    return snapshot(OnlineInstallationPhase.completed);
  }
}

class HeldInstallation extends Installation {
  HeldInstallation(super.mode);
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<OnlineInstallationSnapshot> install(int revision) async {
    entered.complete();
    await release.future;
    return super.install(revision);
  }
}

void main() {
  UsageModeController create(ModePort port, FakeOnlinePort online) =>
      UsageModeController(
        port,
        OnlineReviewController(online),
        Installation(port),
      );
  void cleanup(UsageModeController c, FakeOnlinePort online) {
    addTearDown(c.dispose);
    addTearDown(c.review.dispose);
    addTearDown(online.close);
  }

  test(
    'returning user without a receipt can return from online to local',
    () async {
      final port = ModePort(
        online: true,
        done: false,
        eligibility: OnboardingEligibility.returning,
      );
      final online = FakeOnlinePort();
      final c = create(port, online);
      cleanup(c, online);
      await c.refresh();
      await c.enterLocal();
      expect(port.online, false);
      expect(port.actions, [OnboardingAction.applyMode]);
      expect(c.reply!.completed, null);
      expect(port.finishes, 0);
    },
  );
  test('returning user without a receipt can begin usage mode without finishing setup', () async {
    final port = ModePort(
      done: false,
      eligibility: OnboardingEligibility.returning,
    );
    final online = FakeOnlinePort();
    final c = create(port, online);
    cleanup(c, online);
    await c.refresh();
    expect(c.completed, true);
    await c.begin();
    expect(c.step, UsageModeStep.login);
    expect(port.actions, [OnboardingAction.applyMode]);
    expect(port.finishes, 0);
    expect(c.reply!.completed, null);
    expect((c.installation as Installation).installs, 0);
  });
  test('a live confirmed name review resumes at installation without replaying installation', () async {
    final port = ModePort(hasLog: true)
      ..pending = true
      ..loggedIn = true
      ..matched = true
      ..restored = const OnboardingCheckpoint(
        step: OnboardingStep.identity,
        mode: OnboardingMode.online,
      );
    final online = FakeOnlinePort()
      ..snapshot = const OnlineReviewSnapshot(
        revision: 3,
        modeState: OnlineReviewModeState.signInRequired,
        state: OnlineReviewState.confirmedForHandoff,
      );
    final c = create(port, online);
    cleanup(c, online);
    await c.refresh();
    expect(c.step, UsageModeStep.installation);
    expect((c.installation as Installation).installs, 0);
    expect(port.online, false);
    expect(port.finishes, 0);
  });

  for (final (locale, pendingText) in const [
    (Locale('zh', 'CN'), '登录成功，游戏身份稍后自动核对'),
    (Locale('zh', 'TW'), '登入成功，遊戲身分稍後自動核對'),
    (
      Locale('en'),
      'Signed in. Your game identity will be checked automatically later.',
    ),
  ]) {
    testWidgets('usage mode hides unverified SCM names: $locale', (
      tester,
    ) async {
      final port = ModePort()
        ..pending = true
        ..loggedIn = true
        ..restored = const OnboardingCheckpoint(
          step: OnboardingStep.mode,
          mode: OnboardingMode.online,
        );
      final online = FakeOnlinePort();
      final c = create(port, online);
      cleanup(c, online);
      for (final scmName in ['Synthetic SCM Name', 'pilot@example.com']) {
        online.snapshot = OnlineReviewSnapshot(
          revision: 3,
          modeState: OnlineReviewModeState.signInRequired,
          state: OnlineReviewState.verificationRequired,
          retainsSession: true,
          accountDisplayName: scmName,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: buildStarBridgeTheme(
              FutureRestraintStyle.resolve(AppearanceMode.dark),
              locale,
            ),
            locale: locale,
            supportedLocales: [locale],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(
              body: UsageModePage(
                controller: c,
                logPanel: (_) => const SizedBox.shrink(),
              ),
            ),
          ),
        );
        await c.review.refresh();
        await tester.pumpAndSettle();
        expect(find.text(pendingText), findsOneWidget);
        expect(find.text(scmName), findsNothing);
        expect(find.textContaining('example.com'), findsNothing);
        expect(find.byType(CircleAvatar), findsNothing);
        expect(find.byKey(const Key('online-account-initial')), findsNothing);
        expect(
          find.byKey(const Key('online-account-continue')),
          findsOneWidget,
        );
        expect(port.online, false);
        expect(online.actions, isEmpty);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'retained account card preserves resume semantics without advertising fresh-account login',
    (tester) async {
      final port = ModePort()
        ..pending = true
        ..loggedIn = true
        ..restored = const OnboardingCheckpoint(
          step: OnboardingStep.mode,
          mode: OnboardingMode.online,
        );
      final online = FakeOnlinePort()
        ..snapshot = const OnlineReviewSnapshot(
          revision: 3,
          modeState: OnlineReviewModeState.signInRequired,
          state: OnlineReviewState.needsLocalIdentity,
          retainsSession: true,
          authoritativeHandle: 'Pilot-Example',
          accountDisplayName: 'Pilot-Example',
        );
      final c = create(port, online);
      cleanup(c, online);
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
      expect(find.text('Pilot-Example'), findsOneWidget);
      expect(find.byKey(const Key('online-account-continue')), findsOneWidget);
      expect(find.byKey(const Key('online-account-change')), findsNothing);
      expect(find.byType(CircleAvatar), findsNothing);
      expect(online.actions, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('leaving during installation keeps its observation and final mode reconciliation alive', () async {
    final port = ModePort(hasLog: true)
      ..loggedIn = true
      ..matched = true;
    final online = FakeOnlinePort()
      ..snapshot = const OnlineReviewSnapshot(
        revision: 3,
        modeState: OnlineReviewModeState.signInRequired,
        state: OnlineReviewState.confirmedForHandoff,
      );
    final review = OnlineReviewController(online),
        installation = HeldInstallation(port);
    var reconciliations = 0;
    final c = UsageModeController(
      port,
      review,
      installation,
      onModeChanged: () async {
        reconciliations++;
      },
    );
    addTearDown(review.dispose);
    addTearDown(online.close);
    await c.refresh();
    await review.refresh();
    c.step = UsageModeStep.installation;
    final work = c.install();
    await installation.entered.future;
    c.dispose();
    var settled = false;
    final exit = c.settled.then((_) => settled = true);
    await Future<void>.delayed(Duration.zero);
    expect(settled, false);
    expect(port.online, false);
    installation.release.complete();
    await work;
    await exit;
    expect(settled, true);
    expect(port.online, true);
    expect(reconciliations, 1);
    expect(port.finishes, 0);
    expect(c.reply!.completed, same(port.receipt));
  });

  test(
    'confirmed mode changes reconcile the existing main-window owners',
    () async {
      final port = ModePort(online: true, hasLog: true),
          online = FakeOnlinePort();
      var reconciliations = 0;
      final c = UsageModeController(
        port,
        OnlineReviewController(online),
        Installation(port),
        onModeChanged: () async {
          reconciliations++;
        },
      );
      cleanup(c, online);
      await c.refresh();
      reconciliations = 0;
      await c.enterLocal();
      expect(reconciliations, 1);
      await c.begin();
      expect(reconciliations, 1);
      port.loggedIn = true;
      await c.accountConfirmed();
      online.snapshot = const OnlineReviewSnapshot(
        revision: 3,
        modeState: OnlineReviewModeState.signInRequired,
        state: OnlineReviewState.confirmedForHandoff,
      );
      port.matched = true;
      await c.review.refresh();
      await c.namesConfirmed();
      await c.install();
      expect(c.online, true);
      expect(reconciliations, 2);
      expect(port.finishes, 0);
    },
  );

  testWidgets(
    'online switch uses the account card, log, automatic name review and installation in order',
    (tester) async {
      final port = ModePort(), online = FakeOnlinePort();
      online.onAction = (action) async {
        if (action == OnlineReviewAction.login) {
          port.loggedIn = true;
          online.snapshot = const OnlineReviewSnapshot(
            revision: 3,
            modeState: OnlineReviewModeState.signInRequired,
            state: OnlineReviewState.needsLocalIdentity,
            authoritativeHandle: 'Pilot-Example',
            accountDisplayName: 'hidden@example.com',
          );
        }
        if (action == OnlineReviewAction.review ||
            action == OnlineReviewAction.confirm) {
          port.matched = action == OnlineReviewAction.confirm;
          online.snapshot = OnlineReviewSnapshot(
            revision: 3,
            modeState: OnlineReviewModeState.signInRequired,
            state: port.matched
                ? OnlineReviewState.confirmedForHandoff
                : OnlineReviewState.reviewRequired,
            localHandle: 'Pilot-Example',
            authoritativeHandle: 'PILOT-EXAMPLE',
            confirmationKey: port.matched
                ? null
                : '11111111111111111111111111111111',
          );
        }
        return online.snapshot;
      };
      final c = create(port, online);
      cleanup(c, online);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark),
            const Locale('en'),
          ),
          home: Scaffold(
            body: UsageModePage(
              controller: c,
              logPanel: (confirmed) => TextButton(
                key: const Key('fixture-confirm-log'),
                onPressed: () async {
                  port.hasLog = true;
                  await confirmed();
                },
                child: const Text('Confirm synthetic log'),
              ),
            ),
          ),
        ),
      );
      Future<void> tap(String key) async {
        final found = find.byKey(Key(key));
        await tester.ensureVisible(found);
        await tester.pumpAndSettle();
        await tester.ensureVisible(found);
        await tester.pumpAndSettle();
        await tester.tap(found);
        await tester.pumpAndSettle();
      }

      await tester.pumpAndSettle();
      await tap('usage-mode-to-online');
      expect(c.step, UsageModeStep.login);
      await tap('online-review-login');
      expect(find.text('Pilot-Example'), findsOneWidget);
      expect(find.byKey(const Key('online-account-change')), findsOneWidget);
      expect(find.byType(CircleAvatar), findsNothing);
      expect(find.byKey(const Key('online-account-initial')), findsNothing);
      await tap('online-account-continue');
      expect(c.step, UsageModeStep.log);
      expect(port.online, false);
      await tap('fixture-confirm-log');
      expect(c.step, UsageModeStep.names);
      expect(port.online, false);
      expect(find.text('Game names match'), findsOneWidget);
      await tap('online-review-confirm');
      expect(c.step, UsageModeStep.installation);
      expect(port.online, false);
      await tap('usage-mode-install');
      expect(find.text('Current: Online mode'), findsOneWidget);
      expect(find.text('Switched to online mode'), findsOneWidget);
      expect(port.finishes, 0);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('four steps keep local mode until installation, resume each checkpoint, preserve receipt', () async {
    final port = ModePort(), online = FakeOnlinePort();
    var c = create(port, online);
    await c.refresh();
    await c.begin();
    expect(c.step, UsageModeStep.login);
    await c.accountConfirmed();
    expect(c.step, UsageModeStep.login);
    port.loggedIn = true;
    await c.accountConfirmed();
    expect(c.step, UsageModeStep.log);
    for (final target in [
      UsageModeStep.log,
      UsageModeStep.names,
      UsageModeStep.installation,
    ]) {
      if (target == UsageModeStep.names) {
        port.hasLog = true;
        await c.logConfirmed();
      }
      if (target == UsageModeStep.installation) {
        await c.namesConfirmed();
        expect(c.step, UsageModeStep.names);
        online.snapshot = const OnlineReviewSnapshot(
          revision: 3,
          modeState: OnlineReviewModeState.signInRequired,
          state: OnlineReviewState.confirmedForHandoff,
        );
        port.matched = true;
        await c.review.refresh();
        await c.namesConfirmed();
      }
      expect(c.step, target);
      expect(port.online, false);
      c.dispose();
      c.review.dispose();
      c = create(port, online);
      await c.refresh();
      expect(c.step, target);
      expect(c.reply!.completed, same(port.receipt));
    }
    await c.install();
    expect(c.online, true);
    expect(c.switched, true);
    expect(port.finishes, 0);
    expect(c.reply!.completed, same(port.receipt));
    cleanup(c, online);
  });
  for (final target in UsageModeStep.values) {
    test(
      'cancel $target clears pending switch and retains local receipt',
      () async {
        final port = ModePort(hasLog: true), online = FakeOnlinePort();
        final c = create(port, online);
        cleanup(c, online);
        await c.refresh();
        await c.begin();
        c.step = target;
        await c.cancel();
        expect(c.step, null);
        expect(port.pending, false);
        expect(c.online, false);
        expect(c.reply!.completed, same(port.receipt));
        expect(port.finishes, 0);
        final reopened = create(port, online);
        await reopened.refresh();
        expect(reopened.step, null);
        reopened.dispose();
        reopened.review.dispose();
      },
    );
  }
  for (final isOnline in [false, true]) {
    testWidgets('current mode $isOnline and original descriptions', (
      tester,
    ) async {
      final port = ModePort(online: isOnline), online = FakeOnlinePort();
      final c = create(port, online);
      cleanup(c, online);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark),
            const Locale('en'),
          ),
          home: Scaffold(
            body: UsageModePage(
              controller: c,
              logPanel: (_) => const Text('Log panel'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(isOnline ? 'Current: Online mode' : 'Current: Local mode'),
        findsOneWidget,
      );
      final copy = OnboardingCopy(const Locale('en'));
      expect(find.text(copy.text('onlineDescription')), findsOneWidget);
      expect(find.text(copy.text('localDescription')), findsOneWidget);
      if (isOnline) {
        await tester.tap(find.byKey(const Key('usage-mode-to-local')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(port.online, true);
        expect(port.actions, isEmpty);
        await tester.tap(find.byKey(const Key('usage-mode-to-local')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Switch'));
        await tester.pumpAndSettle();
        expect(port.online, false);
        expect(c.reply!.completed, same(port.receipt));
      }
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('online usage mode offers the installed identity review', (
    tester,
  ) async {
    Map<String, Object?> installed(String state) => {
      ...onlineWire(
        mode: 'online',
        state: state,
        local: 'Pilot-Example',
        remote: 'Pilot-Example',
        key: state == 'installedReviewRequired' ? 'a' * 32 : null,
      ),
      'schemaVersion': 2,
      'retainsSession': false,
    };
    final port = ModePort(online: true);
    final online = FakeOnlinePort()
      ..snapshot = OnlineReviewWire.parse(
        installed('identityCheckRequired'),
        retainedProtocol: true,
      );
    online.onAction = (action) async =>
        online.snapshot = OnlineReviewWire.parse(
          installed(
            action == OnlineReviewAction.review
                ? 'installedReviewRequired'
                : 'boundOnlineIdentity',
          ),
          retainedProtocol: true,
        );
    var reconciled = 0;
    final c = UsageModeController(
      port,
      OnlineReviewController(online),
      Installation(port),
      onModeChanged: () async => reconciled++,
    );
    cleanup(c, online);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildStarBridgeTheme(
          FutureRestraintStyle.resolve(AppearanceMode.dark),
          const Locale('en'),
        ),
        home: Scaffold(
          body: UsageModePage(
            controller: c,
            logPanel: (_) => const Text('Log panel'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('usage-mode-installed-review'));
    expect(panel, findsOneWidget);
    expect(find.byKey(const Key('usage-mode-to-local')), findsOneWidget);
    final opened = reconciled;
    await tester.ensureVisible(find.byKey(const Key('online-review-check')));
    await tester.tap(find.byKey(const Key('online-review-check')));
    await tester.pumpAndSettle();
    expect(online.actions, [OnlineReviewAction.review]);
    expect(panel, findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('online-review-confirm')));
    await tester.tap(find.byKey(const Key('online-review-confirm')));
    await tester.pumpAndSettle();
    expect(online.actions, [
      OnlineReviewAction.review,
      OnlineReviewAction.confirm,
    ]);
    // Bound: the review leaves, the main window is reconciled once, and the
    // usage mode itself never changed.
    expect(panel, findsNothing);
    expect(reconciled, opened + 1);
    expect(port.online, true);
    expect(port.actions, isEmpty);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('a bound installed identity shows no review in usage mode', (
    tester,
  ) async {
    final port = ModePort(online: true);
    final online = FakeOnlinePort()
      ..snapshot = OnlineReviewWire.parse({
        ...onlineWire(
          mode: 'online',
          state: 'boundOnlineIdentity',
          local: 'Pilot-Example',
          remote: 'Pilot-Example',
        ),
        'schemaVersion': 2,
        'retainsSession': false,
      }, retainedProtocol: true);
    final c = create(port, online);
    cleanup(c, online);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildStarBridgeTheme(
          FutureRestraintStyle.resolve(AppearanceMode.dark),
          const Locale('en'),
        ),
        home: Scaffold(
          body: UsageModePage(
            controller: c,
            logPanel: (_) => const Text('Log panel'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('usage-mode-installed-review')),
      findsNothing,
    );
    expect(find.byKey(const Key('usage-mode-to-local')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('approved copy uses actual three-language menu paths', () {
    for (final locale in [
      const Locale('zh', 'CN'),
      const Locale('zh', 'TW'),
      const Locale('en'),
    ]) {
      final copy = OnboardingCopy(locale);
      final path = locale.languageCode == 'en'
          ? 'Settings › Account & identity › Game log'
          : locale.countryCode == 'TW'
          ? '設定 › 帳號與識別 › 遊戲日誌'
          : '设置 › 账号与识别 › 游戏日志';
      expect(copy.text('logDeferredBody'), contains(path));
      expect(copy.text('summary.detail.log.deferred'), contains(path));
      expect(
        copy.text('onlineNeedsLog'),
        contains(usageModeText(locale, 'title')),
      );
      expect(
        copy.text('onlineNeedsLog'),
        isNot(contains('Continue first-use')),
      );
    }
  });
}
