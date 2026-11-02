import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/appearance/holiday_appearance_controller.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/design_system/appearance/appearance_layers.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_calendar.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_theme.dart';
import 'package:starbridge_flutter/design_system/appearance/user_background.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

// 到了日期自动换上，过了日期自动改回；开关关掉就一直是平时；图标跟着换。
final class _Rig {
  _Rig(DateTime start, {bool enabled = true})
    : now = start,
      preferences = InMemoryAppPreferences(
        initial: AppPreferences.defaults.copyWith(holidayAppearance: enabled),
      ) {
    controller = HolidayAppearanceController(
      calendar: BuiltInHolidayCalendar(),
      preferences: preferences.projection,
      windowChrome: chrome,
      now: () => now,
      schedule: (delay, wake) {
        scheduled.add(delay);
        pendingWake = wake;
      },
    );
  }
  DateTime now;
  final InMemoryAppPreferences preferences;
  final chrome = InMemoryWindowChrome();
  late final HolidayAppearanceController controller;
  final scheduled = <Duration>[];
  void Function()? pendingWake;

  /// 时间走到 [to]，然后定时器醒来。
  void advanceTo(DateTime to) {
    now = to;
    pendingWake?.call();
  }

  AppearanceLayers get layers => controller.layers.value;
  List<String> get icons =>
      chrome.commands.where((c) => c.startsWith('setIconVariant:')).toList();
  void dispose() {
    controller.dispose();
    preferences.dispose();
  }
}

void main() {
  test('节前是平时，到 12-18 零点自动换上，到 01-03 零点自动改回', () async {
    final rig = _Rig(DateTime(2026, 12, 17, 9));
    addTearDown(rig.dispose);
    expect(rig.layers.holidayActive, isFalse);
    expect(rig.icons, isEmpty, reason: '启动就是默认图标，不用再发');
    expect(rig.controller.nextCheck, DateTime(2026, 12, 18));
    // 定时器多等一秒，免得零点前一瞬醒来。
    expect(
      rig.scheduled.single,
      DateTime(2026, 12, 18).difference(rig.now) + const Duration(seconds: 1),
    );

    rig.advanceTo(DateTime(2026, 12, 18, 0, 0, 1));
    await Future<void>.delayed(Duration.zero);
    expect(rig.layers.holidayActive, isTrue);
    expect(rig.layers.holiday, xmasHolidayTheme);
    expect(rig.icons.last, 'setIconVariant:xmas');
    expect(rig.controller.nextCheck, DateTime(2027, 1, 3));

    rig.advanceTo(DateTime(2027, 1, 3, 0, 0, 1));
    await Future<void>.delayed(Duration.zero);
    expect(rig.layers.holidayActive, isFalse);
    expect(rig.icons.last, 'setIconVariant:default');
    // 圣诞过完，下一个变化点是明年的万圣节。
    expect(rig.controller.nextCheck, DateTime(2027, 10, 24));
    // 图标只在变化时发一次，不会反复发。
    expect(rig.icons, ['setIconVariant:xmas', 'setIconVariant:default']);
  });

  test('节日期间关掉开关：立刻改回平时；再打开：立刻换上', () async {
    final rig = _Rig(DateTime(2026, 12, 24, 20));
    addTearDown(rig.dispose);
    expect(rig.layers.holidayActive, isTrue);
    expect(rig.icons, ['setIconVariant:xmas']);

    await rig.preferences.setHolidayAppearance(false);
    await Future<void>.delayed(Duration.zero);
    expect(rig.layers.holidayActive, isFalse);
    expect(rig.layers.holiday, xmasHolidayTheme, reason: '日历没变，只是关了');
    expect(rig.icons.last, 'setIconVariant:default');

    await rig.preferences.setHolidayAppearance(true);
    await Future<void>.delayed(Duration.zero);
    expect(rig.layers.holidayActive, isTrue);
    expect(rig.icons.last, 'setIconVariant:xmas');
  });

  test('一开始就关着：节日期间也是平时，图标是默认', () {
    final rig = _Rig(DateTime(2026, 12, 25), enabled: false);
    addTearDown(rig.dispose);
    expect(rig.layers.holidayActive, isFalse);
    expect(rig.icons, isEmpty);
  });

  test('用户背景图进来：节日照常，只是页面底色不印花', () {
    final rig = _Rig(DateTime(2026, 12, 25));
    addTearDown(rig.dispose);
    rig.controller.setUserBackground(const UserBackgroundImage(path: 'a.jpg'));
    expect(rig.layers.userBackground, isNotNull);
    expect(rig.layers.holidayActive, isTrue);
    rig.controller.setUserBackground(null);
    expect(rig.layers.userBackground, isNull);
  });

  test('睡眠唤醒后 wake 会重新判断', () {
    final rig = _Rig(DateTime(2026, 12, 17));
    addTearDown(rig.dispose);
    rig.now = DateTime(2026, 12, 20);
    rig.controller.wake();
    expect(rig.layers.holidayActive, isTrue);
  });

  test('销毁后不再响应', () async {
    final rig = _Rig(DateTime(2026, 12, 17));
    rig.controller.dispose();
    rig.advanceTo(DateTime(2026, 12, 20));
    await rig.preferences.setHolidayAppearance(false);
    expect(rig.icons, isEmpty);
    rig.preferences.dispose();
  });
}
