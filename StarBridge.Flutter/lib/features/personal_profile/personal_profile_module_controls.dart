import 'package:flutter/material.dart';

import 'dart:async';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_menu_anchor.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/window/native_viewport_visibility.dart';
import 'personal_profile_layout.dart';
import 'personal_profile_models.dart';
import 'personal_profile_favorite_modules.dart';

String personalProfileModuleTitleKey(String moduleId) =>
    switch (PersonalProfileModuleIds.typeOf(moduleId)) {
      ProfileFavoriteModules.addAction => 'profile.ships.title',
      PersonalProfileModuleIds.favoriteShips => 'profile.ships.title',
      PersonalProfileModuleIds.hangarSummary => 'profile.hangar.title',
      PersonalProfileModuleIds.skilledRoles => 'profile.position.title',
      _ => 'profile.module.unavailable',
    };

class PersonalProfileModuleControls extends StatelessWidget {
  const PersonalProfileModuleControls({
    required this.item,
    required this.onSizeSelected,
    required this.onRemove,
    this.onEditShips,
    this.onEditPositions,
    super.key,
  });

  final PersonalProfileModuleLayoutItem item;
  final ValueChanged<PersonalProfileModuleSize> onSizeSelected;
  final VoidCallback onRemove;
  final VoidCallback? onEditShips;
  final VoidCallback? onEditPositions;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final allowedSizes = PersonalProfileLayout.allowedSizes(item.moduleId);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onEditPositions != null)
          SizedBox.square(
            dimension: tokens.density.controlHeight * .8,
            child: StarBridgeIconAction(
              controlKey: const Key('profile-positions-edit'),
              constraints: BoxConstraints.tightFor(
                width: tokens.density.compactControlHeight,
                height: tokens.density.compactControlHeight,
              ),
              padding: EdgeInsets.all(tokens.space.xs),
              onActivate: (_) => onEditPositions!(),
              label: strings.text('profile.position.title'),
              icon: StarBridgeIcon(
                StarBridgeIconSemantic.edit,
                size: tokens.icons.small,
              ),
            ),
          ),
        if (onEditShips != null)
          SizedBox.square(
            dimension: tokens.density.controlHeight * .8,
            child: StarBridgeIconAction(
              controlKey: Key('profile-module-edit-${item.moduleId}'),
              constraints: BoxConstraints.tightFor(
                width: tokens.density.compactControlHeight,
                height: tokens.density.compactControlHeight,
              ),
              padding: EdgeInsets.all(tokens.space.xs),
              onActivate: (_) => onEditShips!(),
              label: strings.text('profile.favorites.edit'),
              icon: StarBridgeIcon(
                StarBridgeIconSemantic.edit,
                size: tokens.icons.small,
              ),
            ),
          ),
        if (allowedSizes.length > 1) ...[
          NativeViewportMenu(
            builder: (onOpen, onClose) => StarBridgeMenuAnchor(
              semanticLabel: strings.text('profile.layout.size'),
              onOpen: onOpen,
              onClose: onClose,
              entries: [
                for (final size in allowedSizes)
                  StarBridgeMenuEntry(
                    id: ('profile-module-size-${item.moduleId}', size),
                    label: strings.text('profile.layout.size.${size.name}'),
                    selected: size == item.size,
                    onActivate: size == item.size
                        ? null
                        : (source) => unawaited(
                            runStarBridgeActivation<void>(
                              source,
                              () => onSizeSelected(size),
                            ),
                          ),
                    child: Text(
                      strings.text('profile.layout.size.${size.name}'),
                    ),
                  ),
              ],
              builder: (_, _, focus, toggle) => StarBridgeTooltip(
                message: strings.text('profile.layout.size'),
                child: StarBridgeActionRow(
                  controlKey: Key('profile-module-size-${item.moduleId}'),
                  focusNode: focus,
                  onActivate: (_, source) => toggle(source),
                  child: Container(
                    height: tokens.density.compactControlHeight,
                    padding: EdgeInsets.symmetric(horizontal: tokens.space.sm),
                    decoration: BoxDecoration(
                      color: tokens.surfaces.status.fill,
                      borderRadius: tokens.shape.small,
                      border: Border.all(
                        color: tokens.surfaces.status.border,
                        width: tokens.stroke.hairline,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StarBridgeIcon(
                          StarBridgeIconSemantic.resize,
                          size: tokens.icons.small,
                          color: tokens.colors.textSecondary,
                        ),
                        SizedBox(width: tokens.space.xs),
                        Text(
                          strings.text('profile.layout.size.${item.size.name}'),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        SizedBox(width: tokens.space.xs),
        SizedBox.square(
          dimension: tokens.density.controlHeight * .8,
          child: StarBridgeIconAction(
            controlKey: Key('profile-module-remove-${item.moduleId}'),
            constraints: BoxConstraints.tightFor(
              width: tokens.density.compactControlHeight,
              height: tokens.density.compactControlHeight,
            ),
            padding: EdgeInsets.all(tokens.space.xs),
            onActivate: (_) => onRemove(),
            label: strings.text('profile.layout.remove'),
            icon: StarBridgeIcon(
              StarBridgeIconSemantic.remove,
              size: tokens.icons.small,
            ),
          ),
        ),
      ],
    );
  }
}

class PersonalProfileAddModuleButton extends StatelessWidget {
  const PersonalProfileAddModuleButton({
    required this.hiddenModuleIds,
    required this.onSelected,
    this.compact = false,
    super.key,
  });

  final List<String> hiddenModuleIds;
  final ValueChanged<String> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final entries = ProfileFavoriteModules.addMenuItems(hiddenModuleIds);
    final enabled = hiddenModuleIds.isNotEmpty;
    return NativeViewportMenu(
      builder: (onOpen, onClose) => StarBridgeMenuAnchor(
        enabled: enabled,
        retainExitContent: enabled,
        semanticLabel: strings.text('profile.layout.addModule'),
        onOpen: onOpen,
        onClose: onClose,
        entries: [
          for (final moduleId in entries)
            StarBridgeMenuEntry(
              id: ('profile-add-module', moduleId),
              label: strings.text(personalProfileModuleTitleKey(moduleId)),
              onActivate: (source) => unawaited(
                runStarBridgeActivation<void>(
                  source,
                  () => onSelected(moduleId),
                ),
              ),
              child: Text(
                strings.text(personalProfileModuleTitleKey(moduleId)),
              ),
            ),
        ],
        builder: (_, _, focus, toggle) => StarBridgeTooltip(
          message: strings.text('profile.layout.addModule'),
          child: StarBridgeActionRow(
            controlKey: const Key('profile-add-module-anchor'),
            focusNode: focus,
            onActivate: enabled ? (_, source) => toggle(source) : null,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? tokens.space.sm : tokens.space.md,
                vertical: tokens.space.sm,
              ),
              decoration: BoxDecoration(
                color: tokens.surfaces.status.fill,
                borderRadius: tokens.shape.small,
                border: Border.all(
                  color: tokens.surfaces.status.border,
                  width: tokens.stroke.hairline,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StarBridgeIcon(
                    StarBridgeIconSemantic.add,
                    size: tokens.icons.small,
                    color: hiddenModuleIds.isEmpty
                        ? tokens.colors.textDisabled
                        : tokens.colors.accent,
                  ),
                  if (!compact) ...[
                    SizedBox(width: tokens.space.xs),
                    Text(
                      strings.text('profile.layout.addModule'),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: hiddenModuleIds.isEmpty
                            ? tokens.colors.textDisabled
                            : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
