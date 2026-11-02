import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_controller.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_copy.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_page.dart';
import 'package:starbridge_flutter/features/onboarding/device_review_controller.dart';
import 'package:starbridge_flutter/features/onboarding/device_review_port.dart';
import 'package:starbridge_flutter/features/onboarding/local_statistics_controller.dart';
import 'package:starbridge_flutter/features/onboarding/local_history_controller.dart';
import 'package:starbridge_flutter/features/onboarding/app_behavior_choice_controller.dart';
import 'package:starbridge_flutter/features/onboarding/native_overlay_check_controller.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_controller.dart';

import 'onboarding_test_support.dart';

Future<OnboardingController> pumpSetup(
  WidgetTester tester, {
  OnboardingStep step = OnboardingStep.welcome,
  OnboardingMode? mode,
  OnboardingFacts? observation,
  FakeOnboardingPort? port,
  Locale locale = const Locale('zh', 'CN'),
  AppearanceMode appearance = AppearanceMode.dark,
  double scale = 1,
  VoidCallback? onClose,
  AppBehaviorChoiceController? appBehavior,
  DeviceReviewController? deviceReview,
  Future<void> Function(DeviceReviewSection)? editDeviceSettings,
  LocalStatisticsController? localStatistics,
  LocalHistoryController? localHistory,
  NativeOverlayCheckController? nativeOverlay,
  OnlineReviewController? onlineReview,
}) async {
  final fake = port ?? FakeOnboardingPort(observation ?? facts());
  if (mode == OnboardingMode.online && !fake.facts.onlineSetupPending) {
    await fake.execute(
      OnboardingAction.applyMode,
      OnboardingCheckpoint(mode: mode),
    );
    fake.actions.clear();
  }
  fake.restored = OnboardingCheckpoint(
    step: step,
    mode: mode,
    sourceKey: fake.facts.sourceKey,
    evidenceKey: fake.facts.evidenceKey,
  );
  final controller = OnboardingController(fake);
  addTearDown(controller.dispose);
  final tokens = FutureRestraintStyle.resolve(appearance);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildStarBridgeTheme(tokens, locale),
      locale: locale,
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: MediaQuery(
        data: MediaQueryData(
          size: tester.view.physicalSize,
          disableAnimations: true,
          textScaler: TextScaler.linear(scale),
        ),
        child: RepaintBoundary(
          key: const Key('onboarding-capture'),
          child: OnboardingPage(
            controller: controller,
            onClose: onClose ?? () {},
            appBehavior: appBehavior,
            deviceReview: deviceReview,
            editDeviceSettings: editDeviceSettings,
            localStatistics: localStatistics,
            localHistory: localHistory,
            nativeOverlay: nativeOverlay,
            onlineReview: onlineReview,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final font in <String, String>{
      'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
      'Saira': 'assets/fonts/Saira-VF.ttf',
      'Rajdhani': 'assets/fonts/Rajdhani-SemiBold.ttf',
      'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  testWidgets('stored profile explains its non-live meaning at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpSetup(
      tester,
      step: OnboardingStep.identity,
      mode: OnboardingMode.local,
      observation: facts(
        origin: OnboardingEvidenceOrigin.confirmedLocal,
        confirmed: true,
        signedIn: false,
        matched: false,
      ),
      scale: 1.6,
    );
    expect(find.text('已确认的本机档案'), findsOneWidget);
    expect(find.text('游戏退出后，档案仍会保留。这不是当前游戏状态，也不会开启共享。'), findsOneWidget);
    expect(find.text('当前日志'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    for (final width in [320.0, 1280.0]) {
      testWidgets('${locale.toLanguageTag()} $width mode fits large text', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpSetup(
          tester,
          step: OnboardingStep.mode,
          locale: locale,
          scale: 1.6,
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('onboarding-next')), findsOneWidget);
        expect(find.byKey(const Key('onboarding-close')), findsOneWidget);
      });
    }
  }

  testWidgets('local selection never triggers a login request', (tester) async {
    final port = FakeOnboardingPort(facts(signedIn: false));
    final c = await pumpSetup(tester, step: OnboardingStep.mode, port: port);
    await tester.tap(find.byKey(const Key('onboarding-mode-local')));
    await tester.pump();
    expect(c.value.mode, OnboardingMode.local);
    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pump();
    expect(c.value.step, OnboardingStep.log);
    expect(port.actions, isEmpty);
  });

  testWidgets(
    'missing Handle exposes mandatory game step without manual input',
    (tester) async {
      await pumpSetup(
        tester,
        step: OnboardingStep.identity,
        mode: OnboardingMode.local,
        observation: facts(evidence: OnboardingEvidence.missing),
      );
      expect(find.text('没有找到可用 Handle，请进入一次游戏'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('onboarding-next')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('partial scan is not a mandatory-game conclusion', (
    tester,
  ) async {
    await pumpSetup(
      tester,
      step: OnboardingStep.identity,
      mode: OnboardingMode.local,
      observation: facts(
        evidence: OnboardingEvidence.missing,
        scopeChecked: false,
      ),
    );
    expect(find.text('日志检查尚未完成，请重新检查。'), findsOneWidget);
    expect(find.text('没有找到可用 Handle，请进入一次游戏'), findsNothing);
  });

  testWidgets('close waits for saved progress without claiming completion', (
    tester,
  ) async {
    var closes = 0;
    final port = FakeOnboardingPort(
      facts(evidence: OnboardingEvidence.missing),
    );
    final c = await pumpSetup(
      tester,
      step: OnboardingStep.identity,
      mode: OnboardingMode.local,
      port: port,
      onClose: () => closes++,
    );
    await tester.tap(find.byKey(const Key('onboarding-close')));
    await tester.pumpAndSettle();
    expect(port.saves, 1);
    expect(closes, 1);
    expect(c.value.completed, false);
  });

  testWidgets('failed save requires explicit close without saving', (
    tester,
  ) async {
    var closes = 0;
    final port = FakeOnboardingPort(facts())..saveReceipt = false;
    await pumpSetup(tester, port: port, onClose: () => closes++);
    await tester.tap(find.byKey(const Key('onboarding-close')));
    await tester.pumpAndSettle();
    expect(find.text('进度尚未保存'), findsOneWidget);
    expect(closes, 0);
    await tester.tap(find.text('继续设置'));
    await tester.pumpAndSettle();
    expect(closes, 0);
    await tester.tap(find.byKey(const Key('onboarding-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不保存并关闭'));
    await tester.pumpAndSettle();
    expect(closes, 1);
  });

  testWidgets('online page keeps sharing and inheritance separate', (
    tester,
  ) async {
    await pumpSetup(
      tester,
      step: OnboardingStep.online,
      mode: OnboardingMode.online,
      observation: facts(confirmed: true, onlineReviewed: false),
    );
    expect(find.text('共享由你决定，暂不开启也可以完成设置。'), findsOneWidget);
    expect(find.text('资料继承需单独预览和确认，不会自动合并或覆盖。'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('onboarding-next')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('keyboard can select local mode and continue', (tester) async {
    final port = FakeOnboardingPort(facts(signedIn: false));
    final c = await pumpSetup(tester, step: OnboardingStep.mode, port: port);
    // Follow the actual native tab order: close action, then the radio group.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    // RadioGroup responds to arrows/space without pointer clicks.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.value.mode, OnboardingMode.local);
    expect(port.actions, isEmpty);
  });

  for (final stage in OnboardingStep.values) {
    testWidgets('${stage.name} fits at 320 with 160% text', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpSetup(
        tester,
        step: stage,
        mode: stage == OnboardingStep.welcome ? null : OnboardingMode.online,
        observation: facts(confirmed: true),
        scale: 1.6,
      );
      await tester.drag(
        find.byKey(const Key('onboarding-scroll')),
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final capture
      in <String, (OnboardingStep, OnboardingMode?, OnboardingFacts)>{
        'mode-dark': (OnboardingStep.mode, null, facts()),
        'identity-dark': (
          OnboardingStep.identity,
          OnboardingMode.local,
          facts(),
        ),
        'wait-for-game-dark': (
          OnboardingStep.identity,
          OnboardingMode.local,
          facts(evidence: OnboardingEvidence.missing),
        ),
        'summary-light': (
          OnboardingStep.summary,
          OnboardingMode.local,
          facts(confirmed: true),
        ),
      }.entries) {
    testWidgets('preview ${capture.key}', (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpSetup(
        tester,
        step: capture.value.$1,
        mode: capture.value.$2,
        observation: capture.value.$3,
        appearance: capture.key.endsWith('light')
            ? AppearanceMode.light
            : AppearanceMode.dark,
      );
      if (!const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE')) {
        await expectLater(
          find.byKey(const Key('onboarding-capture')),
          matchesGoldenFile('goldens/${capture.key}.png'),
        );
      }
    });
  }

  test('copy defines all stages in three locales', () {
    for (final locale in [
      const Locale('zh', 'CN'),
      const Locale('zh', 'TW'),
      const Locale('en', 'US'),
    ]) {
      final copy = OnboardingCopy(locale);
      for (final stage in OnboardingStep.values) {
        expect(copy.step(stage), isNotEmpty);
        expect(copy.title(stage), isNotEmpty);
        expect(copy.description(stage), isNotEmpty);
      }
    }
  });
}
