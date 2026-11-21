import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_slider.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_settings_help.dart';
import 'overlay_workspace_global_group.dart';
import 'overlay_workspace_models.dart';

const _moduleKeyByGroup = <String, String>{
  'notice': 'Notice',
  'fleetOverview': 'Squads',
  'members': 'Members',
  'chat': 'Chat',
  'events': 'Events',
};

class OverlayWorkspaceModuleStyleControls extends StatelessWidget {
  const OverlayWorkspaceModuleStyleControls({
    required this.group,
    required this.layout,
    required this.settings,
    required this.onLayoutChanged,
    required this.onSettingChanged,
    this.onOpenGlobal,
    this.onSizeStep,
    this.layoutLocked = false,
    super.key,
  });

  /// Opens the global group, where calm display is set (null: no link).
  final VoidCallback? onOpenGlobal;

  final String group;
  final bool layoutLocked;
  final void Function(String field, Object? value)? onSizeStep;
  final List<OverlayWorkspaceLayoutItem> layout;
  final OverlayWorkspaceSettings settings;
  final void Function(OverlayWorkspaceLayoutItem item, bool coalesce)
  onLayoutChanged;
  final void Function(String field, Object? value) onSettingChanged;

  @override
  Widget build(BuildContext context) {
    final moduleKey = _moduleKeyByGroup[group];
    if (moduleKey == null) return const SizedBox.shrink();
    final item = moduleKey == 'Events'
        ? null
        : layout.cast<OverlayWorkspaceLayoutItem?>().firstWhere(
            (candidate) => candidate?.key == moduleKey,
            orElse: () => null,
          );
    if (moduleKey != 'Events' && item == null) return const SizedBox.shrink();

    final textOpacity = moduleKey == 'Events'
        ? (settings['eventNotificationTextOpacity']! as num).toDouble()
        : item!.textOpacity;
    final backgroundOpacity = moduleKey == 'Events'
        ? (settings['eventNotificationBackgroundOpacity']! as num).toDouble()
        : item!.backgroundOpacity;
    final decorationOpacity = moduleKey == 'Events'
        ? (settings['eventNotificationDecorationOpacity']! as num).toDouble()
        : item!.decorationOpacity;
    final tokens = context.tokens;

    return Column(
      key: Key('overlay-module-style-$moduleKey'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // the block's look, apart from what it shows and how (11-11 user)
        Text(
          AppStrings.of(context).text('overlay.workspace.group.look'),
          key: Key('overlay-module-look-$moduleKey'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        SizedBox(height: tokens.space.xs),
        OverlayWorkspaceBlockLook(
          onSizeStep: onSizeStep,
          sizeLocked: layoutLocked || (item?.isLocked ?? false),
          moduleKey: moduleKey,
          settings: settings,
          onChanged: onSettingChanged,
        ),
        _OpacityControl(
          key: Key('overlay-module-text-opacity-$moduleKey'),
          label: AppStrings.of(context)
              .text('overlay.workspace.layout.textOpacity'),
          value: textOpacity,
          minimum: 0.15,
          divisions: 17,
          onChanged: (value) {
            if (item == null) {
              onSettingChanged('eventNotificationTextOpacity', value);
            } else {
              onLayoutChanged(item.copyWith(textOpacity: value), true);
            }
          },
        ),
        _OpacityControl(
          key: Key('overlay-module-background-opacity-$moduleKey'),
          label: AppStrings.of(context)
              .text('overlay.workspace.layout.backgroundOpacity'),
          value: backgroundOpacity,
          minimum: 0,
          divisions: 20,
          onChanged: (value) {
            if (item == null) {
              onSettingChanged('eventNotificationBackgroundOpacity', value);
            } else {
              onLayoutChanged(item.copyWith(backgroundOpacity: value), true);
            }
          },
        ),
        _OpacityControl(
          key: Key('overlay-module-decoration-opacity-$moduleKey'),
          label: AppStrings.of(context)
              .text('overlay.workspace.layout.decorationOpacity'),
          value: decorationOpacity,
          minimum: 0,
          divisions: 20,
          onChanged: (value) {
            if (item == null) {
              onSettingChanged('eventNotificationDecorationOpacity', value);
            } else {
              onLayoutChanged(item.copyWith(decorationOpacity: value), true);
            }
          },
        ),
        Padding(
          padding: EdgeInsets.only(top: tokens.space.xs),
          child: OverlaySettingsHelp(
            AppStrings.of(context)
                .text('overlay.workspace.layout.backgroundHelp'),
            key: Key('overlay-module-background-help-$moduleKey'),
          ),
        ),
        // calm display is the whole visor's: set in the global group (11-11)
        if (moduleKey case 'Squads' || 'Members' || 'Chat') ...[
          SizedBox(height: tokens.space.sm),
          OverlayWorkspaceGlobalLink(
            key: const Key('overlay-calm-global-link'),
            text: AppStrings.of(context).text(
              settings['calmDisplay'] == 'On'
                  ? 'overlay.workspace.global.calmOn'
                  : 'overlay.workspace.global.calmOff',
            ),
            onOpen: onOpenGlobal,
          ),
        ],
        if (item != null) ...[
          SizedBox(height: tokens.space.md),
          Text(
            AppStrings.of(context).text('overlay.editor.opacityControls'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          StarBridgeSwitch.tile(
            controlKey: Key('overlay-module-lock-$moduleKey'),
            preserveNativeTile: true,
            label: AppStrings.of(context)
                .text('overlay.workspace.layout.lockPositionSize'),
            value: item.isLocked,
            onChanged: (value) =>
                onLayoutChanged(item.copyWith(isLocked: value), false),
          ),
        ],
      ],
    );
  }
}

class _OpacityControl extends StatelessWidget {
  const _OpacityControl({
    required this.label,
    required this.value,
    required this.minimum,
    required this.divisions,
    required this.onChanged,
    super.key,
  });

  final String label;
  final double value;
  final double minimum;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: EdgeInsets.only(top: tokens.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                '${(value * 100).round()}%',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: tokens.colors.textSecondary,
                  fontFamily: tokens.typography.monoFamily,
                ),
              ),
            ],
          ),
          StarBridgeSlider(
            semanticLabel: label,
            value: value.clamp(minimum, 1),
            min: minimum,
            max: 1,
            divisions: divisions,
            valueLabel: (value) => '${(value * 100).round()}%',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
