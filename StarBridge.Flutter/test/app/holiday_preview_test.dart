// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/appearance/holiday_appearance_controller.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_port.dart';
import 'package:starbridge_flutter/app/preferences/host_unavailable_app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_calendar.dart';
import 'package:starbridge_flutter/design_system/appearance/appearance_scope.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_theme.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/general_settings_page.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';

// 调试预览（STARBRIDGE_HOLIDAY_PREVIEW）：不看日期、不看开关，只在本次运行有效，界面上没有入口。
// 默认开：没设置过的人节日期间自动生效，关过的人保持关。
// 自动切换：跨年、改日期/时区（wake）、客户端一直开着跨过边界。
void main() {
  group('控制器', () {
    test('不在节日里也能预览；结束预览回到平时；预览不受开关影响', () async {
      final preferences = InMemoryAppPreferences(
        initial: AppPreferences.defaults.copyWith(holidayAppearance: false),
      );
      final chrome = InMemoryWindowChrome();
      final controller = HolidayAppearanceController(
        calendar: BuiltInHolidayCalendar(),
        preferences: preferences.projection,
        windowChrome: chrome,
        now: () => DateTime(2026, 11, 3),
        schedule: (_, _) {},
      );
      addTearDown(() {
        controller.dispose();
        preferences.dispose();
      });
      expect(controller.layers.value.holidayActive, isFalse);

      controller.previewHoliday('xmas');
      expect(controller.layers.value.holiday, xmasHolidayTheme);
      expect(controller.layers.value.previewing, isTrue);
      expect(controller.layers.value.holidayActive, isTrue, reason: '开关关着也能预览');
      expect(chrome.commands.last, 'setIconVariant:xmas');

      controller.previewHoliday('xmas');
      expect(
        chrome.commands.where((c) => c.startsWith('setIconVariant')).length,
        1,
        reason: '重复点同一个不重发',
      );

      controller.previewHoliday(null);
      expect(controller.layers.value.previewing, isFalse);
      expect(controller.layers.value.holidayActive, isFalse);
      expect(chrome.commands.last, 'setIconVariant:default');

      controller.previewHoliday('no-such-holiday');
      expect(controller.layers.value.previewing, isFalse);
    });

    test('跨年：12-31 和 01-01 都是圣诞，01-03 零点改回', () {
      var now = DateTime(2026, 12, 31, 23, 59);
      void Function()? wake;
      final preferences = InMemoryAppPreferences();
      final controller = HolidayAppearanceController(
        calendar: BuiltInHolidayCalendar(),
        preferences: preferences.projection,
        now: () => now,
        schedule: (_, w) => wake = w,
      );
      addTearDown(() {
        controller.dispose();
        preferences.dispose();
      });
      expect(controller.layers.value.holidayActive, isTrue);
      expect(controller.nextCheck, DateTime(2027, 1, 3));
      now = DateTime(2027, 1, 1, 0, 0, 1);
      wake!();
      expect(controller.layers.value.holidayActive, isTrue);
      now = DateTime(2027, 1, 3, 0, 0, 1);
      wake!();
      expect(controller.layers.value.holidayActive, isFalse);
    });

    test('改了系统日期或时区：wake 后按新日期判断', () {
      var now = DateTime(2026, 11, 3);
      final preferences = InMemoryAppPreferences();
      final controller = HolidayAppearanceController(
        calendar: BuiltInHolidayCalendar(),
        preferences: preferences.projection,
        now: () => now,
        schedule: (_, _) {},
      );
      addTearDown(() {
        controller.dispose();
        preferences.dispose();
      });
      expect(controller.layers.value.holidayActive, isFalse);
      now = DateTime(2026, 12, 24, 9);
      controller.wake();
      expect(controller.layers.value.holidayActive, isTrue);
      now = DateTime(2026, 11, 4);
      controller.wake();
      expect(controller.layers.value.holidayActive, isFalse);
    });

    test('真实定时器：到了边界自动换，不用重启', () {
      FakeAsync().run((async) {
        var now = DateTime(2026, 12, 17, 23, 59, 30);
        final preferences = InMemoryAppPreferences();
        final controller = HolidayAppearanceController(
          calendar: BuiltInHolidayCalendar(),
          preferences: preferences.projection,
          now: () => now,
        );
        expect(controller.layers.value.holidayActive, isFalse);
        // 走到 12-18 零点过一秒，定时器醒来。
        now = DateTime(2026, 12, 18, 0, 0, 1);
        async.elapse(const Duration(seconds: 31));
        expect(controller.layers.value.holidayActive, isTrue);
        // 每分钟看一次日期：直接把日期改到 01-05，不等定时器也会改回。
        now = DateTime(2027, 1, 5, 10);
        async.elapse(const Duration(minutes: 1));
        expect(controller.layers.value.holidayActive, isFalse);
        controller.dispose();
        preferences.dispose();
      });
    });
  });

  group('设置页', () {
    const previewTexts = ['立即预览', '立即預覽', 'Preview now', '结束预览', '結束預覽', 'End preview'];

    Future<void> pump(
      WidgetTester tester,
      AppPreferencesPort preferences,
      Locale locale,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark),
            locale,
          ),
          home: Scaffold(body: GeneralSettingsPage(preferences: preferences)),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final locale in AppStrings.supportedLocales) {
      testWidgets('$locale：没有预览入口，开关还在，默认开着', (tester) async {
        final preferences = InMemoryAppPreferences();
        addTearDown(preferences.dispose);
        await pump(tester, preferences, locale);
        for (final text in previewTexts) {
          expect(find.text(text), findsNothing);
        }
        final toggle = find.byKey(const Key('general-holiday-appearance'));
        await tester.ensureVisible(toggle);
        expect(toggle, findsOneWidget);
        final control = find.ancestor(
          of: toggle,
          matching: find.byType(StarBridgeSwitch),
        );
        expect(tester.widget<StarBridgeSwitch>(control).value, isTrue);
      });
    }

    testWidgets('读不到设置时也没有预览入口', (tester) async {
      await pump(
        tester,
        HostUnavailableAppPreferences(),
        const Locale('zh', 'CN'),
      );
      expect(find.byKey(const Key('general-settings-retry')), findsOneWidget);
      for (final text in previewTexts) {
        expect(find.text(text), findsNothing);
      }
    });
  });

  group('整个应用', () {
    Future<InMemoryWindowChrome> pumpApp(
      WidgetTester tester, {
      required DateTime now,
      AppPreferences? initial,
      String? debugPreview,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final chrome = InMemoryWindowChrome();
      final composition = AppComposition.forTest(
        windowChrome: chrome,
        preferences: initial == null
            ? null
            : InMemoryAppPreferences(initial: initial),
      );
      await tester.pumpWidget(
        StarBridgeApp(
          composition: composition,
          holidayCalendar: BuiltInHolidayCalendar(),
          now: () => now,
          initialHolidayPreview: debugPreview,
        ),
      );
      await tester.pumpAndSettle();
      return chrome;
    }

    final surfacePrint = find.byKey(const Key('surface-print-navigation'));
    ThemeData? exemptTheme(WidgetTester tester) => tester
        .widget<HolidayExemptThemeScope>(find.byType(HolidayExemptThemeScope))
        .data;

    String greetingText(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('home-greeting'))).data!;

    testWidgets('从没设置过：节日期间自动换上，交易页的还原主题也在', (tester) async {
      final chrome = await pumpApp(tester, now: DateTime(2026, 12, 24));
      expect(surfacePrint, findsOneWidget);
      expect(chrome.commands, contains('setIconVariant:xmas'));
      expect(exemptTheme(tester), isNotNull);
      expect(greetingText(tester), contains('🎄'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('明确关过：节日期间也保持平时', (tester) async {
      final chrome = await pumpApp(
        tester,
        now: DateTime(2026, 12, 24),
        initial: AppPreferences.defaults.copyWith(holidayAppearance: false),
      );
      expect(surfacePrint, findsNothing);
      expect(chrome.commands, isNot(contains('setIconVariant:xmas')));
      expect(exemptTheme(tester), isNull);
      expect(greetingText(tester), isNot(contains('🎄')));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('平时的日子：什么都不换', (tester) async {
      await pumpApp(tester, now: DateTime(2026, 11, 3));
      expect(surfacePrint, findsNothing);
      expect(exemptTheme(tester), isNull);
      expect(greetingText(tester), isNot(contains('🎃')));
      expect(greetingText(tester), isNot(contains('🎄')));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('调试预览：不在节日里也出现，开关关着也出现', (tester) async {
      final chrome = await pumpApp(
        tester,
        now: DateTime(2026, 11, 3),
        initial: AppPreferences.defaults.copyWith(holidayAppearance: false),
        debugPreview: 'xmas',
      );
      expect(surfacePrint, findsOneWidget);
      expect(chrome.commands, contains('setIconVariant:xmas'));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
