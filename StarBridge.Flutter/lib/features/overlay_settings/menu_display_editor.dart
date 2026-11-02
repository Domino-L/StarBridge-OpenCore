import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/interaction/starbridge_select_field.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';

import '../../app/localization/app_strings.dart';
import 'overlay_settings_help.dart';
import '../../platform/window/menu_display_preferences.dart';
import '../../platform/window/menu_desktop_widgets.dart';
import 'menu_desktop_widgets_editor.dart';

class MenuDisplayEditor extends StatelessWidget {
  const MenuDisplayEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.showTitle = true,
    this.widgets = const MenuDesktopWidgets(),
    this.onWidgetsChanged,
  });
  final MenuDisplayPreferences value;
  final bool showTitle;
  final MenuDesktopWidgets widgets;
  final bool enabled;
  final ValueChanged<MenuDesktopWidgets>? onWidgetsChanged;
  final ValueChanged<MenuDisplayPreferences> onChanged;
  @override
  Widget build(BuildContext context) {
    String text(String key) => AppStrings.of(context).text('menu.display.$key');
    Widget flag(String key, bool selectedValue, {bool active = true}) =>
        StarBridgeSwitch.tile(
          key: ValueKey('menu-display-$key'),
          label: text(key),
          value: selectedValue,
          onChanged: !enabled
              ? null
              : enabled && active
              ? (v) => onChanged(value.change(key, v))
              : null,
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
          StarBridgeSelectField<int>(
            key: ValueKey('menu-display-interfaceScale'),
            identity: 'menu-display-interfaceScale',
            value: value.interfaceScalePercent,
            decoration: InputDecoration(labelText: text('interfaceScale')),
            options: [
              for (final percent in MenuDisplayPreferences.interfaceScales)
                StarBridgeSelectOption(
                  value: percent,
                  label: percent == 0 ? text('system') : '$percent%',
                ),
            ],
            onSelected: !enabled
                ? null
                : (percent, _) {
                    onChanged(value.change('interfaceScalePercent', percent));
                  },
          ),
          OverlaySettingsHelp(text('interfaceScaleHint')),
          const SizedBox(height: 12),
          StarBridgeSelectField<int>(
            key: ValueKey('menu-display-textScale'),
            identity: 'menu-display-textScale',
            value: value.textScalePercent,
            decoration: InputDecoration(labelText: text('textScale')),
            options: [
              for (final percent in MenuDisplayPreferences.textScales)
                StarBridgeSelectOption(value: percent, label: '$percent%'),
            ],
            onSelected: !enabled
                ? null
                : (percent, _) {
                    onChanged(value.change('textScalePercent', percent));
                  },
          ),
          OverlaySettingsHelp(text('textScaleHint')),
          flag('reduceMotion', value.reduceMotion),
          OverlaySettingsHelp(text('reduceMotionHint')),
          flag('highContrast', value.highContrast),
          OverlaySettingsHelp(text('highContrastHint')),
          const SizedBox(height: 12),
          Text('${text('tooltipDelay')} ${value.tooltipDelayMilliseconds} ms'),
          StarBridgeFieldFrame(
            enabled: enabled,
            cursor: SystemMouseCursors.click,
            builder: (_, focus) => KeyedSubtree(
              // Preserve the existing client workaround: SDK Slider owns an
              // OverlayPortal whose semantics cache must not cross enabled.
              key: ValueKey(('menu-display-slider', enabled)),
              child: Slider(
                focusNode: focus,
                key: const ValueKey('menu-display-tooltipDelay'),
                value: value.tooltipDelayMilliseconds.toDouble(),
                min: 100,
                max: 1500,
                divisions: 14,
                label: '${value.tooltipDelayMilliseconds} ms',
                onChanged: !enabled
                    ? null
                    : (delay) => onChanged(
                        value.change('tooltipDelayMilliseconds', delay.round()),
                      ),
              ),
            ),
          ),
          OverlaySettingsHelp(text('tooltipDelayHint')),
          const SizedBox(height: 12),
          Text(text('time'), style: Theme.of(context).textTheme.titleSmall),
          flag('showClock', value.showClock),
          flag('showDate', value.showDate),
          StarBridgeSelectField<String>(
            key: ValueKey('menu-display-format'),
            identity: 'menu-display-format',
            value: value.clockFormat,
            decoration: InputDecoration(labelText: text('clockFormat')),
            options: [
              for (final id in const ['system', 'twentyFourHour', 'twelveHour'])
                StarBridgeSelectOption(value: id, label: text(id)),
            ],
            onSelected: !enabled
                ? null
                : value.showClock
                ? (v, _) {
                    onChanged(value.change('clockFormat', v));
                  }
                : null,
          ),
          flag('showPresence', value.showPresence),
          if (onWidgetsChanged case final change?) ...[
            const SizedBox(height: 16),
            MenuDesktopWidgetsEditor(
              value: widgets,
              onChanged: change,
              enabled: enabled,
            ),
          ],
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
