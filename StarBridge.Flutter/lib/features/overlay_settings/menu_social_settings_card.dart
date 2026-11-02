import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/interaction/starbridge_select_field.dart';

import '../../app/localization/app_strings.dart';
import 'overlay_settings_help.dart';
import '../../platform/window/menu_social_preferences.dart';
import '../../platform/window/menu_window_preferences.dart';
import 'menu_preferences_settings_card.dart';

class MenuSocialSettingsCard extends StatelessWidget {
  const MenuSocialSettingsCard({super.key, required this.port});
  final MenuWindowPreferencesPort port;
  @override
  Widget build(BuildContext context) =>
      MenuPreferencesSettingsCard<MenuSocialPreferences>(
        port: port,
        section: 'social',
        read: (settings) => MenuSocialPreferences.fromSettings(settings)!,
        patch: (value) => value.toSettingsPatch(),
        editor: (value, onChanged, enabled) => MenuSocialEditor(
          value: value,
          onChanged: onChanged,
          enabled: enabled,
        ),
      );
}

class MenuSocialEditor extends StatelessWidget {
  const MenuSocialEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.showTitle = true,
  });
  final MenuSocialPreferences value;
  final bool showTitle;
  final bool enabled;
  final ValueChanged<MenuSocialPreferences> onChanged;
  @override
  Widget build(BuildContext context) {
    String text(String key) => AppStrings.of(context).text('menu.social.$key');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle)
          Text(text('title'), style: Theme.of(context).textTheme.titleLarge),
        OverlaySettingsHelp(text('hint')),
        const SizedBox(height: 12),
        StarBridgeSelectField<String>(
          key: ValueKey('menu-social-sort'),
          identity: 'menu-social-sort',
          value: value.friendSort,
          decoration: InputDecoration(labelText: text('friendSort')),
          options: [
            for (final id in MenuSocialPreferences.sorts)
              StarBridgeSelectOption(value: id, label: text(id)),
          ],
          onSelected: !enabled
              ? null
              : (v, _) {
                  onChanged(value.copyWith(friendSort: v));
                },
        ),
        Material(
          type: MaterialType.transparency,
          child: StarBridgeSwitch.tile(
            key: const Key('menu-social-notifications'),
            label: text('notifications'),
            value: value.notifications,
            onChanged: !enabled
                ? null
                : (v) => onChanged(value.copyWith(notifications: v)),
          ),
        ),
        StarBridgeSelectField<String>(
          key: ValueKey('menu-social-preview'),
          identity: 'menu-social-preview',
          value: value.preview,
          decoration: InputDecoration(labelText: text('preview')),
          options: [
            for (final id in MenuSocialPreferences.previews)
              StarBridgeSelectOption(value: id, label: text(id)),
          ],
          onSelected: !enabled
              ? null
              : value.notifications
              ? (v, _) {
                  onChanged(value.copyWith(preview: v));
                }
              : null,
        ),
        OverlaySettingsHelp(text('privacyHint')),
        Material(
          type: MaterialType.transparency,
          child: StarBridgeSwitch.tile(
            key: const Key('menu-social-sound'),
            label: text('sound'),
            value: value.sound,
            onChanged: !enabled
                ? null
                : value.notifications
                ? (v) => onChanged(value.copyWith(sound: v))
                : null,
          ),
        ),
        OverlaySettingsHelp(text('soundHint')),
        Material(
          type: MaterialType.transparency,
          child: StarBridgeSwitch.tile(
            label: text('showAvatars'),
            key: const ValueKey('menu-social-avatars'),
            value: value.showAvatars,
            onChanged: !enabled
                ? null
                : (v) => onChanged(value.copyWith(showAvatars: v)),
          ),
        ),
        OverlaySettingsHelp(text('avatarHint')),
      ],
    );
  }
}
