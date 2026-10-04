import 'package:flutter/material.dart';

import '../../platform/window/menu_restore_preferences.dart';
import '../../platform/window/menu_window_preferences.dart';
import 'menu_preferences_settings_card.dart';
import 'menu_restore_editor.dart';

class MenuRestoreSettingsCard extends StatelessWidget {
  const MenuRestoreSettingsCard({super.key, required this.port});
  final MenuWindowPreferencesPort port;
  @override
  Widget build(BuildContext context) =>
      MenuPreferencesSettingsCard<MenuRestorePreferences>(
        port: port,
        section: 'restore',
        read: (settings) => MenuRestorePreferences.fromSettings(settings)!,
        patch: (value) => value.toSettingsPatch(),
        editor: (value, onChanged) =>
            MenuRestoreEditor(value: value, onChanged: onChanged),
      );
}
