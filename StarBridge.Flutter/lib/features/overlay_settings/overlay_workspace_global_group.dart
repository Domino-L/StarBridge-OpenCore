import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_calm_display_controls.dart';
import 'overlay_settings_help.dart';
import 'overlay_workspace_controls.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_rules.dart';
import 'overlay_workspace_schema.dart';

/// The settings for the whole visor, in one group at the top (11-11 user:
/// "浮层设置应该加入全局设置，包含3d类、安静显示等等", the layout he chose:
/// shape, colour, calm display, the whole overlay, opening and closing).
/// Only where they are shown changed: the same settings, saved as before.
class OverlayWorkspaceGlobalGroup extends StatelessWidget {
  const OverlayWorkspaceGlobalGroup({
    required this.settings,
    required this.onChanged,
    this.onExperiencePreset,
    this.appearances = const [],
    this.editOwner,
    this.currentEditOwner,
    super.key,
  });

  final OverlayWorkspaceSettings settings;
  final void Function(String field, Object? value) onChanged;
  final ValueChanged<String>? onExperiencePreset;
  final List<OverlayWorkspaceAppearance> appearances;
  final Object? editOwner;
  final Object? Function()? currentEditOwner;

  static const group = 'global';

  /// The sections in order and their settings; calm display shows its own
  /// controls (the idle level never above the lit one).
  static const sections = <String, List<String>>{
    'shape': ['visorSize', 'visorTilt', 'visorViewingDistance'],
    'color': ['theme', 'autoThemeByShip'],
    'calm': [
      'calmDisplay',
      'calmWaitSeconds',
      'calmIdleOpacity',
      'calmLitOpacity',
      'calmLightWhen',
      'calmPeekHotkey',
    ],
    // the overall opacity is retired (11-12 user: "全局里的整体透明度应该去掉"):
    // no control, and the overlay draws full whatever value is saved. The
    // animation experience sits with every frame rate it sets (11-13 user,
    // 请你定 6), where the overall section was.
    'animation': [
      'animationFrameRate',
      'enableStartupTransition',
      'startupTransitionFrameRate',
    ],
    'openClose': [
      'skipStartupTransitionWhenGameForeground',
      'autoFocusGameWindowOnOpen',
    ],
  };

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final copy = AppStrings.of(context).text;
    final profile = overlayWorkspaceAppearanceRule(settings);
    final specs = {
      for (final spec in overlayWorkspaceFieldSpecs)
        if (spec.group == group) spec.field: spec,
    };
    Widget fields(List<String> keys) => LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 900
            ? (constraints.maxWidth - tokens.space.md) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: tokens.space.md,
          runSpacing: tokens.space.sm,
          children: [
            for (final key in keys)
              if (specs[key] case final spec?
                  when spec.userVisible &&
                      overlayWorkspaceFieldVisible(
                        key,
                        settings,
                        appearanceRule: profile,
                      ))
                SizedBox(
                  width: width,
                  child: OverlayWorkspaceField(
                    spec: spec,
                    labelKey: overlayWorkspaceFieldLabelKey(key, settings),
                    editOwner: editOwner,
                    currentEditOwner: currentEditOwner,
                    value: settings[key],
                    appearances: appearances,
                    enabled: overlayWorkspaceFieldEnabled(
                      key,
                      settings,
                      appearanceRule: profile,
                    ),
                    disabledReason: overlayWorkspaceFieldDisabledReason(
                      key,
                      settings,
                      appearanceRule: profile,
                    ),
                    onChanged: (value) => onChanged(key, value),
                  ),
                ),
          ],
        );
      },
    );

    return StarBridgeSurface(
      role: SurfaceRole.panel,
      key: const Key('overlay-group-global'),
      padding: EdgeInsets.all(tokens.space.md),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              overlayWorkspaceGroupName(context, group),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: tokens.space.xs),
            OverlaySettingsHelp(copy('overlay.workspace.global.help')),
            for (final MapEntry(key: section, value: keys)
                in sections.entries) ...[
              SizedBox(height: tokens.space.md),
              Text(
                overlayWorkspaceGroupName(context, '$group.$section'),
                key: Key('overlay-global-$section'),
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: tokens.colors.accent),
              ),
              SizedBox(height: tokens.space.sm),
              if (section == 'color' && profile.locksTheme) ...[
                OverlaySettingsHelp(
                  copy('overlay.workspace.fixedPalette'),
                  key: const Key('overlay-appearance-fixed-palette'),
                ),
                SizedBox(height: tokens.space.sm),
              ],
              if (section == 'animation' && onExperiencePreset != null) ...[
                OverlayExperiencePresetPicker(
                  settings: settings,
                  onSelected: onExperiencePreset!,
                ),
                SizedBox(height: tokens.space.sm),
              ],
              if (section == 'calm')
                OverlayCalmDisplayControls(
                  settings: settings,
                  onSettingChanged: onChanged,
                  // barrage chat takes no part; the controls say so
                  chatBarrage:
                      settings['chatDisplayMode'] == 'FullScreenBarrage',
                )
              else
                fields(keys),
            ],
          ],
        ),
      ),
    );
  }
}

