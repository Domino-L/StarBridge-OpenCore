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

  Future<bool> setApplicationBehavior(ApplicationBehaviorPreferences behavior);

  Future<bool> retry();

  void dispose();
}
