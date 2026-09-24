import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'personal_profile_module_controls.dart';

class PersonalProfileLayoutToolbar extends StatelessWidget {
  const PersonalProfileLayoutToolbar({
    required this.hiddenModuleIds,
    required this.onAdd,
    super.key,
  });

  final List<String> hiddenModuleIds;
  final ValueChanged<String> onAdd;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: SurfaceRole.status,
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.md,
        vertical: tokens.space.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              AppStrings.of(context).text('profile.favorites.hint'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
          ),
          SizedBox(width: tokens.space.md),
          PersonalProfileAddModuleButton(
            key: const Key('profile-layout-add-module'),
            hiddenModuleIds: hiddenModuleIds,
            onSelected: onAdd,
          ),
        ],
      ),
    );
  }
}

class PersonalProfileEmptyGridCell extends StatelessWidget {
  const PersonalProfileEmptyGridCell({
    required this.position,
    required this.hiddenModuleIds,
    required this.onAdd,
    super.key,
  });

  final int position;
  final List<String> hiddenModuleIds;
  final ValueChanged<String> onAdd;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      key: Key('profile-grid-cell-$position'),
      decoration: BoxDecoration(
        color: tokens.surfaces.status.fill,
        borderRadius: tokens.shape.medium,
        border: Border.all(
          color: tokens.surfaces.status.border,
          width: tokens.stroke.hairline,
        ),
      ),
      alignment: Alignment.center,
      child: PersonalProfileAddModuleButton(
        hiddenModuleIds: hiddenModuleIds,
        onSelected: onAdd,
        compact: true,
      ),
    );
  }
}

class PersonalProfileGridDropPreview extends StatelessWidget {
  const PersonalProfileGridDropPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: tokens.shape.medium,
          border: Border.all(
            color: tokens.colors.focusRing,
            width: tokens.stroke.focusWidth,
          ),
        ),
      ),
    );
  }
}

class PersonalProfileUnavailableModule extends StatelessWidget {
  const PersonalProfileUnavailableModule({super.key});

  @override
  Widget build(BuildContext context) {
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Text(
        AppStrings.of(context).text('profile.module.unavailable'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
