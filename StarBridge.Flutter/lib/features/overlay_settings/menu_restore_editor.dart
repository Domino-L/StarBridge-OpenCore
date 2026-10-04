import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'overlay_settings_help.dart';
import '../../platform/window/menu_restore_preferences.dart';

/// Shared editor for the primary settings page and the in-game menu.
class MenuRestoreEditor extends StatelessWidget {
  const MenuRestoreEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.showTitle = true,
  });
  final MenuRestorePreferences value;
  final bool showTitle;
  final ValueChanged<MenuRestorePreferences> onChanged;
  @override
  Widget build(BuildContext context) {
    String text(String key) => AppStrings.of(context).text('menu.restore.$key');
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle)
            Text(text('title'), style: Theme.of(context).textTheme.titleLarge),
          SwitchListTile(
            key: const Key('menu-restore-session'),
            contentPadding: EdgeInsets.zero,
            title: Text(text('session')),
            subtitle: OverlaySettingsHelp(text('sessionHint')),
            value: value.inSession,
            onChanged: (v) => onChanged(value.change(inSession: v)),
          ),
          SwitchListTile(
            key: const Key('menu-restore-restart'),
            contentPadding: EdgeInsets.zero,
            title: Text(text('restart')),
            subtitle: OverlaySettingsHelp(text('restartHint')),
            value: value.afterRestart,
            onChanged: (v) => onChanged(value.change(afterRestart: v)),
          ),
          SwitchListTile(
            key: const Key('menu-restore-last-focus'),
            contentPadding: EdgeInsets.zero,
            title: Text(text('focus')),
            subtitle: OverlaySettingsHelp(text('focusHint')),
            value: value.lastFocus,
            onChanged: (v) => onChanged(value.change(lastFocus: v)),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('menu-restore-crash-${value.crashRecovery}'),
            initialValue: value.crashRecovery,
            isExpanded: true,
            decoration: InputDecoration(labelText: text('crash')),
            items: [
              for (final id in MenuRestorePreferences.recoveryModes)
                DropdownMenuItem(value: id, child: Text(text(id))),
            ],
            onChanged: (v) {
              if (v != null) onChanged(value.change(crashRecovery: v));
            },
          ),
          const SizedBox(height: 8),
          OverlaySettingsHelp(text('crashHint')),
          SwitchListTile(
            key: const Key('menu-safe-next-launch'),
            contentPadding: EdgeInsets.zero,
            title: Text(text('safeNext')),
            subtitle: OverlaySettingsHelp(text('safeHint')),
            value: value.safeModeNextLaunch,
            onChanged: (v) => onChanged(value.change(safeModeNextLaunch: v)),
          ),
          const SizedBox(height: 12),
          OverlaySettingsHelp(text('privacy')),
        ],
      ),
    );
  }
}
