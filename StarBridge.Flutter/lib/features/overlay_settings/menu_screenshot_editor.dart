import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'overlay_settings_help.dart';
import '../../platform/window/menu_screenshot_preferences.dart';

class MenuScreenshotEditor extends StatelessWidget {
  const MenuScreenshotEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.showTitle = true,
  });
  final MenuScreenshotPreferences value;
  final bool showTitle;
  final ValueChanged<MenuScreenshotPreferences> onChanged;
  @override
  Widget build(BuildContext context) {
    String text(String key) =>
        AppStrings.of(context).text('menu.screenshot.$key');
    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle)
            Text(text('title'), style: Theme.of(context).textTheme.titleLarge),
          OverlaySettingsHelp(text('hint')),
          SwitchListTile(
            key: const Key('menu-screenshot-hide-menu'),
            contentPadding: EdgeInsets.zero,
            title: Text(text('hideMenu')),
            subtitle: OverlaySettingsHelp(text('hideMenuHint')),
            value: value.hideMenu,
            onChanged: (v) => onChanged(value.change('hideMenu', v)),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('menu-screenshot-format-${value.format}'),
            initialValue: value.format,
            isExpanded: true,
            decoration: InputDecoration(labelText: text('format')),
            items: [
              for (final format in const ['png', 'jpeg'])
                DropdownMenuItem(value: format, child: Text(text(format))),
            ],
            onChanged: (v) {
              if (v != null) onChanged(value.change('format', v));
            },
          ),
          OverlaySettingsHelp(text('formatHint')),
          if (value.format == 'jpeg') ...[
            const SizedBox(height: 12),
            Text('${text('quality')} ${value.jpegQuality}%'),
            Slider(
              key: const Key('menu-screenshot-quality'),
              value: value.jpegQuality.toDouble(),
              min: 50,
              max: 100,
              divisions: 50,
              label: '${value.jpegQuality}%',
              onChanged: (v) =>
                  onChanged(value.change('jpegQuality', v.round())),
            ),
          ],
          SwitchListTile(
            key: const Key('menu-screenshot-copy'),
            contentPadding: EdgeInsets.zero,
            title: Text(text('copy')),
            subtitle: OverlaySettingsHelp(text('copyHint')),
            value: value.copyAfterSave,
            onChanged: (v) => onChanged(value.change('copyAfterSave', v)),
          ),
          SwitchListTile(
            key: const Key('menu-screenshot-confirmation'),
            contentPadding: EdgeInsets.zero,
            title: Text(text('confirmation')),
            subtitle: OverlaySettingsHelp(text('confirmationHint')),
            value: value.showConfirmation,
            onChanged: (v) => onChanged(value.change('showConfirmation', v)),
          ),
          OverlaySettingsHelp(text('privacy')),
        ],
      ),
    );
  }
}
