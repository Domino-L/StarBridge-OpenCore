import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_switch.dart';

import '../../app/localization/app_strings.dart';
import '../../platform/window/menu_desktop_widgets.dart';
import 'overlay_settings_help.dart';

/// Menu presentation only; the tool page retains monitoring and reminders.
class MenuDesktopWidgetsEditor extends StatelessWidget {
  const MenuDesktopWidgetsEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final MenuDesktopWidgets value;
  final bool enabled;
  final ValueChanged<MenuDesktopWidgets> onChanged;
  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.of(context).text('execHangar.$key');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t('widgetSettings'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        StarBridgeSwitch.tile(
          key: const Key('menu-widget-visible'),
          label: t('widgetAlwaysShow'),
          value: value.hangar,
          onChanged: !enabled
              ? null
              : (show) => onChanged(value.copyWith(hangar: show)),
        ),
        OverlaySettingsHelp(t('widgetRailHint')),
      ],
    );
  }
}