/// A block's own look settings beyond its opacities (11-11 user: "各块宽高应该
/// 在各块位置调"): its size, and for the chat its plate and text outline.
/// Shown in the block's "外观" section; the same settings, saved as before.
class OverlayWorkspaceBlockLook extends StatelessWidget {
  const OverlayWorkspaceBlockLook({
    required this.moduleKey,
    required this.settings,
    required this.onChanged,
    this.onSizeStep,
    this.sizeLocked = false,
    super.key,
  });

  final String moduleKey;
  final bool sizeLocked;
  final void Function(String field, Object? value)? onSizeStep;
  final OverlayWorkspaceSettings settings;
  final void Function(String field, Object? value) onChanged;

  /// Each block's look settings, in order.
  static const fields = <String, List<String>>{
    'Members': [
      'visorMembersAutoWidth',
      'visorMembersWidth',
      'visorMembersAutoHeight',
      'visorMembersHeight',
    ],
    'Events': ['visorEventsAutoWidth', 'visorEventsWidth'],
    'Chat': [
      'visorChatAutoWidth',
      'visorChatWidth',
      'visorChatPlate',
      'chatTextEdgeStrength',
    ],
  };

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final profile = overlayWorkspaceAppearanceRule(settings);
    final specs = {
      for (final spec in overlayWorkspaceFieldSpecs) spec.field: spec,
    };
    final shown = [
      for (final key in fields[moduleKey] ?? const <String>[])
        if (specs[key] case final spec?
            when spec.userVisible &&
                overlayWorkspaceFieldVisible(
                  key,
                  settings,
                  appearanceRule: profile,
                ))
          spec,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: Key('overlay-block-look-$moduleKey'),
      padding: EdgeInsets.only(bottom: tokens.space.sm),
      child: Wrap(
        runSpacing: tokens.space.sm,
        children: [
          for (final spec in shown)
            OverlayWorkspaceField(
              spec: spec,
              labelKey: overlayWorkspaceFieldLabelKey(spec.field, settings),
              value: settings[spec.field],
              enabled:
                  !(sizeLocked &&
                      const {
                        'visorMembersWidth',
                        'visorMembersHeight',
                      }.contains(spec.field)) &&
                  overlayWorkspaceFieldEnabled(
                    spec.field,
                    settings,
                    appearanceRule: profile,
                  ),
              disabledReason: overlayWorkspaceFieldDisabledReason(
                spec.field,
                settings,
                appearanceRule: profile,
              ),
              onChanged: (value) => onChanged(spec.field, value),
              onStep: onSizeStep == null
                  ? null
                  : (value) => onSizeStep!(spec.field, value),
            ),
        ],
      ),
    );
  }
}

/// The settings the appearance try-on page offers: the appearance's own, the
/// whole visor's and the blocks' sizes, as before the 11-11 regrouping.
bool overlayWorkspaceTriedOn(OverlayWorkspaceFieldSpec spec) =>
    const {'appearance', 'global'}.contains(spec.group) ||
    spec.field.startsWith('visor');

/// Where a whole-visor setting used to be: one line that says where it is now
/// and opens the global group (the user chose "删掉，留一行跳转").
class OverlayWorkspaceGlobalLink extends StatelessWidget {
  const OverlayWorkspaceGlobalLink({
    required this.text,
    this.onOpen,
    super.key,
  });

  final String text;

  /// Opens the global group; null where there is nowhere to go (the line
  /// then only says where the setting is).
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final copy = AppStrings.of(context).text;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.sm,
        vertical: tokens.space.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaces.panel.fill,
        border: Border.all(color: tokens.surfaces.panel.border),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: tokens.space.sm,
        children: [
          Text(text, style: Theme.of(context).textTheme.bodySmall),
          if (onOpen != null)
            TextButton(
              key: const Key('overlay-open-global'),
              onPressed: onOpen,
              child: Text('${copy('overlay.workspace.global.open')} →'),
            )
          else
            Text(
              copy('overlay.workspace.global.open'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
