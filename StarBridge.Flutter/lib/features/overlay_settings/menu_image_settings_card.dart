import 'package:flutter/material.dart';

import '../../platform/window/menu_image_preferences.dart';
import '../../platform/window/menu_window_preferences.dart';
import 'menu_image_editor.dart';
import 'menu_preferences_settings_card.dart';

class MenuImageSettingsCard extends StatelessWidget {
  const MenuImageSettingsCard({super.key, required this.port});
  final MenuWindowPreferencesPort port;
  @override
  Widget build(BuildContext context) =>
      MenuPreferencesSettingsCard<MenuImagePreferences>(
        port: port,
        section: 'image',
        read: (settings) => MenuImagePreferences.fromSettings(settings)!,
        patch: (value) => value.toSettingsPatch(),
        editor: (value, onChanged) =>
            MenuImageEditor(value: value, onChanged: onChanged),
      );
}
