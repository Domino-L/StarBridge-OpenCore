import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

class PersonalProfileModuleSurface extends StatelessWidget {
  const PersonalProfileModuleSurface({
    required this.icon,
    required this.titleKey,
    required this.child,
    this.accentRole,
    this.headerTrailing,
    super.key,
  });

  final StarBridgeIconSemantic icon;
  final String titleKey;
  final Widget child;
  final DomainColorRole? accentRole;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final iconColor = accentRole == null
        ? tokens.colors.textSecondary
        : tokens.domainColors.resolve(accentRole!).foreground;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      fillOpacity: 0.84,
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.md,
        vertical: tokens.space.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  headerTrailing != null &&
                  constraints.maxWidth < 300;
              final heading = Row(
                children: [
                  StarBridgeIcon(
                    icon,
                    size: tokens.icons.medium,
                    color: iconColor,
                  ),
                  SizedBox(width: tokens.space.sm),
                  Expanded(
                    child: Text(
                      strings.text(titleKey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (!stacked && headerTrailing != null) ...[
                    SizedBox(width: tokens.space.sm),
                    headerTrailing!,
                  ],
                ],
              );
              return stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        heading,
                        SizedBox(height: tokens.space.xs),
                        headerTrailing!,
                      ],
                    )
                  : heading;
            },
          ),
          SizedBox(height: tokens.space.xs),
          Expanded(child: child),
        ],
      ),
    );
  }
}
