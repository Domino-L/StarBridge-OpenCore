import 'package:flutter/material.dart';

import '../../shared/ships/catalog_vehicle_icon.dart';
import 'community_ships_port.dart';

/// The Host resolves an exact local catalog key after authorization. Broad
/// categories lose ground/passenger/racing distinctions, so never guess from them.
class CommunityShipVehicleIcon extends StatelessWidget {
  const CommunityShipVehicleIcon({required this.ship, super.key});
  final CommunitySharedShip ship;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CatalogVehicleIcon.supportsKey(ship.displayIcon ?? '')
          ? CatalogVehicleIcon.byKey(iconKey: ship.displayIcon!)
          : const SizedBox.square(dimension: 28),
    );
  }
}
