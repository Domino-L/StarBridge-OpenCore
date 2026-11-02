import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_port.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_projection.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/runtime/application_behavior_prompt.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

final class _Prefs implements AppPreferencesPort {
  _Prefs(AppPreferences initial)
    : _inner = InMemoryAppPreferences(initial: initial);
  final InMemoryAppPreferences _inner;
  bool fail = false;
  int writes = 0;
  @override
  ValueListenable<AppPreferencesProjection> get projection => _inner.projection;
  @override
  Future<bool> setApplicationBehavior(
    ApplicationBehaviorPreferences behavior,
  ) async {
    writes++;
    if (fail) return false;
    return _inner.setApplicationBehavior(behavior);
  }

  @override
  Future<bool> setLocale(Locale locale) => _inner.setLocale(locale);
  @override
  Future<bool> setAppearanceMode(AppearanceMode mode) =>
      _inner.setAppearanceMode(mode);
  @override
  Future<bool> setHolidayAppearance(bool enabled) =>
      _inner.setHolidayAppearance(enabled);
  @override
  Future<bool> setMotionPreference(MotionPreference preference) =>
      _inner.setMotionPreference(preference);
  @override
  Future<bool> setInteractionStyle(InteractionStyle style) =>
      _inner.setInteractionStyle(style);
  @override
  Future<bool> retry() => _inner.retry();
  @override
  void dispose() => _inner.dispose();
}

ApplicationBehaviorPreferences _b(_Prefs p) =>
    p.projection.value.confirmed!.applicationBehavior;

_Prefs _prefs({bool startupChosen = false, bool closeChosen = false}) {
  final p = _Prefs(
    AppPreferences.defaults.copyWith(
      applicationBehavior: ApplicationBehaviorPreferences.defaults.copyWith(
        launchAtStartup: startupChosen,
        startMinimized: false,
        startupChoiceMade: startupChosen,
        keepRunningInBackground: true,
        closeBehaviorChoiceMade: closeChosen,
      ),
    ),
  );
  addTearDown(p.dispose);
  return p;
}

Future<Future<bool>> _open(WidgetTester tester, _Prefs prefs) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  const locale = Locale('zh', 'CN');
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        locale,
      ),
      locale: locale,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Covers the root navigator, so the dialog route is in the capture.
      builder: (_, child) =>
          RepaintBoundary(key: const Key('capture'), child: child),
      home: Scaffold(
        body: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  final result = showApplicationBehaviorPrompt(context, prefs);
  await tester.pumpAndSettle();
  return result;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

bool _saveEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const Key('app-behavior-prompt-save')))
        .onPressed !=
    null;

void main() {
  setUpAll(() async {
    for (final font in <String, String>{
      'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
      'Saira': 'assets/fonts/Saira-VF.ttf',
      'Rajdhani': 'assets/fonts/Rajdhani-SemiBold.ttf',
      'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  testWidgets('both unchosen: one prompt, nothing preselected, saves both', (
    tester,
  ) async {
    final prefs = _prefs();
    final result = await _open(tester, prefs);
    expect(find.text('启动与关闭方式'), findsOneWidget);
    expect(find.byKey(const Key('app-behavior-startup-auto')), findsOneWidget);
    expect(find.byKey(const Key('app-behavior-close-tray')), findsOneWidget);
    expect(
      find.text('当前'),
      findsNWidgets(2),
      reason: 'effective values marked',
    );
    expect(_saveEnabled(tester), isFalse, reason: 'never preselected');
    await _tap(tester, 'app-behavior-startup-auto');
    expect(_saveEnabled(tester), isFalse);
    await _tap(tester, 'app-behavior-close-tray');
    if (!const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE')) {
      await expectLater(
        find.byKey(const Key('capture')),
        matchesGoldenFile('goldens/behavior-prompt-both-dark.png'),
      );
    }
    await _tap(tester, 'app-behavior-prompt-save');
    expect(prefs.writes, 1);
    final saved = _b(prefs);
    expect(saved.startupChoiceMade && saved.closeBehaviorChoiceMade, isTrue);
    expect(saved.launchAtStartup && saved.startMinimized, isTrue);
    expect(saved.keepRunningInBackground, isTrue);
    expect(find.textContaining('已保存'), findsOneWidget);
    await _tap(tester, 'app-behavior-prompt-save');
    expect(await result, isTrue);
  });

  testWidgets('only the never-chosen question is asked', (tester) async {
    final prefs = _prefs(startupChosen: true);
    final result = await _open(tester, prefs);
    expect(find.text('关闭主窗口时怎么处理？'), findsOneWidget);
    expect(find.byKey(const Key('app-behavior-startup-auto')), findsNothing);
    expect(find.textContaining('开机方式你之前已经选过：随 Windows 启动'), findsOneWidget);
    await _tap(tester, 'app-behavior-close-exit');
    if (!const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE')) {
      await expectLater(
        find.byKey(const Key('capture')),
        matchesGoldenFile('goldens/behavior-prompt-close-dark.png'),
      );
    }
    await _tap(tester, 'app-behavior-prompt-save');
    final saved = _b(prefs);
    expect(saved.launchAtStartup, isTrue);
    expect(saved.startMinimized, isFalse, reason: 'earlier choice untouched');
    expect(saved.keepRunningInBackground, isFalse);
    expect(saved.closeBehaviorChoiceMade, isTrue);
    await _tap(tester, 'app-behavior-prompt-save');
    expect(await result, isTrue);
  });

  testWidgets('later writes nothing and reports deferred', (tester) async {
    final prefs = _prefs();
    final result = await _open(tester, prefs);
    await _tap(tester, 'app-behavior-startup-manual');
    await _tap(tester, 'app-behavior-prompt-later');
    expect(await result, isFalse);
    expect(prefs.writes, 0);
    expect(_b(prefs).startupChoiceMade, isFalse);
  });

  testWidgets('a failed save keeps the original and offers retry', (
    tester,
  ) async {
    final prefs = _prefs()..fail = true;
    final result = await _open(tester, prefs);
    await _tap(tester, 'app-behavior-startup-manual');
    await _tap(tester, 'app-behavior-close-exit');
    await _tap(tester, 'app-behavior-prompt-save');
    expect(find.text('未能保存，原设置未改变。请重试。'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(_b(prefs).startupChoiceMade, isFalse);
    prefs.fail = false;
    await _tap(tester, 'app-behavior-prompt-save');
    expect(_b(prefs).closeBehaviorChoiceMade, isTrue);
    expect(_b(prefs).launchAtStartup, isFalse);
    await _tap(tester, 'app-behavior-prompt-save');
    expect(await result, isTrue);
  });
}
