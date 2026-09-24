import '../../../design_system/styles/catalog_vehicle_palette.dart';
import 'dart:ui';
import '../catalog_vehicle_glyph.dart';

// Generated solely from the 19 ground/MPUV final SVGs in the V1 icon index.
// See catalog_ground_vehicle_icon_sources.json for exact sources and hashes.
// White body = theme foreground (null); source accents and fill rules preserved.
final Map<String, CatalogVehicleGlyph> entries = {
  'ground-combat-small-mech': CatalogVehicleGlyph(
    const Rect.fromLTWH(0, 0, 40, 40),
    [
      CatalogVehicleLayer(
        (Path()
          ..fillType = PathFillType.evenOdd
          ..moveTo(16, 5)
          ..lineTo(24, 5)
          ..lineTo(26, 7)
          ..lineTo(26, 16)
          ..lineTo(23, 20)
          ..lineTo(17, 20)
          ..lineTo(14, 16)
          ..lineTo(14, 7)
          ..close()
          ..moveTo(17, 8)
          ..lineTo(23, 8)
          ..lineTo(23, 14)
          ..lineTo(21, 17)
          ..lineTo(19, 17)
          ..lineTo(17, 14)
          ..close()),
        null,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(7, 1)
          ..lineTo(11, 1)
          ..lineTo(12, 3)
          ..lineTo(12, 14)
          ..lineTo(10, 17)
          ..lineTo(6, 17)
          ..lineTo(5, 15)
          ..lineTo(5, 4)
          ..close()),
        null,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(29, 1)
          ..lineTo(33, 1)
          ..lineTo(35, 4)
          ..lineTo(35, 15)
          ..lineTo(34, 17)
          ..lineTo(30, 17)
          ..lineTo(28, 14)
          ..lineTo(28, 3)
          ..close()),
        null,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(12, 22)
          ..lineTo(18, 22)
          ..lineTo(18, 29)
          ..lineTo(17, 31)
          ..lineTo(12, 31)
          ..lineTo(11, 29)
          ..lineTo(11, 24)
          ..close()
          ..moveTo(12, 33)
          ..lineTo(17, 33)
          ..lineTo(17, 35)
          ..lineTo(18, 36)
          ..lineTo(18, 38)
          ..lineTo(10, 38)
          ..lineTo(10, 36)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(28, 22)
          ..lineTo(22, 22)
          ..lineTo(22, 29)
          ..lineTo(23, 31)
          ..lineTo(28, 31)
          ..lineTo(29, 29)
          ..lineTo(29, 24)
          ..close()
          ..moveTo(28, 33)
          ..lineTo(23, 33)
          ..lineTo(23, 35)
          ..lineTo(22, 36)
          ..lineTo(22, 38)
          ..lineTo(30, 38)
          ..lineTo(30, 36)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(7, 19)
          ..lineTo(10, 19)
          ..lineTo(11, 20)
          ..lineTo(11, 23)
          ..lineTo(10, 24)
          ..lineTo(10, 26)
          ..lineTo(7, 26)
          ..lineTo(7, 24)
          ..lineTo(6, 23)
          ..lineTo(6, 20)
          ..close()),
        CatalogVehiclePalette.combat,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(33, 19)
          ..lineTo(30, 19)
          ..lineTo(29, 20)
          ..lineTo(29, 23)
          ..lineTo(30, 24)
          ..lineTo(30, 26)
          ..lineTo(33, 26)
          ..lineTo(33, 24)
          ..lineTo(34, 23)
          ..lineTo(34, 20)
          ..close()),
        CatalogVehiclePalette.combat,
        [],
      ),
    ],
  ),
};
