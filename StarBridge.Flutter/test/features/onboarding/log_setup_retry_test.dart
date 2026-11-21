import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_copy.dart';

import 'onboarding_page_test.dart' show pumpSetup;
import 'onboarding_test_support.dart';

void main() {
  for (final mode in OnboardingMode.values) {
    for (final step in [
      OnboardingStep.identity,
      OnboardingStep.local,
      if (mode == OnboardingMode.online) OnboardingStep.online,
      OnboardingStep.verify,
      OnboardingStep.summary,
    ]) {
      testWidgets('pending log restores $mode/$step to identity retry', (
        tester,
      ) async {
        final port = FakeOnboardingPort(
          facts(
            confirmed: true,
            logSetupPending: true,
            onlineSetupPending: mode == OnboardingMode.online,
          ),
        );
        final controller = await pumpSetup(
          tester,
          port: port,
          step: step,
          mode: mode,
        );
        expect(controller.value.step, OnboardingStep.identity);
        expect(controller.canContinue, false);
        await controller.next();
        await controller.refresh();
        await tester.pumpAndSettle();
        expect(controller.value.step, OnboardingStep.identity);
        expect(find.text('游戏日志已确认，但统计设置还没保存好。'), findsOneWidget);
        expect(
          find.byKey(const Key('onboarding-action-finishLogSetup')),
          findsOneWidget,
        );
        expect(port.actions, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  test('retry copy matches the required three locales', () {
    for (final entry in [
      (const Locale('zh', 'CN'), '游戏日志已确认，但统计设置还没保存好。', '重试'),
      (const Locale('zh', 'TW'), '遊戲日誌已確認，但統計設定還沒儲存好。', '重試'),
      (
        const Locale('en', 'US'),
        "Your game log is confirmed, but the statistics setting hasn't been saved yet.",
        'Try again',
      ),
    ]) {
      expect(OnboardingCopy(entry.$1).text('logSetupPending'), entry.$2);
      expect(OnboardingCopy(entry.$1).text('finishLogSetup'), entry.$3);
    }
  });
  testWidgets('partial confirmation failure rereads durable recovery state', (
    tester,
  ) async {
    final port = FakeOnboardingPort(facts());
    port.onAction = (action, checkpoint) async {
      expect(action, OnboardingAction.confirmHandle);
      port.facts = facts(confirmed: true, logSetupPending: true);
      throw StateError('Synthetic statistics writer locked');
    };
    final controller = await pumpSetup(
      tester,
      port: port,
      step: OnboardingStep.identity,
      mode: OnboardingMode.local,
    );
    await controller.next();
    await tester.pumpAndSettle();
    expect(port.actions, [OnboardingAction.confirmHandle]);
    expect(controller.value.step, OnboardingStep.identity);
    expect(controller.canContinue, false);
    expect(
      find.byKey(const Key('onboarding-action-finishLogSetup')),
      findsOneWidget,
    );
  });
  testWidgets('unfinished setup retries migration before leaving identity', (
    tester,
  ) async {
    final port = FakeOnboardingPort(
      facts(confirmed: true, logSetupPending: true),
    );
    port.onAction = (action, checkpoint) async {
      expect(action, OnboardingAction.finishLogSetup);
      expect(checkpoint.step, OnboardingStep.identity);
      port.facts = facts(confirmed: true);
      return OnboardingReply(facts: port.facts);
    };
    final controller = await pumpSetup(
      tester,
      port: port,
      step: OnboardingStep.identity,
      mode: OnboardingMode.local,
    );
    expect(controller.canContinue, false);
    expect(find.text('游戏日志已确认，但统计设置还没保存好。'), findsOneWidget);
    final retry = find.byKey(const Key('onboarding-action-finishLogSetup'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(port.actions, [OnboardingAction.finishLogSetup]);
    expect(find.text('游戏日志已确认，但统计设置还没保存好。'), findsNothing);
    expect(controller.canContinue, true);
  });
}
