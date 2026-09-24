import '../../design_system/styles/catalog_vehicle_palette.dart';
import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';

Color shipSizeColor(BuildContext context, String? size) {
  final t = context.tokens;
  return switch (size?.toLowerCase().replaceFirst('ground-', '')) {
    'capital' || '旗舰级' || '旗艦級' => t.domainColors.command.foreground,
    'large' || '大型' => t.colors.info,
    'medium' || '中型' => t.colors.warning,
    'small' || '小型' => t.colors.success,
    _ => t.colors.textSecondary,
  };
}

Color shipCategoryColor(BuildContext context, String role) {
  final t = context.tokens;
  return switch (role) {
    // Exact approved glyph accents; white hulls retain theme adaptation.
    'combat' || 'ground-combat' => CatalogVehiclePalette.combat,
    'transport' => CatalogVehiclePalette.logistics,
    'industrial' => CatalogVehiclePalette.industrial,
    'exploration' => CatalogVehiclePalette.exploration,
    'support' => CatalogVehiclePalette.support,
    'competition' => CatalogVehiclePalette.competition,
    'ground-transport' => CatalogVehiclePalette.groundTransport,
    'ground-industrial' => CatalogVehiclePalette.groundIndustrial,
    'ground-exploration' => CatalogVehiclePalette.groundExploration,
    'ground-support' => CatalogVehiclePalette.groundSupport,
    'ground-competition' => CatalogVehiclePalette.groundCompetition,
    'multi-role' || 'utility' => t.domainColors.ship.foreground,
    _ => t.colors.textSecondary,
  };
}
