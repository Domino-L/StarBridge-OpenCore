import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_workspace_models.dart';
import 'overlay_preset_name.dart';

// Presentation only. The original bar owns draft controllers and all commands.
class OverlayPresetNameEditor extends StatelessWidget {
  const OverlayPresetNameEditor({
    required this.controller,
    required this.currentName,
    required this.enabled,
    required this.onSave,
    super.key,
  });

  final TextEditingController controller;
  final String currentName;
  final bool enabled;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final name = value.text.trim();
        final canSave = enabled && name.isNotEmpty && name != currentName;
        return StarBridgeFieldFrame(
          enabled: enabled,
          builder: (context, focus) => TextField(
            key: const Key('overlay-active-preset-name'),
            controller: controller,
            focusNode: focus,
            enabled: enabled,
            maxLength: 24,
            textInputAction: TextInputAction.done,
            onSubmitted: canSave ? (_) => onSave() : null,
            decoration: InputDecoration(
              labelText: _copy(context, 'overlay.workspace.currentPresetName'),
              isDense: true,
              counterText: '',
              suffixIconConstraints: const BoxConstraints(minHeight: 40),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _copy(context, 'overlay.workspace.renamePresetHint'),
                    key: const Key('overlay-preset-name-save-hint'),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.colors.textDisabled),
                  ),
                  StarBridgeIconAction(
                    controlKey: const Key('overlay-active-preset-rename'),
                    label: _copy(context, 'overlay.workspace.savePresetName'),
                    onActivate: canSave ? (_) => onSave() : null,
                    icon: StarBridgeIcon(
                      StarBridgeIconSemantic.save,
                      size: tokens.icons.small,
                      color: canSave
                          ? tokens.colors.accent
                          : tokens.colors.textDisabled,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class OverlayAddPresetCard extends StatelessWidget {
  const OverlayAddPresetCard({
    required this.enabled,
    required this.onPressed,
    super.key,
  });

  final bool enabled;
  final ValueChanged<InteractionSource> onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.surfaces.ground.fill,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: enabled
              ? tokens.colors.accent.withValues(alpha: 0.72)
              : tokens.colors.textDisabled,
        ),
        borderRadius: tokens.shape.medium,
      ),
      child: StarBridgeActionRow(
        key: const Key('overlay-add-preset'),
        onActivate: enabled ? (_, source) => onPressed(source) : null,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.space.md,
            vertical: tokens.space.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StarBridgeIcon(
                StarBridgeIconSemantic.add,
                size: tokens.icons.small,
                color: enabled
                    ? tokens.colors.accent
                    : tokens.colors.textDisabled,
              ),
              SizedBox(width: tokens.space.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _copy(context, 'overlay.workspace.addPreset'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    _copy(context, 'overlay.workspace.addPresetDefault'),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.colors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OverlayQuickPresetCard extends StatelessWidget {
  const OverlayQuickPresetCard({
    required this.preset,
    required this.showLegacyScene,
    required this.selected,
    required this.enabled,
    required this.onPressed,
    super.key,
  });

  final OverlayWorkspacePreset preset;
  final bool showLegacyScene;
  final bool selected;
  final bool enabled;
  final ValueChanged<InteractionSource> onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scene = preset.settings['scenePreference'] as String;
    return Material(
      color: selected
          ? tokens.colors.accent.withValues(alpha: 0.14)
          : tokens.surfaces.ground.fill,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? tokens.colors.accent : tokens.surfaces.panel.border,
        ),
        borderRadius: tokens.shape.medium,
      ),
      child: StarBridgeActionRow(
        key: Key('overlay-quick-preset-${preset.id}'),
        onActivate: enabled ? (_, source) => onPressed(source) : null,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.space.md,
            vertical: tokens.space.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? tokens.colors.accent : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? tokens.colors.accent
                        : tokens.colors.textSecondary,
                    width: tokens.stroke.regular,
                  ),
                ),
              ),
              SizedBox(width: tokens.space.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.shownName(AppStrings.of(context)),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  if (showLegacyScene)
                    Text(
                      _copy(context, 'overlay.workspace.option.$scene'),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: tokens.colors.textSecondary),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);
