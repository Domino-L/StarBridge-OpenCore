import '../../../design_system/styles/catalog_vehicle_palette.dart';
import 'dart:ui';
import '../catalog_vehicle_glyph.dart';

// Generated solely from the 19 ground/MPUV final SVGs in the V1 icon index.
// See catalog_ground_vehicle_icon_sources.json for exact sources and hashes.
// White body = theme foreground (null); source accents and fill rules preserved.
final Map<String, CatalogVehicleGlyph> entries = {
  'ground-transport-flatbed': CatalogVehicleGlyph(
    const Rect.fromLTWH(0, 0, 40, 40),
    [
      CatalogVehicleLayer(
        (Path()
          ..fillType = PathFillType.evenOdd
          ..moveTo(15, 3)
          ..lineTo(25, 3)
          ..lineTo(29, 7)
          ..lineTo(29, 13)
          ..lineTo(11, 13)
          ..lineTo(11, 7)
          ..close()
          ..moveTo(15, 6)
          ..lineTo(25, 6)
          ..lineTo(25, 10)
          ..lineTo(15, 10)
          ..close()),
        null,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(11, 15)
          ..lineTo(14, 15)
          ..lineTo(14, 35)
          ..lineTo(26, 35)
          ..lineTo(26, 15)
          ..lineTo(29, 15)
          ..lineTo(29, 36)
          ..lineTo(27, 38)
          ..lineTo(13, 38)
          ..lineTo(11, 36)
          ..close()),
        null,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(5, 8)
          ..lineTo(8, 8)
          ..lineTo(9, 9)
          ..lineTo(9, 15)
          ..lineTo(8, 16)
          ..lineTo(5, 16)
          ..lineTo(4, 15)
          ..lineTo(4, 9)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(32, 8)
          ..lineTo(35, 8)
          ..lineTo(36, 9)
          ..lineTo(36, 15)
          ..lineTo(35, 16)
          ..lineTo(32, 16)
          ..lineTo(31, 15)
          ..lineTo(31, 9)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(5, 28)
          ..lineTo(8, 28)
          ..lineTo(9, 29)
          ..lineTo(9, 35)
          ..lineTo(8, 36)
          ..lineTo(5, 36)
          ..lineTo(4, 35)
          ..lineTo(4, 29)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(32, 28)
          ..lineTo(35, 28)
          ..lineTo(36, 29)
          ..lineTo(36, 35)
          ..lineTo(35, 36)
          ..lineTo(32, 36)
          ..lineTo(31, 35)
          ..lineTo(31, 29)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(17, 17)
          ..lineTo(19, 17)
          ..lineTo(19, 19)
          ..lineTo(21, 19)
          ..lineTo(21, 17)
          ..lineTo(23, 17)
          ..lineTo(24, 18)
          ..lineTo(24, 23)
          ..lineTo(16, 23)
          ..lineTo(16, 18)
          ..close()),
        CatalogVehiclePalette.groundTransport,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(17, 25)
          ..lineTo(19, 25)
          ..lineTo(19, 27)
          ..lineTo(21, 27)
          ..lineTo(21, 25)
          ..lineTo(23, 25)
          ..lineTo(24, 26)
          ..lineTo(24, 33)
          ..lineTo(16, 33)
          ..lineTo(16, 26)
          ..close()),
        CatalogVehiclePalette.groundTransport,
        [],
      ),
    ],
  ),
};
