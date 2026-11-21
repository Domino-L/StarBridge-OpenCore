import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/routing/screen_reading_route.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/screen_reading_settings_page.dart';
import 'package:starbridge_flutter/features/settings/settings_models.dart';
import 'package:starbridge_flutter/features/settings/settings_page.dart';

// "屏幕读取"：本机设置里单独一类（用户 11-10）。读血开关默认关；浮层设置里的跳转在这一类上线后才显示。
// 用户 11-14：开关旁只留一句话和"查看说明"；打开时先弹确认框（完整说明 + 风险说明），
// 点"同意并开启"才打开，取消保持关闭；关掉不弹；每次打开都弹，没有"不再提示"。
void main() {
  testWidgets('the own health switch lives in screen reading, off by default, with one short line', (
    tester,
  ) async {
    final preferences = InMemoryAppPreferences();
    addTearDown(preferences.dispose);
    await tester.pumpWidget(_app(ScreenReadingSettingsPage(preferences: preferences)));
    await tester.pumpAndSettle();

    expect(find.text('屏幕读取'), findsOneWidget);
    expect(preferences.projection.value.effective.readOwnHealth, isFalse);
    // 用户 11-12："可以直接往应用里放了，注明实验版"
    expect(find.text('读取自己的血量（实验版）'), findsOneWidget);
    expect(find.text('读取画面左下角自己的血量，显示在面罩里。开启前需要阅读并同意风险说明。'), findsOneWidget);
    expect(find.text('查看说明'), findsOneWidget);
    // 大段说明不再常显在开关旁。
    expect(find.textContaining('不读游戏内存'), findsNothing);
    expect(find.text('自动读取游戏画面可能不符合游戏的使用条款，请自行判断是否开启。'), findsNothing);
  });

  testWidgets('turning reading on asks first; cancel keeps it off, agree turns it on, off never asks', (
    tester,
  ) async {
    final preferences = InMemoryAppPreferences();
    addTearDown(preferences.dispose);
    await tester.pumpWidget(_app(ScreenReadingSettingsPage(preferences: preferences)));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('general-read-own-health'));
    final consent = find.byKey(const Key('own-health-consent'));

    // 取消：保持关闭。确认框开着时、点任何按钮之前，开关必须还是关着（不能先开再在取消时关）。
    await _tapToggle(tester, toggle);
    expect(consent, findsOneWidget);
    expect(preferences.projection.value.effective.readOwnHealth, isFalse);
    expect(find.text('开启“读取自己的血量（实验版）”'), findsOneWidget);
    for (final title in ['会读什么', '怎么读', '不做的事', '还要知道', '风险说明']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.textContaining('用 Windows 图形捕获，只读游戏窗口本身的画面'), findsOneWidget);
    expect(find.textContaining('不读游戏内存，不注入游戏，不模拟任何按键或鼠标'), findsOneWidget);
    expect(find.textContaining('没打开时面罩里不显示你的血量圆环'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('own-health-risk')),
        matching: find.text('自动读取游戏画面可能不符合游戏的使用条款，请自行判断是否开启。'),
      ),
      findsOneWidget,
    );
    expect(find.text('点“同意并开启”，表示你已经看过上面的说明，了解可能的风险，自己决定开启。'), findsOneWidget);
    expect(find.text('不再提示'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.byKey(const Key('own-health-consent-cancel')));
    await tester.pumpAndSettle();
    expect(consent, findsNothing);
    expect(preferences.projection.value.effective.readOwnHealth, isFalse);

    // Esc 也算取消。
    await _tapToggle(tester, toggle);
    expect(consent, findsOneWidget);
    expect(preferences.projection.value.effective.readOwnHealth, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(consent, findsNothing);
    expect(preferences.projection.value.effective.readOwnHealth, isFalse);

    // 点框外也算取消。
    await _tapToggle(tester, toggle);
    expect(consent, findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(consent, findsNothing);
    expect(preferences.projection.value.effective.readOwnHealth, isFalse);

    // 确认框开着时再点开关的位置：点到的是遮罩，只会关掉这个框，不会叠出第二个框，也不会打开。
    await _tapToggle(tester, toggle);
    await tester.tap(toggle, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(consent, findsNothing);
    expect(preferences.projection.value.effective.readOwnHealth, isFalse);

    // 同意：打开，开关旁那句话换成开着时的写法。
    await _tapToggle(tester, toggle);
    expect(preferences.projection.value.effective.readOwnHealth, isFalse);
    await tester.tap(find.byKey(const Key('own-health-consent-agree')));
    await tester.pumpAndSettle();
    expect(consent, findsNothing);
    expect(preferences.projection.value.effective.readOwnHealth, isTrue);
    expect(find.text('正在读取画面左下角自己的血量，显示在面罩里。关掉开关会立刻停止读取。'), findsOneWidget);

    // 关掉：不弹。
    await _tapToggle(tester, toggle);
    expect(consent, findsNothing);
    expect(preferences.projection.value.effective.readOwnHealth, isFalse);

    // 再打开：还是弹（不记"同意过"）。
    await _tapToggle(tester, toggle);
    expect(consent, findsOneWidget);
    expect(preferences.projection.value.effective.readOwnHealth, isFalse);
    await tester.tap(find.byKey(const Key('own-health-consent-agree')));
    await tester.pumpAndSettle();
    expect(preferences.projection.value.effective.readOwnHealth, isTrue);
  });

  testWidgets('view notes while off shows the notes and keeps reading off', (tester) async {
    final preferences = InMemoryAppPreferences();
    addTearDown(preferences.dispose);
    await tester.pumpWidget(_app(ScreenReadingSettingsPage(preferences: preferences)));
    await tester.pumpAndSettle();
    final notes = find.byKey(const Key('general-read-own-health-notes'));
    await tester.ensureVisible(notes);
    await tester.pumpAndSettle();
    await tester.tap(notes);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('own-health-notes')), findsOneWidget);
    expect(find.byKey(const Key('own-health-consent-agree')), findsNothing);
    await tester.tap(find.byKey(const Key('own-health-notes-close')));
    await tester.pumpAndSettle();
    expect(preferences.projection.value.effective.readOwnHealth, isFalse);
  });

  testWidgets('already on after an upgrade: no prompt; view notes shows the notes and changes nothing', (
    tester,
  ) async {
    final preferences = InMemoryAppPreferences();
    addTearDown(preferences.dispose);
    await preferences.setReadOwnHealth(true);
    await tester.pumpWidget(_app(ScreenReadingSettingsPage(preferences: preferences)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('own-health-consent')), findsNothing);
    expect(preferences.projection.value.effective.readOwnHealth, isTrue);

    final notes = find.byKey(const Key('general-read-own-health-notes'));
    await tester.ensureVisible(notes);
    await tester.pumpAndSettle();
    await tester.tap(notes);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('own-health-notes')), findsOneWidget);
    expect(find.text('风险说明'), findsOneWidget);
    expect(find.byKey(const Key('own-health-consent-agree')), findsNothing);
    expect(find.textContaining('点“同意并开启”'), findsNothing);
    await tester.tap(find.byKey(const Key('own-health-notes-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('own-health-notes')), findsNothing);
    expect(preferences.projection.value.effective.readOwnHealth, isTrue);
  });

  for (final (locale, title, risk, confirm, line) in [
    (const Locale('zh', 'TW'), '開啟“讀取自己的血量（實驗版）”', '風險說明', '同意並開啟', '開啟前需要閱讀並同意風險說明'),
    (const Locale('en'), 'Turn on “Read my own health (experimental)”', 'Risk', 'Agree and turn on', 'read and agree to the risk notes'),
  ]) {
    testWidgets('the consent dialog speaks $locale', (tester) async {
      final preferences = InMemoryAppPreferences();
      addTearDown(preferences.dispose);
      await tester.pumpWidget(_app(ScreenReadingSettingsPage(preferences: preferences), locale: locale));
      await tester.pumpAndSettle();
      expect(find.textContaining(line), findsOneWidget);
      await _tapToggle(tester, find.byKey(const Key('general-read-own-health')));
      expect(find.text(title), findsOneWidget);
      expect(find.text(risk), findsOneWidget);
      expect(find.text(confirm), findsOneWidget);
      await tester.tap(find.byKey(const Key('own-health-consent-agree')));
      await tester.pumpAndSettle();
      expect(preferences.projection.value.effective.readOwnHealth, isTrue);
    });
  }

  // 用户 11-13："游戏在后台时也读取"是读血的子开关，默认关；读血关着时不能改。
  testWidgets('the background sub-switch is off by default and only changes while reading is on', (
    tester,
  ) async {
    final preferences = InMemoryAppPreferences();
    addTearDown(preferences.dispose);
    await tester.pumpWidget(_app(ScreenReadingSettingsPage(preferences: preferences)));
    await tester.pumpAndSettle();

    expect(find.text('游戏在后台时也读取'), findsOneWidget);
    expect(find.textContaining('游戏最小化后没有画面，读不到，圆环会隐藏'), findsOneWidget);
    expect(preferences.projection.value.effective.readOwnHealthInBackground, isFalse);

    final background = find.byKey(const Key('general-read-own-health-background'));
    await tester.ensureVisible(background);
    await tester.pumpAndSettle();
    await tester.tap(background, warnIfMissed: false);
    await tester.pump();
    expect(
      preferences.projection.value.effective.readOwnHealthInBackground,
      isFalse,
      reason: 'reading is off, so the sub-switch cannot change',
    );

    await _tapToggle(tester, find.byKey(const Key('general-read-own-health')));
    await tester.tap(find.byKey(const Key('own-health-consent-agree')));
    await tester.pumpAndSettle();
    expect(preferences.projection.value.effective.readOwnHealth, isTrue);
    expect(preferences.projection.value.effective.readOwnHealthInBackground, isFalse);

    await tester.ensureVisible(background);
    await tester.pumpAndSettle();
    await tester.tap(background);
    await tester.pump();
    expect(preferences.projection.value.effective.readOwnHealthInBackground, isTrue);
    expect(preferences.projection.value.effective.readOwnHealth, isTrue);
    await tester.tap(background);
    await tester.pump();
    expect(preferences.projection.value.effective.readOwnHealthInBackground, isFalse);
  });

  testWidgets('settings lists screen reading and shows its page when picked', (tester) async {
    final preferences = InMemoryAppPreferences();
    addTearDown(preferences.dispose);
    expect(visibleSettingsSections, contains(SettingsSection.screenReading));
    expect(screenReadingSettingsAvailable, isTrue);
    expect(screenReadingSettingsRoute, '/settings/screen-reading');
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        SettingsPage(
          initialSection: SettingsSection.screenReading,
          accountAndIdentityBuilder: (_) => const SizedBox(),
          generalDataBuilder: (_) => const SizedBox(),
          syncPrivacyBuilder: (_) => const SizedBox(),
          notificationsBuilder: (_) => const SizedBox(),
          screenReadingBuilder: (_) => ScreenReadingSettingsPage(preferences: preferences),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-section-screenReading')), findsOneWidget);
    expect(find.byKey(const Key('general-read-own-health')), findsOneWidget);
  });
}

Future<void> _tapToggle(WidgetTester tester, Finder toggle) async {
  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

Widget _app(Widget home, {Locale locale = const Locale('zh', 'CN')}) {
  final tokens = StyleRegistry()
      .resolve(AppPreferences.defaults.designStyleId, AppearanceMode.dark)
      .tokens;
  return MaterialApp(
    locale: locale,
    supportedLocales: AppStrings.runtimeSupportedLocales(),
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildStarBridgeTheme(tokens, locale),
    home: Scaffold(body: home),
  );
}
