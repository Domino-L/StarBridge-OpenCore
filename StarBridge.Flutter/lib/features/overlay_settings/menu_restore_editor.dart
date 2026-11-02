import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/interaction/starbridge_select_field.dart';

import '../../app/localization/app_strings.dart';
import 'overlay_settings_help.dart';
import '../../platform/window/menu_restore_preferences.dart';

/// Shared editor for the primary settings page and the in-game menu.
class MenuRestoreEditor extends StatelessWidget {
  const MenuRestoreEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.showTitle = true,
  });
  final MenuRestorePreferences value;
  final bool showTitle;
  final bool enabled;
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
          StarBridgeSwitch.tile(
            key: const Key('menu-restore-session'),
            label: text('session'),
            subtitle: text('sessionHint'),
            subtitleWidget: OverlaySettingsHelp(text('sessionHint')),
            value: value.inSession,
            onChanged: !enabled
                ? null
                : (v) => onChanged(value.change(inSession: v)),
          ),
          StarBridgeSwitch.tile(
            key: const Key('menu-restore-restart'),
            label: text('restart'),
            subtitle: text('restartHint'),
            subtitleWidget: OverlaySettingsHelp(text('restartHint')),
            value: value.afterRestart,
            onChanged: !enabled
                ? null
                : (v) => onChanged(value.change(afterRestart: v)),
          ),
          StarBridgeSwitch.tile(
            key: const Key('menu-restore-last-focus'),
            label: text('focus'),
            subtitle: text('focusHint'),
            subtitleWidget: OverlaySettingsHelp(text('focusHint')),
            value: value.lastFocus,
            onChanged: !enabled
                ? null
                : (v) => onChanged(value.change(lastFocus: v)),
          ),
          const SizedBox(height: 12),
          StarBridgeSelectField<String>(
            key: ValueKey('menu-restore-crash'),
            identity: 'menu-restore-crash',
            value: value.crashRecovery,
            decoration: InputDecoration(labelText: text('crash')),
            options: [
              for (final id in MenuRestorePreferences.recoveryModes)
                StarBridgeSelectOption(value: id, label: text(id)),
            ],
            onSelected: !enabled
                ? null
                : (v, _) {
                    onChanged(value.change(crashRecovery: v));
                  },
          ),
          const SizedBox(height: 8),
          OverlaySettingsHelp(text('crashHint')),
          StarBridgeSwitch.tile(
            key: const Key('menu-safe-next-launch'),
            label: text('safeNext'),
            subtitle: text('safeHint'),
            subtitleWidget: OverlaySettingsHelp(text('safeHint')),
            value: value.safeModeNextLaunch,
            onChanged: !enabled
                ? null
                : (v) => onChanged(value.change(safeModeNextLaunch: v)),
          ),
          const SizedBox(height: 12),
          OverlaySettingsHelp(text('privacy')),
        ],
      ),
    );
  }
}
