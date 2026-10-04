import 'package:flutter/material.dart';

import '../../platform/window/menu_screenshot_preferences.dart';
import '../../platform/window/menu_window_preferences.dart';
import 'menu_screenshot_editor.dart';
import 'menu_preferences_settings_card.dart';

class MenuScreenshotSettingsCard extends StatelessWidget {
  const MenuScreenshotSettingsCard({super.key, required this.port});
  final MenuWindowPreferencesPort port;
  @override
  Widget build(BuildContext context) =>
      MenuPreferencesSettingsCard<MenuScreenshotPreferences>(
        port: port,
        section: 'screenshot',
        read: (settings) => MenuScreenshotPreferences.fromSettings(settings)!,
        patch: (value) => value.toSettingsPatch(),
        editor: (value, onChanged) =>
            MenuScreenshotEditor(value: value, onChanged: onChanged),
      );
}
