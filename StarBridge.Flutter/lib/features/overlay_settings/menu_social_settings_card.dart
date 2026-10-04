import 'package:flutter/material.dart';

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
        editor: (value, onChanged) =>
            MenuSocialEditor(value: value, onChanged: onChanged),
      );
}

class MenuSocialEditor extends StatelessWidget {
  const MenuSocialEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.showTitle = true,
  });
  final MenuSocialPreferences value;
  final bool showTitle;
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
        DropdownButtonFormField<String>(
          key: ValueKey('menu-social-sort-${value.friendSort}'),
          initialValue: value.friendSort,
          isExpanded: true,
          decoration: InputDecoration(labelText: text('friendSort')),
          items: [
            for (final id in MenuSocialPreferences.sorts)
              DropdownMenuItem(value: id, child: Text(text(id))),
          ],
          onChanged: (v) {
            if (v != null) onChanged(value.copyWith(friendSort: v));
          },
        ),
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(text('notifications')),
            value: value.notifications,
            onChanged: (v) => onChanged(value.copyWith(notifications: v)),
          ),
        ),
        DropdownButtonFormField<String>(
          key: ValueKey('menu-social-preview-${value.preview}'),
          initialValue: value.preview,
          isExpanded: true,
          decoration: InputDecoration(labelText: text('preview')),
          items: [
            for (final id in MenuSocialPreferences.previews)
              DropdownMenuItem(value: id, child: Text(text(id))),
          ],
          onChanged: value.notifications
              ? (v) {
                  if (v != null) onChanged(value.copyWith(preview: v));
                }
              : null,
        ),
        OverlaySettingsHelp(text('privacyHint')),
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(text('sound')),
            value: value.sound,
            onChanged: value.notifications
                ? (v) => onChanged(value.copyWith(sound: v))
                : null,
          ),
        ),
        OverlaySettingsHelp(text('soundHint')),
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(text('showAvatars')),
            key: const ValueKey('menu-social-avatars'),
            value: value.showAvatars,
            onChanged: (v) => onChanged(value.copyWith(showAvatars: v)),
          ),
        ),
        OverlaySettingsHelp(text('avatarHint')),
      ],
    );
  }
}
