import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
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
          IconButton(
            key: const Key('profile-positions-edit'),
            onPressed: onEditPositions,
            tooltip: strings.text('profile.position.title'),
            visualDensity: VisualDensity.compact,
            icon: StarBridgeIcon(
              StarBridgeIconSemantic.edit,
              size: tokens.icons.small,
            ),
          ),
        if (onEditShips != null)
          IconButton(
            key: Key('profile-module-edit-${item.moduleId}'),
            onPressed: onEditShips,
            tooltip: strings.text('profile.favorites.edit'),
            visualDensity: VisualDensity.compact,
            icon: StarBridgeIcon(
              StarBridgeIconSemantic.edit,
              size: tokens.icons.small,
            ),
          ),
        if (allowedSizes.length > 1) ...[
          PopupMenuButton<PersonalProfileModuleSize>(
            key: Key('profile-module-size-${item.moduleId}'),
            tooltip: strings.text('profile.layout.size'),
            onSelected: onSizeSelected,
            itemBuilder: (context) => [
              for (final size in allowedSizes)
                PopupMenuItem(
                  value: size,
                  enabled: size != item.size,
                  child: Text(strings.text('profile.layout.size.${size.name}')),
                ),
            ],
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
        ],
        SizedBox(width: tokens.space.xs),
        IconButton(
          key: Key('profile-module-remove-${item.moduleId}'),
          onPressed: onRemove,
          tooltip: strings.text('profile.layout.remove'),
          visualDensity: VisualDensity.compact,
          iconSize: tokens.icons.small,
          icon: StarBridgeIcon(StarBridgeIconSemantic.remove),
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
    return PopupMenuButton<String>(
      enabled: hiddenModuleIds.isNotEmpty,
      tooltip: strings.text('profile.layout.addModule'),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final moduleId in entries)
          PopupMenuItem(
            value: moduleId,
            child: Text(strings.text(personalProfileModuleTitleKey(moduleId))),
          ),
      ],
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
    );
  }
}
