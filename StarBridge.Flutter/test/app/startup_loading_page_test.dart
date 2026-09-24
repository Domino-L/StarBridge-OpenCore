import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/startup/startup_brand_logo.dart';
import 'package:starbridge_flutter/app/startup/startup_loading_page.dart';
import 'package:starbridge_flutter/app/startup/startup_motion_spec.dart';
import 'package:starbridge_flutter/app/startup/startup_session.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

void main() {
  setUpAll(() async {
    if (const bool.fromEnvironment('STARTUP_GOLDENS')) {
      for (final font in {
        'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
        'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
      }.entries) {
        await (FontLoader(
          font.key,
        )..addFont(rootBundle.load(font.value))).load();
      }
      // Desktop engine tests do not automatically discover Windows font fallbacks.
      await (FontLoader('Microsoft JhengHei UI')..addFont(
            File('C:/Windows/Fonts/msjh.ttc')
                .readAsBytes()
                .then(ByteData.sublistView),
          ))
          .load();
    }
  });

  testWidgets('unknown preferences stay still and never invent readiness', (
    tester,
  ) async {
    final session = StartupSession();
    addTearDown(session.dispose);
    await _pump(tester, session);
    await tester.pump(const Duration(seconds: 30));
    expect(session.value, StartupPhase.connecting);
    expect(_logo(tester).spin.value, 0);
    expect(_logo(tester).assemblyProgress, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.tap(find.byKey(const Key('startup-enter')));
    expect(session.complete, isTrue);
  });

  testWidgets('failure stops logo and retry is visible and single flight', (
    tester,
  ) async {
    final session = StartupSession();
    addTearDown(session.dispose);
    final pending = Completer<void>();
    var calls = 0;
    await _pump(
      tester,
      session,
      confirmed: true,
      onRetry: () async {
        calls++;
        session.connecting(manual: true);
        await pending.future;
        session.hostUnavailable();
      },
    );
    await tester.pump(const Duration(milliseconds: 120));
    session.hostUnavailable();
    await tester.pump();
    final stopped = _logo(tester).spin.value;
    await tester.pump(const Duration(seconds: 3));
    expect(_logo(tester).spin.value, stopped);
    await tester.tap(find.byKey(const Key('startup-retry')));
    await tester.pump();
    expect(find.text('正在重试…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byKey(const Key('startup-retry')));
    expect(calls, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('暂时无法启动本机服务'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final mode in ['user', 'system', 'performance']) {
    testWidgets(
      '$mode reduction shows original logo and hands off without a delay',
      (tester) async {
        final session = StartupSession();
        addTearDown(session.dispose);
        await _pump(
          tester,
          session,
          confirmed: true,
          reduce: mode == 'user',
          systemReduce: mode == 'system',
          lowPerformance: mode == 'performance',
        );
        expect(
          find.byKey(const Key('startup-brand-settled-image')),
          findsOneWidget,
        );
        expect(_logo(tester).spin.value, 0);
        session.resolveAccount(
          AccountProjection.fromSnapshot(
            const AccountHostSnapshot.signedOut(generation: 0),
          ),
        );
        await tester.pump();
        expect(session.complete, isTrue);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('hidden window stops timers and ready can finish in background', (
    tester,
  ) async {
    final session = StartupSession();
    addTearDown(session.dispose);
    await _pump(tester, session, confirmed: true);
    await tester.pump(const Duration(milliseconds: 100));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    final before = _logo(tester).spin.value;
    await tester.pump(const Duration(seconds: 3));
    expect(_logo(tester).spin.value, before);
    session.resolveAccount(
      AccountProjection.fromSnapshot(
        const AccountHostSnapshot.signedOut(generation: 0),
      ),
    );
    await tester.pump();
    expect(session.complete, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('system reduced-motion change immediately stops a running turn', (
    tester,
  ) async {
    final session = StartupSession();
    addTearDown(session.dispose);
    await _pump(tester, session, confirmed: true);
    await tester.pump(const Duration(milliseconds: 150));
    expect(_logo(tester).spin.value, greaterThan(0));
    await _pump(tester, session, confirmed: true, systemReduce: true);
    expect(_logo(tester).reduceMotion, isTrue);
    final before = _logo(tester).spin.value;
    await tester.pump(const Duration(seconds: 2));
    expect(_logo(tester).spin.value, before);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('window controls remain usable during a stalled connection', (
    tester,
  ) async {
    final session = StartupSession();
    addTearDown(session.dispose);
    final chrome = InMemoryWindowChrome();
    await _pump(tester, session, chrome: chrome);
    await tester.tap(find.byTooltip('最小化'));
    await tester.tap(find.byKey(const Key('window-maximize-control')));
    await tester.tap(find.byTooltip('关闭'));
    expect(chrome.commands, ['minimize', 'toggleMaximize', 'close']);
  });

  for (final direction in StartupMotionDirection.values) {
    testWidgets(
      '${direction.name} assembles only after ready and uses the original final image',
      (tester) async {
        final session = _sessionFor(direction);
        addTearDown(session.dispose);
        await _pump(tester, session);
        session.readingPreferences();
        session.resolveAccount(
          AccountProjection.fromSnapshot(
            const AccountHostSnapshot.signedOut(generation: 0),
          ),
        );
        await tester.pump();
        await tester.pump(session.spec.assemblyDuration ~/ 2);
        expect(_logo(tester).assemblyProgress, closeTo(.5, .05));
        await _golden(tester, '${direction.name}-assembly');
        await tester.pump(session.spec.assemblyDuration);
        final settled = tester.widget<Image>(
          find.byKey(const Key('startup-brand-settled-image')),
        );
        expect((settled.image as AssetImage).assetName, startupLogoAsset);
        await _golden(tester, '${direction.name}-settled');
        await tester.pump(); // Start the handoff ticker scheduled by assembly.
        await tester.pump(session.spec.handoffDuration);
        expect(
          tester
              .widget<Opacity>(find.byKey(const Key('startup-handoff')))
              .opacity,
          0,
        );
        // Handoff is finished; terminal navigation is deferred out of build.
        await tester.pump(const Duration(milliseconds: 20));
        expect(session.complete, isTrue);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final locale in AppStrings.supportedLocales) {
    for (final appearance in AppearanceMode.values) {
      testWidgets(
        '${locale.toLanguageTag()} ${appearance.name} narrow large text stays accessible',
        (tester) async {
          final session = StartupSession()..preferencesUnavailable();
          addTearDown(session.dispose);
          await _pump(
            tester,
            session,
            locale: locale,
            appearance: appearance,
            size: const Size(420, 640),
            textScale: 1.6,
            reduce: true,
          );
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.byKey(const Key('startup-enter')));
          await tester.pump();
          await _golden(
            tester,
            '${locale.toLanguageTag()}-${appearance.name}-narrow',
          );
          await tester.tap(find.byKey(const Key('startup-enter')));
          expect(session.complete, isTrue);
        },
      );
    }
  }
}

FivePartBrandLogo _logo(WidgetTester tester) =>
    tester.widget(find.byType(FivePartBrandLogo));

StartupSession _sessionFor(StartupMotionDirection direction) {
  for (var seed = 0; ; seed++) {
    final session = StartupSession(random: Random(seed));
    if (session.spec.direction == direction) return session;
    session.dispose();
  }
}

Future<void> _pump(
  WidgetTester tester,
  StartupSession session, {
  bool confirmed = false,
  bool reduce = false,
  bool systemReduce = false,
  bool lowPerformance = false,
  double textScale = 1,
  Size size = const Size(1280, 720),
  Locale locale = const Locale('zh', 'CN'),
  AppearanceMode appearance = AppearanceMode.dark,
  InMemoryWindowChrome? chrome,
  Future<void> Function()? onRetry,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(appearance),
        locale,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: systemReduce,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: StartupLoadingPage(
        session: session,
        windowChrome: chrome ?? InMemoryWindowChrome(),
        preferencesConfirmed: confirmed,
        reduceMotion: reduce,
        lowPerformance: lowPerformance,
        onRetry: onRetry ?? () async {},
      ),
    ),
  );
  await tester
      .pump(); // Material localization delegates resolve asynchronously.
  await tester.runAsync(() async {
    final context = tester.element(find.byType(StartupLoadingPage));
    await precacheImage(const AssetImage(startupLogoAsset), context);
    if (context.mounted) {
      await precacheImage(const AssetImage(startupCenterStarAsset), context);
    }
  });
  await tester.pump();
}

Future<void> _golden(WidgetTester tester, String name) async {
  if (const bool.fromEnvironment('STARTUP_GOLDENS')) {
    await expectLater(
      find.byType(StartupLoadingPage),
      matchesGoldenFile('goldens/startup/$name.png'),
    );
  }
}
