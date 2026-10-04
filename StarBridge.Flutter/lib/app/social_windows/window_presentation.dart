import 'package:flutter/material.dart';

import '../../design_system/style_registry.dart';
import '../../design_system/theme/theme_builder.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../preferences/app_preferences.dart';

/// Only presentation preferences cross the engine boundary, never account data.
Map<String, Object?> encodeWindowPresentation(AppPreferences preferences) => {
  'appearanceMode': preferences.appearanceMode.name,
  'designStyleId': preferences.designStyleId,
  'locale': preferences.locale.toLanguageTag(),
  'reduceMotion': preferences.motionPreference == MotionPreference.reduce,
};

class WindowPresentation {
  const WindowPresentation([this.values = const {}]);
  factory WindowPresentation.decode(Object? value) =>
      WindowPresentation(value is Map ? value : const {});
  final Map values;
  Locale get locale => switch (values['locale']) {
    'en-US' || 'en' => const Locale('en', 'US'),
    'zh-TW' => const Locale('zh', 'TW'),
    _ => const Locale('zh', 'CN'),
  };
  StarBridgeTokens get tokens => StyleRegistry()
      .resolve(
        values['designStyleId'] is String
            ? values['designStyleId'] as String
            : AppPreferences.defaults.designStyleId,
        values['appearanceMode'] == 'light'
            ? AppearanceMode.light
            : AppearanceMode.dark,
      )
      .tokens
      .withReducedMotion(values['reduceMotion'] == true);
  ThemeData get theme => buildStarBridgeTheme(tokens, locale);
}
