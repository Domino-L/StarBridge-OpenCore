import 'package:flutter/material.dart';

import '../../shared/ships/catalog_vehicle_icon.dart';
import '../../shared/ships/ship_reviewed_display.dart';
import 'hangar_combat_icon.dart';
import 'hangar_combat_motion.dart';
import 'hangar_catalog_icon.dart';

/// Play the exact reviewed family. Old payloads keep the legacy combat icon;
/// never infer a category from a ship's name or invent an unclassified sequence.
class HangarShipIcon extends StatelessWidget {
  const HangarShipIcon({
    required this.display,
    required this.legacyCombatSize,
    required this.elapsed,
    this.active = true,
    this.fallback = const SizedBox.shrink(),
    super.key,
  });

  final ShipReviewedDisplay? display;
  final HangarCombatSize? legacyCombatSize;
  final Duration elapsed;
  final bool active;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final reviewed = display;
    if (reviewed != null &&
        CatalogVehicleIcon.motionDuration(reviewed.iconKey ?? '') != null) {
      return ExcludeSemantics(
        child: HangarCatalogIcon(
          iconKey: reviewed.iconKey!,
          elapsed: elapsed,
          active: active,
        ),
      );
    }
    final size = reviewed == null ? legacyCombatSize : null;
    if (size != null) {
      return ExcludeSemantics(
        child: HangarCombatIcon(
          sizeClass: size,
          elapsed: elapsed,
          active: active,
          dimension: 24,
        ),
      );
    }
    final key = reviewed?.iconKey;
    return key != null && CatalogVehicleIcon.supportsKey(key)
        ? CatalogVehicleIcon.byKey(iconKey: key)
        : fallback;
  }
}
