import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../design_system/appearance/appearance_layers.dart';
import '../../design_system/appearance/holiday_calendar.dart';
import '../../design_system/appearance/holiday_theme.dart';
import '../../design_system/appearance/user_background.dart';
import '../../platform/window/window_chrome_port.dart';
import '../preferences/app_preferences_projection.dart';

/// 决定现在该用哪套外观，并在日期到了或过了的时候自动换。
///
/// 输入：节日日历、本地时间、设置里的"节日外观"开关、用户背景图。
/// 输出：[layers]，外壳和主题都从它读。图标跟着一起换给窗口、任务栏、托盘。
final class HolidayAppearanceController {
  HolidayAppearanceController({
    required this._calendar,
    required this._preferences,
    this._windowChrome,
    DateTime Function()? now,
    this._schedule,
  }) : _now = now ?? DateTime.now {
    _preferences.addListener(_refresh);
    _refresh();
  }

  final HolidayCalendar _calendar;
  final ValueListenable<AppPreferencesProjection> _preferences;
  final WindowChromePort? _windowChrome;
  final DateTime Function() _now;
  final void Function(Duration delay, void Function() wake)? _schedule;
  final _layers = ValueNotifier<AppearanceLayers>(AppearanceLayers.standard);
  UserBackgroundImage? _userBackground;
  HolidayTheme? _preview;
  Timer? _timer;
  Timer? _clockWatch;
  DateTime? _lastSeenDate;
  // 运行时起来就是默认图标，所以第一次是默认时不用发。
  String _appliedIcon = defaultIconVariant;
  bool _disposed = false;

  ValueListenable<AppearanceLayers> get layers => _layers;

  /// 下一次自动重新判断的时间（本地）。测试用。
  DateTime? nextCheck;

  /// 用户设了或清掉了背景图。这一版没有设置界面，由以后的设置页调用。
  void setUserBackground(UserBackgroundImage? image) {
    if (_userBackground == image) return;
    _userBackground = image;
    _refresh();
  }

  /// 时间可能变了（睡眠唤醒、改了系统时间），重新判断一次。
  void wake() => _refresh();

  /// 调试用（STARBRIDGE_HOLIDAY_PREVIEW）：预览某个节日，不看日期、也不看开关；
  /// 只在本次运行有效，不写设置。界面上没有入口。
  /// 传 null 结束预览。不认识的 id 当作结束预览。
  void previewHoliday(String? id) {
    HolidayTheme? next;
    for (final theme in _calendar.themes) {
      if (theme.id == id) next = theme;
    }
    if (_preview == next) return;
    _preview = next;
    _refresh();
  }

  void _refresh() {
    if (_disposed) return;
    final now = _now();
    final enabled = _preferences.value.effective.holidayAppearance;
    final preview = _preview;
    final next = AppearanceLayers(
      holiday: preview ?? _calendar.activeOn(now),
      holidayEnabled: enabled,
      previewing: preview != null,
      userBackground: _userBackground,
    );
    _lastSeenDate = DateTime(now.year, now.month, now.day);
    if (next != _layers.value) _layers.value = next;
    _applyIcon(next.iconVariant);
    _arm(now);
  }

  void _applyIcon(String variant) {
    if (_appliedIcon == variant) return;
    _appliedIcon = variant;
    final chrome = _windowChrome;
    if (chrome != null) unawaited(chrome.setIconVariant(variant));
  }

  void _arm(DateTime now) {
    _timer?.cancel();
    final boundary = _calendar.nextChangeAfter(now);
    nextCheck = boundary;
    // 多等一秒，免得定时器在零点前一瞬醒来又算成昨天。
    var delay = boundary.difference(now) + const Duration(seconds: 1);
    if (delay.isNegative) delay = const Duration(seconds: 1);
    final schedule = _schedule;
    if (schedule != null) {
      schedule(delay, _refresh);
    } else {
      _timer = Timer(delay, _refresh);
      // 改了系统日期或时区时定时器算的点就不对了，每分钟看一眼日期有没有变。
      _clockWatch ??= Timer.periodic(const Duration(minutes: 1), (_) {
        final today = _now();
        if (DateTime(today.year, today.month, today.day) != _lastSeenDate) {
          _refresh();
        }
      });
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _clockWatch?.cancel();
    _preferences.removeListener(_refresh);
    _layers.dispose();
  }
}
