import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/interaction/starbridge_select_field.dart';

import '../../app/localization/app_strings.dart';
import 'overlay_settings_help.dart';
import '../../platform/window/menu_browser_preferences.dart';

class MenuBrowserEditor extends StatelessWidget {
  const MenuBrowserEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.showTitle = true,
  });
  final MenuBrowserPreferences value;
  final bool showTitle;
  final bool enabled;
  final ValueChanged<MenuBrowserPreferences> onChanged;
  @override
  Widget build(BuildContext context) {
    String text(String key) => AppStrings.of(context).text('menu.browser.$key');
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle)
            Text(text('title'), style: Theme.of(context).textTheme.titleLarge),
          OverlaySettingsHelp(text('hint')),
          const SizedBox(height: 12),
          StarBridgeSelectField<String>(
            key: ValueKey('menu-browser-provider'),
            identity: 'menu-browser-provider',
            value: value.provider,
            decoration: InputDecoration(labelText: text('provider')),
            options: [
              for (final id in MenuBrowserPreferences.providers)
                StarBridgeSelectOption(value: id, label: text(id)),
            ],
            onSelected: !enabled
                ? null
                : (v, _) {
                    onChanged(value.change('provider', v));
                  },
          ),
          const SizedBox(height: 12),
          StarBridgeSelectField<int>(
            key: ValueKey('menu-browser-limit'),
            identity: 'menu-browser-limit',
            value: value.tabLimit,
            decoration: InputDecoration(labelText: text('tabLimit')),
            options: [
              for (var count = 1; count <= 12; count++)
                StarBridgeSelectOption(value: count, label: '$count'),
            ],
            onSelected: !enabled
                ? null
                : (v, _) {
                    onChanged(value.change('tabLimit', v));
                  },
          ),
          OverlaySettingsHelp(text('limitHint')),
          StarBridgeSwitch.tile(
            key: const Key('menu-browser-links'),
            label: text('links'),
            subtitle: text('linksHint'),
            subtitleWidget: OverlaySettingsHelp(text('linksHint')),
            value: value.openLinksInNewTab,
            onChanged: !enabled
                ? null
                : (v) => onChanged(value.change('openLinksInNewTab', v)),
          ),
          StarBridgeSwitch.tile(
            key: const Key('menu-browser-pause'),
            label: text('pause'),
            subtitle: text('pauseHint'),
            subtitleWidget: OverlaySettingsHelp(text('pauseHint')),
            value: value.pauseWhenHidden,
            onChanged: !enabled
                ? null
                : (v) => onChanged(value.change('pauseWhenHidden', v)),
          ),
          OverlaySettingsHelp(text('privacy')),
        ],
      ),
    );
  }
}
