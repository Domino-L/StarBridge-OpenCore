import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'overlay_settings_help.dart';
import '../../platform/window/menu_browser_preferences.dart';

class MenuBrowserEditor extends StatelessWidget {
  const MenuBrowserEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.showTitle = true,
  });
  final MenuBrowserPreferences value;
  final bool showTitle;
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
          DropdownButtonFormField<String>(
            key: ValueKey('menu-browser-provider-${value.provider}'),
            initialValue: value.provider,
            isExpanded: true,
            decoration: InputDecoration(labelText: text('provider')),
            items: [
              for (final id in MenuBrowserPreferences.providers)
                DropdownMenuItem(value: id, child: Text(text(id))),
            ],
            onChanged: (v) {
              if (v != null) onChanged(value.change('provider', v));
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: ValueKey('menu-browser-limit-${value.tabLimit}'),
            initialValue: value.tabLimit,
            isExpanded: true,
            decoration: InputDecoration(labelText: text('tabLimit')),
            items: [
              for (var count = 1; count <= 12; count++)
                DropdownMenuItem(value: count, child: Text('$count')),
            ],
            onChanged: (v) {
              if (v != null) onChanged(value.change('tabLimit', v));
            },
          ),
          OverlaySettingsHelp(text('limitHint')),
          SwitchListTile(
            key: const Key('menu-browser-links'),
            contentPadding: EdgeInsets.zero,
            title: Text(text('links')),
            subtitle: OverlaySettingsHelp(text('linksHint')),
            value: value.openLinksInNewTab,
            onChanged: (v) => onChanged(value.change('openLinksInNewTab', v)),
          ),
          SwitchListTile(
            key: const Key('menu-browser-pause'),
            contentPadding: EdgeInsets.zero,
            title: Text(text('pause')),
            subtitle: OverlaySettingsHelp(text('pauseHint')),
            value: value.pauseWhenHidden,
            onChanged: (v) => onChanged(value.change('pauseWhenHidden', v)),
          ),
          OverlaySettingsHelp(text('privacy')),
        ],
      ),
    );
  }
}
