import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/interaction/starbridge_select_field.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';

import '../../app/localization/app_strings.dart';
import 'overlay_settings_help.dart';
import '../../platform/window/menu_screenshot_preferences.dart';

class MenuScreenshotEditor extends StatelessWidget {
  const MenuScreenshotEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.showTitle = true,
  });
  final MenuScreenshotPreferences value;
  final bool showTitle;
  final bool enabled;
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
          StarBridgeSwitch.tile(
            key: const Key('menu-screenshot-hide-menu'),
            label: text('hideMenu'),
            subtitle: text('hideMenuHint'),
            subtitleWidget: OverlaySettingsHelp(text('hideMenuHint')),
            value: value.hideMenu,
            onChanged: !enabled
                ? null
                : (v) => onChanged(value.change('hideMenu', v)),
          ),
          const SizedBox(height: 12),
          StarBridgeSelectField<String>(
            key: ValueKey('menu-screenshot-format'),
            identity: 'menu-screenshot-format',
            value: value.format,
            decoration: InputDecoration(labelText: text('format')),
            options: [
              for (final format in const ['png', 'jpeg'])
                StarBridgeSelectOption(value: format, label: text(format)),
            ],
            onSelected: !enabled
                ? null
                : (v, _) {
                    onChanged(value.change('format', v));
                  },
          ),
          OverlaySettingsHelp(text('formatHint')),
          if (value.format == 'jpeg') ...[
            const SizedBox(height: 12),
            Text('${text('quality')} ${value.jpegQuality}%'),
            StarBridgeFieldFrame(
              enabled: enabled,
              cursor: SystemMouseCursors.click,
              builder: (_, focus) => KeyedSubtree(
                key: ValueKey(('menu-screenshot-slider', enabled)),
                child: Slider(
                  focusNode: focus,
                  key: const Key('menu-screenshot-quality'),
                  value: value.jpegQuality.toDouble(),
                  min: 50,
                  max: 100,
                  divisions: 50,
                  label: '${value.jpegQuality}%',
                  onChanged: !enabled
                      ? null
                      : (v) =>
                            onChanged(value.change('jpegQuality', v.round())),
                ),
              ),
            ),
          ],
          StarBridgeSwitch.tile(
            key: const Key('menu-screenshot-copy'),
            label: text('copy'),
            subtitle: text('copyHint'),
            subtitleWidget: OverlaySettingsHelp(text('copyHint')),
            value: value.copyAfterSave,
            onChanged: !enabled
                ? null
                : (v) => onChanged(value.change('copyAfterSave', v)),
          ),
          StarBridgeSwitch.tile(
            key: const Key('menu-screenshot-confirmation'),
            label: text('confirmation'),
            subtitle: text('confirmationHint'),
            subtitleWidget: OverlaySettingsHelp(text('confirmationHint')),
            value: value.showConfirmation,
            onChanged: !enabled
                ? null
                : (v) => onChanged(value.change('showConfirmation', v)),
          ),
          OverlaySettingsHelp(text('privacy')),
        ],
      ),
    );
  }
}
