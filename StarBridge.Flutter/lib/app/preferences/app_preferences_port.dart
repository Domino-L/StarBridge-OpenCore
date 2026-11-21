import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../design_system/tokens/color_tokens.dart';
import 'app_preferences.dart';
import 'app_preferences_projection.dart';

abstract interface class AppPreferencesPort {
  ValueListenable<AppPreferencesProjection> get projection;

  Future<bool> setLocale(Locale locale);

  Future<bool> setAppearanceMode(AppearanceMode mode);

  Future<bool> setMotionPreference(MotionPreference preference);

  Future<bool> setInteractionStyle(InteractionStyle style);

  Future<bool> setApplicationBehavior(ApplicationBehaviorPreferences behavior);

  Future<bool> setHolidayAppearance(bool enabled);

  Future<bool> setPerformanceMode(bool enabled);

  /// 读取自己的血量（默认关）。
  Future<bool> setReadOwnHealth(bool enabled);

  /// 游戏在后台时也读取（读血的子开关，默认关）。
  Future<bool> setReadOwnHealthInBackground(bool enabled);

  Future<bool> retry();

  void dispose();
}
