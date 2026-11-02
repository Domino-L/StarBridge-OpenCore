import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_port.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_projection.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:starbridge_flutter/features/onboarding/app_behavior_choice_controller.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_summary.dart';

import 'onboarding_page_test.dart' show pumpSetup;
import 'onboarding_test_support.dart';

final class _FlakyPreferences implements AppPreferencesPort {
  _FlakyPreferences({AppPreferences initial = AppPreferences.defaults})
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

ApplicationBehaviorPreferences _behavior(AppPreferencesPort p) =>
    p.projection.value.confirmed!.applicationBehavior;

AppPreferences _chosen({required bool launch, required bool tray}) =>
    AppPreferences.defaults.copyWith(
      applicationBehavior: ApplicationBehaviorPreferences.defaults.copyWith(
        launchAtStartup: launch,
        startMinimized: launch,
        startupChoiceMade: true,
        keepRunningInBackground: tray,
        closeBehaviorChoiceMade: true,
      ),
    );

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

  test('first choice is never preselected and needs both answers', () async {
    final prefs = _FlakyPreferences();
    final c = AppBehaviorChoiceController(prefs);
    addTearDown(c.dispose);
    expect(c.value.launchAtStartup, isNull);
    expect(c.value.keepInTray, isNull);
    expect(c.value.saved, false);
    c.chooseStartup(true);
    expect(c.value.canSave, false);
    expect(await c.save(), false);
    expect(prefs.writes, 0);
    c.chooseClose(false);
    expect(c.value.canSave, true);
    expect(await c.save(), true);
    final saved = _behavior(prefs);
    expect(saved.startupChoiceMade && saved.closeBehaviorChoiceMade, true);
    expect(saved.launchAtStartup && saved.startMinimized, true);
    expect(saved.keepRunningInBackground, false);
    expect(c.value.saved && !c.value.dirty, true);
  });

  test('existing choices show as saved; failed save keeps them', () async {
    final prefs = _FlakyPreferences(
      initial: _chosen(launch: false, tray: true),
    );
    final c = AppBehaviorChoiceController(prefs);
    addTearDown(c.dispose);
    expect(c.value.saved, true);
    expect(c.value.savedLaunchAtStartup, false);
    expect(c.value.canSave, false, reason: 'nothing changed');
    prefs.fail = true;
    c.chooseStartup(true);
    expect(c.value.dirty, true);
    expect(await c.save(), false);
    expect(c.value.failed, true);
    expect(_behavior(prefs).launchAtStartup, false, reason: 'unchanged');
    expect(c.value.launchAtStartup, true, reason: 'draft kept for retry');
    prefs.fail = false;
    expect(await c.save(), true);
    expect(c.value.failed, false);
    expect(_behavior(prefs).launchAtStartup, true);
  });

  test('summary reports the saved combination, not the draft', () {
    final view = OnboardingView(
      step: OnboardingStep.summary,
      mode: OnboardingMode.local,
      facts: facts(confirmed: true, signedIn: false, matched: false),
    );
    SummaryEntry row(AppBehaviorChoiceView v) =>
        buildOnboardingSummary(view: view, appBehavior: v)
            .singleWhere((e) => e.item == SummaryItem.appBehavior);
    var e = row(const AppBehaviorChoiceView(available: true));
    expect(e.status, SummaryStatus.incomplete);
    e = row(
      const AppBehaviorChoiceView(
        available: true,
        launchAtStartup: true,
        keepInTray: true,
      ),
    );
    expect(e.status, SummaryStatus.incomplete, reason: 'unsaved draft');
    e = row(const AppBehaviorChoiceView(available: true, failed: true));
    expect(e.status, SummaryStatus.failed);
    e = row(
      const AppBehaviorChoiceView(
        available: true,
        savedLaunchAtStartup: false,
        savedKeepInTray: true,
        launchAtStartup: false,
        keepInTray: true,
      ),
    );
    expect(e.status, SummaryStatus.saved);
    expect(e.detail, 'summary.detail.appBehavior.manualTray');
  });

  testWidgets('local step asks once and blocks Next until saved', (
    tester,
  ) async {
    final prefs = _FlakyPreferences();
    addTearDown(prefs.dispose);
    final c = AppBehaviorChoiceController(prefs);
    addTearDown(c.dispose);
    await pumpSetup(
      tester,
      step: OnboardingStep.local,
      mode: OnboardingMode.local,
      observation: facts(confirmed: true, signedIn: false, matched: false),
      appBehavior: c,
    );
    FilledButton next() =>
        tester.widget<FilledButton>(find.byKey(const Key('onboarding-next')));
    expect(find.text('启动与关闭方式'), findsOneWidget);
    expect(find.textContaining('请分别选择两项'), findsOneWidget);
    expect(next().onPressed, isNull);
    for (final key in ['app-behavior-startup-auto', 'app-behavior-close-tray']) {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
    }
    await tester.ensureVisible(find.byKey(const Key('app-behavior-save')));
    await tester.tap(find.byKey(const Key('app-behavior-save')));
    await tester.pumpAndSettle();
    expect(prefs.writes, 1);
    expect(find.textContaining('已保存。以后可在'), findsOneWidget);
    expect(next().onPressed, isNotNull);
  });

  testWidgets('preview app-behavior-light', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = _FlakyPreferences();
    addTearDown(prefs.dispose);
    final c = AppBehaviorChoiceController(prefs)..chooseStartup(true);
    addTearDown(c.dispose);
    await pumpSetup(
      tester,
      step: OnboardingStep.local,
      mode: OnboardingMode.local,
      observation: facts(confirmed: true, signedIn: false, matched: false),
      appearance: AppearanceMode.light,
      appBehavior: c,
    );
    if (!const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE')) {
      await expectLater(
        find.byKey(const Key('onboarding-capture')),
        matchesGoldenFile('goldens/app-behavior-light.png'),
      );
    }
  });
}
