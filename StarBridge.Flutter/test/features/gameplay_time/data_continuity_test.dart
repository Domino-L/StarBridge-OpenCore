import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/gameplay_time/gameplay_account_total.dart';
import 'package:starbridge_flutter/features/gameplay_time/gameplay_time_controller.dart';
import 'package:starbridge_flutter/features/gameplay_time/gameplay_time_panel.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';

import 'gameplay_time_test.dart' as support;

void main() {
  const pendingCopy = '正在确认游戏身份，确认后按你在引导里的选择开始记录。';
  testWidgets('identity pending copy is settings-only and absent on old Host', (
    tester,
  ) async {
    final h = support.Harness(consent: 'unknown')..consentPending = 'identity';
    Future<void> refresh() async {
      final request = h.controller.retry();
      await tester.pumpAndSettle();
      await request;
    }

    await tester.pump();
    await tester.pumpWidget(
      support.app(GameplayTimePanel(controller: h.controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text(pendingCopy), findsOneWidget);
    expect(find.text('已停止记录'), findsNothing);
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('gameplay-time-record-switch')))
          .value,
      isFalse,
    );
    for (final locale in AppStrings.supportedLocales) {
      expect(
        AppStrings.resolve(locale).text('gameplay.consentPendingIdentity'),
        pendingCopy,
      );
    }
    // Missing optional field from an older Host preserves the existing status.
    h.consentPending = null;
    await refresh();
    await tester.pumpAndSettle();
    expect(find.text(pendingCopy), findsNothing);
    expect(find.text('已停止记录'), findsOneWidget);
    h.consentPending = 'identity';
    await refresh();
    await tester.pumpAndSettle();
    expect(find.text(pendingCopy), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('gameplay-time-record-switch')),
    );
    final recordLabel = find.text(
      AppStrings.resolve(const Locale('zh', 'CN'))
          .text('gameplay.recordSwitch'),
    );
    await tester.tap(recordLabel);
    await tester.pumpAndSettle();
    expect(h.requests.last.name, 'gameplayTime.setConsent');
    expect(h.requests.last.payload['allowed'], isTrue);
    expect(find.text(pendingCopy), findsNothing);
    await tester.tap(recordLabel);
    await tester.pumpAndSettle();
    expect(h.requests.last.payload['allowed'], isFalse);
    expect(find.text(pendingCopy), findsNothing);
    // Exercise the real owner page and its visitor preview with pending data.
    h.consent = 'unknown';
    await refresh();
    final profile = createPersonalProfileModule(
      InMemoryPersonalProfileAdapter.forReview(signedIn: true),
    );
    await profile.initialize();
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    await tester.pumpWidget(
      support.app(
        SizedBox(
          height: 1000,
          child: PersonalProfilePage(
            module: profile,
            gameplayTime: h.controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(pendingCopy), findsNothing);
    await tester.tap(find.text('预览访客视角'));
    await tester.pumpAndSettle();
    expect(find.text(pendingCopy), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    profile.dispose();
    await h.close(tester);
    await tester.binding.setSurfaceSize(null);
  });
  for (final locale in AppStrings.supportedLocales) {
    test(
      'fixed continuity copy is available without internal keys: $locale',
      () {
        final strings = AppStrings.resolve(locale);
        expect(strings.text('gameplay.deviceStorage'), '本机累计只保存在这台电脑上。');
        expect(strings.text('gameplay.accountTotal'), '账号累计 {hours} 小时');
        expect(strings.text('gameplay.accountEmpty'), '账号还没有云端累计');
        expect(strings.text('gameplay.accountUnavailable'), '账号累计暂时读不到');
        expect(strings.text('profile.ownerRead.neverSaved'), '这个账号还没有保存过个人页');
        expect(strings.text('profile.ownerRead.retry'), '重试');
        expect(
          strings.text('profile.local.onlySaved'),
          '这些改动只保存在这台电脑上，换电脑后看不到。',
        );
        expect(
          strings.text('profile.error.ownerReadFailed'),
          '暂时读不到你的个人页，稍后重试',
        );
      },
    );
  }
  testWidgets('bridge read failure clears the previous account number', (
    tester,
  ) async {
    final h = support.Harness()
      ..accountTotalState = 'available'
      ..accountTotalSeconds = 36000;
    await tester.pump();
    await tester.pumpWidget(
      support.app(GameplayTimePanel(controller: h.controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('账号累计 10 小时'), findsOneWidget);
    h.remoteError = 'bridge.host_error';
    await tester.runAsync(h.controller.retry);
    await tester.pumpAndSettle();
    expect(find.text('账号累计 10 小时'), findsNothing);
    expect(find.text('账号累计暂时读不到'), findsOneWidget);
    expect(find.text('账号累计 0 小时'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await h.close(tester);
  });

  for (final state in ['available', 'empty', 'unavailable']) {
    testWidgets('account total wire and display: $state', (tester) async {
      final h = support.Harness();
      h.accountTotalState = state;
      h.accountTotalSeconds = state == 'available' ? 36000 : null;
      await tester.pump();
      await tester.pumpWidget(
        support.app(GameplayTimePanel(controller: h.controller)),
      );
      await tester.pumpAndSettle();
      expect(h.controller.value.accountTotalState, state);
      expect(find.text('本机累计只保存在这台电脑上。'), findsOneWidget);
      expect(
        find.text(switch (state) {
          'available' => '账号累计 10 小时',
          'empty' => '账号还没有云端累计',
          _ => '账号累计暂时读不到',
        }),
        findsOneWidget,
      );
      expect(find.text('账号累计 0 小时'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await h.close(tester);
    });
  }

  // 11-08 build 78: the two totals lines floated above the page column, and
  // the header and rail lacked the account hours the controller had read.
  // A saved "show on profile" off no longer hides anything (user 11-08: the
  // profile's own visibility governs it), so both runs look the same.
  for (final shown in [true, false]) {
    testWidgets('owner page playtime leads the rail (saved: $shown)', (
      tester,
    ) async {
      final h = support.Harness(showOnProfile: shown)
        ..seconds = 5 * 3600
        ..accountTotalState = 'available'
        ..accountTotalSeconds = 617 * 3600;
      await tester.pump();
      final profile = createPersonalProfileModule(
        InMemoryPersonalProfileAdapter.forReview(signedIn: true),
      );
      await profile.initialize();
      await tester.binding.setSurfaceSize(const Size(1280, 1600));
      await tester.pumpWidget(
        support.app(
          SizedBox(
            height: 1600,
            child: PersonalProfilePage(
              module: profile,
              gameplayTime: h.controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // User 11-11: playtime leads the side rail and shows the account total
      // the controller read, as visitors see it; this PC's own 5 hours and its
      // storage note stay in the gameplay settings.
      final rail = find.byKey(const Key('profile-side-rail'));
      final band = find.descendant(
        of: rail,
        matching: find.byKey(const Key('profile-showcase-gameplay')),
      );
      expect(band, findsOneWidget);
      expect(
        find.descendant(of: band, matching: find.text('617')),
        findsOneWidget,
      );
      expect(find.text('本机累计只保存在这台电脑上。'), findsNothing);
      expect(find.descendant(of: band, matching: find.text('5')), findsNothing);
      expect(find.text('账号累计 617 小时'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      profile.dispose();
      await h.close(tester);
      await tester.binding.setSurfaceSize(null);
    });
  }

  test('owner hours: account total first, then this PC, then the page', () {
    GameplayTimeView view({
      int? seconds,
      String account = 'unavailable',
      int? accountSeconds,
      bool shown = true,
    }) => GameplayTimeView(
      visible: true,
      seconds: seconds,
      accountTotalState: account,
      accountTotalSeconds: accountSeconds,
      showOnProfile: shown,
    );
    expect(
      ownerGameplayHours(
        view(seconds: 0, account: 'available', accountSeconds: 617 * 3600),
        60,
      ),
      617,
    );
    expect(ownerGameplayHours(view(seconds: 7200), 600), 10);
    expect(ownerGameplayHours(view(seconds: 7200), null), 2);
    expect(ownerGameplayHours(view(), null), isNull);
    expect(ownerGameplayHours(null, 125), 2);
    expect(
      ownerGameplayHours(
        view(account: 'available', accountSeconds: 36000, shown: false),
        120,
      ),
      10,
    );
    expect(ownerAccountMinutes(view(account: 'empty'), 30), 30);
  });
}
