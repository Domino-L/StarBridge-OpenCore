import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'overlay_settings_help.dart';
import '../../platform/window/menu_display_preferences.dart';

class MenuDisplayEditor extends StatelessWidget {
  const MenuDisplayEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.showTitle = true,
  });
  final MenuDisplayPreferences value;
  final bool showTitle;
  final ValueChanged<MenuDisplayPreferences> onChanged;
  @override
  Widget build(BuildContext context) {
    String text(String key) => AppStrings.of(context).text('menu.display.$key');
    Widget flag(String key, bool enabled, {bool active = true}) =>
        SwitchListTile(
          key: ValueKey('menu-display-$key'),
          contentPadding: EdgeInsets.zero,
          title: Text(text(key)),
          value: enabled,
          onChanged: active ? (v) => onChanged(value.change(key, v)) : null,
        );
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle)
            Text(text('title'), style: Theme.of(context).textTheme.titleLarge),
          OverlaySettingsHelp(text('hint')),
          const SizedBox(height: 12),
          Text(
            text('appearance'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: ValueKey(
              'menu-display-interfaceScale-${value.interfaceScalePercent}',
            ),
            initialValue: value.interfaceScalePercent,
            isExpanded: true,
            decoration: InputDecoration(labelText: text('interfaceScale')),
            items: [
              for (final percent in MenuDisplayPreferences.interfaceScales)
                DropdownMenuItem(
                  value: percent,
                  child: Text(percent == 0 ? text('system') : '$percent%'),
                ),
            ],
            onChanged: (percent) {
              if (percent != null) {
                onChanged(value.change('interfaceScalePercent', percent));
              }
            },
          ),
          OverlaySettingsHelp(text('interfaceScaleHint')),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: ValueKey('menu-display-textScale-${value.textScalePercent}'),
            initialValue: value.textScalePercent,
            isExpanded: true,
            decoration: InputDecoration(labelText: text('textScale')),
            items: [
              for (final percent in MenuDisplayPreferences.textScales)
                DropdownMenuItem(value: percent, child: Text('$percent%')),
            ],
            onChanged: (percent) {
              if (percent != null) {
                onChanged(value.change('textScalePercent', percent));
              }
            },
          ),
          OverlaySettingsHelp(text('textScaleHint')),
          flag('reduceMotion', value.reduceMotion),
          OverlaySettingsHelp(text('reduceMotionHint')),
          flag('highContrast', value.highContrast),
          OverlaySettingsHelp(text('highContrastHint')),
          const SizedBox(height: 12),
          Text('${text('tooltipDelay')} ${value.tooltipDelayMilliseconds} ms'),
          Slider(
            key: const ValueKey('menu-display-tooltipDelay'),
            value: value.tooltipDelayMilliseconds.toDouble(),
            min: 100,
            max: 1500,
            divisions: 14,
            label: '${value.tooltipDelayMilliseconds} ms',
            onChanged: (delay) => onChanged(
              value.change('tooltipDelayMilliseconds', delay.round()),
            ),
          ),
          OverlaySettingsHelp(text('tooltipDelayHint')),
          const SizedBox(height: 12),
          Text(text('time'), style: Theme.of(context).textTheme.titleSmall),
          flag('showClock', value.showClock),
          flag('showDate', value.showDate),
          DropdownButtonFormField<String>(
            key: ValueKey('menu-display-format-${value.clockFormat}'),
            initialValue: value.clockFormat,
            isExpanded: true,
            decoration: InputDecoration(labelText: text('clockFormat')),
            items: [
              for (final id in const ['system', 'twentyFourHour', 'twelveHour'])
                DropdownMenuItem(value: id, child: Text(text(id))),
            ],
            onChanged: value.showClock
                ? (v) {
                    if (v != null) onChanged(value.change('clockFormat', v));
                  }
                : null,
          ),
          flag('showPresence', value.showPresence),
          const SizedBox(height: 16),
          Text(text('context'), style: Theme.of(context).textTheme.titleSmall),
          flag('showContext', value.showContext),
          flag('showScene', value.showScene, active: value.showContext),
          flag('showMembers', value.showMembers, active: value.showContext),
          flag('showShip', value.showShip, active: value.showContext),
          flag('showLocation', value.showLocation, active: value.showContext),
          flag('showServer', value.showServer, active: value.showContext),
          const SizedBox(height: 16),
          Text(text('privacy'), style: Theme.of(context).textTheme.titleSmall),
          flag('streamerPrivacy', value.streamerPrivacy),
          OverlaySettingsHelp(text('privacyHint')),
          flag(
            'showRoomCode',
            value.showRoomCode,
            active: !value.streamerPrivacy,
          ),
        ],
      ),
    );
  }
}
