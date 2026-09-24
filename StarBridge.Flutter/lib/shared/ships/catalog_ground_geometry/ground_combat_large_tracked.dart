import '../../../design_system/styles/catalog_vehicle_palette.dart';
import 'dart:ui';
import '../catalog_vehicle_glyph.dart';

// Generated solely from the 19 ground/MPUV final SVGs in the V1 icon index.
// See catalog_ground_vehicle_icon_sources.json for exact sources and hashes.
// White body = theme foreground (null); source accents and fill rules preserved.
final Map<String, CatalogVehicleGlyph> entries = {
  'ground-combat-large-tracked': CatalogVehicleGlyph(
    const Rect.fromLTWH(-4, -5, 40, 40),
    [
      CatalogVehicleLayer(
        (Path()
          ..moveTo(10, 3)
          ..lineTo(12.5, 3)
          ..lineTo(12.5, 10)
          ..lineTo(9.5, 14)
          ..lineTo(9.5, 22)
          ..lineTo(13, 26)
          ..lineTo(19, 26)
          ..lineTo(22.5, 22)
          ..lineTo(22.5, 14)
          ..lineTo(19.5, 10)
          ..lineTo(19.5, 3)
          ..lineTo(22, 3)
          ..lineTo(24, 7)
          ..lineTo(24, 27)
          ..lineTo(20, 32)
          ..lineTo(12, 32)
          ..lineTo(8, 27)
          ..lineTo(8, 7)
          ..close()),
        null,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(3, 1)
          ..lineTo(6, 1)
          ..lineTo(6, 30)
          ..lineTo(4, 33)
          ..lineTo(2, 33)
          ..lineTo(0, 30)
          ..lineTo(0, 25)
          ..lineTo(4, 25)
          ..lineTo(4, 23)
          ..lineTo(0, 23)
          ..lineTo(0, 12)
          ..lineTo(4, 12)
          ..lineTo(4, 10)
          ..lineTo(0, 10)
          ..lineTo(0, 5)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(26, 1)
          ..lineTo(29, 1)
          ..lineTo(32, 5)
          ..lineTo(32, 10)
          ..lineTo(28, 10)
          ..lineTo(28, 12)
          ..lineTo(32, 12)
          ..lineTo(32, 23)
          ..lineTo(28, 23)
          ..lineTo(28, 25)
          ..lineTo(32, 25)
          ..lineTo(32, 30)
          ..lineTo(30, 33)
          ..lineTo(28, 33)
          ..lineTo(26, 30)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(14.2, -4)
          ..lineTo(17.8, -4)
          ..lineTo(18.5, -2.5)
          ..lineTo(18.5, 1)
          ..lineTo(17.5, 2)
          ..lineTo(17.5, 13)
          ..lineTo(14.5, 13)
          ..lineTo(14.5, 2)
          ..lineTo(13.5, 1)
          ..lineTo(13.5, -2.5)
          ..close()),
        CatalogVehiclePalette.combat,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(13.5, 13)
          ..lineTo(18.5, 13)
          ..lineTo(20.5, 16)
          ..lineTo(20.5, 20.5)
          ..lineTo(18, 23)
          ..lineTo(14, 23)
          ..lineTo(11.5, 20.5)
          ..lineTo(11.5, 16)
          ..close()),
        CatalogVehiclePalette.combat,
        [],
      ),
    ],
  ),
};
