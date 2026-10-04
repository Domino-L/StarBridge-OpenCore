import 'package:flutter/material.dart';

import '../../platform/window/menu_display_preferences.dart';
import '../../platform/window/menu_window_preferences.dart';
import 'menu_display_editor.dart';
import 'menu_preferences_settings_card.dart';

class MenuDisplaySettingsCard extends StatelessWidget {
  const MenuDisplaySettingsCard({super.key, required this.port});
  final MenuWindowPreferencesPort port;
  @override
  Widget build(BuildContext context) =>
      MenuPreferencesSettingsCard<MenuDisplayPreferences>(
        port: port,
        section: 'display',
        read: (settings) => MenuDisplayPreferences.fromSettings(settings)!,
        patch: (value) => value.toSettingsPatch(),
        editor: (value, onChanged) =>
            MenuDisplayEditor(value: value, onChanged: onChanged),
      );
}
