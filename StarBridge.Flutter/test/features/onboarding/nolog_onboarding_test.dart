import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_controller.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_copy.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_summary.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_controller.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_port.dart';
import 'package:starbridge_flutter/features/account/bridge_account_failure.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/onboarding/recognition_check_controller.dart';
import 'package:starbridge_flutter/features/onboarding/local_statistics_controller.dart';

import 'onboarding_test_support.dart';
import 'onboarding_page_test.dart' show pumpSetup;
import 'online_review_test_support.dart';
import 'local_statistics_test_support.dart';

const deferred = OnboardingFacts(
  eligibility: OnboardingEligibility.firstUse,
  available: true,
  canSave: true,
  logDeferred: true,
  localSettingsReady: true,
  activeMode: OnboardingMode.local,
  publicationSuspended: true,
);

void main() {
  test('local no-log completion skips identity and recognition and restores summary', () async {
    final port = FakeOnboardingPort(
      const OnboardingFacts(
        eligibility: OnboardingEligibility.firstUse,
        available: true,
        canSave: true,
        activeMode: OnboardingMode.local,
        publicationSuspended: true,
      ),
    );
    port.onAction = (action, checkpoint) async {
      expect(action, OnboardingAction.skipLog);
      port.facts = deferred;
      return OnboardingReply(facts: deferred);
    };
    final c = OnboardingController(port, skipWelcomeIntro: true);
    addTearDown(c.dispose);
    await c.initialize();
    expect(c.value.step, OnboardingStep.log);
    await c.run(OnboardingAction.skipLog);
    expect(c.value.identityReady, false);
    await c.next();
    expect(c.value.step, OnboardingStep.mode);
    c.chooseMode(OnboardingMode.online);
    expect(c.value.mode, OnboardingMode.local);
    await c.next();
    expect(c.value.step, OnboardingStep.local);
    await c.next();
    expect(c.value.step, OnboardingStep.summary);
    final summary = buildOnboardingSummary(
      view: c.value,
      recognition: const RecognitionCheckView(passed: true),
    );
    expect(
      summary.singleWhere((e) => e.item == SummaryItem.log).status,
      SummaryStatus.skipped,
    );
    expect(summary.any((e) => e.item == SummaryItem.identity), false);
    expect(
      summary.singleWhere((e) => e.item == SummaryItem.recognition).status,
      SummaryStatus.skipped,
    );
    await c.next();
    expect(c.value.completed, true);
    port.restored = c.value.checkpoint;
    final reopened = OnboardingController(port, skipWelcomeIntro: true);
    addTearDown(reopened.dispose);
    await reopened.initialize();
    expect(reopened.value.step, OnboardingStep.summary);
    expect(reopened.value.readyToFinish, true);
  });

  test('local-mode account failure keeps its message', () {
    expect(
      mapAccountBridgeFailure(const BridgeClientException('account.local_mode'))
          .messageKey,
      'account.error.localMode',
    );
  });

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    testWidgets(
      'no-log statistics requires a choice without claiming a confirmed identity: $locale',
      (tester) async {
        final port = FakeStatisticsPort();
        final statistics = LocalStatisticsController(port);
        addTearDown(statistics.dispose);
        addTearDown(port.close);
        await pumpSetup(
          tester,
          step: OnboardingStep.local,
          mode: OnboardingMode.local,
          observation: deferred,
          localStatistics: statistics,
          locale: locale,
        );
        final copy = OnboardingCopy(locale);
        expect(find.text(copy.text('statistics.intro')), findsNothing);
        expect(
          find.textContaining(copy.text('statistics.savedTime')),
          findsNothing,
        );
        expect(find.byKey(const Key('statistics-allow')), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('onboarding-next')))
              .onPressed,
          isNull,
        );
        final decline = find.byKey(const Key('statistics-decline'));
        await tester.ensureVisible(decline);
        await tester.tap(decline);
        await tester.pumpAndSettle();
        final confirm = find.byKey(const Key('statistics-confirm'));
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(port.confirmations, 1);
        expect(find.text(copy.text('statistics.declined')), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('onboarding-next')))
              .onPressed,
          isNotNull,
        );
      },
    );
    testWidgets(
      'source-invalid explains version folder, and local-mode copy names actual settings: $locale',
      (tester) async {
        final port = FakeOnboardingPort(facts());
        port.onAction = (_, _) async =>
            throw const BridgeClientException('firstUse.source_invalid');
        await pumpSetup(
          tester,
          step: OnboardingStep.log,
          mode: OnboardingMode.local,
          port: port,
          locale: locale,
        );
        await tester.tap(find.byKey(const Key('onboarding-action-selectLog')));
        await tester.pumpAndSettle();
        expect(
          find.text(OnboardingCopy(locale).text('sourceInvalid')),
          findsOneWidget,
        );
        final text = AppStrings.resolve(locale).text('account.error.localMode');
        expect(text, isNot('account.error.localMode'));
        expect(
          text,
          contains(
            locale.languageCode == 'en'
                ? 'cannot sign in'
                : locale.countryCode == 'TW'
                ? '無法登入'
                : '不能登录',
          ),
        );
      },
    );
    testWidgets('no-log notice and summary are honest: $locale', (
      tester,
    ) async {
      await pumpSetup(
        tester,
        step: OnboardingStep.log,
        mode: OnboardingMode.local,
        observation: deferred,
        locale: locale,
      );
      final copy = OnboardingCopy(locale);
      expect(find.text(copy.text('skipLog')), findsOneWidget);
      expect(find.text(copy.text('logDeferredBody')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpSetup(
        tester,
        step: OnboardingStep.summary,
        mode: OnboardingMode.local,
        observation: deferred,
        locale: locale,
      );
      expect(
        find.text(copy.text('summary.detail.log.deferred')),
        findsOneWidget,
      );
      expect(
        find.text(copy.text('summary.detail.identity.confirmed')),
        findsNothing,
      );
      expect(find.text(copy.text('summary.detail.log.ready')), findsNothing);
    });
    testWidgets(
      'mode account card hides unverified names and automatically reviews verified identity: $locale',
      (tester) async {
        final port = FakeOnlinePort()
          ..snapshot = const OnlineReviewSnapshot(
            revision: 3,
            modeState: OnlineReviewModeState.signInRequired,
            state: OnlineReviewState.verificationRequired,
            accountDisplayName: 'pilot@example.com',
          );
        final online = OnlineReviewController(port);
        addTearDown(online.dispose);
        addTearDown(port.close);
        await pumpSetup(
          tester,
          step: OnboardingStep.mode,
          mode: OnboardingMode.online,
          observation: facts(confirmed: true, onlineSetupPending: true),
          onlineReview: online,
          locale: locale,
        );
        final copy = OnboardingCopy(locale);
        expect(
          find.text(copy.text('accountCard.identityPending')),
          findsNothing,
        );
        expect(find.textContaining('example.com'), findsNothing);
        for (final state in [
          OnlineReviewState.verificationRequired,
          OnlineReviewState.revoked,
          OnlineReviewState.unavailable,
        ]) {
          for (final scmName in ['Synthetic SCM Name', 'p@example.com']) {
            port.snapshot = OnlineReviewSnapshot(
              revision: 3,
              modeState: OnlineReviewModeState.signInRequired,
              state: state,
              authoritativeHandle:
                  state == OnlineReviewState.verificationRequired
                  ? null
                  : 'OldHandle',
              accountDisplayName: scmName,
            );
            await online.refresh();
            await tester.pumpAndSettle();
            expect(find.text(scmName), findsNothing);
            expect(find.textContaining('example.com'), findsNothing);
            expect(find.text('OldHandle'), findsNothing);
            expect(
              find.text(copy.text('accountCard.identityPending')),
              findsNothing,
            );
            expect(
              find.text(copy.text('accountCard.unverified')),
              findsOneWidget,
            );
          }
        }
        port.snapshot = const OnlineReviewSnapshot(
          revision: 3,
          modeState: OnlineReviewModeState.signInRequired,
          state: OnlineReviewState.reviewRequired,
          localHandle: 'Pilot',
          confirmationKey: '11111111111111111111111111111111',
          authoritativeHandle: 'Pilot',
          accountDisplayName: 'Synthetic SCM Name',
        );
        await online.refresh();
        await tester.pumpAndSettle();
        expect(find.text('Pilot'), findsWidgets);
        expect(find.text('Synthetic SCM Name'), findsNothing);
        expect(find.text(copy.text('accountCard.verified')), findsOneWidget);
        expect(
          find.text(copy.text('accountCard.identityPending')),
          findsNothing,
        );
        expect(find.byKey(const Key('online-account-initial')), findsNothing);
        expect(find.byType(CircleAvatar), findsNothing);
        expect(find.byKey(const Key('online-review-check')), findsNothing);
        expect(find.byKey(const Key('online-review-confirm')), findsOneWidget);
        expect(port.actions, isEmpty);
        port.snapshot = const OnlineReviewSnapshot(
          revision: 3,
          modeState: OnlineReviewModeState.signInRequired,
          state: OnlineReviewState.accountReviewRequired,
          retainsSession: true,
          authoritativeHandle: 'Pilot',
          accountDisplayName: 'Pilot',
          confirmationKey: '11111111111111111111111111111111',
        );
        await online.refresh();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('online-account-continue')), findsNothing);
        expect(find.byKey(const Key('online-review-confirm')), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('onboarding-next')))
              .onPressed,
          isNull,
        );
      },
    );
    testWidgets(
      'mode reviews automatically once and retains confirmation: $locale',
      (tester) async {
        final port = FakeOnlinePort()
          ..snapshot = const OnlineReviewSnapshot(
            revision: 3,
            modeState: OnlineReviewModeState.signInRequired,
            state: OnlineReviewState.identityCheckRequired,
          );
        final online = OnlineReviewController(port);
        addTearDown(online.dispose);
        addTearDown(port.close);
        await pumpSetup(
          tester,
          step: OnboardingStep.mode,
          mode: OnboardingMode.online,
          observation: facts(confirmed: true, onlineSetupPending: true),
          onlineReview: online,
          locale: locale,
        );
        expect(port.actions, [OnlineReviewAction.review]);
        expect(
          find.text(OnboardingCopy(locale).text('onlineReview.namesMatch')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('online-review-confirm')), findsOneWidget);
        final words = OnboardingCopy(locale);
        expect(
          find.descendant(
            of: find.byKey(const Key('online-review-confirm')),
            matching: find.text(words.text('onlineReview.confirmOne')),
          ),
          findsOneWidget,
        );
        expect(find.text(words.text('onlineReview.confirm')), findsNothing);
        expect(find.byKey(const Key('online-review-check')), findsNothing);
      },
    );
  }
}
