import 'package:flutter/material.dart';

import '../../platform/window/menu_window_preferences.dart';
import '../../platform/window/menu_toolbar_preferences.dart';
import 'menu_toolbar_editor.dart';
import 'menu_preferences_settings_card.dart';

class MenuToolbarSettingsCard extends StatelessWidget {
  const MenuToolbarSettingsCard({super.key, required this.port});
  final MenuWindowPreferencesPort port;
  @override
  Widget build(BuildContext context) =>
      MenuPreferencesSettingsCard<MenuToolbarPreferences>(
        port: port,
        section: 'toolbar',
        read: (settings) => MenuToolbarPreferences.parse(settings['toolbar'])!,
        patch: (value) => {'toolbar': value.toMap()},
        editor: (value, onChanged) =>
            MenuToolbarEditor(value: value, onChanged: onChanged),
      );
}
