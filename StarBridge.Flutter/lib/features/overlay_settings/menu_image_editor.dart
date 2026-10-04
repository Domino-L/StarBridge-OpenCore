import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'overlay_settings_help.dart';
import '../../platform/window/menu_image_preferences.dart';

class MenuImageEditor extends StatelessWidget {
  const MenuImageEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.showTitle = true,
  });
  final MenuImagePreferences value;
  final bool showTitle;
  final ValueChanged<MenuImagePreferences> onChanged;
  @override
  Widget build(BuildContext context) {
    String text(String key) => AppStrings.of(context).text('menu.image.$key');
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
            key: ValueKey('menu-image-open-${value.openMode}'),
            initialValue: value.openMode,
            isExpanded: true,
            decoration: InputDecoration(labelText: text('openMode')),
            items: [
              for (final mode in const ['edit', 'imageOnly'])
                DropdownMenuItem(value: mode, child: Text(text(mode))),
            ],
            onChanged: (v) {
              if (v != null) onChanged(value.change('openMode', v));
            },
          ),
          OverlaySettingsHelp(text('modeHint')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('menu-image-scale-${value.scaleMode}'),
            initialValue: value.scaleMode,
            isExpanded: true,
            decoration: InputDecoration(labelText: text('scaleMode')),
            items: [
              for (final mode in const ['fit', 'actualSize'])
                DropdownMenuItem(value: mode, child: Text(text(mode))),
            ],
            onChanged: (v) {
              if (v != null) onChanged(value.change('scaleMode', v));
            },
          ),
          OverlaySettingsHelp(text('actualHint')),
          const SizedBox(height: 12),
          Text('${text('opacity')} ${value.opacityPercent}%'),
          Slider(
            key: const Key('menu-image-default-opacity'),
            value: value.opacityPercent.toDouble(),
            min: 20,
            max: 100,
            divisions: 80,
            label: '${value.opacityPercent}%',
            onChanged: (v) =>
                onChanged(value.change('opacityPercent', v.round())),
          ),
          OverlaySettingsHelp(text('privacy')),
          SwitchListTile(
            key: const Key('menu-image-remember'),
            contentPadding: EdgeInsets.zero,
            title: Text(text('remember')),
            subtitle: OverlaySettingsHelp(text('rememberHint')),
            value: value.rememberAdjustments,
            onChanged: (v) => onChanged(value.change('rememberAdjustments', v)),
          ),
          SwitchListTile(
            key: const Key('menu-image-pinned'),
            contentPadding: EdgeInsets.zero,
            title: Text(text('pinned')),
            subtitle: OverlaySettingsHelp(text('pinnedHint')),
            value: value.defaultPinned,
            onChanged: (v) => onChanged(value.change('defaultPinned', v)),
          ),
        ],
      ),
    );
  }
}
