import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/styles/approved_appearance_thumbnail.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_projection.dart';

class OverlayWorkspaceAppearanceEntry extends StatelessWidget {
  const OverlayWorkspaceAppearanceEntry({
    required this.projection,
    required this.onPressed,
    super.key,
  });

  final OverlayWorkspaceProjection projection;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final snapshot = projection.snapshot!;
    final skin = projection.settings!['skin'] as String;
    final appearance = snapshot.appearances
        .cast<OverlayWorkspaceAppearance?>()
        .firstWhere(
          (entry) => entry?.id == skin,
          orElse: () =>
              snapshot.appearances.isEmpty ? null : snapshot.appearances.first,
        );
    final locale = Localizations.localeOf(context);
    final english = locale.languageCode == 'en';
    final name = appearance == null
        ? _copy(context, 'overlay.workspace.appearance.unknown')
        : english
        ? appearance.displayNameEn
        : appearance.displayNameZh;
    final status = appearance?.isAvailable == false
        ? _copy(context, 'overlay.workspace.appearance.requiresQualification')
        : _copy(context, 'overlay.workspace.appearance.available');
    final statusColor = appearance?.isAvailable == false
        ? tokens.colors.warning
        : tokens.colors.success;
    return SizedBox(
      height: tokens.density.controlHeight + tokens.space.sm,
      child: Material(
        color: tokens.surfaces.ground.fill,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: tokens.surfaces.panel.border),
          borderRadius: tokens.shape.small,
        ),
        child: InkWell(
          key: const Key('overlay-appearance-center-entry'),
          onTap: onPressed,
          borderRadius: tokens.shape.small,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.space.sm),
            child: Row(
              children: [
                ApprovedAppearanceThumbnail(skinId: skin),
                SizedBox(width: tokens.space.sm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _copy(context, 'overlay.workspace.appearance.current'),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: tokens.colors.textSecondary),
                      ),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: tokens.space.sm),
                Text(
                  status,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: statusColor),
                ),
                SizedBox(width: tokens.space.xs),
                StarBridgeIcon(
                  StarBridgeIconSemantic.forward,
                  size: tokens.icons.small,
                  color: tokens.colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);
