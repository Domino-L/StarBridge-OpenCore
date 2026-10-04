import 'package:flutter/material.dart';

import '../../platform/window/menu_browser_preferences.dart';
import '../../platform/window/menu_window_preferences.dart';
import 'menu_browser_editor.dart';
import 'menu_preferences_settings_card.dart';

class MenuBrowserSettingsCard extends StatelessWidget {
  const MenuBrowserSettingsCard({super.key, required this.port});
  final MenuWindowPreferencesPort port;
  @override
  Widget build(BuildContext context) =>
      MenuPreferencesSettingsCard<MenuBrowserPreferences>(
        port: port,
        section: 'browser',
        read: (settings) => MenuBrowserPreferences.fromSettings(settings)!,
        patch: (value) => value.toSettingsPatch(),
        editor: (value, onChanged) =>
            MenuBrowserEditor(value: value, onChanged: onChanged),
      );
}
