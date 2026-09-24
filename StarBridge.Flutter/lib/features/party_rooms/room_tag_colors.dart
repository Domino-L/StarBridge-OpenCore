import 'package:flutter/material.dart';

import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'room_tag_catalog.dart';

/// Gameplay taxonomy colors are independent of the application accent/skin.
DomainColorPairTokens roomTagColors(BuildContext context, String id) {
  final tokens = context.tokens;
  final root = RoomTagCatalog.pathIds(id).firstOrNull;
  final role = switch (root) {
    'combat' || 'arena' => DomainColorRole.airCombat,
    'industry' => DomainColorRole.industry,
    'logistics' => DomainColorRole.logistics,
    'support' => DomainColorRole.medical,
    'exploration' => DomainColorRole.recon,
    'social' => DomainColorRole.ship,
    'special' => DomainColorRole.command,
    _ => null,
  };
  return role == null
      ? DomainColorPairTokens(
          foreground: tokens.colors.textSecondary,
          soft: tokens.surfaces.raised.fill,
        )
      : tokens.domainColors.resolve(role);
}
