import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/interaction/starbridge_select_field.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';

import '../../app/localization/app_strings.dart';
import 'overlay_settings_help.dart';
import '../../platform/window/menu_image_preferences.dart';

class MenuImageEditor extends StatelessWidget {
  const MenuImageEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.showTitle = true,
  });
  final MenuImagePreferences value;
  final bool showTitle;
  final bool enabled;
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
          StarBridgeSelectField<String>(
            key: ValueKey('menu-image-open'),
            identity: 'menu-image-open',
            value: value.openMode,
            decoration: InputDecoration(labelText: text('openMode')),
            options: [
              for (final mode in const ['edit', 'imageOnly'])
                StarBridgeSelectOption(value: mode, label: text(mode)),
            ],
            onSelected: !enabled
                ? null
                : (v, _) {
                    onChanged(value.change('openMode', v));
                  },
          ),
          OverlaySettingsHelp(text('modeHint')),
          const SizedBox(height: 12),
          StarBridgeSelectField<String>(
            key: ValueKey('menu-image-scale'),
            identity: 'menu-image-scale',
            value: value.scaleMode,
            decoration: InputDecoration(labelText: text('scaleMode')),
            options: [
              for (final mode in const ['fit', 'actualSize'])
                StarBridgeSelectOption(value: mode, label: text(mode)),
            ],
            onSelected: !enabled
                ? null
                : (v, _) {
                    onChanged(value.change('scaleMode', v));
                  },
          ),
          OverlaySettingsHelp(text('actualHint')),
          const SizedBox(height: 12),
          Text('${text('opacity')} ${value.opacityPercent}%'),
          StarBridgeFieldFrame(
            enabled: enabled,
            cursor: SystemMouseCursors.click,
            builder: (_, focus) => KeyedSubtree(
              key: ValueKey(('menu-image-slider', enabled)),
              child: Slider(
                focusNode: focus,
                key: const Key('menu-image-default-opacity'),
                value: value.opacityPercent.toDouble(),
                min: 20,
                max: 100,
                divisions: 80,
                label: '${value.opacityPercent}%',
                onChanged: !enabled
                    ? null
                    : (v) =>
                          onChanged(value.change('opacityPercent', v.round())),
              ),
            ),
          ),
          OverlaySettingsHelp(text('privacy')),
          StarBridgeSwitch.tile(
            key: const Key('menu-image-remember'),
            label: text('remember'),
            subtitle: text('rememberHint'),
            subtitleWidget: OverlaySettingsHelp(text('rememberHint')),
            value: value.rememberAdjustments,
            onChanged: !enabled
                ? null
                : (v) => onChanged(value.change('rememberAdjustments', v)),
          ),
          StarBridgeSwitch.tile(
            key: const Key('menu-image-pinned'),
            label: text('pinned'),
            subtitle: text('pinnedHint'),
            subtitleWidget: OverlaySettingsHelp(text('pinnedHint')),
            value: value.defaultPinned,
            onChanged: !enabled
                ? null
                : (v) => onChanged(value.change('defaultPinned', v)),
          ),
        ],
      ),
    );
  }
}
