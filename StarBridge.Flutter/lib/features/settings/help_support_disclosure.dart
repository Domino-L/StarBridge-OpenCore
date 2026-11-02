import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'help_support_expansion_tile.dart';

/// Original help header presentation, with suite feedback and body reveal.
class HelpSupportDisclosureCard extends StatelessWidget {
  const HelpSupportDisclosureCard({
    required this.titleKey,
    required this.bodyKey,
    required this.accent,
    this.initiallyExpanded = false,
    super.key,
  });

  final String titleKey;
  final String bodyKey;
  final Color accent;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: HelpSupportExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding: EdgeInsets.symmetric(
              horizontal: tokens.space.md,
              vertical: tokens.space.xxs,
            ),
            childrenPadding: EdgeInsetsDirectional.fromSTEB(
              tokens.space.md,
              0,
              tokens.space.md,
              tokens.space.md,
            ),
            leading: Container(
              width: 4,
              height: 30,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: tokens.shape.small,
              ),
            ),
            title: Text(
              strings.text(titleKey),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            trailing: StarBridgeIcon(
              StarBridgeIconSemantic.menuDown,
              size: tokens.icons.small,
              color: tokens.colors.textSecondary,
            ),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  strings.text(bodyKey),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.colors.textSecondary,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
